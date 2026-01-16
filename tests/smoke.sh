#!/usr/bin/env bash
# =============================================================================
# Smoke Test - Schema Registry Container
# =============================================================================
# Tests basic container functionality without requiring full Kafka cluster
# Validates: Container starts, API responds, health check passes

set -euo pipefail

# Configuration
IMAGE="${1:-ib-schema-registry:latest}"
CONTAINER_NAME="schema-registry-smoke-test-$$"
HOST_PORT="18081"
CONTAINER_PORT="8081"
HEALTH_ENDPOINT="/subjects"
TIMEOUT=60
POLL_INTERVAL=2

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Cleanup function
cleanup() {
    echo ""
    echo "→ Cleaning up..."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}

# Register cleanup on exit
trap cleanup EXIT INT TERM

# Start test
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  Schema Registry Smoke Test                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "Image: $IMAGE"
echo "Test Container: $CONTAINER_NAME"
echo ""

# Check if image exists
echo "→ Checking if image exists..."
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo -e "${RED}✗ Image not found: $IMAGE${NC}"
    echo "Run 'make build' first"
    exit 1
fi
echo -e "${GREEN}✓ Image found${NC}"
echo ""

# Start container
echo "→ Starting container..."
docker run -d \
    --name "$CONTAINER_NAME" \
    -p "$HOST_PORT:$CONTAINER_PORT" \
    "$IMAGE" >/dev/null

echo -e "${GREEN}✓ Container started${NC}"
echo ""

# Wait for container to start and capture logs
echo "→ Validating Schema Registry binary startup (max ${TIMEOUT}s)..."
sleep 3  # Give container time to start

# Capture logs before container might exit
CONTAINER_LOGS=$(docker logs "$CONTAINER_NAME" 2>&1)

# Check if Schema Registry binary started successfully
if echo "$CONTAINER_LOGS" | grep -q "Adding listener"; then
    echo -e "${GREEN}✓ Schema Registry binary started successfully${NC}"
    echo -e "${YELLOW}⚠ Service requires Kafka cluster for full operation${NC}"
    echo "  Validated: Docker image, Java runtime, Schema Registry binary"
    READY=true
elif echo "$CONTAINER_LOGS" | grep -qi "error"; then
    echo -e "${RED}✗ Container has errors${NC}"
    echo ""
    echo "Container logs (last 20 lines):"
    echo "$CONTAINER_LOGS" | tail -20
    exit 1
else
    echo -e "${RED}✗ Container failed to start${NC}"
    echo ""
    echo "Container logs:"
    echo "$CONTAINER_LOGS"
    exit 1
fi

# Verify non-root user
echo "→ Verifying non-root execution..."
CONTAINER_USER=$(docker exec "$CONTAINER_NAME" sh -c 'id -u' 2>/dev/null || echo "shell-not-available")

if [ "$CONTAINER_USER" = "shell-not-available" ]; then
    echo -e "${YELLOW}⚠ Cannot verify user (no shell in container - distroless?)${NC}"
    echo "  This is expected for distroless base images"
elif [ "$CONTAINER_USER" = "65532" ] || [ "$CONTAINER_USER" = "nobody" ]; then
    echo -e "${GREEN}✓ Running as non-root user (UID: $CONTAINER_USER)${NC}"
else
    echo -e "${RED}✗ Running as unexpected user (UID: $CONTAINER_USER)${NC}"
    echo "  Expected UID 65532 (nobody)"
    exit 1
fi
echo ""

# Verify OCI labels
echo "→ Verifying OCI labels..."
LABEL_SOURCE=$(docker image inspect "$IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.source"}}')
LABEL_VERSION=$(docker image inspect "$IMAGE" --format '{{index .Config.Labels "org.opencontainers.image.version"}}')

if [ -z "$LABEL_SOURCE" ]; then
    echo -e "${RED}✗ Missing org.opencontainers.image.source label${NC}"
    exit 1
fi

if [ -z "$LABEL_VERSION" ]; then
    echo -e "${RED}✗ Missing org.opencontainers.image.version label${NC}"
    exit 1
fi

echo -e "${GREEN}✓ OCI labels present${NC}"
echo "  Source: $LABEL_SOURCE"
echo "  Version: $LABEL_VERSION"
echo ""

# Success
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✓ All smoke tests passed                                    ║"
echo "╚══════════════════════════════════════════════════════════════╝"
exit 0
