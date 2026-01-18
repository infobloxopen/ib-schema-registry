# Research: Prometheus JMX Metrics Export

**Feature**: 007-jmx-prometheus-metrics  
**Date**: 2026-01-18  
**Purpose**: Resolve technical unknowns and establish implementation patterns

## Research Questions

### 1. Maven dependency plugin configuration for javaagent jar

**Question**: How to configure maven-dependency-plugin to download jmx_prometheus_javaagent.jar to a specific path during build?

**Decision**: Use maven-dependency-plugin in `prepare-package` phase with `copy` goal

**Rationale**: 
- The `copy` goal allows specifying exact artifact coordinates and destination path
- `prepare-package` phase runs after compilation but before packaging, allowing jar to be included in final distribution
- Destination path `${project.build.directory}/jmx-exporter/` aligns with Docker COPY conventions

**Configuration**:
```xml
<plugin>
  <groupId>org.apache.maven.plugins</groupId>
  <artifactId>maven-dependency-plugin</artifactId>
  <version>3.6.1</version>
  <executions>
    <execution>
      <id>copy-jmx-exporter</id>
      <phase>prepare-package</phase>
      <goals>
        <goal>copy</goal>
      </goals>
      <configuration>
        <artifactItems>
          <artifactItem>
            <groupId>io.prometheus.jmx</groupId>
            <artifactId>jmx_prometheus_javaagent</artifactId>
            <version>1.0.1</version>
            <type>jar</type>
            <outputDirectory>${project.build.directory}/jmx-exporter</outputDirectory>
            <destFileName>jmx_prometheus_javaagent.jar</destFileName>
          </artifactItem>
        </artifactItems>
      </configuration>
    </execution>
  </executions>
</plugin>
```

**Alternatives considered**:
- Download during Docker build: Rejected due to slower builds and Maven Central authentication complexity in container
- Bundle jar in repository: Rejected per constitution (supply-chain security - fetch from trusted source)

---

### 2. JMX exporter config format for Schema Registry MBeans

**Question**: What JMX MBean patterns should be exported for Schema Registry monitoring?

**Decision**: Export three categories of MBeans with pattern matching

**Rationale**:
- Schema Registry exposes MBeans under `kafka.schema.registry:` domain
- jetty-metrics: HTTP request/response metrics (throughput, latency)
- jersey-metrics: REST API endpoint-specific metrics
- master-slave-role: Cluster role status for HA deployments

**Configuration**:
```yaml
lowercaseOutputName: true
lowercaseOutputLabelNames: true
whitelistObjectNames:
  - "kafka.schema.registry:type=jetty-metrics,*"
  - "kafka.schema.registry:type=jersey-metrics,*"
  - "kafka.schema.registry:type=master-slave-role,*"
  - "java.lang:type=Memory"
  - "java.lang:type=GarbageCollector,*"
  - "java.lang:type=Threading"
rules:
  - pattern: 'kafka.schema.registry<type=jetty-metrics><>(.+):'
    name: kafka_schema_registry_jetty_$1
  - pattern: 'kafka.schema.registry<type=jersey-metrics, path=(.+)><>(.+):'
    name: kafka_schema_registry_jersey_$2
    labels:
      path: "$1"
  - pattern: 'kafka.schema.registry<type=master-slave-role><>(.+):'
    name: kafka_schema_registry_master_slave_$1
```

**Alternatives considered**:
- Export all MBeans (`*:*`): Rejected due to metric explosion (thousands of JVM internals)
- Minimal Schema Registry only: Considered but added JVM memory/GC for basic health monitoring

---

### 3. JAVA_TOOL_OPTIONS environment variable handling

**Question**: How to inject javaagent argument via environment variable without breaking existing configuration?

**Decision**: Conditionally set JAVA_TOOL_OPTIONS in Helm deployment template when `metrics.enabled=true`

**Rationale**:
- JAVA_TOOL_OPTIONS is universally supported by all JVMs (not vendor-specific like JAVA_OPTS)
- Environment variable approach avoids modifying entrypoint scripts or CMD instructions
- Helm templating allows clean enable/disable without complex shell logic

**Implementation**:
```yaml
{{- if .Values.metrics.enabled }}
- name: JAVA_TOOL_OPTIONS
  value: "-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar={{ .Values.metrics.port }}:/opt/jmx-exporter/config.yaml"
{{- end }}
```

**Alternatives considered**:
- Modify existing SCHEMA_REGISTRY_OPTS: Rejected because this var may not exist in all base image variants
- Shell wrapper script: Rejected per distroless compatibility requirement (no shell)
- Java system property: Rejected because javaagent MUST be specified before -jar argument

**Conflict handling**: If user has existing JAVA_TOOL_OPTIONS in values.yaml, document that metrics.enabled will override. Consider future enhancement to append rather than replace.

---

### 4. Dockerfile integration path

**Question**: Where in multi-stage Dockerfile should javaagent jar be copied?

**Decision**: Copy jar from Maven build stage target directory to `/opt/jmx-exporter/` in runtime image

**Rationale**:
- Matches existing pattern of copying Schema Registry artifacts from builder to runtime
- `/opt/jmx-exporter/` is standard location (not under `/opt/schema-registry/` to keep concerns separated)
- Single COPY instruction adds one layer (minimal size impact: ~700KB for javaagent jar)

**Dockerfile addition**:
```dockerfile
# In final runtime stage
COPY --from=builder /workspace/package-schema-registry/target/jmx-exporter/ /opt/jmx-exporter/
```

**Alternatives considered**:
- Bundle in `/opt/schema-registry/lib/`: Rejected to avoid confusion with Schema Registry dependencies
- Download in runtime image: Rejected due to slower startup and network dependency

---

### 5. Helm chart values structure

**Question**: What is the optimal Helm values structure for metrics configuration?

**Decision**: Nested `metrics` section with sensible defaults

**Rationale**:
- Groups all metrics-related config under single namespace
- `enabled: false` ensures backwards compatibility (opt-in)
- `annotations.enabled` separates concern of pod annotations from metrics enablement

**values.yaml addition**:
```yaml
metrics:
  # Enable Prometheus metrics export via JMX exporter
  enabled: false
  
  # Port for metrics HTTP endpoint
  port: 9404
  
  # Path for metrics endpoint
  path: /metrics
  
  # Prometheus scrape annotations
  annotations:
    enabled: true
  
  # Custom JMX exporter configuration (optional)
  # If not provided, uses default config that exports Schema Registry MBeans
  config: |
    # lowercaseOutputName: true
    # ... (users can override entire config)
```

**Alternatives considered**:
- Top-level `enableMetrics`: Rejected because it doesn't scale for future metrics configuration options
- Separate `metricsPort` at top level: Rejected for same grouping reason

---

### 6. Testing strategy

**Question**: How to validate metrics functionality in CI without full Prometheus deployment?

**Decision**: Three-tier testing approach

**Tier 1 - Smoke test** (fast, always run):
```bash
# In tests/smoke.sh
if [ "$METRICS_ENABLED" = "true" ]; then
  echo "→ Testing metrics endpoint..."
  METRICS_RESPONSE=$(docker exec "$CONTAINER_NAME" curl -s -o /dev/null -w "%{http_code}" http://localhost:9404/metrics)
  if [ "$METRICS_RESPONSE" = "200" ]; then
    echo "✓ Metrics endpoint responding"
  else
    echo "✗ Metrics endpoint failed: HTTP $METRICS_RESPONSE"
    exit 1
  fi
fi
```

**Tier 2 - E2E Helm test** (medium, run in CI):
- Deploy with `metrics.enabled=false` → verify port not exposed
- Deploy with `metrics.enabled=true` → verify `/metrics` returns Prometheus format
- Validate metric content includes `kafka_schema_registry_` prefix

**Tier 3 - Integration test** (optional, not blocking):
- Full Prometheus deployment scraping Schema Registry
- Validate metrics appear in Prometheus UI
- Documented in `docs/metrics-integration.md` but not required for merge

**Rationale**: Balanced coverage without requiring full monitoring stack in CI

---

## Summary of Decisions

| Decision Area | Choice | Rationale |
|---|---|---|
| Jar delivery | Maven dependency plugin | Leverages existing build system, trusted source |
| MBean patterns | jetty, jersey, master-slave + JVM basics | Coverage of key Schema Registry metrics without explosion |
| Javaagent injection | JAVA_TOOL_OPTIONS env var | Universal, distroless-compatible, no entrypoint changes |
| Docker path | /opt/jmx-exporter/ | Separation of concerns, standard location |
| Helm structure | Nested `metrics.*` values | Grouping, extensibility, backwards compatibility |
| Testing | Three-tier (smoke/E2E/integration) | Fast feedback, comprehensive coverage, optional deep testing |

## Implementation Notes

- **Backward compatibility**: All changes are opt-in via `metrics.enabled=false` default
- **Multi-arch**: Javaagent is pure Java bytecode, no platform-specific concerns
- **Licensing**: Document Apache 2.0 license for jmx_prometheus_javaagent in README
- **Documentation**: Update README with metrics section, Helm chart README with configuration examples
