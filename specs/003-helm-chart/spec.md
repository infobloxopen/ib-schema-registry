# Feature Specification: Helm Chart for Kubernetes Deployment

**Feature Branch**: `003-helm-chart`  
**Created**: 2026-01-16  
**Status**: Draft  
**Input**: User description: "Helm chart for Kubernetes deployment with packaging and e2e testing"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Deploy Schema Registry to Kubernetes (Priority: P1)

Platform operators need to deploy Schema Registry to their Kubernetes clusters using standard Kubernetes tooling (Helm). The deployment should follow cloud-native best practices including health checks, resource limits, and configuration management.

**Why this priority**: Core functionality - without Helm chart deployment, users cannot run Schema Registry on Kubernetes.

**Independent Test**: Can be fully tested by installing the Helm chart on a test cluster and verifying the Schema Registry API responds to health check requests, delivering a working Schema Registry instance.

**Acceptance Scenarios**:

1. **Given** a Kubernetes cluster with Helm installed, **When** operator runs `helm install my-registry ./chart`, **Then** Schema Registry pods start successfully and pass readiness probes
2. **Given** a deployed Schema Registry instance, **When** operator queries the health endpoint, **Then** Schema Registry returns HTTP 200 with healthy status
3. **Given** a deployed instance, **When** operator inspects the deployment, **Then** all pods are running as non-root users and have resource limits configured

---

### User Story 2 - Configure Schema Registry via Values (Priority: P1)

Platform operators need to customize Schema Registry configuration (replicas, resources, Kafka connection, authentication) through Helm values without editing raw Kubernetes manifests.

**Why this priority**: Essential for production use - operators must configure Schema Registry to match their environment (Kafka clusters, security policies, resource constraints).

**Independent Test**: Can be tested by deploying with custom values.yaml overriding defaults (replicas, Kafka bootstrap servers, resource limits) and verifying configuration is applied correctly.

**Acceptance Scenarios**:

1. **Given** a values.yaml with custom replica count, **When** operator installs chart, **Then** deployment creates the specified number of pods
2. **Given** values specifying Kafka bootstrap servers, **When** Schema Registry starts, **Then** it connects to the correct Kafka cluster
3. **Given** custom resource requests/limits in values, **When** pods start, **Then** Kubernetes applies the specified resource constraints
4. **Given** Java JVM settings in values, **When** containers start, **Then** JVM heap size is configured based on container memory limits

---

### User Story 3 - High Availability Deployment (Priority: P2)

Platform operators deploying Schema Registry with multiple replicas need automatic pod distribution across zones/nodes and disruption protection to ensure high availability during node maintenance or failures.

**Why this priority**: Required for production resilience but not needed for single-replica deployments or development environments.

**Independent Test**: Deploy with replicas > 1 and verify PodDisruptionBudget exists and TopologySpreadConstraints distribute pods across availability zones.

**Acceptance Scenarios**:

1. **Given** values.yaml with `replicaCount: 3`, **When** chart is installed, **Then** PodDisruptionBudget is created ensuring at least 2 pods remain available during disruptions
2. **Given** a multi-node cluster with zone labels, **When** 3 replicas are deployed, **Then** TopologySpreadConstraints spread pods across different availability zones
3. **Given** a node draining event, **When** Kubernetes evicts a pod, **Then** PodDisruptionBudget prevents eviction if it would violate availability requirements

---

### User Story 4 - Configuration Changes Trigger Rolling Updates (Priority: P2)

Operators updating Schema Registry configuration (via ConfigMap) need pods to automatically restart with new configuration without manual intervention, ensuring configuration changes are applied reliably.

**Why this priority**: Operational efficiency - prevents configuration drift and reduces manual intervention, but basic deployment works without it.

**Independent Test**: Deploy chart, update ConfigMap via Helm upgrade, verify pods automatically restart with checksum-driven rolling update.

**Acceptance Scenarios**:

1. **Given** a running deployment, **When** operator updates configuration in values and runs `helm upgrade`, **Then** ConfigMap is updated and pods restart automatically
2. **Given** a ConfigMap update, **When** pods restart, **Then** each pod annotation includes a checksum of the ConfigMap content
3. **Given** unchanged configuration during upgrade, **When** operator runs helm upgrade, **Then** pods do NOT restart (checksum unchanged)

---

### User Story 5 - End-to-End Validation (Priority: P2)

Developers contributing to the Helm chart need automated end-to-end tests that validate the chart deploys successfully and Schema Registry functions correctly with a real Kafka-compatible backend.

**Why this priority**: Development quality assurance - ensures chart changes don't break deployments, but chart can function without automated tests.

**Independent Test**: Run e2e test suite in CI that creates k3d cluster, deploys Redpanda and Schema Registry chart, validates API operations.

**Acceptance Scenarios**:

1. **Given** a k3d test cluster, **When** e2e test deploys Redpanda and Schema Registry chart, **Then** both services start successfully within 5 minutes
2. **Given** deployed test environment, **When** test registers a schema via API, **Then** schema is successfully stored and retrievable
3. **Given** a chart code change, **When** CI runs e2e tests, **Then** test provides pass/fail feedback within 10 minutes

---

### User Story 6 - Helm Chart as OCI Artifact (Priority: P3)

Platform teams using GitOps or Helm OCI registries need the Helm chart packaged as an OCI image for distribution alongside container images, enabling unified artifact management.

**Why this priority**: Nice-to-have for advanced use cases - chart can be distributed via Git or traditional Helm repos without OCI packaging.

**Independent Test**: Package chart as OCI image, push to registry, pull and install from OCI registry.

**Acceptance Scenarios**:

1. **Given** a built Helm chart, **When** chart is packaged as OCI artifact, **Then** OCI image can be pushed to container registry
2. **Given** chart in OCI registry, **When** operator runs `helm install oci://registry/chart`, **Then** chart installs successfully from OCI source
3. **Given** multi-arch container images, **When** chart metadata is generated, **Then** chart references multi-arch image digests

---

### Edge Cases

- What happens when Schema Registry cannot connect to Kafka at startup? (Should retry with exponential backoff, pod should remain in CrashLoopBackOff until Kafka is available, readiness probe should fail)
- How does system handle memory pressure in containers? (JVM should detect container memory limits via -XX:+UseContainerSupport, helm values should allow override of heap settings, OOMKilled pods should restart with proper backoff)
- What happens during a rolling update if new config is invalid? (Kubernetes should halt rollout when new pods fail readiness checks, old pods remain running, operator gets clear failure message)
- How does chart handle different Kubernetes versions? (Chart should specify minimum kubeVersion, use stable API versions, avoid deprecated APIs)
- What if operators deploy with zero replicas? (Chart should validate replicaCount >= 1, or allow 0 for specific maintenance scenarios if documented)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Chart MUST create a Deployment resource that runs Schema Registry container with configurable replica count (default: 1)
- **FR-002**: Chart MUST create a Service resource exposing Schema Registry HTTP API on configurable port (default: 8081)
- **FR-003**: Chart MUST generate a ConfigMap containing Schema Registry configuration properties, templated from Helm values
- **FR-004**: Chart MUST configure container environment variables for Schema Registry, with values sourced from Helm values.yaml
- **FR-005**: Deployment MUST include pod annotations with ConfigMap checksum to trigger rolling updates when configuration changes
- **FR-006**: Chart MUST support configuration of Kafka bootstrap servers via values (required for Schema Registry to function)
- **FR-007**: Chart MUST create a PodDisruptionBudget when `replicaCount > 1`, ensuring at least `ceiling(replicaCount/2)` pods remain available
- **FR-008**: Chart MUST configure TopologySpreadConstraints when `replicaCount > 1` to distribute pods across availability zones with ScheduleAnyway policy
- **FR-009**: Chart MUST configure container resource requests and limits based on values, with sensible defaults (requests: 512Mi/500m, limits: 2Gi/2000m)
- **FR-010**: Container MUST configure JVM to respect container memory limits using `-XX:+UseContainerSupport` and `-XX:MaxRAMPercentage`
- **FR-011**: Deployment MUST include readiness and liveness probes checking Schema Registry health endpoint
- **FR-012**: Chart MUST support ConfigMap-based configuration for properties that cannot be set via environment variables
- **FR-013**: values.yaml MUST include comprehensive documentation comments explaining each configurable parameter and its default value
- **FR-014**: Chart MUST validate required values (Kafka bootstrap servers) and fail with clear error message if missing
- **FR-015**: E2E test suite MUST create k3d cluster, deploy Redpanda, install Schema Registry chart, and validate API operations
- **FR-016**: E2E test MUST verify schema registration, retrieval, and deletion operations against live Schema Registry
- **FR-017**: Chart packaging MUST generate Helm chart OCI artifact compatible with `helm push` to container registries
- **FR-018**: Chart MUST include NOTES.txt template providing post-install instructions for accessing Schema Registry

### Security & Portability Requirements

- **SPR-001**: Container MUST run as non-root user (UID 65532) matching the container image's default user
- **SPR-002**: Deployment MUST set `securityContext.runAsNonRoot: true` and `securityContext.allowPrivilegeEscalation: false`
- **SPR-003**: Service Account MUST be created for Schema Registry pods with minimal required permissions (none by default)
- **SPR-004**: Chart MUST support custom service account name via values for environments with pod identity requirements
- **SPR-005**: Image reference MUST be configurable via values (repository, tag, pullPolicy) to support private registries
- **SPR-006**: Chart MUST support imagePullSecrets configuration for private container registries
- **SPR-007**: ConfigMap and Secret references MUST use checksum annotations to ensure updates trigger pod restarts
- **SPR-008**: Chart MUST be compatible with Kubernetes 1.24+ (minimum version supporting stable APIs used)
- **SPR-009**: Chart MUST use stable API versions (apps/v1, v1, policy/v1) and avoid deprecated APIs
- **SPR-010**: Helm chart OCI artifact MUST reference multi-arch container images (linux/amd64, linux/arm64)

### Key Entities

- **Helm Chart**: Package containing Kubernetes manifests (templates) and values.yaml defining Schema Registry deployment
- **ConfigMap**: Kubernetes resource containing Schema Registry configuration properties file (schema-registry.properties)
- **Deployment**: Kubernetes resource managing Schema Registry pod replicas with rolling update strategy
- **Service**: Kubernetes resource exposing Schema Registry HTTP API internally within cluster
- **PodDisruptionBudget**: Kubernetes resource limiting concurrent pod evictions to maintain availability
- **TopologySpreadConstraints**: Pod scheduling rules distributing replicas across zones/nodes for resilience

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can deploy Schema Registry to Kubernetes cluster from Helm chart in under 2 minutes
- **SC-002**: Deployed Schema Registry successfully connects to Kafka and passes readiness checks within 1 minute of pod start
- **SC-003**: Configuration changes via `helm upgrade` trigger automatic pod rolling updates within 30 seconds
- **SC-004**: Multi-replica deployments (3 pods) survive single node failure without service disruption
- **SC-005**: E2E test suite completes successfully in under 10 minutes, validating full deployment and API operations
- **SC-006**: Chart supports deployment on ARM64 and AMD64 Kubernetes clusters without modification
- **SC-007**: 90% of configuration parameters documented in values.yaml with clear descriptions and examples
- **SC-008**: JVM automatically adjusts heap size to 70% of container memory limit, preventing OOMKilled pods

## Assumptions

- Schema Registry container image is already built and available (from previous feature 001-schema-registry-image)
- Kubernetes cluster has StorageClass available for any persistent volumes (though Schema Registry itself is stateless)
- Kafka or Kafka-compatible system (like Redpanda) is deployed separately and accessible from Kubernetes cluster
- Cluster has network connectivity to pull container images from specified registry
- k3d is acceptable tool for e2e testing (lightweight, fast, sufficient for validation)
- Redpanda is suitable Kafka-compatible backend for e2e tests (lighter than full Kafka, API compatible)
- Helm 3.x is used (not Helm 2.x which is deprecated)
- Chart will use environment variables as primary configuration method where Schema Registry supports them
- ConfigMap will handle configuration properties not supported via environment variables
- Single ConfigMap per release is sufficient (no need for multiple ConfigMaps)

## Dependencies

- Feature 001 (schema-registry-image) must be completed - provides container image referenced by Helm chart
- k3d CLI tool must be available for e2e testing
- Helm CLI must be available for chart packaging and testing
- Container registry supporting OCI artifacts (for Helm chart packaging as image)
- Redpanda Helm chart or deployment manifests for e2e test Kafka backend

## Out of Scope

- Kafka/Redpanda deployment (users deploy separately or use existing cluster)
- Schema Registry clustering/leader election (handled by upstream Schema Registry, not chart)
- Ingress resources (operators configure separately based on their ingress controller)
- TLS certificate management (operators use cert-manager or other tools)
- Monitoring/alerting configuration (operators integrate with their observability stack)
- Backup/restore procedures (Schema Registry state in Kafka, handled by Kafka backup)
- Authentication/authorization (configured via values, but setup of auth providers is user responsibility)
- Multi-namespace deployment (single namespace per Helm release)
- StatefulSet alternative (Deployment is appropriate as Schema Registry is stateless)
- HorizontalPodAutoscaler (operators add separately if desired)
- NetworkPolicies (cluster-specific, operators configure based on their security model)

## Notes

- Chart should follow Helm best practices: https://helm.sh/docs/chart_best_practices/
- JVM container detection: `-XX:+UseContainerSupport` and `-XX:MaxRAMPercentage=70.0` are recommended for containerized Java apps
- PodDisruptionBudget formula: `minAvailable = ceiling(replicaCount / 2)` ensures majority availability
- TopologySpreadConstraints should use `whenUnsatisfiable: ScheduleAnyway` to allow deployment even if zones unavailable (graceful degradation)
- ConfigMap checksum pattern: `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}`
- Chart packaging as OCI: Use `helm package` then `helm push` to OCI registry (requires Helm 3.8+)
- E2E test should clean up resources after test (delete k3d cluster) to avoid resource leaks in CI
