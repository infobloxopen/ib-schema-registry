# syntax=docker/dockerfile:1.7

# Global build arguments (must be before first FROM)
ARG BUILDER_IMAGE=maven:3-eclipse-temurin-17
ARG RUNTIME_IMAGE=cgr.dev/chainguard/jre:latest

# =============================================================================
# Builder Stage - Compile Schema Registry from upstream source
# =============================================================================
# Use --platform=$BUILDPLATFORM to run Maven on native architecture
# This prevents protoc cross-compilation issues (protoc-jar downloads platform-specific binaries)
FROM --platform=$BUILDPLATFORM ${BUILDER_IMAGE} AS builder

# Configure Maven memory settings for constrained environments
# Use less memory to avoid OOM in Docker environments with limited resources
ENV MAVEN_OPTS="-Xmx1536m -XX:+UseSerialGC -Xss256k"

# Set working directory for build
WORKDIR /workspace

# Copy upstream Schema Registry source (from git submodule)
COPY upstream/schema-registry /workspace/upstream/schema-registry

# Apply Infoblox patches for security updates
COPY patches /workspace/patches
RUN apt-get update && apt-get install -y patch && rm -rf /var/lib/apt/lists/* && \
    cd /workspace/upstream/schema-registry && \
    for patch in /workspace/patches/*.patch; do \
        echo "Applying patch: $(basename $patch)" && \
        patch -p1 < "$patch" || exit 1; \
    done

# Build Schema Registry standalone JAR with Maven
# - Use BuildKit cache mount for Maven dependencies to speed up rebuilds
# - Skip tests during build (tests run in upstream CI)
# - Use standalone profile to create single executable JAR
# - Disable memory-intensive plugins for constrained environments
# - Security patches applied via patches/ directory
WORKDIR /workspace/upstream/schema-registry

# Build the application (dependency versions patched in pom.xml)
RUN --mount=type=cache,target=/root/.m2 \
    mvn -DskipTests package -P standalone \
    -Dspotbugs.skip=true \
    -Dcheckstyle.skip=true \
    -Dcyclonedx.skip=true \
    -Dmaven.javadoc.skip=true \
    -Dhttp.keepAlive=false \
    -Dmaven.wagon.http.pool=false

# =============================================================================
# Runtime Stage - Minimal JRE with Schema Registry
# =============================================================================
FROM ${RUNTIME_IMAGE} AS runtime

# Metadata labels (OCI standard annotations)
ARG VERSION=dev
ARG REVISION=unknown
ARG CREATED=1970-01-01T00:00:00Z

LABEL org.opencontainers.image.title="Infoblox Schema Registry" \
      org.opencontainers.image.description="Multi-architecture Confluent Schema Registry container built from upstream source" \
      org.opencontainers.image.vendor="Infoblox Inc." \
      org.opencontainers.image.source="https://github.com/infobloxopen/ib-schema-registry" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.created="${CREATED}"

# Create non-root user for security (UID 65532 = nobody)
USER 65532:65532

# Create application directories
WORKDIR /app

# Copy Schema Registry standalone JAR from builder
# Use wildcard pattern to handle version-specific filename
COPY --from=builder --chown=65532:65532 \
    /workspace/upstream/schema-registry/package-schema-registry/target/kafka-schema-registry-package-*-standalone.jar \
    /app/schema-registry.jar

# Copy default configuration
COPY --chown=65532:65532 config/schema-registry.properties /etc/schema-registry/schema-registry.properties

# Expose Schema Registry HTTP API port
EXPOSE 8081

# Start Schema Registry with configuration file
# Use JSON exec-form for distroless compatibility (no shell required)
ENTRYPOINT ["java", "-jar", "/app/schema-registry.jar", "/etc/schema-registry/schema-registry.properties"]
