# Data Model: Versioning Scheme

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)  
**Date**: 2026-01-18

## Overview

This document defines the data entities, algorithms, and transformation rules for the unified versioning scheme.

---

## Entities

### 1. Version String

**Description**: The complete version identifier for Docker images and Helm charts.

**Format**: `<upstream>-ib.<suffix>.<sha>[.dirty]`

**Components**:
- `<upstream>`: SemVer version from upstream schema-registry (e.g., `8.1.1`)
- `ib`: Infoblox identifier (constant)
- `<suffix>`: Release number OR branch name (sanitized)
- `<sha>`: Short Git commit SHA (7 characters)
- `.dirty`: Optional suffix when uncommitted changes exist

**Type**: String  
**Max Length**: 128 characters (OCI registry limit)  
**Character Set**: `[A-Za-z0-9._-]` (alphanumeric, dot, underscore, hyphen)

**Examples**:
```
8.1.1-ib.1.abc1234              # Release tag v8.1.1-ib.1
8.1.1-ib.main.abc1234           # Main branch
8.1.1-ib.feature-auth.abc1234   # Feature branch
8.1.1-ib.main.abc1234.dirty     # Uncommitted changes
```

**Validation Rules**:
- Must match regex: `^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$`
- Upstream must be valid SemVer MAJOR.MINOR.PATCH
- Suffix must be lowercase alphanumeric with dots, underscores, hyphens
- SHA must be exactly 7 lowercase hexadecimal characters
- Total length must not exceed 128 characters

---

### 2. Upstream Version

**Description**: The base version from the upstream Confluent schema-registry project.

**Format**: `<major>.<minor>.<patch>`

**Type**: String (SemVer 2.0 compliant)

**Examples**:
```
8.1.1
7.6.1
8.0.0
```

**Extraction Algorithm**:
```bash
# Navigate to upstream submodule
cd upstream/schema-registry

# Get latest tag from upstream
git describe --tags --abbrev=0 | sed 's/^v//'

# Expected output: 8.1.1
```

**Fallback Behavior**:
- If submodule missing: Error with message "Upstream submodule not found"
- If no tags exist: Error with message "No upstream version tags found"
- If tag not semver: Use tag as-is with warning

**Validation Rules**:
- Must match regex: `^[0-9]+\.[0-9]+\.[0-9]+$`
- Major, minor, and patch must be non-negative integers
- No leading zeros (e.g., `01.02.03` is invalid)

---

### 3. Revision Number

**Description**: Infoblox-specific revision number for a given upstream version.

**Format**: Integer starting from 1

**Type**: Integer

**Examples**:
```
1    # First Infoblox build of upstream version
2    # Second Infoblox build (patch or configuration change)
3    # Third Infoblox build
```

**Extraction Algorithm**:
```bash
# Get current git tag
current_tag=$(git describe --exact-match --tags 2>/dev/null)

# Parse revision number from tag format v<upstream>-ib.<n>
if [[ $current_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+-ib\.([0-9]+)$ ]]; then
  revision="${BASH_REMATCH[1]}"
else
  # Not a release tag, use default
  revision=""
fi

# Expected output: 1, 2, 3, etc., or empty string
```

**Usage Context**:
- Only present for release tags (e.g., `v8.1.1-ib.1`)
- Not used for main branch or feature branches
- Incremented when creating new release of same upstream version

---

### 4. Commit SHA

**Description**: Short Git commit identifier.

**Format**: 7-character lowercase hexadecimal string

**Type**: String

**Examples**:
```
abc1234
def5678
1a2b3c4
```

**Computation Algorithm**:
```bash
# Get short SHA of current HEAD
git rev-parse --short=7 HEAD

# Expected output: abc1234
```

**Validation Rules**:
- Must be exactly 7 characters
- Must contain only hexadecimal characters: `[0-9a-f]`
- Should be lowercase (Git default)

---

### 5. Dirty Flag

**Description**: Indicates whether the working directory has uncommitted changes.

**Format**: Boolean (represented as `.dirty` suffix or absent)

**Type**: Boolean

**Examples**:
```
true   → version includes ".dirty" suffix
false  → version has no dirty suffix
```

**Detection Algorithm**:
```bash
# Check for uncommitted changes (excluding untracked files)
if git status --porcelain | grep -v "^??" | grep -q .; then
  echo ".dirty"
else
  echo ""
fi
```

**Notes**:
- Untracked files (`??` in git status) are ignored
- Modified, added, deleted, or renamed files trigger dirty flag
- Staged but uncommitted changes also trigger dirty flag
- Used to prevent accidental releases from dirty working directories

---

### 6. Branch Name

**Description**: Git branch name, sanitized for use in version string.

**Format**: Lowercase alphanumeric with hyphens, dots, underscores

**Type**: String

**Examples**:
```
main                    → main
feature/auth            → feature-auth
bugfix/SCHEMA-123       → bugfix-schema-123
release/8.1.1           → release-8-1-1
```

**Extraction Algorithm**:
```bash
# Get current branch name
branch=$(git rev-parse --abbrev-ref HEAD)

# Handle detached HEAD state
if [ "$branch" = "HEAD" ]; then
  # Try to get branch from CI environment
  branch="${GITHUB_REF_NAME:-unknown}"
fi

echo "$branch"
```

**Sanitization Algorithm**:
```bash
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
  
  echo "$branch"
}
```

**Validation Rules**:
- Must be non-empty after sanitization
- Must match regex: `^[a-z0-9._-]+$`
- Must not start or end with hyphen or dot
- Maximum length: 50 characters (leaves room for prefix/suffix)

---

## Algorithms

### Version Computation (Main Algorithm)

**Purpose**: Compute complete version string based on Git state.

**Input**: Current Git working directory state

**Output**: Version String (format defined above)

**Algorithm**:

```bash
compute_version() {
  # Step 1: Extract upstream version
  upstream=$(get_upstream_version)
  if [ -z "$upstream" ]; then
    echo "ERROR: Could not determine upstream version" >&2
    exit 1
  fi
  
  # Step 2: Compute commit SHA
  sha=$(git rev-parse --short=7 HEAD)
  if [ -z "$sha" ]; then
    echo "ERROR: Could not determine commit SHA" >&2
    exit 1
  fi
  
  # Step 3: Detect dirty state
  dirty=$(detect_dirty)
  
  # Step 4: Determine suffix based on Git state
  current_tag=$(git describe --exact-match --tags 2>/dev/null)
  
  if [[ $current_tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+-ib\.([0-9]+)$ ]]; then
    # Release tag: use revision number
    revision="${BASH_REMATCH[1]}"
    suffix="${revision}"
  else
    # Not a release tag: use branch name
    branch=$(git rev-parse --abbrev-ref HEAD)
    
    # Handle detached HEAD
    if [ "$branch" = "HEAD" ]; then
      branch="${GITHUB_REF_NAME:-unknown}"
    fi
    
    # Sanitize branch name
    suffix=$(sanitize_branch "$branch")
  fi
  
  # Step 5: Assemble version string
  version="${upstream}-ib.${suffix}.${sha}${dirty}"
  
  # Step 6: Validate
  if ! validate_version "$version"; then
    echo "ERROR: Generated invalid version: $version" >&2
    exit 1
  fi
  
  echo "$version"
}
```

**Error Handling**:
- Exit with code 1 if upstream version cannot be determined
- Exit with code 1 if commit SHA cannot be determined
- Exit with code 1 if generated version fails validation
- Print error messages to stderr

**Edge Cases**:
- Detached HEAD state: Use `GITHUB_REF_NAME` environment variable
- Missing upstream submodule: Error message with suggestion to init submodule
- Shallow clone: Should work if HEAD is reachable
- Git tag without `-ib.N`: Treat as non-release, use branch name

---

### Version Validation

**Purpose**: Validate that a version string meets all requirements.

**Input**: Version string

**Output**: Boolean (exit code 0 = valid, exit code 1 = invalid)

**Algorithm**:

```bash
validate_version() {
  local version="$1"
  
  # Check length
  if [ ${#version} -gt 128 ]; then
    echo "ERROR: Version exceeds 128 characters" >&2
    return 1
  fi
  
  # Check format with regex
  if ! echo "$version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$'; then
    echo "ERROR: Version does not match required format" >&2
    return 1
  fi
  
  # Check character set (redundant with regex, but explicit)
  if ! echo "$version" | grep -qE '^[A-Za-z0-9._-]+$'; then
    echo "ERROR: Version contains invalid characters" >&2
    return 1
  fi
  
  return 0
}
```

**Validation Criteria**:
1. Total length ≤ 128 characters
2. Matches format regex exactly
3. Only contains allowed characters: `[A-Za-z0-9._-]`

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Git Repository State                                        │
├─────────────────────────────────────────────────────────────┤
│ • upstream/schema-registry tags   → Upstream Version       │
│ • Current HEAD commit             → Commit SHA             │
│ • Working directory status        → Dirty Flag             │
│ • Current branch or tag           → Suffix                 │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Version Computation (scripts/version.sh)                    │
├─────────────────────────────────────────────────────────────┤
│ 1. Extract upstream version                                 │
│ 2. Compute SHA                                              │
│ 3. Detect dirty state                                       │
│ 4. Determine suffix (revision OR branch)                    │
│ 5. Assemble: <upstream>-ib.<suffix>.<sha>[.dirty]          │
│ 6. Validate format                                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Output Formats                                              │
├─────────────────────────────────────────────────────────────┤
│ • Plain:  8.1.1-ib.1.abc1234                                │
│ • JSON:   {"TAG":"8.1.1-ib.1.abc1234",...}                  │
│ • Make:   VERSION=8.1.1-ib.1.abc1234\n...                   │
│ • GitHub: TAG=8.1.1-ib.1.abc1234\n...                       │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Consumers                                                   │
├─────────────────────────────────────────────────────────────┤
│ • Makefile            → VERSION variable                    │
│ • Docker build        → IMAGE_TAG                           │
│ • Helm Chart.yaml     → version field                       │
│ • GitHub Actions      → Steps/outputs                       │
│ • OCI Registry        → Image tags                          │
└─────────────────────────────────────────────────────────────┘
```

---

## Output Formats

The version script supports multiple output formats for different consumers:

### 1. Plain Format (Default)

**Usage**: `./scripts/version.sh`

**Output**:
```
8.1.1-ib.1.abc1234
```

**Use Case**: Quick checks, simple scripts

---

### 2. Export Format

**Usage**: `./scripts/version.sh --format=export`

**Output**:
```bash
VERSION="8.1.1-ib.1.abc1234"
UPSTREAM_VERSION="8.1.1"
REVISION="1"
SHA="abc1234"
DIRTY="false"
TAG="8.1.1-ib.1.abc1234"
```

**Use Case**: Source in shell scripts: `eval $(./scripts/version.sh --format=export)`

---

### 3. JSON Format

**Usage**: `./scripts/version.sh --format=json`

**Output**:
```json
{
  "VERSION": "8.1.1-ib.1.abc1234",
  "UPSTREAM_VERSION": "8.1.1",
  "REVISION": "1",
  "SHA": "abc1234",
  "DIRTY": false,
  "TAG": "8.1.1-ib.1.abc1234"
}
```

**Use Case**: Parse in tools, CI systems

---

### 4. Make Format

**Usage**: `./scripts/version.sh --format=make`

**Output**:
```makefile
VERSION = 8.1.1-ib.1.abc1234
UPSTREAM_VERSION = 8.1.1
REVISION = 1
SHA = abc1234
DIRTY = false
TAG = 8.1.1-ib.1.abc1234
```

**Use Case**: Include in Makefile: `include version.mk`

---

### 5. GitHub Actions Format

**Usage**: `./scripts/version.sh --format=github`

**Output**:
```
VERSION=8.1.1-ib.1.abc1234
UPSTREAM_VERSION=8.1.1
REVISION=1
SHA=abc1234
DIRTY=false
TAG=8.1.1-ib.1.abc1234
```

**Use Case**: Append to `$GITHUB_OUTPUT` in workflow steps

---

## Version Lifecycle

### Scenario 1: Release Build (Git Tag)

```bash
# Developer creates release tag
git tag v8.1.1-ib.1
git push origin v8.1.1-ib.1

# CI detects tag, computes version
# Input: tag=v8.1.1-ib.1, sha=abc1234, clean tree
# Output: 8.1.1-ib.1.abc1234

# Docker image tagged: ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.abc1234
# Helm chart version: 8.1.1-ib.1.abc1234
# Helm chart appVersion: 8.1.1
```

---

### Scenario 2: Main Branch Build

```bash
# Developer merges PR to main
git checkout main
git pull

# CI builds from main branch
# Input: branch=main, sha=def5678, clean tree
# Output: 8.1.1-ib.main.def5678

# Docker image tagged: ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.main.def5678
#                     ghcr.io/infobloxopen/ib-schema-registry:latest
```

---

### Scenario 3: Feature Branch Build

```bash
# Developer pushes feature branch
git checkout -b feature/auth-improvements
git push origin feature/auth-improvements

# CI builds from feature branch
# Input: branch=feature/auth-improvements, sha=1a2b3c4, clean tree
# Output: 8.1.1-ib.feature-auth-improvements.1a2b3c4

# Docker image tagged: ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.feature-auth-improvements.1a2b3c4
```

---

### Scenario 4: Local Dirty Build

```bash
# Developer makes local changes without committing
echo "test" >> README.md

# Local build
make version
# Input: branch=main, sha=abc1234, dirty tree
# Output: 8.1.1-ib.main.abc1234.dirty

# Docker build tagged with dirty version
make build
# Image: ib-schema-registry:8.1.1-ib.main.abc1234.dirty
```

---

## References

- **SemVer 2.0**: https://semver.org/
- **OCI Image Spec**: https://github.com/opencontainers/image-spec/blob/main/image-layout.md
- **Docker Tag Naming**: https://docs.docker.com/engine/reference/commandline/tag/
- **Helm Chart Versioning**: https://helm.sh/docs/topics/charts/#the-chartyaml-file
