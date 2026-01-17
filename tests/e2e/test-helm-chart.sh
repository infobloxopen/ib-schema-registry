#!/usr/bin/env bash
# Main E2E test orchestrator for Schema Registry Helm chart
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)/helm/ib-schema-registry"
NAMESPACE="default"
RELEASE_NAME="test-sr"
SKIP_TEARDOWN="${SKIP_TEARDOWN:-false}"

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Schema Registry Helm Chart E2E Tests                 ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Cleanup function
cleanup() {
  local exit_code=$?
  echo ""
  
  if [ "$SKIP_TEARDOWN" = "true" ]; then
    echo "⚠️  SKIP_TEARDOWN=true - Leaving cluster running for debugging"
    echo ""
    echo "Cluster: schema-registry-test"
    echo "Release: $RELEASE_NAME"
    echo "Namespace: $NAMESPACE"
    echo ""
    echo "Useful commands:"
    echo "  kubectl get pods -n $NAMESPACE"
    echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=ib-schema-registry"
    echo "  helm test $RELEASE_NAME -n $NAMESPACE --logs"
    echo "  kubectl describe pod -n $NAMESPACE -l app.kubernetes.io/name=ib-schema-registry"
    echo ""
    echo "To teardown manually:"
    echo "  bash $SCRIPT_DIR/teardown.sh"
    exit $exit_code
  fi
  
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
echo "Step 1/6: Setting up k3d cluster"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
bash "$SCRIPT_DIR/setup-k3d-cluster.sh"

# Step 2: Build and load Docker image
echo ""
echo "Step 2/6: Building and loading Docker image"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IMAGE_NAME="ib-schema-registry"
IMAGE_TAG="test"

echo "→ Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
cd "$REPO_ROOT"
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" . || {
  echo "❌ Failed to build Docker image"
  exit 1
}

echo "→ Loading image into k3d cluster..."
k3d image import "${IMAGE_NAME}:${IMAGE_TAG}" -c schema-registry-test || {
  echo "❌ Failed to load image into k3d"
  exit 1
}

echo "✅ Image built and loaded into k3d cluster"

# Step 3: Deploy Redpanda
echo ""
echo "Step 3/6: Deploying Redpanda (Kafka backend)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if ! bash "$SCRIPT_DIR/deploy-redpanda.sh"; then
  echo "❌ Redpanda deployment failed!"
  echo "Collecting diagnostics..."
  kubectl get pods -n default -l app=redpanda
  kubectl describe pod -n default -l app=redpanda
  kubectl logs -n default -l app=redpanda --tail=100 || true
  exit 1
fi

# Step 4: Install Helm chart
echo ""
echo "Step 4/6: Installing Schema Registry Helm chart"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "→ Installing chart from: $CHART_DIR"

helm install "$RELEASE_NAME" "$CHART_DIR" \
  --namespace "$NAMESPACE" \
  --set config.kafkaBootstrapServers="redpanda.$NAMESPACE.svc.cluster.local:9092" \
  --set replicaCount=1 \
  --set image.repository="${IMAGE_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set image.pullPolicy=Never \
  --wait \
  --timeout 5m

echo ""
echo "✅ Helm chart installed successfully!"
kubectl get pods,svc -n "$NAMESPACE" -l app.kubernetes.io/name=ib-schema-registry

# Step 5: Run Helm tests
echo ""
echo "Step 5/6: Running Helm tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "→ Checking for test pods..."
echo "Expected test pod name: ${RELEASE_NAME}-ib-schema-registry-test"
kubectl get pods -n "$NAMESPACE" --show-labels | grep -E "NAME|helm.sh/hook=test" || echo "  No test pods found yet"

echo ""
echo "→ Running helm test..."
if ! helm test "$RELEASE_NAME" -n "$NAMESPACE"; then
  echo ""
  echo "❌ Helm test failed! Collecting diagnostics..."
  echo ""
  echo "=== All pods in namespace ==="
  kubectl get pods -n "$NAMESPACE" -o wide
  echo ""
  echo "=== Test pods (if any) ==="
  kubectl get pods -n "$NAMESPACE" -l "helm.sh/hook=test" -o wide || echo "No test pods found"
  echo ""
  echo "=== Test pod logs (if available) ==="
  kubectl logs -n "$NAMESPACE" -l "helm.sh/hook=test" --all-containers=true || echo "No logs available"
  echo ""
  echo "=== Test pod description ==="
  kubectl describe pod -n "$NAMESPACE" -l "helm.sh/hook=test" || echo "No test pods to describe"
  exit 1
fi

# Step 6: Validate Schema Registry API
echo ""
echo "Step 6/6: Validating Schema Registry API"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
export RELEASE_NAME
export NAMESPACE
bash "$SCRIPT_DIR/validate-schema-registry.sh"

echo ""
echo "╔════════════════════════════════════════════════════════╗"
echo "║  ✅ All E2E Tests Passed!                             ║"
echo "╚════════════════════════════════════════════════════════╝"
