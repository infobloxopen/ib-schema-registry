# Contract: Metrics Endpoint HTTP API

**Protocol**: HTTP/1.1  
**Format**: Prometheus text exposition format  
**Consumer**: Prometheus server (or compatible scrapers)  
**Availability**: Only when `metrics.enabled=true`

## Endpoint Specification

```
GET http://<pod-ip>:<metrics.port><metrics.path>
```

**Default URL**: `http://<pod-ip>:9404/metrics`

## Request

### Method
`GET`

### Headers
- None required
- `Accept: text/plain` (optional, default response format)

### Authentication
None (open endpoint, access controlled via Kubernetes network policies)

### Query Parameters
None

## Response

### Success Response

**HTTP Status**: `200 OK`

**Headers**:
```
Content-Type: text/plain; version=0.0.4; charset=utf-8
```

**Body Format**: Prometheus text exposition format
```
# HELP <metric_name> <description>
# TYPE <metric_name> <type>
<metric_name>{<label>="<value>",...} <value> [<timestamp>]
```

**Example**:
```
# HELP kafka_schema_registry_jetty_requests_total Jetty HTTP server metric: requests-total
# TYPE kafka_schema_registry_jetty_requests_total gauge
kafka_schema_registry_jetty_requests_total 12345.0

# HELP kafka_schema_registry_jersey_request_count Jersey REST API metric: request-count
# TYPE kafka_schema_registry_jersey_request_count gauge
kafka_schema_registry_jersey_request_count{path="/subjects"} 5678.0
kafka_schema_registry_jersey_request_count{path="/config"} 123.0

# HELP jvm_memory_heapmemoryusage_used JVM memory metric
# TYPE jvm_memory_heapmemoryusage_used gauge
jvm_memory_heapmemoryusage_used 2.68435456E8
```

### Error Responses

#### Metrics Disabled

**HTTP Status**: Connection refused (port not listening)

**Condition**: `metrics.enabled=false` in Helm values

#### JMX Exporter Initialization Failure

**HTTP Status**: `503 Service Unavailable`

**Body**:
```
Error: JMX exporter not initialized
```

**Condition**: Javaagent failed to load or JMX connection failed

#### Malformed JMX Config

**HTTP Status**: `500 Internal Server Error`

**Body**:
```
Error: Invalid JMX exporter configuration
```

**Condition**: Custom `metrics.config` contains invalid YAML or patterns

## Metric Types

| Type | Description | Example |
|---|---|---|
| gauge | Instant value that can go up or down | Current memory usage, active connections |
| counter | Monotonically increasing value | Total requests, error count |
| histogram | Distribution of values in buckets | Request duration percentiles |
| summary | Similar to histogram, calculated on client side | Response time quantiles |

**Note**: Schema Registry metrics are primarily exposed as `gauge` type (current state snapshot).

## Metric Naming Convention

### Application Metrics
- Prefix: `kafka_schema_registry_`
- Component: `jetty_`, `jersey_`, `master_slave_`
- Metric: descriptive name
- Example: `kafka_schema_registry_jetty_requests_total`

### JVM Metrics
- Prefix: `jvm_`
- Component: `memory_`, `gc_`, `threads_`, `os_`
- Metric: descriptive name
- Example: `jvm_memory_heapmemoryusage_used`

## Label Conventions

| Label | Values | Usage |
|---|---|---|
| `path` | REST endpoint path | Distinguishes metrics by API endpoint (e.g., `/subjects`, `/config`) |
| `gc` | GC algorithm name | Distinguishes GC metrics (e.g., `G1 Young Generation`, `G1 Old Generation`) |
| `area` | `heap`, `nonheap` | Distinguishes memory areas |

## Performance Characteristics

- **Response time**: <500ms under normal load (<100 qps to Schema Registry)
- **Response size**: ~50-100KB (50-100 metrics)
- **Scrape interval**: Prometheus default is 30 seconds
- **CPU overhead**: <5% during scrape
- **Memory overhead**: <10MB for JMX exporter agent

## Security

- **No authentication**: Standard Prometheus model (network-level access control)
- **No encryption**: Plain HTTP (TLS termination at ingress if needed)
- **No sensitive data**: Metrics contain only operational telemetry (no user data, no secrets)
- **DoS protection**: Rate limiting should be applied at network layer (not enforced by exporter)

## Prometheus Scrape Configuration

### Pod Annotations (when `metrics.annotations.enabled=true`)

```yaml
annotations:
  prometheus.io/scrape: "true"
  prometheus.io/port: "9404"
  prometheus.io/path: "/metrics"
```

Prometheus auto-discovery interprets these as:
```yaml
scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
```

### Manual Prometheus Configuration

```yaml
scrape_configs:
  - job_name: 'schema-registry'
    kubernetes_sd_configs:
      - role: pod
        namespaces:
          names:
            - default
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app_kubernetes_io_name]
        action: keep
        regex: ib-schema-registry
      - source_labels: [__address__]
        action: replace
        target_label: __address__
        regex: ([^:]+)(?::\d+)?
        replacement: $1:9404
      - source_labels: []
        target_label: __metrics_path__
        replacement: /metrics
```

## Health Check

To verify metrics endpoint is responding:

```bash
# From within Kubernetes cluster
curl http://<pod-ip>:9404/metrics

# Using kubectl port-forward
kubectl port-forward <pod-name> 9404:9404
curl http://localhost:9404/metrics

# Expected response: 200 OK with Prometheus text format metrics
```

## Compatibility

- **Prometheus version**: Compatible with Prometheus 2.0+
- **Grafana**: Compatible with Grafana 7.0+ (Prometheus datasource)
- **Other scrapers**: Compatible with any scraper supporting Prometheus text format (VictoriaMetrics, Thanos, Cortex)

## References

- Prometheus exposition formats: https://prometheus.io/docs/instrumenting/exposition_formats/
- Prometheus text format: https://github.com/prometheus/docs/blob/main/content/docs/instrumenting/exposition_formats.md
- Kubernetes scrape annotations: https://prometheus.io/docs/prometheus/latest/configuration/configuration/#kubernetes_sd_config
