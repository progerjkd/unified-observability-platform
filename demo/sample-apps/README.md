# Demo Sample Applications

This directory contains sample applications for demonstrating the unified observability platform.

## Applications

### 1. Node.js E-Commerce Shop (`nodejs-shop/`)

Three-tier microservices architecture:
- **frontend** — Express.js app, calls product-api
- **product-api** — Express.js app, calls inventory
- **inventory** — Express.js app, returns stock levels

**Auto-instrumentation**: Each deployment has the annotation `instrumentation.opentelemetry.io/inject-nodejs: "true"` — no SDK code in the app!

**Build and deploy**:
```bash
# Build images (you'll need to push to your registry)
cd nodejs-shop/frontend
docker build -t YOUR_REGISTRY/frontend:latest .
docker push YOUR_REGISTRY/frontend:latest

# Repeat for product-api and inventory (they use the same Dockerfile + package.json pattern)

# Update deployment.yaml with your registry, then deploy
kubectl apply -f nodejs-shop/frontend/deployment.yaml
kubectl apply -f nodejs-shop/product-api/deployment.yaml
kubectl apply -f nodejs-shop/inventory/deployment.yaml
```

**Or use a quick local build** (if you have a local registry or minikube):
```bash
eval $(minikube docker-env)  # If using minikube
docker build -t frontend:latest nodejs-shop/frontend/
docker build -t product-api:latest nodejs-shop/product-api/
docker build -t inventory:latest nodejs-shop/inventory/

# Update deployments to use local images (imagePullPolicy: Never)
```

### 2. Legacy Nginx App (`legacy-nginx/`)

Demonstrates agent-only collection for apps that can't be instrumented:
- nginx container (no instrumentation)
- nginx-exporter sidecar (exposes Prometheus metrics)
- otel-agent sidecar (scrapes logs + metrics)

**Deploy**:
```bash
kubectl apply -f legacy-nginx/deployment.yaml
```

### 3. Load Generator (`load-generator.yaml`)

K6-based load generator that sends traffic to all apps.

**Deploy**:
```bash
kubectl apply -f load-generator.yaml
```

## Demo Flow

1. Deploy the OTel Operator and Instrumentation CR first:
   ```bash
   make install-otel  # From repo root
   ```

2. Deploy sample apps:
   ```bash
   kubectl apply -f demo/sample-apps/nodejs-shop/
   kubectl apply -f demo/sample-apps/legacy-nginx/
   ```

3. Start load generator:
   ```bash
   kubectl apply -f demo/sample-apps/load-generator.yaml
   ```

4. Open Grafana and explore:
   - Tempo: Search for service `frontend` — see distributed traces
   - Loki: Query `{service_name="legacy-nginx"}` — see parsed nginx logs
   - Mimir: Query `rate(http_server_requests_total[5m])` — see request rate

5. Trigger errors for demo:
   ```bash
   kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
     sh -c "for i in {1..50}; do curl http://frontend:3000/error; sleep 0.2; done"
   ```

6. Show alert firing in Grafana → Alerting → Alert Rules (HighErrorRate should fire)
