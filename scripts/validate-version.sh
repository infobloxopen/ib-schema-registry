#!/bin/bash
# Validate version string format for ib-schema-registry
#
# Usage:
#   ./scripts/validate-version.sh <version-string>
#   ./scripts/validate-version.sh --help
#
# Exit codes:
#   0 = Valid version string
#   1 = Invalid version string or error

set -euo pipefail

# Version format regex
VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$'

# Maximum length (OCI registry limit)
MAX_LENGTH=128

# ============================================================================
# Helper Functions
# ============================================================================

print_usage() {
  cat <<EOF
Usage: $0 <version-string>
       $0 --help

Validate version string format for ib-schema-registry.

Version Format:
  <upstream>-ib.<suffix>.<sha>[.dirty]

  Components:
    <upstream>  - SemVer MAJOR.MINOR.PATCH (e.g., 8.1.1)
    -ib.        - Infoblox identifier (literal)
    <suffix>    - Revision number OR branch name (sanitized)
    <sha>       - 7-character commit SHA (lowercase hex)
    .dirty      - Optional suffix for uncommitted changes

  Examples:
    8.1.1-ib.1.abc1234                # Valid: Release
    8.1.1-ib.main.abc1234             # Valid: Main branch
    8.1.1-ib.feature-auth.abc1234     # Valid: Feature branch
    8.1.1-ib.main.abc1234.dirty       # Valid: Dirty build

Validation Rules:
  1. Total length ≤ $MAX_LENGTH characters
  2. Matches format regex exactly
  3. Only allowed characters: [A-Za-z0-9._-]
  4. Upstream version must be valid SemVer (MAJOR.MINOR.PATCH)
  5. SHA must be exactly 7 lowercase hexadecimal characters

Exit Codes:
  0 = Version string is valid
  1 = Version string is invalid or error
EOF
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_version() {
  local version="$1"
  local errors=0
  
  echo "Validating version: $version"
  echo
  
  # Check 1: Length
  local length=${#version}
  if [ $length -gt $MAX_LENGTH ]; then
    echo "❌ FAIL: Version exceeds maximum length"
    echo "   Length: $length characters (max: $MAX_LENGTH)"
    errors=$((errors + 1))
  else
    echo "✅ PASS: Length check ($length ≤ $MAX_LENGTH)"
  fi
  
  # Check 2: Format regex
  if echo "$version" | grep -qE "$VERSION_REGEX"; then
    echo "✅ PASS: Format matches regex"
  else
    echo "❌ FAIL: Format does not match required pattern"
    echo "   Expected: <upstream>-ib.<suffix>.<sha>[.dirty]"
    errors=$((errors + 1))
  fi
  
  # Check 3: Character set
  if echo "$version" | grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "✅ PASS: Character set valid"
  else
    echo "❌ FAIL: Version contains invalid characters"
    echo "   Allowed: [A-Za-z0-9._-]"
    errors=$((errors + 1))
  fi
  
  # Check 4: Upstream version format
  if echo "$version" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' >/dev/null; then
    local upstream
    upstream=$(echo "$version" | grep -oE '^[0-9]+\.[0-9]+\.[0-9]+')
    echo "✅ PASS: Upstream version valid ($upstream)"
  else
    echo "❌ FAIL: Upstream version invalid or missing"
    errors=$((errors + 1))
  fi
  
  # Check 5: SHA format
  if echo "$version" | grep -oE '\.[a-z0-9]{7}(\.dirty)?$' >/dev/null; then
    local sha
    sha=$(echo "$version" | grep -oE '\.([a-z0-9]{7})(\.dirty)?$' | sed 's/^\.//' | sed 's/\.dirty$//')
    echo "✅ PASS: SHA valid ($sha)"
  else
    echo "❌ FAIL: SHA invalid or missing (expected 7 lowercase hex chars)"
    errors=$((errors + 1))
  fi
  
  # Check 6: No uppercase in suffix or SHA
  if echo "$version" | grep -E '[A-Z]' >/dev/null; then
    echo "⚠️  WARN: Version contains uppercase letters (should be lowercase)"
    errors=$((errors + 1))
  fi
  
  echo
  if [ $errors -eq 0 ]; then
    echo "✅ Version string is VALID"
    return 0
  else
    echo "❌ Version string is INVALID ($errors error(s) found)"
    return 1
  fi
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
  if [ $# -eq 0 ]; then
    echo "ERROR: No version string provided" >&2
    echo >&2
    print_usage
    exit 1
  fi
  
  case "$1" in
    --help|-h)
      print_usage
      exit 0
      ;;
    *)
      validate_version "$1"
      ;;
  esac
}

main "$@"
