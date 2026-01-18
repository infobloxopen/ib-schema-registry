# Feature Specification: Prometheus JMX Metrics Export

**Feature Branch**: `007-jmx-prometheus-metrics`  
**Created**: January 18, 2026  
**Status**: Draft  
**Input**: User description: "add support for exporting JMX metrics to prometheus"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Enable Prometheus scraping in production (Priority: P1)

As a platform operator running Schema Registry in Kubernetes, I need to enable Prometheus metrics collection to monitor the health and performance of my Schema Registry instances without having to rebuild container images or manually configure JMX settings.

**Why this priority**: Observability is critical for production operations. This is the core functionality that enables all monitoring workflows.

**Independent Test**: Can be fully tested by setting `metrics.enabled=true` in Helm values, deploying the chart, and verifying that `curl http://<pod-ip>:9404/metrics` returns Prometheus-formatted metrics including Schema Registry-specific JMX data.

**Acceptance Scenarios**:

1. **Given** a Kubernetes cluster with Prometheus, **When** operator deploys Helm chart with `metrics.enabled=true`, **Then** Prometheus successfully scrapes metrics from Schema Registry pods
2. **Given** Schema Registry is processing schema requests, **When** metrics endpoint is queried, **Then** response includes JMX metrics for Jetty, Jersey, and master-slave role
3. **Given** metrics are enabled, **When** operator queries service endpoints, **Then** metrics port (9404) is exposed alongside the main API port (8081)

---

### User Story 2 - Deploy without metrics overhead (Priority: P2)

As a developer running Schema Registry in development/test environments, I need to deploy without metrics collection enabled by default to minimize resource usage and simplify the deployment when monitoring is not needed.

**Why this priority**: Resource efficiency in non-production environments and maintaining backwards compatibility for existing deployments.

**Independent Test**: Can be fully tested by deploying Helm chart with default values (or explicitly `metrics.enabled=false`) and verifying that no metrics port is exposed and `/metrics` endpoint returns 404.

**Acceptance Scenarios**:

1. **Given** default Helm values, **When** chart is deployed, **Then** no metrics port is opened and no javaagent is loaded
2. **Given** `metrics.enabled=false`, **When** pod starts, **Then** `JAVA_TOOL_OPTIONS` does not include javaagent flag
3. **Given** metrics disabled, **When** operator attempts to access `:9404/metrics`, **Then** connection is refused (port not listening)

---

### User Story 3 - Customize metrics configuration (Priority: P3)

As a platform operator with specific monitoring requirements, I need to customize which JMX beans are exported and adjust the metrics port to fit my infrastructure standards without rebuilding the container image.

**Why this priority**: Flexibility for advanced users with specific monitoring requirements, but not essential for basic functionality.

**Independent Test**: Can be fully tested by providing a custom JMX exporter config via ConfigMap override, deploying with custom `metrics.port` value, and verifying metrics are exposed on the custom port with the filtered metric set.

**Acceptance Scenarios**:

1. **Given** custom JMX exporter config in values, **When** chart is deployed, **Then** only specified MBeans appear in metrics output
2. **Given** `metrics.port=9999`, **When** pod starts, **Then** metrics are accessible on port 9999 instead of default 9404
3. **Given** custom config filters out JVM metrics, **When** metrics endpoint is scraped, **Then** only Schema Registry-specific metrics are returned

---

### Edge Cases

- What happens when metrics port conflicts with existing service port? Deployment should fail with clear error message about port conflict
- How does system handle malformed JMX exporter config? Container should fail to start with error logs indicating config parse failure
- What happens when javaagent jar is missing from image? Container should fail to start with FileNotFoundException in logs
- How does metrics collection affect Schema Registry performance under heavy load? JMX exporter overhead should be < 5% additional CPU usage
- What happens when Prometheus scraper is slower than metrics generation rate? Exporter should handle concurrent scrapes without blocking Schema Registry operations

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST include `io.prometheus.jmx:jmx_prometheus_javaagent` version 1.0.1 jar in the container image at `/opt/jmx-exporter/jmx_prometheus_javaagent.jar`
- **FR-002**: System MUST provide a default JMX exporter configuration file that exports Schema Registry-specific MBeans (jetty-metrics, master-slave-role, jersey-metrics)
- **FR-003**: Helm chart MUST provide `metrics.enabled` boolean flag (default: false) to control metrics collection
- **FR-004**: When `metrics.enabled=true`, container MUST start Schema Registry with `-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=<port>:<config>` argument
- **FR-005**: When `metrics.enabled=true`, metrics endpoint MUST be accessible at `http://<pod-ip>:<metrics.port>/metrics` returning Prometheus text format
- **FR-006**: When `metrics.enabled=false`, javaagent MUST NOT be loaded and metrics port MUST NOT be opened
- **FR-007**: Helm chart MUST expose metrics port on Service when `metrics.enabled=true`
- **FR-008**: Helm chart MUST support configurable metrics port via `metrics.port` (default: 9404)
- **FR-009**: Helm chart MUST support configurable metrics path via `metrics.path` (default: /metrics)
- **FR-010**: System MUST allow JMX exporter config to be customized via ConfigMap without rebuilding image
- **FR-011**: Helm chart MUST optionally add Prometheus scrape annotations when both `metrics.enabled` and `metrics.annotations.enabled` are true
- **FR-012**: Build process MUST download javaagent jar during Maven build using maven-dependency-plugin
- **FR-013**: Javaagent MUST run inside same JVM process as Schema Registry (no separate sidecar or remote JMX)

### Security & Portability Requirements

- **SPR-001**: Metrics endpoint MUST NOT require authentication (standard Prometheus scraping model)
- **SPR-002**: Javaagent jar MUST be fetched from Maven Central during build (not pre-bundled in repo)
- **SPR-003**: Container MUST continue to run as non-root user even with javaagent enabled
- **SPR-004**: JMX exporter config MUST be mounted via ConfigMap (not baked into image) to allow runtime customization
- **SPR-005**: Solution MUST NOT open remote JMX ports (RMI ports 7199, etc.) for security
- **SPR-006**: JAVA_TOOL_OPTIONS modification MUST NOT break existing environment variable handling
- **SPR-007**: Metrics collection MUST work on both linux/amd64 and linux/arm64 platforms

### Key Entities

- **JMX Exporter Agent**: Java agent (jar file) that runs in-process with Schema Registry, scrapes JMX MBeans, and exposes them as HTTP /metrics endpoint in Prometheus format
- **JMX Exporter Config**: YAML configuration file that defines which JMX MBeans to export, how to transform them to Prometheus metric names, and what labels to apply
- **Metrics Service Port**: Additional Kubernetes Service port (named "metrics") that exposes the metrics endpoint separately from the main API port
- **Prometheus Scrape Annotations**: Standard Kubernetes pod annotations (`prometheus.io/scrape`, `prometheus.io/port`, `prometheus.io/path`) that tell Prometheus where to scrape metrics

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Operators can enable metrics collection by setting a single Helm value (`metrics.enabled=true`) without any additional configuration
- **SC-002**: Metrics endpoint responds within 500ms under normal Schema Registry load (< 100 qps)
- **SC-003**: Metrics output includes at least 10 Schema Registry-specific metrics (jetty, jersey, master-slave role indicators)
- **SC-004**: JMX exporter overhead adds less than 5% additional CPU usage and less than 50MB additional memory consumption
- **SC-005**: 95% of Prometheus scrape attempts succeed without timeout (15 second scrape timeout)
- **SC-006**: Operators can deploy with metrics disabled and observe zero additional resource consumption compared to baseline
- **SC-007**: Custom JMX exporter configurations can be applied without container rebuild or pod restart (ConfigMap update requires pod restart per Kubernetes standard)
