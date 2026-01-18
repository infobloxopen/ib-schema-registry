# Data Model: Prometheus JMX Metrics Export

**Feature**: 007-jmx-prometheus-metrics  
**Date**: 2026-01-18

## Overview

This feature has minimal data model - metrics are ephemeral and exported via HTTP. The "data" consists of configuration structures and runtime state.

## Configuration Data Structures

### 1. Helm Values Schema

```yaml
# Type: HelmValues
metrics:
  # Type: boolean
  # Default: false
  # Description: Master switch to enable/disable all metrics functionality
  enabled: false
  
  # Type: integer
  # Range: 1024-65535
  # Default: 9404
  # Description: TCP port for metrics HTTP endpoint
  port: 9404
  
  # Type: string
  # Default: "/metrics"
  # Description: HTTP path for Prometheus scrape endpoint
  path: /metrics
  
  # Type: object
  annotations:
    # Type: boolean
    # Default: true
    # Description: Whether to add prometheus.io/* pod annotations
    enabled: true
  
  # Type: string (YAML content)
  # Optional: If not provided, uses default MBean config
  # Description: Custom JMX exporter configuration
  config: |
    lowercaseOutputName: true
    # ... custom rules
```

### 2. JMX Exporter Configuration Schema

```yaml
# Type: JMXExporterConfig
# Format: YAML
# Location: ConfigMap -> /opt/jmx-exporter/config.yaml

# Type: boolean
# Converts MBean property names to lowercase
lowercaseOutputName: true

# Type: boolean
# Converts metric label names to lowercase
lowercaseOutputLabelNames: true

# Type: array of strings
# JMX ObjectName patterns to export
whitelistObjectNames:
  - "kafka.schema.registry:type=jetty-metrics,*"
  - "kafka.schema.registry:type=jersey-metrics,*"
  - "kafka.schema.registry:type=master-slave-role,*"
  - "java.lang:type=Memory"
  - "java.lang:type=GarbageCollector,*"
  - "java.lang:type=Threading"

# Type: array of objects
# Pattern matching and transformation rules
rules:
  # Type: object
  - pattern: 'regex-pattern'          # Type: string (Java regex)
    name: 'prometheus_metric_name'    # Type: string
    labels:                           # Type: map<string, string>
      label_key: "$1"                 # Captured groups from pattern
```

## Runtime Data Structures

### 3. Environment Variables (Container)

```bash
# Type: string
# Only set when metrics.enabled=true
# Format: -javaagent:<jar-path>=<port>:<config-path>
JAVA_TOOL_OPTIONS="-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9404:/opt/jmx-exporter/config.yaml"
```

### 4. Kubernetes Service Ports

```yaml
# Type: ServicePort
- name: metrics                    # Type: string
  port: 9404                       # Type: integer (matches metrics.port)
  targetPort: metrics              # Type: string (named port reference)
  protocol: TCP                    # Type: string
```

### 5. Prometheus Annotations

```yaml
# Type: map<string, string>
# Added to Pod.metadata.annotations when metrics.annotations.enabled=true
annotations:
  prometheus.io/scrape: "true"                     # Type: string (boolean as string)
  prometheus.io/port: "9404"                       # Type: string (integer as string)
  prometheus.io/path: "/metrics"                   # Type: string
```

## Prometheus Metrics Output Schema

### 6. Exported Metric Format

```
# Type: PrometheusMetric
# Format: Prometheus text exposition format

# HELP metric_name Human-readable description
# TYPE metric_name gauge|counter|histogram|summary

kafka_schema_registry_jetty_requests_total{method="GET"} 1234.0 1737148800000
kafka_schema_registry_jetty_response_time_seconds{quantile="0.5"} 0.012
kafka_schema_registry_jersey_endpoint_calls_total{path="/subjects"} 5678.0
kafka_schema_registry_master_slave_role{role="master"} 1.0
jvm_memory_bytes_used{area="heap"} 268435456.0
```

**Metric Naming Convention**:
- Prefix: `kafka_schema_registry_*` for application metrics
- Prefix: `jvm_*` for Java Virtual Machine metrics
- Suffix: `_total` for counters
- Suffix: `_seconds` for durations
- Suffix: `_bytes` for sizes
- Labels: `{key="value"}` for dimensions

### 7. JMX MBean Source Data

```java
// Type: JMX ObjectName
// Schema Registry exposes these MBeans (read-only source)

ObjectName: kafka.schema.registry:type=jetty-metrics
Attributes:
  - requests-total            // Type: long
  - response-time-ms-mean     // Type: double
  - response-time-ms-p99      // Type: double
  - active-connections        // Type: int

ObjectName: kafka.schema.registry:type=jersey-metrics,path=/subjects
Attributes:
  - request-count             // Type: long
  - error-count               // Type: long
  - request-duration-ms-mean  // Type: double

ObjectName: kafka.schema.registry:type=master-slave-role
Attributes:
  - master-slave-role         // Type: string ("master"|"slave")
```

## File System Structure

### 8. Container Image Paths

```
# Type: FilePath
/opt/jmx-exporter/
  ├── jmx_prometheus_javaagent.jar    # Type: binary (Java JAR)
  │                                   # Size: ~700KB
  │                                   # Permissions: 644
  └── config.yaml                     # Type: text (YAML)
                                      # Size: ~2KB
                                      # Permissions: 644
                                      # Source: ConfigMap mount
```

## State Transitions

### 9. Metrics Enablement State Machine

```
┌─────────────────┐
│  Deployed       │
│ metrics.enabled │
│    = false      │
└────────┬────────┘
         │
         │ Helm upgrade with
         │ metrics.enabled=true
         ▼
┌─────────────────┐
│  Pod Restart    │
│ JAVA_TOOL_      │
│ OPTIONS set     │
└────────┬────────┘
         │
         │ JVM starts with
         │ javaagent
         ▼
┌─────────────────┐
│ Metrics Active  │
│ :9404/metrics   │
│ responding      │
└────────┬────────┘
         │
         │ Helm upgrade with
         │ metrics.enabled=false
         ▼
┌─────────────────┐
│  Pod Restart    │
│ JAVA_TOOL_      │
│ OPTIONS unset   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Deployed       │
│ metrics.enabled │
│    = false      │
└─────────────────┘
```

## Data Validation Rules

### 10. Validation Constraints

| Field | Constraint | Reason |
|---|---|---|
| `metrics.port` | Must be 1024-65535 | Non-privileged ports only |
| `metrics.port` | Must not equal main service port (8081) | Avoid port conflicts |
| `metrics.path` | Must start with `/` | HTTP path convention |
| `metrics.config` | Must be valid YAML | Parsed by JMX exporter |
| JMX pattern | Must be valid Java regex | Pattern matching requirement |
| Metric names | Must match `[a-zA-Z_:][a-zA-Z0-9_:]*` | Prometheus naming rules |
| Label names | Must match `[a-zA-Z_][a-zA-Z0-9_]*` | Prometheus naming rules |

## Size and Performance Estimates

| Data Element | Size | Update Frequency |
|---|---|---|
| ConfigMap (JMX config) | ~2KB | Static (deployment time) |
| Javaagent JAR | ~700KB | Static (image build time) |
| Single metric scrape response | ~50-100KB | Per scrape (default 30s) |
| JVM heap overhead | <50MB | Constant while metrics enabled |
| Network bandwidth | ~2-3 KB/s per pod | Continuous (Prometheus scraping) |

## Notes

- **No persistent storage**: All metrics are ephemeral, regenerated on each scrape
- **No database**: Prometheus stores time-series data, Schema Registry only exports current state
- **No authentication**: Standard Prometheus scraping model (network policy controls access)
- **No encryption**: Metrics endpoint is plain HTTP (TLS termination at ingress if needed)
