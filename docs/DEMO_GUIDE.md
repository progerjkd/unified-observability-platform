# Demo Guide — 90-Minute Panel Interview Presentation

This guide provides a step-by-step walkthrough for demonstrating the unified observability platform during your interview at Stem Inc.

---

## Table of Contents

- [Demo Environment Setup](#demo-environment-setup)
- [Sample Applications](#sample-applications)
- [90-Minute Presentation Timeline](#90-minute-presentation-timeline)
- [Demo Flow](#demo-flow)
- [Key Talking Points](#key-talking-points)
- [Troubleshooting](#troubleshooting)
- [Pre-Demo Checklist](#pre-demo-checklist)

---

## Demo Environment Setup

### Minimal Infrastructure (Cost: ~$150–$250/mo)

For the demo, we'll deploy a **scaled-down version** of the production architecture:

| Component | Production | Demo | Justification |
|---|---|---|---|
| **EKS cluster** | Multi-AZ, 3 node groups | Single-AZ, 1 node group | Reduce costs, same functionality |
| **EKS nodes** | r7g.xlarge + m7g.large | 2-4x Graviton Spot (autoscaled) | 70% cost reduction |
| **Mimir ingesters** | 3 replicas, dedicated nodes | 1 replica, shared nodes | Sufficient for demo load |
| **Loki/Tempo** | 3/2/2 replicas | 1 replica each | Minimal HA for demo |
| **Sample apps** | N/A | 3 deployments | Node.js + Python + legacy nginx |
| **On-prem** | 200+ hosts | 1 EC2 simulating on-prem | Demonstrate pattern |

### Terraform Variables for Demo

Create `terraform/demo.tfvars`:

```hcl
aws_region      = "us-east-1"
environment     = "demo"
org_prefix      = "yourname"  # Your name for S3 bucket uniqueness
cluster_name    = "obs-lgtm-demo"
cluster_version = "1.35"
vpc_cidr        = "10.0.0.0/16"

# Diversified Spot pool + Cluster Autoscaler (2-4 nodes)
eks_node_groups = {
  demo = {
    instance_types = ["t4g.medium", "t4g.large", "m6g.medium", "m7g.medium"]
    capacity_type  = "SPOT"
    min_size       = 2
    max_size       = 4
    desired_size   = 2  # Autoscaler adds nodes as needed
  }
}
```

### Deployment Steps (Do this 1–2 days before the interview)

```bash
# 1. Deploy infrastructure (~20 minutes)
make tf-init
make tf-plan-demo && make tf-apply

# 2. Configure kubectl
aws eks update-kubeconfig --name obs-lgtm-demo --region us-east-1 --profile your-aws-profile

# 3. Deploy everything: autoscaler + LGTM + OTel + alerts + dashboards (~15 minutes)
make helm-repos
make deploy-all-demo

# 4. Deploy sample applications + load generator
make deploy-demo-apps

# 5. Port-forward Grafana (keep running)
kubectl -n observability port-forward svc/grafana 3000:80
```

Access Grafana at `http://localhost:3000` (default credentials: `admin` / `prom-operator` or check Helm output).

---

## Sample Applications

### 1. Modern App — Auto-Instrumented Node.js

**Location**: `demo/sample-apps/nodejs-shop/`

This is an e-commerce microservice that demonstrates:
- Zero-code auto-instrumentation via OTel Operator annotations
- Distributed tracing across HTTP calls
- RED metrics (Rate, Errors, Duration)
- Structured logs with trace correlation

**Architecture**:
```
┌──────────────┐    HTTP     ┌──────────────┐    HTTP     ┌──────────────┐
│   frontend   │────────────▶│  product-api │────────────▶│  inventory   │
│ (Express.js) │             │ (Express.js) │             │ (Express.js) │
└──────────────┘             └──────────────┘             └──────────────┘
       │                             │                             │
       └─────────────────────────────┴─────────────────────────────┘
                                     │
                            OTLP :4318 (auto-injected)
                                     │
                            OTel DaemonSet Agent
```

**What it demonstrates**:
- Auto-instrumentation: Just add annotation `instrumentation.opentelemetry.io/inject-nodejs: "true"`
- Service topology in Grafana (frontend → product-api → inventory)
- Trace waterfall showing database query latency
- Exemplars linking from request rate metrics to specific traces
- Log-to-trace correlation (click trace ID in logs, jump to Tempo)

**Key files**:
- `demo/sample-apps/nodejs-shop/frontend/deployment.yaml` — Deployment with auto-instrumentation annotation
- `demo/sample-apps/nodejs-shop/frontend/app.js` — Express.js app (no OTel SDK code needed!)
- `demo/sample-apps/nodejs-shop/load-generator.yaml` — K6 load generator to produce traffic

---

### 2. Modern App — Auto-Instrumented Python (Flask)

**Location**: `demo/sample-apps/python-api/`

A simple REST API showing Python auto-instrumentation:
- Flask app with database queries (SQLite)
- OTel Operator annotation for Python auto-instrumentation
- Error injection endpoint (`/error`) to demonstrate error tracking

**What it demonstrates**:
- Python auto-instrumentation works the same as Node.js (annotation-based)
- Error traces show up in RED metrics dashboards
- Database spans are captured automatically

---

### 3. Legacy App — Agent-Only Collection (Nginx)

**Location**: `demo/sample-apps/legacy-nginx/`

An nginx web server simulating a legacy application that **cannot be modified**:
- No code changes possible
- No auto-instrumentation
- Agent scrapes host metrics, access logs, and Prometheus metrics from nginx-exporter sidecar

**Architecture**:
```
┌──────────────────────────────────────────────────────┐
│                     Pod                               │
│                                                       │
│  ┌────────────┐   Access    ┌─────────────────────┐  │
│  │   nginx    │─── logs ───▶│  OTel Agent         │  │
│  │ (legacy)   │             │  (filelog receiver) │  │
│  └────────────┘             └─────────────────────┘  │
│        │                              │               │
│        │ :9113                        │               │
│  ┌─────▼──────────┐                  │               │
│  │ nginx-exporter │ /metrics         │               │
│  │  (Prometheus)  │──────────────────┘               │
│  └────────────────┘   (prometheus receiver)          │
└──────────────────────────────────────────────────────┘
                           │ OTLP
                    OTel DaemonSet
```

**What it demonstrates**:
- **Agent-only collection** for legacy apps that can't be changed
- **filelog receiver** — parses nginx access logs, extracts HTTP status, latency, user agent
- **prometheus receiver** — scrapes nginx-exporter for metrics (requests/sec, response codes, active connections)
- **hostmetrics receiver** — CPU, memory, disk, network from the pod/host
- No distributed tracing, but still full visibility into metrics and logs

---

### 4. Simulated On-Prem Host (EC2)

**Location**: `demo/on-prem-simulator/`

An EC2 instance simulating an on-premises Linux host:
- Deployed via Terraform module `otel-ec2-linux`
- OTel Collector installed as systemd service
- Runs a simple Go HTTP server writing logs to `/var/log/app.log`
- Demonstrates agent buffering during gateway downtime

**What it demonstrates**:
- Agents work the same across EKS, ECS, EC2, on-prem
- Persistent queue buffering (stop gateway, agent queues locally, resume gateway, data replays)
- Host metrics from non-Kubernetes environments

---

## 90-Minute Presentation Timeline

### Phase 1: Introduction and Problem Statement (10 minutes)

**Talking Points**:
- "The challenge: 500 instances across 8 platform types — EKS, ECS Fargate, ECS EC2, bare EC2, on-prem Linux and Windows"
- "Requirements: Unified visibility, vendor neutrality, minimal code changes, single pane of glass"
- "Existing approaches: Vendor tools (expensive, lock-in), ELK (ops-heavy), CloudWatch (AWS-only)"

**Visuals**: Walk through the [README.md](../README.md) — show architecture diagram, platform coverage table.

---

### Phase 2: Architecture Deep Dive (15 minutes)

**Talking Points**:
- **Three-layer architecture**: Collection (agents) → Gateway (sampling/filtering) → Backend (LGTM)
- **Why OpenTelemetry**: Vendor-neutral, single agent for all signals, CNCF-backed standard
- **Why LGTM stack**: Open-source, S3-portable, cross-signal correlation, cost-effective (~$2,840/mo vs $12K+ for Datadog)
- **Sampling strategy**: Multi-tier (head + tail) — 100% errors, ~0.1% normal traffic
- **IRSA pattern**: No static AWS credentials, scoped IAM roles per component

**Visuals**:
- Main architecture diagram in README
- Mimir/Loki/Tempo architecture diagrams (reference official docs)
- Sampling strategy table

**Commands**:
```bash
# Show deployed infrastructure
kubectl get nodes
kubectl get pods -n observability

# Show Helm releases
helm list -n observability

# Show OTel Operator CRs
kubectl get instrumentation -n default
kubectl get opentelemetrycollector -n observability
```

---

### Phase 3: Demo — Auto-Instrumentation (20 minutes)

**Objective**: Show zero-code instrumentation of Node.js and Python apps

**Steps**:

1. **Show the code** — `demo/sample-apps/nodejs-shop/frontend/app.js`
   - Point out: **No OpenTelemetry SDK imports, no instrumentation code**
   - "This is a standard Express.js app"

2. **Show the deployment** — `demo/sample-apps/nodejs-shop/frontend/deployment.yaml`
   - Highlight the annotation:
     ```yaml
     instrumentation.opentelemetry.io/inject-nodejs: "true"
     ```
   - "This single annotation tells the OTel Operator to inject the Node.js SDK at pod startup"

3. **Deploy the app**:
   ```bash
   kubectl apply -f demo/sample-apps/nodejs-shop/
   kubectl get pods -n default
   kubectl logs <frontend-pod> | grep -i opentelemetry
   # You'll see: "OpenTelemetry automatic instrumentation started"
   ```

4. **Generate traffic**:
   ```bash
   kubectl apply -f demo/sample-apps/load-generator.yaml
   ```

5. **Open Grafana** → Explore → Tempo:
   - Search for traces from service `frontend`
   - Click on a trace → **show waterfall view**:
     - HTTP span: `GET /products`
     - Child span: HTTP call to `product-api`
     - Child span: HTTP call to `inventory`
     - Child span: Database query `SELECT * FROM products`
   - **Key point**: "All of this was captured automatically — no code changes"

6. **Show service topology**:
   - Grafana → Dashboards → Service Health
   - Show the **nodeGraph panel** with frontend → product-api → inventory connections
   - "This is auto-generated from span data via Tempo's metrics generator"

7. **Show metrics → traces correlation (exemplars)**:
   - Grafana → Dashboards → Service Health
   - In the "Request Rate" panel, click on a data point
   - **Exemplar link appears** → click it → jumps to Tempo with the exact trace
   - "This is what we mean by cross-signal correlation — seamless drill-down from metrics to traces"

8. **Show logs → traces correlation**:
   - Grafana → Explore → Loki
   - Query: `{service_name="frontend"} | json | traceID != ""`
   - Click on a log line → in the **Derived Fields** section, click the trace ID
   - Jumps to Tempo showing the trace for that log entry
   - "Grafana extracts the trace ID from structured logs and creates a clickable link — no configuration needed on the app side"

**Talking Points**:
- "Auto-instrumentation works for Java, .NET, Node.js, Python, and more"
- "The OTel Operator manages the SDK lifecycle — updates, configuration, rollbacks"
- "This approach scales to hundreds of services without per-service instrumentation work"

---

### Phase 4: Demo — Legacy App (Agent-Only Collection) (15 minutes)

**Objective**: Show that you can still get visibility into apps that **can't be changed**

**Steps**:

1. **Deploy the legacy nginx app**:
   ```bash
   kubectl apply -f demo/sample-apps/legacy-nginx/
   kubectl get pods
   ```

2. **Show the architecture**:
   - Open `demo/sample-apps/legacy-nginx/deployment.yaml`
   - Show three containers:
     1. `nginx` — the legacy app (no instrumentation)
     2. `nginx-exporter` — sidecar exposing Prometheus `/metrics` endpoint
     3. `otel-agent` — sidecar running OTel Collector with `filelog`, `prometheus`, `hostmetrics` receivers
   - "We can't change the nginx binary, but we can scrape its logs and metrics"

3. **Generate traffic**:
   ```bash
   kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
     sh -c "for i in {1..100}; do curl http://legacy-nginx/; sleep 0.1; done"
   ```

4. **Show logs in Grafana**:
   - Grafana → Explore → Loki
   - Query: `{service_name="legacy-nginx"}`
   - Show parsed log lines with fields: `method`, `status_code`, `response_time_ms`, `user_agent`
   - "The OTel filelog receiver parsed nginx access logs using regex and extracted these fields"

5. **Show metrics in Grafana**:
   - Grafana → Explore → Mimir (Prometheus)
   - Query: `rate(nginx_http_requests_total[5m])`
   - Show request rate graph
   - "These metrics come from the nginx-exporter sidecar, scraped by the OTel agent's prometheus receiver"

6. **Show host metrics**:
   - Query: `system_cpu_utilization{service_name="legacy-nginx"}`
   - Query: `system_memory_usage{service_name="legacy-nginx"}`
   - "The hostmetrics receiver gives us CPU, memory, disk, network — even for legacy apps"

**Talking Points**:
- "Not every app can be instrumented — some are legacy, third-party binaries, or vendor appliances"
- "Agent-only collection still gives us logs, metrics, and host telemetry"
- "We lose distributed tracing, but we retain operational visibility"
- "This is how we handle the ~40% of the estate that can't be modified"

---

### Phase 5: Demo — Alerting and Correlation (10 minutes)

**Objective**: Show the unified alerting pipeline and cross-signal drill-down

**Steps**:

1. **Show alert rules**:
   ```bash
   kubectl get prometheusrule -n observability
   cat configs/alert-rules.yaml | grep -A 10 "HighErrorRate"
   ```
   - "We have 4 categories of alerts: service health, infrastructure, OTel pipeline, LGTM backend"

2. **Trigger an error alert**:
   - The Node.js sample app has an `/error` endpoint
   ```bash
   kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
     sh -c "for i in {1..50}; do curl http://frontend:3000/error; sleep 0.2; done"
   ```

3. **Show the alert firing**:
   - Grafana → Alerting → Alert Rules
   - Find `HighErrorRate` → should transition to **Firing** after ~2 minutes
   - Click **View** → shows which service triggered it (`frontend`)

4. **Drill down from alert to root cause**:
   - Grafana → Dashboards → Service Health
   - Select service: `frontend`
   - Error rate panel shows spike
   - **Click exemplar** on the error spike → jumps to Tempo
   - Trace shows `GET /error` with status `500` and error message
   - Scroll down in trace detail → click **"View Logs for this Span"** (if configured)
   - Shows error logs from Loki for the same trace ID

**Talking Points**:
- "This is the power of correlation: alert fires → see metrics → drill to trace → see logs — all in one interface"
- "Traditional systems require manual correlation by timestamp, which is error-prone"
- "Exemplars and derived fields make this seamless"

---

### Phase 6: Infrastructure as Code Walkthrough (10 minutes)

**Objective**: Show the IaC structure and how it enables reproducibility

**Steps**:

1. **Show Terraform module composition**:
   ```bash
   cat terraform/main.tf
   ```
   - "Notice the module chaining: networking → EKS → S3 → IAM"
   - "Each module has inputs/outputs, allowing modular reuse"

2. **Show IRSA pattern**:
   ```bash
   cat terraform/aws/iam-roles/main.tf
   ```
   - "Every LGTM component gets its own scoped IAM role for S3 access"
   - "No static AWS credentials in the cluster — IRSA uses OIDC federation"

3. **Show OTel config validation**:
   ```bash
   make validate
   ```
   - This runs `otelcol validate` in Docker against all agent configs
   - "We validate configs in CI before deployment to catch errors early"

4. **Show Helm values**:
   ```bash
   cat helm/mimir/values.yaml | grep -A 5 "serviceAccount"
   ```
   - Show the `eks.amazonaws.com/role-arn` annotation
   - "This links the Kubernetes ServiceAccount to the IAM role"

**Talking Points**:
- "Everything is code — no manual console clicks, no undocumented 'magic'"
- "This repo can be cloned, tfvars configured, and `make deploy-all` gives you the full stack"
- "We use GitOps principles: all changes are peer-reviewed PRs, Terraform plan in CI"

---

### Phase 7: Cost and Scale Discussion (5 minutes)

**Talking Points**:
- "At 500 hosts, self-hosted LGTM costs ~$2,840/mo vs $12K+ for Datadog or New Relic"
- "The stack scales horizontally — Mimir has customers running 1B+ active series, we're at 50–250K"
- "S3 storage is cheap and portable — we can add lifecycle policies (Standard → IA → Glacier) or migrate to on-prem MinIO without changing the LGTM stack"
- "For cost optimization, we use Graviton (ARM) instances, Spot for non-critical workloads, and S3 lifecycle rules"

**Visuals**: Show cost comparison table from README.

---

### Phase 8: Q&A and Deep Dives (15 minutes)

**Likely Questions**:

1. **"How do you handle on-prem connectivity?"**
   - "We use AWS Direct Connect — agents send to `gateway.observability.internal` via a Route53 private zone, which resolves to an internal NLB in the VPC"
   - "The on-prem agents are identical to EC2 agents — same config, same systemd service"

2. **"What about data retention and compliance?"**
   - "Retention is configurable per signal: metrics 90d hot → 180d IA → 365d Glacier, logs 30d, traces 14d"
   - "For compliance, all data is encrypted at rest (KMS) and in transit (TLS)"
   - "Data residency: all telemetry stays in our AWS account and on-prem — no third-party SaaS"

3. **"How do you ensure the monitoring system itself doesn't fail?"**
   - "The LGTM stack has its own alerts (ingester health, compactor running, ingestion rate spikes)"
   - "We use Kubernetes liveness/readiness probes, PodDisruptionBudgets, and multi-replica deployments"
   - "The OTel agents have persistent file-backed queues — if the gateway is down, they buffer locally up to 2 GB"

4. **"What about Windows environments?"**
   - "The OTel Collector has native Windows support — `windowseventlog` receiver for Event Logs, `iis` receiver for IIS metrics"
   - "We deploy via MSI and run as a Windows Service — shown in `terraform/modules/otel-ec2-windows/`"
   - "The challenge was IIS log parsing — we use the `iis` receiver which parses W3C format natively"

5. **"How do you handle secrets (Slack webhooks, PagerDuty keys)?"**
   - "Currently using Kubernetes Secrets — in production, we'd integrate AWS Secrets Manager or HashiCorp Vault"
   - "The Alertmanager config references `${SLACK_WEBHOOK_URL}` — injected via environment variable from Secret"

6. **"What's your disaster recovery plan?"**
   - "S3 has 99.999999999% durability and versioning enabled"
   - "For DR, we'd enable S3 cross-region replication to a secondary region"
   - "Mimir/Loki/Tempo state is in S3, so recovery is just redeploying the Helm charts against the same S3 buckets"

---

## Key Talking Points

### Strategic Architecture Decisions

1. **Vendor Neutrality**:
   - "OpenTelemetry + LGTM gives us portability — we can switch backends without changing agents"
   - "S3-compatible storage means we can run LGTM on AWS S3, on-prem MinIO, GCS, Azure Blob"

2. **Operational Simplicity**:
   - "Stateless components (queriers, distributors) backed by S3 — no complex cluster state management like Elasticsearch"
   - "Single agent type (OTel Collector) across all platforms — one config pattern to maintain"

3. **Cost Efficiency**:
   - "Self-hosting saves ~70–85% vs SaaS at our scale"
   - "Label-indexed logs (Loki) vs full-text indexing (ELK) — 5–10x cheaper storage"
   - "Tail sampling reduces trace storage by 95–98% while retaining all errors and anomalies"

4. **Developer Experience**:
   - "Auto-instrumentation means developers don't need to learn OTel SDK APIs"
   - "Single annotation on Kubernetes deployments — `instrumentation.opentelemetry.io/inject-<lang>: 'true'`"
   - "PromQL, LogQL, TraceQL are all query languages developers already know from the Prometheus/Grafana ecosystem"

### Technical Highlights

1. **Cross-Signal Correlation**:
   - "Exemplars, derived fields, and trace-to-logs are first-class Grafana features — no glue code"
   - "This is the difference between 'unified observability' and 'three separate tools in one UI'"

2. **Sampling Intelligence**:
   - "Head sampling at agent (5%) → tail sampling at gateway (2%) = 0.1% normal traffic, 100% errors"
   - "Tail sampling sees the entire trace, so it can make smart decisions (error status, duration, custom attributes)"

3. **Resilience**:
   - "Agents have persistent queues — if the gateway goes down, agents buffer up to 2 GB on disk"
   - "When the gateway recovers, queued data is replayed — no data loss"

---

## Troubleshooting

### Common Issues During Demo

| Issue | Cause | Fix |
|---|---|---|
| **No traces in Tempo** | Auto-instrumentation not working | Check pod logs: `kubectl logs <pod> | grep -i opentelemetry`<br>Verify Instrumentation CR exists: `kubectl get instrumentation` |
| **Grafana datasource errors** | LGTM components not ready | Check pod status: `kubectl get pods -n observability`<br>Check logs: `kubectl logs -n observability <pod>` |
| **Exemplars not showing** | Mimir not configured to accept exemplars | Verify `mimir/values.yaml` has `ingester.limits.max_exemplars: 100`<br>Check that OTel Gateway is sending exemplars (trace sampler adds them) |
| **Logs missing trace IDs** | App not logging in structured format | Ensure app logs JSON with `traceID` field<br>Or configure Loki derived field regex to extract from plaintext |
| **High memory usage in Mimir ingesters** | Too many active series for demo nodes | Reduce scrape frequency or limit app replicas<br>Use `t4g.large` instead of `t4g.medium` for ingesters |

### Pre-Demo Health Checks

Run these commands 30 minutes before the interview:

```bash
# Check all LGTM pods are Running
kubectl get pods -n observability

# Check OTel Gateway is receiving data
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector-gateway --tail=50

# Check sample apps are deployed
kubectl get pods -n default

# Port-forward Grafana
kubectl -n observability port-forward svc/grafana 3000:80 &

# Test Grafana access
curl -s http://localhost:3000/api/health | jq .

# Generate some baseline traffic
kubectl apply -f demo/sample-apps/load-generator.yaml
```

---

## Pre-Demo Checklist

### 1 Week Before

- [ ] Deploy demo infrastructure (`make tf-apply`)
- [ ] Deploy LGTM stack (`make install-lgtm`)
- [ ] Deploy OTel Operator and Gateway (`make install-otel`)
- [ ] Deploy sample applications (`kubectl apply -f demo/sample-apps/`)
- [ ] Verify all pods are Running
- [ ] Test Grafana access and datasources
- [ ] Import dashboards (`make install-dashboards`)

### 1 Day Before

- [ ] Run load generator for 24h to populate dashboards with data
- [ ] Take screenshots of key dashboards (backup in case of live demo issues)
- [ ] Test all demo flows end-to-end
- [ ] Prepare a "cheat sheet" of commands (see next section)

### 1 Hour Before

- [ ] Restart load generator
- [ ] Port-forward Grafana (`kubectl port-forward ...`)
- [ ] Open Grafana in browser, verify datasources are green
- [ ] Open VS Code with the repo
- [ ] Have terminal windows pre-arranged (one for commands, one for logs)

### During Demo

- [ ] Use **two monitors**: one for Grafana, one for terminal/code
- [ ] Have backup screenshots ready in case of network issues
- [ ] Keep a terminal with `kubectl get pods -n observability -w` running in background
- [ ] If something breaks, stay calm and explain the architecture while troubleshooting

---

## Demo Commands Cheat Sheet

### Infrastructure

```bash
# Show EKS cluster
kubectl get nodes -o wide

# Show LGTM components
kubectl get pods -n observability

# Show Helm releases
helm list -n observability

# Show OTel Operator CRs
kubectl get instrumentation -n default -o yaml
kubectl get opentelemetrycollector -n observability
```

### Sample Apps

```bash
# Deploy sample apps
kubectl apply -f demo/sample-apps/

# Check app pods
kubectl get pods -n default

# View app logs
kubectl logs -l app=frontend --tail=100

# Generate traffic
kubectl apply -f demo/sample-apps/load-generator.yaml

# Trigger errors
kubectl run curl --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c "for i in {1..50}; do curl http://frontend:3000/error; sleep 0.2; done"
```

### Grafana Queries

**Tempo (Traces)**:
- `{service.name="frontend"}` — all traces from frontend service
- `{status=error}` — all error traces

**Loki (Logs)**:
- `{service_name="frontend"}` — all logs from frontend
- `{service_name="frontend"} |= "error"` — filter for "error" in logs
- `{service_name="legacy-nginx"} | json` — parse JSON logs

**Mimir (Metrics)**:
- `rate(http_server_requests_total[5m])` — request rate
- `histogram_quantile(0.99, rate(http_server_duration_bucket[5m]))` — p99 latency
- `sum by (service_name, status_code) (rate(http_server_requests_total[5m]))` — requests by service and status

### Troubleshooting

```bash
# Check OTel Gateway logs
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector-gateway --tail=100

# Check Mimir distributor logs
kubectl logs -n observability -l app.kubernetes.io/component=distributor --tail=50

# Check Tempo distributor logs
kubectl logs -n observability -l app.kubernetes.io/component=distributor,app.kubernetes.io/instance=tempo --tail=50

# Check OTel Operator logs
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-operator --tail=50

# Force delete a stuck pod
kubectl delete pod <pod-name> --grace-period=0 --force
```

---

## Final Tips for the Presentation

### Do's

1. **Tell a story**: Start with the problem (fragmented tools, vendor lock-in, cost), show the solution (OTel + LGTM), demonstrate the value (cost savings, unified UX, portability)
2. **Use the Socratic method**: Ask the panel questions ("Have you dealt with observability sprawl? How many tools do you use today?") to engage them
3. **Highlight trade-offs**: Self-hosting requires operational expertise — be honest about the investment in platform engineering vs "just use Datadog"
4. **Show, don't just tell**: Live demo > slides. If something breaks, troubleshoot live — shows real-world skills
5. **Relate to Stem's needs**: Review the job description again — highlight multi-region/hybrid cloud, cost optimization, security/compliance, platform unification

### Don'ts

1. **Don't read from slides**: Use the README as a visual aid, but speak from knowledge
2. **Don't apologize for the demo environment**: "This is scaled down for cost, but the architecture is identical to production at 500 hosts"
3. **Don't skip error handling**: Show what happens when things fail (agent buffers during gateway downtime) — this demonstrates depth
4. **Don't go too deep too fast**: Gauge the panel's technical level — if they're more strategic, focus on cost/vendor lock-in; if hands-on, dive into OTel config

### If Things Go Wrong

- **Grafana datasource is down**: Have screenshots ready — "Let me show you the architecture while this recovers"
- **No traces appearing**: Show the code and explain auto-instrumentation — "The mechanism is sound, let's check logs" (then troubleshoot)
- **Kubernetes pod crashes**: "This is a demo environment on t4g.medium nodes — in prod we'd use larger instances, but let me restart this pod" (shows you know the limits)

---

## Success Metrics

By the end of the demo, the panel should understand:

1. **Why** you chose OpenTelemetry + LGTM (vendor neutrality, cost, portability)
2. **How** the three-layer architecture works (collection → gateway → backend)
3. **What** problems it solves (unified visibility, cross-signal correlation, multi-platform support)
4. **How much** it costs vs alternatives (70–85% savings vs SaaS)
5. **How** to deploy it (Terraform, Helm, Ansible — all IaC)

And they should have seen:
- ✅ Auto-instrumentation in action (Node.js + Python)
- ✅ Legacy app collection (nginx logs + metrics)
- ✅ Cross-signal correlation (metrics → traces → logs)
- ✅ Alerting pipeline (alert fires → drill-down to root cause)
- ✅ Infrastructure as Code (Terraform modules, Helm charts)

Good luck with your interview! 🚀
