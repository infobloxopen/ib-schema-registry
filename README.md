# Infoblox Schema Registry - Multi-Architecture Container Image

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE.md)

> **Portable, multi-architecture OCI container image for Confluent Schema Registry**  
> Built from [upstream source](https://github.com/confluentinc/schema-registry) without Spotify's dockerfile-maven-plugin

## Features

✅ **Multi-Architecture**: Native support for `linux/amd64` and `linux/arm64`  
✅ **Secure by Default**: Chainguard distroless JRE runtime (~60% smaller, minimal CVEs)  
✅ **Pluggable Base Images**: Swap between Chainguard (default), Eclipse Temurin, or other JRE bases  
✅ **Supply-Chain Security**: Non-root user (UID 65532), OCI labels, reproducible builds  
✅ **Developer Friendly**: Simple `make build` on macOS Apple Silicon or Linux x86  
✅ **CI/CD Ready**: GitHub Actions workflow with multi-arch buildx

## Quick Start

### Prerequisites

- **Docker**: Version 20.10+ with BuildKit enabled (default in Docker 23.0+)
- **Docker Buildx**: For multi-architecture builds (`docker buildx version`)
- **Git**: For submodule management
- **Make**: Build automation (pre-installed on macOS/Linux)

### Build Image

```bash
# Clone repository with upstream submodule
git clone --recurse-submodules https://github.com/infobloxopen/ib-schema-registry.git
cd ib-schema-registry

# Build for your native platform (Apple Silicon → ARM64, Linux x86 → AMD64)
make build

# Build for all platforms (AMD64 + ARM64)
make buildx

# Run smoke tests
make test
```

### Run Container

```bash
# Start Schema Registry (requires Kafka cluster)
docker run -d \
  --name schema-registry \
  -p 8081:8081 \
  -e KAFKA_BOOTSTRAP_SERVERS=kafka:9092 \
  ib-schema-registry:latest

# Health check
curl http://localhost:8081/subjects
# Expected: []
```

## Kubernetes Deployment (Helm Chart)

### Quick Deploy to Kubernetes

```bash
# Install from OCI registry
helm install schema-registry oci://ghcr.io/infobloxopen/ib-schema-registry \
  --set config.kafkaBootstrapServers="kafka:9092"

# Or install from local chart
helm install schema-registry ./helm/ib-schema-registry \
  --set config.kafkaBootstrapServers="kafka:9092"
```

### Production HA Deployment

```bash
# Deploy with 3 replicas, PodDisruptionBudget, and topology spread
helm install schema-registry oci://ghcr.io/infobloxopen/ib-schema-registry \
  --set config.kafkaBootstrapServers="kafka-0:9092,kafka-1:9092,kafka-2:9092" \
  --set replicaCount=3 \
  --set resources.requests.memory=1Gi \
  --set resources.limits.memory=2Gi
```

### Helm Chart Features

- ✅ **High Availability**: Multi-replica with PodDisruptionBudget and zone distribution
- ✅ **Rolling Updates**: Automatic pod restarts on configuration changes
- ✅ **Security**: Non-root, read-only filesystem, minimal privileges
- ✅ **E2E Tested**: Validated with k3d and Redpanda in CI/CD

See [helm/ib-schema-registry/README.md](helm/ib-schema-registry/README.md) for full Helm chart documentation.

### Docker Compose Example

```yaml
version: '3.8'

services:
  schema-registry:
    image: ib-schema-registry:latest
    ports:
      - "8081:8081"
    volumes:
      # Optional: Mount custom configuration
      - ./custom-config.properties:/etc/schema-registry/schema-registry.properties:ro
    depends_on:
      - kafka
    restart: unless-stopped

  # Kafka cluster services (zookeeper, kafka) not shown
```

## Configuration

### Default Configuration

The image includes sensible defaults for local development:

```properties
listeners=http://0.0.0.0:8081
kafkastore.bootstrap.servers=PLAINTEXT://kafka:9092
schema.registry.group.id=schema-registry
kafkastore.topic=_schemas
kafkastore.topic.replication.factor=1
schema.compatibility.level=BACKWARD
```

### Custom Configuration

For production deployments, you'll want to customize the Schema Registry configuration to match your Kafka cluster and security requirements.

**Example Configuration Templates**:

The repository provides example configurations in `config/examples/`:
- **[production.properties](config/examples/production.properties)**: Production-ready template with SSL, SASL, monitoring, and best practices
- **[development.properties](config/examples/development.properties)**: Minimal local development setup with permissive settings

**Option 1: Mount Configuration File (Recommended)**

The cleanest approach is to mount your custom configuration file into the container:

```bash
# Use production example as template
cp config/examples/production.properties my-config.properties
# Edit my-config.properties with your Kafka bootstrap servers, SSL certs, etc.

docker run -d \
  -v $(pwd)/my-config.properties:/etc/schema-registry/schema-registry.properties:ro \
  -p 8081:8081 \
  ib-schema-registry:latest
```

**Docker Compose with Custom Config**:

```yaml
version: '3.8'

services:
  schema-registry:
    image: ib-schema-registry:latest
    ports:
      - "8081:8081"
    volumes:
      - ./config/production.properties:/etc/schema-registry/schema-registry.properties:ro
      # Mount SSL certificates if using secure Kafka
      - ./certs/kafka.truststore.jks:/etc/schema-registry/kafka.truststore.jks:ro
      - ./certs/kafka.keystore.jks:/etc/schema-registry/kafka.keystore.jks:ro
    environment:
      # Pass secrets as environment variables (reference them in properties file)
      - TRUSTSTORE_PASSWORD=${TRUSTSTORE_PASSWORD}
      - KEYSTORE_PASSWORD=${KEYSTORE_PASSWORD}
      - KEY_PASSWORD=${KEY_PASSWORD}
    depends_on:
      - kafka
    restart: unless-stopped
```

**Option 2: Environment Variables**

Schema Registry supports environment variable overrides using `SCHEMA_REGISTRY_` prefix. Convert property names:
- Replace `.` with `_`
- Convert to uppercase
- Add `SCHEMA_REGISTRY_` prefix

Examples:
```bash
# listeners=http://0.0.0.0:8081
# becomes:
-e SCHEMA_REGISTRY_LISTENERS=http://0.0.0.0:8081

# kafkastore.bootstrap.servers=PLAINTEXT://kafka:9092
# becomes:
-e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=PLAINTEXT://kafka:9092

# schema.compatibility=BACKWARD
# becomes:
-e SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY=BACKWARD
```

**Full example with environment variables**:

```bash
docker run -d \
  -v /path/to/production.properties:/etc/schema-registry/schema-registry.properties:ro \
  -p 8081:8081 \
**Full example with environment variables**:

```bash
docker run -d \
  -e SCHEMA_REGISTRY_LISTENERS=http://0.0.0.0:8081 \
  -e SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS=PLAINTEXT://prod-kafka-1:9092,PLAINTEXT://prod-kafka-2:9092 \
  -e SCHEMA_REGISTRY_SCHEMA_REGISTRY_GROUP_ID=schema-registry-prod \
  -e SCHEMA_REGISTRY_SCHEMA_COMPATIBILITY=BACKWARD \
  -p 8081:8081 \
  ib-schema-registry:latest
```

**Configuration Precedence**:
1. Environment variables (`SCHEMA_REGISTRY_*`) - highest priority
2. Mounted configuration file (`/etc/schema-registry/schema-registry.properties`)
3. Built-in defaults - lowest priority

**Important Configuration Properties**:

| Property | Description | Example |
|----------|-------------|---------|
| `kafkastore.bootstrap.servers` | Kafka cluster connection (REQUIRED) | `PLAINTEXT://kafka:9092` |
| `listeners` | Schema Registry HTTP endpoint | `http://0.0.0.0:8081` |
| `schema.registry.group.id` | Unique cluster identifier | `schema-registry-prod` |
| `kafkastore.topic` | Internal storage topic | `_schemas` (default) |
| `schema.compatibility` | Default compatibility mode | `BACKWARD`, `FORWARD`, `FULL` |
| `kafkastore.security.protocol` | Kafka encryption/auth | `PLAINTEXT`, `SSL`, `SASL_SSL` |

See [Confluent documentation](https://docs.confluent.io/platform/current/schema-registry/installation/config.html) for full configuration reference.

## Advanced Usage

### Alternative Base Images

**Default**: Chainguard JRE (distroless, minimal CVEs)

To use Eclipse Temurin instead:

```bash
# Build with Temurin JRE (larger image, more tooling)
make build RUNTIME_IMAGE=eclipse-temurin:17-jre

# Note: Chainguard is ~60% smaller with significantly fewer CVEs
```

### Pin Base Images by Digest

For production, pin base images by digest for reproducibility:

```bash
make build \
  BUILDER_IMAGE=maven@sha256:abc123... \
  RUNTIME_IMAGE=cgr.dev/chainguard/jre@sha256:def456...
```

### Custom Image Tags

```bash
# Build with custom name and version
make build IMAGE=ghcr.io/infobloxopen/schema-registry TAG=v8.1.1

# Push to registry
make push IMAGE=ghcr.io/infobloxopen/schema-registry TAG=v8.1.1
```

### Update Upstream Version

```bash
# Update to latest Schema Registry release
make submodule-update

# Or manually
cd upstream/schema-registry
git fetch --tags
git checkout v7.7.0
cd ../..

# Rebuild image
make build
```

## Makefile Targets

| Target | Description |
|--------|-------------|
| `help` | Display available targets (default) |
| `submodule-init` | Initialize upstream Schema Registry submodule |
| `submodule-update` | Update upstream to latest version |
| `build` | Build image for native platform |
| `buildx` | Build multi-arch image (AMD64 + ARM64) |
| `push` | Push multi-arch image to registry |
| `test` | Run smoke tests |
| `clean` | Remove local images |
| `info` | Display build configuration |

## CI/CD Integration

### GitHub Actions

The repository includes a multi-arch CI workflow:

```yaml
# .github/workflows/build-image.yml
# Triggers: Push to main, pull requests
# Platforms: linux/amd64, linux/arm64
# Registry: GitHub Container Registry (ghcr.io)
```

**On PR**: Build and validate (no registry push)  
**On main**: Build, tag with commit SHA + `latest`, and push to GHCR  
**On tag**: Build, tag with version number, and push to GHCR

### Build Times

| Scenario | Expected Time |
|----------|---------------|
| Cold build (no cache) | ~15 minutes |
| Warm build (Maven cache hit) | ~5 minutes |
| Multi-arch buildx | ~15 minutes (parallel) |

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Multi-Stage Dockerfile                              │
├─────────────────────────────────────────────────────┤
│  Builder Stage (BUILDPLATFORM)                       │
│  ├─ Base: Maven 3 + Eclipse Temurin 17 JDK          │
│  ├─ Copy: upstream/schema-registry (submodule)      │
│  ├─ Build: mvn -DskipTests package -P standalone    │
│  └─ Output: kafka-schema-registry-*-standalone.jar  │
├─────────────────────────────────────────────────────┤
│  Runtime Stage (TARGETPLATFORM)                      │
│  ├─ Base: Chainguard JRE (distroless, minimal CVEs) │
│  ├─ User: 65532 (nobody, non-root)                  │
│  ├─ Copy: Standalone JAR + config                   │
│  ├─ Expose: Port 8081                               │
│  └─ Entrypoint: java -jar (JSON exec-form)          │
└─────────────────────────────────────────────────────┘
```

## Troubleshooting

### Build Errors

**Error: `submodule not initialized`**
```bash
make submodule-init
```

**Error: `BUILDPLATFORM is blank`**
```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1
```

**Error: `Maven build failed`**
```bash
# Check submodule is on valid tag
cd upstream/schema-registry
git describe --tags
cd ../..

# Clean and retry
make clean && make build
```

### Runtime Errors

**Container exits immediately**
```bash
# Check logs
docker logs <container-name>

# Verify Kafka is reachable
docker exec <container-name> ping kafka
```

**Health check fails**
```bash
# Verify port mapping
docker ps | grep schema-registry

# Test locally
curl http://localhost:8081/subjects
```

### Platform Issues

**ARM vs x86 dependency resolution**
- Builder stage runs on `BUILDPLATFORM` (native architecture) for speed
- Maven resolves dependencies for native platform, avoiding cross-compilation
- Runtime stage uses `TARGETPLATFORM` (target architecture)

## Compliance & Licensing

### ⚠️ Confluent Community License

This repository contains **build tooling only** (MIT licensed). The actual Confluent Schema Registry source code is subject to the [Confluent Community License](https://github.com/confluentinc/schema-registry/blob/master/LICENSE).

**Key Restrictions**:
- ❌ Providing Schema Registry as a **hosted/managed service** to third parties is **prohibited**
- ✅ Using Schema Registry for internal infrastructure is **allowed**
- ✅ Modifying build tooling in this repository is **allowed**

**Full License Text**: See [LICENSE.md](LICENSE.md) for details and compliance guidance.

**Disclaimer**: This is not legal advice. Consult your legal counsel for commercial use.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development workflow, testing guidelines, and PR process.

## Support

- **Issues**: [GitHub Issues](https://github.com/infobloxopen/ib-schema-registry/issues)
- **Upstream Docs**: [Confluent Schema Registry Docs](https://docs.confluent.io/platform/current/schema-registry/index.html)
- **Specification**: [specs/001-schema-registry-image/](specs/001-schema-registry-image/)

## Roadmap

- [ ] Helm chart for Kubernetes deployments
- [ ] SBOM generation (Software Bill of Materials)
- [ ] Provenance attestation (SLSA framework)
- [ ] Image signing with cosign
- [ ] Performance benchmarking suite

## License

- **Build Tooling** (this repository): MIT License
- **Confluent Schema Registry** (upstream): Confluent Community License

See [LICENSE.md](LICENSE.md) for full details.

---

**Built with ❤️ by Infoblox | [Constitution](./specify/memory/constitution.md) | [Specification](specs/001-schema-registry-image/spec.md)**
