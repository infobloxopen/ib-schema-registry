# Implementation Plan: Unified Versioning Scheme

**Branch**: `006-versioning-scheme` | **Date**: 2026-01-18 | **Spec**: [spec.md](spec.md)

## Summary

Replace the current versioning scheme (`<upstream>+infoblox.1`) with a SemVer prerelease-based scheme (`<upstream>-ib.<n>.<sha>[.dirty]`) that provides commit traceability while maintaining OCI registry compatibility. The new scheme avoids the `+` character (build metadata) that causes issues with Docker/OCI tags and instead uses semver prerelease identifiers exclusively.

**Current State**: Version is `<upstream>+infoblox.1` (e.g., `7.6.1+infoblox.1`), extracted from upstream submodule tags.  
**Target State**: Version is `<upstream>-ib.<suffix>.<sha>[.dirty]` where suffix is `main` for main branch, `<n>` for release tags, or sanitized branch name for feature branches.

## Technical Context

**Language/Version**: Shell (bash), Make, GitHub Actions YAML  
**Primary Dependencies**: git, docker buildx, helm, sed  
**Storage**: N/A (versioning metadata only)  
**Testing**: Shell script unit tests, CI validation, semver parser validation  
**Target Platform**: Linux (CI), macOS (local development)  
**Project Type**: Container build tooling  
**Performance Goals**: Version computation <1 second  
**Constraints**: Must work offline (no network), must produce OCI-compatible tags  
**Scale/Scope**: Single script, 4 workflow updates, 3 documentation files

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Multi-arch portability**: Version script uses POSIX sh where possible; Makefile portable across macOS/Linux
- [x] **Base image pluggability**: N/A (versioning logic, not image build)
- [x] **Distroless compatibility**: N/A (versioning logic, not runtime)
- [x] **Supply-chain security**: 
  - [x] Version script runs as non-root (no privilege escalation)
  - [x] No external downloads (pure git operations)
  - [x] OCI labels updated to include new version format
- [x] **Licensing compliance**: No upstream code modification (versioning is metadata only)
- [x] **Repository ergonomics**: `make version` target added; documented in README
- [x] **Testing validation**: Version script tested with unit tests; CI validates output format

**Violations**: None

## Project Structure

### Documentation (this feature)
```
specs/006-versioning-scheme/
├── spec.md                    # Feature specification (exists)
├── plan.md                    # This implementation plan
├── research.md                # Version format research (to create)
├── data-model.md              # Version entity definitions (to create)
├── quickstart.md              # Testing guide (to create)
├── tasks.md                   # Implementation task tracking (to create)
├── checklists/
│   └── requirements.md        # Spec validation (exists)
└── contracts/
    └── version-format.md      # Version string format contract (to create)
```

### Implementation Files
```
scripts/
├── version.sh                 # NEW: Version computation script
└── validate-version.sh        # NEW: Version format validation

Makefile                       # UPDATE: Add version target, use version.sh
.github/workflows/
└── build-image.yml            # UPDATE: Use version.sh, update Helm chart logic

helm/ib-schema-registry/
├── Chart.yaml                 # UPDATE: Use new version format
└── values.yaml                # UPDATE: Documentation updates

README.md                      # UPDATE: Versioning section
CONTRIBUTING.md                # UPDATE: Release tagging conventions
docs/
└── versioning.md              # NEW: Detailed versioning guide
```

## Phase 0: Research & Design

### Goals
- Finalize version format for all scenarios
- Design version script API (inputs/outputs)
- Identify all locations using version strings
- Define test cases for edge cases

### Tasks

**T001**: Create `research.md` documenting:
- Comparison of semver prerelease vs build metadata
- OCI registry tag character restrictions
- Docker metadata-action compatibility
- Helm chart version field semver requirements
- Git tag naming conventions for releases

**T002**: Create `data-model.md` defining:
- Version String entity (format, validation rules)
- Upstream Version extraction algorithm
- SHA computation method
- Dirty detection logic
- Branch name sanitization rules

**T003**: Create `contracts/version-format.md` specifying:
- Regex pattern for valid version strings
- Examples for each scenario (release, main, feature, dirty)
- Character set restrictions
- Maximum length constraints

**T004**: Audit codebase for version usage:
- Grep for `VERSION`, `TAG`, `+infoblox`, `metadata-action`
- Document all files that reference versioning
- Identify Makefile variables to update
- Identify workflow steps to update

**Deliverables**:
- research.md, data-model.md, contracts/version-format.md
- Audit report of version usage locations

---

## Phase 1: Version Computation Script

### Goals
- Create standalone version computation script
- Support all version scenarios (release, main, feature, dirty)
- Provide structured output for consumption by Make/CI

### Tasks

**T005**: Create `scripts/version.sh` with functions:
- `get_upstream_version()`: Extract from upstream/schema-registry tags
- `get_short_sha()`: `git rev-parse --short=7 HEAD`
- `detect_dirty()`: Check `git status --porcelain`
- `get_branch_name()`: `git rev-parse --abbrev-ref HEAD`
- `sanitize_branch()`: Convert invalid chars to hyphens, truncate to 50
- `compute_version()`: Main entry point, returns full version string

**T006**: Implement version logic in `scripts/version.sh`:
```bash
# If current commit has tag matching v<upstream>-ib.<n>
if tag=$(git describe --exact-match --tags 2>/dev/null); then
  # Extract n from tag, format: <upstream>-ib.<n>.<sha>[.dirty]
  version="${upstream}-ib.${n}.${sha}${dirty}"
# Else if on main branch
elif [[ "$branch" == "main" ]]; then
  version="${upstream}-ib.main.${sha}${dirty}"
# Else feature branch
else
  sanitized=$(sanitize_branch "$branch")
  version="${upstream}-ib.${sanitized}.${sha}${dirty}"
fi
```

**T007**: Add output modes to `scripts/version.sh`:
- `--format=export`: Shell variable exports for sourcing
- `--format=json`: JSON object for CI consumption
- `--format=make`: Makefile variable syntax
- `--format=github`: GitHub Actions output syntax
- Default: Plain TAG output

**T008**: Handle edge cases in `scripts/version.sh`:
- Missing upstream submodule → fallback to VERSION file or error
- Git tag without `-ib.N` suffix → default to `-ib.1`
- Detached HEAD state → use SHA, mark as `detached` branch
- Shallow clone (CI) → ensure `git describe` works with `--always`

**T009**: Add validation function `validate_version()`:
- Check character set `[A-Za-z0-9_.-]`
- Verify semver prerelease format using regex
- Maximum length check (255 chars for OCI tags)
- Return exit code 0 if valid, 1 if invalid

**T010**: Create `scripts/validate-version.sh`:
- Wrapper for external validation (called by CI)
- Uses `semver` tool if available (optional dependency)
- Validates against version format contract
- Outputs human-readable error messages

**Deliverables**:
- `scripts/version.sh` (executable, tested)
- `scripts/validate-version.sh` (executable)
- Unit tests for version computation edge cases

---

## Phase 2: Makefile Integration

### Goals
- Replace hardcoded VERSION variables with version script
- Maintain backward compatibility for manual overrides
- Add `make version` target for inspection

### Tasks

**T011**: Update Makefile version variables:
```makefile
# Old:
# VERSION ?= $(shell cd upstream/schema-registry && git describe --tags --abbrev=0 || echo "dev")
# LOCAL_VERSION ?= $(VERSION)+infoblox.1

# New:
COMPUTED_VERSION := $(shell ./scripts/version.sh)
VERSION ?= $(COMPUTED_VERSION)
TAG ?= $(VERSION)
UPSTREAM_VERSION := $(shell ./scripts/version.sh --upstream-only)
```

**T012**: Remove `LOCAL_VERSION` variable:
- Replace all references to `LOCAL_VERSION` with `VERSION`
- Update `BUILD_ARGS` to use `VERSION` consistently
- Update OCI labels to use new version format

**T013**: Add `make version` target:
```makefile
.PHONY: version
version: ## Display computed version information
	@echo "Version Information:"
	@./scripts/version.sh --format=make | column -t -s "="
	@echo ""
	@echo "Full version string: $(VERSION)"
```

**T014**: Add `make version-validate` target:
```makefile
.PHONY: version-validate
version-validate: ## Validate version format
	@./scripts/validate-version.sh "$(VERSION)"
	@echo "✓ Version format valid: $(VERSION)"
```

**T015**: Update `make help` output:
- Add version targets to help text
- Update examples to show new version format
- Document `VERSION` override capability

**T016**: Test Makefile changes:
- `make version` from main branch → `<upstream>-ib.main.<sha>`
- `make version` from feature branch → `<upstream>-ib.<branch>.<sha>`
- `make version` with dirty tree → includes `.dirty`
- `make build VERSION=custom` → override works

**Deliverables**:
- Updated Makefile with version script integration
- New `version` and `version-validate` targets
- Tested on macOS and Linux

---

## Phase 3: GitHub Actions Workflow Updates

### Goals
- Replace docker/metadata-action version logic with version script
- Update Helm chart versioning to use new format
- Ensure version consistency across Docker and Helm artifacts

### Tasks

**T017**: Update `.github/workflows/build-image.yml` - Add version computation step:
```yaml
- name: Compute version
  id: compute-version
  run: |
    chmod +x scripts/version.sh
    ./scripts/version.sh --format=github >> $GITHUB_OUTPUT
    # Outputs: VERSION, UPSTREAM_VERSION, SHA, DIRTY, TAG
```

**T018**: Update docker/metadata-action step:
```yaml
- name: Docker metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
    tags: |
      type=raw,value=${{ steps.compute-version.outputs.TAG }}
      type=raw,value=latest,enable={{is_default_branch}}
    labels: |
      org.opencontainers.image.version=${{ steps.compute-version.outputs.TAG }}
      org.opencontainers.image.revision=${{ steps.compute-version.outputs.SHA }}
      org.infoblox.upstream.version=${{ steps.compute-version.outputs.UPSTREAM_VERSION }}
```

**T019**: Remove old version extraction step:
```yaml
# DELETE:
# - name: Get upstream version
#   id: version
#   run: |
#     cd upstream/schema-registry
#     UPSTREAM_VERSION=$(git describe --tags --abbrev=0 || echo "dev")
#     echo "upstream_version=${UPSTREAM_VERSION}" >> $GITHUB_OUTPUT
#     echo "local_version=${UPSTREAM_VERSION}+infoblox.1" >> $GITHUB_OUTPUT
```

**T020**: Update Docker build step:
```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    build-args: |
      VERSION=${{ steps.compute-version.outputs.TAG }}
      UPSTREAM_VERSION=${{ steps.compute-version.outputs.UPSTREAM_VERSION }}
      REVISION=${{ steps.compute-version.outputs.SHA }}
```

**T021**: Update Helm chart packaging step:
```yaml
- name: Package and publish Helm chart
  run: |
    VERSION="${{ steps.compute-version.outputs.TAG }}"
    
    # Update Chart.yaml with computed version
    sed -i "s/^version:.*/version: ${VERSION}/" helm/ib-schema-registry/Chart.yaml
    sed -i "s/^appVersion:.*/appVersion: \"${{ steps.compute-version.outputs.UPSTREAM_VERSION }}\"/" helm/ib-schema-registry/Chart.yaml
    
    # Note: appVersion uses upstream version (user-facing app version)
    # Chart version uses full TAG (packaging version with commit info)
```

**T022**: Remove branch name transformation logic:
```yaml
# DELETE:
# if [[ "$VERSION" != *"."* ]]; then
#   SHORT_SHA="$(echo ${{ github.sha }} | cut -c1-7)"
#   VERSION="0.0.0-${VERSION}.${SHORT_SHA}"
# fi
```

**T023**: Add version validation step:
```yaml
- name: Validate version format
  run: |
    chmod +x scripts/validate-version.sh
    ./scripts/validate-version.sh "${{ steps.compute-version.outputs.TAG }}"
```

**T024**: Update workflow comments and documentation:
- Add comments explaining new version scheme
- Document why `+` is avoided (OCI compatibility)
- Link to versioning documentation

**Deliverables**:
- Updated `.github/workflows/build-image.yml`
- Removed `0.0.0-main.<sha>` transformation logic
- Version computation centralized in script

---

## Phase 4: Documentation Updates

### Goals
- Document new versioning scheme in README
- Update examples to use new format
- Create comprehensive versioning guide

### Tasks

**T025**: Update `README.md` - Add Versioning section:
```markdown
## Versioning

This project uses a SemVer-compatible versioning scheme that preserves the upstream Confluent Schema Registry version while adding Infoblox-specific metadata:

**Format**: `<upstream>-ib.<suffix>.<sha>[.dirty]`

**Examples**:
- Release: `8.1.1-ib.1.abc1234` (git tag `v8.1.1-ib.1`)
- Release (2nd build): `8.1.1-ib.2.def5678` (git tag `v8.1.1-ib.2`)
- Main branch: `8.1.1-ib.main.abc1234`
- Feature branch: `8.1.1-ib.feature-auth.abc1234`
- Dirty build: `8.1.1-ib.main.abc1234.dirty`

**Why not use `+` for build metadata?**
Docker and OCI registries have inconsistent support for the `+` character in tags. We use SemVer prerelease identifiers (`-suffix`) instead of build metadata (`+suffix`) to ensure universal compatibility.

**Version Components**:
- `<upstream>`: Confluent Schema Registry version (e.g., `8.1.1`)
- `-ib.<n>`: Infoblox revision number for releases (e.g., `-ib.1`, `-ib.2`)
- `-ib.main`: Main branch development builds
- `-ib.<branch>`: Feature branch builds (branch name sanitized)
- `.<sha>`: 7-character git commit SHA
- `.dirty`: Uncommitted changes present (local builds only)

**Local version check**:
```bash
make version
```
```

**T026**: Update installation examples in README.md:
```markdown
# Old:
# docker pull ghcr.io/infobloxopen/ib-schema-registry:v7.6.1
# helm install ... --version 1.2.3

# New:
docker pull ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.1.abc1234
helm install schema-registry oci://ghcr.io/infobloxopen/ib-schema-registry \
  --version 8.1.1-ib.1.abc1234
```

**T027**: Update `CONTRIBUTING.md` - Release process:
```markdown
## Creating a Release

1. **Determine version**: Check upstream Schema Registry version:
   ```bash
   cd upstream/schema-registry
   git describe --tags
   # Example output: v8.1.1
   ```

2. **Create release tag**:
   ```bash
   # First release for upstream 8.1.1
   git tag -a v8.1.1-ib.1 -m "Release 8.1.1-ib.1"
   
   # If patching the same upstream version
   git tag -a v8.1.1-ib.2 -m "Release 8.1.1-ib.2 (hotfix)"
   ```

3. **Push tag**:
   ```bash
   git push origin v8.1.1-ib.1
   ```

4. **CI builds automatically**: Docker image and Helm chart will be published with version `8.1.1-ib.1.<sha>`.

**Tag naming convention**: `v<upstream>-ib.<n>` where `<n>` is an integer starting at 1, incrementing for each Infoblox-specific release of the same upstream version.
```

**T028**: Create `docs/versioning.md` with comprehensive guide:
- Detailed format specification
- Version component breakdown
- Semver sorting behavior explanation
- FAQ section (Why no `+`? How to find commit from version?)
- Troubleshooting guide (dirty builds, missing upstream)

**T029**: Update `helm/ib-schema-registry/README.md`:
- Replace old version examples with new format
- Add section explaining Chart version vs appVersion
- Document version synchronization with Docker image

**T030**: Update `helm/ib-schema-registry/values.yaml` comments:
```yaml
image:
  repository: ghcr.io/infobloxopen/ib-schema-registry
  pullPolicy: IfNotPresent
  # Overrides the image tag whose default is the chart appVersion.
  # The appVersion tracks the upstream Confluent Schema Registry version.
  # For full version with commit SHA, see the chart version field.
  # Example: appVersion "8.1.1", chart version "8.1.1-ib.1.abc1234"
  tag: ""
```

**Deliverables**:
- Updated README.md with Versioning section
- Updated CONTRIBUTING.md with release process
- New `docs/versioning.md` comprehensive guide
- Updated Helm chart documentation

---

## Phase 5: Remove Old Versioning References

### Goals
- Clean up all references to old `+infoblox.1` format
- Remove version transformation logic
- Ensure no hardcoded versions remain

### Tasks

**T031**: Search and replace `+infoblox` references:
```bash
grep -r "+infoblox" . --exclude-dir=.git
# Replace all occurrences with new format or remove
```

**T032**: Remove `LOCAL_VERSION` from all files:
- Makefile (already done in Phase 2)
- Any scripts or documentation mentioning it

**T033**: Update Dockerfile version labels:
```dockerfile
# Old:
# LABEL org.opencontainers.image.version="${VERSION}"

# New (if VERSION arg is <upstream>-ib.<suffix>.<sha>):
LABEL org.opencontainers.image.version="${VERSION}" \
      org.infoblox.upstream.version="${UPSTREAM_VERSION}"
```

**T034**: Remove metadata-action semver type tags:
```yaml
# DELETE (unless still useful for backward compat):
# type=semver,pattern={{version}}
# type=semver,pattern={{major}}.{{minor}}
# type=semver,pattern={{major}}
```

**T035**: Audit CHANGELOG.md or similar:
- Update any version references to show migration
- Document version scheme change

**T036**: Update issue templates if they mention versions:
- Replace example versions with new format

**Deliverables**:
- All `+infoblox` references removed
- Consistent version format throughout repository
- No hardcoded version examples in old format

---

## Phase 6: Testing & Validation

### Goals
- Verify version computation works in all scenarios
- Validate version format compliance
- Test end-to-end CI/CD pipeline

### Tasks

**T037**: Create `scripts/test-version.sh`:
```bash
#!/bin/bash
# Unit tests for version.sh

test_main_branch() {
  # Mock git commands, verify output matches expected format
}

test_release_tag() {
  # Verify v8.1.1-ib.1 → 8.1.1-ib.1.<sha>
}

test_feature_branch() {
  # Verify sanitization: feature/auth → feature-auth
}

test_dirty_detection() {
  # Create dirty state, verify .dirty suffix
}

run_all_tests
```

**T038**: Add version validation to CI:
```yaml
- name: Validate version format
  run: |
    VERSION=$(./scripts/version.sh)
    echo "Computed version: $VERSION"
    
    # Check character set
    if ! echo "$VERSION" | grep -E '^[A-Za-z0-9._-]+$'; then
      echo "Error: Invalid characters in version"
      exit 1
    fi
    
    # Check semver prerelease format
    if ! echo "$VERSION" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[A-Za-z0-9.-]+$'; then
      echo "Error: Invalid semver prerelease format"
      exit 1
    fi
```

**T039**: Test local builds:
```bash
# Test main branch
git checkout main
make version
# Expected: <upstream>-ib.main.<sha>

# Test feature branch
git checkout -b test/versioning-feature
make version
# Expected: <upstream>-ib.test-versioning-feature.<sha>

# Test dirty state
echo "test" >> README.md
make version
# Expected: <upstream>-ib.test-versioning-feature.<sha>.dirty

# Test release tag
git checkout main
git tag v8.1.1-ib.1
make version
# Expected: 8.1.1-ib.1.<sha>
```

**T040**: Test CI pipeline:
```bash
# Push feature branch → verify version includes branch name
# Push to main → verify version uses -ib.main
# Create tag v8.1.1-ib.1 → verify version uses -ib.1
```

**T041**: Validate OCI registry acceptance:
```bash
# Push test image with new version format
docker buildx build --platform linux/amd64 \
  -t ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.test.abc1234 \
  --push .

# Pull to verify
docker pull ghcr.io/infobloxopen/ib-schema-registry:8.1.1-ib.test.abc1234
```

**T042**: Test Helm chart versioning:
```bash
# Verify Chart.yaml version matches Docker tag
helm show chart oci://ghcr.io/infobloxopen/ib-schema-registry \
  --version 8.1.1-ib.test.abc1234

# Check version and appVersion fields
```

**Deliverables**:
- `scripts/test-version.sh` with comprehensive tests
- CI validation pipeline
- Manual test results documented

---

## Phase 7: Migration & Rollout

### Goals
- Plan migration from old to new versioning
- Document breaking changes
- Provide upgrade path for users

### Tasks

**T043**: Create migration guide in `docs/migration-versioning.md`:
```markdown
# Versioning Scheme Migration Guide

## What's Changing

**Old format**: `<upstream>+infoblox.1` (e.g., `7.6.1+infoblox.1`)  
**New format**: `<upstream>-ib.<n>.<sha>` (e.g., `8.1.1-ib.1.abc1234`)

## Why the Change

The `+` character (SemVer build metadata) is not reliably supported by Docker/OCI registries. The new format uses SemVer prerelease identifiers (`-`) which are universally compatible.

## Impact

- **Docker images**: New tags will use new format
- **Helm charts**: Chart versions will match Docker tags
- **Git tags**: Must follow new pattern `v<upstream>-ib.<n>`

## Upgrade Path

1. **Existing deployments**: Continue working (old images not affected)
2. **New deployments**: Use new version format
3. **Tag naming**: Future releases use `v<upstream>-ib.<n>` format

## Examples

| Old Tag | New Tag | Git Tag |
|---------|---------|---------|
| `7.6.1+infoblox.1` | `8.1.1-ib.1.abc1234` | `v8.1.1-ib.1` |
| `main` | `8.1.1-ib.main.abc1234` | N/A (branch) |
```

**T044**: Update PR template or CHANGELOG:
- Document version scheme change
- Link to migration guide
- Highlight breaking change for release process

**T045**: Create announcement draft:
- Explain why change is necessary (OCI compatibility)
- Show before/after examples
- Link to documentation

**T046**: Plan backward compatibility (if needed):
- Decide if old format images should be tagged with aliases
- Document deprecation timeline if maintaining both formats temporarily

**T047**: Update CI to tag images with both formats (optional transition period):
```yaml
tags: |
  type=raw,value=${{ steps.compute-version.outputs.TAG }}
  type=raw,value=${{ steps.compute-version.outputs.UPSTREAM_VERSION }}+infoblox.1,enable=${{ github.event_name == 'push' && github.ref == 'refs/heads/main' }}
```

**Deliverables**:
- Migration guide document
- Announcement draft
- Backward compatibility plan (if needed)

---

## Task Summary

| Phase | Tasks | Priority | Estimated Effort |
|-------|-------|----------|------------------|
| Phase 0: Research | T001-T004 | P1 | 4 hours |
| Phase 1: Version Script | T005-T010 | P1 | 8 hours |
| Phase 2: Makefile | T011-T016 | P1 | 4 hours |
| Phase 3: CI Workflow | T017-T024 | P1 | 6 hours |
| Phase 4: Documentation | T025-T030 | P2 | 6 hours |
| Phase 5: Cleanup | T031-T036 | P2 | 3 hours |
| Phase 6: Testing | T037-T042 | P1 | 8 hours |
| Phase 7: Migration | T043-T047 | P3 | 4 hours |
| **Total** | **47 tasks** | | **43 hours** |

## Risk Assessment

| Risk | Impact | Mitigation |
|------|--------|------------|
| Breaking change for existing deployments | Medium | Document migration path; old images still work |
| Version script fails in CI | High | Extensive testing; fallback to manual version |
| OCI registry rejects new format | High | Validate format before rollout; test with GHCR |
| Helm chart version parsing issues | Medium | Use semver validation in CI |
| Git tag naming conflicts | Low | Document new convention; validate in PR reviews |

## Success Criteria

- [ ] Version script produces correct format for all scenarios (release, main, feature, dirty)
- [ ] Docker images use new version format in tags and labels
- [ ] Helm charts use new version format consistently
- [ ] Version validation passes in CI for all builds
- [ ] Documentation comprehensively explains new scheme
- [ ] All old `+infoblox` references removed
- [ ] Local `make version` command works on macOS and Linux
- [ ] OCI registry accepts all generated version strings
- [ ] Zero manual version updates required in workflows

## Dependencies

- Git command-line tools (local and CI)
- Bash 4+ for version script
- Upstream submodule initialized
- GitHub Actions environment variables
- Helm 3.8+ for OCI chart publishing

## Open Questions

1. **Infoblox revision number source**: Where should `<n>` in `-ib.<n>` come from?
   - **Option A**: Extract from git tag itself (`v8.1.1-ib.2` → `2`)
   - **Option B**: Read from VERSION file
   - **Recommendation**: Extract from tag (simpler, no file to maintain)

2. **appVersion vs version in Helm charts**:
   - **Chart version**: Full version with SHA (`8.1.1-ib.1.abc1234`)
   - **appVersion**: Just upstream version (`8.1.1`) or full version?
   - **Recommendation**: appVersion = upstream (shows user-facing app version), version = full (shows packaging version)

3. **Backward compatibility period**:
   - Should we tag images with both old and new formats during transition?
   - **Recommendation**: No, clean break. Document migration.

4. **Latest tag behavior**:
   - Currently `latest` points to last main branch build
   - Should it continue or only tag stable releases as `latest`?
   - **Recommendation**: Keep current behavior (latest = main), add `stable` tag for releases

## Notes

- Version script must be executable and tested before merging
- CI changes should be tested in feature branch before merging
- Documentation updates should happen simultaneously with code changes
- Migration guide should be available before first release with new format
