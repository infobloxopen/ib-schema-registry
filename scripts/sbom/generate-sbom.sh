#!/usr/bin/env bash
# =============================================================================
# SBOM Generation Script with Idempotent Caching
# =============================================================================
# Generates Software Bill of Materials (SBOM) for container images
# Supports: CycloneDX and SPDX formats
# Tool: Syft (https://github.com/anchore/syft)
#
# Features (Feature 004):
#   - Idempotent operation: Re-running for same digest succeeds without conflicts
#   - Hash-based verification: Detects when SBOM content is identical
#   - Operation tracking: GENERATED, VERIFIED_IDENTICAL, or UPDATED status
#   - Metadata persistence: Digest and hash stored for audit trail
#
# Usage:
#   ./generate-sbom.sh <image:tag> <format> <output-file> [platform]
#
# Arguments:
#   image:tag    - Docker image to scan (e.g., ib-schema-registry:latest)
#   format       - SBOM format: cyclonedx-json, spdx-json
#   output-file  - Path to save SBOM (e.g., build/sbom/latest.cyclonedx.json)
#   platform     - Optional: linux/amd64 or linux/arm64 (defaults to native)
#
# Requirements:
#   - Syft v1.0.0+ installed (https://github.com/anchore/syft)
#   - Docker or containerd runtime
#   - jq for JSON processing
#
# Constitution: Aligns with multi-arch portability and supply-chain security
# =============================================================================

set -euo pipefail

# Auto-detect Docker socket if DOCKER_HOST not set
if [ -z "${DOCKER_HOST:-}" ]; then
    # Check for standard Docker socket first
    if [ -S "/var/run/docker.sock" ]; then
        export DOCKER_HOST="unix:///var/run/docker.sock"
    # Fallback to Rancher Desktop socket on macOS
    elif [ -S "$HOME/.rd/docker.sock" ]; then
        export DOCKER_HOST="unix://$HOME/.rd/docker.sock"
    fi
fi

# Source idempotent caching library (Feature 004)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/lib-idempotent.sh" ]; then
    echo "Error: Idempotent caching library not found: $SCRIPT_DIR/lib-idempotent.sh" >&2
    exit 1
fi
source "$SCRIPT_DIR/lib-idempotent.sh"

# -----------------------------------------------------------------------------
# Input Validation
# -----------------------------------------------------------------------------

if [ $# -lt 3 ]; then
    echo "Usage: $0 <image:tag> <format> <output-file> [platform]" >&2
    echo "" >&2
    echo "Formats:" >&2
    echo "  cyclonedx-json - CycloneDX JSON format (recommended)" >&2
    echo "  spdx-json      - SPDX JSON format" >&2
    echo "" >&2
    echo "Example:" >&2
    echo "  $0 ib-schema-registry:latest cyclonedx-json build/sbom/latest.cyclonedx.json" >&2
    echo "  $0 ib-schema-registry:latest spdx-json build/sbom/latest.spdx.json linux/amd64" >&2
    exit 1
fi

IMAGE="$1"
FORMAT="$2"
OUTPUT_FILE="$3"
PLATFORM="${4:-}"

# Validate format
case "$FORMAT" in
    cyclonedx-json|spdx-json)
        ;;
    *)
        echo "Error: Invalid format '$FORMAT'. Must be cyclonedx-json or spdx-json" >&2
        exit 1
        ;;
esac

# -----------------------------------------------------------------------------
# Tool Check
# -----------------------------------------------------------------------------

if ! command -v syft &> /dev/null; then
    echo "Error: Syft is not installed" >&2
    echo "" >&2
    echo "Install Syft:" >&2
    echo "  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin" >&2
    echo "" >&2
    echo "Or use Makefile:" >&2
    echo "  make sbom-install-tools" >&2
    exit 1
fi

# Check Syft version (require v1.0.0+)
SYFT_VERSION=$(syft version 2>&1 | grep -i version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "0.0.0")
REQUIRED_VERSION="1.0.0"

version_gte() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

if ! version_gte "$SYFT_VERSION" "$REQUIRED_VERSION"; then
    echo "Warning: Syft version $SYFT_VERSION is older than recommended $REQUIRED_VERSION" >&2
    echo "Consider upgrading: curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin" >&2
fi

# -----------------------------------------------------------------------------
# Image Validation
# -----------------------------------------------------------------------------

echo "→ Validating image: $IMAGE"

if [ -n "$PLATFORM" ]; then
    echo "  Platform: $PLATFORM"
else
    # Detect native platform
    PLATFORM=$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}' 2>/dev/null || echo "linux/amd64")
    echo "  Platform: $PLATFORM (auto-detected)"
fi

# Check if image exists locally
if ! docker image inspect "$IMAGE" &> /dev/null; then
    echo "Error: Image '$IMAGE' not found locally" >&2
    echo "Build the image first: make build TAG=${IMAGE##*:}" >&2
    exit 1
fi

# Get image digest for idempotency tracking (Feature 004)
echo "→ Extracting image digest..."
IMAGE_DIGEST=$(docker inspect --format='{{.RepoDigests}}' "$IMAGE" 2>/dev/null | grep -oE 'sha256:[a-f0-9]{64}' | head -1 || true)
if [ -z "$IMAGE_DIGEST" ]; then
    # Fallback: use image ID if digest not available
    IMAGE_DIGEST=$(docker inspect --format='{{.ID}}' "$IMAGE" | sed 's|sha256:||')
    echo "  Digest (from ID): $IMAGE_DIGEST"
else
    echo "  Digest: $IMAGE_DIGEST"
fi

# -----------------------------------------------------------------------------
# SBOM Generation
# -----------------------------------------------------------------------------

echo "→ Generating SBOM..."
echo "  Format: $FORMAT"
echo "  Output: $OUTPUT_FILE"

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Feature 004: Idempotent SBOM Generation
# Generate to temporary file first, then verify and move atomically
TEMP_OUTPUT_FILE="$OUTPUT_FILE.tmp.$$"

echo "→ Generating SBOM..."
echo "  Format: $FORMAT"
echo "  Output: $OUTPUT_FILE"

# Generate SBOM with Syft
SYFT_OPTS=(
    --quiet
    --output "$FORMAT=$TEMP_OUTPUT_FILE"
)

if [ -n "$PLATFORM" ]; then
    SYFT_OPTS+=(--platform "$PLATFORM")
fi

if ! syft "${SYFT_OPTS[@]}" "$IMAGE"; then
    echo "Error: SBOM generation failed" >&2
    rm -f "$TEMP_OUTPUT_FILE"
    exit 1
fi

# Verify generated SBOM format
if ! validate_sbom_format "$TEMP_OUTPUT_FILE"; then
    echo "Error: Generated SBOM is invalid" >&2
    rm -f "$TEMP_OUTPUT_FILE"
    exit 1
fi

# Feature 004: Check for existing SBOM and verify equivalence
OPERATION="GENERATED"
if detect_existing_sbom "$OUTPUT_FILE"; then
    # Metadata exists, check if this is the same image digest (idempotent)
    if verify_sbom_identical "$OUTPUT_FILE" "$IMAGE_DIGEST"; then
        # Same digest, skip overwrite and mark as verified
        OPERATION="VERIFIED_IDENTICAL"
        rm -f "$TEMP_OUTPUT_FILE"
    else
        # Different digest, mark as updated and proceed with overwrite
        OPERATION="UPDATED"
    fi
else
    # No prior version, proceed with generation
    OPERATION="GENERATED"
fi

# Only move file to final location if not VERIFIED_IDENTICAL
if [ "$OPERATION" != "VERIFIED_IDENTICAL" ]; then
    if ! atomic_sbom_rename "$TEMP_OUTPUT_FILE" "$OUTPUT_FILE"; then
        echo "Error: Failed to finalize SBOM file" >&2
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Post-Processing & Metadata
# -----------------------------------------------------------------------------

# Verify output file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: SBOM file was not created: $OUTPUT_FILE" >&2
    exit 1
fi

# Get file size and component count
FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
COMPONENT_COUNT=$(grep -o '"name"' "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "unknown")

# Feature 004: Write idempotent metadata
if ! write_sbom_metadata "$OUTPUT_FILE" "$IMAGE" "$IMAGE_DIGEST" "$PLATFORM" "$OPERATION"; then
    echo "Error: Failed to write SBOM metadata" >&2
    exit 1
fi

# Feature 004: Log operation status
log_operation_status "$OPERATION" "$OUTPUT_FILE" "$FILE_SIZE"
echo "  Components: ~$COMPONENT_COUNT"

# Get metadata for summary output
METADATA_FILE="${OUTPUT_FILE%.json}.metadata.json"
if [ -f "$METADATA_FILE" ]; then
    DIGEST_SUMMARY=$(jq -r '.digest // "unknown"' "$METADATA_FILE" 2>/dev/null || echo "unknown")
    HASH_SUMMARY=$(jq -r '.content_hash // "unknown"' "$METADATA_FILE" 2>/dev/null | cut -c1-20)
    echo "  Digest: $DIGEST_SUMMARY"
    echo "  Hash: $HASH_SUMMARY..."
    echo "  Metadata: $METADATA_FILE"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "Next steps:"
echo "  1. Validate SBOM: make sbom-validate TAG=${IMAGE##*:}"
echo "  2. Scan for vulnerabilities: grype sbom:$OUTPUT_FILE"
echo "  3. View SBOM: cat $OUTPUT_FILE | jq ."

exit 0
