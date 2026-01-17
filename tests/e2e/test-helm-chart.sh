#!/usr/bin/env bash
# Main E2E test orchestrator for Schema Registry Helm chart
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/helm/ib-schema-registry"
NAMESPACE="default"
RELEASE_NAME="schema-registry"

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Schema Registry Helm Chart E2E Tests                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Cleanup function
cleanup() {
  local exit_code=$?
  echo ""
  echo "→ Cleaning up..."
  
  # Uninstall Helm release
  if helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
    echo "  - Uninstalling Helm release: $RELEASE_NAME"
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait || true
  fi
  
  # Teardown cluster
  if [ -f "$SCRIPT_DIR/teardown.sh" ]; then
    bash "$SCRIPT_DIR/teardown.sh"
  fi
  
  if [ $exit_code -eq 0 ]; then
    echo ""
    echo "✅ E2E tests completed successfully!"
  else
    echo ""
    echo "❌ E2E tests failed!"
  fi
  
  exit $exit_code
}

trap cleanup EXIT

# Step 1: Setup k3d cluster
echo "Step 1/5: Setting up k3d cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/setup-k3d-cluster.sh"

# Step 2: Deploy Redpanda
echo ""
echo "Step 2/5: Deploying Redpanda (Kafka backend)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! bash "$SCRIPT_DIR/deploy-redpanda.sh"; then
  echo "❌ Redpanda deployment failed!"
  echo "Collecting diagnostics..."
  kubectl get pods -n default -l app=redpanda
  kubectl describe pod -n default -l app=redpanda
  kubectl logs -n default -l app=redpanda --tail=100 || true
  exit 1
fi

# Step 3: Install Helm chart
echo ""
echo "Step 3/5: Installing Schema Registry Helm chart"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "→ Installing chart from: $CHART_DIR"

helm install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set config.kafkaBootstrapServers="redpanda.$NAMESPACE.svc.cluster.local:9092" \
  --set replicaCount=1 \
  --wait \
  --timeout 5m

echo ""
echo "✅ Helm chart installed successfully!"
kubectl get pods,svc -n "$NAMESPACE" -l app.kubernetes.io/name=ib-schema-registry

# Step 4: Run Helm tests
echo ""
echo "Step 4/5: Running Helm tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
helm test "$RELEASE_NAME" -n "$NAMESPACE" --logs

# Step 5: Validate Schema Registry API
echo ""
echo "Step 5/5: Validating Schema Registry API"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
export RELEASE_NAME
export NAMESPACE
bash "$SCRIPT_DIR/validate-schema-registry.sh"

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  ✅ All E2E Tests Passed!                             ║"
echo "╚════════════════════════════════════════════════════════╝"
