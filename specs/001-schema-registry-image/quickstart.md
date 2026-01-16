# Quickstart: Multi-Architecture Schema Registry Container Image

**Purpose**: Get started building and running the Schema Registry image in under 5 minutes.

**Audience**: Platform engineers, DevOps, developers evaluating the image.

## Prerequisites

- **Docker**: Version 23.0+ with BuildKit enabled (check: `docker buildx version`)
- **Git**: For cloning repository and managing submodules
- **Platform**: macOS (Apple Silicon or Intel), Linux (x86_64 or ARM64), or Windows with WSL2

**Optional**:
- **Make**: For using Makefile targets (alternative: run Docker commands directly)
- **Kafka cluster**: For production testing (not required for smoke tests)

## Quick Start (Local Build)

### 1. Clone Repository with Submodules

```bash
git clone --recurse-submodules https://github.com/infobloxopen/ib-schema-registry.git
cd ib-schema-registry
```

**Or** if already cloned without submodules:

```bash
git submodule update --init --recursive
```

### 2. Build for Your Platform

```bash
make build
```

This builds an image for your native architecture (`linux/arm64` on Apple Silicon, `linux/amd64` on Intel/AMD).

**Output**: Image tagged as `ghcr.io/infobloxopen/ib-schema-registry:dev`

**Time**: ~12-15 minutes first build (Maven downloads dependencies), ~3-5 minutes subsequent builds (cached).

### 3. Run Smoke Test

```bash
make test
```

**What it does**: Starts container, waits for Schema Registry to initialize, queries `/subjects` endpoint, verifies response.

**Expected**: Test passes with exit code 0, confirming container starts successfully.

### 4. Run Interactively (Optional)

Start container with default config:

```bash
docker run -p 8081:8081 \
  -e JAVA_TOOL_OPTIONS="-Xms256m -Xmx512m" \
  ghcr.io/infobloxopen/ib-schema-registry:dev
```

Test API:

```bash
curl http://localhost:8081/subjects
# Expected: []
```

**Note**: Default config points to `kafka:9092` which won't resolve without Docker Compose or custom config. For full functionality, see [Running with Kafka](#running-with-kafka) below.

## Multi-Architecture Build

Build for both `linux/amd64` and `linux/arm64` simultaneously:

```bash
make buildx
```

**Note**: This creates a multi-platform manifest but doesn't load to local Docker images (multi-arch manifests can't be loaded directly). To push to a registry:

```bash
make push IMAGE=ghcr.io/your-org/ib-schema-registry TAG=latest
```

**Or** export to OCI layout for inspection:

```bash
docker buildx build --platform linux/amd64,linux/arm64 \
  -t temp-image:latest \
  --output type=oci,dest=./image.tar \
  .
```

## Alternative Base Images

**Default (as of 2026-01-16)**: Chainguard JRE distroless runtime for maximum security

### Build with Eclipse Temurin Instead

If you need a traditional JRE with shell access for debugging:

```bash
make build RUNTIME_IMAGE=eclipse-temurin:17-jre
```

**Note**: Chainguard is recommended for production due to:
- 44% smaller base image (427MB vs 769MB)
- Significantly fewer CVEs (typically 0-2 vs 20-50 for Temurin)
- Distroless runtime (no shell, minimal attack surface)
- All smoke tests pass with both runtimes

**Scan images to compare**:

```bash
# Scan default Chainguard-based image
docker scan ib-schema-registry:latest

# Scan Temurin-based image (if built)
docker scan ib-schema-registry:temurin
```

## Running with Kafka

### Docker Compose Example

Create `docker-compose.yml`:

```yaml
version: '3.8'

services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.1
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka:
    image: confluentinc/cp-kafka:7.6.1
    depends_on:
      - zookeeper
    environment:
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

  schema-registry:
    image: ghcr.io/infobloxopen/ib-schema-registry:dev
    depends_on:
      - kafka
    ports:
      - "8081:8081"
    # Default config already points to kafka:9092
```

Start stack:

```bash
docker-compose up -d
```

Test Schema Registry with Kafka:

```bash
# Register a schema
curl -X POST -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema": "{\"type\": \"string\"}"}' \
  http://localhost:8081/subjects/test-value/versions

# List subjects
curl http://localhost:8081/subjects
# Expected: ["test-value"]
```

## Custom Configuration

### Option 1: Volume Mount Configuration File (Recommended)

Mount a custom configuration file to override the built-in defaults:

```bash
# Start from example template
cp config/examples/production.properties my-kafka-config.properties

# Edit with your Kafka cluster details
vim my-kafka-config.properties

# Run with custom config
docker run -p 8081:8081 \
  -v $(pwd)/my-kafka-config.properties:/etc/schema-registry/schema-registry.properties:ro \
  ghcr.io/infobloxopen/ib-schema-registry:dev
```

### Option 2: Docker Compose with Custom Config

```yaml
version: '3.8'

services:
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.1
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181

  kafka:
    image: confluentinc/cp-kafka:7.6.1
    depends_on:
      - zookeeper
    environment:
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1

  schema-registry:
    image: ghcr.io/infobloxopen/ib-schema-registry:dev
    depends_on:
      - kafka
    ports:
      - "8081:8081"
    volumes:
      # Mount custom configuration
      - ./config/examples/development.properties:/etc/schema-registry/schema-registry.properties:ro
      # Mount SSL certs if needed (for production with secure Kafka)
      # - ./certs:/etc/schema-registry/certs:ro
    environment:
      # Pass secrets for SSL/SASL authentication
      # TRUSTSTORE_PASSWORD: ${TRUSTSTORE_PASSWORD}
      # KEYSTORE_PASSWORD: ${KEYSTORE_PASSWORD}
```

Start with custom config:

```bash
docker-compose up -d

# Verify Schema Registry started with custom config
docker-compose logs schema-registry | grep "Adding listener"
```

### Option 3: Environment Variable Overrides

Override individual properties without mounting config file:

```bash
docker run -p 8081:8081 \
  -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=PLAINTEXT://prod-kafka:9092 \
  -e SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY=FORWARD \
  ghcr.io/infobloxopen/ib-schema-registry:dev
```

**Configuration Examples**:

- **Development**: See [config/examples/development.properties](../../config/examples/development.properties) - minimal setup for local testing
- **Production**: See [config/examples/production.properties](../../config/examples/production.properties) - SSL, SASL, monitoring, best practices

## Makefile Targets Reference

```bash
make help          # Show all available targets
make build         # Build for native platform
make buildx        # Build multi-arch (amd64+arm64)
make push          # Build multi-arch and push to registry
make test          # Run smoke test
make clean         # Remove built images
make submodule-init    # Initialize upstream submodule
make submodule-update  # Update submodule to latest
```

## Makefile Variables

Override defaults via command line:

```bash
make build \
  IMAGE=my-registry/schema-registry \
  TAG=7.6.1 \
  BUILDER_IMAGE=maven:3-eclipse-temurin-17 \
  RUNTIME_IMAGE=eclipse-temurin:17-jre \
  APP_UID=10001
```

**Common Variables**:
- `IMAGE`: Full image name (default: `ghcr.io/infobloxopen/ib-schema-registry`)
- `TAG`: Image tag (default: `dev`)
- `PLATFORMS`: Build architectures (default: `linux/amd64,linux/arm64`)
- `BUILDER_IMAGE`: Maven+JDK base (default: `maven:3-eclipse-temurin-17`)
- `RUNTIME_IMAGE`: JRE base (default: `eclipse-temurin:17-jre`)
- `APP_UID`: Runtime user ID (default: `65532`)

## Troubleshooting

### Build fails with "submodule not found"

```bash
# Initialize submodule
git submodule update --init --recursive
```

### Build is slow (>20 minutes)

- First build downloads ~500 MB of Maven dependencies (expected)
- Ensure BuildKit cache mounts are working: check for "using cache" in build output
- Subsequent builds should be <5 minutes with cache

### "Cannot connect to Kafka" errors at startup

- Expected if no Kafka cluster configured
- Schema Registry still serves API endpoints (e.g., `/subjects`)
- For full functionality, provide valid `kafkastore.bootstrap.servers` in config

### Multi-arch build fails with "platform not supported"

```bash
# Ensure buildx is set up
docker buildx create --use --name multiarch --driver docker-container

# Retry build
make buildx
```

### Chainguard image build fails

- Ensure you have access to `cgr.dev` registry (public images, no auth required)
- Some Chainguard images require acceptance of terms on their website
- Try with `latest-dev` tag for builder (includes build tools)

## Next Steps

- **Production deployment**: See [README - Production Configuration](../README.md#production-configuration)
- **CI/CD setup**: See `.github/workflows/build-image.yml` for GitHub Actions example
- **Version updates**: See [README - Updating Upstream](../README.md#updating-upstream-version)
- **Security hardening**: See [README - Digest Pinning](../README.md#base-image-digest-pinning)

## Support

- **Issues**: https://github.com/infobloxopen/ib-schema-registry/issues
- **Upstream docs**: https://docs.confluent.io/platform/current/schema-registry/
- **License compliance**: See [README - Compliance](../README.md#compliance)
