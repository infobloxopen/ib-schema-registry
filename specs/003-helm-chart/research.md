# Research: Helm Chart Best Practices & Implementation Patterns

**Feature**: 003-helm-chart | **Phase**: 0 (Research) | **Date**: 2026-01-16

## Research Tasks

This document resolves all technical unknowns from the Technical Context and specification requirements.

---

## 1. Helm Chart Best Practices for Stateless Applications

**Research Question**: What are the recommended patterns for deploying stateless applications like Schema Registry with Helm?

### Decision: Use Deployment (not StatefulSet)

**Rationale**: 
- Schema Registry stores all state in Kafka topics (`_schemas`, `_schemas_encoders`)
- No persistent volumes required
- Pods are fungible and can be replaced without data loss
- Deployment provides rolling updates and replica management

**Alternatives Considered**:
- **StatefulSet**: Provides stable network identities and ordered deployment, but Schema Registry doesn't require stable pod names or ordered startup
- **DaemonSet**: Runs one pod per node, inappropriate for Schema Registry which needs flexible replica count

### Best Practices Applied

1. **ConfigMap for Configuration**: Store `schema-registry.properties` in ConfigMap, mount as file
2. **ConfigMap Checksum Annotation**: Add checksum of ConfigMap to pod template to trigger rolling updates
   ```yaml
   annotations:
     checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
   ```
3. **Resource Requests/Limits**: Define sensible defaults (512Mi/500m requests, 2Gi/2000m limits)
4. **Readiness/Liveness Probes**: Use HTTP probes on `/` or `/subjects` endpoints
5. **PodDisruptionBudget**: Ensure `minAvailable` during voluntary disruptions (node drains, upgrades)

**References**:
- Helm Best Practices: https://helm.sh/docs/chart_best_practices/
- Kubernetes Workload Best Practices: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/

---

## 2. ConfigMap Checksum Pattern for Rolling Updates

**Research Question**: How to automatically trigger pod restarts when configuration changes?

### Decision: Use Template Checksum Annotation

**Implementation**:
```yaml
# templates/deployment.yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

**How It Works**:
1. Helm renders ConfigMap template and computes SHA256 hash
2. Hash stored as pod annotation
3. When ConfigMap content changes, hash changes
4. Kubernetes sees pod template change and triggers rolling update
5. Old pods replaced with new pods that mount updated ConfigMap

**Alternatives Considered**:
- **Manual pod deletion**: Requires operator intervention, error-prone
- **Reloader operator**: Third-party tool, adds dependency
- **Helm hooks**: Can trigger jobs but not rolling updates of existing Deployment

**Edge Case**: If only non-ConfigMap values change (e.g., replica count), checksum remains same and pods don't restart unnecessarily.

**References**:
- Helm FAQ: https://helm.sh/docs/howto/charts_tips_and_tricks/#automatically-roll-deployments

---

## 3. PodDisruptionBudget Sizing for High Availability

**Research Question**: How to calculate minAvailable for PodDisruptionBudget when `replicaCount > 1`?

### Decision: `minAvailable = ceiling(replicaCount / 2)`

**Rationale**:
- Ensures majority of replicas remain available during disruptions
- For 3 replicas: minAvailable=2 (allows 1 eviction at a time)
- For 2 replicas: minAvailable=1 (allows 1 eviction at a time)
- For 5 replicas: minAvailable=3 (allows 2 concurrent evictions)

**Formula in Helm Template**:
```yaml
{{- if gt .Values.replicaCount 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "schema-registry.fullname" . }}
spec:
  minAvailable: {{ div .Values.replicaCount 2 | add1 }}
  selector:
    matchLabels:
      {{- include "schema-registry.selectorLabels" . | nindent 6 }}
{{- end }}
```

**Alternatives Considered**:
- **maxUnavailable=1**: Simpler but less flexible for large replica counts
- **minAvailable=1**: Too permissive, allows most pods to be evicted simultaneously
- **50% maxUnavailable**: Equivalent to ceiling(replicaCount/2) but less explicit

**Edge Case**: When `replicaCount=1`, PodDisruptionBudget is NOT created (no HA guarantee possible).

**References**:
- Kubernetes PodDisruptionBudget: https://kubernetes.io/docs/concepts/workloads/pods/disruptions/

---

## 4. TopologySpreadConstraints for Zone Distribution

**Research Question**: How to distribute pods across availability zones without failing when zones are unavailable?

### Decision: Use `whenUnsatisfiable: ScheduleAnyway` with zone topology

**Implementation**:
```yaml
{{- if gt .Values.replicaCount 1 }}
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        {{- include "schema-registry.selectorLabels" . | nindent 8 }}
{{- end }}
```

**How It Works**:
- `maxSkew: 1`: Tries to keep pod count per zone within 1 of each other
- `whenUnsatisfiable: ScheduleAnyway`: Allows scheduling even if constraint can't be met (graceful degradation)
- `topologyKey: topology.kubernetes.io/zone`: Distributes across zones (standard label in cloud providers)

**Alternatives Considered**:
- **whenUnsatisfiable: DoNotSchedule**: Hard constraint, deployment fails if not enough zones
- **Affinity rules**: More verbose, less expressive for spreading
- **No topology constraints**: Pods may all land in same zone

**Edge Cases**:
- Single-zone cluster: Constraint satisfied trivially
- Zones with insufficient capacity: ScheduleAnyway allows pods to concentrate in available zones
- `replicaCount=1`: Constraint not applied (no spreading needed)

**References**:
- Kubernetes Pod Topology Spread: https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/

---

## 5. JVM Container Memory Detection

**Research Question**: How to configure JVM to automatically detect container memory limits?

### Decision: Use `-XX:+UseContainerSupport` and `-XX:MaxRAMPercentage`

**Implementation in Deployment**:
```yaml
env:
  - name: SCHEMA_REGISTRY_OPTS
    value: "-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0"
  - name: SCHEMA_REGISTRY_HEAP_OPTS
    value: ""  # Let container support auto-configure heap
```

**How It Works**:
- `-XX:+UseContainerSupport`: JVM reads memory limits from cgroup (Kubernetes resource.limits.memory)
- `-XX:MaxRAMPercentage=70.0`: Sets max heap to 70% of container memory (leaves 30% for non-heap, OS)
- If container has 2Gi limit, JVM heap ~1.4Gi automatically

**Alternatives Considered**:
- **Manual heap sizing** (`-Xmx` flags): Requires operator to calculate, prone to OOMKilled if misconfigured
- **MaxRAMPercentage=100%**: Doesn't leave room for metaspace, thread stacks, native memory
- **InitialRAMPercentage**: Only affects initial heap, MaxRAMPercentage is sufficient

**Edge Case**: If no memory limit set, JVM uses physical host memory (dangerous in Kubernetes).

**Best Practice**: Always set `resources.limits.memory` in values.yaml defaults.

**References**:
- JVM Container Support: https://developers.redhat.com/articles/2022/04/19/java-17-whats-new-openjdks-container-awareness

---

## 6. values.yaml Documentation Strategy

**Research Question**: How to provide comprehensive inline documentation in values.yaml?

### Decision: Multi-line YAML comments above each parameter

**Pattern**:
```yaml
# -- Number of Schema Registry replicas to deploy.
# For high availability, set to 3 or more and distribute across zones.
# @default -- 1
replicaCount: 1

# -- Container image configuration
image:
  # -- Container image repository
  # @default -- ghcr.io/infobloxopen/ib-schema-registry
  repository: ghcr.io/infobloxopen/ib-schema-registry
  
  # -- Image pull policy (Always, IfNotPresent, Never)
  # @default -- IfNotPresent
  pullPolicy: IfNotPresent
  
  # -- Image tag (overrides Chart.appVersion if set)
  # @default -- Chart.appVersion
  tag: ""
```

**Documentation Conventions**:
- `# --`: Marks parameter documentation (parseable by helm-docs tool)
- `@default --`: Documents actual default value (useful when default is computed)
- Nested structure with 2-space indentation
- Include examples for complex configurations
- Warn about security implications (e.g., imagePullSecrets)

**Tools**:
- **helm-docs**: Auto-generates README from comments (optional, not required for chart)
- **helm lint**: Validates syntax
- **helm template --debug**: Shows rendered output for testing

**References**:
- Helm Values Files: https://helm.sh/docs/chart_template_guide/values_files/
- helm-docs tool: https://github.com/norwoodj/helm-docs

---

## 7. E2E Testing with k3d and Redpanda

**Research Question**: How to create reproducible e2e tests without requiring full Kafka cluster?

### Decision: Use k3d for Kubernetes + Redpanda for Kafka API

**Architecture**:
```
┌─────────────────────────────────────┐
│ k3d cluster (local Docker)          │
│  ┌─────────────┐   ┌──────────────┐│
│  │  Redpanda   │   │ Schema       ││
│  │  (Kafka API)│◄──│ Registry     ││
│  │             │   │ (Helm chart) ││
│  └─────────────┘   └──────────────┘│
└─────────────────────────────────────┘
         ▲
         │ kubectl/curl API tests
    Test Script (Bash)
```

**k3d Benefits**:
- Lightweight: Runs Kubernetes in Docker (no VM overhead)
- Fast: Cluster creation <30 seconds
- Multi-arch: Works on macOS ARM and Linux x86
- Disposable: `k3d cluster delete` removes all resources

**Redpanda Benefits**:
- Kafka-compatible API (Schema Registry can't tell the difference)
- Single binary (no Zookeeper dependency)
- Faster startup than Kafka (~10s vs ~60s)
- Lower resource usage (suitable for CI)

**E2E Test Flow**:
1. Create k3d cluster: `k3d cluster create test-cluster`
2. Deploy Redpanda: `kubectl apply -f redpanda.yaml`
3. Wait for Redpanda ready: `kubectl wait --for=condition=ready pod -l app=redpanda`
4. Install Schema Registry chart: `helm install sr ./chart --set kafkaBootstrapServers=redpanda:9092`
5. Wait for Schema Registry ready: `kubectl wait --for=condition=ready pod -l app=schema-registry`
6. Test API operations:
   - Register schema: `POST /subjects/test-subject/versions`
   - Retrieve schema: `GET /subjects/test-subject/versions/1`
   - List subjects: `GET /subjects`
7. Verify rolling update: Change ConfigMap, verify pods restart
8. Cleanup: `k3d cluster delete test-cluster`

**Test Validation**:
- Exit code 0 if all steps pass
- Exit code 1 on first failure
- Verbose logging for debugging

**Alternatives Considered**:
- **Minikube**: Heavier, slower startup, requires VM on some platforms
- **kind**: Similar to k3d but less ergonomic CLI
- **Real Kafka**: Heavyweight, slow startup, overkill for basic API testing
- **Mocked Kafka**: Doesn't validate real integration

**References**:
- k3d Documentation: https://k3d.io/
- Redpanda Quick Start: https://docs.redpanda.com/docs/get-started/quick-start/

---

## 8. Helm Chart OCI Packaging

**Research Question**: How to package and distribute Helm chart as OCI artifact?

### Decision: Use `helm package` + `helm push` to OCI registry

**Workflow**:
```bash
# 1. Package chart as .tgz
helm package chart/

# 2. Login to OCI registry
echo $REGISTRY_TOKEN | helm registry login ghcr.io -u $REGISTRY_USER --password-stdin

# 3. Push to OCI registry
helm push schema-registry-1.0.0.tgz oci://ghcr.io/infobloxopen

# 4. Install from OCI registry
helm install my-sr oci://ghcr.io/infobloxopen/schema-registry --version 1.0.0
```

**OCI Registry Support**:
- GitHub Container Registry (ghcr.io): ✅ Supported
- Docker Hub: ✅ Supported
- Google Artifact Registry: ✅ Supported
- AWS ECR: ✅ Supported (requires `helm registry login` with AWS credentials)

**Chart Metadata**:
```yaml
# Chart.yaml
apiVersion: v2
name: schema-registry
version: 1.0.0  # Chart version
appVersion: "8.1.1"  # Schema Registry version (matches container image tag)
description: Confluent Schema Registry Helm chart for Kubernetes
type: application
home: https://github.com/infobloxopen/ib-schema-registry
sources:
  - https://github.com/confluentinc/schema-registry
maintainers:
  - name: Infoblox
    url: https://github.com/infobloxopen
```

**Versioning Strategy**:
- Chart version: Semantic versioning (1.0.0, 1.1.0, 2.0.0) for chart changes
- appVersion: Matches upstream Schema Registry version (8.1.1, 8.2.0)
- Example: Chart 1.2.0 might deploy Schema Registry 8.1.1

**Alternatives Considered**:
- **Traditional Helm repository** (HTTP): More setup, requires hosting
- **Git-based**: Cloning required, less discoverable
- **Tarball distribution**: Manual download, no registry integration

**Requirements**:
- Helm 3.8+ (OCI support became stable in 3.8.0)
- Registry with OCI support (GitHub Container Registry recommended)

**References**:
- Helm OCI Support: https://helm.sh/docs/topics/registries/
- GHCR OCI Support: https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry

---

## Summary: All Research Complete

### Decisions Made

1. ✅ **Deployment Pattern**: Deployment (not StatefulSet) for stateless Schema Registry
2. ✅ **Rolling Updates**: ConfigMap checksum annotation triggers automatic pod restarts
3. ✅ **High Availability**: PodDisruptionBudget with `minAvailable = ceiling(replicaCount/2)`
4. ✅ **Zone Distribution**: TopologySpreadConstraints with `ScheduleAnyway` for graceful degradation
5. ✅ **JVM Configuration**: `-XX:+UseContainerSupport -XX:MaxRAMPercentage=70.0` for automatic heap sizing
6. ✅ **Documentation**: Inline YAML comments with `# --` convention in values.yaml
7. ✅ **E2E Testing**: k3d (lightweight Kubernetes) + Redpanda (Kafka-compatible) for CI-friendly tests
8. ✅ **OCI Packaging**: `helm package` + `helm push` to GitHub Container Registry

### No Outstanding Clarifications

All technical unknowns from the specification have been resolved with concrete decisions and implementation patterns.

**Ready for Phase 1**: Design data models and contracts based on these research findings.
