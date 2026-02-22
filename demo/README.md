# Demo Environment

This directory contains everything needed to run a cost-optimized demo of the unified observability platform on AWS EKS.

## Prerequisites

- AWS CLI configured with credentials (`aws configure` or `AWS_PROFILE`)
- Docker Desktop (for building ARM64 images)
- Terraform >= 1.5
- kubectl >= 1.28
- Helm >= 3.12

## Set Your Environment

Export these before running any commands. Adjust values to match your setup:

```bash
export AWS_PROFILE=your-profile
```

```bash
export AWS_REGION=us-east-1
```

```bash
export CLUSTER_NAME=obs-lgtm-demo
```

## Quick Start

### 1. Deploy AWS infrastructure (~20 min)

Creates EKS cluster, S3 buckets, IAM roles, and ECR repositories.

```bash
make tf-init
```

```bash
make tf-plan-demo
```

```bash
make tf-apply-demo
```

### 2. Add Helm repos (one-time)

```bash
make helm-repos
```

### 3. Deploy LGTM stack + OTel (~10 min on first run)

Deploys Mimir, Loki, Tempo, Grafana, OTel Operator, OTel Gateway, OTel Agent DaemonSet, auto-instrumentation CRs, alert rules, dashboards, and a quick demo app.

```bash
make deploy-all-demo
```

> **Note**: First run on a fresh cluster may take longer while the cluster autoscaler provisions additional nodes. The 10-minute Helm timeout allows for this.

### 4. Build and push demo app images

Build ARM64 Docker images for the 3 Node.js microservices (frontend, product-api, inventory):

```bash
make build-demo-images
```

Push to ECR:

```bash
make push-demo-images
```

### 5. Deploy sample apps + load generator

Deploys the 3-tier Node.js shop, legacy nginx, and K6 load generator. Image URIs are automatically substituted from ECR.

```bash
make deploy-demo-apps
```

### 6. Access Grafana

```bash
kubectl -n observability port-forward svc/grafana 3000:80
```

Open <http://localhost:3000> — Login: `admin` / `demo-admin-2025`

Dashboards will populate with data within ~2 minutes of deployment.

### 7. (Optional) Install ArgoCD for deployment visualization

```bash
make install-argocd-demo
```

```bash
make argocd-apps-demo
```

### 8. Access ArgoCD (if installed)

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

```bash
make argocd-password
```

Open <http://localhost:8080> — Login: `admin` / password from above

## Teardown

### Remove Helm releases + apps (keeps infrastructure)

```bash
make undeploy-demo
```

### Remove only sample apps (keeps LGTM stack)

```bash
make destroy-demo-apps
```

### Full teardown (destroy EKS cluster + all AWS resources)

```bash
make teardown-demo
```

This automatically:

1. Empties S3 buckets (all object versions and delete markers)
2. Removes the Kubernetes namespace from Terraform state (avoids timeout)
3. Runs `terraform destroy` (removes EKS, S3, IAM, ECR)
4. Cleans up orphaned EBS volumes left behind by PVCs

### Redeploy from scratch (after undeploy)

```bash
make deploy-all-demo
```

```bash
make deploy-demo-apps
```

## Architecture

<p align="center">
  <img src="../docs/diagrams/aws_infrastructure.png" width="700" alt="AWS Infrastructure">
</p>

<p align="center">
  <img src="../docs/diagrams/data_flow.png" width="600" alt="Telemetry Data Flow">
</p>

<p align="center">
  <img src="../docs/diagrams/eks_cluster.png" width="700" alt="EKS Cluster Architecture">
</p>

<p align="center">
  <img src="../docs/diagrams/network_architecture.png" width="600" alt="Network Architecture">
</p>

> Diagrams are generated from code — see [docs/diagrams/](../docs/diagrams/) for sources and regeneration instructions.

## Infrastructure

Demo mode deploys a minimal EKS cluster optimized for cost (~$100-150/month):

| Resource     | Demo                                       | Production                             |
| ------------ | ------------------------------------------ | -------------------------------------- |
| EKS nodes    | 2-10x Graviton Spot (autoscaled)           | 13 nodes across 3 node groups          |
| ECR          | 3 repos (frontend, product-api, inventory) | N/A (use your CI/CD registry)          |
| Mimir        | 1 replica, replication_factor=1            | 3+ replicas, distributed               |
| Loki         | 1 replica, SingleBinary                    | Distributed with read/write separation |
| Tempo        | 1 replica per component                    | Distributed with compactor             |
| Grafana      | 1 replica                                  | 2 replicas, HA                         |
| OTel Gateway | 1 replica                                  | 3 replicas with HPA                    |
| ArgoCD       | 1 replica (optional, visualization)        | N/A (or dedicated GitOps cluster)      |

All features (auto-instrumentation, tail sampling, cross-signal correlation) work identically.

### Node Scaling Strategy

The demo uses **Cluster Autoscaler** with tight packing to minimize cost:

- **Starts with 2 nodes** — minimum viable for the LGTM stack
- **Scales up automatically** when pods are Pending (e.g., after deploying sample apps)
- **Scales back down** within ~10 min when load drops (utilization threshold: 50%)
- **Diversified Spot pool** (`t4g.medium`, `t4g.large`, `m6g.medium`, `m7g.medium`) for availability

If Spot capacity is unavailable, switch to On-Demand:

```bash
make tf-plan-demo-ondemand && make tf-apply
```

## Directory Structure

```
demo/
  quick-demo-app.yaml           # Standalone demo app (alternative to sample-apps)
  sample-apps/                  # Full sample application suite
    nodejs-shop/                # 3-tier e-commerce microservices
      frontend/                 #   Express.js web frontend
        app.js, Dockerfile, package.json, deployment.yaml
      product-api/              #   Product catalog API
        app.js, Dockerfile, package.json, deployment.yaml
      inventory/                #   Inventory service
        app.js, Dockerfile, package.json, deployment.yaml
    legacy-nginx/               # Legacy app with agent-only collection
    load-generator.yaml         # K6 load generator for all apps
```

## Sample Applications

### 1. Node.js E-Commerce Shop (`sample-apps/nodejs-shop/`)

Three-tier microservices architecture demonstrating **zero-code auto-instrumentation**:

```
frontend (:3000) --> product-api (:3001) --> inventory (:3002)
```

**frontend** — Express.js web app that serves product listings. Calls `product-api` for data. Includes an `/error` endpoint that always returns HTTP 500 for demonstrating error tracking and alerting.

**product-api** — Express.js API returning a product catalog (Solar Panels, Battery Storage, Inverters). For each product, it calls the `inventory` service to fetch stock levels. Includes simulated database query delay (0-100ms).

**inventory** — Express.js service returning stock levels for products. Simulates database latency (0-50ms).

**Key point**: None of these apps contain any OpenTelemetry SDK code. Instrumentation is injected at runtime by the OTel Operator via a single annotation on each Deployment:

```yaml
annotations:
  instrumentation.opentelemetry.io/inject-nodejs: "true"
```

The Operator injects an init container that copies the Node.js SDK into the app container and sets `NODE_OPTIONS` to auto-load it. The result is full distributed tracing, RED metrics, and log correlation with zero application changes.

**Image build pipeline**: Images are built for `linux/arm64` (matching Graviton nodes) and stored in ECR repositories created by Terraform (`obs-platform-demo/frontend`, `obs-platform-demo/product-api`, `obs-platform-demo/inventory`). The `deploy-demo-apps` target automatically substitutes the ECR URI into the deployment manifests.

**What to show in Grafana:**

- **Tempo**: Search for service `frontend` — trace waterfall shows `frontend -> product-api -> inventory` call chain
- **Mimir**: `rate(http_server_duration_count{service_name="frontend"}[5m])` — request rate metrics
- **Loki**: `{service_name="frontend"}` — logs with trace IDs for cross-signal correlation

### 2. Legacy Nginx (`sample-apps/legacy-nginx/`)

Demonstrates **agent-only collection** for applications that cannot be modified or instrumented. The pod runs three containers:

| Container        | Image                                  | Purpose                                |
| ---------------- | -------------------------------------- | -------------------------------------- |
| `nginx`          | `nginx:1.25-alpine`                    | The "legacy" app — cannot be changed   |
| `nginx-exporter` | `nginx/nginx-prometheus-exporter:1.1`  | Sidecar exposing Prometheus `/metrics` |
| `otel-agent`     | `otel/opentelemetry-collector-contrib` | Sidecar collecting logs + metrics      |

The OTel agent sidecar is configured with three receivers:

- **filelog** — Parses JSON-formatted nginx access logs, extracts `method`, `status`, `request_time`, `user_agent`
- **prometheus** — Scrapes `nginx-exporter` for connection count, request rate, response codes
- **hostmetrics** — Collects CPU, memory, and network from the pod

All telemetry is tagged with `service.name: legacy-nginx` and exported via OTLP to the gateway.

**What to show in Grafana:**

- **Loki**: `{service_name="legacy-nginx"} | json` — structured nginx access logs
- **Mimir**: `nginx_http_requests_total` — request metrics from the exporter
- **Talking point**: "Not every app can be instrumented. For legacy, third-party, or black-box apps, we use agent-only collection for logs, metrics, and host telemetry — no code changes, no redeployment."

### 3. K6 Load Generator (`sample-apps/load-generator.yaml`)

A [Grafana K6](https://k6.io/) Job that generates continuous traffic to both the Node.js shop and legacy nginx:

- **5 virtual users** running for **24 hours**
- Hits random endpoints: `/`, `/product/1`, `/product/2`, `/product/3`, `http://legacy-nginx/`
- **5% of requests** hit the `/error` endpoint to produce error traces and trigger alerts
- Random sleep between 0-5 seconds to simulate realistic traffic patterns

### 4. Quick Demo App (`quick-demo-app.yaml`)

A standalone alternative to the full sample-apps suite. Deploys:

- 2 replicas of the OTel demo frontend image with auto-instrumentation annotation
- A simple curl-based load generator hitting the app every 2 seconds

Use this for a minimal demo when you don't need the full 3-tier architecture. It is deployed automatically by `make deploy-all-demo`.

## ArgoCD — Deployment Visualization

ArgoCD provides a visual dashboard showing all LGTM stack components with real-time health and sync status. Useful for demos to show everything is green at a glance.

### Setup

```bash
make install-argocd-demo
```

```bash
make argocd-apps-demo
```

### Access

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:80
```

```bash
make argocd-password
```

Open <http://localhost:8080> — Login: `admin` / password from command above

### What ArgoCD Shows

8 Application tiles, each showing health status:

| Application        | Source                    | Namespace     |
| ------------------ | ------------------------- | ------------- |
| mimir              | grafana/mimir-distributed | observability |
| loki               | grafana/loki              | observability |
| tempo              | grafana/tempo-distributed | observability |
| grafana            | grafana/grafana           | observability |
| otel-operator      | opentelemetry-operator    | observability |
| otel-gateway       | opentelemetry-collector   | observability |
| cluster-autoscaler | cluster-autoscaler        | kube-system   |
| demo-apps          | demo/sample-apps/ (git)   | observability |

Each Application uses **multi-source**: Helm chart from upstream + values from this git repo. Click any tile to see the full resource topology (Deployments, StatefulSets, Pods, Services, PVCs).

**Talking point**: "All deployment configuration lives in git. ArgoCD visualizes the live state and detects drift — if someone changes something in the cluster that doesn't match git, it shows as OutOfSync."

## Grafana Queries Cheat Sheet

### Tempo (Traces)

```
{service.name="frontend"}              # All frontend traces
{status=error}                         # All error traces
{duration > 500ms}                     # Slow traces
```

### Loki (Logs)

```logql
{service_name="frontend"}                                # All frontend logs
{service_name="frontend"} |= "error"                     # Error logs
{service_name="legacy-nginx"} | json                      # Parsed nginx logs
{service_name="frontend"} | json | trace_id != ""         # Logs with trace context
```

### Mimir (Metrics)

```promql
rate(http_server_duration_count[5m])                      # Request rate
histogram_quantile(0.99, rate(http_server_duration_bucket[5m]))  # p99 latency
sum by (service_name, status_code) (rate(http_server_requests_total[5m]))  # By service + status
rate(otelcol_receiver_accepted_spans_total[5m])           # OTel pipeline throughput
```

## Triggering Errors (for alerting demo)

```bash
kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c "for i in \$(seq 1 50); do curl http://frontend:3000/error; sleep 0.2; done"
```

This triggers the `HighErrorRate` alert in Mimir. Show the alert firing in Grafana > Alerting > Alert Rules, then drill down: alert -> metrics -> exemplar -> trace -> logs.

## Cross-Signal Correlation Demo

The core value proposition of unified observability:

1. **Metrics to Traces**: In a Mimir panel, click an exemplar data point -> jumps to the exact trace in Tempo
2. **Traces to Logs**: In a Tempo trace view, click "View logs for this span" -> jumps to Loki with the matching trace ID
3. **Logs to Traces**: In Loki, click a trace ID in the derived fields -> jumps to the trace in Tempo

This requires no application-side configuration. Grafana datasources are pre-configured with `tracesToLogsV2`, `tracesToMetrics`, and derived fields in `helm/grafana/values-demo-simple.yaml`.
