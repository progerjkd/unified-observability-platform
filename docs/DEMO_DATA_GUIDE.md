# Demo Data Generation Guide

## Quick Start - See Data in 3 Minutes

### 1. Deploy Demo App (Already Done ✅)

```bash
kubectl apply -f demo/quick-demo-app.yaml
```

This deploys:
- **demo-app**: 2 replicas with auto-instrumentation
- **load-generator**: Continuous traffic generator

### 2. Verify Auto-Instrumentation is Working

```bash
# Check init container was injected
kubectl describe pod -n default -l app=demo-app | grep -A 2 "Init Containers"

# Should see:
# Init Containers:
#   opentelemetry-auto-instrumentation-nodejs:
```

### 3. Wait for Data (2-3 minutes)

The pipeline flow is:
```
demo-app → OTel Agent (sidecar) → OTel Gateway → Mimir/Loki/Tempo
```

### 4. Query Data in Grafana

**Access Grafana**: http://localhost:3000

#### **Mimir (Metrics)**

Go to **Explore** → Select **Mimir** datasource:

```promql
# OTel Gateway metrics (should appear immediately)
rate(otelcol_receiver_accepted_spans_total[5m])
otelcol_exporter_sent_spans_total

# Demo app metrics (after 2-3 min)
rate(http_server_duration_count{service_name="demo-frontend"}[5m])
histogram_quantile(0.95, rate(http_server_duration_bucket[5m]))
```

#### **Loki (Logs)**

Go to **Explore** → Select **Loki** datasource:

```logql
# All logs from demo app
{service_name="demo-frontend"}

# Logs with trace context
{service_name="demo-frontend"} | json | trace_id != ""
```

#### **Tempo (Traces)**

Go to **Explore** → Select **Tempo** datasource:

Click **"Search"** tab:
- Service Name: `demo-frontend`
- Click **"Run query"**

You should see traces appear!

---

## How Auto-Instrumentation Works

### The Annotation Magic

In [demo/quick-demo-app.yaml](../demo/quick-demo-app.yaml):

```yaml
metadata:
  annotations:
    instrumentation.opentelemetry.io/inject-nodejs: "true"
```

**This single annotation triggers**:
1. OTel Operator detects the annotation
2. Injects init container with Node.js SDK
3. Sets NODE_OPTIONS to auto-load instrumentation
4. App sends OTLP to gateway with **zero code changes**

### What Gets Captured

**Traces**:
- HTTP requests/responses
- Database queries (if app uses DB)
- External API calls
- Custom spans

**Metrics**:
- Request rate, error rate, duration (RED)
- Runtime metrics (heap, CPU, event loop)
- Custom metrics

**Logs**:
- Structured logs with trace context
- Error logs
- Console output

---

## For Your Panel Interview Demo

### Talking Points

1. **Show the annotation**:
   ```bash
   kubectl get deployment demo-app -o yaml | grep -A 2 annotations
   ```

   > "This single annotation enables auto-instrumentation. No SDK imports, no code changes."

2. **Show the injected init container**:
   ```bash
   kubectl describe pod -l app=demo-app | grep -A 5 "Init Containers"
   ```

   > "The OTel Operator injected an init container that copies the Node.js SDK into the app container."

3. **Show data in Grafana**:
   - **Mimir**: Query `rate(http_server_duration_count[5m])` → "Request rate metrics"
   - **Tempo**: Search for service `demo-frontend` → "Distributed traces without code changes"
   - **Loki**: Query `{service_name="demo-frontend"}` → "Logs with trace correlation"

4. **Show cross-signal correlation**:
   - In Tempo, click a trace
   - Scroll down → Click **"View logs for this span"**
   - **Boom!** → Loki opens with exact logs for that trace

   > "This is the power of unified observability - seamless drill-down from traces to logs to metrics."

---

## Load Generator Explained

The load generator (in quick-demo-app.yaml) is a simple Job that curls the demo app every 2 seconds:

```yaml
while true; do
  curl -s http://demo-app:8080/ || true
  curl -s http://demo-app:8080/products || true
  curl -s http://demo-app:8080/cart || true
  sleep 2
done
```

**Why it matters**:
- Generates consistent traffic for demo
- Produces traces, metrics, logs
- Shows real-world patterns (request rate, latency)

**To stop it**:
```bash
kubectl delete job load-generator -n default
```

**To increase load** (for stress testing):
```bash
# Scale up load generator replicas (edit the Job to be a Deployment first)
# Or run multiple curl loops
```

---

## Custom Sample Apps (For Production Demo)

The `demo/sample-apps/` directory has more realistic apps, but they require building Docker images:

### 1. Node.js E-Commerce (nodejs-shop/)

**Services**:
- frontend → product-api → inventory (3-tier architecture)

**Build**:
```bash
cd demo/sample-apps/nodejs-shop/frontend
docker build -t YOUR_REGISTRY/frontend:latest .
docker push YOUR_REGISTRY/frontend:latest

# Repeat for product-api and inventory
```

**Deploy**:
```bash
# Update image refs in deployment.yaml first
kubectl apply -f demo/sample-apps/nodejs-shop/frontend/deployment.yaml
kubectl apply -f demo/sample-apps/nodejs-shop/product-api/deployment.yaml
```

### 2. Legacy LAMP Stack (legacy-lamp/)

Demonstrates **agent-only collection** (no auto-instrumentation):
- php-apache container (legacy PHP guestbook — no OTel SDK)
- mysqld-exporter sidecar (MySQL metrics on :9104)
- otel-agent sidecar (scrapes Apache logs + MySQL metrics + host metrics)

**Deploy**:
```bash
kubectl apply -f demo/sample-apps/legacy-lamp/deployment.yaml
```

**What it shows**:
> "Not every app can be instrumented. For this legacy LAMP stack, we use agent-only collection — Apache logs, MySQL metrics, and host telemetry without touching the app code."

---

## Integration into Interview Workflow

### Before Interview (1-2 Days)

1. **Deploy demo app**:
   ```bash
   kubectl apply -f demo/quick-demo-app.yaml
   ```

2. **Let it run for 24 hours** to populate dashboards

3. **Take screenshots** (backup if demo fails live):
   - Grafana Explore with traces
   - Logs with trace correlation
   - RED metrics dashboard

### During Interview

**Option A - Live Demo** (preferred):
1. Show Grafana Explore
2. Query Mimir for metrics
3. Search Tempo for traces
4. Click trace → Show waterfall
5. Click "View logs" → Jump to Loki
6. **Boom!** Cross-signal correlation in action

**Option B - Explain Architecture** (if demo fails):
1. Show the annotation in deployment.yaml
2. Explain init container injection
3. Show screenshots from earlier run
4. Walk through the data flow diagram

### Demo Safety Tips

- **Keep load generator running** during interview
- **Have port-forward pre-started**: `kubectl port-forward svc/grafana 3000:80`
- **Pre-open Grafana tabs**: Mimir, Loki, Tempo Explore views
- **Backup screenshots** in case Grafana is down

---

## Cleanup

```bash
# Remove demo app
kubectl delete -f demo/quick-demo-app.yaml

# Remove Instrumentation CR from default namespace
kubectl delete instrumentation otel-instrumentation -n default
```

---

## Next Steps

1. ✅ **Now**: Check Grafana - data should be appearing!
2. **Practice**: Run through the demo flow 2-3 times
3. **Prepare**: Take screenshots, refine talking points
4. **Before interview**: Redeploy fresh to test `make deploy-all-demo` with zero warnings

**You're ready! 🚀**
