---
description: "Implementation tasks for Prometheus JMX Metrics Export feature"
---

# Tasks: Prometheus JMX Metrics Export

**Feature Branch**: `007-jmx-prometheus-metrics`  
**Input**: Design documents from `/specs/007-jmx-prometheus-metrics/`  
**Prerequisites**: [plan.md](plan.md), [spec.md](spec.md), [research.md](research.md), [data-model.md](data-model.md), [contracts/](contracts/)

**Implementation Strategy**: MVP-first approach focusing on User Story 1 (P1) as the core functionality. US2 and US3 can be implemented in parallel after foundational tasks are complete.

## Format: `- [ ] [ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (US1, US2, US3)
- File paths are relative to repository root

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Maven build configuration to fetch javaagent jar

- [X] T001 Configure maven-dependency-plugin in upstream/schema-registry/package-schema-registry/pom.xml to fetch io.prometheus.jmx:jmx_prometheus_javaagent:1.0.1
- [X] T002 Verify Maven build downloads javaagent jar to target/jmx-exporter/ directory

**Validation**: Run `mvn -f upstream/schema-registry/pom.xml clean prepare-package && ls -lh upstream/schema-registry/package-schema-registry/target/jmx-exporter/jmx_prometheus_javaagent.jar` (should show ~700KB jar file)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Container image modifications that ALL user stories depend on

**⚠️ CRITICAL**: No user story work can begin until Phase 2 is complete

- [X] T003 Add COPY instruction in Dockerfile to copy javaagent jar from upstream/schema-registry/package-schema-registry/target/jmx-exporter/ to /opt/jmx-exporter/ in container
- [X] T004 Set permissions (644) on /opt/jmx-exporter/jmx_prometheus_javaagent.jar in Dockerfile
- [X] T005 Verify javaagent jar exists in built container image at /opt/jmx-exporter/jmx_prometheus_javaagent.jar

**Validation**: Run `docker build -t test-sr . && docker run --rm test-sr ls -lh /opt/jmx-exporter/` (should show jmx_prometheus_javaagent.jar)

**Checkpoint**: Foundation ready - user story implementation can now begin in parallel

---

## Phase 3: User Story 1 - Enable Prometheus scraping in production (Priority: P1) 🎯 MVP

**Goal**: Enable Prometheus metrics collection in production deployments via single Helm value (`metrics.enabled=true`)

**Independent Test**: Deploy Helm chart with `metrics.enabled=true`, verify `curl http://<pod-ip>:9404/metrics` returns Prometheus-formatted metrics including Schema Registry JMX data

### Implementation for User Story 1

- [X] T006 [P] [US1] Add metrics configuration section to helm/ib-schema-registry/values.yaml (enabled: false, port: 9404, path: /metrics, annotations.enabled: true, config: null)
- [X] T007 [P] [US1] Create helm/ib-schema-registry/templates/configmap-jmx-exporter.yaml with default JMX exporter configuration (conditional on metrics.enabled)
- [X] T008 [US1] Add conditional JAVA_TOOL_OPTIONS environment variable in helm/ib-schema-registry/templates/deployment.yaml (only when metrics.enabled=true)
- [X] T009 [US1] Add ConfigMap volume mount in helm/ib-schema-registry/templates/deployment.yaml at /etc/schema-registry/jmx-exporter-config.yaml (conditional on metrics.enabled)
- [X] T010 [US1] Add ConfigMap volume definition in helm/ib-schema-registry/templates/deployment.yaml referencing metrics-config ConfigMap (conditional on metrics.enabled)
- [X] T011 [US1] Add metrics port definition in helm/ib-schema-registry/templates/service.yaml (name: metrics, port: metrics.port, conditional on metrics.enabled)
- [X] T012 [P] [US1] Add Prometheus scrape annotations to pod metadata in helm/ib-schema-registry/templates/deployment.yaml (conditional on metrics.enabled and metrics.annotations.enabled)
- [X] T013 [P] [US1] Update helm/ib-schema-registry/templates/NOTES.txt to include metrics endpoint information when metrics.enabled=true

### Testing for User Story 1

- [ ] T014 [US1] Add metrics endpoint validation to tests/smoke.sh (curl metrics endpoint when METRICS_ENABLED=true)
- [ ] T015 [US1] Add metrics.enabled=true test scenario to tests/e2e/test-helm-chart.sh (verify metrics port exposed, endpoint responds)
- [ ] T016 [US1] Add metrics endpoint check to tests/e2e/validate-schema-registry.sh (verify Prometheus format output, check for kafka_schema_registry_* metrics)

**Story Complete**: Operators can enable metrics with single Helm value, Prometheus can scrape metrics

---

## Phase 4: User Story 2 - Deploy without metrics overhead (Priority: P2)

**Goal**: Ensure default deployment without metrics enabled has zero overhead and maintains backwards compatibility

**Independent Test**: Deploy Helm chart with default values (metrics.enabled=false), verify no metrics port exposed and no javaagent loaded

### Implementation for User Story 2

- [X] T017 [P] [US2] Verify values.yaml has metrics.enabled: false as default (should already be set from T006)
- [X] T018 [P] [US2] Verify deployment.yaml conditionals prevent JAVA_TOOL_OPTIONS from being set when metrics.enabled=false (should already be implemented from T008)
- [X] T019 [P] [US2] Verify service.yaml conditionals prevent metrics port from being exposed when metrics.enabled=false (should already be implemented from T011)

### Testing for User Story 2

- [ ] T020 [US2] Add metrics.enabled=false test scenario to tests/e2e/test-helm-chart.sh (verify no metrics port in service, no javaagent in env)
- [ ] T021 [US2] Add test to verify :9404 port connection refused when metrics disabled in tests/e2e/validate-schema-registry.sh
- [ ] T022 [US2] Add performance comparison test to verify zero overhead when metrics disabled (optional: compare CPU/memory with metrics on vs off)

**Story Complete**: Default deployments have no metrics overhead, existing deployments unaffected

---

## Phase 5: User Story 3 - Customize metrics configuration (Priority: P3)

**Goal**: Allow platform operators to customize JMX exporter configuration and metrics port for advanced use cases

**Independent Test**: Deploy with custom metrics.config and metrics.port=9999, verify metrics on custom port with filtered metric set

### Implementation for User Story 3

- [X] T023 [US3] Add conditional logic in helm/ib-schema-registry/templates/configmap-jmx-exporter.yaml to use metrics.config if provided, else use default config
- [X] T024 [P] [US3] Update JAVA_TOOL_OPTIONS template in helm/ib-schema-registry/templates/deployment.yaml to use metrics.port value
- [X] T025 [P] [US3] Update service port template in helm/ib-schema-registry/templates/service.yaml to use metrics.port value
- [X] T026 [P] [US3] Update Prometheus annotations template in helm/ib-schema-registry/templates/deployment.yaml to use metrics.port and metrics.path values

### Testing for User Story 3

- [ ] T027 [US3] Add custom metrics.port test scenario to tests/e2e/test-helm-chart.sh (deploy with port 9999, verify service exposes custom port)
- [ ] T028 [US3] Add custom metrics.config test to tests/e2e/test-helm-chart.sh (provide minimal config, verify only specified metrics exported)
- [ ] T029 [US3] Add test to verify malformed metrics.config causes container startup failure in tests/e2e/test-helm-chart.sh

**Story Complete**: Operators can customize metrics configuration without rebuilding images

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation, README updates, and final integration validation

- [X] T030 [P] Update helm/ib-schema-registry/README.md with metrics configuration section (values table, usage examples)
- [X] T031 [P] Update README.md with Monitoring section (feature description, example Prometheus queries, license info for jmx_prometheus_javaagent)
- [X] T032 [P] Add example Prometheus scrape configuration to helm/ib-schema-registry/README.md
- [ ] T033 Verify multi-arch build works on both linux/amd64 and linux/arm64 with metrics enabled (run make build-multiarch)
- [ ] T034 Run full E2E test suite to verify no regressions in existing functionality
- [X] T035 [P] Update CHANGELOG.md with feature addition entry

**Final Validation**: All three user stories work independently, no constitutional violations, documentation complete

---

## Task Dependencies

### User Story Dependency Graph

```
Phase 1 (Setup) → Phase 2 (Foundational) → Phase 3 (US1) → Phase 4 (US2) → Phase 5 (US3) → Phase 6 (Polish)
                                         ↘                ↗
                                          (US2 and US3 can run in parallel after foundational)
```

**Critical Path**: T001 → T002 → T003 → T004 → T005 → T006-T016 (US1 implementation)

**Parallel Opportunities Within User Stories**:
- US1: T006, T007, T012, T013 can run in parallel (different files)
- US2: T017, T018, T019 can run in parallel (verification only)
- US3: T024, T025, T026 can run in parallel (different template sections)
- Phase 6: T030, T031, T032, T035 can run in parallel (documentation updates)

### Blocking Relationships

- **T003-T005 block ALL subsequent tasks**: Container image must have javaagent jar before Helm chart can use it
- **T006-T007 block T008-T013**: Helm values and ConfigMap must exist before deployment can reference them
- **T008-T011 block T014-T016**: Implementation must be complete before tests can validate it
- **T006 partially implemented in T023**: US3 extends US1's values.yaml (not a blocker, but logical dependency)

---

## Parallel Execution Strategy

### Phase 3 (US1) - Maximum Parallelization

**Batch 1** (independent template creation):
- T006: values.yaml (developer A)
- T007: configmap-jmx-exporter.yaml (developer B)
- T013: NOTES.txt (developer C)

**Batch 2** (deployment.yaml modifications):
- T008: JAVA_TOOL_OPTIONS env var (developer A)
- T009-T010: ConfigMap volume and mount (can be done together by developer A)
- T012: Prometheus annotations (developer B)

**Batch 3** (remaining components):
- T011: service.yaml port (developer C)

**Batch 4** (tests - after implementation):
- T014: smoke.sh (developer A)
- T015: test-helm-chart.sh (developer B)
- T016: validate-schema-registry.sh (developer C)

**Estimated Time Savings**: ~60% reduction vs sequential (8-12 parallel tasks out of ~13 total in US1)

---

## Task Summary

| Phase | Task Count | Parallelizable | User Story | Dependencies |
|-------|-----------|----------------|-----------|--------------|
| Phase 1: Setup | 2 | 0 | - | None |
| Phase 2: Foundational | 3 | 0 | - | Phase 1 |
| Phase 3: US1 (P1) | 11 | 5 | US1 | Phase 2 |
| Phase 4: US2 (P2) | 6 | 3 | US2 | Phase 2, US1 (partial) |
| Phase 5: US3 (P3) | 7 | 3 | US3 | Phase 2, US1 (extends) |
| Phase 6: Polish | 6 | 4 | - | All phases |
| **Total** | **35** | **15** | **3** | - |

**Parallelizable Tasks**: 15 out of 35 (43%) can run in parallel

**MVP Scope** (Minimum Viable Product): Phase 1 + Phase 2 + Phase 3 (US1 only)
- **Task Count**: 16 tasks
- **Deliverable**: Operators can enable Prometheus metrics in production deployments
- **Time Estimate**: 6-8 hours for single developer, 3-4 hours with 3 developers parallelizing

**Full Feature Scope**: All 6 phases
- **Task Count**: 35 tasks  
- **Time Estimate**: 12-16 hours for single developer, 6-8 hours with 3 developers parallelizing

---

## Independent Testing Per Story

### User Story 1 Testing (Independent)

**Prerequisites**: Phase 1 + Phase 2 complete

**Test Sequence**:
1. Deploy Helm chart with `--set metrics.enabled=true`
2. Wait for pod ready
3. Port-forward metrics port: `kubectl port-forward svc/<name> 9404:9404`
4. Curl endpoint: `curl http://localhost:9404/metrics`
5. Verify Prometheus format output
6. Verify metrics include `kafka_schema_registry_jetty_*`, `kafka_schema_registry_jersey_*`, `jvm_memory_*`

**Success Criteria**: Metrics endpoint responds with Prometheus text format, includes Schema Registry MBeans

### User Story 2 Testing (Independent)

**Prerequisites**: Phase 1 + Phase 2 complete

**Test Sequence**:
1. Deploy Helm chart with default values (metrics.enabled=false)
2. Wait for pod ready
3. Check service ports: `kubectl get svc <name> -o yaml | grep -A5 ports`
4. Verify only port 8081 present (no metrics port)
5. Check pod env: `kubectl get pod <name> -o yaml | grep JAVA_TOOL_OPTIONS`
6. Verify JAVA_TOOL_OPTIONS not set

**Success Criteria**: No metrics port, no javaagent, Schema Registry functions normally

### User Story 3 Testing (Independent)

**Prerequisites**: Phase 1 + Phase 2 + Phase 3 (US1) complete

**Test Sequence**:
1. Create custom values file with `metrics.enabled=true`, `metrics.port=9999`, custom `metrics.config`
2. Deploy Helm chart with custom values
3. Wait for pod ready
4. Port-forward custom port: `kubectl port-forward svc/<name> 9999:9999`
5. Curl endpoint: `curl http://localhost:9999/metrics`
6. Verify only metrics matching custom config appear

**Success Criteria**: Metrics on custom port, filtered metric set matches custom config

---

## Implementation Notes

### Task Format Compliance

✅ **All tasks follow required format**: `- [ ] [TaskID] [P?] [Story?] Description with file path`

**Examples**:
- `- [ ] T006 [P] [US1] Add metrics configuration section to helm/ib-schema-registry/values.yaml` ✓
- `- [ ] T008 [US1] Add conditional JAVA_TOOL_OPTIONS environment variable in helm/ib-schema-registry/templates/deployment.yaml` ✓
- `- [ ] T030 [P] Update helm/ib-schema-registry/README.md with metrics configuration section` ✓

### Story Label Usage

- **Setup phase (T001-T002)**: NO story label (shared infrastructure)
- **Foundational phase (T003-T005)**: NO story label (blocking prerequisites)
- **US1 phase (T006-T016)**: ALL tasks have `[US1]` label
- **US2 phase (T017-T022)**: ALL tasks have `[US2]` label
- **US3 phase (T023-T029)**: ALL tasks have `[US3]` label
- **Polish phase (T030-T035)**: NO story label (cross-cutting concerns)

### File Path Specificity

All tasks include exact file paths:
- ✅ `upstream/schema-registry/package-schema-registry/pom.xml`
- ✅ `helm/ib-schema-registry/values.yaml`
- ✅ `helm/ib-schema-registry/templates/deployment.yaml`
- ✅ `tests/smoke.sh`
- ✅ `README.md`

### Parallelization Markers

Tasks marked with `[P]` can be executed in parallel:
- Different files with no logical dependencies
- Independent verification tasks
- Documentation updates
- Separate test files

**Not marked [P]**:
- Tasks modifying same file sequentially
- Tasks with explicit dependencies (volume mount depends on volume definition)
- Test tasks that depend on implementation completion

---

## References

- [Feature Specification](spec.md) - User stories and requirements
- [Implementation Plan](plan.md) - Technical approach and structure
- [Research Decisions](research.md) - Technical decisions and rationale
- [Data Model](data-model.md) - Configuration schemas and runtime structures
- [Helm Values Contract](contracts/helm-values.yaml) - Helm values interface
- [JMX Exporter Config Contract](contracts/jmx-exporter-config.yaml) - JMX configuration format
- [Metrics Endpoint Contract](contracts/metrics-endpoint.md) - HTTP API specification
- [Quickstart Guide](quickstart.md) - Implementation checklist and commands
