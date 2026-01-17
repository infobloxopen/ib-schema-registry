#!/usr/bin/env bash
# Cleanup k3d cluster after E2E tests
set -euo pipefail

CLUSTER_NAME="schema-registry-test"

echo "→ Tearing down k3d cluster..."

# Check if cluster exists
if ! k3d cluster list | grep -q "$CLUSTER_NAME"; then
  echo "ℹ️  Cluster '$CLUSTER_NAME' does not exist, nothing to cleanup"
  exit 0
fi

# Delete cluster
echo "→ Deleting k3d cluster: $CLUSTER_NAME"
k3d cluster delete "$CLUSTER_NAME"

echo "✅ Cleanup complete!"
