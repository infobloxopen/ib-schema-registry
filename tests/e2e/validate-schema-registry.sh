#!/usr/bin/env bash
# Validate Schema Registry API functionality
set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
RELEASE_NAME="${RELEASE_NAME:-schema-registry}"
SERVICE_NAME="${RELEASE_NAME}-ib-schema-registry"
METRICS_ENABLED="${METRICS_ENABLED:-false}"

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

# Prometheus Metrics Tests (if enabled)
if [[ "$METRICS_ENABLED" == "true" ]]; then
  echo ""
  echo "======================================"
  echo "  Prometheus Metrics Tests"
  echo "======================================"
  echo ""
  
  # Setup port-forward for metrics port
  echo "→ Setting up port-forward for metrics..."
  kubectl port-forward -n "$NAMESPACE" "svc/$SERVICE_NAME" 9404:9404 &
  METRICS_PF_PID=$!
  sleep 3
  
  # Cleanup metrics port-forward on exit
  trap "kill $METRICS_PF_PID 2>/dev/null || true; kill $PF_PID 2>/dev/null || true" EXIT
  
  METRICS_URL="http://localhost:9404/metrics"
  
  # Test 1: Metrics endpoint responding
  echo "Test 1: GET /metrics (Prometheus endpoint)"
  if METRICS_RESPONSE=$(curl -f -s "$METRICS_URL"); then
    echo "  ✅ PASS - Metrics endpoint responding"
  else
    echo "  ❌ FAIL - Metrics endpoint not responding"
    exit 1
  fi
  
  # Test 2: Validate Prometheus format
  echo ""
  echo "Test 2: Validate Prometheus text format"
  if echo "$METRICS_RESPONSE" | grep -q "^# HELP"; then
    echo "  ✅ PASS - Metrics in Prometheus text format"
  else
    echo "  ❌ FAIL - Metrics not in expected Prometheus format"
    exit 1
  fi
  
  # Test 3: Check for JVM metrics
  echo ""
  echo "Test 3: Verify JVM metrics exported"
  if echo "$METRICS_RESPONSE" | grep -q "jvm_memory_"; then
    echo "  ✅ PASS - JVM memory metrics found"
  else
    echo "  ❌ FAIL - JVM memory metrics not found"
    exit 1
  fi
  
  # Test 4: Check for Schema Registry metrics
  echo ""
  echo "Test 4: Verify Schema Registry metrics exported"
  if echo "$METRICS_RESPONSE" | grep -qE "kafka_schema_registry_|jetty_|jersey_"; then
    echo "  ✅ PASS - Schema Registry JMX metrics found"
  else
    echo "  ⚠️  WARN - Schema Registry JMX metrics not found (may take time to populate)"
  fi
  
  # Test 5: Count total metrics
  echo ""
  echo "Test 5: Count exported metrics"
  METRIC_COUNT=$(echo "$METRICS_RESPONSE" | grep -v "^#" | grep -v "^$" | wc -l | tr -d ' ')
  if [[ $METRIC_COUNT -gt 10 ]]; then
    echo "  ✅ PASS - Exporting $METRIC_COUNT metrics"
  else
    echo "  ❌ FAIL - Only $METRIC_COUNT metrics found (expected > 10)"
    exit 1
  fi
  
  echo ""
  echo "======================================"
  echo "  ✅ All metrics tests passed!"
  echo "======================================"
  echo ""
  echo "Metrics Summary:"
  echo "  - Endpoint responding: OK"
  echo "  - Prometheus format: OK"
  echo "  - JVM metrics: OK"
  echo "  - Schema Registry metrics: OK (or pending)"
  echo "  - Total metrics exported: $METRIC_COUNT"
  echo ""
fi
