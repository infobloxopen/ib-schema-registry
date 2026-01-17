# Data Model: Kubernetes Resources & Configuration Schema

**Feature**: 003-helm-chart | **Phase**: 1 (Design) | **Date**: 2026-01-16

## Overview

This document defines the Kubernetes resources created by the Helm chart and the structure of the values.yaml configuration schema.

---

## 1. Kubernetes Resources (Entities)

### 1.1 Deployment

**Purpose**: Manages Schema Registry pod replicas with rolling update strategy

**Key Fields**:
- `spec.replicas`: Number of pods (from values.replicaCount)
- `spec.template.spec.containers[0].image`: Container image reference
- `spec.template.spec.containers[0].env`: Environment variables for Schema Registry configuration
- `spec.template.spec.containers[0].resources`: CPU/memory requests and limits
- `spec.template.spec.containers[0].livenessProbe`: HTTP probe on `/` endpoint
- `spec.template.spec.containers[0].readinessProbe`: HTTP probe on `/subjects` endpoint
- `spec.template.spec.securityContext`: Non-root user, read-only root filesystem
- `spec.template.metadata.annotations.checksum/config`: ConfigMap SHA256 for rolling updates

**Relationships**:
- References: ConfigMap (volume mount), ServiceAccount, Service (via labels)
- Managed by: Kubernetes Deployment controller

**Validation Rules**:
- replicas >= 1 (or 0 for maintenance mode if documented)
- image.repository and image.tag must be set
- resources.limits.memory required for JVM container support

---

### 1.2 Service

**Purpose**: Exposes Schema Registry HTTP API within the cluster

**Key Fields**:
- `spec.type`: ClusterIP (internal access only)
- `spec.ports[0].port`: 8081 (default Schema Registry port)
- `spec.ports[0].targetPort`: Container port (matches Deployment)
- `spec.selector`: Matches Deployment pod labels

**Relationships**:
- Selects: Pods created by Deployment (via label selector)
- Consumed by: Other applications in cluster (Kafka connectors, producers/consumers)

**Validation Rules**:
- port >= 1024 (non-privileged port range)
- selector must match Deployment labels exactly

---

### 1.3 ConfigMap

**Purpose**: Stores schema-registry.properties configuration file

**Key Fields**:
- `data["schema-registry.properties"]`: Multi-line configuration file
  - `kafkastore.bootstrap.servers`: Kafka connection string (REQUIRED)
  - `host.name`: Pod hostname (uses downward API)
  - `listeners`: HTTP bind address and port
  - Custom properties from values.config (merged)

**Relationships**:
- Mounted by: Deployment as volume at `/etc/schema-registry/`
- Checksum tracked in: Deployment pod annotations

**Validation Rules**:
- kafkastore.bootstrap.servers must be non-empty
- listeners must bind to 0.0.0.0 (not 127.0.0.1) for cluster access

**State Transitions**:
- ConfigMap content change → checksum changes → Deployment triggers rolling update → pods restart with new config

---

### 1.4 ServiceAccount

**Purpose**: Provides identity for Schema Registry pods (RBAC, pod identity)

**Key Fields**:
- `metadata.name`: Service account name (default: schema-registry)
- `automountServiceAccountToken`: true (allows pod to access Kubernetes API if needed)

**Relationships**:
- Used by: Deployment pods (spec.template.spec.serviceAccountName)
- Can be bound to: RBAC Roles/ClusterRoles (not created by chart, operator responsibility)

**Validation Rules**:
- Name must be DNS-compatible (lowercase, alphanumeric, hyphens)

---

### 1.5 PodDisruptionBudget

**Purpose**: Ensures minimum replica count during voluntary disruptions (node drains, upgrades)

**Key Fields**:
- `spec.minAvailable`: ceiling(replicaCount / 2)
- `spec.selector.matchLabels`: Matches Deployment pod labels

**Relationships**:
- Protects: Pods created by Deployment
- Enforced by: Kubernetes eviction API

**Validation Rules**:
- Only created when replicaCount > 1
- minAvailable must be < replicaCount (Kubernetes requirement)

**Conditional Creation**:
```yaml
{{- if gt .Values.replicaCount 1 }}
# PodDisruptionBudget resource
{{- end }}
```

---

### 1.6 TopologySpreadConstraints (embedded in Deployment)

**Purpose**: Distributes pods across availability zones for resilience

**Key Fields** (in Deployment.spec.template.spec):
- `topologySpreadConstraints[0].maxSkew`: 1 (keep zones balanced within 1 pod)
- `topologySpreadConstraints[0].topologyKey`: topology.kubernetes.io/zone
- `topologySpreadConstraints[0].whenUnsatisfiable`: ScheduleAnyway (graceful degradation)

**Relationships**:
- Embedded in: Deployment pod template
- Enforced by: Kubernetes scheduler

**Validation Rules**:
- Only applied when replicaCount > 1
- topologyKey must match node labels (standard cloud provider labels)

---

## 2. values.yaml Configuration Schema

### 2.1 Top-Level Structure

```yaml
# Global configuration
replicaCount: int                    # Number of replicas (default: 1)

# Image configuration
image:
  repository: string                 # Container registry and image name
  pullPolicy: string                 # Always | IfNotPresent | Never
  tag: string                        # Image tag (default: Chart.appVersion)

imagePullSecrets: []                 # List of secret names for private registries

# Service configuration
service:
  type: string                       # ClusterIP | NodePort | LoadBalancer
  port: int                          # Service port (default: 8081)
  annotations: {}                    # Service annotations (load balancer config)

# Resource limits
resources:
  requests:
    memory: string                   # Memory request (default: 512Mi)
    cpu: string                      # CPU request (default: 500m)
  limits:
    memory: string                   # Memory limit (default: 2Gi)
    cpu: string                      # CPU limit (default: 2000m)

# Schema Registry configuration
config:
  kafkaBootstrapServers: string      # REQUIRED: Kafka connection string
  extraProperties: {}                # Additional schema-registry.properties entries

# JVM configuration
jvm:
  maxRAMPercentage: float            # JVM heap as % of container memory (default: 70.0)
  extraOpts: string                  # Additional JVM options

# High availability
podDisruptionBudget:
  enabled: bool                      # Create PDB when replicaCount > 1 (default: true)

topologySpreadConstraints:
  enabled: bool                      # Enable zone spreading (default: true)
  maxSkew: int                       # Max pod count difference between zones (default: 1)

# Security
securityContext:
  runAsNonRoot: bool                 # Run as non-root user (default: true)
  runAsUser: int                     # User ID (default: 65532)
  allowPrivilegeEscalation: bool     # Prevent privilege escalation (default: false)
  readOnlyRootFilesystem: bool       # Read-only root filesystem (default: true)

# Service account
serviceAccount:
  create: bool                       # Create service account (default: true)
  name: string                       # Service account name (default: "")
  annotations: {}                    # Service account annotations (e.g., IAM roles)

# Probes
livenessProbe:
  httpGet:
    path: string                     # Health check path (default: /)
    port: int                        # Health check port (default: 8081)
  initialDelaySeconds: int           # Wait before first probe (default: 30)
  periodSeconds: int                 # Probe interval (default: 10)
  timeoutSeconds: int                # Probe timeout (default: 5)
  failureThreshold: int              # Failures before restart (default: 3)

readinessProbe:
  httpGet:
    path: string                     # Readiness check path (default: /subjects)
    port: int                        # Readiness check port (default: 8081)
  initialDelaySeconds: int           # Wait before first probe (default: 10)
  periodSeconds: int                 # Probe interval (default: 5)
  timeoutSeconds: int                # Probe timeout (default: 3)
  failureThreshold: int              # Failures before unready (default: 3)

# Node affinity and tolerations
affinity: {}                         # Pod affinity rules (advanced)
nodeSelector: {}                     # Node selector labels
tolerations: []                      # Tolerations for tainted nodes
```

### 2.2 Required vs Optional Fields

**Required** (chart fails if missing):
- `config.kafkaBootstrapServers`: Cannot deploy Schema Registry without Kafka

**Optional with Sensible Defaults**:
- `replicaCount`: 1
- `image.repository`: ghcr.io/infobloxopen/ib-schema-registry
- `image.tag`: Chart.appVersion
- `resources.limits.memory`: 2Gi
- All other fields have defaults

### 2.3 Validation Logic

**Implemented in templates/_helpers.tpl**:
```yaml
{{- define "schema-registry.validate" -}}
{{- if not .Values.config.kafkaBootstrapServers -}}
{{- fail "config.kafkaBootstrapServers is required" -}}
{{- end -}}
{{- if lt .Values.replicaCount 0 -}}
{{- fail "replicaCount must be >= 0" -}}
{{- end -}}
{{- end -}}
```

---

## 3. ConfigMap Data Structure

### 3.1 schema-registry.properties Format

```properties
# Generated from Helm values
kafkastore.bootstrap.servers={{ .Values.config.kafkaBootstrapServers }}
host.name={{ include "schema-registry.fullname" . }}
listeners=http://0.0.0.0:8081

# Schema Registry defaults (overridable via config.extraProperties)
kafkastore.topic=_schemas
schema.registry.group.id=schema-registry

# Merge additional properties from values.config.extraProperties
{{ range $key, $value := .Values.config.extraProperties }}
{{ $key }}={{ $value }}
{{ end }}
```

### 3.2 Environment Variables (Alternative/Supplement)

Some properties set via environment variables (Schema Registry convention):

```yaml
env:
  - name: SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS
    value: {{ .Values.config.kafkaBootstrapServers }}
  - name: SCHEMA_REGISTRY_HOST_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
  - name: SCHEMA_REGISTRY_LISTENERS
    value: "http://0.0.0.0:8081"
  - name: SCHEMA_REGISTRY_OPTS
    value: "-XX:+UseContainerSupport -XX:MaxRAMPercentage={{ .Values.jvm.maxRAMPercentage }}"
```

**Precedence**: Environment variables override properties file (Schema Registry behavior).

---

## 4. Resource Relationships Diagram

```
┌─────────────────────────────────────────────────────┐
│ Helm Release: schema-registry                       │
└─────────────────────────────────────────────────────┘
                      │
      ┌───────────────┼───────────────┬──────────────┐
      │               │               │              │
      ▼               ▼               ▼              ▼
┌──────────┐   ┌─────────────┐  ┌─────────┐  ┌──────────────┐
│ConfigMap │   │ Deployment  │  │Service  │  │ServiceAccount│
│          │   │             │  │         │  │              │
│ schema-  │◄──│ Mounts as   │  │ Selects │  │              │
│ registry │   │ volume      │  │ pods    │  │              │
│.properties│   │             │  │ via     │  │              │
└──────────┘   │ Creates:    │  │ labels  │  │              │
      ▲        │  ┌────────┐ │  └─────────┘  └──────────────┘
      │        │  │Pod     │ │        ▲              ▲
      │        │  │        │ │        │              │
      │        │  │- Image │ │        │              │
   Checksum    │  │- Env   │ │        │              │
   triggers    │  │- Probes│─┼────────┘              │
   rolling     │  │- SA────┼─┼───────────────────────┘
   update      │  └────────┘ │
      │        └─────────────┘
      │               │
      │               ▼
      │        ┌──────────────────┐
      └────────│PodDisruptionBudget│
               │ (if replicas > 1) │
               └──────────────────┘
```

---

## 5. State Management

### 5.1 Configuration Changes

**Flow**: values.yaml change → ConfigMap content change → checksum changes → pod annotation changes → rolling update

**Example**:
1. Operator runs: `helm upgrade sr ./chart --set config.kafkaBootstrapServers=newkafka:9092`
2. Helm renders new ConfigMap with updated bootstrap servers
3. ConfigMap SHA256 changes: `abc123...` → `def456...`
4. Pod template annotation updated: `checksum/config: def456...`
5. Kubernetes Deployment controller notices pod template change
6. Rolling update begins: new pod created, old pod terminated (respecting PDB)

### 5.2 Scaling

**Flow**: replicaCount change → Deployment spec change → scale up/down

**Considerations**:
- PodDisruptionBudget dynamically adjusts minAvailable based on new replicaCount
- TopologySpreadConstraints redistributes pods across zones
- No data loss (state in Kafka, not pods)

### 5.3 Image Updates

**Flow**: image.tag change → pod template image field changes → rolling update

**Example**:
1. Operator runs: `helm upgrade sr ./chart --set image.tag=8.2.0`
2. Deployment pod template image updated: `...:8.1.1` → `...:8.2.0`
3. Rolling update replaces pods with new image
4. Readiness probe prevents traffic to new pods until healthy

---

## 6. Validation Rules Summary

| Field | Validation | Enforcement |
|-------|-----------|-------------|
| config.kafkaBootstrapServers | Non-empty string | Helm template fails if missing |
| replicaCount | >= 0 | Helm template validation |
| image.repository | Non-empty string | Kubernetes validation (image pull) |
| resources.limits.memory | Valid quantity (e.g., 2Gi) | Kubernetes validation |
| service.port | 1-65535 | Kubernetes validation |
| PDB minAvailable | < replicaCount | Kubernetes API validation |
| ServiceAccount name | DNS-compatible | Kubernetes validation |

---

## 7. Extensibility Points

### 7.1 Custom Properties

Users can add arbitrary Schema Registry properties via `config.extraProperties`:

```yaml
config:
  kafkaBootstrapServers: "kafka:9092"
  extraProperties:
    schema.compatibility.level: "FORWARD"
    kafkastore.security.protocol: "SASL_SSL"
    kafkastore.sasl.mechanism: "PLAIN"
```

### 7.2 Custom Annotations/Labels

Users can add annotations to Service, Deployment, etc. (future enhancement):

```yaml
service:
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8081"
```

### 7.3 Init Containers

Chart could support init containers for advanced setup (not in MVP):

```yaml
initContainers:
  - name: wait-for-kafka
    image: busybox
    command: ['sh', '-c', 'until nc -z kafka 9092; do sleep 1; done']
```

---

## Summary

### Key Entities

1. **Deployment**: Manages Schema Registry pods with rolling updates
2. **Service**: Exposes HTTP API (ClusterIP on port 8081)
3. **ConfigMap**: Stores schema-registry.properties configuration
4. **ServiceAccount**: Provides pod identity
5. **PodDisruptionBudget**: Ensures HA during disruptions (when replicas > 1)
6. **TopologySpreadConstraints**: Distributes pods across zones (when replicas > 1)

### Configuration Schema

- 40+ configurable parameters in values.yaml
- Required: `config.kafkaBootstrapServers`
- Sensible defaults for all other fields
- Validation via Helm template functions

### State Transitions

- ConfigMap change → rolling update
- Replica count change → scale up/down
- Image change → rolling update with health checks

**Ready for Phase 1 Contracts**: Example values.yaml files and NOTES.txt template.
