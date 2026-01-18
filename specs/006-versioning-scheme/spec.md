# Feature Specification: Unified Versioning Scheme

**Feature Branch**: `006-versioning-scheme`  
**Created**: 2026-01-18  
**Status**: Draft  
**Input**: User description: "Adopt a version scheme that preserves the upstream Confluent Schema Registry version (major.minor.patch) and appends an Infoblox semver-compatible prerelease suffix that includes the short git SHA, with optional .dirty for dirty trees."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Release Build Versioning (Priority: P1)

When an Infoblox maintainer creates a git tag for a production release, the build system automatically generates a version string that clearly shows both the upstream Confluent Schema Registry version and the Infoblox-specific revision, making it easy to trace back to the exact source code commit.

**Why this priority**: Production releases are the primary artifact delivered to customers. Accurate, traceable versioning is critical for support, compliance, and supply chain security.

**Independent Test**: Create a git tag `v8.1.1-ib.1`, trigger CI, verify Docker image tag and Helm chart version both use `8.1.1-ib.1.abc1234` format.

**Acceptance Scenarios**:

1. **Given** a clean git tree at a specific commit, **When** a maintainer tags the commit as `v8.1.1-ib.1` and pushes the tag, **Then** the build produces Docker image tag `8.1.1-ib.1.abc1234` and Helm chart version `8.1.1-ib.1.abc1234` (where `abc1234` is the 7-char SHA)
2. **Given** a git tree with uncommitted changes to tracked files, **When** a local build is triggered, **Then** the version includes `.dirty` suffix: `8.1.1-ib.1.abc1234.dirty`
3. **Given** an existing release `v8.1.1-ib.1`, **When** a patch is needed for the same upstream version, **Then** the maintainer creates tag `v8.1.1-ib.2` and version becomes `8.1.1-ib.2.def5678`

---

### User Story 2 - Main Branch Development Builds (Priority: P2)

When developers commit to the main branch, the build system automatically generates development versions that sort correctly in semver order (after the base upstream version but before any official releases), allowing teams to test unreleased changes.

**Why this priority**: Development builds enable continuous integration testing and early validation before cutting official releases, but aren't customer-facing.

**Independent Test**: Push a commit to main branch, verify Docker image tag and Helm chart version both use `8.1.1-ib.main.abc1234` format.

**Acceptance Scenarios**:

1. **Given** a commit on the main branch with upstream version 8.1.1, **When** CI builds the image, **Then** the version is `8.1.1-ib.main.abc1234` (where `abc1234` is the 7-char SHA)
2. **Given** multiple commits to main, **When** comparing versions, **Then** `8.1.1-ib.main.abc1234` sorts before `8.1.1-ib.1.def5678` in semver order (prerelease identifiers compared lexically)
3. **Given** a main branch build, **When** pulling the Docker image or Helm chart, **Then** users can identify it as a development build from the `.main.` segment

---

### User Story 3 - Feature Branch Builds (Priority: P3)

When developers work on feature branches, the build system generates versions that include the branch name (sanitized for OCI/semver compatibility), making it easy to identify which branch produced a particular artifact during testing.

**Why this priority**: Feature branch builds are useful for testing but less critical than main branch and release builds. They're typically only used by developers.

**Independent Test**: Push a commit to branch `feature/auth-improvements`, verify version includes sanitized branch name like `8.1.1-ib.feature-auth-improvements.abc1234`.

**Acceptance Scenarios**:

1. **Given** a commit on branch `feature/auth-improvements`, **When** CI builds the image, **Then** the version is `8.1.1-ib.feature-auth-improvements.abc1234` (slashes converted to hyphens)
2. **Given** a branch name with special characters `feature/add-oauth2+support`, **When** version is generated, **Then** invalid characters are sanitized: `8.1.1-ib.feature-add-oauth2-support.abc1234`
3. **Given** a very long branch name (>50 chars), **When** version is generated, **Then** the branch segment is truncated while preserving the SHA: `8.1.1-ib.feature-implement-advanced-auth-with-oa.abc1234`

---

### Edge Cases

- **Git tag without `-ib.N` suffix**: If tag is `v8.1.1` (missing Infoblox revision), system defaults to `-ib.1`
- **Dirty builds in CI**: CI builds should never be dirty; if detected, build warns but continues (dirty flag still applied)
- **No upstream version available**: If `upstream/schema-registry` submodule is missing or has no tags, fall back to reading VERSION file; if VERSION file missing, fail with clear error
- **Non-semver upstream tags**: If upstream Confluent uses non-standard versioning (e.g., `8.1.1-rc1`), use as-is and append Infoblox suffix: `8.1.1-rc1-ib.1.abc1234`
- **Very short SHA collisions**: Document in troubleshooting guide that 7-char SHAs may collide (rare); users should use full commit SHA for disambiguation

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST extract upstream version from `upstream/schema-registry` git tag (stripping leading `v` if present)
- **FR-002**: System MUST generate 7-character short SHA from `git rev-parse --short=7 HEAD`
- **FR-003**: System MUST detect dirty git tree state by checking for uncommitted changes to tracked files
- **FR-004**: For git tags matching pattern `v<upstream>-ib.<n>`, system MUST produce version `<upstream>-ib.<n>.<sha>[.dirty]`
- **FR-005**: For commits on main branch, system MUST produce version `<upstream>-ib.main.<sha>[.dirty]`
- **FR-006**: For commits on other branches, system MUST produce version `<upstream>-ib.<branch>.<sha>[.dirty]` where `<branch>` is sanitized
- **FR-007**: Branch name sanitization MUST convert characters outside `[A-Za-z0-9_.-]` to hyphens
- **FR-008**: Branch name sanitization MUST convert `/` to `-` (e.g., `feature/auth` → `feature-auth`)
- **FR-009**: System MUST limit branch name segment to 50 characters maximum (truncate if longer)
- **FR-010**: System MUST provide a single script or Makefile target that outputs: `VERSION`, `UPSTREAM_VERSION`, `SHA`, `DIRTY`, and final `TAG`
- **FR-011**: GitHub Actions workflow MUST use the generated TAG for both Docker image tags and Helm chart versions
- **FR-012**: Helm Chart.yaml `version` field MUST match the Docker image tag exactly
- **FR-013**: Version strings MUST NOT contain `+` character (SemVer build metadata) to ensure OCI registry compatibility
- **FR-014**: All version components MUST use only characters from `[A-Za-z0-9_.-]` set
- **FR-015**: Generated version strings MUST be valid SemVer 2.0 prerelease identifiers

### Security & Portability Requirements

- **SPR-001**: Version generation script MUST NOT require network access (works offline)
- **SPR-002**: Version generation MUST NOT depend on GitHub-specific environment variables (can run locally)
- **SPR-003**: Version generation MUST fail fast with clear error messages if prerequisites are missing (git, upstream submodule, etc.)
- **SPR-004**: Dirty builds MUST be clearly marked to prevent accidental production deployment of uncommitted changes
- **SPR-005**: Version script MUST be idempotent (running twice on same commit produces identical output)
- **SPR-006**: Documentation MUST explain why `+` is avoided (OCI registry tag limitations) to prevent future regressions

### Key Entities

- **Version String**: Complete version identifier used for Docker tags and Helm chart versions, format: `<upstream>-ib.<suffix>.<sha>[.dirty]`
- **Upstream Version**: Semantic version from Confluent Schema Registry (e.g., `8.1.1`), extracted from `upstream/schema-registry` git tags
- **Infoblox Revision**: Integer `<n>` representing Infoblox-specific packaging iteration for the same upstream version (e.g., `-ib.1`, `-ib.2`)
- **Short SHA**: 7-character git commit hash providing exact commit traceability
- **Dirty Flag**: Boolean indicating uncommitted changes to tracked files, appends `.dirty` when true
- **Branch Suffix**: Sanitized branch name segment used in prerelease identifier (e.g., `main`, `feature-auth`)

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Version generation script completes in under 1 second on typical development machine
- **SC-002**: 100% of Docker image tags and Helm chart versions use identical version strings (verified by CI checks)
- **SC-003**: Version strings are parseable by standard semver libraries (verified in CI with semver validation tool)
- **SC-004**: Developers can determine exact source commit from version string alone (no ambiguity)
- **SC-005**: OCI registry (GHCR) accepts all generated version strings as valid tags without errors
- **SC-006**: Local builds produce correct version with dirty detection working 100% of the time
- **SC-007**: README and documentation clearly explain version format with examples for all scenarios (release, main, feature branch, dirty)
- **SC-008**: Zero manual version updates required in CI/CD workflows (fully automated)

## Assumptions

1. **Git Tag Convention**: Release tags will follow pattern `v<upstream>-ib.<n>` (e.g., `v8.1.1-ib.1`, `v8.1.1-ib.2`)
2. **Upstream Submodule**: The `upstream/schema-registry` git submodule exists and has proper git tags
3. **Git Available**: Git command-line tools are available in all build environments (CI and local)
4. **SemVer Prerelease Sorting**: Users understand that `8.1.1-ib.main.abc1234` < `8.1.1-ib.1.def5678` due to lexical comparison of prerelease identifiers
5. **CI Clean State**: CI environments always build from clean git state (never dirty) - dirty detection is primarily for local development
6. **Single Artifact per Commit**: Each commit produces one set of artifacts (image + chart) with matching versions

## Out of Scope

- **Historical Version Migration**: Existing artifacts with old version schemes are not retroactively updated
- **Version Comparison Tool**: No CLI tool for comparing/sorting Infoblox versions (users can use standard semver tools)
- **Multiple Upstream Tracks**: Only single upstream version line supported (no parallel 7.x and 8.x builds)
- **Custom Version Override**: No mechanism for manually overriding version in CI (always derived from git state)
- **Version Changelog Automation**: Version strings don't include changelog or feature descriptions

## Dependencies

- **Git Repository**: Working git repository with history and tags
- **Upstream Submodule**: `upstream/schema-registry` submodule properly initialized and tracked
- **CI Environment**: GitHub Actions with git, docker, helm tools available
- **Documentation**: README.md, CONTRIBUTING.md for explaining version scheme to users and maintainers

## Open Questions

None - all edge cases addressed with reasonable defaults.
