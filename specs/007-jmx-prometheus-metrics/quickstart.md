# Quickstart: Implementing JMX Prometheus Metrics

**Feature**: 007-jmx-prometheus-metrics  
**Target**: Schema Registry 8.1.1  
**Estimated Implementation Time**: 6-8 hours

## Overview

This guide provides a streamlined implementation checklist for adding Prometheus JMX metrics export to the Schema Registry container image and Helm chart.

## Prerequisites

- Schema Registry 8.1.1 source code in `upstream/schema-registry/`
- Maven 3.6+, Java 17
- Helm 3.8+
- Docker or compatible container runtime
- Kubernetes cluster for testing (k3d recommended)

## Implementation Checklist

### Phase 1: Maven Dependency (1 hour)

**File**: `upstream/schema-registry/pom.xml`

1. [ ] Add maven-dependency-plugin to `<build><plugins>` section
2. [ ] Configure to fetch `io.prometheus.jmx:jmx_prometheus_javaagent:1.0.1`
3. [ ] Set execution phase to `prepare-package`
4. [ ] Set output directory to `target/jmx-exporter/`

**Validation**:
```bash
cd upstream/schema-registry
mvn clean prepare-package
ls -lh target/jmx-exporter/jmx_prometheus_javaagent-1.0.1.jar
# Expected: ~700KB jar file
```

**Reference**: [research.md](research.md#decision-1-maven-dependency-plugin-configuration)

### Phase 2: Dockerfile Modification (1 hour)

**File**: `Dockerfile`

1. [ ] Add COPY instruction after schema-registry jar installation
2. [ ] Create `/opt/jmx-exporter/` directory in container
3. [ ] Copy jar to `/opt/jmx-exporter/jmx_prometheus_javaagent.jar`
4. [ ] Set appropriate permissions (644)

**Example**:
```dockerfile
COPY upstream/schema-registry/target/jmx-exporter/*.jar /opt/jmx-exporter/jmx_prometheus_javaagent.jar
RUN chmod 644 /opt/jmx-exporter/jmx_prometheus_javaagent.jar
```

**Validation**:
```bash
make build-docker
docker run --rm <image> ls -lh /opt/jmx-exporter/
# Expected: jmx_prometheus_javaagent.jar present
```

**Reference**: [research.md](research.md#decision-4-dockerfile-integration-path)

### Phase 3: Helm Values Configuration (30 minutes)

**File**: `helm/ib-schema-registry/values.yaml`

1. [ ] Add `metrics:` section at root level
2. [ ] Set `enabled: false` (opt-in default)
3. [ ] Set `port: 9404`
4. [ ] Set `path: /metrics`
5. [ ] Add `annotations:` subsection with `enabled: true`
6. [ ] Add `config: null` for custom JMX configuration

**Example**:
```yaml
metrics:
  enabled: false
  port: 9404
  path: /metrics
  annotations:
    enabled: true
  config: null
```

**Reference**: [contracts/helm-values.yaml](contracts/helm-values.yaml)

### Phase 4: JMX Exporter Default Configuration (30 minutes)

**File**: `helm/ib-schema-registry/templates/metrics-config.yaml` (new file)

1. [ ] Create ConfigMap template (conditional on `metrics.enabled`)
2. [ ] Add default JMX exporter config from contract
3. [ ] Support `metrics.config` override if provided
4. [ ] Include lowercaseOutputName and lowercaseOutputLabelNames settings

**Template Structure**:
```yaml
{{- if .Values.metrics.enabled }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "ib-schema-registry.fullname" . }}-metrics-config
data:
  jmx-exporter-config.yaml: |
    {{- if .Values.metrics.config }}
    {{ .Values.metrics.config | nindent 4 }}
    {{- else }}
    # Default config from contracts/jmx-exporter-config.yaml
    {{- end }}
{{- end }}
```

**Reference**: [contracts/jmx-exporter-config.yaml](contracts/jmx-exporter-config.yaml)

### Phase 5: Deployment Template Modification (1.5 hours)

**File**: `helm/ib-schema-registry/templates/deployment.yaml`

#### 5.1 Environment Variables

1. [ ] Add conditional `JAVA_TOOL_OPTIONS` environment variable
2. [ ] Only add when `metrics.enabled=true`
3. [ ] Set value to `-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=<port>:/etc/schema-registry/jmx-exporter-config.yaml`

**Example**:
```yaml
env:
  {{- if .Values.metrics.enabled }}
  - name: JAVA_TOOL_OPTIONS
    value: "-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar={{ .Values.metrics.port }}:/etc/schema-registry/jmx-exporter-config.yaml"
  {{- end }}
```

#### 5.2 Volume Mounts

1. [ ] Add ConfigMap volume mount (conditional on `metrics.enabled`)
2. [ ] Mount path: `/etc/schema-registry/jmx-exporter-config.yaml`
3. [ ] SubPath: `jmx-exporter-config.yaml`
4. [ ] ReadOnly: true

**Example**:
```yaml
volumeMounts:
  {{- if .Values.metrics.enabled }}
  - name: metrics-config
    mountPath: /etc/schema-registry/jmx-exporter-config.yaml
    subPath: jmx-exporter-config.yaml
    readOnly: true
  {{- end }}
```

#### 5.3 Volumes

1. [ ] Add ConfigMap volume (conditional on `metrics.enabled`)
2. [ ] Reference metrics-config ConfigMap

**Example**:
```yaml
volumes:
  {{- if .Values.metrics.enabled }}
  - name: metrics-config
    configMap:
      name: {{ include "ib-schema-registry.fullname" . }}-metrics-config
  {{- end }}
```

#### 5.4 Pod Annotations

1. [ ] Add Prometheus scrape annotations (conditional on `metrics.enabled` and `metrics.annotations.enabled`)
2. [ ] Set `prometheus.io/scrape: "true"`
3. [ ] Set `prometheus.io/port: "{{ .Values.metrics.port }}"`
4. [ ] Set `prometheus.io/path: "{{ .Values.metrics.path }}"`

**Example**:
```yaml
metadata:
  annotations:
    {{- if and .Values.metrics.enabled .Values.metrics.annotations.enabled }}
    prometheus.io/scrape: "true"
    prometheus.io/port: "{{ .Values.metrics.port }}"
    prometheus.io/path: "{{ .Values.metrics.path }}"
    {{- end }}
```

**Reference**: [data-model.md](data-model.md#prometheus-pod-annotations)

### Phase 6: Service Template Modification (30 minutes)

**File**: `helm/ib-schema-registry/templates/service.yaml`

1. [ ] Add metrics port (conditional on `metrics.enabled`)
2. [ ] Name: `metrics`
3. [ ] Protocol: `TCP`
4. [ ] Port: `{{ .Values.metrics.port }}`
5. [ ] TargetPort: `{{ .Values.metrics.port }}`

**Example**:
```yaml
spec:
  ports:
    - name: schema-registry
      port: 8081
      targetPort: 8081
      protocol: TCP
    {{- if .Values.metrics.enabled }}
    - name: metrics
      port: {{ .Values.metrics.port }}
      targetPort: {{ .Values.metrics.port }}
      protocol: TCP
    {{- end }}
```

**Reference**: [data-model.md](data-model.md#kubernetes-service-ports)

### Phase 7: Testing (2 hours)

#### 7.1 Smoke Test (local)

1. [ ] Build Docker image with changes
2. [ ] Run container with metrics enabled
3. [ ] Verify javaagent loads without errors
4. [ ] Curl metrics endpoint

**Commands**:
```bash
# Build image
make build-docker

# Run with metrics enabled
docker run -d --name test-sr \
  -e JAVA_TOOL_OPTIONS="-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9404:/opt/jmx-exporter/default-config.yaml" \
  -p 8081:8081 -p 9404:9404 \
  <image>

# Wait for startup (30 seconds)
sleep 30

# Test Schema Registry API
curl http://localhost:8081/

# Test metrics endpoint
curl http://localhost:9404/metrics | grep kafka_schema_registry

# Expected: Metrics in Prometheus format
# Look for: kafka_schema_registry_jetty_*, kafka_schema_registry_jersey_*, jvm_*

# Cleanup
docker stop test-sr && docker rm test-sr
```

#### 7.2 E2E Test (Kubernetes)

1. [ ] Deploy Helm chart with `metrics.enabled=false` (default)
2. [ ] Verify Schema Registry works without metrics port
3. [ ] Upgrade deployment with `metrics.enabled=true`
4. [ ] Verify metrics endpoint responds

**Commands**:
```bash
# Setup k3d cluster
bash tests/e2e/setup-k3d-cluster.sh

# Deploy without metrics
helm install test-sr ./helm/ib-schema-registry \
  --set image.repository=<image> \
  --set image.tag=<tag> \
  --set metrics.enabled=false

# Wait for ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=ib-schema-registry --timeout=120s

# Test Schema Registry API
kubectl port-forward svc/test-sr-ib-schema-registry 8081:8081 &
curl http://localhost:8081/subjects

# Verify no metrics port
kubectl get svc test-sr-ib-schema-registry -o yaml | grep -A5 ports
# Expected: Only port 8081

# Upgrade with metrics enabled
helm upgrade test-sr ./helm/ib-schema-registry \
  --set image.repository=<image> \
  --set image.tag=<tag> \
  --set metrics.enabled=true \
  --reuse-values

# Wait for rollout
kubectl rollout status deployment/test-sr-ib-schema-registry

# Verify metrics port exists
kubectl get svc test-sr-ib-schema-registry -o yaml | grep -A10 ports
# Expected: Ports 8081 and 9404

# Test metrics endpoint
POD_NAME=$(kubectl get pods -l app.kubernetes.io/name=ib-schema-registry -o name | head -n1)
kubectl exec $POD_NAME -- curl -s http://localhost:9404/metrics | head -n50

# Verify Prometheus annotations
kubectl get pod -l app.kubernetes.io/name=ib-schema-registry -o yaml | grep -A5 "prometheus.io"
# Expected: scrape=true, port=9404, path=/metrics

# Cleanup
helm uninstall test-sr
bash tests/e2e/teardown.sh
```

#### 7.3 Integration Test (with Prometheus)

1. [ ] Deploy Prometheus in test cluster
2. [ ] Configure service discovery for Schema Registry
3. [ ] Verify metrics appear in Prometheus UI
4. [ ] Query key metrics (jetty requests, jersey requests, master-slave role)

**Prometheus Configuration**:
```yaml
# prometheus-values.yaml
server:
  extraScrapeConfigs: |
    - job_name: 'schema-registry'
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
```

**Commands**:
```bash
# Install Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/prometheus -f prometheus-values.yaml

# Wait for Prometheus ready
kubectl wait --for=condition=ready pod -l app=prometheus --timeout=180s

# Port-forward Prometheus UI
kubectl port-forward svc/prometheus-server 9090:80 &

# Open browser to http://localhost:9090
# Query: kafka_schema_registry_jetty_requests_total
# Query: kafka_schema_registry_master_slave_role
# Expected: Data points with values

# Cleanup
helm uninstall prometheus
```

### Phase 8: Documentation (1 hour)

#### 8.1 Helm Chart README

**File**: `helm/ib-schema-registry/README.md`

1. [ ] Add `metrics.*` values table
2. [ ] Add usage examples (enable/disable, custom config, custom port)
3. [ ] Add Prometheus integration section

#### 8.2 Main README

**File**: `README.md`

1. [ ] Add "Monitoring" section
2. [ ] Describe metrics feature
3. [ ] Link to Helm chart README for configuration
4. [ ] Provide example Prometheus queries

**Example Section**:
```markdown
## Monitoring

The Schema Registry container includes optional Prometheus metrics export via JMX Exporter.

To enable metrics in Helm deployment:

```yaml
metrics:
  enabled: true
  port: 9404
```

Metrics endpoint: `http://<pod-ip>:9404/metrics`

Key metrics:
- `kafka_schema_registry_jetty_requests_total`: HTTP requests to Schema Registry
- `kafka_schema_registry_jersey_request_count`: REST API requests by endpoint
- `kafka_schema_registry_master_slave_role`: Master/slave role indicator
- `jvm_memory_*`: JVM memory usage

See [Helm chart README](helm/ib-schema-registry/README.md#metrics) for full configuration options.
```

## Quick Commands Reference

```bash
# Build with metrics support
mvn -f upstream/schema-registry/pom.xml clean package
make build-docker

# Test locally
docker run -d --name sr-test \
  -e JAVA_TOOL_OPTIONS="-javaagent:/opt/jmx-exporter/jmx_prometheus_javaagent.jar=9404:/etc/schema-registry/jmx-exporter-config.yaml" \
  -p 9404:9404 <image>
curl http://localhost:9404/metrics

# Deploy with Helm (metrics enabled)
helm install sr ./helm/ib-schema-registry --set metrics.enabled=true

# Port-forward and test
kubectl port-forward svc/sr-ib-schema-registry 9404:9404
curl http://localhost:9404/metrics | grep kafka_schema_registry

# View logs for javaagent initialization
kubectl logs -l app.kubernetes.io/name=ib-schema-registry | grep -i "jmx\|prometheus"
```

## Troubleshooting

### Metrics endpoint returns connection refused

**Cause**: `metrics.enabled=false` or pod not running  
**Solution**: 
```bash
helm upgrade sr ./helm/ib-schema-registry --set metrics.enabled=true --reuse-values
kubectl get pods -l app.kubernetes.io/name=ib-schema-registry
```

### Metrics endpoint returns 404

**Cause**: Wrong port or path  
**Solution**: Verify service configuration
```bash
kubectl get svc sr-ib-schema-registry -o yaml | grep -A10 ports
# Verify metrics port matches metrics.port value
```

### No metrics in Prometheus

**Cause**: Annotations missing or incorrect  
**Solution**: Check pod annotations
```bash
kubectl get pods -l app.kubernetes.io/name=ib-schema-registry -o yaml | grep -A5 "prometheus.io"
# Expected: prometheus.io/scrape="true", prometheus.io/port="9404", prometheus.io/path="/metrics"
```

### Javaagent fails to load

**Cause**: Jar file missing or wrong path  
**Solution**: Verify jar exists in container
```bash
kubectl exec <pod-name> -- ls -lh /opt/jmx-exporter/
# Expected: jmx_prometheus_javaagent.jar (~700KB)
```

### ConfigMap not mounted

**Cause**: metrics.enabled=false or template error  
**Solution**: Check ConfigMap exists and volume mount
```bash
kubectl get configmap sr-ib-schema-registry-metrics-config
kubectl get pod <pod-name> -o yaml | grep -A10 volumeMounts
# Expected: /etc/schema-registry/jmx-exporter-config.yaml mounted
```

## Success Criteria Validation

After implementation, verify all success criteria from [spec.md](spec.md):

1. [ ] Maven build downloads javaagent jar → Check `target/jmx-exporter/` after build
2. [ ] Docker image contains jar at `/opt/jmx-exporter/` → `docker run --rm <image> ls -lh /opt/jmx-exporter/`
3. [ ] Helm default `metrics.enabled=false` → Check `values.yaml`
4. [ ] Helm with `metrics.enabled=true` exposes port 9404 → `kubectl get svc <name> -o yaml`
5. [ ] Prometheus annotations added when enabled → `kubectl get pod <name> -o yaml | grep prometheus.io`
6. [ ] Metrics endpoint returns Prometheus format → `curl http://<pod-ip>:9404/metrics`
7. [ ] No impact when `metrics.enabled=false` → E2E test comparison

## References

- [Feature Specification](spec.md)
- [Implementation Plan](plan.md)
- [Research Decisions](research.md)
- [Data Model](data-model.md)
- [Helm Values Contract](contracts/helm-values.yaml)
- [JMX Exporter Config Contract](contracts/jmx-exporter-config.yaml)
- [Metrics Endpoint Contract](contracts/metrics-endpoint.md)
