# Feature Specification: Multi-Architecture Schema Registry Container Image

**Feature Branch**: `001-schema-registry-image`  
**Created**: 2026-01-15  
**Status**: Draft  
**Input**: User description: "Create a NEW git repository that builds an OCI/Docker image for Confluent's upstream Schema Registry (the confluentinc/schema-registry source repo), but WITHOUT using Confluent's Spotify dockerfile-maven-plugin flow. The goal is a clean, portable, multi-arch image that can be built locally and in GitHub Actions, and can swap base images (e.g., Chainguard JRE/JDK)."

## Clarifications

### Session 2026-01-15

- Q: Default Kafka bootstrap servers configuration: localhost, Docker Compose service name, or force user config? → A: `kafka:9092` (Docker Compose service name for standard local dev pattern)
- Q: Image version strategy: extract from upstream submodule, manual VERSION file, or decoupled? → A: Use upstream tag with semver-appropriate suffix for local builds (e.g., `7.6.1+infoblox.1` or `7.6.1-ib.1`)
- Q: Health check endpoint for smoke tests: `/`, `/subjects`, custom `/health`, or multiple? → A: `/subjects` endpoint (validates full service initialization, returns deterministic `[]`)
- Q: Base image digest pinning: enforce from day one, never pin, or document for production? → A: Use tags in Milestone 1 for development velocity, document digest pinning as production best practice in README
- Q: CI build time expectations: hard 15 min limit, differentiate cached vs uncached, or increase tolerance? → A: 15 min for first/uncached build, 5 min for cached dependencies (warm build with Maven cache hit)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Local Multi-Architecture Build (Priority: P1)

A platform engineer needs to build Schema Registry container image on their Apple Silicon Mac for local development and testing. They want a single command to produce a working image without complex platform workarounds or emulation.

**Why this priority**: Core MVP functionality. Enables immediate local development and validates the multi-arch build approach works correctly. Without this, the entire build system fails its primary goal.

**Independent Test**: Clone repository, run `make build`, verify image starts and responds to basic HTTP health check on port 8081. No Kafka cluster required for this basic validation.

**Acceptance Scenarios**:

1. **Given** a developer with Docker Desktop on macOS Apple Silicon, **When** they run `make build`, **Then** a `linux/arm64` image is created and tagged locally
2. **Given** a developer with Docker on Linux x86_64, **When** they run `make build`, **Then** a `linux/amd64` image is created and tagged locally
3. **Given** either platform, **When** they run `docker run <image>`, **Then** the container starts successfully and listens on port 8081
4. **Given** a running container, **When** they query `GET /subjects`, **Then** the API responds with `[]` (empty array) even without Kafka configured

---

### User Story 2 - Simultaneous Multi-Arch Build (Priority: P1)

A release engineer needs to build both `linux/amd64` and `linux/arm64` images simultaneously using Docker buildx, producing artifacts ready for registry push without building twice.

**Why this priority**: Required for production release workflow. Single-pass multi-arch builds are standard practice and reduce build time by 50% compared to sequential builds.

**Independent Test**: Run `make buildx`, verify both architectures are built in one invocation (check buildx output logs), inspect manifest to confirm both architectures present.

**Acceptance Scenarios**:

1. **Given** Docker buildx configured, **When** engineer runs `make buildx`, **Then** both `linux/amd64` and `linux/arm64` images build in parallel
2. **Given** successful multi-arch build, **When** inspecting the image manifest, **Then** both platform variants are listed with correct architecture metadata
3. **Given** multi-arch build time vs sequential, **When** measured, **Then** buildx completes in approximately same time as single-arch build (parallel execution)

---

### User Story 3 - Pluggable Base Images (Priority: P1)

A security-conscious engineer wants to swap the default base images (Eclipse Temurin) for Chainguard's minimal JRE/Maven images to reduce CVE surface area, without modifying the Dockerfile.

**Why this priority**: Core non-negotiable requirement per constitution. Supply-chain security and distroless compatibility are first-class concerns that must work from day one.

**Independent Test**: Build image with `RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest BUILDER_IMAGE=cgr.dev/chainguard/maven:latest-dev`, verify resulting image runs without shell dependencies, validate non-root user, confirm smaller image size.

**Acceptance Scenarios**:

1. **Given** default Makefile configuration, **When** engineer overrides `RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest`, **Then** final image uses Chainguard JRE base
2. **Given** Chainguard runtime base (no shell), **When** container starts, **Then** Java process launches successfully without shell wrapper scripts
3. **Given** any supported base image swap, **When** building, **Then** no Dockerfile edits required (build args only)
4. **Given** Chainguard minimal base, **When** image is scanned, **Then** significantly fewer CVEs compared to standard base image

---

### User Story 4 - CI/CD Automated Multi-Arch Build (Priority: P2)

A DevOps engineer needs GitHub Actions to automatically build and push multi-arch images on every push to main, with proper tagging for versioning and caching to minimize build times.

**Why this priority**: Automation is essential for sustainable operations, but manual builds (P1) must work first. CI is a force multiplier, not a blocker for initial development.

**Independent Test**: Push commit to main branch, verify GitHub Actions workflow runs, check GHCR for newly pushed multi-arch image with correct tags (commit SHA, `latest`, version if tagged).

**Acceptance Scenarios**:

1. **Given** a push to main branch, **When** GitHub Actions runs, **Then** both architectures build successfully and push to GHCR
2. **Given** a PR event, **When** workflow runs, **Then** image builds for validation but does NOT push to registry
3. **Given** a version tag push (`v7.6.1`), **When** workflow runs, **Then** image is tagged with version number and pushed
4. **Given** repeat builds, **When** using GHA cache, **Then** subsequent builds complete in <50% time of initial build (cache hit)

---

### User Story 5 - Upstream Source Tracking (Priority: P2)

A developer needs to update to a newer Schema Registry version by updating the git submodule reference without copying upstream code into the repository.

**Why this priority**: Ensures licensing compliance and maintainability. Prevents code drift from upstream, but isn't required for initial image build to work.

**Independent Test**: Update submodule to newer tag, rebuild image, verify new version metadata in OCI labels and runtime output.

**Acceptance Scenarios**:

1. **Given** upstream releases Schema Registry 7.7.0, **When** developer updates submodule to tag `7.7.0`, **Then** rebuild produces image with version 7.7.0
2. **Given** submodule reference, **When** building, **Then** no upstream source code is copied into this repository (only referenced via submodule)
3. **Given** submodule update, **When** Maven build runs, **Then** correct upstream version builds without manual pom.xml changes

---

### User Story 6 - Custom Runtime Configuration (Priority: P3)

A deployment engineer needs to run the image with production Kafka cluster settings by mounting a custom configuration file, overriding the default development config.

**Why this priority**: Production deployment requirement, but image must work with default config first. Can be addressed after core build system is proven.

**Independent Test**: Run container with `-v /path/to/prod-config.properties:/etc/schema-registry/schema-registry.properties`, verify Schema Registry connects to specified Kafka cluster and registers schemas.

**Acceptance Scenarios**:

1. **Given** custom config file with production Kafka bootstrap servers, **When** mounted to container, **Then** Schema Registry connects to production Kafka
2. **Given** default config in image, **When** no volume mount provided, **Then** container uses sensible localhost defaults for development
3. **Given** environment variable overrides (if supported), **When** set, **Then** they take precedence over config file values

---

### Edge Cases

- What happens when Maven build fails during Docker build? → Build must fail with actionable error message showing Maven output
- How does the system handle ARM vs x86 dependency resolution in Maven? → BuildKit's `--platform=$BUILDPLATFORM` for builder ensures Maven runs on native architecture, preventing cross-compilation issues
- What if base image doesn't exist or has architecture mismatch? → Docker buildx will fail with clear error about missing platform support
- What if Dockerfile assumes shell but runtime image has none? → Build will succeed, but container start will fail; prevented by using JSON exec form and no RUN commands in runtime stage
- What if upstream Schema Registry source changes build process? → Submodule pin ensures reproducibility; updates require explicit version bump and validation
- What happens when trying to run multi-arch buildx without buildx installed? → Makefile should check prerequisites and provide helpful error message

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST build Schema Registry from upstream source via Maven using command `mvn -DskipTests package -P standalone`
- **FR-002**: System MUST produce OCI-compliant container images for both `linux/amd64` and `linux/arm64` architectures
- **FR-003**: Build system MUST work identically on macOS Apple Silicon and Linux x86_64 developer machines
- **FR-004**: System MUST support single-platform local builds via `make build` (builds for native architecture)
- **FR-005**: System MUST support multi-platform builds via `make buildx` (builds for amd64 + arm64 simultaneously)
- **FR-006**: Dockerfile MUST extract standalone JAR from `package-schema-registry/target/kafka-schema-registry-package-*-standalone.jar`
- **FR-007**: Container MUST expose port 8081 for Schema Registry HTTP API
- **FR-008**: Container MUST start Schema Registry process with default config file at `/etc/schema-registry/schema-registry.properties`
- **FR-009**: System MUST include default configuration file with `listeners=http://0.0.0.0:8081` and `kafkastore.bootstrap.servers=PLAINTEXT://kafka:9092` (Docker Compose service name for local development)
- **FR-010**: Repository MUST track upstream source via git submodule at `upstream/schema-registry` pointing to `https://github.com/confluentinc/schema-registry`
- **FR-011**: System MUST provide Makefile targets: `help`, `submodule-init`, `submodule-update`, `build`, `buildx`, `push`
- **FR-012**: System MUST support registry push via `make push IMAGE=<registry>/<image> TAG=<tag>`
- **FR-013**: GitHub Actions workflow MUST build multi-arch on push to main branch
- **FR-014**: GitHub Actions workflow MUST build but NOT push on pull request events
- **FR-015**: GitHub Actions workflow MUST tag images with commit SHA and `latest` for main branch pushes
- **FR-016**: GitHub Actions workflow MUST tag images with version derived from upstream submodule tag plus local build suffix (e.g., `7.6.1+infoblox.1` or `7.6.1-ib.1`) for version tag pushes
- **FR-017**: Image version metadata in OCI labels MUST include both upstream Schema Registry version and local build identifier
- **FR-018**: Container MUST respond to `GET /subjects` endpoint with HTTP 200 and empty array `[]` within 30 seconds of startup (smoke test validation)

### Security & Portability Requirements *(if applicable)*

- **SPR-001**: Image MUST build for `linux/amd64` and `linux/arm64` without emulation or platform-specific workarounds
- **SPR-002**: Builder base image MUST be configurable via `BUILDER_IMAGE` build arg with default `maven:3-eclipse-temurin-17` (or similar public multi-arch image)
- **SPR-003**: Runtime base image MUST be configurable via `RUNTIME_IMAGE` build arg with default `eclipse-temurin:17-jre` (or similar)
- **SPR-004**: Runtime container MUST run as non-root user with numeric UID ≥ 65532 (default: 65532)
- **SPR-005**: Runtime stage MUST NOT use `RUN` instructions (distroless compatibility - no shell assumption)
- **SPR-006**: ENTRYPOINT and CMD MUST use JSON exec form notation (e.g., `["java", "-jar", "..."]`), NOT shell form
- **SPR-007**: Dockerfile MUST use BuildKit syntax header `# syntax=docker/dockerfile:1.7` or newer
- **SPR-008**: Builder stage MUST run on `BUILDPLATFORM` (native architecture) to avoid cross-compilation issues
- **SPR-009**: Runtime stage MUST run on `TARGETPLATFORM` (target architecture)
- **SPR-010**: Builder stage MUST use BuildKit cache mounts for Maven repository (`--mount=type=cache,target=/root/.m2`)
- **SPR-011**: Image MUST include OCI labels: `org.opencontainers.image.source`, `org.opencontainers.image.version`, `org.opencontainers.image.revision`, `org.opencontainers.image.created`, `org.opencontainers.image.title`, `org.opencontainers.image.description`, `org.opencontainers.image.vendor`
- **SPR-012**: Dockerfile MUST use version tags for base images in Milestone 1 (e.g., `maven:3-eclipse-temurin-17`); README MUST document digest pinning strategy as production best practice with examples
- **SPR-013**: Build system MUST NOT use Confluent's Spotify dockerfile-maven-plugin or socat Docker socket workarounds
- **SPR-014**: Makefile MUST document how to override base images with Chainguard alternatives
- **SPR-015**: README MUST include compliance section warning about Confluent Community License restrictions
- **SPR-016**: Repository MUST NOT copy upstream Schema Registry source code (only reference via submodule)
- **SPR-017**: GitHub Actions workflow MUST set up QEMU for cross-platform build support
- **SPR-018**: GitHub Actions workflow MUST use Docker buildx with cache-from/cache-to for layer caching
- **SPR-019**: GitHub Actions workflow MUST only login to GHCR on push events (skip on PRs for security)
- **SPR-020**: Files and directories in runtime image MUST have correct ownership via `COPY --chown=<uid>:<gid>`

### Key Entities *(include if feature involves data)*

- **Container Image**: Multi-arch OCI image containing Schema Registry standalone JAR, configuration, and minimal runtime environment
- **Build Configuration**: Makefile variables and Docker build args defining image name, tag, platforms, and base images
- **Source Reference**: Git submodule pointer to specific upstream Schema Registry version
- **Runtime Configuration**: Properties file defining Kafka bootstrap servers, listeners, and Schema Registry settings
- **CI Workflow**: GitHub Actions workflow defining automated build, test, and push pipeline

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Developer can clone repository and build working image in under 5 commands (including submodule init)
- **SC-002**: Multi-arch build with cold cache (first build, no Maven dependencies cached) completes in under 15 minutes on GitHub Actions standard runners
- **SC-003**: Multi-arch build with warm cache (Maven dependencies cached, no source changes) completes in under 5 minutes in CI
- **SC-004**: Image successfully starts and responds to HTTP health check within 30 seconds of `docker run`
- **SC-005**: Image built with Chainguard base is at least 30% smaller than default Eclipse Temurin base (measured in MB)
- **SC-006**: Image built with Chainguard base has at least 50% fewer CVEs than default base (measured by Trivy or similar scanner)
- **SC-007**: Both `linux/amd64` and `linux/arm64` images pass identical smoke test (container start + API response)
- **SC-008**: Makefile `help` target displays all available targets with descriptions in under 1 second
- **SC-009**: Repository README enables new contributor to build image without consulting external documentation
- **SC-010**: GitHub Actions workflow successfully builds and pushes image on 100% of main branch commits (no manual intervention)

## Assumptions

- Docker Desktop (with buildx) or Docker CE with buildx plugin is available on developer machines
- GitHub Actions has access to push to GitHub Container Registry (GHCR) with appropriate permissions
- Upstream Confluent Schema Registry Maven build process remains stable (uses `mvn -DskipTests package -P standalone`)
- Default Java runtime environment (OpenJDK/Temurin 17+) is suitable for Schema Registry operation
- Kafka cluster configuration is provided externally (not built into image) for production deployments
- Users understand Confluent Community License restrictions and compliance requirements
- Docker BuildKit is enabled (default in Docker 23.0+, or set via `DOCKER_BUILDKIT=1`)
- For CI, GitHub Actions has sufficient runner capacity and network bandwidth for Maven dependency downloads
- Base images (Eclipse Temurin, Chainguard) maintain backward compatibility for Java 17+ runtime environment

## Dependencies

- **External**: Upstream Confluent Schema Registry source repository at `github.com/confluentinc/schema-registry`
- **External**: Public container registries for base images (Docker Hub for Eclipse Temurin, cgr.dev for Chainguard)
- **External**: Maven Central for Java dependencies during build process
- **Tooling**: Docker buildx for multi-platform builds
- **Tooling**: Git for submodule management
- **CI**: GitHub Actions for automated builds
- **CI**: GitHub Container Registry (GHCR) for image storage and distribution

## Out of Scope (Milestone 1)

- Helm charts or Kubernetes manifests (future milestone)
- SBOM generation (recommended but not blocking)
- Provenance attestation (recommended but not blocking)
- Image signing with cosign (future enhancement)
- Integration tests with full Kafka cluster (smoke test only validates container start)
- Performance benchmarking (basic startup time only)
- Monitoring/observability instrumentation beyond Schema Registry defaults
- Custom JVM tuning beyond `JAVA_TOOL_OPTIONS` environment variable support
- Load testing or HA configuration
- Schema validation beyond what upstream Schema Registry provides
