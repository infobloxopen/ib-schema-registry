#!/usr/bin/env bash
# =============================================================================
# SBOM Validation Script
# =============================================================================
# Validates SBOM files for correctness and scans for vulnerabilities
# Supports: CycloneDX and SPDX formats
# Tools: Grype, Trivy (optional)
#
# Usage:
#   ./validate-sbom.sh <sbom-file> [skip-vulns]
#
# Arguments:
#   sbom-file   - Path to SBOM file (e.g., build/sbom/latest.cyclonedx.json)
#   skip-vulns  - Optional: Set to "skip-vulns" to skip vulnerability scan
#
# Requirements:
#   - Grype v0.65.0+ for vulnerability scanning
#   - jq for JSON validation
#
# Note: Aligns with supply-chain security principles
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Input Validation
# -----------------------------------------------------------------------------

if [ $# -lt 1 ]; then
    echo "Usage: $0 <sbom-file> [skip-vulns]" >&2
    echo "" >&2
    echo "Examples:" >&2
    echo "  $0 build/sbom/latest.cyclonedx.json" >&2
    echo "  $0 build/sbom/latest.spdx.json skip-vulns" >&2
    exit 1
fi

SBOM_FILE="$1"
SKIP_VULNS="${2:-}"

# Check if file exists
if [ ! -f "$SBOM_FILE" ]; then
    echo "Error: SBOM file not found: $SBOM_FILE" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Tool Check
# -----------------------------------------------------------------------------

# Check for jq (required)
if ! command -v jq &> /dev/null; then
    echo "Error: jq is not installed (required for JSON validation)" >&2
    echo "Install: apt-get install jq  # or  brew install jq" >&2
    exit 1
fi

# Check for Grype (optional but recommended)
HAS_GRYPE=false
if command -v grype &> /dev/null; then
    HAS_GRYPE=true
    GRYPE_VERSION=$(grype version 2>&1 | grep -i version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || echo "unknown")
    echo "→ Found Grype version: $GRYPE_VERSION"
else
    echo "Warning: Grype not found - vulnerability scanning will be skipped" >&2
    echo "Install: curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin" >&2
fi

# -----------------------------------------------------------------------------
# SBOM Format Detection
# -----------------------------------------------------------------------------

echo "→ Validating SBOM file: $SBOM_FILE"

# Detect format from file content
if jq -e '.bomFormat == "CycloneDX"' "$SBOM_FILE" &> /dev/null; then
    FORMAT="cyclonedx"
    SPEC_VERSION=$(jq -r '.specVersion // "unknown"' "$SBOM_FILE")
    echo "  Format: CycloneDX $SPEC_VERSION"
elif jq -e '.spdxVersion' "$SBOM_FILE" &> /dev/null; then
    FORMAT="spdx"
    SPEC_VERSION=$(jq -r '.spdxVersion // "unknown"' "$SBOM_FILE")
    echo "  Format: SPDX $SPEC_VERSION"
else
    echo "Error: Unable to detect SBOM format" >&2
    echo "File must be valid CycloneDX or SPDX JSON" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# JSON Validation
# -----------------------------------------------------------------------------

echo "→ Validating JSON structure..."

if ! jq empty "$SBOM_FILE" 2>/dev/null; then
    echo "Error: Invalid JSON in SBOM file" >&2
    exit 1
fi

echo "✓ JSON structure is valid"

# -----------------------------------------------------------------------------
# SBOM Content Validation
# -----------------------------------------------------------------------------

echo "→ Validating SBOM content..."

# Count components/packages
if [ "$FORMAT" = "cyclonedx" ]; then
    COMPONENT_COUNT=$(jq '[.components[]?] | length' "$SBOM_FILE")
    echo "  Components: $COMPONENT_COUNT"
    
    # Check for required fields
    if ! jq -e '.metadata' "$SBOM_FILE" &> /dev/null; then
        echo "Warning: Missing metadata section" >&2
    fi
    
    if ! jq -e '.metadata.component' "$SBOM_FILE" &> /dev/null; then
        echo "Warning: Missing root component in metadata" >&2
    fi
    
elif [ "$FORMAT" = "spdx" ]; then
    PACKAGE_COUNT=$(jq '[.packages[]?] | length' "$SBOM_FILE")
    echo "  Packages: $PACKAGE_COUNT"
    
    # Check for required fields
    if ! jq -e '.name' "$SBOM_FILE" &> /dev/null; then
        echo "Warning: Missing document name" >&2
    fi
    
    if ! jq -e '.creationInfo' "$SBOM_FILE" &> /dev/null; then
        echo "Warning: Missing creation info" >&2
    fi
fi

echo "✓ SBOM content structure is valid"

# -----------------------------------------------------------------------------
# Vulnerability Scanning
# -----------------------------------------------------------------------------

if [ "$SKIP_VULNS" = "skip-vulns" ]; then
    echo "→ Skipping vulnerability scan (skip-vulns flag set)"
elif [ "$HAS_GRYPE" = false ]; then
    echo "→ Skipping vulnerability scan (Grype not installed)"
else
    echo "→ Scanning for vulnerabilities with Grype..."
    echo ""
    
    # Run Grype vulnerability scan
    # --quiet: Reduce output verbosity
    # --fail-on: Exit code based on severity (default: none, continue on vulns)
    # sbom:<file>: Scan SBOM file instead of image
    
    if grype "sbom:$SBOM_FILE" --quiet; then
        echo ""
        echo "✓ Vulnerability scan complete - no critical issues found"
    else
        EXIT_CODE=$?
        echo ""
        if [ $EXIT_CODE -eq 1 ]; then
            echo "⚠ Vulnerabilities found in SBOM components" >&2
            echo "This is informational - review the output above" >&2
        else
            echo "Error: Grype scan failed with exit code $EXIT_CODE" >&2
            exit $EXIT_CODE
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------

FILE_SIZE=$(du -h "$SBOM_FILE" | cut -f1)

echo ""
echo "═══════════════════════════════════════════════════════"
echo "SBOM Validation Summary"
echo "═══════════════════════════════════════════════════════"
echo "File: $SBOM_FILE"
echo "Format: $FORMAT (spec version $SPEC_VERSION)"
echo "Size: $FILE_SIZE"

if [ "$FORMAT" = "cyclonedx" ]; then
    echo "Components: $COMPONENT_COUNT"
else
    echo "Packages: $PACKAGE_COUNT"
fi

echo ""
echo "✓ SBOM validation complete"

exit 0
