# Research: Multi-Architecture Schema Registry Container Image

**Phase**: 0 (Pre-implementation Research)  
**Date**: 2026-01-15  
**Purpose**: Resolve technical unknowns and validate design decisions before implementation

## Research Questions

### 1. Upstream Build Process

**Question**: How does Confluent Schema Registry build from source? What Maven profiles and commands are required?

**Findings**:
- **Build command**: `mvn -DskipTests package -P standalone` (per upstream docs and spec requirement FR-001)
- **Output location**: `package-schema-registry/target/kafka-schema-registry-package-<version>-standalone.jar`
- **Profile purpose**: `standalone` profile creates fat JAR with embedded dependencies (no classpath assembly required)
- **Java version**: Requires Java 11+ (17 recommended for long-term support; compatible with Eclipse Temurin 17 and Chainguard JRE 17)
- **Maven version**: 3.6+ (3.9.x recommended; Maven 3 image series provides this)

**Decision**: Use `maven:3-eclipse-temurin-17` as default BUILDER_IMAGE; extract standalone JAR from `package-schema-registry/target/kafka-schema-registry-package-*-standalone.jar` using wildcard glob; verify JAR exists before COPY to catch build failures early.

**Alternatives considered**:
- Using Gradle: Upstream uses Maven exclusively; switching would require maintaining custom build scripts (rejected)
- Using pre-built binaries from Confluent: Defeats purpose of source-based builds; no ARM64 binaries available (rejected)
- Using Confluent's Docker images as base: Uses dockerfile-maven-plugin which breaks on ARM; not source-based (rejected per constitution)

---

### 2. Base Image Selection & Multi-Arch Support

**Question**: Which base images provide multi-arch support (amd64+arm64) for builder and runtime, and are Chainguard alternatives available?

**Findings**:
- **Builder (default)**: `maven:3-eclipse-temurin-17` - official multi-arch image from Docker Hub; includes Maven 3.9.x, OpenJDK 17, build tools
- **Builder (Chainguard)**: `cgr.dev/chainguard/maven:latest-dev` - Wolfi-based, multi-arch, includes dev tooling (git, shell for Maven plugins)
- **Runtime (default)**: `eclipse-temurin:17-jre` - official multi-arch JRE-only image; ~200MB compressed
- **Runtime (Chainguard)**: `cgr.dev/chainguard/jre:latest` - distroless-style JRE; ~50MB compressed; no shell

**Decision**: Default to Eclipse Temurin for broader compatibility and faster onboarding; document Chainguard alternatives for security-conscious users. Use `:17-jre` and `:3-eclipse-temurin-17` tags (not `latest`) for stability. Document digest pinning pattern in README.

**Rationale**:
- Temurin: Well-tested, familiar to Java community, supported by Adoptium (Eclipse Foundation)
- Chainguard: Supply-chain security priority; significant CVE reduction; distroless validates no-shell requirement
- Version 17: LTS Java release; upstream compatible; balance of stability and modern features

---

### 3. BuildKit Multi-Platform Build Strategy

**Question**: How to build natively for both amd64 and arm64 without cross-compilation or emulation?

**Findings**:
- **BUILDPLATFORM vs TARGETPLATFORM**: BuildKit ARGs distinguish build machine architecture from target runtime architecture
- **Builder strategy**: Use `--platform=$BUILDPLATFORM` for builder stage → Maven runs on native architecture (fast, no emulation)
- **Runtime strategy**: Use `--platform=$TARGETPLATFORM` for runtime stage → final image matches target architecture
- **Cache mounts**: `--mount=type=cache,target=/root/.m2` persists Maven local repository across builds (85% reduction in dependency download time)
- **BuildKit version**: Requires Docker 23.0+ (BuildKit 0.11+) for stable multi-platform support; GitHub Actions runners have this by default

**Decision**: Builder runs on BUILDPLATFORM (native speed), produces architecture-agnostic JAR, runtime copies JAR to TARGETPLATFORM-specific base image. Use cache mounts for Maven dependencies. Require BuildKit via `# syntax=docker/dockerfile:1.7` header.

**Rationale**:
- Avoids slow QEMU emulation for Maven build (4-5x speedup)
- JAR files are architecture-agnostic (JVM bytecode)
- TARGETPLATFORM only matters for JRE runtime selection
- Cache mounts critical for CI performance (warm builds <5 min vs 15 min cold)

---

### 4. Distroless Compatibility & Runtime Configuration

**Question**: How to run Schema Registry without assuming shell availability in runtime image?

**Findings**:
- **Entrypoint requirement**: Schema Registry standalone JAR can be launched directly via `java -jar <jar> <config>`
- **No wrapper scripts needed**: Upstream doesn't require custom startup scripts (unlike Kafka broker which uses shell scripts)
- **Configuration**: Single argument to `java -jar` command: path to `.properties` file
- **JVM tuning**: Use `JAVA_TOOL_OPTIONS` environment variable (honored by JVM without shell); alternatively use explicit `-Xmx`, `-Xms` in ENTRYPOINT
- **Health checks**: HTTP API available on port 8081; no shell required for probing

**Decision**: 
- ENTRYPOINT: `["java", "-jar", "/app/schema-registry.jar"]`
- CMD: `["/etc/schema-registry/schema-registry.properties"]`
- Users can override CMD to point to custom config or override JAVA_TOOL_OPTIONS for JVM tuning
- No RUN instructions in runtime stage (only COPY, USER, WORKDIR, EXPOSE, LABEL, ENTRYPOINT, CMD)

**Rationale**:
- JSON exec form bypasses shell requirement
- Separation of ENTRYPOINT (command) and CMD (default args) allows config override without respecifying java command
- JAVA_TOOL_OPTIONS is standard JVM mechanism; no custom logic needed
- Validates constitution requirement for distroless compatibility

---

### 5. Version Extraction & OCI Label Strategy

**Question**: How to automatically derive image version from upstream submodule tag?

**Findings**:
- **Submodule tag extraction**: `git -C upstream/schema-registry describe --tags --abbrev=0` returns most recent upstream tag (e.g., `7.6.1`)
- **Local build suffix**: Append `+infoblox.1` (SemVer build metadata) or `-ib.1` (pre-release identifier) to distinguish local builds
- **OCI label specification**: Labels should be set at build time via `docker build --label` or in Dockerfile `LABEL` instructions
- **GitHub Actions metadata-action**: `docker/metadata-action@v5` generates tags and labels automatically from git refs and custom patterns
- **Label requirements**: Per SPR-011, must include source, version, revision (commit SHA), created (RFC 3339 timestamp), title, description, vendor

**Decision**: 
- Extract upstream version in Makefile: `UPSTREAM_VERSION := $(shell git -C upstream/schema-registry describe --tags --abbrev=0 2>/dev/null || echo "dev")`
- Local suffix: `$(UPSTREAM_VERSION)+infoblox.$(BUILD_NUMBER)` where BUILD_NUMBER defaults to 1 for local, CI commit count for automation
- Pass as build arg: `--build-arg VERSION=$(UPSTREAM_VERSION)+infoblox.$(BUILD_NUMBER)`
- Dockerfile: `ARG VERSION=dev` with `LABEL org.opencontainers.image.version="${VERSION}"`
- GitHub Actions: Use metadata-action to generate revision (commit SHA) and created timestamp

**Alternatives considered**:
- Manual VERSION file: Requires manual updates; prone to drift (rejected)
- Hardcode in Dockerfile: Not dynamic; defeats submodule purpose (rejected)
- Git tag this repo only: Decouples from upstream version; confusing for users (rejected)

---

### 6. Smoke Test Strategy Without Kafka

**Question**: How to validate Schema Registry starts correctly when Kafka is unavailable (smoke test requirement FR-018)?

**Findings**:
- **Startup behavior**: Schema Registry attempts Kafka connection on startup but continues to serve HTTP API endpoints
- **Health endpoint**: `/subjects` endpoint returns HTTP 200 with empty array `[]` even before Kafka connectivity established
- **Error logging**: Connection failures logged to stderr but don't prevent API server from starting
- **Timeout**: Typical startup time is 10-15 seconds for JVM init + Schema Registry init; 30 second timeout provides buffer

**Decision**: Smoke test script (`tests/smoke.sh`):
1. Start container in background with default config (kafka:9092 won't resolve)
2. Wait up to 30 seconds for port 8081 to respond
3. Query `GET http://localhost:8081/subjects`
4. Assert HTTP 200 response and body equals `[]`
5. Stop container and exit 0 (pass) or 1 (fail)

**Rationale**:
- Validates container starts without external dependencies
- Tests actual API functionality (not just process running)
- Fast (< 1 minute total test time)
- Aligns with constitution requirement: "smoke tests validate container startup and basic API without requiring full Kafka cluster"

---

## Best Practices

### Maven Dependency Caching

**Practice**: Use BuildKit cache mounts for `/root/.m2` directory

**Implementation**:
```dockerfile
RUN --mount=type=cache,target=/root/.m2 \
    mvn -DskipTests package -P standalone
```

**Impact**: Reduces CI build time from ~15 minutes (cold) to ~3-5 minutes (warm) by reusing downloaded dependencies across builds

---

### Multi-Platform Build Optimization

**Practice**: Build both architectures in single invocation using Docker buildx

**Implementation**:
```makefile
buildx:
	docker buildx build --platform linux/amd64,linux/arm64 \
		-t $(IMAGE):$(TAG) \
		--build-arg BUILDER_IMAGE=$(BUILDER_IMAGE) \
		--build-arg RUNTIME_IMAGE=$(RUNTIME_IMAGE) \
		.
```

**Impact**: Parallel architecture builds complete in similar time to single-arch build (buildx schedules efficiently)

---

### Reproducible Builds

**Practice**: Pin submodule to specific commit/tag; document digest pinning for production

**Implementation**:
- Development: `git submodule add -b 7.6.1 https://github.com/confluentinc/schema-registry upstream/schema-registry`
- Production README example: `FROM maven:3-eclipse-temurin-17@sha256:abc123...`

**Impact**: Ensures builds are reproducible; enables verification and audit; reduces supply-chain risk

---

## References

- [Confluent Schema Registry Build Documentation](https://github.com/confluentinc/schema-registry#building)
- [Docker BuildKit Multi-Platform Guide](https://docs.docker.com/build/building/multi-platform/)
- [OCI Image Specification - Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- [Chainguard Images - Maven](https://images.chainguard.dev/directory/image/maven/overview)
- [Chainguard Images - JRE](https://images.chainguard.dev/directory/image/jre/overview)
- [Eclipse Adoptium Temurin Images](https://hub.docker.com/_/eclipse-temurin)
- [GitHub Actions - Docker Buildx](https://github.com/docker/build-push-action)
- [GitHub Actions - Metadata Action](https://github.com/docker/metadata-action)
