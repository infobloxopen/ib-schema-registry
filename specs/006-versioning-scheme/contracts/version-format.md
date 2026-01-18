# Version Format Contract

**Feature**: [spec.md](../spec.md) | **Plan**: [../plan.md](../plan.md)  
**Date**: 2026-01-18

## Overview

This contract defines the exact format specifications, regex patterns, and test cases for the version string. It serves as the source of truth for validation and testing.

---

## Format Specification

### Complete Format

```
<upstream>-ib.<suffix>.<sha>[.dirty]
```

**Component Definitions**:

| Component | Description | Format | Example |
|-----------|-------------|--------|---------|
| `<upstream>` | Upstream SemVer version | `MAJOR.MINOR.PATCH` | `8.1.1` |
| `-ib.` | Infoblox identifier (literal) | `-ib.` | `-ib.` |
| `<suffix>` | Revision OR branch name | `[a-z0-9._-]+` | `1` or `main` or `feature-auth` |
| `<sha>` | Short Git commit SHA | `[a-z0-9]{7}` | `abc1234` |
| `.dirty` | Optional dirty indicator | `.dirty` or absent | `.dirty` |

---

## Regular Expressions

### Complete Version Pattern

```regex
^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$
```

**Explanation**:
- `^` - Start of string
- `[0-9]+` - Major version (one or more digits)
- `\.` - Literal dot
- `[0-9]+` - Minor version (one or more digits)
- `\.` - Literal dot
- `[0-9]+` - Patch version (one or more digits)
- `-ib\.` - Literal Infoblox identifier with dot
- `[a-z0-9._-]+` - Suffix (revision or branch, lowercase alphanumeric with dots, underscores, hyphens)
- `\.` - Literal dot
- `[a-z0-9]{7}` - SHA (exactly 7 lowercase hexadecimal characters)
- `(\.dirty)?` - Optional dirty suffix
- `$` - End of string

---

### Component Patterns

#### Upstream Version

```regex
^[0-9]+\.[0-9]+\.[0-9]+$
```

**Examples**:
- ✅ `8.1.1`
- ✅ `7.6.1`
- ✅ `10.0.0`
- ❌ `8.1` (missing patch)
- ❌ `01.02.03` (leading zeros)
- ❌ `8.1.1-rc1` (prerelease not allowed in upstream)

---

#### Suffix (Revision)

```regex
^[0-9]+$
```

**Examples**:
- ✅ `1`
- ✅ `2`
- ✅ `10`
- ❌ `01` (leading zero)
- ❌ `1.5` (not an integer)

---

#### Suffix (Branch Name, Sanitized)

```regex
^[a-z0-9._-]+$
```

**Requirements**:
- Lowercase only
- Alphanumeric, dots, underscores, hyphens
- Maximum 50 characters (recommended, not enforced by regex)
- Must not start or end with hyphen or dot (enforced by sanitization)

**Examples**:
- ✅ `main`
- ✅ `develop`
- ✅ `feature-auth`
- ✅ `bugfix-schema-123`
- ✅ `release-8.1.1`
- ❌ `Feature-Auth` (uppercase)
- ❌ `feature/auth` (slash not allowed)
- ❌ `feature auth` (space not allowed)

---

#### Commit SHA

```regex
^[a-z0-9]{7}$
```

**Examples**:
- ✅ `abc1234`
- ✅ `def5678`
- ✅ `1a2b3c4`
- ❌ `ABC1234` (uppercase)
- ❌ `abc123` (too short)
- ❌ `abc12345` (too long)
- ❌ `abcdefg` (not hexadecimal)

---

## Character Set Restrictions

### Allowed Characters

```
A-Z a-z 0-9 . _ -
```

**Character Classes**:
- Uppercase letters: `A-Z`
- Lowercase letters: `a-z`
- Digits: `0-9`
- Dot: `.`
- Underscore: `_`
- Hyphen: `-`

### Forbidden Characters

**Not Allowed**:
- Plus sign: `+` (OCI incompatible)
- Slash: `/` (path separator)
- Backslash: `\` (escape character)
- Colon: `:` (registry separator)
- At sign: `@` (digest separator)
- Hash: `#` (fragment identifier)
- Percent: `%` (URL encoding)
- Ampersand: `&` (URL parameter)
- Spaces and other whitespace
- Any special characters not listed as allowed

---

## Length Constraints

### Maximum Length

**Limit**: 128 characters (OCI registry specification)

**Breakdown**:
```
<upstream> : max 15 chars (e.g., "999.999.999" = 11 chars)
-ib.       : 4 chars (literal)
<suffix>   : max 50 chars (recommended)
.          : 1 char (literal)
<sha>      : 7 chars (fixed)
.dirty     : 6 chars (optional)
           ────────────────
Total      : ~83 chars typical, 128 max
```

**Validation**:
- Total string length must be ≤ 128 characters
- Recommended to keep suffix ≤ 50 characters to leave room

---

## Test Cases

### Valid Version Strings

#### Release Tags

```
8.1.1-ib.1.abc1234
7.6.1-ib.2.def5678
10.0.0-ib.1.1a2b3c4
8.1.1-ib.10.abc1234
```

#### Main Branch

```
8.1.1-ib.main.abc1234
7.6.1-ib.main.def5678
```

#### Feature Branches

```
8.1.1-ib.feature-auth.abc1234
8.1.1-ib.bugfix-schema-123.def5678
8.1.1-ib.release-8.1.1.abc1234
8.1.1-ib.hotfix-security.def5678
8.1.1-ib.my-feature.abc1234
```

#### Dirty Builds

```
8.1.1-ib.1.abc1234.dirty
8.1.1-ib.main.abc1234.dirty
8.1.1-ib.feature-auth.abc1234.dirty
```

#### Edge Cases (Valid)

```
8.1.1-ib.unknown.abc1234           # Detached HEAD fallback
8.1.1-ib.pr-123.abc1234             # PR branch
8.1.1-ib.renovate-update.abc1234    # Renovate bot branch
8.1.1-ib.dependabot-npm.abc1234     # Dependabot branch
```

---

### Invalid Version Strings

#### Format Violations

```
❌ 8.1.1+ib.1.abc1234               # Plus sign instead of hyphen
❌ 8.1.1-ib.1.ABC1234               # Uppercase SHA
❌ 8.1.1-ib.Feature-Auth.abc1234    # Uppercase in suffix
❌ 8.1.1-ib.1.abc123                # SHA too short
❌ 8.1.1-ib.1.abc12345              # SHA too long
❌ 8.1.1-ib.1                       # Missing SHA
❌ 8.1.1-ib.abc1234                 # Missing suffix
❌ 8.1.1-1.abc1234                  # Missing "-ib."
```

#### Character Set Violations

```
❌ 8.1.1-ib.feature/auth.abc1234    # Slash in suffix
❌ 8.1.1-ib.feature auth.abc1234    # Space in suffix
❌ 8.1.1-ib.feature@123.abc1234     # At sign in suffix
❌ 8.1.1-ib.feature#123.abc1234     # Hash in suffix
❌ 8.1.1-ib.feature%20.abc1234      # Percent encoding
```

#### Upstream Version Violations

```
❌ 8.1-ib.1.abc1234                 # Missing patch version
❌ 8-ib.1.abc1234                   # Missing minor and patch
❌ v8.1.1-ib.1.abc1234              # "v" prefix not allowed
❌ 8.1.1-rc1-ib.1.abc1234           # Upstream prerelease not allowed
```

#### Length Violations

```
❌ [version string > 128 characters]  # Exceeds OCI limit
```

---

## Validation Test Suite

### Test Cases for Regex

```bash
# test-version-format.sh

# Valid cases - should match
assert_match "8.1.1-ib.1.abc1234"
assert_match "8.1.1-ib.main.abc1234"
assert_match "8.1.1-ib.feature-auth.abc1234"
assert_match "8.1.1-ib.1.abc1234.dirty"
assert_match "10.0.0-ib.10.1a2b3c4"

# Invalid cases - should NOT match
assert_no_match "8.1.1+ib.1.abc1234"          # Plus sign
assert_no_match "8.1.1-ib.1.ABC1234"          # Uppercase
assert_no_match "8.1.1-ib.Feature.abc1234"    # Uppercase suffix
assert_no_match "8.1.1-ib.1.abc123"           # SHA too short
assert_no_match "8.1.1-ib.1.abc12345"         # SHA too long
assert_no_match "8.1.1-ib.1"                  # Missing SHA
assert_no_match "8.1.1-1.abc1234"             # Missing "ib"
assert_no_match "v8.1.1-ib.1.abc1234"         # "v" prefix
assert_no_match "8.1-ib.1.abc1234"            # Incomplete semver
```

### Test Cases for Character Set

```bash
# Valid characters
assert_valid_chars "8.1.1-ib.main.abc1234"
assert_valid_chars "8.1.1-ib.feature-auth_v2.abc1234"
assert_valid_chars "8.1.1-ib.1.abc1234.dirty"

# Invalid characters
assert_invalid_chars "8.1.1-ib.feature/auth.abc1234"    # Slash
assert_invalid_chars "8.1.1-ib.feature auth.abc1234"    # Space
assert_invalid_chars "8.1.1-ib.feature@123.abc1234"     # At sign
assert_invalid_chars "8.1.1-ib.feature#123.abc1234"     # Hash
assert_invalid_chars "8.1.1-ib.feature%20.abc1234"      # Percent
```

### Test Cases for Length

```bash
# Valid lengths
assert_valid_length "8.1.1-ib.1.abc1234"                # 23 chars
assert_valid_length "8.1.1-ib.main.abc1234"             # 26 chars
assert_valid_length "8.1.1-ib.very-long-feature-branch-name-here.abc1234"  # Long but valid

# Invalid lengths
assert_invalid_length "[generate 129-character string]"  # Exceeds limit
```

### Test Cases for SemVer Compliance

```bash
# Valid upstream versions
assert_valid_upstream "8.1.1-ib.1.abc1234"
assert_valid_upstream "10.0.0-ib.1.abc1234"
assert_valid_upstream "999.999.999-ib.1.abc1234"

# Invalid upstream versions
assert_invalid_upstream "8.1-ib.1.abc1234"              # Missing patch
assert_invalid_upstream "v8.1.1-ib.1.abc1234"           # "v" prefix
assert_invalid_upstream "01.02.03-ib.1.abc1234"         # Leading zeros
```

---

## Sorting and Comparison

### SemVer Sorting Rules

According to SemVer 2.0, prerelease versions are compared lexically. The following order is expected:

```
8.1.0-ib.1.abc1234
< 8.1.1-ib.1.abc1234         # Higher patch version
< 8.1.1-ib.2.abc1234         # Higher revision ("2" > "1")
< 8.1.1-ib.10.abc1234        # Lexical: "10" < "2" (strings), BUT "2" < "10" (numeric)
< 8.1.1-ib.main.abc1234      # Lexical: "main" > numeric
< 8.1.1                      # No prerelease (full release) is GREATER
```

**Important Notes**:
- Prerelease identifiers are compared lexically
- Numeric identifiers compare as integers: `1 < 2 < 10`
- Alphanumeric identifiers compare as ASCII: `1 < main < z`
- Version without prerelease is GREATER than version with prerelease

### Comparison Test Cases

```bash
# Test: 8.1.1-ib.1.abc1234 < 8.1.1-ib.2.def5678
assert_less_than "8.1.1-ib.1.abc1234" "8.1.1-ib.2.def5678"

# Test: 8.1.1-ib.2.abc1234 < 8.1.1-ib.10.def5678
assert_less_than "8.1.1-ib.2.abc1234" "8.1.1-ib.10.def5678"

# Test: 8.1.1-ib.1.abc1234 < 8.1.1-ib.main.abc1234
assert_less_than "8.1.1-ib.1.abc1234" "8.1.1-ib.main.abc1234"

# Test: 8.1.1-ib.main.abc1234 < 8.1.1
assert_less_than "8.1.1-ib.main.abc1234" "8.1.1"

# Test: 8.1.0-ib.1.abc1234 < 8.1.1-ib.1.abc1234
assert_less_than "8.1.0-ib.1.abc1234" "8.1.1-ib.1.abc1234"
```

---

## Compatibility Matrix

### OCI Registries

| Registry | Supports Version Format | Notes |
|----------|------------------------|-------|
| GHCR (GitHub Container Registry) | ✅ Yes | No `+` support, `-` works |
| Docker Hub | ✅ Yes | Standard OCI compliance |
| Google Artifact Registry | ✅ Yes | Standard OCI compliance |
| Azure Container Registry | ✅ Yes | Standard OCI compliance |
| AWS ECR | ✅ Yes | Standard OCI compliance |
| Harbor | ✅ Yes | Standard OCI compliance |
| Quay.io | ✅ Yes | Standard OCI compliance |

**Key**: All major OCI-compliant registries support the new version format. The old `+infoblox.1` format was rejected by some registries.

---

### Helm Chart Repositories

| Repository Type | Supports Version Format | Notes |
|-----------------|------------------------|-------|
| Helm OCI (GHCR) | ✅ Yes | Works with OCI-based Helm repos |
| Helm HTTP | ✅ Yes | Standard semver prerelease |
| Artifact Hub | ✅ Yes | Recognizes as prerelease |

---

### SemVer Tools

| Tool | Compatible | Notes |
|------|-----------|-------|
| `semver` (npm) | ✅ Yes | Recognizes prerelease format |
| `go-semver` | ✅ Yes | Valid SemVer 2.0 |
| `python-semver` | ✅ Yes | Valid SemVer 2.0 |
| Docker `metadata-action` | ✅ Yes | Use `type=raw` for custom format |

---

## Examples by Scenario

### Scenario 1: First Release

**Context**: First Infoblox release of upstream 8.1.1

**Git Tag**: `v8.1.1-ib.1`  
**Commit SHA**: `abc1234`  
**Clean Tree**: Yes

**Version**: `8.1.1-ib.1.abc1234`

**Validation**:
```bash
./scripts/validate-version.sh "8.1.1-ib.1.abc1234"
# Output: ✅ Valid version string
```

---

### Scenario 2: Patch Release

**Context**: Second Infoblox release of upstream 8.1.1 (patch applied)

**Git Tag**: `v8.1.1-ib.2`  
**Commit SHA**: `def5678`  
**Clean Tree**: Yes

**Version**: `8.1.1-ib.2.def5678`

**Validation**:
```bash
./scripts/validate-version.sh "8.1.1-ib.2.def5678"
# Output: ✅ Valid version string
```

---

### Scenario 3: Main Branch Build

**Context**: CI build from main branch

**Branch**: `main`  
**Commit SHA**: `1a2b3c4`  
**Clean Tree**: Yes

**Version**: `8.1.1-ib.main.1a2b3c4`

**Validation**:
```bash
./scripts/validate-version.sh "8.1.1-ib.main.1a2b3c4"
# Output: ✅ Valid version string
```

---

### Scenario 4: Feature Branch Build

**Context**: CI build from feature branch

**Branch**: `feature/authentication`  
**Sanitized**: `feature-authentication`  
**Commit SHA**: `9f8e7d6`  
**Clean Tree**: Yes

**Version**: `8.1.1-ib.feature-authentication.9f8e7d6`

**Validation**:
```bash
./scripts/validate-version.sh "8.1.1-ib.feature-authentication.9f8e7d6"
# Output: ✅ Valid version string
```

---

### Scenario 5: Dirty Local Build

**Context**: Local build with uncommitted changes

**Branch**: `main`  
**Commit SHA**: `abc1234`  
**Clean Tree**: No (modified files)

**Version**: `8.1.1-ib.main.abc1234.dirty`

**Validation**:
```bash
./scripts/validate-version.sh "8.1.1-ib.main.abc1234.dirty"
# Output: ✅ Valid version string
```

---

## Implementation Reference

### Bash Regex Test

```bash
#!/bin/bash

VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+-ib\.[a-z0-9._-]+\.[a-z0-9]{7}(\.dirty)?$'

validate_version() {
  local version="$1"
  
  if [[ $version =~ $VERSION_REGEX ]]; then
    echo "✅ Valid: $version"
    return 0
  else
    echo "❌ Invalid: $version"
    return 1
  fi
}

# Test cases
validate_version "8.1.1-ib.1.abc1234"                  # ✅
validate_version "8.1.1-ib.main.abc1234"               # ✅
validate_version "8.1.1-ib.feature-auth.abc1234"       # ✅
validate_version "8.1.1-ib.1.abc1234.dirty"            # ✅
validate_version "8.1.1+ib.1.abc1234"                  # ❌
validate_version "8.1.1-ib.1.ABC1234"                  # ❌
```

---

## References

- **SemVer 2.0 Specification**: https://semver.org/
- **OCI Image Spec (Tag Format)**: https://github.com/opencontainers/image-spec/blob/main/image-layout.md
- **Docker Tag Naming**: https://docs.docker.com/engine/reference/commandline/tag/#extended-description
- **Helm Chart Versioning**: https://helm.sh/docs/topics/charts/#the-chartyaml-file
- **POSIX Extended Regular Expressions**: https://en.wikibooks.org/wiki/Regular_Expressions/POSIX-Extended_Regular_Expressions
