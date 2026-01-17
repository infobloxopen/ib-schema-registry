#!/usr/bin/env bash
# Deploy Redpanda (Kafka-compatible backend) for Schema Registry testing
set -euo pipefail

NAMESPACE="${NAMESPACE:-default}"
REDPANDA_IMAGE="docker.redpanda.com/redpandadata/redpanda:v23.3.3"

echo "→ Deploying Redpanda to namespace: $NAMESPACE..."

# Create Redpanda Deployment
cat <<EOF | kubectl apply -f -
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redpanda
  namespace: $NAMESPACE
  labels:
    app: redpanda
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
        image: $REDPANDA_IMAGE
        command:
        - /usr/bin/rpk
        - redpanda
        - start
        - --smp=1
        - --memory=768M
        - --reserve-memory=0M
        - --overprovisioned
        - --node-id=0
        - --kafka-addr=PLAINTEXT://0.0.0.0:9092
        - --advertise-kafka-addr=PLAINTEXT://redpanda.$NAMESPACE.svc.cluster.local:9092
        ports:
        - name: kafka
          containerPort: 9092
          protocol: TCP
        - name: admin
          containerPort: 9644
          protocol: TCP
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 1Gi
            cpu: 1000m
        livenessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 30
          periodSeconds: 10
          failureThreshold: 6
        readinessProbe:
          tcpSocket:
            port: 9092
          initialDelaySeconds: 20
          periodSeconds: 5
          failureThreshold: 12
---
apiVersion: v1
kind: Service
metadata:
  name: redpanda
  namespace: $NAMESPACE
  labels:
    app: redpanda
spec:
  type: ClusterIP
  ports:
  - name: kafka
    port: 9092
    targetPort: kafka
    protocol: TCP
  - name: admin
    port: 9644
    targetPort: admin
    protocol: TCP
  selector:
    app: redpanda
EOF

echo "→ Waiting for Redpanda to be ready..."
kubectl wait --for=condition=Ready pod -l app=redpanda -n "$NAMESPACE" --timeout=180s

# Additional check: ensure Kafka port is actually responding
echo "→ Verifying Kafka port is accessible..."
for i in {1..30}; do
  if kubectl exec -n "$NAMESPACE" deploy/redpanda -- timeout 2 bash -c "echo > /dev/tcp/localhost/9092" 2>/dev/null; then
    echo "✓ Kafka port 9092 is accepting connections"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "❌ Kafka port 9092 not responding after 30 attempts"
    kubectl logs -n "$NAMESPACE" -l app=redpanda --tail=50
    exit 1
  fi
  echo "  Waiting for Kafka port... (attempt $i/30)"
  sleep 2
done

echo ""
echo "✅ Redpanda deployed successfully!"
echo ""
kubectl get pods,svc -n "$NAMESPACE" -l app=redpanda
echo ""
echo "📋 Kafka bootstrap servers: redpanda.$NAMESPACE.svc.cluster.local:9092"
echo ""
echo "Test Redpanda connectivity:"
echo "  kubectl run -n $NAMESPACE -it --rm debug --image=curlimages/curl --restart=Never -- \\"
echo "    curl -s http://redpanda:9644/v1/status/ready"
echo ""
