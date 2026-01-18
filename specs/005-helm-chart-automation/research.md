# Research: Automated Helm Chart Publishing with Version Sync

**Feature**: 005-helm-chart-automation  
**Date**: January 17, 2026  
**Status**: Complete

## Research Overview

This document consolidates research findings for automating Helm chart publishing with version synchronization. All technical decisions are documented with rationale and alternatives considered.

---

## R1: Version Extraction Strategy

**Decision**: Use `steps.meta.outputs.version` from `docker/metadata-action@v5` for both Docker image tags and Helm chart versions.

**Rationale**:
- The metadata-action is already configured in `.github/workflows/build-image.yml` (line 48-60)
- It provides consistent version formatting across all build events (tags, branches, SHAs)
- Output format:
  - Git tag `v1.2.3` → `1.2.3` (strips `v` prefix automatically with `type=semver,pattern={{version}}`)
  - Branch `main` → `main` (with `type=ref,event=branch`)
  - SHA builds → `sha-<7-char>` (with `type=sha`)
- Single source of truth prevents version drift between Docker images and Helm charts

**Alternatives Considered**:
1. **Manual version extraction from git tags**: Rejected because it duplicates logic already in metadata-action and increases maintenance burden
2. **Separate version calculation for charts**: Rejected because it introduces potential for version mismatch
3. **Use `github.ref_name` directly**: Rejected because it doesn't strip `v` prefix from tags or handle branch/SHA formatting consistently

**Implementation**: Access via `${{ steps.meta.outputs.version }}` in workflow YAML

---

## R2: Chart Version Format for Branch Builds

**Decision**: Use pre-release semver format `0.0.0-<branch>.<short-sha>` for branch builds (e.g., `0.0.0-main.abc1234`).

**Rationale**:
- Semver 2.0.0 compliant pre-release identifier format
- `0.0.0` major version signals "development/unreleased" status
- Branch name provides context (e.g., `main`, `feature-xyz`)
- Short SHA (7 chars) provides unique identifier matching Docker image tags
- Helm understands pre-release versions and sorts them correctly (`0.0.0-*` < `1.0.0`)

**Alternatives Considered**:
1. **Use branch name only (e.g., `main`)**: Rejected because Helm requires versions for OCI artifacts; branch names alone aren't semver-compliant and don't provide uniqueness for multiple commits
2. **Use full 40-char SHA**: Rejected because metadata-action generates 7-char short SHAs for Docker tags; consistency is critical
3. **Use timestamp-based versions (e.g., `0.0.0-20260117123045`)**: Rejected because it doesn't match Docker image tagging strategy and makes correlation harder

**Implementation**: 
```yaml
VERSION="${{ steps.meta.outputs.version }}"
# For branch builds, metadata-action outputs just the branch name (e.g., "main")
# Need to construct: 0.0.0-main.<short-sha>
if [[ "$VERSION" != *"."* ]]; then  # Simple heuristic: no dots = branch name
  SHORT_SHA="$(echo ${{ github.sha }} | cut -c1-7)"
  VERSION="0.0.0-${VERSION}.${SHORT_SHA}"
fi
```

**Follow-up**: Verify metadata-action output format for branch builds. May need custom formatting logic.

---

## R3: Chart.yaml Field Update Mechanism

**Decision**: Use `sed` for in-place field replacement at build time (not committed to git).

**Rationale**:
- Simple, POSIX-compliant tool available in GitHub Actions ubuntu-latest runners
- No external dependencies required (yq, jq not needed for two-field updates)
- Fast execution (<1 second)
- Build-time only modification keeps git history clean

**Alternatives Considered**:
1. **yq (YAML processor)**: Rejected because it adds dependency installation time (~5 seconds) for minimal benefit; overkill for two field updates
2. **Template Chart.yaml with placeholders**: Rejected because Helm requires valid Chart.yaml in repo; templating breaks local `helm package` commands
3. **Commit version updates back to git**: Rejected because it creates noise in git history and triggers additional CI runs (infinite loop risk)
4. **Perl one-liners**: Rejected because `sed` is more universally understood and maintainable

**Implementation**:
```bash
sed -i "s/^version:.*/version: ${VERSION}/" helm/ib-schema-registry/Chart.yaml
sed -i "s/^appVersion:.*/appVersion: \"${VERSION}\"/" helm/ib-schema-registry/Chart.yaml
```

**Note**: The `-i` flag works without backup extension on Linux (GitHub Actions); macOS requires `-i ''` but not relevant for CI-only execution.

---

## R4: OCI Registry Coexistence

**Decision**: Publish Helm charts to same OCI path as Docker images (`ghcr.io/infobloxopen/ib-schema-registry`) using different media types.

**Rationale**:
- OCI registries distinguish artifacts by media type, not path:
  - Docker images: `application/vnd.docker.distribution.manifest.v2+json`
  - Helm charts: `application/vnd.cncf.helm.chart.content.v1.tar+gzip`
- Simplified naming convention (single path for all project artifacts)
- Helm 3.8+ has native OCI support with automatic media type handling
- GHCR supports multi-artifact repositories

**Alternatives Considered**:
1. **Separate chart repository path (e.g., `ghcr.io/infobloxopen/charts/ib-schema-registry`)**: Rejected because it fragments artifact locations and adds discovery complexity
2. **Traditional Helm repository with index.yaml**: Rejected because OCI-based approach is more modern, requires no index maintenance, and integrates with existing container registry
3. **Chart Museum or dedicated Helm repository server**: Rejected because it adds infrastructure overhead; GHCR is already available and integrated with GitHub

**Implementation**: Use `helm push <chart>.tgz oci://ghcr.io/infobloxopen` (Helm CLI handles media type automatically)

**Validation**: Confirmed with existing documentation in `README.md` (line references to `oci://ghcr.io/infobloxopen/ib-schema-registry`)

---

## R5: Workflow Step Placement

**Decision**: Add Helm chart publishing step after SBOM attestation steps (line ~285 in build-image.yml) and before `test` job.

**Rationale**:
- SBOM attestations complete the Docker image artifact lifecycle
- Helm chart depends on Docker image being fully published (no logical dependency, but conceptual ordering)
- Placing before `test` job ensures charts are available for e2e tests if needed (though current tests don't require it)
- If chart publishing fails, test job still runs (non-blocking failure for supplementary artifact)

**Alternatives Considered**:
1. **Parallel job separate from build job**: Rejected because it requires re-checkout and doesn't have access to `steps.meta` outputs from build job
2. **After test job**: Rejected because it delays chart availability; tests don't depend on charts being published
3. **Before SBOM attestations**: Rejected because it violates logical ordering (complete image artifacts before supplementary artifacts)

**Implementation**: Add as final step in `build` job with condition `if: github.event_name == 'push'`

---

## R6: Authentication Strategy

**Decision**: Use `GITHUB_TOKEN` secret with `helm registry login` for GHCR authentication.

**Rationale**:
- `GITHUB_TOKEN` automatically available in GitHub Actions workflows
- Automatically scoped to repository permissions (no PAT management overhead)
- Workflow already uses `GITHUB_TOKEN` for Docker image push (line 43-47 in build-image.yml)
- GitHub Actions `packages:write` permission already granted to workflow (line 21)

**Alternatives Considered**:
1. **Personal Access Token (PAT)**: Rejected because it requires manual secret management, rotation, and broader scope than necessary
2. **GitHub App authentication**: Rejected because it adds complexity; `GITHUB_TOKEN` is sufficient for repository-scoped operations
3. **Docker credentials reuse**: Rejected because Helm CLI requires separate `helm registry login` command (doesn't share Docker credential store in CI environment)

**Implementation**:
```yaml
echo "${{ secrets.GITHUB_TOKEN }}" | helm registry login ghcr.io -u ${{ github.actor }} --password-stdin
```

**Security Note**: Password passed via stdin (not command line argument) prevents exposure in process lists

---

## R7: Error Handling Strategy

**Decision**: Chart publishing step should log errors but NOT fail the entire build if publishing fails.

**Rationale**:
- Docker image is the primary artifact; Helm chart is supplementary
- Chart publishing failure (e.g., transient registry issue) should not block image availability
- Workflow should continue to test job to validate Docker image functionality
- Clear error logging enables diagnosis without blocking pipeline

**Alternatives Considered**:
1. **Fail-fast on chart publishing error**: Rejected because it makes Docker image availability dependent on Helm registry reliability (lower priority artifact blocks higher priority)
2. **Silent failure**: Rejected because it hides issues; explicit logging required for operational visibility
3. **Retry mechanism**: Considered for future enhancement; initial implementation uses single attempt with clear error messages

**Implementation**:
```yaml
- name: Package and publish Helm chart
  if: github.event_name == 'push'
  continue-on-error: true  # Don't fail build on chart publishing issues
  run: |
    # ... packaging and push commands ...
  || echo "::warning::Helm chart publishing failed - Docker image published successfully"
```

---

## R8: Version Validation

**Decision**: No strict semver validation in workflow; trust metadata-action output format.

**Rationale**:
- Metadata-action is maintained by Docker organization; output format stable and well-tested
- Over-validation adds complexity and maintenance burden
- Helm validates version format during `helm package` command (will fail fast if invalid)
- User-visible error from Helm is clearer than custom validation logic

**Alternatives Considered**:
1. **Regex validation of semver format**: Rejected because it duplicates validation logic that Helm already performs
2. **Fail on unexpected version format**: Rejected because it's redundant (Helm package command will fail anyway)
3. **Transform unexpected formats to valid semver**: Rejected because it risks silent data corruption; explicit failure is better

**Implementation**: No additional validation code needed; rely on Helm CLI error messages

---

## Summary of Key Decisions

| Aspect | Decision | Key Rationale |
|--------|----------|---------------|
| Version source | `steps.meta.outputs.version` | Single source of truth, already configured |
| Branch version format | `0.0.0-<branch>.<short-sha>` | Semver-compliant pre-release, matches Docker tags |
| Chart.yaml updates | `sed` in-place replacement | Simple, no dependencies, build-time only |
| OCI path | Same as Docker images | Media type differentiation, simplified naming |
| Workflow placement | After SBOM, before test | Logical ordering, non-blocking |
| Authentication | `GITHUB_TOKEN` | Already available, properly scoped |
| Error handling | Continue-on-error | Chart is supplementary artifact |
| Validation | Trust Helm CLI | Avoid redundant logic |

---

## Open Questions

None. All technical decisions finalized and documented above.

---

## References

- Docker metadata-action docs: https://github.com/docker/metadata-action
- Helm OCI support: https://helm.sh/docs/topics/registries/
- GHCR documentation: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry
- Existing workflow: `.github/workflows/build-image.yml`
- Semver 2.0.0 specification: https://semver.org/
