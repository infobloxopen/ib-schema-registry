#!/usr/bin/env bash
# =============================================================================
# SBOM Generation Script
# =============================================================================
# Generates Software Bill of Materials (SBOM) for container images
# Supports: CycloneDX and SPDX formats
# Tool: Syft (https://github.com/anchore/syft)
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
#
# Constitution: Aligns with multi-arch portability and supply-chain security
# =============================================================================

set -euo pipefail

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

# -----------------------------------------------------------------------------
# SBOM Generation
# -----------------------------------------------------------------------------

echo "→ Generating SBOM..."
echo "  Format: $FORMAT"
echo "  Output: $OUTPUT_FILE"

# Create output directory
OUTPUT_DIR=$(dirname "$OUTPUT_FILE")
mkdir -p "$OUTPUT_DIR"

# Generate SBOM with Syft
SYFT_OPTS=(
    --quiet
    --output "$FORMAT=$OUTPUT_FILE"
)

if [ -n "$PLATFORM" ]; then
    SYFT_OPTS+=(--platform "$PLATFORM")
fi

if ! syft "${SYFT_OPTS[@]}" "$IMAGE"; then
    echo "Error: SBOM generation failed" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Post-Processing & Metadata
# -----------------------------------------------------------------------------

# Verify output file was created
if [ ! -f "$OUTPUT_FILE" ]; then
    echo "Error: SBOM file was not created: $OUTPUT_FILE" >&2
    exit 1
fi

# Get file size
FILE_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
COMPONENT_COUNT=$(grep -o '"name"' "$OUTPUT_FILE" 2>/dev/null | wc -l || echo "unknown")

echo "✓ SBOM generated successfully"
echo "  File: $OUTPUT_FILE"
echo "  Size: $FILE_SIZE"
echo "  Components: ~$COMPONENT_COUNT"

# Generate metadata file
METADATA_FILE="${OUTPUT_FILE%.json}.metadata.json"
cat > "$METADATA_FILE" <<EOF
{
  "image": "$IMAGE",
  "platform": "$PLATFORM",
  "format": "$FORMAT",
  "generated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "tool": "syft",
  "tool_version": "$SYFT_VERSION",
  "file_size_bytes": $(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE"),
  "output_file": "$OUTPUT_FILE"
}
EOF

echo "  Metadata: $METADATA_FILE"

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

echo ""
echo "Next steps:"
echo "  1. Validate SBOM: make sbom-validate TAG=${IMAGE##*:}"
echo "  2. Scan for vulnerabilities: grype sbom:$OUTPUT_FILE"
echo "  3. View SBOM: cat $OUTPUT_FILE | jq ."

exit 0
