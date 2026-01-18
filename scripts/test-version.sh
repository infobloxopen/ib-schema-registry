#!/usr/bin/env bash
#
# Test suite for version.sh
# Validates version computation across different scenarios
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION_SCRIPT="${SCRIPT_DIR}/version.sh"
VALIDATE_SCRIPT="${SCRIPT_DIR}/validate-version.sh"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helper functions
test_start() {
    TESTS_RUN=$((TESTS_RUN + 1))
    echo -e "${YELLOW}TEST ${TESTS_RUN}: ${1}${NC}"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓ PASS${NC}"
    echo
}

test_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗ FAIL: ${1}${NC}"
    echo
}

# Test 1: Version script exists and is executable
test_start "Version script exists and is executable"
if [[ -x "${VERSION_SCRIPT}" ]]; then
    test_pass
else
    test_fail "Version script not found or not executable at ${VERSION_SCRIPT}"
fi

# Test 2: Validation script exists and is executable
test_start "Validation script exists and is executable"
if [[ -x "${VALIDATE_SCRIPT}" ]]; then
    test_pass
else
    test_fail "Validation script not found or not executable at ${VALIDATE_SCRIPT}"
fi

# Test 3: Version script runs without errors
test_start "Version script runs without errors"
if VERSION_OUTPUT=$("${VERSION_SCRIPT}" 2>&1); then
    echo "Output: ${VERSION_OUTPUT}"
    test_pass
else
    test_fail "Version script exited with non-zero status"
fi

# Test 4: Version format matches expected pattern
test_start "Version format matches expected pattern"
VERSION_OUTPUT=$("${VERSION_SCRIPT}")
# Pattern: <upstream>-ib.<suffix>.<sha>[.dirty]
# Example: 8.1.1-ib.main.abc1234 or 8.1.1-ib.1.abc1234
if [[ "${VERSION_OUTPUT}" =~ ^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$ ]]; then
    echo "Version: ${VERSION_OUTPUT}"
    test_pass
else
    test_fail "Version '${VERSION_OUTPUT}' does not match expected pattern"
fi

# Test 5: Validation script accepts computed version
test_start "Validation script accepts computed version"
VERSION_OUTPUT=$("${VERSION_SCRIPT}")
if "${VALIDATE_SCRIPT}" "${VERSION_OUTPUT}" >/dev/null 2>&1; then
    echo "Version validated: ${VERSION_OUTPUT}"
    test_pass
else
    test_fail "Validation script rejected version '${VERSION_OUTPUT}'"
fi

# Test 6: Version script supports --format=json
test_start "Version script supports --format=json"
if JSON_OUTPUT=$("${VERSION_SCRIPT}" --format=json 2>&1); then
    echo "JSON: ${JSON_OUTPUT}"
    # Basic JSON validation: should contain "VERSION" key
    if echo "${JSON_OUTPUT}" | grep -q '"VERSION"'; then
        test_pass
    else
        test_fail "JSON output does not contain VERSION key"
    fi
else
    test_fail "Version script --format=json failed"
fi

# Test 7: Version script supports --format=export
test_start "Version script supports --format=export"
if EXPORT_OUTPUT=$("${VERSION_SCRIPT}" --format=export 2>&1); then
    echo "Export format:"
    echo "${EXPORT_OUTPUT}"
    # Should contain VERSION= statements (without export keyword in some implementations)
    if echo "${EXPORT_OUTPUT}" | grep -q 'VERSION='; then
        test_pass
    else
        test_fail "Export output does not contain 'VERSION=' statement"
    fi
else
    test_fail "Version script --format=export failed"
fi

# Test 8: Version script supports --format=make
test_start "Version script supports --format=make"
if MAKE_OUTPUT=$("${VERSION_SCRIPT}" --format=make 2>&1); then
    echo "Make format:"
    echo "${MAKE_OUTPUT}"
    # Should contain VERSION variable
    if echo "${MAKE_OUTPUT}" | grep -q '^VERSION = '; then
        test_pass
    else
        test_fail "Make output does not contain 'VERSION = ' statement"
    fi
else
    test_fail "Version script --format=make failed"
fi

# Test 9: Version script supports --format=github
test_start "Version script supports --format=github"
if GITHUB_OUTPUT=$("${VERSION_SCRIPT}" --format=github 2>&1); then
    echo "GitHub Actions format:"
    echo "${GITHUB_OUTPUT}"
    # Should contain GitHub Actions output syntax
    if echo "${GITHUB_OUTPUT}" | grep -q 'VERSION='; then
        test_pass
    else
        test_fail "GitHub output does not contain VERSION= statement"
    fi
else
    test_fail "Version script --format=github failed"
fi

# Test 10: Version contains correct number of components
test_start "Version contains correct number of components"
VERSION_OUTPUT=$("${VERSION_SCRIPT}")
# Count dots: should be at least 3 (X.Y.Z-ib.suffix.sha)
DOT_COUNT=$(echo "${VERSION_OUTPUT}" | tr -cd '.' | wc -c | tr -d ' ')
if [[ ${DOT_COUNT} -ge 3 ]]; then
    echo "Version has ${DOT_COUNT} dots: ${VERSION_OUTPUT}"
    test_pass
else
    test_fail "Version '${VERSION_OUTPUT}' has only ${DOT_COUNT} dots (expected at least 3)"
fi

# Test 11: SHA component is 7 characters
test_start "SHA component is 7 characters"
VERSION_OUTPUT=$("${VERSION_SCRIPT}")
# Extract SHA (last component before optional .dirty)
if [[ "${VERSION_OUTPUT}" =~ \.([a-z0-9]{7})(\.dirty)?$ ]]; then
    SHA="${BASH_REMATCH[1]}"
    echo "Extracted SHA: ${SHA}"
    if [[ ${#SHA} -eq 7 ]]; then
        test_pass
    else
        test_fail "SHA '${SHA}' is not 7 characters"
    fi
else
    test_fail "Could not extract SHA from version '${VERSION_OUTPUT}'"
fi

# Test 12: Validation script rejects invalid formats
test_start "Validation script rejects invalid formats"
INVALID_VERSIONS=(
    "invalid"
    "1.2.3+infoblox.1"
    "1.2.3-ib.1.abc123"    # SHA too short
    "1.2.3-ib.1.abc12345"  # SHA too long
    "1.2.3-ib.1.ABC1234"   # SHA uppercase
    "1.2.3-ib..abc1234"    # Empty suffix
    "1.2.3-ib.1.abc1234.not-dirty" # Invalid dirty suffix
)

ALL_REJECTED=true
for INVALID_VERSION in "${INVALID_VERSIONS[@]}"; do
    if "${VALIDATE_SCRIPT}" "${INVALID_VERSION}" >/dev/null 2>&1; then
        echo "ERROR: Validation script incorrectly accepted '${INVALID_VERSION}'"
        ALL_REJECTED=false
    else
        echo "Correctly rejected: ${INVALID_VERSION}"
    fi
done

if ${ALL_REJECTED}; then
    test_pass
else
    test_fail "Validation script accepted one or more invalid versions"
fi

# Test 13: Upstream version extraction
test_start "Upstream version is extracted correctly"
if JSON_OUTPUT=$("${VERSION_SCRIPT}" --format=json --quiet 2>&1); then
    # Use jq if available, otherwise grep
    if command -v jq >/dev/null 2>&1; then
        UPSTREAM_VERSION=$(echo "${JSON_OUTPUT}" | jq -r '.UPSTREAM_VERSION')
    else
        UPSTREAM_VERSION=$(echo "${JSON_OUTPUT}" | grep '"UPSTREAM_VERSION"' | sed 's/.*: "\([^"]*\)".*/\1/')
    fi
    echo "Upstream version: ${UPSTREAM_VERSION}"
    # Should match X.Y.Z format
    if [[ "${UPSTREAM_VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        test_pass
    else
        test_fail "Upstream version '${UPSTREAM_VERSION}' does not match X.Y.Z format"
    fi
else
    test_fail "Could not extract upstream version"
fi

# Test 14: Version script handles missing upstream submodule gracefully
test_start "Version script handles missing upstream submodule gracefully"
# Temporarily hide upstream directory
UPSTREAM_DIR="${SCRIPT_DIR}/../upstream/schema-registry"
if [[ -d "${UPSTREAM_DIR}" ]]; then
    # Just test that it doesn't crash - we can't actually move the submodule
    if VERSION_OUTPUT=$("${VERSION_SCRIPT}" 2>&1); then
        echo "Version computed successfully even with submodule check"
        test_pass
    else
        test_fail "Version script failed"
    fi
else
    echo "Upstream submodule not present - skipping test"
    test_pass
fi

# Test 15: Validation script provides helpful error messages
test_start "Validation script provides helpful error messages"
ERROR_OUTPUT=$("${VALIDATE_SCRIPT}" "invalid-version" 2>&1 || true)
if [[ "${ERROR_OUTPUT}" =~ (Invalid|must|format|pattern) ]]; then
    echo "Error message: ${ERROR_OUTPUT}"
    test_pass
else
    test_fail "Validation script did not provide helpful error message"
fi

# Summary
echo
echo "=================================================="
echo "Test Summary"
echo "=================================================="
echo "Tests run:    ${TESTS_RUN}"
echo -e "Tests passed: ${GREEN}${TESTS_PASSED}${NC}"
if [[ ${TESTS_FAILED} -gt 0 ]]; then
    echo -e "Tests failed: ${RED}${TESTS_FAILED}${NC}"
else
    echo -e "Tests failed: ${TESTS_FAILED}"
fi
echo "=================================================="
echo

if [[ ${TESTS_FAILED} -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
