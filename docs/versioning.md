# Versioning Scheme

**Feature**: [specs/006-versioning-scheme/spec.md](../specs/006-versioning-scheme/spec.md)  
**Last Updated**: 2026-01-18

## Overview

The Infoblox Schema Registry uses a **unified versioning scheme** that ensures all artifacts (Docker images, Helm charts, build tags) share a consistent, traceable version identifier. This version format is **OCI-registry compatible** and includes commit traceability for reproducible builds.

---

## Version Format

```
<upstream>-ib.<suffix>.<sha>[.dirty]
```

### Components

| Component | Description | Example |
|-----------|-------------|---------|
| `<upstream>` | Upstream Confluent Schema Registry version (SemVer MAJOR.MINOR.PATCH) | `8.1.1` |
| `-ib.` | Infoblox identifier (literal constant) | `-ib.` |
| `<suffix>` | **Release number** (for tagged releases) OR **branch name** (for development builds) | `1`, `main`, `feature-auth` |
| `.<sha>` | Short Git commit SHA (7 lowercase hexadecimal characters) | `.abc1234` |
| `.dirty` | Optional suffix indicating uncommitted changes in working directory | `.dirty` |

---

## Version Examples

### Release Builds (Git Tags)

When you create a git tag following the pattern `v<upstream>-ib.<n>`, the version uses the release number:

```bash
# Git tag: v8.1.1-ib.1
# Version: 8.1.1-ib.1.abc1234

# Git tag: v8.1.1-ib.2 (second Infoblox build)
# Version: 8.1.1-ib.2.def5678
```

**Docker Image**:
```bash
docker pull ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.abc1234
```

**Helm Chart**:
```bash
helm install schema-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 8.1.1-ib.1.abc1234
```

---

### Main Branch Builds

Commits to the `main` branch produce development versions with the branch name:

```bash
# Branch: main
# Commit: abc1234
# Version: 8.1.1-ib.main.abc1234
```

**Docker Image**:
```bash
docker pull ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.main.abc1234
docker pull ghcr.io/infobloxopen/ib-schema-registry:latest  # Also tagged as latest
```

---

### Feature Branch Builds

Feature branches use the sanitized branch name as the suffix:

```bash
# Branch: feature/authentication
# Sanitized: feature-authentication
# Version: 8.1.1-ib.feature-authentication.abc1234

# Branch: bugfix/SCHEMA-123
# Sanitized: bugfix-schema-123
# Version: 8.1.1-ib.bugfix-schema-123.def5678
```

Branch name sanitization rules:
- Converted to lowercase
- Slashes (`/`) replaced with hyphens (`-`)
- Invalid characters removed (only `[a-z0-9._-]` allowed)
- Truncated to 50 characters maximum

---

### Dirty Builds (Local Development)

If you have uncommitted changes in your working directory, the version includes `.dirty`:

```bash
# Uncommitted changes present
# Version: 8.1.1-ib.main.abc1234.dirty
```

This prevents accidental deployment of un-versioned code.

---

## Why This Format?

### OCI Registry Compatibility

The previous versioning scheme used `+` (SemVer build metadata):
```
7.6.1+infoblox.1  ❌ Incompatible
```

**Problem**: OCI registries like GHCR (GitHub Container Registry) **do not support `+` in image tags**. GHCR URL-encodes `+` to `%2B`, causing errors and confusion.

**Solution**: Use `-` (SemVer prerelease identifiers) instead:
```
8.1.1-ib.1.abc1234  ✅ Compatible
```

### SemVer Compliance

The new format follows **SemVer 2.0 prerelease identifier** rules:
- `8.1.1-ib.1.abc1234` is a valid SemVer prerelease version
- Sorts correctly: `8.1.1-ib.1.abc1234` < `8.1.1-ib.2.def5678` < `8.1.1` (full release)
- Universally supported by Docker, Helm, and OCI registries

### Character Set Restrictions

Version strings only use **OCI-allowed characters**:
```
[A-Za-z0-9._-]
```

**Forbidden** characters: `+`, `/`, `\`, `:`, `@`, `#`, `%`, `&`, spaces

**Maximum length**: 128 characters (OCI specification limit)

---

## Version Lifecycle

### 1. Local Development

```bash
# Check your version
make version

# Example output:
# VERSION = 8.1.1-ib.feature-auth.abc1234.dirty
# UPSTREAM_VERSION = 8.1.1
# SHA = abc1234
# DIRTY = true

# Build with computed version
make build
```

---

### 2. Pull Request Builds

When you open a pull request, CI builds the image but **does not push** to the registry:

```bash
# Branch: feature/authentication
# Version: 8.1.1-ib.feature-authentication.abc1234
# Image built: ✅
# Image pushed: ❌ (PR validation only)
```

---

### 3. Main Branch Deployment

When your PR merges to `main`, CI builds and pushes the image:

```bash
# Branch: main
# Commit: def5678
# Version: 8.1.1-ib.main.def5678

# Docker images pushed:
# - ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.main.def5678
# - ghcr.io/infobloxopen/ib-schema-registry:latest

# Helm chart pushed:
# - oci://ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.main.def5678
```

---

### 4. Release Tagging

To create an official release, push a git tag:

```bash
# Determine upstream version
cd upstream/schema-registry
git describe --tags --abbrev=0
# Output: v8.1.1

# Create Infoblox release tag
cd ../..
git tag v8.1.1-ib.1
git push origin v8.1.1-ib.1

# CI builds and pushes:
# Version: 8.1.1-ib.1.9f8e7d6
# Docker: ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.9f8e7d6
# Helm: oci://ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.9f8e7d6
```

**Tag naming convention**: `v<upstream>-ib.<n>`
- `<upstream>`: Upstream Schema Registry version (without `v` prefix in version string)
- `<n>`: Infoblox revision number (starts at 1, increment for patches/rebuilds)

---

## Docker and Helm Version Synchronization

### Docker Images

Docker images are tagged with the **full version string**:

```bash
# OCI labels include:
org.opencontainers.image.version=8.1.1-ib.1.abc1234
org.opencontainers.image.revision=abc1234
org.infoblox.upstream.version=8.1.1
```

### Helm Charts

Helm charts use **two version fields**:

```yaml
# Chart.yaml
version: 8.1.1-ib.1.abc1234        # Full version (identifies chart artifact)
appVersion: "8.1.1"                 # Upstream version (shows application version)
```

**Why two fields?**
- `version`: Complete chart version with commit SHA (for traceability)
- `appVersion`: Clean upstream version (for user-facing documentation)

This allows users to see:
- **Which chart artifact** they're deploying (`version`)
- **Which Schema Registry version** is running (`appVersion`)

---

## Version Sorting and Precedence

According to SemVer 2.0, prerelease versions are compared lexically:

```
8.1.0-ib.1.abc1234
< 8.1.1-ib.1.abc1234       # Higher patch version
< 8.1.1-ib.2.def5678       # Higher revision number
< 8.1.1-ib.10.xyz9876      # Numeric: 10 > 2
< 8.1.1-ib.main.abc1234    # Alphanumeric sorts after numeric
< 8.1.1                    # Full release (no prerelease) is GREATER
```

**Key Rules**:
- Prerelease identifiers compare lexically
- Numeric-only identifiers compare as integers: `1 < 2 < 10`
- Alphanumeric identifiers compare as ASCII: `1 < main < z`
- Versions **without** prerelease are **greater** than versions with prerelease

---

## Commit Traceability

Every version includes a 7-character commit SHA, enabling:

### 1. Source Code Lookup

```bash
# From version string: 8.1.1-ib.1.abc1234
# Extract SHA: abc1234

# View commit in GitHub
https://github.com/infobloxopen/ib-schema-registry/commit/abc1234

# Or clone and inspect locally
git show abc1234
```

### 2. Reproducible Builds

```bash
# Check out exact commit
git checkout abc1234

# Rebuild from source
make build

# Verify image matches registry
docker pull ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.abc1234
docker inspect ib-schema-registry:latest | jq '.[0].Config.Labels'
```

### 3. Supply Chain Verification

```bash
# Verify SLSA provenance includes correct commit SHA
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.abc1234 \
  | jq '.payload | @base64d | fromjson | .predicate.invocation.configSource.digest.sha1'
```

---

## Frequently Asked Questions

### Why not use `+` (build metadata)?

**OCI registries don't reliably support `+` in tags**. GHCR (GitHub Container Registry) URL-encodes `+` to `%2B`, which breaks image pulls and causes confusion. SemVer prerelease identifiers (`-`) are universally supported.

---

### How do I find the commit for a specific version?

Extract the 7-character SHA from the version string:

```bash
# Version: 8.1.1-ib.1.abc1234
# SHA: abc1234

# View on GitHub
open https://github.com/infobloxopen/ib-schema-registry/commit/abc1234
```

---

### What's the difference between `8.1.1-ib.1.abc1234` and `8.1.1`?

- `8.1.1-ib.1.abc1234`: **Infoblox build** of upstream 8.1.1 with commit traceability
- `8.1.1`: **Upstream release** (no Infoblox modifications)

The Infoblox version includes our container image, Helm chart, and build infrastructure. The upstream version is the raw Confluent Schema Registry release.

---

### How do I upgrade to a new upstream version?

See [CONTRIBUTING.md](../CONTRIBUTING.md#updating-schema-registry-version) for the complete upgrade process.

---

### Can I use a custom version for local builds?

Yes! Override the `VERSION` variable:

```bash
make build VERSION=my-custom-version
```

The version script will still validate format compatibility.

---

### What happens if I have uncommitted changes?

The version will include `.dirty` suffix:

```bash
# With uncommitted changes
make version
# Output: 8.1.1-ib.main.abc1234.dirty
```

This prevents accidentally pushing un-versioned code to production.

---

### How do I create a patch release (e.g., `8.1.1-ib.2`)?

Increment the revision number in your git tag:

```bash
# First release
git tag v8.1.1-ib.1
git push origin v8.1.1-ib.1

# Patch release (configuration change, security update, etc.)
git tag v8.1.1-ib.2
git push origin v8.1.1-ib.2
```

The revision number indicates multiple Infoblox builds of the same upstream version.

---

## Troubleshooting

### Error: "Generated invalid version"

**Symptom**: CI build fails with version validation error.

**Cause**: Version string doesn't match required format or contains invalid characters.

**Solution**:
```bash
# Test version locally
make version
make version-validate

# Check for issues:
# - Invalid characters in branch name
# - Upstream submodule not initialized
# - Git repository in detached HEAD state
```

---

### Error: "GHCR rejects image tag with `+`"

**Symptom**: Cannot push image to GHCR, receives 400 Bad Request.

**Cause**: Legacy version format using `+` (build metadata) is not supported.

**Solution**: Upgrade to new versioning scheme. All new builds automatically use `-` format.

---

### Version shows "dev" or "unknown"

**Symptom**: Version computation returns `dev` or `unknown`.

**Cause**: Upstream submodule not initialized or Git repository issues.

**Solution**:
```bash
# Initialize submodule
git submodule update --init --recursive

# Verify submodule
cd upstream/schema-registry
git describe --tags --abbrev=0
```

---

## Technical Reference

For complete technical specification, algorithms, and validation rules, see:

- **Specification**: [specs/006-versioning-scheme/spec.md](../specs/006-versioning-scheme/spec.md)
- **Data Model**: [specs/006-versioning-scheme/data-model.md](../specs/006-versioning-scheme/data-model.md)
- **Version Format Contract**: [specs/006-versioning-scheme/contracts/version-format.md](../specs/006-versioning-scheme/contracts/version-format.md)
- **Implementation Plan**: [specs/006-versioning-scheme/plan.md](../specs/006-versioning-scheme/plan.md)

---

## Version Script Usage

The version computation is implemented in `scripts/version.sh`:

```bash
# Display version (plain text)
./scripts/version.sh

# Output formats
./scripts/version.sh --format=json     # JSON object
./scripts/version.sh --format=export   # Shell variables
./scripts/version.sh --format=make     # Makefile syntax
./scripts/version.sh --format=github   # GitHub Actions output

# Validate version
./scripts/validate-version.sh "8.1.1-ib.1.abc1234"

# Makefile integration
make version            # Display version information
make version-validate   # Validate version format
```

---

## Migration from Old Format

If you're upgrading from the old `<version>+infoblox.<n>` format, see:
- [Migration Guide](migration-versioning.md) (coming soon)
- [CHANGELOG.md](../CHANGELOG.md) for version history

**Old format** (deprecated):
```
7.6.1+infoblox.1  ❌
```

**New format** (current):
```
8.1.1-ib.1.abc1234  ✅
```
