# Quick Start Guide: Deploy Schema Registry with Helm

**Feature**: 003-helm-chart | **Audience**: Platform Operators | **Time**: 10 minutes

## Prerequisites

Before deploying Schema Registry, ensure you have:

- **Kubernetes cluster** (1.24+)
  - Local: k3d, minikube, Docker Desktop
  - Cloud: GKE, EKS, AKS, etc.
- **Helm** (3.8+): `helm version`
- **kubectl** (1.24+): `kubectl version`
- **Kafka cluster** (or Kafka-compatible like Redpanda) accessible from Kubernetes

---

## Quick Deploy (30 seconds)

### 1. Create namespace (optional)

```bash
kubectl create namespace schema-registry
```

### 2. Deploy with minimal configuration

```bash
helm install my-registry ./chart \
  --namespace schema-registry \
  --set config.kafkaBootstrapServers=kafka:9092
```

### 3. Verify deployment

```bash
# Check pods
kubectl get pods -n schema-registry

# Wait for ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=schema-registry -n schema-registry --timeout=120s

# Test API
kubectl port-forward -n schema-registry svc/my-registry-schema-registry 8081:8081 &
curl http://localhost:8081/subjects
# Expected: []
```

---

## Development Setup (with k3d + Redpanda)

For local testing without an existing Kafka cluster:

### 1. Create k3d cluster

```bash
k3d cluster create test-cluster --agents 2
```

### 2. Deploy Redpanda (Kafka-compatible)

```bash
# Create Redpanda deployment
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: redpanda
spec:
  ports:
    - port: 9092
      name: kafka
  selector:
    app: redpanda
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redpanda
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redpanda
  template:
    metadata:
      labels:
        app: redpanda
    spec:
      containers:
        - name: redpanda
          image: vectorized/redpanda:v23.3.1
          args:
            - redpanda
            - start
            - --smp
            - "1"
            - --memory
            - "512M"
            - --overprovisioned
            - --node-id
            - "0"
            - --check=false
            - --kafka-addr
            - PLAINTEXT://0.0.0.0:9092
            - --advertise-kafka-addr
            - PLAINTEXT://redpanda:9092
          ports:
            - containerPort: 9092
              name: kafka
          resources:
            requests:
              memory: 512Mi
              cpu: 250m
            limits:
              memory: 1Gi
              cpu: 1000m
EOF

# Wait for Redpanda ready
kubectl wait --for=condition=ready pod -l app=redpanda --timeout=120s
```

### 3. Deploy Schema Registry

```bash
helm install sr ./chart --set config.kafkaBootstrapServers=redpanda:9092
```

### 4. Test end-to-end

```bash
# Port-forward to access locally
kubectl port-forward svc/sr-schema-registry 8081:8081 &

# List subjects (should be empty)
curl http://localhost:8081/subjects
# Expected: []

# Register a schema
curl -X POST \
  -H "Content-Type: application/vnd.schemaregistry.v1+json" \
  --data '{"schema": "{\"type\": \"record\", \"name\": \"User\", \"fields\": [{\"name\": \"name\", \"type\": \"string\"}]}"}' \
  http://localhost:8081/subjects/users-value/versions

# Expected: {"id":1}

# Retrieve schema
curl http://localhost:8081/subjects/users-value/versions/1
# Expected: Full schema JSON

# List subjects again
curl http://localhost:8081/subjects
# Expected: ["users-value"]
```

### 5. Cleanup

```bash
helm uninstall sr
kubectl delete deployment redpanda
kubectl delete service redpanda
k3d cluster delete test-cluster
```

---

## Production Deployment (High Availability)

### 1. Create production values file

```bash
cat > values-production.yaml <<EOF
replicaCount: 3

image:
  repository: ghcr.io/infobloxopen/ib-schema-registry
  tag: "8.1.1"
  pullPolicy: IfNotPresent

config:
  kafkaBootstrapServers: "kafka-0.kafka:9092,kafka-1.kafka:9092,kafka-2.kafka:9092"
  extraProperties:
    schema.compatibility.level: "BACKWARD"

resources:
  requests:
    memory: 1Gi
    cpu: 500m
  limits:
    memory: 2Gi
    cpu: 2000m

podDisruptionBudget:
  enabled: true

topologySpreadConstraints:
  enabled: true
  maxSkew: 1

service:
  type: ClusterIP
  port: 8081
  annotations:
    prometheus.io/scrape: "true"
    prometheus.io/port: "8081"

securityContext:
  runAsNonRoot: true
  runAsUser: 65532
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
EOF
```

### 2. Deploy with production values

```bash
helm install schema-registry ./chart \
  --namespace kafka-infrastructure \
  --create-namespace \
  --values values-production.yaml
```

### 3. Verify HA configuration

```bash
# Check pod distribution across zones
kubectl get pods -n kafka-infrastructure -l app.kubernetes.io/name=schema-registry -o wide

# Verify PodDisruptionBudget
kubectl get pdb -n kafka-infrastructure

# Check resources
kubectl top pods -n kafka-infrastructure -l app.kubernetes.io/name=schema-registry
```

### 4. Test rolling update

```bash
# Update configuration
helm upgrade schema-registry ./chart \
  --namespace kafka-infrastructure \
  --reuse-values \
  --set config.extraProperties.schema\\.compatibility\\.level=FORWARD

# Watch rolling update
kubectl rollout status deployment/schema-registry -n kafka-infrastructure

# Verify new configuration applied
kubectl exec -n kafka-infrastructure deployment/schema-registry -- \
  env | grep SCHEMA_REGISTRY
```

---

## Common Configuration Scenarios

### Custom Image Repository

```bash
helm install sr ./chart \
  --set image.repository=myregistry.io/schema-registry \
  --set image.tag=custom-v1 \
  --set config.kafkaBootstrapServers=kafka:9092
```

### Private Registry with Pull Secrets

```bash
# Create pull secret
kubectl create secret docker-registry ghcr-creds \
  --docker-server=ghcr.io \
  --docker-username=myuser \
  --docker-password=mytoken

# Deploy with pull secrets
helm install sr ./chart \
  --set imagePullSecrets[0].name=ghcr-creds \
  --set config.kafkaBootstrapServers=kafka:9092
```

### TLS/SASL for Kafka Connection

```bash
helm install sr ./chart \
  --set config.kafkaBootstrapServers=kafka:9093 \
  --set config.extraProperties.kafkastore\\.security\\.protocol=SASL_SSL \
  --set config.extraProperties.kafkastore\\.sasl\\.mechanism=PLAIN \
  --set-string config.extraProperties.kafkastore\\.sasl\\.jaas\\.config='org.apache.kafka.common.security.plain.PlainLoginModule required username="user" password="pass";'
```

### Custom Resource Limits

```bash
helm install sr ./chart \
  --set resources.requests.memory=2Gi \
  --set resources.requests.cpu=1000m \
  --set resources.limits.memory=4Gi \
  --set resources.limits.cpu=3000m \
  --set jvm.maxRAMPercentage=75.0 \
  --set config.kafkaBootstrapServers=kafka:9092
```

---

## Upgrading Schema Registry

### Upgrade to new chart version

```bash
# Pull latest chart
git pull origin main

# Upgrade release (preserves existing values)
helm upgrade schema-registry ./chart \
  --namespace kafka-infrastructure \
  --reuse-values
```

### Upgrade to new Schema Registry version

```bash
# Update container image version
helm upgrade schema-registry ./chart \
  --namespace kafka-infrastructure \
  --reuse-values \
  --set image.tag=8.2.0

# Monitor rolling update
kubectl rollout status deployment/schema-registry -n kafka-infrastructure
```

---

## Troubleshooting

### Pods not starting

```bash
# Check pod status
kubectl get pods -n schema-registry -l app.kubernetes.io/name=schema-registry

# View logs
kubectl logs -n schema-registry -l app.kubernetes.io/name=schema-registry --tail=50

# Describe pod for events
kubectl describe pod -n schema-registry <pod-name>

# Common issues:
# - Kafka connection failed: Check config.kafkaBootstrapServers value
# - Image pull errors: Verify image.repository and imagePullSecrets
# - Resource limits: Check if cluster has sufficient CPU/memory
```

### API not responding

```bash
# Check service
kubectl get svc -n schema-registry

# Test from inside cluster
kubectl run -n schema-registry debug --image=curlimages/curl --rm -it --restart=Never -- \
  curl -v http://schema-registry:8081/subjects

# Check readiness probe
kubectl get pods -n schema-registry -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")]}'
```

### Configuration not applying

```bash
# Verify ConfigMap content
kubectl get configmap -n schema-registry <release-name>-schema-registry -o yaml

# Check ConfigMap checksum annotation on pods
kubectl get pods -n schema-registry -o jsonpath='{.items[0].metadata.annotations.checksum/config}'

# Force rolling update
kubectl rollout restart deployment/schema-registry -n schema-registry
```

### PodDisruptionBudget blocking upgrades

```bash
# Check PDB status
kubectl get pdb -n schema-registry

# Temporarily disable PDB (not recommended for production)
kubectl delete pdb <release-name>-schema-registry -n schema-registry

# Re-enable after maintenance
helm upgrade schema-registry ./chart --reuse-values
```

---

## Uninstalling

```bash
# Remove Helm release (deletes all resources)
helm uninstall schema-registry --namespace kafka-infrastructure

# Verify cleanup
kubectl get all -n kafka-infrastructure -l app.kubernetes.io/name=schema-registry

# Delete namespace (if dedicated)
kubectl delete namespace kafka-infrastructure
```

---

## Next Steps

- **Monitoring**: Integrate with Prometheus/Grafana for metrics
- **Alerting**: Set up alerts for pod crashes, API errors, Kafka connection failures
- **Backup**: Document Schema Registry state backup (stored in Kafka topics)
- **Ingress**: Configure Ingress controller for external access (if needed)
- **Security**: Enable TLS, authentication, authorization as required
- **Scaling**: Use HorizontalPodAutoscaler for automatic scaling (optional)

---

## Resources

- **Helm Chart Repository**: https://github.com/infobloxopen/ib-schema-registry
- **Schema Registry Documentation**: https://docs.confluent.io/platform/current/schema-registry/
- **Kubernetes Best Practices**: https://kubernetes.io/docs/concepts/configuration/overview/
- **Helm Documentation**: https://helm.sh/docs/

**Questions?** Open an issue in the GitHub repository.
