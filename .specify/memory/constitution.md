# ib-schema-registry Constitution

## Scope & Goals

### I. Project Mission

This project builds and publishes a **portable, multi-architecture OCI container image** for Confluent Schema Registry, built from upstream source (Apache 2.0 components + Confluent Community License components). The image MUST be:

- **Source-based**: Built from upstream Confluent Schema Registry source (via git submodule or pinned tarball), not derived from `confluentinc/cp-schema-registry` image layers.
- **Multi-arch native**: Supports `linux/amd64` and `linux/arm64` without emulation or platform-specific workarounds.
- **Minimal & auditable**: Uses distroless-compatible runtime images (no shell requirement at runtime), minimal layer count, pinned dependencies.
- **Pluggable base images**: Swappable builder and runtime base images (e.g., Chainguard JDK/Maven for build, Chainguard JRE for runtime).

**Out of Scope (Milestone 1)**: Helm charts, Kubernetes operators, or multi-service orchestration. These may be added in future milestones but MUST NOT block Milestone 1 (working Docker image).

**Rationale**: Provides ARM-native Schema Registry for Apple Silicon development and ARM-based production deployments; avoids Confluent's dockerfile-maven-plugin limitations; enables supply-chain-secured base images.

## Core Principles

### II. Multi-Architecture Build Portability (NON-NEGOTIABLE)

All build tooling, scripts, and workflows MUST produce **identical functional artifacts** on:

- **macOS Apple Silicon** (darwin/arm64): Local developer builds via `make` targets.
- **Linux x86_64**: CI builds (GitHub Actions) and production build environments.
- **Docker buildx multi-platform**: Simultaneous `linux/amd64` and `linux/arm64` output in single command.

**Forbidden Approaches**:

- Platform-specific scripts (e.g., `build-macos.sh` vs `build-linux.sh`) unless wrapped in unified Makefile targets.
- Emulation-based builds (QEMU for opposite architecture) for primary workflows—acceptable only for troubleshooting.
- Docker socket bind mounts + socat workarounds for Maven Docker integration (Spotify plugin anti-pattern).

**Required Validations**:

- CI MUST build both architectures (`docker buildx build --platform linux/amd64,linux/arm64`).
- Local build targets MUST work identically on macOS ARM and Linux x86_64 (tested via `make build` on both).

**Rationale**: Ensures developer/CI parity, avoids "works on my machine" failures, and prevents ARM vs x86 behavioral divergence.

### III. Base Image Pluggability & Distroless Compatibility (NON-NEGOTIABLE)

Build system MUST support swapping base images via build arguments or environment variables:

- **Builder image** (default: `docker.io/library/maven:3-eclipse-temurin-17`; alternate: `cgr.dev/chainguard/maven:latest-dev`).
- **Runtime image** (default: `docker.io/library/eclipse-temurin:17-jre`; alternate: `cgr.dev/chainguard/jre:latest`).

**Distroless Constraints**:

- Runtime image MAY lack shell (`/bin/sh`, `/bin/bash`).
- Entrypoint MUST use `["exec-form"]` notation (not `/bin/sh -c`).
- Startup scripts MUST be pre-compiled (Java main class invocation) or use minimal POSIX tools guaranteed in distroless (none assumed).
- Health checks and debugging MUST NOT rely on shell commands in runtime image (use HTTP probes or Java-based tooling).

**Configuration Mechanism**:

- Makefile/Dockerfile MUST accept `BUILDER_IMAGE` and `RUNTIME_IMAGE` build args.
- Defaults MUST be documented in README and Makefile comments.
- CI MUST test at least one Chainguard-based build variant per release cycle.

**Rationale**: Enables supply-chain hardening (Chainguard/Wolfi), minimizes CVE surface area, and prevents lock-in to specific base image vendors.

### IV. Supply-Chain & Security Requirements (NON-NEGOTIABLE)

All artifacts MUST adhere to supply-chain security best practices:

**Image Construction**:

- **Non-root runtime**: Final image runs as non-root user (UID > 1000, documented in Dockerfile).
- **Pinned dependencies**: Base images pinned by SHA256 digest (e.g., `maven@sha256:abc123...`), not `latest` tags, in production Dockerfiles (development `latest` acceptable if documented).
- **Minimal layers**: Avoid `RUN curl | bash` installers; prefer distro package managers or pre-built binaries from trusted sources.
- **No secrets in layers**: Build args for credentials, never `ENV` or `COPY` of secret files.

**OCI Metadata**:

- Images MUST include OCI annotations: `org.opencontainers.image.source`, `org.opencontainers.image.version`, `org.opencontainers.image.revision` (Git commit SHA).
- SBOM generation RECOMMENDED (via Syft or buildkit SBOM output) but NOT blocking for Milestone 1.
- Provenance attestation RECOMMENDED (via `docker buildx --provenance=true`) but NOT blocking for Milestone 1.

**Dependency Management**:

- Maven dependencies MUST be version-pinned in `pom.xml` (no `LATEST`, `RELEASE` version ranges).
- Dependency updates MUST be reviewed for license compatibility and CVE status before merging.

**Rationale**: Enables verifiable builds, reduces attack surface, and aligns with supply-chain security frameworks (SLSA, in-toto).

### V. Licensing & Compliance

Upstream Confluent Schema Registry is dual-licensed (Apache 2.0 + Confluent Community License for proprietary components). This project:

- **MUST NOT copy upstream code into this repository** beyond a Git submodule reference or pinned source tarball download.
- **MUST include a clear LICENSE.md** in repository root stating:
  - This repository's build tooling is licensed under `[PROJECT_LICENSE]` (e.g., Apache 2.0 or MIT).
  - Upstream Confluent Schema Registry code is subject to Confluent's licenses (Apache 2.0 + Confluent Community License).
  - Link to upstream license files and compliance documentation.
- **README MUST include a "Compliance" section** warning users that Confluent Community License has use restrictions (e.g., no competing SaaS offerings).

**Build Artifact Compliance**:

- Resulting Docker image MUST include upstream `LICENSE` and `NOTICE` files in `/opt/schema-registry/licenses/` or similar documented path.
- SBOM (if generated) MUST list Confluent components with accurate license metadata.

**Rationale**: Prevents license violations, provides transparency to users, and avoids legal risk from misrepresenting upstream license terms.

### VI. Repository Ergonomics & Developer Experience

Repository MUST be approachable for new contributors and provide predictable workflows:

**Makefile Targets** (REQUIRED):

- `make build`: Build Docker image for native platform (automatic platform detection).
- `make build-multiarch`: Build for `linux/amd64,linux/arm64` simultaneously (requires Docker buildx).
- `make test`: Run smoke tests (basic container startup validation).
- `make clean`: Remove build artifacts and dangling images.
- `make help`: Display all available targets with descriptions.

**Naming Conventions**:

- Image tag format: `[REGISTRY]/ib-schema-registry:[VERSION]-[VARIANT]` (e.g., `ghcr.io/infobloxopen/ib-schema-registry:7.6.1-chainguard`).
- Version MUST match upstream Schema Registry version (e.g., `7.6.1`), with optional `-dev` suffix for unreleased builds.
- Variant suffix OPTIONAL to distinguish base image choices (e.g., `-chainguard`, `-eclipse-temurin`).

**Documentation**:

- **README.md** MUST include: quickstart build command, runtime example (`docker run`), configuration env vars, compliance section.
- **CONTRIBUTING.md** MUST document: PR requirements, build prerequisites (Docker version, buildx setup), testing steps.
- **Inline comments** in Dockerfile and Makefile for non-obvious decisions (e.g., why specific base image, why specific Maven flags).

**Predictable Outputs**:

- Built images MUST output final tag names to stdout at completion.
- Failed builds MUST emit actionable error messages (not silent failures).

**Rationale**: Reduces onboarding friction, prevents tribal knowledge, and enables self-service contributions.

### VII. Testing & Validation Requirements

Minimum validation gates before merge:

**Build Validation** (REQUIRED):

- CI MUST successfully build both `linux/amd64` and `linux/arm64` images.
- Build MUST NOT require Docker socket bind mounts or privileged mode (except for buildx setup, which is standard).
- Build time SHOULD be <15 minutes for clean builds in CI (measured on GitHub Actions standard runners).

**Smoke Tests** (REQUIRED):

- Container MUST start successfully (`docker run` exits 0 after init, or reaches ready state).
- Health endpoint (if exposed, e.g., `/health`) MUST return 200 OK within 30 seconds of startup.
- Basic API validation: `GET /subjects` MUST return empty array `[]` on fresh container (no Kafka cluster required for this minimal test).

**Smoke tests MUST NOT require**:

- Full Kafka cluster (unless explicitly documented as "integration test" separate from smoke tests).
- External dependencies beyond the Schema Registry container itself.

**Expanded Testing** (OPTIONAL, documented separately):

- Integration tests with Kafka cluster (documented in `docs/integration-testing.md` if implemented).
- Load testing or performance benchmarks (NOT required for Milestone 1).

**Test Automation**:

- Smoke tests MUST run in CI via `make test` target.
- Test failures MUST fail the CI build (non-zero exit code).

**Rationale**: Prevents regressions without requiring expensive full-stack integration tests for every PR; provides fast feedback loop.

### VIII. Governance & Compatibility

**Constitution Primacy**:

- This constitution supersedes any ad-hoc decisions or prior patterns not documented here.
- Amendments require PR approval from at least one maintainer + updated version number (see below).

**Amendment Process**:

- Propose changes via PR to `.specify/memory/constitution.md`.
- Increment version per semantic versioning:
  - **MAJOR**: Removing or fundamentally changing a NON-NEGOTIABLE principle (e.g., removing multi-arch requirement).
  - **MINOR**: Adding new principles or expanding existing sections with new requirements.
  - **PATCH**: Clarifications, typo fixes, example updates without semantic change.
- Update `LAST_AMENDED_DATE` to amendment merge date.

**Backward Compatibility for Image Consumers**:

- Image tag format MUST remain stable (see §VI naming conventions).
- Breaking changes to runtime env vars or entrypoint behavior MUST be documented in CHANGELOG and image tag (e.g., `8.0.0-breaking`).
- Deprecated features MUST be warned for at least one minor version before removal.

**PR Review Requirements**:

- All PRs MUST pass CI build validation and smoke tests (see §VII).
- Security-sensitive changes (base image changes, dependency updates) MUST include rationale and CVE review.
- PRs MUST NOT introduce platform-specific hacks (see §II portability principle).

**Rationale**: Ensures stability for downstream users while allowing principled evolution of the project.

## Definition of Done

Every PR MUST satisfy this checklist before merge:

- [ ] **Build**: Successfully builds for `linux/amd64` and `linux/arm64` in CI.
- [ ] **Smoke tests**: Passes `make test` (container starts, basic API responds).
- [ ] **Documentation**: Updates README or relevant docs if behavior/config changes.
- [ ] **Security invariants**:
  - [ ] Non-root runtime user (if Dockerfile modified).
  - [ ] No shell assumptions in ENTRYPOINT/CMD (distroless-compatible).
  - [ ] Base image pinning strategy maintained (digests for prod, or documented exception).
- [ ] **Licensing**: No upstream code copied into repo; LICENSE.md remains accurate.
- [ ] **Constitution compliance**: No violations of NON-NEGOTIABLE principles (§II-§IV).
- [ ] **Versioning**: Image tags follow naming convention (§VI); CHANGELOG updated if user-facing change.

**Optional (if applicable)**:

- [ ] Integration tests pass (if modified integration test suite).
- [ ] SBOM/provenance generated (if release artifact).

**Version**: 1.0.0 | **Ratified**: 2026-01-15 | **Last Amended**: 2026-01-15
