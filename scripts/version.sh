#!/bin/bash
# Version computation script for ib-schema-registry
# Generates version strings in format: <upstream>-ib.<suffix>.<sha>[.dirty]
#
# Usage:
#   ./scripts/version.sh                    # Plain output (default)
#   ./scripts/version.sh --format=export    # Export format (shell variables)
#   ./scripts/version.sh --format=json      # JSON format
#   ./scripts/version.sh --format=make      # Makefile format
#   ./scripts/version.sh --format=github    # GitHub Actions output format
#
# Exit codes:
#   0 = Success
#   1 = Error (invalid state, missing data, validation failure)

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Version format regex for validation
VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$'

# ============================================================================
# Helper Functions
# ============================================================================

# Print error message to stderr
error() {
  echo "ERROR: $*" >&2
}

# Print info message to stderr (only if not in quiet mode)
info() {
  if [ "${QUIET:-false}" != "true" ]; then
    echo "INFO: $*" >&2
  fi
}

# ============================================================================
# Version Component Extraction
# ============================================================================

# Extract upstream version from upstream/schema-registry submodule
get_upstream_version() {
  local upstream_dir="${REPO_ROOT}/upstream/schema-registry"
  
  # Check if upstream submodule exists (either .git file or .git directory)
  if [ ! -e "$upstream_dir/.git" ]; then
    error "Upstream submodule not found at $upstream_dir"
    error "Please run: git submodule update --init --recursive"
    return 1
  fi
  
  # Get latest tag from upstream
  local version
  version=$(cd "$upstream_dir" && git describe --tags --abbrev=0 2>/dev/null)
  
  if [ -z "$version" ]; then
    error "No upstream version tags found in $upstream_dir"
    return 1
  fi
  
  # Remove leading 'v' if present
  version="${version#v}"
  
  # Validate upstream version format (MAJOR.MINOR.PATCH)
  if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    error "Invalid upstream version format: $version (expected MAJOR.MINOR.PATCH)"
    return 1
  fi
  
  echo "$version"
}

# Get short commit SHA (7 characters)
get_short_sha() {
  local sha
  sha=$(git -C "$REPO_ROOT" rev-parse --short=7 HEAD 2>/dev/null)
  
  if [ -z "$sha" ]; then
    error "Could not determine commit SHA"
    return 1
  fi
  
  # Convert to lowercase (Git should already return lowercase, but ensure it)
  echo "$sha" | tr '[:upper:]' '[:lower:]'
}

# Detect if working directory has uncommitted changes
detect_dirty() {
  # Check for any changes (staged, modified, deleted)
  # Exclude untracked files (lines starting with ??)
  if git -C "$REPO_ROOT" status --porcelain 2>/dev/null | grep -v "^??" | grep -q .; then
    echo ".dirty"
  else
    echo ""
  fi
}

# Get current branch name
get_branch_name() {
  local branch
  branch=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)
  
  # Handle detached HEAD state
  if [ "$branch" = "HEAD" ]; then
    # Try to get branch from GitHub Actions environment
    if [ -n "${GITHUB_REF_NAME:-}" ]; then
      branch="$GITHUB_REF_NAME"
    else
      # Fallback to "unknown"
      branch="unknown"
    fi
  fi
  
  echo "$branch"
}

# Sanitize branch name for use in version string
sanitize_branch() {
  local branch="$1"
  
  # Convert to lowercase
  branch=$(echo "$branch" | tr '[:upper:]' '[:lower:]')
  
  # Replace slashes with hyphens
  branch=$(echo "$branch" | tr '/' '-')
  
  # Remove all invalid characters (keep only a-z, 0-9, -, ., _)
  branch=$(echo "$branch" | tr -cd 'a-z0-9._-')
  
  # Truncate to 50 characters max
  branch=$(echo "$branch" | cut -c1-50)
  
  # Remove leading/trailing hyphens or dots
  branch=$(echo "$branch" | sed 's/^[-.]*//' | sed 's/[-.]$//')
  
  # Ensure branch is not empty
  if [ -z "$branch" ]; then
    branch="unknown"
  fi
  
  echo "$branch"
}

# ============================================================================
# Version Validation
# ============================================================================

# Validate version string format
validate_version() {
  local version="$1"
  
  # Check length (OCI registry limit)
  if [ ${#version} -gt 128 ]; then
    error "Version exceeds 128 characters: ${#version} chars"
    return 1
  fi
  
  # Check format with regex
  if ! echo "$version" | grep -qE "$VERSION_REGEX"; then
    error "Version does not match required format: $version"
    error "Expected format: <upstream>-ib.<suffix>.<sha>[.dirty]"
    return 1
  fi
  
  # Check character set (redundant with regex, but explicit)
  if ! echo "$version" | grep -qE '^[A-Za-z0-9._-]+$'; then
    error "Version contains invalid characters: $version"
    error "Allowed characters: A-Z a-z 0-9 . _ -"
    return 1
  fi
  
  return 0
}

# ============================================================================
# Main Version Computation
# ============================================================================

# Compute complete version string
compute_version() {
  # Step 1: Extract upstream version
  local upstream
  upstream=$(get_upstream_version)
  if [ $? -ne 0 ] || [ -z "$upstream" ]; then
    return 1
  fi
  
  # Step 2: Compute commit SHA
  local sha
  sha=$(get_short_sha)
  if [ $? -ne 0 ] || [ -z "$sha" ]; then
    return 1
  fi
  
  # Step 3: Detect dirty state
  local dirty
  dirty=$(detect_dirty)
  
  # Step 4: Determine suffix based on Git state
  local suffix
  local revision=""
  
  # Try to detect release tag
  local current_tag
  current_tag=$(git -C "$REPO_ROOT" describe --exact-match --tags 2>/dev/null || echo "")
  
  if [[ $current_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+-ib\.([0-9]+)$ ]]; then
    # Release tag: extract revision number
    revision="${BASH_REMATCH[1]}"
    suffix="${revision}"
    info "Detected release tag: $current_tag (revision: $revision)"
  else
    # Not a release tag: use branch name
    local branch
    branch=$(get_branch_name)
    suffix=$(sanitize_branch "$branch")
    info "Using branch name: $branch (sanitized: $suffix)"
  fi
  
  # Step 5: Assemble version string
  local version="${upstream}-ib.${suffix}.${sha}${dirty}"
  
  # Step 6: Validate
  if ! validate_version "$version"; then
    error "Generated invalid version: $version"
    return 1
  fi
  
  # Export variables for use by output formatters
  export COMPUTED_VERSION="$version"
  export COMPUTED_UPSTREAM_VERSION="$upstream"
  export COMPUTED_REVISION="$revision"
  export COMPUTED_SHA="$sha"
  export COMPUTED_DIRTY="$dirty"
  export COMPUTED_TAG="$version"
  
  echo "$version"
}

# ============================================================================
# Output Formatters
# ============================================================================

# Plain text output (default)
format_plain() {
  echo "$COMPUTED_TAG"
}

# Export format (shell variables)
format_export() {
  cat <<EOF
VERSION="$COMPUTED_VERSION"
UPSTREAM_VERSION="$COMPUTED_UPSTREAM_VERSION"
REVISION="$COMPUTED_REVISION"
SHA="$COMPUTED_SHA"
DIRTY="$([ -n "$COMPUTED_DIRTY" ] && echo "true" || echo "false")"
TAG="$COMPUTED_TAG"
EOF
}

# JSON format
format_json() {
  local dirty_bool
  if [ -n "$COMPUTED_DIRTY" ]; then
    dirty_bool="true"
  else
    dirty_bool="false"
  fi
  
  cat <<EOF
{
  "VERSION": "$COMPUTED_VERSION",
  "UPSTREAM_VERSION": "$COMPUTED_UPSTREAM_VERSION",
  "REVISION": "$COMPUTED_REVISION",
  "SHA": "$COMPUTED_SHA",
  "DIRTY": $dirty_bool,
  "TAG": "$COMPUTED_TAG"
}
EOF
}

# Makefile format
format_make() {
  cat <<EOF
VERSION = $COMPUTED_VERSION
UPSTREAM_VERSION = $COMPUTED_UPSTREAM_VERSION
REVISION = $COMPUTED_REVISION
SHA = $COMPUTED_SHA
DIRTY = $([ -n "$COMPUTED_DIRTY" ] && echo "true" || echo "false")
TAG = $COMPUTED_TAG
EOF
}

# GitHub Actions output format
format_github() {
  cat <<EOF
VERSION=$COMPUTED_VERSION
UPSTREAM_VERSION=$COMPUTED_UPSTREAM_VERSION
REVISION=$COMPUTED_REVISION
SHA=$COMPUTED_SHA
DIRTY=$([ -n "$COMPUTED_DIRTY" ] && echo "true" || echo "false")
TAG=$COMPUTED_TAG
EOF
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
  local format="plain"
  
  # Parse arguments
  for arg in "$@"; do
    case "$arg" in
      --format=export)
        format="export"
        ;;
      --format=json)
        format="json"
        ;;
      --format=make)
        format="make"
        ;;
      --format=github)
        format="github"
        ;;
      --format=plain|--format=*)
        format="plain"
        ;;
      --quiet|-q)
        export QUIET=true
        ;;
      --help|-h)
        cat <<EOF
Usage: $0 [OPTIONS]

Compute version string for ib-schema-registry.

Options:
  --format=export    Output as shell variables (for eval/source)
  --format=json      Output as JSON object
  --format=make      Output as Makefile variables
  --format=github    Output for GitHub Actions (GITHUB_OUTPUT)
  --format=plain     Output plain version string (default)
  --quiet, -q        Suppress info messages
  --help, -h         Show this help message

Version Format:
  <upstream>-ib.<suffix>.<sha>[.dirty]

Examples:
  8.1.1-ib.1.abc1234              # Release tag v8.1.1-ib.1
  8.1.1-ib.main.abc1234           # Main branch
  8.1.1-ib.feature-auth.abc1234   # Feature branch
  8.1.1-ib.main.abc1234.dirty     # Uncommitted changes

Exit Codes:
  0 = Success
  1 = Error (invalid state, missing data, validation failure)
EOF
        exit 0
        ;;
      *)
        error "Unknown option: $arg"
        error "Use --help for usage information"
        exit 1
        ;;
    esac
  done
  
  # Compute version
  if ! compute_version >/dev/null; then
    exit 1
  fi
  
  # Output in requested format
  case "$format" in
    export)
      format_export
      ;;
    json)
      format_json
      ;;
    make)
      format_make
      ;;
    github)
      format_github
      ;;
    plain|*)
      format_plain
      ;;
  esac
}

# Run main function
main "$@"
