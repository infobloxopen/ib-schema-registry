# Research: Versioning Scheme Implementation

**Feature**: [spec.md](spec.md) | **Plan**: [plan.md](plan.md)  
**Date**: 2026-01-18

## SemVer: Prerelease vs Build Metadata

### Build Metadata (`+metadata`)

**Format**: `<version>+<build>`  
**Example**: `7.6.1+infoblox.1`

**Characteristics**:
- Appended to version with `+` character
- Ignored during version precedence comparison
- Used for build identifiers, timestamps, commit SHAs
- **NOT part of version precedence**: `1.0.0+001` = `1.0.0+002` in precedence

**Problems for Our Use Case**:
- ❌ Docker/OCI registries have inconsistent `+` support
- ❌ Some registries treat `+` as invalid character in tags
- ❌ GHCR (GitHub Container Registry) URL-encodes `+` → `%2B` causing confusion
- ❌ Helm chart OCI repositories may reject `+` in version strings
- ❌ Not suitable when version needs to be part of artifact identifier

### Prerelease Identifiers (`-prerelease`)

**Format**: `<version>-<prerelease>`  
**Example**: `8.1.1-ib.1.abc1234`

**Characteristics**:
- Appended to version with `-` character
- **INCLUDED in version precedence comparison**
- Compared lexically (alphanumeric + hyphen allowed)
- Prerelease versions sort BEFORE release: `1.0.0-alpha` < `1.0.0`

**Advantages for Our Use Case**:
- ✅ Universally supported in Docker/OCI registries
- ✅ Safe for HTTP URLs (no encoding needed)
- ✅ Helm charts accept as valid semver
- ✅ Provides meaningful version ordering
- ✅ Can embed commit SHA as part of version identity

**Sorting Behavior**:
```
8.1.1-ib.1.abc1234       (release -ib.1)
< 8.1.1-ib.2.def5678     (release -ib.2)
< 8.1.1-ib.main.abc1234  (main branch, "main" > "2" lexically)
< 8.1.1                  (full release, no prerelease)
```

Note: `main` sorts AFTER `1`, `2` lexically, which means main branch builds sort after numbered releases in the same upstream version.

### Decision

**Use prerelease identifiers (`-`) exclusively** to ensure universal compatibility with OCI registries, Docker, and Helm.

## OCI Registry Tag Character Restrictions

### OCI Distribution Spec

Reference: [OCI Distribution Specification](https://github.com/opencontainers/distribution-spec/blob/main/spec.md)

**Tag Naming Rules**:
- Must match regex: `[a-zA-Z0-9_][a-zA-Z0-9._-]{0,127}`
- First character: alphanumeric or underscore
- Subsequent: alphanumeric, underscore, period, hyphen
- Maximum length: 128 characters
- Case-sensitive

**Characters Allowed**: `[A-Za-z0-9_.-]`  
**Characters NOT Allowed**: `+`, `/`, `\`, `:`, `@`, `#`, `%`, `&`, etc.

### Docker Hub Specifics

- Enforces OCI tag rules strictly
- URL-encodes special characters if present
- Recommends semantic versioning-compatible tags

### GHCR (GitHub Container Registry)

- Follows OCI spec
- **Does NOT support `+` in tags**
- URL-encodes `+` → `%2B` in web UI (causes confusion)
- Case-insensitive storage (lowercases tags internally)

### Recommendation

Stick to: `[A-Za-z0-9._-]` only  
Avoid: Any character outside this set, especially `+` and `/`

## Docker Metadata Action Compatibility

### docker/metadata-action@v5

**Purpose**: Generates Docker tags and labels from git refs and events

**Tag Generation Types**:
```yaml
tags:
  type=ref,event=branch        # Branch name as tag
  type=ref,event=pr            # PR number as tag
  type=semver,pattern={{version}}  # Git tag parsed as semver
  type=semver,pattern={{major}}.{{minor}}
  type=raw,value=<value>       # Custom static value
  type=sha                     # Git SHA as tag
```

**Key Findings**:
1. **type=semver** parses git tags expecting semver format
   - Works with: `v1.2.3`, `v1.2.3-alpha`, `v1.2.3-alpha.1`
   - **Fails with**: `v1.2.3+build` (build metadata stripped or causes issues)
   
2. **type=raw** allows complete control
   - Can use output from our version script
   - No parsing/transformation applied
   - Recommended approach for our scheme

3. **Outputs**:
   - `version`: Main version extracted
   - `tags`: Newline-separated list of full image tags
   - `labels`: OCI labels as KEY=VALUE pairs

### Integration Strategy

**Replace semver-based tags with raw TAG from version script**:
```yaml
- name: Compute version
  id: version
  run: ./scripts/version.sh --format=github >> $GITHUB_OUTPUT

- name: Docker metadata
  uses: docker/metadata-action@v5
  with:
    tags: |
      type=raw,value=${{ steps.version.outputs.TAG }}
      type=raw,value=latest,enable={{is_default_branch}}
```

This gives us full control over version format without relying on metadata-action's semver parser.

## Helm Chart Version Field Semver Requirements

### Helm Chart.yaml Schema

Reference: [Helm Chart Schema](https://helm.sh/docs/topics/charts/)

**Required Fields**:
- `version`: Chart version (semver 2.0)
- `appVersion`: Version of the app this chart contains (string, not validated)

**Version Field Rules**:
- MUST be valid SemVer 2.0
- Used for chart versioning and upgrades
- Supports prerelease: `1.2.3-alpha.1`
- Supports build metadata: `1.2.3+build.1` (but see OCI issues below)

**appVersion Field Rules**:
- String value, not validated
- Informational only
- Represents the version of the application being deployed
- Can be any format (doesn't have to be semver)

### Helm OCI Registry Considerations

When pushing Helm charts to OCI registries (e.g., GHCR):
- Chart version becomes OCI tag
- Subject to same OCI tag restrictions
- **`+` in version field causes issues** when used as OCI tag

### Helm Version Sorting

Helm sorts chart versions using semver precedence:
```
1.0.0-alpha < 1.0.0-beta < 1.0.0-rc.1 < 1.0.0
```

For our scheme:
```
8.1.1-ib.1.abc1234 < 8.1.1-ib.2.def5678
```

### Our Approach

**Chart `version` field**: Full version with SHA (`8.1.1-ib.1.abc1234`)
- Valid semver prerelease
- Works as OCI tag
- Provides commit traceability

**Chart `appVersion` field**: Upstream version only (`8.1.1`)
- User-facing application version
- Shows Confluent Schema Registry version clearly
- Omits packaging/build details

**Rationale**:
- `version` tracks the chart artifact (includes build commit)
- `appVersion` tracks the application inside (upstream version)
- Clear separation of concerns

## Git Tag Naming Conventions for Releases

### Current Upstream Practice

Confluent Schema Registry uses:
- `v7.6.1`, `v8.0.0`, `v8.1.1`, etc.
- Leading `v` prefix
- Semantic versioning
- No additional suffixes

### Our Convention

**Format**: `v<upstream>-ib.<n>`

**Examples**:
- First Infoblox build of 8.1.1: `v8.1.1-ib.1`
- Second Infoblox build of 8.1.1: `v8.1.1-ib.2`
- First Infoblox build of 8.2.0: `v8.2.0-ib.1`

**Rationale**:
1. `v` prefix: Follows git tag conventions
2. `<upstream>`: Preserves Confluent version (e.g., `8.1.1`)
3. `-ib.<n>`: Infoblox-specific revision marker
4. `<n>`: Integer starting at 1, increments for patches/rebuilds

**Revision Number `<n>`**:
- Starts at `1` for first build of an upstream version
- Increments to `2`, `3`, etc. for:
  - Hotfixes to the same upstream version
  - Infoblox-specific patches
  - Rebuild with updated base images
  - Security updates not requiring upstream upgrade

**Tag Lifecycle**:
```
v8.1.1-ib.1  → First release of Confluent 8.1.1
v8.1.1-ib.2  → Hotfix or rebuild of 8.1.1
v8.2.0-ib.1  → First release of Confluent 8.2.0 (new upstream)
```

### Tag Detection Logic

Version script must:
1. Check if current commit has annotated tag
2. Parse tag to extract `<upstream>` and `<n>`
3. Generate version: `<upstream>-ib.<n>.<sha>[.dirty]`

```bash
# If on tagged commit matching v<upstream>-ib.<n>
if tag=$(git describe --exact-match --tags 2>/dev/null); then
  # Extract: v8.1.1-ib.1 → upstream=8.1.1, n=1
  upstream="${tag#v}"           # Remove leading v
  upstream="${upstream%%-ib.*}" # Extract upstream part
  n="${tag##*-ib.}"             # Extract revision number
  sha=$(git rev-parse --short=7 HEAD)
  version="${upstream}-ib.${n}.${sha}"
fi
```

## Codebase Audit: Version Usage Locations

### Files Containing Version References

**Build Configuration**:
- `Makefile` - VERSION, LOCAL_VERSION variables
- `Dockerfile` - VERSION, UPSTREAM_VERSION args/labels
- `.github/workflows/build-image.yml` - Version extraction and usage

**Documentation**:
- `README.md` - Installation examples with versions
- `CONTRIBUTING.md` - Release process
- `helm/ib-schema-registry/README.md` - Chart version examples
- `helm/ib-schema-registry/values.yaml` - Image tag comments

**Helm Chart**:
- `helm/ib-schema-registry/Chart.yaml` - version and appVersion fields

**Upstream Tracking**:
- `upstream/schema-registry/` - Submodule with upstream tags

### Search Results for `+infoblox`

```bash
$ grep -r "+infoblox" . --exclude-dir=.git --exclude-dir=upstream
./Makefile:LOCAL_VERSION ?= $(VERSION)+infoblox.1
./.github/workflows/build-image.yml:      echo "local_version=${UPSTREAM_VERSION}+infoblox.1" >> $GITHUB_OUTPUT
```

**Locations to update**: 2 files

### Search Results for `LOCAL_VERSION`

```bash
$ grep -r "LOCAL_VERSION" . --exclude-dir=.git --exclude-dir=upstream
./Makefile:LOCAL_VERSION ?= $(VERSION)+infoblox.1
./Makefile:            --build-arg VERSION=$(LOCAL_VERSION) \
```

**Locations to update**: 2 references in 1 file

### Search Results for Version-Related Patterns

**`metadata-action`**: `.github/workflows/build-image.yml`
- Line 48: `uses: docker/metadata-action@v5`
- Lines 50-58: Tag generation configuration

**`VERSION` in workflows**: `.github/workflows/build-image.yml`
- Line 80: `VERSION=${{ steps.version.outputs.local_version }}`
- Line 303: `VERSION="${{ steps.meta.outputs.version }}"`

**`0.0.0-` transformation**: `.github/workflows/build-image.yml`
- Line 310: `VERSION="0.0.0-${VERSION}.${SHORT_SHA}"`

### Files Requiring Updates

| File | Changes Needed |
|------|---------------|
| `Makefile` | Replace VERSION extraction, remove LOCAL_VERSION, add version targets |
| `.github/workflows/build-image.yml` | Add version script step, update metadata-action, remove old version logic |
| `Dockerfile` | Update VERSION arg usage, add UPSTREAM_VERSION label |
| `README.md` | Add Versioning section, update examples |
| `CONTRIBUTING.md` | Update release process documentation |
| `helm/ib-schema-registry/Chart.yaml` | Dynamic updates in CI (no source changes) |
| `helm/ib-schema-registry/README.md` | Update version examples |
| `helm/ib-schema-registry/values.yaml` | Update image.tag comments |

### New Files to Create

| File | Purpose |
|------|---------|
| `scripts/version.sh` | Version computation script |
| `scripts/validate-version.sh` | Version format validation |
| `scripts/test-version.sh` | Unit tests for version script |
| `docs/versioning.md` | Comprehensive versioning guide |
| `docs/migration-versioning.md` | Migration guide from old format |

## Summary & Recommendations

### Key Decisions

1. **Use SemVer prerelease identifiers** (`-suffix`) instead of build metadata (`+suffix`)
2. **Version format**: `<upstream>-ib.<suffix>.<sha>[.dirty]`
3. **Git tag format**: `v<upstream>-ib.<n>` for releases
4. **Character set**: `[A-Za-z0-9._-]` only
5. **Helm versioning**: Chart version = full TAG, appVersion = upstream only

### Implementation Priorities

1. **Critical Path**: Version script → Makefile → CI workflow
2. **Documentation**: Parallel with implementation
3. **Testing**: After script and CI integration
4. **Migration**: Final phase before merge

### Risk Mitigation

- Test version script thoroughly before CI integration
- Validate OCI registry acceptance with test images
- Document migration path clearly
- Plan for rollback if issues arise

### Open Questions Resolved

- **Revision number source**: Extract from git tag (`v8.1.1-ib.2` → `2`)
- **Helm appVersion**: Use upstream version only for clarity
- **Backward compatibility**: Clean break, no dual-format tagging
- **Latest tag**: Continue pointing to main, add `stable` for releases if needed
