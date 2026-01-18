# Implementation Plan: Prometheus JMX Metrics Export

**Branch**: `007-jmx-prometheus-metrics` | **Date**: 2026-01-18 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-jmx-prometheus-metrics/spec.md`

**Note**: This template is filled in by the `/speckit.plan` command. See `.specify/templates/commands/plan.md` for the execution workflow.

## Summary

Add Prometheus JMX metrics export capability to Schema Registry container via in-process javaagent integration. Primary requirement: enable Prometheus scraping of Schema Registry JMX metrics through HTTP /metrics endpoint without requiring separate sidecars or remote JMX ports. Technical approach: integrate `io.prometheus.jmx:jmx_prometheus_javaagent` (version 1.0.1) into build pipeline, package in container image, and provide Helm chart controls for opt-in enablement with ConfigMap-based configuration.

## Technical Context

**Language/Version**: Java 17 (inherited from upstream Confluent Schema Registry)  
**Primary Dependencies**: 
- `io.prometheus.jmx:jmx_prometheus_javaagent:1.0.1` (new dependency)
- Maven 3+ (existing build system)
- Confluent Schema Registry 8.1.1 (current upstream version)

**Storage**: N/A (metrics are ephemeral, exported via HTTP)  
**Testing**: 
- Bash smoke tests (existing framework in `tests/`)
- Docker-based E2E tests with Kubernetes (k3d + Helm, existing in `tests/e2e/`)
- curl-based metrics endpoint validation

**Target Platform**: 
- Container: linux/amd64, linux/arm64 (multi-arch OCI image)
- Runtime: Kubernetes with Helm chart deployment
- Metrics consumer: Prometheus (HTTP pull model)

**Project Type**: Container image + Helm chart (infrastructure/deployment)

**Performance Goals**: 
- Metrics endpoint response time: <500ms under normal load (<100 qps to Schema Registry)
- JMX exporter overhead: <5% additional CPU usage
- Memory overhead: <50MB additional RSS

**Constraints**: 
- MUST work with existing distroless-compatible runtime (no shell assumptions)
- MUST NOT break existing JAVA_TOOL_OPTIONS or environment variable handling
- MUST NOT open remote JMX ports (security requirement)
- MUST work identically on both amd64 and arm64 platforms

**Scale/Scope**: 
- Single container modification (add javaagent + config)
- Helm chart additions: ~150 lines (new ConfigMap, service port, deployment env vars)
- Maven build additions: ~20 lines (maven-dependency-plugin configuration)
- Expected metrics output: 50-100 Prometheus metrics (JVM + Schema Registry MBeans)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Initial Check (Pre-Phase 0)

- [x] **Multi-arch portability**: Javaagent jar downloaded from Maven Central works identically on amd64 and arm64 (architecture-independent Java bytecode). Build uses existing multi-arch Docker buildx pipeline. No platform-specific scripts needed.
- [x] **Base image pluggability**: No changes to base image selection. Javaagent integration uses existing Java runtime, works with both Eclipse Temurin and Chainguard JRE base images.
- [x] **Distroless compatibility**: Javaagent loaded via JAVA_TOOL_OPTIONS environment variable (exec-form compatible). No shell scripts in entrypoint. ConfigMap provides YAML config file (no shell parsing required).
- [x] **Supply-chain security**: 
  - [x] Runtime images continue to run as non-root user (no privilege escalation).
  - [x] Javaagent jar fetched from Maven Central during build via maven-dependency-plugin (trusted source).
  - [x] No new binary downloads or `curl | bash` patterns.
  - [x] OCI labels unchanged (existing versioning scheme applies).
- [x] **Licensing compliance**: Prometheus JMX Exporter is Apache 2.0 licensed (compatible). No upstream Schema Registry code modifications. README will document new dependency license.
- [x] **Repository ergonomics**: No new Makefile targets required (existing `make build`, `make build-multiarch`, `make test` work unchanged). Helm chart changes are self-documenting via values.yaml comments.
- [x] **Testing validation**: Existing CI pipeline builds both architectures. New smoke test will validate metrics endpoint when enabled. E2E Helm tests will verify metrics.enabled=true and metrics.enabled=false scenarios.

**Initial Check Result**: ✅ No violations. Feature fully complies with constitution.

### Post-Design Re-check (Post-Phase 1)

*Re-evaluated after completing research.md, data-model.md, contracts/, and quickstart.md.*

- [x] **Multi-arch portability**: Design confirms no platform-specific code paths. Maven dependency plugin fetches universal jar. Helm templates use standard Kubernetes constructs (no architecture-specific logic).
- [x] **Base image pluggability**: No base image coupling introduced. Design uses `/opt/jmx-exporter/` path (not base-image-specific). JAVA_TOOL_OPTIONS works with any JVM base image.
- [x] **Distroless compatibility**: Design validated against distroless constraints:
  - ✅ No shell commands in entrypoint modifications
  - ✅ ConfigMap volume mount (Kubernetes primitive, no shell required)
  - ✅ Environment variable injection only (JAVA_TOOL_OPTIONS)
  - ✅ No startup scripts or bash dependencies
- [x] **Supply-chain security**: 
  - [x] Design documents Maven Central as single trusted source for javaagent jar.
  - [x] Helm ConfigMap contains only YAML configuration (no executable code).
  - [x] No new network ports opened except metrics endpoint (HTTP only, no RMI/JMX remote).
  - [x] Metrics endpoint exposes only operational telemetry (no sensitive data).
- [x] **Licensing compliance**: 
  - [x] Prometheus JMX Exporter verified as Apache 2.0.
  - [x] No modifications to upstream Schema Registry source code.
  - [x] Quickstart.md documents adding license info to README.
- [x] **Repository ergonomics**: 
  - [x] Design preserves existing Makefile interface (no new targets).
  - [x] Helm chart follows existing patterns (conditional templates, default disabled).
  - [x] values.yaml additions use nested structure (metrics.*) for clarity.
  - [x] Quickstart guide provides comprehensive implementation checklist.
- [x] **Testing validation**: 
  - [x] Design includes three-tier testing strategy (smoke/E2E/integration).
  - [x] Smoke test validates both metrics.enabled=true and metrics.enabled=false.
  - [x] E2E test covers upgrade path (disabled → enabled).
  - [x] Integration test validates Prometheus scraping.

**Post-Design Result**: ✅ No violations introduced during design phase. All constitution principles preserved.

**Justification for any deviations**: None. Feature design fully aligns with constitutional requirements.

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (/speckit.plan command output)
├── research.md          # Phase 0 output (/speckit.plan command)
├── data-model.md        # Phase 1 output (/speckit.plan command)
├── quickstart.md        # Phase 1 output (/speckit.plan command)
├── contracts/           # Phase 1 output (/speckit.plan command)
└── tasks.md             # Phase 2 output (/speckit.tasks command - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
upstream/schema-registry/           # Git submodule (modified pom.xml)
├── package-schema-registry/
│   └── pom.xml                     # Add maven-dependency-plugin to fetch javaagent jar

Dockerfile                          # Copy javaagent jar to /opt/jmx-exporter/
helm/ib-schema-registry/
├── values.yaml                     # Add metrics.* configuration section
├── templates/
│   ├── deployment.yaml             # Add metrics port, JAVA_TOOL_OPTIONS env var, ConfigMap volume
│   ├── service.yaml                # Add metrics port when metrics.enabled
│   ├── configmap-jmx-exporter.yaml # New: JMX exporter config (when metrics.enabled)
│   └── NOTES.txt                   # Add metrics endpoint info

tests/
├── smoke.sh                        # Add metrics endpoint validation
└── e2e/
    ├── test-helm-chart.sh          # Add metrics.enabled test scenarios
    └── validate-schema-registry.sh  # Add metrics endpoint checks

README.md                           # Document metrics feature + Apache 2.0 license for jmx_prometheus_javaagent
```


# [REMOVE IF UNUSED] Option 3: Mobile + API (when "iOS/Android" detected)
api/
└── [same as backend above]

ios/ or android/
└── [platform-specific structure: feature modules, UI flows, platform tests]
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |
| [e.g., Repository pattern] | [specific problem] | [why direct DB access insufficient] |
