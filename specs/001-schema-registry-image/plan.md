# Implementation Plan: Multi-Architecture Schema Registry Container Image

**Branch**: `001-schema-registry-image` | **Date**: 2026-01-15 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-schema-registry-image/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Build a portable, multi-architecture OCI container image for Confluent Schema Registry from upstream source without using Confluent's dockerfile-maven-plugin. The image supports linux/amd64 and linux/arm64, enables pluggable base images (Eclipse Temurin default, Chainguard alternative), and is distroless-compatible. Implementation uses Docker BuildKit multi-stage builds with Maven for upstream compilation, Makefile for developer ergonomics, and GitHub Actions for CI/CD automation. Core technical approach: BuildKit BUILDPLATFORM/TARGETPLATFORM for cross-compilation, cache mounts for Maven dependencies, JSON exec-form entrypoint, non-root runtime user, and git submodule for upstream source tracking.

## Technical Context

**Language/Version**: Java 17 (upstream Schema Registry requirement; OpenJDK/Temurin compatible)  
**Primary Dependencies**: Maven 3.x (build tool), Docker BuildKit 0.11+ (multi-platform support), Git (submodule management), upstream confluentinc/schema-registry (source)  
**Storage**: N/A (stateless container; Kafka cluster provides persistence)  
**Testing**: Shell scripts for smoke tests (container start + HTTP `/subjects` endpoint check); no unit tests in this repo (build infrastructure only)  
**Target Platform**: linux/amd64 and linux/arm64 container runtime (Docker, containerd, Kubernetes)  
**Project Type**: Build infrastructure / container image (not application code)  
**Performance Goals**: Cold build <15 min in CI, warm build (cached Maven deps) <5 min, container startup <30 sec  
**Constraints**: Distroless-compatible (no shell in runtime), non-root (UID 65532), BuildKit required, multi-arch mandatory, no Spotify plugin  
**Scale/Scope**: Single Dockerfile + Makefile + CI workflow + config template; ~500-800 lines total; supports Schema Registry 7.x versions

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] **Multi-arch portability**: Build approach works identically on macOS ARM and Linux x86; no platform-specific scripts outside unified Makefile targets.
  - ✅ Makefile provides unified interface; Dockerfile uses BuildKit BUILDPLATFORM/TARGETPLATFORM; no OS-specific logic
- [x] **Base image pluggability**: Builder and runtime images configurable via build args; no hardcoded base image references that prevent swapping (e.g., Chainguard alternatives).
  - ✅ `BUILDER_IMAGE` and `RUNTIME_IMAGE` build args in Dockerfile; defaults documented; Makefile supports overrides
- [x] **Distroless compatibility**: No shell assumptions in runtime containers; ENTRYPOINT uses exec-form notation; no `/bin/sh -c` wrappers.
  - ✅ Runtime stage has zero `RUN` commands; ENTRYPOINT `["java", "-jar", ...]`; no shell dependencies
- [x] **Supply-chain security**: 
  - [x] Runtime images run as non-root user (UID > 1000).
    - ✅ USER 65532 in Dockerfile; COPY --chown=65532:65532 for file ownership
  - [x] No `curl | bash` installers or untrusted binary downloads.
    - ✅ Maven downloads from Central via upstream build; no custom installers
  - [x] Base images pinned by digest (production) or pinning strategy documented (development).
    - ✅ Milestone 1 uses tags; README documents digest pinning best practice with examples
  - [x] OCI labels included (`org.opencontainers.image.*` annotations).
    - ✅ Dockerfile LABEL instructions with source, version, revision, created, title, description, vendor
- [x] **Licensing compliance**: No upstream code copied into repo beyond submodule/tarball reference; README includes compliance section with upstream license warnings.
  - ✅ Git submodule only; README has compliance section citing Confluent Community License restrictions
- [x] **Repository ergonomics**: Makefile targets documented and tested (`make build`, `make build-multiarch`, `make test`, `make help`).
  - ✅ Makefile with help target (default); build, buildx, push, test targets; inline comments
- [x] **Testing validation**: CI builds both `linux/amd64` and `linux/arm64`; smoke tests validate container startup and basic API without requiring full Kafka cluster.
  - ✅ GitHub Actions workflow builds both archs with buildx; smoke.sh tests /subjects endpoint

**Violations**: None

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
.
├── Dockerfile                      # Multi-stage build: builder + runtime
├── .dockerignore                   # Exclude .git, docs from build context
├── Makefile                        # Targets: help, build, buildx, push, test, submodule-*
├── LICENSE.md                      # Repo tooling license + upstream license notice
├── README.md                       # Quickstart, compliance section, examples
├── config/
│   └── schema-registry.properties  # Default config (kafka:9092, port 8081)
├── .github/
│   └── workflows/
│       └── build-image.yml         # Multi-arch CI: QEMU, buildx, GHCR push
├── upstream/
│   └── schema-registry/            # Git submodule -> confluentinc/schema-registry
└── tests/
    └── smoke.sh                    # Container start + GET /subjects validation
```

**Structure Decision**: Build infrastructure repository (not application code). No `src/` directory needed—Dockerfile orchestrates Maven build of upstream submodule. Makefile provides unified interface for local and CI builds. Configuration template in `config/` serves as default (user mounts custom config in production). Tests are minimal smoke validation scripts, not unit tests (upstream has tests).

## Complexity Tracking

No complexity violations—all constitution gates passed. Design adheres to NON-NEGOTIABLE principles:
- Multi-arch portability via BuildKit BUILDPLATFORM/TARGETPLATFORM
- Base image pluggability via build args
- Distroless compatibility via JSON exec-form entrypoint, zero RUN commands in runtime stage
- Supply-chain security via non-root user, OCI labels, documented digest pinning
- Licensing compliance via submodule-only approach
- Repository ergonomics via Makefile targets
- Testing validation via CI multi-arch builds + smoke tests

## Phase 0-1 Artifacts

**Phase 0 (Research)**: ✅ Complete
- [research.md](research.md) - Upstream build process, base image selection, BuildKit strategy, distroless compatibility, version extraction, smoke test approach

**Phase 1 (Design)**: ✅ Complete
- [data-model.md](data-model.md) - Build entities (ContainerImage, BuildArtifact, SourceReference, RuntimeConfiguration, BuildConfiguration, OCILabels, CIWorkflow)
- [contracts/oci-labels.md](contracts/oci-labels.md) - Required OCI image annotations contract
- [quickstart.md](quickstart.md) - Getting started guide for building and running locally

**Agent Context**: ✅ Updated
- [.github/agents/copilot-instructions.md](../../.github/agents/copilot-instructions.md) - Java 17, Maven 3.x, Docker BuildKit, Git submodules

## Constitution Re-Check (Post-Design)

All gates remain ✅ PASS. Design artifacts validate:
- research.md confirms BuildKit multi-platform approach works on macOS ARM + Linux x86
- data-model.md defines BuildConfiguration with BUILDER_IMAGE/RUNTIME_IMAGE attributes (pluggability)
- contracts/oci-labels.md specifies all required OCI labels (SPR-011 compliance)
- quickstart.md documents Makefile targets and Chainguard alternative examples (ergonomics)
- No shell assumptions in design (distroless-compatible)

## Next Steps

Run `/speckit.tasks` to generate task breakdown organized by user stories:
- Phase 1: Setup (project structure, submodule init)
- Phase 2: Foundational (Dockerfile, Makefile, config template)
- Phase 3-8: User story implementation (US1-US6 from spec.md)
- Phase 9: Validation (CI workflow, smoke tests, documentation)
