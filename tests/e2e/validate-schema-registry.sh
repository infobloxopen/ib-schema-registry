#!/usr/bin/env bash
# Validate Schema Registry API functionality
set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-schema-registry}"
SERVICE_NAME="${RELEASE_NAME}-ib-schema-registry"

echo "→ Validating Schema Registry API..."

# Wait for Schema Registry to be ready
echo "→ Waiting for Schema Registry pods to be ready..."
kubectl wait --for=condition=Ready pod -l app.kubernetes.io/name=ib-schema-registry -n "$NAMESPACE" --timeout=120s

# Port-forward to Schema Registry (run in background)
echo "→ Setting up port-forward..."
kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" 8081:8081 &
PF_PID=$!
sleep 5  # Give port-forward time to establish

# Cleanup port-forward on exit
cleanup() {
  echo "→ Cleaning up port-forward..."
  kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

SR_URL="http://localhost:8081"

echo ""
echo "======================================"
echo "  Schema Registry API Tests"
echo "======================================"
echo ""

# Test 1: Root endpoint
echo "Test 1: GET / (root endpoint)"
if curl -f -s "$SR_URL/" > /dev/null; then
  echo "  ✅ PASS - Root endpoint responding"
else
  echo "  ❌ FAIL - Root endpoint not responding"
  exit 1
fi

# Test 2: List subjects (should be empty initially)
echo ""
echo "Test 2: GET /subjects (list subjects)"
SUBJECTS=$(curl -f -s "$SR_URL/subjects")
if [[ "$SUBJECTS" == "[]" ]] || [[ "$SUBJECTS" =~ ^\[.*\]$ ]]; then
  echo "  ✅ PASS - Subjects endpoint responding: $SUBJECTS"
else
  echo "  ❌ FAIL - Subjects endpoint returned unexpected response: $SUBJECTS"
  exit 1
fi

# Test 3: Get config
echo ""
echo "Test 3: GET /config (global compatibility config)"
CONFIG=$(curl -f -s "$SR_URL/config")
if echo "$CONFIG" | grep -q "compatibilityLevel"; then
  echo "  ✅ PASS - Config endpoint responding: $CONFIG"
else
  echo "  ❌ FAIL - Config endpoint returned unexpected response: $CONFIG"
  exit 1
fi

# Test 4: Register a test schema
echo ""
echo "Test 4: POST /subjects/test-subject/versions (register schema)"
SCHEMA='{"schema":"{\"type\":\"record\",\"name\":\"Test\",\"fields\":[{\"name\":\"id\",\"type\":\"int\"}]}"}'
REGISTER_RESPONSE=$(curl -f -s -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data "$SCHEMA" \
  "$SR_URL/subjects/test-subject/versions")

if echo "$REGISTER_RESPONSE" | grep -q "\"id\""; then
  SCHEMA_ID=$(echo "$REGISTER_RESPONSE" | grep -o '"id":[0-9]*' | cut -d: -f2)
  echo "  ✅ PASS - Schema registered with ID: $SCHEMA_ID"
else
  echo "  ❌ FAIL - Schema registration failed: $REGISTER_RESPONSE"
  exit 1
fi

# Test 5: Retrieve the registered schema
echo ""
echo "Test 5: GET /subjects/test-subject/versions/latest (retrieve schema)"
RETRIEVE_RESPONSE=$(curl -f -s "$SR_URL/subjects/test-subject/versions/latest")
if echo "$RETRIEVE_RESPONSE" | grep -q "\"subject\":\"test-subject\""; then
  echo "  ✅ PASS - Schema retrieved successfully"
else
  echo "  ❌ FAIL - Schema retrieval failed: $RETRIEVE_RESPONSE"
  exit 1
fi

# Test 6: List subjects again (should include test-subject)
echo ""
echo "Test 6: GET /subjects (verify test-subject exists)"
SUBJECTS_AFTER=$(curl -f -s "$SR_URL/subjects")
if echo "$SUBJECTS_AFTER" | grep -q "test-subject"; then
  echo "  ✅ PASS - test-subject found in subjects list: $SUBJECTS_AFTER"
else
  echo "  ❌ FAIL - test-subject not found in subjects list: $SUBJECTS_AFTER"
  exit 1
fi

# Test 7: Get schema by ID
echo ""
echo "Test 7: GET /schemas/ids/$SCHEMA_ID (get schema by ID)"
SCHEMA_BY_ID=$(curl -f -s "$SR_URL/schemas/ids/$SCHEMA_ID")
if echo "$SCHEMA_BY_ID" | grep -q "\"schema\""; then
  echo "  ✅ PASS - Schema retrieved by ID successfully"
else
  echo "  ❌ FAIL - Schema retrieval by ID failed: $SCHEMA_BY_ID"
  exit 1
fi

echo ""
echo "======================================"
echo "  ✅ All API tests passed!"
echo "======================================"
echo ""
echo "Summary:"
echo "  - Root endpoint: OK"
echo "  - List subjects: OK"
echo "  - Get config: OK"
echo "  - Register schema: OK (ID: $SCHEMA_ID)"
echo "  - Retrieve schema: OK"
echo "  - List subjects after registration: OK"
echo "  - Get schema by ID: OK"
echo ""
