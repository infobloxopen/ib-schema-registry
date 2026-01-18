# Contract: Version Mapping Rules

**Feature**: 005-helm-chart-automation  
**Date**: January 17, 2026

---

## Overview

This document defines the exact transformation rules for converting git references to Helm chart versions, ensuring consistency between Docker image tags and Helm chart versions.

---

## Transformation Table

### Git Tags (Semantic Versions)

| Git Tag | `github.ref` | Metadata Action Output | Docker Image Tag | Helm Chart Version | Helm Chart appVersion |
|---------|--------------|------------------------|------------------|--------------------|-----------------------|
| `v1.0.0` | `refs/tags/v1.0.0` | `1.0.0` | `1.0.0` | `1.0.0` | `"1.0.0"` |
| `v1.2.3` | `refs/tags/v1.2.3` | `1.2.3` | `1.2.3` | `1.2.3` | `"1.2.3"` |
| `v2.0.0-rc.1` | `refs/tags/v2.0.0-rc.1` | `2.0.0-rc.1` | `2.0.0-rc.1` | `2.0.0-rc.1` | `"2.0.0-rc.1"` |
| `v10.5.3` | `refs/tags/v10.5.3` | `10.5.3` | `10.5.3` | `10.5.3` | `"10.5.3"` |

**Rule**: Metadata action strips `v` prefix via `type=semver,pattern={{version}}`. Version passes through unchanged to both Docker tag and Helm chart version.

**Validation**: All versions MUST conform to semver 2.0.0 specification (Helm validates during packaging).

---

### Branch Builds (Development Versions)

| Branch | `github.ref` | `github.sha` | Metadata Action Output | Docker Image Tag | Helm Chart Version | Helm Chart appVersion |
|--------|--------------|--------------|------------------------|------------------|--------------------|-----------------------|
| `main` | `refs/heads/main` | `a1b2c3d...` | `main` | `sha-a1b2c3d` | `0.0.0-main.a1b2c3d` | `"0.0.0-main.a1b2c3d"` |
| `develop` | `refs/heads/develop` | `e4f5g6h...` | `develop` | `sha-e4f5g6h` | `0.0.0-develop.e4f5g6h` | `"0.0.0-develop.e4f5g6h"` |
| `feature-auth` | `refs/heads/feature-auth` | `i7j8k9l...` | `feature-auth` | `sha-i7j8k9l` | `0.0.0-feature-auth.i7j8k9l` | `"0.0.0-feature-auth.i7j8k9l"` |

**Rule**: Branch name from metadata-action is transformed to pre-release semver:
- Format: `0.0.0-<branch-name>.<short-sha>`
- Short SHA: First 7 characters of `github.sha`
- Semver pre-release identifier: `<branch-name>.<short-sha>`

**Validation**: 
- Branch name MUST NOT contain spaces or special characters incompatible with semver pre-release identifiers
- Short SHA MUST be exactly 7 characters (hex)
- Resulting version MUST parse as valid semver

**Transformation Code**:
```bash
VERSION="${{ steps.meta.outputs.version }}"  # e.g., "main"
SHORT_SHA="$(echo ${{ github.sha }} | cut -c1-7)"  # e.g., "a1b2c3d"

if [[ "$VERSION" != *"."* ]]; then
  # No dots detected = branch name
  VERSION="0.0.0-${VERSION}.${SHORT_SHA}"  # Result: "0.0.0-main.a1b2c3d"
fi
```

**Rationale**:
- `0.0.0` major version signals unreleased/development status
- Pre-release identifier sorts before any `1.0.0+` release in semver ordering
- Branch name provides human context
- Short SHA provides uniqueness and traceability to commit

---

### Pull Request Builds (Not Published)

| PR | `github.ref` | Metadata Action Output | Docker Image Tag | Helm Chart Version |
|----|--------------|------------------------|------------------|--------------------|
| PR #123 | `refs/pull/123/merge` | `pr-123` | (not pushed) | (not published) |

**Rule**: Helm chart publishing step is SKIPPED for pull request events via condition:
```yaml
if: github.event_name == 'push'
```

**Rationale**: PRs are for testing only; avoid cluttering registry with potentially unstable PR builds.

---

### SHA-Only Builds (Manual Triggers)

| Trigger | `github.ref` | Metadata Action Output | Docker Image Tag | Helm Chart Version | Notes |
|---------|--------------|------------------------|------------------|-----------------------|-------|
| Workflow dispatch | `refs/heads/<branch>` | `sha-a1b2c3d` | `sha-a1b2c3d` | `sha-a1b2c3d` | Treated as branch build if no tag |

**Rule**: If metadata-action outputs `sha-<hash>` format (7-char SHA with prefix), use as-is for both Docker tag and Helm chart version.

**Note**: Current metadata-action configuration may not produce this format; verify actual output during implementation.

---

## Version Comparison Examples

### Semver Ordering (Helm Default Behavior)

Helm uses semver comparison for version resolution. Example ordering from oldest to newest:

```
0.0.0-develop.abc1234       (branch build)
0.0.0-feature-xyz.def5678   (branch build)
0.0.0-main.9876543          (branch build)
1.0.0-rc.1                  (release candidate)
1.0.0                       (release)
1.0.1                       (patch release)
1.1.0                       (minor release)
2.0.0                       (major release)
```

**Implication**: Development versions (`0.0.0-*`) always sort before production releases, as expected.

---

## Edge Cases

### Case 1: Branch Name with Slashes (e.g., `feature/auth-improvements`)

**Problem**: Slashes in branch names may cause issues in semver pre-release identifiers or file paths.

**Solution**: Replace slashes with hyphens in version transformation:
```bash
VERSION="${{ steps.meta.outputs.version }}"  # e.g., "feature/auth-improvements"
VERSION="${VERSION//\//-}"  # Replace / with - → "feature-auth-improvements"
SHORT_SHA="$(echo ${{ github.sha }} | cut -c1-7)"
VERSION="0.0.0-${VERSION}.${SHORT_SHA}"  # Result: "0.0.0-feature-auth-improvements.abc1234"
```

**Status**: Recommended enhancement (not in initial implementation; document limitation if needed).

---

### Case 2: Tag with `+` Build Metadata (e.g., `v1.2.3+build.20260117`)

**Metadata Action Behavior**: `type=semver,pattern={{version}}` outputs `1.2.3` (strips build metadata per semver spec).

**Helm Chart Version**: `1.2.3` (build metadata lost)

**Impact**: Acceptable. Build metadata is informational only and not significant for version comparison per semver 2.0.0.

---

### Case 3: Non-Semver Tag (e.g., `release-2024-01`)

**Metadata Action Behavior**: `type=semver,pattern={{version}}` may fail to parse; falls back to `type=ref` output (full tag name).

**Result**: `release-2024-01` passed to Helm chart version.

**Validation**: Helm package will FAIL with error (invalid semver).

**Recommendation**: Enforce semver tag naming convention in repository (document in CONTRIBUTING.md).

---

### Case 4: Very Long Branch Names (>50 characters)

**Problem**: Semver pre-release identifiers have no strict length limit, but very long branch names may cause readability or tooling issues.

**Example**: `feature-implement-advanced-authentication-with-oauth2-and-saml` (58 chars)

**Result**: Chart version `0.0.0-feature-implement-advanced-authentication-with-oauth2-and-saml.abc1234` (70 chars)

**Impact**: Functionally valid but unwieldy. No truncation in initial implementation.

**Recommendation**: Encourage short branch names (document in contribution guidelines).

---

## Version Synchronization Verification

### Automated Check (Future Enhancement)

```bash
# In test job, verify version synchronization
DOCKER_VERSION=$(docker inspect ghcr.io/infobloxopen/ib-schema-registry:${{ steps.meta.outputs.version }} | \
  jq -r '.[0].Config.Labels."org.opencontainers.image.version"')

HELM_VERSION=$(helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version ${{ steps.meta.outputs.version }} && \
  tar -xzf ib-schema-registry-*.tgz && \
  grep "^version:" ib-schema-registry/Chart.yaml | awk '{print $2}')

if [ "$DOCKER_VERSION" != "$HELM_VERSION" ]; then
  echo "::error::Version mismatch! Docker: $DOCKER_VERSION, Helm: $HELM_VERSION"
  exit 1
fi

echo "✅ Version synchronization verified: $DOCKER_VERSION"
```

**Status**: Optional enhancement for increased confidence (not required for MVP).

---

## Documentation Requirements

### README.md

Add section documenting version synchronization:

```markdown
## Helm Chart Versions

Helm chart versions are automatically synchronized with Docker image versions:

- **Release tags** (e.g., `v1.2.3`): Chart version is `1.2.3`
- **Branch builds** (e.g., `main`): Chart version is `0.0.0-main.<short-sha>`

Example installation:

```bash
# Install specific release
helm install my-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3

# Install development build
helm install my-registry oci://ghcr.io/infobloxopen/ib-schema-registry --version 0.0.0-main.abc1234
```

### Helm Chart README.md

Add section explaining version format:

```markdown
## Versioning

This chart follows semantic versioning synchronized with the Schema Registry Docker image version:

- **Stable releases**: Semver format (e.g., `1.2.3`, `2.0.0-rc.1`)
- **Development builds**: Pre-release format (e.g., `0.0.0-main.abc1234`)
  - `0.0.0` indicates unreleased development version
  - Branch name (e.g., `main`) provides context
  - Short SHA (7 chars) provides commit traceability

Chart `appVersion` always matches the Docker image tag used in templates.
```

---

## Summary

This version mapping contract ensures:

1. **Exact synchronization** between Docker image tags and Helm chart versions
2. **Semver compliance** for all published charts
3. **Development version isolation** via `0.0.0-*` pre-release format
4. **Traceability** via short SHA inclusion in branch builds
5. **Predictable transformation** via clear rules and code examples

All transformations follow semver 2.0.0 specification and Helm version comparison behavior.
