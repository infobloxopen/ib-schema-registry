# Feature Specification: Upgrade to Schema Registry 8.1.1

**Feature Branch**: `002-upgrade-8-1-1`  
**Created**: 2026-01-16  
**Status**: Draft  
**Input**: User description: "upgrade to schema registry 8.1.1"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Version Update with Compatibility Verification (Priority: P1) 🎯 MVP

Platform engineers need to update the upstream Schema Registry source to version 8.1.1 while ensuring the build system continues to work and no breaking changes affect the container image.

**Why this priority**: Core upgrade task. Without this, the feature cannot deliver value. All downstream testing depends on this.

**Independent Test**: Update git submodule to 8.1.1 tag, run `make clean && make build`, verify image builds successfully with new version in OCI labels and smoke tests pass.

**Acceptance Scenarios**:

1. **Given** the repository is on main branch with submodule at 7.6.1, **When** maintainer updates submodule to 8.1.1 tag and rebuilds image, **Then** build completes successfully without Maven errors
2. **Given** image built with 8.1.1, **When** maintainer inspects OCI labels, **Then** `org.opencontainers.image.version` shows `8.1.1+infoblox.1`
3. **Given** 8.1.1 image is built, **When** smoke test runs, **Then** container starts and `/subjects` endpoint responds with HTTP 200

---

### User Story 2 - Multi-Architecture Build Validation (Priority: P1)

Release engineers need to verify that Schema Registry 8.1.1 builds successfully for both linux/amd64 and linux/arm64 architectures without platform-specific issues.

**Why this priority**: Constitution requirement for multi-arch portability. Failure here breaks production deployments on ARM platforms (EKS Graviton, etc.).

**Independent Test**: Run `make buildx`, verify build output shows both architectures complete, inspect manifest to confirm both platforms are present.

**Acceptance Scenarios**:

1. **Given** submodule updated to 8.1.1, **When** maintainer runs multi-arch build, **Then** both linux/amd64 and linux/arm64 build without errors
2. **Given** multi-arch manifest exists, **When** maintainer inspects manifest with `docker buildx imagetools inspect`, **Then** output lists both platforms
3. **Given** both platform images exist, **When** smoke tests run on each architecture, **Then** both pass identically

---

### User Story 3 - Base Image Compatibility Testing (Priority: P2)

Security engineers need to verify that Schema Registry 8.1.1 works with both Chainguard JRE (default) and Eclipse Temurin (fallback) runtime images.

**Why this priority**: Constitution requirement for base image pluggability. Ensures users aren't locked into single base image vendor.

**Independent Test**: Build with default Chainguard runtime and verify smoke tests pass, then rebuild with Temurin override and verify smoke tests pass.

**Acceptance Scenarios**:

1. **Given** 8.1.1 source, **When** built with Chainguard JRE default, **Then** smoke tests pass and image has no shell access (distroless verification)
2. **Given** 8.1.1 source, **When** built with `RUNTIME_IMAGE=eclipse-temurin:17-jre`, **Then** smoke tests pass and rollback is confirmed working
3. **Given** both runtime variants built, **When** images are compared, **Then** Chainguard variant is ~44% smaller with fewer CVEs

---

### User Story 4 - Breaking Changes Documentation (Priority: P2)

Documentation maintainers need to identify any breaking changes in Schema Registry 8.1.1 that affect configuration, API compatibility, or deployment patterns.

**Why this priority**: User-facing impact. Prevents production incidents from undocumented breaking changes between 7.6.1 and 8.1.1.

**Independent Test**: Review upstream release notes, test configuration file compatibility, verify existing quickstart examples still work, document any required changes.

**Acceptance Scenarios**:

1. **Given** upstream 8.1.1 release notes reviewed, **When** maintainer compares to 7.6.1, **Then** all breaking changes are identified and documented in CHANGELOG.md
2. **Given** existing config/schema-registry.properties file, **When** used with 8.1.1 container, **Then** Schema Registry starts without configuration errors or deprecation warnings
3. **Given** quickstart.md examples, **When** tested against 8.1.1 image, **Then** all examples work without modification (or required updates are documented)

---

### User Story 5 - CI/CD Pipeline Validation (Priority: P3)

DevOps engineers need to verify the GitHub Actions workflow successfully builds and pushes the 8.1.1 multi-arch image to the registry.

**Why this priority**: Automation validation. Nice to have but not blocking for manual builds. Can be tested after manual build validation.

**Independent Test**: Push commit updating submodule to main branch (or create PR), verify GitHub Actions workflow completes successfully, check registry for 8.1.1 tagged image.

**Acceptance Scenarios**:

1. **Given** submodule updated to 8.1.1 and committed, **When** pushed to main branch, **Then** GitHub Actions workflow builds both architectures and pushes to GHCR
2. **Given** workflow completes, **When** checking GHCR, **Then** multi-arch manifest exists with tag `8.1.1+infoblox.1` and both platform images are present
3. **Given** CI-built image in registry, **When** pulled and tested locally, **Then** smoke tests pass on both architectures

---

### Edge Cases

- **What happens when Maven build fails for 8.1.1?** Build should fail fast with clear error message from Maven. Developer reviews upstream changes for new dependencies or build requirements.
- **What if 8.1.1 requires Java 21 instead of Java 17?** BUILDER_IMAGE build arg must be updated to use Java 21 base image. Dockerfile and documentation updated accordingly.
- **What if 8.1.1 introduces breaking API changes?** Document in CHANGELOG.md under "Breaking Changes" section with migration guide. Update smoke tests if `/subjects` endpoint changes.
- **What if Chainguard JRE doesn't support Java features in 8.1.1?** Test with Temurin first to isolate issue. If Chainguard incompatible, document workaround or request Chainguard update.
- **What if 8.1.1 has CVEs at release time?** Document in CHANGELOG.md as known issues. Monitor for upstream patches. Consider staying on 7.6.1 until patched.
- **What if configuration format changes between 7.6.1 and 8.1.1?** Update config/schema-registry.properties template and config/examples/* with new format. Document migration in CHANGELOG.md.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST update git submodule pointer to Schema Registry 8.1.1 tag from upstream repository
- **FR-002**: Build process MUST successfully compile Schema Registry 8.1.1 using Maven without errors
- **FR-003**: Generated container image MUST include Schema Registry 8.1.1 standalone JAR as runtime artifact
- **FR-004**: OCI image labels MUST reflect version `8.1.1+infoblox.1` (upstream version + local iteration suffix)
- **FR-005**: Container MUST start successfully and serve HTTP API on port 8081 with 8.1.1 runtime
- **FR-006**: Smoke test suite MUST pass with 8.1.1 image (GET /subjects returns HTTP 200)
- **FR-007**: CHANGELOG.md MUST document upgrade from 7.6.1 to 8.1.1 with breaking changes section
- **FR-008**: Existing configuration templates (config/schema-registry.properties, config/examples/*) MUST work with 8.1.1 or be updated if schema changes
- **FR-009**: Quickstart documentation MUST be validated against 8.1.1 image (or updated if examples break)
- **FR-010**: README version references MUST be updated from 7.6.1 to 8.1.1 where applicable

### Security & Portability Requirements

- **SPR-001**: Image MUST build for both linux/amd64 and linux/arm64 architectures with 8.1.1 source
- **SPR-002**: Chainguard JRE runtime MUST remain default and functional with 8.1.1
- **SPR-003**: Eclipse Temurin fallback (RUNTIME_IMAGE override) MUST remain functional with 8.1.1
- **SPR-004**: Container MUST continue running as non-root user (UID 65532) with 8.1.1
- **SPR-005**: Runtime image MUST remain distroless-compatible (no shell dependencies) with 8.1.1
- **SPR-006**: Build process MUST NOT introduce new `curl | bash` installers or untrusted downloads
- **SPR-007**: If Java version requirement changes, BUILDER_IMAGE default MUST be updated to matching JDK version
- **SPR-008**: OCI labels (org.opencontainers.image.*) MUST be preserved and accurately reflect 8.1.1 metadata
- **SPR-009**: Multi-stage build optimizations (cache mounts) MUST remain functional with 8.1.1
- **SPR-010**: GitHub Actions workflow MUST successfully build and push 8.1.1 multi-arch image

### Key Entities

- **Upstream Submodule Reference**: Git pointer to confluentinc/schema-registry at tag 8.1.1
- **Version Metadata**: Composite version string `8.1.1+infoblox.1` derived from submodule tag
- **Build Artifact**: Schema Registry 8.1.1 standalone JAR (kafka-schema-registry-package-8.1.1-standalone.jar)
- **Container Image**: Multi-arch OCI image tagged with 8.1.1 version, containing updated runtime

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Submodule reference points to Schema Registry 8.1.1 tag (verifiable via `git submodule status`)
- **SC-002**: `make build` completes in under 5 minutes with warm cache (Maven dependency cache hit)
- **SC-003**: `make buildx` completes in under 15 minutes with warm cache for both architectures
- **SC-004**: Smoke tests pass on both linux/amd64 and linux/arm64 architectures with identical results
- **SC-005**: OCI label `org.opencontainers.image.version` returns `8.1.1+infoblox.1` when inspected
- **SC-006**: Image built with Chainguard JRE default has zero high/critical CVEs at build time (or documented as known issues)
- **SC-007**: Image built with Eclipse Temurin fallback passes all smoke tests (compatibility verification)
- **SC-008**: GitHub Actions workflow builds and pushes 8.1.1 multi-arch manifest successfully without manual intervention
- **SC-009**: All quickstart.md examples work with 8.1.1 image without modification (or documented updates applied)
- **SC-010**: CHANGELOG.md includes complete upgrade notes with breaking changes (if any) and migration guide

## Assumptions *(if applicable)*

- **Assumption 1**: Schema Registry 8.1.1 maintains Java 17 compatibility. If Java 21 is required, BUILDER_IMAGE and documentation must be updated.
- **Assumption 2**: Maven build process for 8.1.1 is compatible with existing Dockerfile commands (mvn -DskipTests package -P standalone). If changed, Dockerfile must be updated.
- **Assumption 3**: Confluent has published 8.1.1 tag in upstream GitHub repository. If not available, this feature cannot proceed.
- **Assumption 4**: 8.1.1 configuration schema is backward-compatible with 7.6.1 config files. If breaking changes exist, config templates must be updated.
- **Assumption 5**: Chainguard JRE image supports all Java features required by 8.1.1. If incompatibilities exist, Temurin becomes temporary default until resolved.
- **Assumption 6**: No new third-party dependencies in 8.1.1 conflict with BuildKit cache mount strategy. If conflicts arise, Dockerfile cache configuration may need adjustment.

## Out of Scope *(if applicable)*

The following are explicitly NOT part of this upgrade:

- **Performance tuning for 8.1.1**: This upgrade focuses on version compatibility, not optimization of new features. Performance improvements in 8.1.1 are delivered automatically but not explicitly tested beyond smoke tests.
- **New 8.1.1 features**: This upgrade makes 8.1.1 available but does not add configuration examples or documentation for new features introduced in 8.1.1. Users reference upstream docs for new capabilities.
- **Migration tooling**: No automated migration scripts from 7.6.1 to 8.1.1. Users manually update configuration based on CHANGELOG migration guide.
- **Backward compatibility layer**: If 8.1.1 has breaking API changes, this repo does not provide compatibility shims. Users must update clients to 8.1.1 API.
- **Version pinning flexibility**: This upgrade targets 8.1.1 specifically. Support for multiple concurrent versions (e.g., 7.6.1 and 8.1.1 in parallel) is out of scope.
- **Comprehensive integration testing**: Smoke tests validate basic functionality. Full integration testing with Kafka cluster, schema compatibility checks, and multi-client scenarios remain user responsibility.

## Dependencies *(if applicable)*

- **Upstream Release**: Schema Registry 8.1.1 must be released by Confluent with tag in GitHub repository
- **Java Version Compatibility**: If 8.1.1 requires Java 21, BUILDER_IMAGE must be updated first (e.g., maven:3-eclipse-temurin-21)
- **Chainguard Image Updates**: If 8.1.1 requires Java 21, Chainguard must provide JRE 21 image (cgr.dev/chainguard/jre:latest with Java 21 support)
- **Existing Feature 001**: Build infrastructure from feature 001 (schema-registry-image) must be complete and working

## Risks *(if applicable)*

- **Risk 1 - Breaking API Changes**: If 8.1.1 has breaking REST API changes, smoke tests may fail. **Mitigation**: Review upstream release notes early; update smoke tests if needed.
- **Risk 2 - Java Version Requirement**: If 8.1.1 requires Java 21, build fails with Java 17. **Mitigation**: Test build early; update BUILDER_IMAGE and RUNTIME_IMAGE if needed.
- **Risk 3 - Maven Build Changes**: If 8.1.1 changes build profile (e.g., no longer uses `-P standalone`), build fails. **Mitigation**: Review upstream pom.xml changes; adjust Dockerfile Maven command.
- **Risk 4 - Configuration Schema Changes**: If 8.1.1 changes config file format, existing templates are invalid. **Mitigation**: Compare 7.6.1 and 8.1.1 config schemas; update templates.
- **Risk 5 - Chainguard Incompatibility**: If 8.1.1 uses Java features unsupported by Chainguard JRE, runtime fails. **Mitigation**: Test Temurin first to isolate; fallback to Temurin default if Chainguard incompatible.
- **Risk 6 - CVE Introduction**: If 8.1.1 has new high/critical CVEs, security posture degrades. **Mitigation**: Scan image post-build; document known issues; monitor for patches.

## Notes *(optional)*

- **Version Numbering**: This upgrade increments the local suffix from `7.6.1+infoblox.1` to `8.1.1+infoblox.1`. Future builds for 8.1.1 (e.g., config changes) increment to `8.1.1+infoblox.2`.
- **Rollback Strategy**: If 8.1.1 upgrade fails or introduces issues, rollback by reverting submodule to 7.6.1 tag: `cd upstream/schema-registry && git checkout 7.6.1 && cd ../.. && git add upstream/schema-registry && git commit -m "Revert to 7.6.1"`.
- **Testing Priority**: Prioritize multi-arch build testing (US2) over CI/CD validation (US5) because manual builds are more commonly used during development.
- **Documentation Updates**: README.md references to version 7.6.1 should be updated to 8.1.1, but keep 7.6.1 in "Updating Upstream Version" section as example of previous version.
- **Constitution Compliance**: This upgrade must maintain all 8 constitution gates from feature 001. No regressions in multi-arch portability, base image pluggability, distroless compatibility, security, licensing, ergonomics, or testing.
