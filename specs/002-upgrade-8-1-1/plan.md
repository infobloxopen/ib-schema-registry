# Implementation Plan: Upgrade to Schema Registry 8.1.1

**Branch**: `002-upgrade-8-1-1` | **Date**: 2026-01-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/002-upgrade-8-1-1/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Upgrade the existing Schema Registry container image from version 7.6.1 to 8.1.1 by updating the git submodule reference to the upstream release tag. This is a version update that leverages all existing build infrastructure from feature 001 (multi-arch builds, Chainguard runtime, CI/CD automation). Core technical approach: Update submodule pointer, validate Maven build compatibility with 8.1.1, verify multi-arch builds work without changes, test base image compatibility (Chainguard + Temurin), document any breaking changes from upstream, and update version metadata in OCI labels. No changes to Dockerfile or Makefile expected unless 8.1.1 introduces Java version requirements or build profile changes.

## Technical Context

**Language/Version**: Java 17 (assumption: 8.1.1 maintains Java 17 compatibility; if Java 21 required, will update BUILDER_IMAGE)  
**Primary Dependencies**: Maven 3.x (build tool), Docker BuildKit 0.11+ (multi-platform support), Git (submodule management), upstream confluentinc/schema-registry 8.1.1 tag  
**Storage**: N/A (stateless container; Kafka cluster provides persistence)  
**Testing**: Shell scripts for smoke tests (container start + HTTP `/subjects` endpoint check); no unit tests in this repo (build infrastructure only)  
**Target Platform**: linux/amd64 and linux/arm64 container runtime (Docker, containerd, Kubernetes)  
**Project Type**: Build infrastructure / container image upgrade (not application code)  
**Performance Goals**: Cold build <15 min in CI, warm build (cached Maven deps) <5 min, container startup <30 sec (same as 7.6.1)  
**Constraints**: Distroless-compatible (no shell in runtime), non-root (UID 65532), BuildKit required, multi-arch mandatory, maintain all constitution gates from feature 001  
**Scale/Scope**: Minimal changes - submodule update, version metadata, documentation updates, validation testing; ~50-100 lines of changes total (primarily git submodule commit + CHANGELOG)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Multi-arch portability**: Build approach remains identical on macOS ARM and Linux x86; no platform-specific changes needed for version upgrade.
  - ✅ Existing Makefile and Dockerfile design from feature 001 is version-agnostic; submodule update preserves portability
- [x] **Base image pluggability**: Builder and runtime images remain configurable via build args; no hardcoded version-specific base image dependencies.
  - ✅ BUILDER_IMAGE and RUNTIME_IMAGE build args remain unchanged unless 8.1.1 requires Java 21 (will validate in Phase 0)
- [x] **Distroless compatibility**: No shell assumptions in runtime containers; ENTRYPOINT remains exec-form; 8.1.1 JAR runs identically to 7.6.1.
  - ✅ Runtime stage unchanged; Schema Registry 8.1.1 JAR invocation identical to 7.6.1
- [x] **Supply-chain security**: 
  - [x] Runtime images run as non-root user (UID 65532) - unchanged from feature 001.
  - [x] No `curl | bash` installers - submodule update only, no new build steps.
  - [x] Base images remain pinned (or pinning strategy documented) - no changes to base image strategy.
  - [x] OCI labels updated to reflect 8.1.1 version - Makefile VERSION extraction handles automatically.
- [x] **Licensing compliance**: No upstream code copied; git submodule reference updated to 8.1.1 tag; README compliance section remains accurate.
  - ✅ Submodule-only approach preserved; no code duplication
- [x] **Repository ergonomics**: Makefile targets remain functional (`make build`, `make buildx`, `make test`, `make help`); no changes to ergonomics.
  - ✅ All targets version-agnostic; user experience unchanged
- [x] **Testing validation**: CI builds both architectures unchanged; smoke tests validate 8.1.1 container startup and `/subjects` endpoint.
  - ✅ Existing test infrastructure applies to 8.1.1; no test changes needed unless API breaks

**Violations**: None - this is a version update that maintains all constitution gates from feature 001

## Project Structure

### Documentation (this feature)

```text
specs/002-upgrade-8-1-1/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output: upstream 8.1.1 changes, Java version, breaking changes
├── data-model.md        # Phase 1 output: updated version entities (8.1.1 metadata)
├── quickstart.md        # Phase 1 output: upgrade workflow documentation
├── contracts/           # Phase 1 output: version label contract (if needed)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root - MINIMAL CHANGES)

```text
.
├── upstream/
│   └── schema-registry/            # Git submodule: UPDATE commit pointer to 8.1.1 tag
├── CHANGELOG.md                    # UPDATE: Add 8.1.1 upgrade section
├── README.md                       # UPDATE: Version references 7.6.1 → 8.1.1 (if hardcoded)
├── Dockerfile                      # NO CHANGE (unless Java 21 required)
├── Makefile                        # NO CHANGE (VERSION extraction automatic from submodule)
├── config/
│   ├── schema-registry.properties  # VALIDATE: Test compatibility with 8.1.1
│   └── examples/
│       ├── development.properties  # VALIDATE: Test compatibility with 8.1.1
│       └── production.properties   # VALIDATE: Test compatibility with 8.1.1
├── specs/
│   └── 002-upgrade-8-1-1/          # NEW: This feature's planning docs
├── tests/
│   └── smoke.sh                    # VALIDATE: Test passes with 8.1.1 (no changes expected)
└── .github/
    └── workflows/
        └── build-image.yml         # NO CHANGE (workflow version-agnostic)
```

**Structure Decision**: This is a version upgrade, not a new feature. All build infrastructure from feature 001 is reused. Only changes: submodule commit pointer, CHANGELOG documentation, and validation testing. No new source files required. Documentation in `specs/002-upgrade-8-1-1/` captures upgrade-specific planning and validation steps.

## Complexity Tracking

No complexity violations—this upgrade maintains all constitution gates from feature 001. The existing multi-arch, base-image-pluggable, distroless-compatible infrastructure handles version changes without modifications. Only unknown is whether 8.1.1 requires Java 21 (will research in Phase 0), in which case BUILDER_IMAGE and RUNTIME_IMAGE defaults must be updated.

## Phase 0-1 Artifacts

**Phase 0 (Research)**: ✅ Required
- [research.md](research.md) - Upstream 8.1.1 release notes review, Java version requirement check, Maven build compatibility check, breaking API changes identification, configuration schema comparison, Chainguard JRE 17 vs 21 compatibility

**Phase 1 (Design)**: ✅ Required
- [data-model.md](data-model.md) - Updated version metadata entity (8.1.1+infoblox.1), submodule reference entity, OCI label contract
- [contracts/version-labels.md](contracts/version-labels.md) - OCI label contract for 8.1.1 (if changes needed)
- [quickstart.md](quickstart.md) - Upgrade workflow: update submodule → rebuild → test → verify labels → document breaking changes

**Agent Context**: ✅ Update not needed
- Existing [.github/agents/copilot-instructions.md](../../.github/agents/copilot-instructions.md) already covers Java 17, Maven 3.x, Docker BuildKit, Git submodules from feature 001. No technology additions for version upgrade.

## Constitution Re-Check (Post-Design)

All gates remain ✅ PASS after Phase 1 design. This upgrade leverages existing constitution-compliant infrastructure:
- research.md confirms 8.1.1 build process compatibility
- data-model.md defines version metadata without infrastructure changes
- quickstart.md documents upgrade workflow maintaining all gates
- No shell assumptions introduced
- No base image changes (unless Java 21 required, in which case documented and tested)

## Next Steps

Run `/speckit.tasks` to generate task breakdown. Expected phases:

### Phase 1: Prerequisites Validation
- Validate upstream 8.1.1 tag exists
- Verify git submodule status before update
- Confirm clean working directory

### Phase 2: Submodule Update
- Fetch upstream tags
- Checkout 8.1.1 tag in submodule
- Stage submodule commit pointer update

### Phase 3: Build Validation
- Test Maven build with 8.1.1 source (Java 17 compatibility)
- Build native platform image
- Verify OCI labels contain 8.1.1+infoblox.1
- Run smoke tests on single architecture

### Phase 4: Multi-Architecture Validation
- Build both linux/amd64 and linux/arm64
- Inspect multi-arch manifest
- Run smoke tests on both architectures

### Phase 5: Base Image Compatibility
- Build with Chainguard JRE default (smoke tests)
- Build with Temurin override (smoke tests)
- Compare image sizes and CVE counts
- Verify distroless on Chainguard variant

### Phase 6: Configuration Validation
- Test existing config/schema-registry.properties
- Test config/examples/development.properties
- Test config/examples/production.properties
- Document any deprecation warnings or new properties

### Phase 7: Documentation Updates
- Update CHANGELOG.md with 8.1.1 section
- Update README.md version references (if hardcoded)
- Document breaking changes (if any discovered)
- Document known issues (if any discovered)

### Phase 8: Final Validation & Commit
- Review all changes (git diff)
- Run final smoke test pass
- Commit submodule update + documentation
- Tag release (optional)

**Estimated task count**: ~25-30 tasks (minimal scope compared to feature 001's 99 tasks)

**Critical path**: Phase 2 (submodule) → Phase 3 (build validation) → Phase 7 (documentation)

**Parallelizable**: Phase 5 (base image tests) can run parallel to Phase 6 (config tests)
