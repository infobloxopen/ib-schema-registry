#!/usr/bin/env bash
# =============================================================================
# SBOM Generation Tests
# =============================================================================
# Tests SBOM generation functionality
#
# Usage: ./test-sbom-generation.sh [image:tag]
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Configuration
IMAGE="${1:-ib-schema-registry:latest}"
SBOM_DIR="$REPO_ROOT/build/sbom"
TEST_TAG="test-sbom-$(date +%s)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}→${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_func="$2"
    
    TESTS_RUN=$((TESTS_RUN + 1))
    echo ""
    log_info "Test $TESTS_RUN: $test_name"
    
    if $test_func; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        log_success "PASS: $test_name"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        log_error "FAIL: $test_name"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Test Cases
# -----------------------------------------------------------------------------

test_syft_installed() {
    if command -v syft &> /dev/null; then
        local version=$(syft version | grep -oP 'Version:\s+\K[\d.]+' || echo "unknown")
        log_info "Syft version: $version"
        return 0
    else
        log_error "Syft is not installed"
        return 1
    fi
}

test_image_exists() {
    if docker image inspect "$IMAGE" &> /dev/null; then
        log_info "Image found: $IMAGE"
        return 0
    else
        log_error "Image not found: $IMAGE"
        return 1
    fi
}

test_generate_cyclonedx() {
    local output_file="$SBOM_DIR/${TEST_TAG}.cyclonedx.json"
    
    if bash "$REPO_ROOT/scripts/sbom/generate-sbom.sh" \
        "$IMAGE" \
        cyclonedx-json \
        "$output_file" &> /dev/null; then
        
        if [ -f "$output_file" ]; then
            log_info "CycloneDX SBOM generated: $output_file"
            return 0
        else
            log_error "CycloneDX SBOM file not created"
            return 1
        fi
    else
        log_error "Failed to generate CycloneDX SBOM"
        return 1
    fi
}

test_generate_spdx() {
    local output_file="$SBOM_DIR/${TEST_TAG}.spdx.json"
    
    if bash "$REPO_ROOT/scripts/sbom/generate-sbom.sh" \
        "$IMAGE" \
        spdx-json \
        "$output_file" &> /dev/null; then
        
        if [ -f "$output_file" ]; then
            log_info "SPDX SBOM generated: $output_file"
            return 0
        else
            log_error "SPDX SBOM file not created"
            return 1
        fi
    else
        log_error "Failed to generate SPDX SBOM"
        return 1
    fi
}

test_cyclonedx_format() {
    local sbom_file="$SBOM_DIR/${TEST_TAG}.cyclonedx.json"
    
    if [ ! -f "$sbom_file" ]; then
        log_error "SBOM file not found: $sbom_file"
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$sbom_file" 2>/dev/null; then
        log_error "Invalid JSON format"
        return 1
    fi
    
    # Check CycloneDX structure
    if ! jq -e '.bomFormat == "CycloneDX"' "$sbom_file" &> /dev/null; then
        log_error "Missing or invalid bomFormat"
        return 1
    fi
    
    if ! jq -e '.specVersion' "$sbom_file" &> /dev/null; then
        log_error "Missing specVersion"
        return 1
    fi
    
    if ! jq -e '.components' "$sbom_file" &> /dev/null; then
        log_error "Missing components array"
        return 1
    fi
    
    local component_count=$(jq '[.components[]?] | length' "$sbom_file")
    log_info "CycloneDX components: $component_count"
    
    if [ "$component_count" -lt 1 ]; then
        log_warning "Expected at least 1 component"
        return 1
    fi
    
    return 0
}

test_spdx_format() {
    local sbom_file="$SBOM_DIR/${TEST_TAG}.spdx.json"
    
    if [ ! -f "$sbom_file" ]; then
        log_error "SBOM file not found: $sbom_file"
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$sbom_file" 2>/dev/null; then
        log_error "Invalid JSON format"
        return 1
    fi
    
    # Check SPDX structure
    if ! jq -e '.spdxVersion' "$sbom_file" &> /dev/null; then
        log_error "Missing spdxVersion"
        return 1
    fi
    
    if ! jq -e '.packages' "$sbom_file" &> /dev/null; then
        log_error "Missing packages array"
        return 1
    fi
    
    local package_count=$(jq '[.packages[]?] | length' "$sbom_file")
    log_info "SPDX packages: $package_count"
    
    if [ "$package_count" -lt 1 ]; then
        log_warning "Expected at least 1 package"
        return 1
    fi
    
    return 0
}

test_metadata_file() {
    local metadata_file="$SBOM_DIR/${TEST_TAG}.cyclonedx.metadata.json"
    
    if [ ! -f "$metadata_file" ]; then
        log_error "Metadata file not found: $metadata_file"
        return 1
    fi
    
    # Check JSON validity
    if ! jq empty "$metadata_file" 2>/dev/null; then
        log_error "Invalid metadata JSON"
        return 1
    fi
    
    # Check required fields
    for field in image platform format generated_at tool; do
        if ! jq -e ".$field" "$metadata_file" &> /dev/null; then
            log_error "Missing metadata field: $field"
            return 1
        fi
    done
    
    log_info "Metadata file is valid"
    return 0
}

test_validation_script() {
    local sbom_file="$SBOM_DIR/${TEST_TAG}.cyclonedx.json"
    
    if bash "$REPO_ROOT/scripts/sbom/validate-sbom.sh" "$sbom_file" skip-vulns &> /dev/null; then
        log_info "Validation script succeeded"
        return 0
    else
        log_error "Validation script failed"
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Main Test Execution
# -----------------------------------------------------------------------------

main() {
    echo "═══════════════════════════════════════════════════════"
    echo "SBOM Generation Test Suite"
    echo "═══════════════════════════════════════════════════════"
    echo "Image: $IMAGE"
    echo "SBOM Dir: $SBOM_DIR"
    echo "Test Tag: $TEST_TAG"
    echo ""
    
    # Create SBOM directory
    mkdir -p "$SBOM_DIR"
    
    # Run tests
    run_test "Syft is installed" test_syft_installed
    run_test "Docker image exists" test_image_exists
    run_test "Generate CycloneDX SBOM" test_generate_cyclonedx
    run_test "Generate SPDX SBOM" test_generate_spdx
    run_test "Validate CycloneDX format" test_cyclonedx_format
    run_test "Validate SPDX format" test_spdx_format
    run_test "Validate metadata file" test_metadata_file
    run_test "Run validation script" test_validation_script
    
    # Summary
    echo ""
    echo "═══════════════════════════════════════════════════════"
    echo "Test Summary"
    echo "═══════════════════════════════════════════════════════"
    echo "Tests Run:    $TESTS_RUN"
    echo "Tests Passed: $TESTS_PASSED"
    echo "Tests Failed: $TESTS_FAILED"
    echo ""
    
    # Cleanup
    log_info "Cleaning up test artifacts..."
    rm -f "$SBOM_DIR/${TEST_TAG}."*
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        log_success "All tests passed!"
        exit 0
    else
        log_error "Some tests failed"
        exit 1
    fi
}

# Run main function
main "$@"
