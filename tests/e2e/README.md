# End-to-End Testing for Helm Chart

This directory contains end-to-end tests for the Infoblox Schema Registry Helm chart.

## Test Architecture

The E2E test suite validates the full deployment lifecycle:

1. **Cluster Setup**: Creates k3d cluster (lightweight Kubernetes)
2. **Backend Deployment**: Deploys Redpanda (Kafka-compatible backend)
3. **Chart Installation**: Installs Schema Registry Helm chart
4. **API Validation**: Tests REST API endpoints (register, retrieve, list schemas)
5. **Cleanup**: Tears down cluster and resources

## Prerequisites

- **k3d** 5.x or later (`brew install k3d` on macOS)
- **helm** 3.8+ (`brew install helm`)
- **kubectl** 1.24+ (`brew install kubectl`)
- **curl** and **jq** for API testing

## Test Scripts

| Script | Purpose |
|--------|---------|
| `test-helm-chart.sh` | Main orchestrator - runs full E2E test suite |
| `setup-k3d-cluster.sh` | Creates k3d cluster with 2 agent nodes |
| `deploy-redpanda.sh` | Deploys Redpanda as Kafka backend |
| `validate-schema-registry.sh` | Tests Schema Registry API (register/retrieve schemas) |
| `teardown.sh` | Cleanup cluster and resources |

## Usage

### Run Full E2E Tests

```bash
# From repository root
make helm-test-e2e

# Or directly
bash tests/e2e/test-helm-chart.sh
```

### Run Individual Test Steps

```bash
# Setup cluster
bash tests/e2e/setup-k3d-cluster.sh

# Deploy Redpanda
bash tests/e2e/deploy-redpanda.sh

# Install Schema Registry
helm install schema-registry chart/ --set config.kafkaBootstrapServers=redpanda.default.svc.cluster.local:9092

# Validate API
bash tests/e2e/validate-schema-registry.sh

# Cleanup
bash tests/e2e/teardown.sh
```

## Test Coverage

- ✅ Basic deployment (single replica)
- ✅ HA deployment (multi-replica with PDB and topology spread)
- ✅ Configuration via values.yaml
- ✅ Rolling updates triggered by ConfigMap changes
- ✅ API connectivity (register, retrieve, list schemas)
- ✅ Health probes (liveness and readiness)
- ✅ Security context (non-root, no privilege escalation)

## CI Integration

Tests run automatically in GitHub Actions on:
- Pull requests to main branch
- Commits to feature branches
- Release tags

See `.github/workflows/helm-test.yaml` for CI configuration.

## Troubleshooting

### Cluster Creation Fails

```bash
# Check k3d version
k3d version

# Cleanup existing clusters
k3d cluster delete schema-registry-test

# Check Docker is running
docker ps
```

### Helm Install Fails

```bash
# Check chart syntax
helm lint chart/

# Debug template rendering
helm template schema-registry chart/ --debug

# Check pod status
kubectl get pods -n default
kubectl describe pod <pod-name>
kubectl logs <pod-name>
```

### API Validation Fails

```bash
# Check service endpoints
kubectl get svc

# Port-forward to Schema Registry
kubectl port-forward svc/schema-registry 8081:8081

# Test API manually
curl http://localhost:8081/subjects
```

## Architecture

```text
┌─────────────────────────────────────────────────────────┐
│ k3d Cluster (schema-registry-test)                      │
│ ┌─────────────────────────────────────────────────────┐ │
│ │ Namespace: default                                  │ │
│ │ ┌─────────────────┐   ┌─────────────────────────┐  │ │
│ │ │ Redpanda        │   │ Schema Registry         │  │ │
│ │ │ (Kafka backend) │◄──┤ (chart under test)      │  │ │
│ │ │                 │   │                         │  │ │
│ │ │ Port: 9092      │   │ Port: 8081              │  │ │
│ │ └─────────────────┘   └─────────────────────────┘  │ │
│ │                              ▲                      │ │
│ │                              │                      │ │
│ │                              │ API Tests            │ │
│ │                       ┌──────┴──────┐               │ │
│ │                       │ validate-   │               │ │
│ │                       │ schema-     │               │ │
│ │                       │ registry.sh │               │ │
│ │                       └─────────────┘               │ │
│ └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

## Development Notes

- Tests are idempotent and can be run multiple times
- k3d cluster name: `schema-registry-test` (hardcoded in scripts)
- Redpanda replaces full Kafka stack for lightweight testing
- Tests validate constitution compliance (non-root, security context)
