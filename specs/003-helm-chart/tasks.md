# Tasks: Helm Chart for Kubernetes Deployment

**Branch**: `003-helm-chart` | **Date**: 2026-01-16  
**Input**: Design documents from `/specs/003-helm-chart/`  
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/)

**Note**: Tests are NOT requested in the specification except for E2E validation (User Story 5). Unit/contract tests for individual templates are omitted.

**Organization**: Tasks grouped by user story to enable independent implementation and testing per story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3, US4, US5, US6)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize Helm chart structure and repository scaffolding

- [ ] T001 Create chart directory structure at `chart/` with Chart.yaml, values.yaml, templates/, .helmignore
- [ ] T002 Create templates helper file at `chart/templates/_helpers.tpl` with name/label functions
- [ ] T003 [P] Add Helm targets to Makefile (helm-lint, helm-package, helm-push, helm-test-e2e)
- [ ] T004 [P] Create e2e test directory structure at `tests/e2e/` with README.md

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core chart components that MUST be complete before user story work begins

**⚠️ CRITICAL**: These resources are required by all deployment scenarios

- [ ] T005 Create Chart.yaml metadata in `chart/Chart.yaml` with apiVersion, name, version, appVersion, description, maintainers
- [ ] T006 Create base values.yaml schema in `chart/values.yaml` with image, replicaCount, service, resources structure
- [ ] T007 [P] Implement template helpers in `chart/templates/_helpers.tpl` (fullname, name, chart, labels, selectorLabels functions)
- [ ] T008 [P] Create .helmignore file in `chart/.helmignore` to exclude .git, .DS_Store, *.md files

**Checkpoint**: Foundation ready - user story templates can now be implemented in parallel

---

## Phase 3: User Story 1 - Deploy to Kubernetes (Priority: P1) 🎯 MVP

**Goal**: Operators can deploy Schema Registry to Kubernetes using `helm install` with basic health checks

**Independent Test**: Install chart on test cluster, verify pods start and API returns 200 on health endpoint

### Implementation for User Story 1

- [ ] T009 [P] [US1] Create Deployment template in `chart/templates/deployment.yaml` with container spec, image reference, ports, basic env vars
- [ ] T010 [P] [US1] Add liveness probe to Deployment in `chart/templates/deployment.yaml` (httpGet on / endpoint)
- [ ] T011 [P] [US1] Add readiness probe to Deployment in `chart/templates/deployment.yaml` (httpGet on /subjects endpoint)
- [ ] T012 [P] [US1] Configure securityContext in Deployment in `chart/templates/deployment.yaml` (runAsNonRoot, runAsUser 65532, allowPrivilegeEscalation false)
- [ ] T013 [P] [US1] Create Service template in `chart/templates/service.yaml` with ClusterIP type, port 8081, selector labels
- [ ] T014 [P] [US1] Create ServiceAccount template in `chart/templates/serviceaccount.yaml` with conditional creation
- [ ] T015 [US1] Add resource requests/limits to Deployment in `chart/templates/deployment.yaml` from values.resources
- [ ] T016 [US1] Create NOTES.txt template in `chart/templates/NOTES.txt` with basic access instructions
- [ ] T017 [US1] Create Helm test template in `chart/templates/tests/test-connection.yaml` to validate API connectivity

**Checkpoint**: Basic deployment functional - can install chart, pods start, API accessible

---

## Phase 4: User Story 2 - Configure via Values (Priority: P1) 🎯 MVP

**Goal**: Operators customize Schema Registry (replicas, Kafka connection, resources, JVM) through values.yaml

**Independent Test**: Deploy with custom values.yaml, verify configuration applied (check env vars, ConfigMap content)

### Implementation for User Story 2

- [ ] T018 [P] [US2] Create ConfigMap template in `chart/templates/configmap.yaml` with schema-registry.properties from values
- [ ] T019 [P] [US2] Add ConfigMap volume mount to Deployment in `chart/templates/deployment.yaml` at /etc/schema-registry/
- [ ] T020 [US2] Add Kafka bootstrap servers environment variable to Deployment in `chart/templates/deployment.yaml` from values.config.kafkaBootstrapServers
- [ ] T021 [US2] Add JVM options environment variable to Deployment in `chart/templates/deployment.yaml` (SCHEMA_REGISTRY_OPTS with UseContainerSupport and MaxRAMPercentage)
- [ ] T022 [US2] Add host.name environment variable to Deployment in `chart/templates/deployment.yaml` using downward API (metadata.name)
- [ ] T023 [US2] Add extraProperties support to ConfigMap in `chart/templates/configmap.yaml` (range loop over values.config.extraProperties)
- [ ] T024 [US2] Add validation function to helpers in `chart/templates/_helpers.tpl` to fail if kafkaBootstrapServers is empty
- [ ] T025 [US2] Enhance values.yaml in `chart/values.yaml` with comprehensive inline documentation for all 40+ parameters
- [ ] T026 [US2] Update NOTES.txt in `chart/templates/NOTES.txt` to show Kafka connection and configuration update instructions

**Checkpoint**: Configuration fully customizable - operators can set replicas, Kafka, resources via values

---

## Phase 5: User Story 3 - High Availability (Priority: P2)

**Goal**: Multi-replica deployments with pod distribution across zones and disruption protection

**Independent Test**: Deploy with replicaCount=3, verify PodDisruptionBudget exists and pods spread across zones

### Implementation for User Story 3

- [ ] T027 [P] [US3] Create PodDisruptionBudget template in `chart/templates/poddisruptionbudget.yaml` with conditional creation (if replicaCount > 1)
- [ ] T028 [US3] Add minAvailable calculation to PodDisruptionBudget in `chart/templates/poddisruptionbudget.yaml` (ceiling(replicaCount / 2) formula)
- [ ] T029 [US3] Add topologySpreadConstraints to Deployment in `chart/templates/deployment.yaml` (conditional, if replicaCount > 1)
- [ ] T030 [US3] Configure topologySpreadConstraints in Deployment in `chart/templates/deployment.yaml` (maxSkew: 1, topologyKey: topology.kubernetes.io/zone, whenUnsatisfiable: ScheduleAnyway)
- [ ] T031 [US3] Add HA configuration section to values.yaml in `chart/values.yaml` (podDisruptionBudget.enabled, topologySpreadConstraints.enabled, topologySpreadConstraints.maxSkew)
- [ ] T032 [US3] Update NOTES.txt in `chart/templates/NOTES.txt` to show HA status (replica count, PDB, topology spread)

**Checkpoint**: HA features functional - multi-replica deployments resilient to node failures and zone outages

---

## Phase 6: User Story 4 - Rolling Updates (Priority: P2)

**Goal**: Configuration changes via Helm upgrade trigger automatic pod restarts

**Independent Test**: Deploy chart, update ConfigMap via helm upgrade, verify pods restart automatically

### Implementation for User Story 4

- [ ] T033 [US4] Add ConfigMap checksum annotation to Deployment in `chart/templates/deployment.yaml` (pod template annotations, sha256sum of configmap.yaml)
- [ ] T034 [US4] Test rolling update behavior: update values, run helm upgrade, verify new pods created with updated config
- [ ] T035 [US4] Update NOTES.txt in `chart/templates/NOTES.txt` to document rolling update behavior and helm upgrade command

**Checkpoint**: Rolling updates functional - configuration changes automatically applied without manual intervention

---

## Phase 7: User Story 5 - E2E Validation (Priority: P2)

**Goal**: Automated E2E tests validate full deployment lifecycle with k3d and Redpanda

**Independent Test**: Run e2e test suite in CI, verify passes with fresh cluster

### Implementation for User Story 5

- [ ] T036 [P] [US5] Create k3d cluster setup script in `tests/e2e/setup-k3d-cluster.sh` (create cluster with 2 agents)
- [ ] T037 [P] [US5] Create Redpanda deployment script in `tests/e2e/deploy-redpanda.sh` (Deployment + Service YAML)
- [ ] T038 [US5] Create Schema Registry validation script in `tests/e2e/validate-schema-registry.sh` (register schema, retrieve, list subjects)
- [ ] T039 [US5] Create main E2E test orchestrator in `tests/e2e/test-helm-chart.sh` (calls setup, deploy, validate, teardown)
- [ ] T040 [US5] Create teardown script in `tests/e2e/teardown.sh` (delete k3d cluster and resources)
- [ ] T041 [US5] Create E2E test documentation in `tests/e2e/README.md` with prerequisites and usage
- [ ] T042 [US5] Create GitHub Actions workflow in `.github/workflows/helm-test.yaml` for Helm chart CI (lint, e2e tests, matrix for architectures)
- [ ] T043 [US5] Add helm-test-e2e target to Makefile in `Makefile` to run E2E tests locally

**Checkpoint**: E2E tests functional - automated validation catches regressions in chart behavior

---

## Phase 8: User Story 6 - OCI Packaging (Priority: P3)

**Goal**: Helm chart packaged as OCI artifact for distribution via container registry

**Independent Test**: Package chart as OCI image, push to registry, install from OCI source

### Implementation for User Story 6

- [ ] T044 [P] [US6] Add helm-package target to Makefile in `Makefile` (helm package chart/)
- [ ] T045 [P] [US6] Add helm-push target to Makefile in `Makefile` (helm push to OCI registry)
- [ ] T046 [US6] Update Chart.yaml in `chart/Chart.yaml` to reference multi-arch container images (annotations or documentation)
- [ ] T047 [US6] Create chart packaging documentation in `chart/README.md` with helm push examples
- [ ] T048 [US6] Update GitHub Actions workflow in `.github/workflows/helm-test.yaml` to publish chart to GHCR on release

**Checkpoint**: OCI packaging complete - chart distributed as container artifact alongside images

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final refinements, documentation, and release readiness

- [ ] T049 [P] Create comprehensive chart README in `chart/README.md` with installation, configuration, examples, troubleshooting
- [ ] T050 [P] Add affinity/tolerations/nodeSelector support to values.yaml in `chart/values.yaml` and Deployment template
- [ ] T051 [P] Add imagePullSecrets support to values.yaml in `chart/values.yaml` and Deployment template
- [ ] T052 [P] Add service annotations support to values.yaml in `chart/values.yaml` and Service template
- [ ] T053 Validate all values.yaml parameters have inline documentation comments
- [ ] T054 Run helm lint on chart and fix any warnings
- [ ] T055 Test chart with values-minimal.yaml and values-ha.yaml from contracts/
- [ ] T056 Update repository README.md with Helm chart usage section
- [ ] T057 Create CHANGELOG entry for Helm chart feature

**Checkpoint**: Chart production-ready - comprehensive documentation, validated configurations, CI passing

---

## Dependencies & Parallel Execution

### Phase Dependencies (Sequential)

1. **Phase 1 (Setup)** → Must complete first
2. **Phase 2 (Foundational)** → Must complete before any user stories
3. **Phases 3-8 (User Stories)** → Can be implemented in parallel after Phase 2 completes
4. **Phase 9 (Polish)** → Should be done after all user stories complete

### Within-Phase Parallelization

**Phase 3 (US1)**: Tasks T009-T014, T017 can run in parallel (different templates)  
**Phase 4 (US2)**: Tasks T018-T019 can run in parallel, T025-T026 can run in parallel  
**Phase 5 (US3)**: Task T027 independent, T029-T030 must be sequential (same file)  
**Phase 7 (US5)**: Tasks T036-T037, T041-T043 can run in parallel (different files)  
**Phase 8 (US6)**: Tasks T044-T045, T047 can run in parallel  
**Phase 9 (Polish)**: Tasks T049-T052 can run in parallel (different files)

### Suggested MVP Scope

**Minimum for deployment**: Phases 1, 2, 3, 4 (T001-T026)  
**Production ready**: Add Phase 5 (T027-T032)  
**Fully automated**: Add Phase 7 (T036-T043)

---

## Task Summary

- **Total Tasks**: 57
- **Parallelizable**: 24 tasks marked with [P]
- **User Story Distribution**:
  - US1 (Deploy): 9 tasks
  - US2 (Configure): 9 tasks
  - US3 (HA): 6 tasks
  - US4 (Rolling Updates): 3 tasks
  - US5 (E2E Tests): 8 tasks
  - US6 (OCI Packaging): 5 tasks
  - Setup/Foundational: 8 tasks
  - Polish: 9 tasks

**Implementation Strategy**: 
1. Complete Phases 1-2 (foundational)
2. Implement US1+US2 for MVP (P1 stories)
3. Add US3-US4 for production readiness (P2 stories)
4. Implement US5 for CI automation (P2)
5. Add US6 for advanced distribution (P3)
6. Polish and document (Phase 9)
