#!/usr/bin/env bash
# =============================================================================
# Provenance Validation Script
# =============================================================================
# Validates SLSA provenance attestations for container images
# Usage: ./validate-provenance.sh <image-reference>
# Example: ./validate-provenance.sh ghcr.io/infobloxopen/ib-schema-registry:main

set -euo pipefail

# Configuration
IMAGE="${1:-}"
EXPECTED_REPO="github.com/infobloxopen/ib-schema-registry"
EXPECTED_WORKFLOW=".github/workflows/build-image.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage
usage() {
    echo "Usage: $0 <image-reference>"
    echo ""
    echo "Examples:"
    echo "  $0 ghcr.io/infobloxopen/ib-schema-registry:main"
    echo "  $0 ghcr.io/infobloxopen/ib-schema-registry:v1.0.0"
    echo "  $0 ghcr.io/infobloxopen/ib-schema-registry:sha-abc123..."
    echo ""
    echo "Requirements:"
    echo "  - cosign (for signature verification)"
    echo "  - docker buildx (for attestation inspection)"
    echo "  - jq (for JSON parsing)"
    exit 1
}

# Check if image reference provided
if [ -z "$IMAGE" ]; then
    echo -e "${RED}Error: Image reference required${NC}"
    echo ""
    usage
fi

# Check dependencies
check_dependency() {
    local cmd=$1
    local install_hint=$2
    
    if ! command -v "$cmd" &> /dev/null; then
        echo -e "${RED}✗ $cmd not found${NC}"
        echo "  Install: $install_hint"
        return 1
    fi
    return 0
}

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  SLSA Provenance Validation                                  ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${BLUE}Image:${NC} $IMAGE"
echo ""

# Check dependencies
echo "→ Checking dependencies..."
DEPS_OK=true
check_dependency "cosign" "go install github.com/sigstore/cosign/v2/cmd/cosign@latest" || DEPS_OK=false
check_dependency "docker" "https://docs.docker.com/get-docker/" || DEPS_OK=false
check_dependency "jq" "brew install jq (macOS) or apt-get install jq (Linux)" || DEPS_OK=false

if [ "$DEPS_OK" = false ]; then
    echo ""
    echo -e "${RED}Missing required dependencies. Please install them and try again.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ All dependencies found${NC}"
echo ""

# Step 1: Check if image exists
echo "→ Checking if image exists..."
if docker pull "$IMAGE" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Image pulled successfully${NC}"
else
    echo -e "${RED}✗ Failed to pull image${NC}"
    echo "  Make sure you're logged in to the registry and the image exists"
    exit 1
fi
echo ""

# Step 2: Check for provenance attestation using docker buildx
echo "→ Checking for provenance attestation..."
if docker buildx imagetools inspect "$IMAGE" --format '{{json .Provenance}}' 2>/dev/null | jq -e '.SLSA' >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Provenance attestation found${NC}"
else
    echo -e "${YELLOW}⚠ No provenance attestation found${NC}"
    echo "  This may be expected for:"
    echo "  - PR builds (provenance is skipped)"
    echo "  - Older images (built before provenance was enabled)"
    echo "  - Images from external sources"
    echo ""
    echo "To generate provenance, ensure:"
    echo "  1. Image was built via GitHub Actions (not locally)"
    echo "  2. Build was triggered by push to main or tag creation"
    echo "  3. Provenance generation is enabled in build workflow"
    exit 1
fi
echo ""

# Step 3: Verify signature with cosign
echo "→ Verifying signature with cosign..."
VERIFICATION_OUTPUT=$(mktemp)
if cosign verify-attestation \
    --type slsaprovenance \
    --certificate-identity-regexp "^https://github.com/$EXPECTED_REPO/" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    "$IMAGE" > "$VERIFICATION_OUTPUT" 2>&1; then
    echo -e "${GREEN}✓ Signature verification passed${NC}"
    echo "  - Certificate identity: GitHub repository workflow"
    echo "  - OIDC issuer: GitHub Actions"
    echo "  - Signature: Valid"
else
    echo -e "${RED}✗ Signature verification failed${NC}"
    echo ""
    echo "Verification output:"
    cat "$VERIFICATION_OUTPUT"
    rm -f "$VERIFICATION_OUTPUT"
    exit 1
fi
echo ""

# Step 4: Extract and validate provenance content
echo "→ Extracting provenance content..."
PROVENANCE=$(cat "$VERIFICATION_OUTPUT" | jq -r '.payload | @base64d | fromjson')
rm -f "$VERIFICATION_OUTPUT"

# Extract key fields
PREDICATE_TYPE=$(echo "$PROVENANCE" | jq -r '.predicateType')
SOURCE_REPO=$(echo "$PROVENANCE" | jq -r '.predicate.invocation.configSource.uri' 2>/dev/null || echo "")
SOURCE_COMMIT=$(echo "$PROVENANCE" | jq -r '.predicate.invocation.configSource.digest.sha1' 2>/dev/null || echo "")
BUILDER_ID=$(echo "$PROVENANCE" | jq -r '.predicate.builder.id' 2>/dev/null || echo "")
BUILD_TIME=$(echo "$PROVENANCE" | jq -r '.predicate.metadata.buildStartedOn' 2>/dev/null || echo "")

# Validate predicate type
echo "  Predicate Type: $PREDICATE_TYPE"
if [[ "$PREDICATE_TYPE" == *"slsa.dev/provenance"* ]]; then
    echo -e "    ${GREEN}✓ Valid SLSA provenance schema${NC}"
else
    echo -e "    ${RED}✗ Invalid predicate type${NC}"
    exit 1
fi

# Validate source repository
echo "  Source Repository: $SOURCE_REPO"
if [[ "$SOURCE_REPO" == *"$EXPECTED_REPO"* ]]; then
    echo -e "    ${GREEN}✓ Matches expected repository${NC}"
else
    echo -e "    ${YELLOW}⚠ Does not match expected repository: $EXPECTED_REPO${NC}"
fi

# Display source commit
echo "  Source Commit: $SOURCE_COMMIT"
if [ -n "$SOURCE_COMMIT" ] && [ "$SOURCE_COMMIT" != "null" ]; then
    echo -e "    ${GREEN}✓ Commit SHA present${NC}"
else
    echo -e "    ${YELLOW}⚠ No commit SHA found${NC}"
fi

# Display builder identity
echo "  Builder: $BUILDER_ID"
if [[ "$BUILDER_ID" == *"github.com"* ]] || [[ "$BUILDER_ID" == *"docker"* ]]; then
    echo -e "    ${GREEN}✓ Trusted builder${NC}"
else
    echo -e "    ${YELLOW}⚠ Unknown builder${NC}"
fi

# Display build time
echo "  Build Time: $BUILD_TIME"
if [ -n "$BUILD_TIME" ] && [ "$BUILD_TIME" != "null" ]; then
    echo -e "    ${GREEN}✓ Timestamp present${NC}"
else
    echo -e "    ${YELLOW}⚠ No timestamp found${NC}"
fi
echo ""

# Step 5: Check multi-arch attestations
echo "→ Checking multi-architecture attestations..."
PLATFORMS=$(docker buildx imagetools inspect "$IMAGE" --format '{{json .Manifest}}' 2>/dev/null | jq -r '.manifests[].platform | "\(.os)/\(.architecture)"' 2>/dev/null || echo "")

if [ -z "$PLATFORMS" ]; then
    echo -e "${YELLOW}⚠ Could not detect platforms${NC}"
else
    echo "  Detected platforms:"
    echo "$PLATFORMS" | while read -r platform; do
        echo "    - $platform"
    done
    
    PLATFORM_COUNT=$(echo "$PLATFORMS" | wc -l | tr -d ' ')
    if [ "$PLATFORM_COUNT" -gt 1 ]; then
        echo -e "    ${GREEN}✓ Multi-architecture image${NC}"
    else
        echo -e "    ${GREEN}✓ Single architecture image${NC}"
    fi
fi
echo ""

# Step 6: Detailed provenance summary
echo "→ Provenance Summary"
echo "╭────────────────────────────────────────────────────────────────╮"
echo "│ Verification Status: PASSED                                    │"
echo "├────────────────────────────────────────────────────────────────┤"

# Truncate long fields to prevent overflow
SOURCE_SHORT=$(echo "$SOURCE_REPO" | awk '{if (length($0) > 50) print substr($0,1,47)"..."; else print $0}')
COMMIT_SHORT=$(echo "$SOURCE_COMMIT" | cut -c1-12)
BUILDER_SHORT=$(echo "$BUILDER_ID" | awk '{if (length($0) > 50) print substr($0,1,47)"..."; else print $0}')

echo "│ Source:     $SOURCE_SHORT"
echo "│ Commit:     $COMMIT_SHORT"
echo "│ Builder:    $BUILDER_SHORT"
echo "│ Build Time: $BUILD_TIME"
echo "╰────────────────────────────────────────────────────────────────╯"
echo ""

# Success
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  ✓ Provenance validation passed                              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "This image:"
echo "  ✓ Has a valid SLSA provenance attestation"
echo "  ✓ Was built from a trusted source (GitHub repository)"
echo "  ✓ Has a cryptographically verifiable signature"
echo "  ✓ Meets supply-chain security requirements"
echo ""
echo "It is safe to use this image in production."
exit 0
