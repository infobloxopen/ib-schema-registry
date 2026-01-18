# Infoblox Schema Registry Helm Chart

Helm chart for deploying Confluent Schema Registry on Kubernetes with multi-architecture support and supply-chain security.

## Features

- ✅ **Production Ready**: High availability, rolling updates, health checks
- ✅ **Multi-Architecture**: Runs on both AMD64 and ARM64 nodes
- ✅ **Security Hardened**: Non-root user, read-only filesystem, minimal privileges
- ✅ **Supply-Chain Security**: Container images include SLSA provenance attestations
- ✅ **Kubernetes Native**: Pod disruption budgets, topology spread constraints
- ✅ **E2E Tested**: Validated with k3d and Redpanda in CI/CD

## Prerequisites

- Kubernetes 1.23+
- Helm 3.8+ (OCI registry support)
- Kafka cluster (Confluent, Apache Kafka, Redpanda, etc.)

## Quick Start

### Install from OCI Registry

```bash
# Install stable release
helm install schema-registry oci://ghcr.io/infobloxopen/ib-schema-registry \
  --version 1.2.3 \
  --set config.kafkaBootstrapServers="kafka:9092"

# Install development build
helm install schema-registry-dev oci://ghcr.io/infobloxopen/ib-schema-registry \
  --version 0.0.0-main.abc1234 \
  --set config.kafkaBootstrapServers="kafka:9092"
```

### Install from Local Chart

```bash
# Clone repository
git clone https://github.com/infobloxopen/ib-schema-registry.git
cd ib-schema-registry

# Install chart
helm install schema-registry ./helm/ib-schema-registry \
  --set config.kafkaBootstrapServers="kafka:9092"
```

### Chart Versioning

**Stable Releases**: Charts are automatically published when git tags are pushed
- Git tag `v1.2.3` → Helm chart version `1.2.3`
- Chart version synchronized with Docker image version
- Example: `helm install ... oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3`

**Development Builds**: Charts published for every commit to main branch
- Commit SHA `abc1234...` → Chart version `0.0.0-main.abc1234` (7-char SHA)
- Pre-release semver format ensures development builds sort before stable releases
- Use for testing unreleased features
- Example: `helm install ... oci://ghcr.io/infobloxopen/ib-schema-registry --version 0.0.0-main.abc1234`

**List Available Versions**:
```bash
# Search for charts (requires adding repo first)
helm repo add ib-schema-registry oci://ghcr.io/infobloxopen
helm search repo ib-schema-registry --versions

# Or pull specific version directly
helm pull oci://ghcr.io/infobloxopen/ib-schema-registry --version 1.2.3
tar -xzf ib-schema-registry-1.2.3.tgz
```

### Verify Installation

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=ib-schema-registry

# Verify Schema Registry is responding
kubectl port-forward svc/ib-schema-registry 8081:8081
curl http://localhost:8081/subjects
# Expected: []
```

## Configuration

### Required Configuration

The only required configuration is the Kafka bootstrap servers:

```bash
helm install schema-registry ./helm/ib-schema-registry \
  --set config.kafkaBootstrapServers="kafka-broker-1:9092,kafka-broker-2:9092"
```

### Common Configurations

#### High Availability Deployment

```bash
helm install schema-registry ./helm/ib-schema-registry \
  --set replicaCount=3 \
  --set config.kafkaBootstrapServers="kafka:9092" \
  --set resources.requests.memory=1Gi \
  --set resources.limits.memory=2Gi
```

#### Custom Image

> **Note**: By default, the chart uses the `appVersion` field from Chart.yaml as the image tag. The `appVersion` is automatically synchronized with the Docker image version during CI/CD builds. Only override `image.tag` if you need to use a different version than the chart's default.

```bash
helm install schema-registry ./helm/ib-schema-registry \
  --set image.repository=ghcr.io/infobloxopen/ib-schema-registry \
  --set image.tag=v1.0.0 \
  --set config.kafkaBootstrapServers="kafka:9092"
```

#### Security Configuration

```bash
helm install schema-registry ./helm/ib-schema-registry \
  --set config.kafkaBootstrapServers="kafka:9092" \
  --set config.kafkastoreSecurityProtocol="SASL_SSL" \
  --set config.kafkastoreSaslMechanism="SCRAM-SHA-512" \
  --set-file config.kafkastoreSslTruststoreLocation=./kafka.truststore.jks
```

### Configuration Values

See [values.yaml](values.yaml) for full configuration options.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of Schema Registry replicas | `1` |
| `image.repository` | Container image repository | `ghcr.io/infobloxopen/ib-schema-registry` |
| `image.tag` | Container image tag | `latest` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `config.kafkaBootstrapServers` | Kafka bootstrap servers (REQUIRED) | `kafka:9092` |
| `config.schemaRegistryGroupId` | Schema Registry group ID | `schema-registry` |
| `config.kafkastoreTopic` | Internal storage topic | `_schemas` |
| `resources.requests.memory` | Memory request | `512Mi` |
| `resources.limits.memory` | Memory limit | `1Gi` |

## Supply-Chain Security

### Container Image Provenance

All container images used by this chart include SLSA provenance attestations that allow you to verify the build origin and integrity.

#### Verify Image Provenance

```bash
# Get image reference from values
IMAGE=$(helm get values schema-registry -o json | jq -r '.image.repository + ":" + .image.tag')

# Install cosign (if not already installed)
go install github.com/sigstore/cosign/v2/cmd/cosign@latest

# Verify image provenance
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  ${IMAGE}

# ✅ Success means: signature valid, built by trusted GitHub Actions workflow
```

#### What is SLSA Provenance?

SLSA (Supply-chain Levels for Software Artifacts) provenance attestations provide cryptographically verifiable metadata about how artifacts were built:

- **Source Repository**: GitHub repository URL and commit SHA
- **Build Workflow**: GitHub Actions workflow that built the image
- **Build Environment**: Builder identity and platform details
- **Build Timestamp**: When the image was built
- **Signature**: Cryptographically signed using GitHub OIDC

#### Pre-Deployment Verification Script

Use this script to verify image provenance before deploying:

```bash
#!/bin/bash
# verify-before-deploy.sh

CHART_PATH="./helm/ib-schema-registry"
IMAGE_REPO=$(yq '.image.repository' ${CHART_PATH}/values.yaml)
IMAGE_TAG=$(yq '.image.tag' ${CHART_PATH}/values.yaml)
IMAGE="${IMAGE_REPO}:${IMAGE_TAG}"

echo "Verifying image: ${IMAGE}"

# Verify provenance
if cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  "${IMAGE}" > /dev/null 2>&1; then
  echo "✅ Image provenance verified - safe to deploy"
  exit 0
else
  echo "❌ Image provenance verification failed"
  echo "Do not deploy untrusted images"
  exit 1
fi
```

### Helm Chart Provenance (Future)

> **Note**: Helm chart provenance is planned for a future release when OCI registry publishing is enabled.

When enabled, you'll be able to verify the Helm chart itself:

```bash
# Future: Verify Helm chart provenance
cosign verify-attestation \
  --type slsaprovenance \
  --certificate-identity-regexp '^https://github.com/infobloxopen/ib-schema-registry/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  oci://ghcr.io/infobloxopen/ib-schema-registry:1.0.0
```

See [docs/helm-provenance-verification.md](../../docs/helm-provenance-verification.md) for detailed documentation.

## Upgrading

### Helm Upgrade

```bash
# Upgrade to new chart version
helm upgrade schema-registry ./helm/ib-schema-registry

# Upgrade with new image version
helm upgrade schema-registry ./helm/ib-schema-registry \
  --set image.tag=v1.1.0
```

### Rolling Updates

The chart uses Kubernetes Deployments with rolling update strategy:

- **Strategy**: RollingUpdate
- **Max Unavailable**: 0 (zero-downtime updates)
- **Max Surge**: 1 (one extra pod during rollout)

```bash
# Watch rolling update progress
kubectl rollout status deployment/ib-schema-registry

# Rollback if needed
helm rollback schema-registry
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod status
kubectl get pods -l app.kubernetes.io/name=ib-schema-registry

# View pod logs
kubectl logs -l app.kubernetes.io/name=ib-schema-registry --tail=100

# Describe pod for events
kubectl describe pod -l app.kubernetes.io/name=ib-schema-registry
```

### Connection to Kafka Failed

```bash
# Check Kafka connectivity from pod
kubectl exec -it deploy/ib-schema-registry -- sh -c 'nc -zv kafka 9092'

# Verify Kafka bootstrap servers configuration
helm get values schema-registry | grep kafkaBootstrapServers
```

### Health Check Failing

```bash
# Test readiness probe manually
kubectl exec -it deploy/ib-schema-registry -- wget -q -O- http://localhost:8081/subjects

# Check if Schema Registry is listening
kubectl exec -it deploy/ib-schema-registry -- netstat -ln | grep 8081
```

## Uninstall

```bash
# Uninstall chart
helm uninstall schema-registry

# Clean up persistent data (if any)
kubectl delete pvc -l app.kubernetes.io/name=ib-schema-registry
```

## Development

### Linting

```bash
# Lint chart
helm lint ./helm/ib-schema-registry

# Validate templates
helm template schema-registry ./helm/ib-schema-registry --validate
```

### Testing

```bash
# Run E2E tests
bash tests/e2e/test-helm-chart.sh

# Manual testing with k3d
k3d cluster create test
helm install schema-registry ./helm/ib-schema-registry \
  --set config.kafkaBootstrapServers="redpanda:9092"
```

## Additional Resources

- **Main Repository**: https://github.com/infobloxopen/ib-schema-registry
- **Provenance Verification**: [docs/provenance-verification.md](../../docs/provenance-verification.md)
- **Helm Chart Provenance**: [docs/helm-provenance-verification.md](../../docs/helm-provenance-verification.md)
- **Confluent Docs**: https://docs.confluent.io/platform/current/schema-registry/

## License

- **Helm Chart**: MIT License
- **Container Image Build Tooling**: MIT License
- **Confluent Schema Registry**: Confluent Community License

See [LICENSE.md](../../LICENSE.md) for full details.
