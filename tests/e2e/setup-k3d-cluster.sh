#!/usr/bin/env bash
# Setup k3d cluster for Schema Registry Helm chart testing
set -euo pipefail

CLUSTER_NAME="schema-registry-test"
K3D_VERSION="v5.6.0"

echo "→ Setting up k3d cluster for E2E testing..."

# Check prerequisites
command -v k3d >/dev/null 2>&1 || {
  echo "❌ k3d not found. Install with: brew install k3d (macOS) or see https://k3d.io/#installation"
  exit 1
}

command -v kubectl >/dev/null 2>&1 || {
  echo "❌ kubectl not found. Install with: brew install kubectl"
  exit 1
}

# Check if cluster already exists
if k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "⚠️  Cluster '$CLUSTER_NAME' already exists. Deleting..."
  k3d cluster delete "$CLUSTER_NAME"
fi

# Create k3d cluster with 2 agent nodes for realistic multi-node testing
echo "→ Creating k3d cluster: $CLUSTER_NAME (1 server + 2 agents)"
k3d cluster create "$CLUSTER_NAME" \
  --agents 2 \
  --wait \
  --timeout 300s

# Verify cluster is ready
echo "→ Waiting for cluster to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Display cluster info
echo ""
echo "✅ k3d cluster ready!"
echo ""
kubectl cluster-info
echo ""
kubectl get nodes -o wide
echo ""
echo "📋 Cluster: $CLUSTER_NAME"
echo "   Nodes: $(kubectl get nodes --no-headers | wc -l)"
echo "   Kubeconfig: $(k3d kubeconfig get $CLUSTER_NAME)"
echo ""
echo "Next steps:"
echo "  1. Deploy Redpanda: bash tests/e2e/deploy-redpanda.sh"
echo "  2. Install chart: helm install schema-registry chart/"
echo "  3. Run tests: bash tests/e2e/validate-schema-registry.sh"
echo ""
