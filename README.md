# Unified Observability Platform

A vendor-neutral, production-grade observability platform providing **metrics, logs, and traces** across ~500 compute instances spanning AWS and on-premises infrastructure. Built on [OpenTelemetry](https://opentelemetry.io/) for collection and the [Grafana LGTM stack](https://grafana.com/about/grafana-stack/) for backend storage and visualization.

> **Design goal**: Full telemetry coverage across 8 heterogeneous platform types (EKS, ECS Fargate, ECS EC2, bare EC2, on-prem — Linux and Windows), with zero vendor lock-in, minimal application code changes, and a single pane of glass for all signals.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Why OpenTelemetry?](#why-opentelemetry)
- [Why the Grafana LGTM Stack?](#why-the-grafana-lgtm-stack)
- [The LGTM Stack In Depth](#the-lgtm-stack-in-depth)
  - [Grafana Mimir — Metrics](#grafana-mimir--metrics)
  - [Grafana Loki — Logs](#grafana-loki--logs)
  - [Grafana Tempo — Traces](#grafana-tempo--traces)
  - [Grafana — Visualization and Alerting](#grafana--visualization-and-alerting)
- [Alternatives Considered](#alternatives-considered)
- [Platform Coverage](#platform-coverage)
- [Data Pipeline](#data-pipeline)
- [Auto-Instrumentation](#auto-instrumentation)
- [Sampling Strategy](#sampling-strategy)
- [Alerting](#alerting)
- [Cross-Signal Correlation](#cross-signal-correlation)
- [Cost Analysis](#cost-analysis)
- [Infrastructure as Code](#infrastructure-as-code)
- [Quick Start](#quick-start)
- [Demo Mode](#demo-mode)
- [Repository Structure](#repository-structure)

---

## Architecture Overview

```
┌───────────────────────────────────────────────────────────────────────────┐
│                       COMPUTE INSTANCES (~500)                            │
│                                                                           │
│   EKS Linux    ECS Fargate    ECS EC2       EC2 Bare      On-Premises    │
│   (DaemonSet)  (Sidecar)      Linux/Win     Linux/Win     Linux/Win      │
│                                                                           │
│   ┌─────────────────────────────────────────────────────────────────┐     │
│   │  Applications + OTel SDK Auto-Instrumentation                   │     │
│   │  Java (.NET Core, Node.js) ─── OTLP ──▶ localhost:4317         │     │
│   │                                                                  │     │
│   │  Legacy Apps (no code changes)                                   │     │
│   │  Host metrics, log files, Windows Event Logs ──▶ Agent scrape   │     │
│   └─────────────────────────────────────────────────────────────────┘     │
│                               │                                           │
│   ┌───────────────────────────▼─────────────────────────────────────┐     │
│   │           OTel Collector Agent (per host / per task)            │     │
│   │   Receivers: otlp, hostmetrics, filelog, windowseventlog, iis   │     │
│   │   Processors: memory_limiter, batch, resourcedetection          │     │
│   │   Buffer: file_storage (2GB persistent disk queue)              │     │
│   └───────────────────────────┬─────────────────────────────────────┘     │
└───────────────────────────────┼───────────────────────────────────────────┘
                                │ OTLP gRPC :4317
                                │ (gateway.observability.internal)
                ┌───────────────▼───────────────────┐
                │      OTel Gateway Cluster          │
                │      3 replicas + HPA (up to 6)    │
                │                                    │
                │  ◆ Tail sampling (errors: 100%,    │
                │    high-latency: 100%, normal: 2%) │
                │  ◆ Health-check span filtering     │
                │  ◆ Attribute normalization          │
                └───────────────┬───────────────────┘
                                │ OTLP HTTP
                ┌───────────────┼───────────────────┐
                │               │                   │
        ┌───────▼──────┐ ┌─────▼─────┐ ┌──────────▼──────┐
        │ Grafana Mimir │ │Grafana Loki│ │  Grafana Tempo  │
        │   (Metrics)   │ │   (Logs)   │ │    (Traces)     │
        │   PromQL      │ │   LogQL    │ │    TraceQL      │
        └───────┬───────┘ └─────┬──────┘ └────────┬────────┘
                └───────────────┼──────────────────┘
                          S3 Buckets
                    (KMS-encrypted, lifecycle-managed)
                ┌───────────────▼───────────────────┐
                │           Grafana                  │
                │                                    │
                │   Dashboards · Alerts · Explore    │
                │   Exemplars · Derived Fields       │
                │   Service Topology · Trace-to-Logs │
                └────────────────────────────────────┘
```

The platform follows a **three-layer architecture**:

1. **Collection Layer** — OpenTelemetry Collector agents deployed on every compute instance, exporting via OTLP
2. **Gateway Layer** — Centralized OTel Collectors performing tail sampling, filtering, and fan-out
3. **Backend Layer** — Grafana LGTM stack on EKS with S3-compatible object storage

---

## Why OpenTelemetry?

<p align="center">
  <img src="https://opentelemetry.io/img/logos/opentelemetry-horizontal-color.png" width="400" alt="OpenTelemetry Logo">
</p>

[OpenTelemetry](https://opentelemetry.io/) (OTel) is the **CNCF's second-most active project** (after Kubernetes) and the emerging industry standard for telemetry collection. It provides a single, vendor-neutral framework for instrumenting applications and collecting metrics, logs, and traces.

### What OpenTelemetry provides

| Component | Role | How we use it |
|---|---|---|
| **OTel SDK** | Language-specific instrumentation libraries | Auto-instruments Java, .NET Core, and Node.js apps — no code changes |
| **OTel Collector** | Vendor-agnostic telemetry pipeline (receive → process → export) | Runs as agent on every host + centralized gateway cluster |
| **OTLP Protocol** | Standard wire protocol for all three signals | Unified transport between agents, gateway, and backends |
| **OTel Operator** | Kubernetes operator for managing Collectors and auto-instrumentation | Manages DaemonSet agents and injects instrumentation via pod annotations |

### OTel Collector Pipeline Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     OTel Collector Pipeline                       │
│                                                                   │
│  ┌───────────┐    ┌────────────┐    ┌───────────┐               │
│  │ Receivers  │───▶│ Processors │───▶│ Exporters │               │
│  │            │    │            │    │           │               │
│  │ • otlp     │    │ • batch    │    │ • otlp    │               │
│  │ • hostmetr.│    │ • mem_limit│    │ • otlphttp│               │
│  │ • filelog  │    │ • resource │    │ • promethe│               │
│  │ • winlog   │    │ • k8sattr  │    │           │               │
│  │ • iis      │    │ • sampling │    │           │               │
│  └───────────┘    └────────────┘    └───────────┘               │
│                                                                   │
│  Extensions: health_check, file_storage (persistent queue)       │
└──────────────────────────────────────────────────────────────────┘
```

> **Reference**: [OTel Collector Architecture](https://opentelemetry.io/docs/collector/architecture/) · [Deployment Patterns](https://opentelemetry.io/docs/collector/deployment/gateway/)

### Why not just use vendor-specific agents?

| Criteria | OpenTelemetry | Vendor Agents (Datadog, New Relic, etc.) |
|---|---|---|
| **Vendor lock-in** | None — OTLP is an open standard | Full — proprietary protocols and formats |
| **Backend flexibility** | Switch backends without changing agents | Locked to one vendor |
| **Coverage** | Single agent for metrics + logs + traces | Often requires multiple agents |
| **Community** | CNCF-backed, 1000+ contributors | Single-vendor development |
| **Cost** | Open-source, no per-agent licensing | Per-host or per-GB fees |
| **Auto-instrumentation** | Java, .NET, Node.js, Python, Go, PHP | Varies by vendor |

---

## Why the Grafana LGTM Stack?

<p align="center">
  <img src="https://grafana.com/static/img/logos/logo-mimir.svg" width="80" alt="Mimir">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://grafana.com/static/img/logos/logo-loki.svg" width="80" alt="Loki">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://grafana.com/static/assets/img/logos/grafana-tempo.svg" width="80" alt="Tempo">
  &nbsp;&nbsp;&nbsp;&nbsp;
  <img src="https://grafana.com/static/img/menu/grafana2.svg" width="80" alt="Grafana">
</p>

The decision to use the **Grafana LGTM stack** (Loki, Grafana, Tempo, Mimir) was driven by five key requirements:

### 1. Zero vendor lock-in

All four LGTM components are **open-source** (AGPLv3 / Apache 2.0). The platform can run entirely self-hosted on any Kubernetes cluster — no proprietary SaaS dependency. If the organization later decides to move to Grafana Cloud, the migration is seamless since the same stack powers the managed offering.

### 2. S3-compatible object storage = portable data

Mimir, Loki, and Tempo all use **S3-compatible object storage** as their primary long-term storage backend. This means:
- **AWS**: Use native S3 with lifecycle policies (Standard → IA → Glacier)
- **On-prem**: Drop in [MinIO](https://min.io/) as an S3-compatible replacement
- **Migration**: Data is portable between clouds — no proprietary storage format

### 3. Native cross-signal correlation

Grafana provides **built-in links between all three signals** without custom glue code:
- Metrics → Traces via exemplars (click a data point, see the trace)
- Logs → Traces via derived fields (extract `traceID`, jump to Tempo)
- Traces → Logs via Tempo-to-Loki correlation (view logs inline in trace view)
- Traces → Metrics via Tempo metrics generator (automatic RED metrics from spans)

### 4. Proven scale

| Component | Proven Scale | Our Scale |
|---|---|---|
| **Mimir** | 1 billion+ active series (Grafana Cloud) | ~50K–250K active series |
| **Loki** | Petabytes of logs (Grafana Cloud) | ~60 GB/day compressed |
| **Tempo** | Trillions of spans (Grafana Cloud) | ~10–50 GB/day after sampling |

We are operating well within the proven limits of each component.

### 5. Unified query language ecosystem

Each backend has a purpose-built, expressive query language:
- **PromQL** (Mimir) — the industry standard for metrics, compatible with existing Prometheus dashboards
- **LogQL** (Loki) — Prometheus-inspired syntax for log querying and aggregation
- **TraceQL** (Tempo) — SQL-like trace querying with span-level filtering

---

## The LGTM Stack In Depth

### Grafana Mimir — Metrics

<p align="center">
  <img src="https://grafana.com/static/img/logos/logo-mimir.svg" width="120" alt="Grafana Mimir">
</p>

[Grafana Mimir](https://grafana.com/oss/mimir/) is a horizontally scalable, highly available metrics backend that provides **long-term storage for Prometheus metrics** with global query capabilities.

**Key characteristics:**
- **PromQL-compatible** — drop-in replacement for Prometheus for querying, works with all existing dashboards and alert rules
- **Multi-tenant** — isolates data by tenant for shared infrastructure
- **Microservices architecture** — independently scalable components (distributor, ingester, querier, compactor, store-gateway)
- **Object storage** — writes blocks to S3; local disk is only used for short-term WAL buffering

**How we deploy it:**

```
                    ┌──────────────┐
    OTLP metrics ──▶│ Distributor  │──▶ Consistent hash ring
                    │  (2 replicas) │
                    └──────────────┘
                           │
                    ┌──────▼───────┐
                    │  Ingesters   │──▶ In-memory + WAL
                    │  (3 replicas) │──▶ Flush to S3 every 2h
                    └──────────────┘
                           │
                    ┌──────▼───────┐     ┌──────────────┐
                    │  Compactor   │     │ Store-Gateway │
                    │  (1 replica)  │     │  (2 replicas)  │
                    │  Merges blocks│     │  Serves queries │
                    └──────────────┘     │  from S3       │
                                         └──────────────┘
                                                │
                    ┌───────────────┐    ┌──────▼───────┐
                    │ Query-Frontend│───▶│   Querier    │
                    │  (2 replicas)  │    │  (2 replicas) │
                    └───────────────┘    └──────────────┘
```

**Our configuration** ([helm/mimir/values.yaml](helm/mimir/values.yaml)):
- 3 ingesters on dedicated `r7g.xlarge` nodes (memory-optimized for time-series data)
- S3 storage with 90-day hot → 180-day IA → 365-day Glacier lifecycle
- IRSA (IAM Roles for Service Accounts) for S3 access — no static credentials
- Built-in ruler for evaluating alerting rules, connected to Alertmanager

> **Reference**: [Mimir Architecture](https://grafana.com/docs/mimir/latest/get-started/about-grafana-mimir-architecture/) · [Deployment Modes](https://grafana.com/docs/mimir/latest/references/architecture/deployment-modes/)

---

### Grafana Loki — Logs

<p align="center">
  <img src="https://grafana.com/static/img/logos/logo-loki.svg" width="120" alt="Grafana Loki">
</p>

[Grafana Loki](https://grafana.com/oss/loki/) is a horizontally scalable log aggregation system inspired by Prometheus. Unlike traditional log systems (Elasticsearch, Splunk), Loki **indexes only metadata labels** — not the full text of log lines — making it significantly cheaper to operate at scale.

**Key characteristics:**
- **Label-based indexing** — stores logs indexed by labels (e.g., `service_name`, `environment`), not full-text. Dramatically reduces index size and cost
- **LogQL** — Prometheus-inspired query language for filtering, parsing, and aggregating logs
- **Same storage as metrics** — uses S3 for both index and chunks
- **Multi-tenant** — supports tenant isolation for shared deployments

**How it differs from Elasticsearch / ELK:**

| Feature | Loki | Elasticsearch |
|---|---|---|
| **Indexing** | Labels only (lightweight) | Full-text indexing (expensive) |
| **Storage cost** | Low — compressed chunks in S3 | High — requires fast SSD for indexes |
| **Query speed** | Fast for label-filtered queries | Fast for full-text search |
| **Operational overhead** | Low — stateless readers, S3 storage | High — JVM tuning, shard management, cluster state |
| **Integration** | Native Grafana + OTel | Requires Kibana + Beats/Logstash |

**Our deployment** ([helm/loki/values.yaml](helm/loki/values.yaml)):
- Simple Scalable mode (write/read/backend separation)
- 3 write replicas, 2 read replicas, 2 backend replicas
- TSDB schema v13 with S3 storage
- 30-day hot retention, 90-day archive via S3 lifecycle

> **Reference**: [Loki Architecture](https://grafana.com/docs/loki/latest/get-started/architecture/) · [Deployment Modes](https://grafana.com/docs/loki/latest/get-started/deployment-modes/)

---

### Grafana Tempo — Traces

<p align="center">
  <img src="https://grafana.com/static/assets/img/logos/grafana-tempo.svg" width="120" alt="Grafana Tempo">
</p>

[Grafana Tempo](https://grafana.com/oss/tempo/) is a high-scale distributed tracing backend that requires **only object storage** (S3) to operate. It accepts trace data in OpenTelemetry, Jaeger, and Zipkin formats.

**Key characteristics:**
- **No indexing required** — traces are stored by trace ID in object storage; Tempo uses a bloom filter and columnar (Parquet) format for efficient search
- **Extremely cost-effective** — no dedicated index nodes, no Elasticsearch, just S3
- **TraceQL** — SQL-like query language for searching traces by span attributes, duration, status
- **Metrics generator** — automatically derives RED metrics (Rate, Errors, Duration) and service graph metrics from ingested traces, pushing them into Mimir

**The metrics generator is a key feature** — it means we get service-level RED metrics "for free" from traces, without requiring separate metric instrumentation:

```
  Incoming traces ──▶ Tempo Ingester ──▶ S3 (trace storage)
                           │
                           ▼
                  Metrics Generator
                  ├── span_metrics (RED: rate/error/duration per service+operation)
                  └── service_graph (service-to-service topology)
                           │
                           ▼
                   Mimir (remote_write)
                   └── Queryable via PromQL in Grafana dashboards
```

**Our deployment** ([helm/tempo/values.yaml](helm/tempo/values.yaml)):
- Distributed mode with 3 ingesters, 2 distributors, 2 queriers
- 14-day trace retention in S3
- Metrics generator enabled — pushes RED metrics + service graph to Mimir

> **Reference**: [Tempo Architecture](https://grafana.com/docs/tempo/latest/operations/architecture/) · [How Tempo Works](https://grafana.com/oss/tempo/)

---

### Grafana — Visualization and Alerting

<p align="center">
  <img src="https://grafana.com/static/img/menu/grafana2.svg" width="120" alt="Grafana">
</p>

[Grafana](https://grafana.com/oss/grafana/) serves as the **single pane of glass** for all observability data. It is pre-configured with datasources for Mimir, Loki, and Tempo, with full cross-signal correlation enabled.

**Pre-provisioned datasources** ([helm/grafana/values.yaml](helm/grafana/values.yaml)):

| Datasource | Signal | Query Language | Correlation |
|---|---|---|---|
| Mimir | Metrics | PromQL | Exemplars → Tempo traces |
| Loki | Logs | LogQL | Derived fields → Tempo traces |
| Tempo | Traces | TraceQL | Trace-to-logs (Loki), trace-to-metrics (Mimir), service map |

**Pre-provisioned dashboards** ([dashboards/](dashboards/)):

| Dashboard | Purpose |
|---|---|
| **Platform Overview** | Agent health across all 8 platform types, grouped by environment |
| **Service Health** | RED metrics (Rate, Errors, Duration) per service, with service topology graph |
| **Infrastructure** | Host-level CPU, memory, disk I/O, network, filesystem usage |

**Alerting pipeline:**

```
Mimir ruler (PromQL rules) ──▶ Alertmanager ──▶ PagerDuty (critical)
Loki ruler (LogQL rules)   ──▶ Alertmanager ──▶ Slack (warning)
                                              ──▶ Slack #infra (infrastructure)
```

---

## Alternatives Considered

### Why not Datadog?

[Datadog](https://www.datadoghq.com/) is a leading managed observability platform, but was ruled out for this use case:

| Factor | Datadog | Our LGTM Solution |
|---|---|---|
| **Cost at 500 hosts** | ~$12,000–$25,000/mo ($15–$23/host for Infra + APM + Logs) | ~$2,840/mo (self-hosted) |
| **Vendor lock-in** | Proprietary agent, protocol, and storage | Open standards (OTel, S3, PromQL) |
| **Data residency** | Data sent to Datadog SaaS | Data stays in our AWS account / on-prem |
| **On-prem support** | Limited (requires internet egress) | Full — MinIO replaces S3 for on-prem |
| **Customization** | Limited to vendor roadmap | Full control over pipeline and storage |

**Datadog is excellent** for smaller fleets or teams that prefer fully managed solutions. At 500 instances with on-prem requirements, the cost and lock-in become significant.

### Why not New Relic?

| Factor | New Relic | Our LGTM Solution |
|---|---|---|
| **Pricing model** | Per-GB ingestion ($0.30–$0.50/GB) | S3 storage only (~$0.023/GB/mo) |
| **Cost at our volume** | ~$8,000–$15,000/mo | ~$2,840/mo |
| **On-prem visibility** | Requires internet egress | Native via Direct Connect |
| **Query language** | NRQL (proprietary) | PromQL + LogQL + TraceQL (open) |

### Why not the ELK Stack (Elasticsearch + Logstash + Kibana)?

| Factor | ELK Stack | Our LGTM Solution |
|---|---|---|
| **Scope** | Primarily logs + APM (Elastic APM) | Native metrics + logs + traces |
| **Storage cost** | High — full-text indexing requires fast SSDs | Low — label-indexed logs in S3 |
| **Operational burden** | JVM heap tuning, shard management, split-brain | Stateless components backed by S3 |
| **Metrics** | Bolted on (less mature than Prometheus ecosystem) | PromQL-native (Mimir) |
| **License** | SSPL (not truly open-source since 2021) | AGPLv3 / Apache 2.0 |

### Why not AWS-native (CloudWatch + X-Ray)?

| Factor | CloudWatch + X-Ray | Our LGTM Solution |
|---|---|---|
| **Cost at scale** | ~$4,000–$8,000/mo (per-metric, per-GB) | ~$2,840/mo |
| **On-prem support** | CloudWatch agent only, no X-Ray on-prem | Full parity across all platforms |
| **Portability** | AWS-only | Multi-cloud, on-prem compatible |
| **Correlation** | Limited (no exemplars, basic trace-log linking) | Full cross-signal correlation |
| **Query power** | CloudWatch Insights (limited) | PromQL + LogQL + TraceQL |

### Summary Comparison

| Solution | Monthly Cost (500 hosts) | Vendor Lock-in | On-Prem Support | Cross-Signal Correlation |
|---|---|---|---|---|
| **Self-hosted LGTM** | **~$2,840** | **None** | **Full** | **Native** |
| Grafana Cloud | ~$5,000–$12,000 | Low (same OSS stack) | Partial | Native |
| Datadog | ~$12,000–$25,000 | High | Limited | Good |
| New Relic | ~$8,000–$15,000 | High | Limited | Good |
| ELK Stack (self-hosted) | ~$4,000–$6,000 | Medium (SSPL) | Full | Limited |
| AWS CloudWatch + X-Ray | ~$4,000–$8,000 | High (AWS-only) | Limited | Basic |

---

## Platform Coverage

Every compute platform type in the environment has a tailored OTel Collector deployment:

| Platform | Agent Deployment | Key Receivers | Config |
|---|---|---|---|
| **EKS Linux** | DaemonSet via OTel Operator | `otlp`, `hostmetrics`, `kubeletstats`, `filelog` (pod logs) | [collector-daemonset.yaml](helm/otel-operator/collector-daemonset.yaml) |
| **ECS Fargate** | Sidecar container | `otlp`, `awsecscontainermetrics` | [otel-agent-fargate.yaml](configs/otel-agent-fargate.yaml) |
| **ECS EC2 Linux** | ECS daemon task | `otlp`, `hostmetrics`, `filelog`, `docker_stats` | [otel-agent-linux.yaml](configs/otel-agent-linux.yaml) |
| **ECS EC2 Windows** | Windows Service (MSI) | `otlp`, `hostmetrics`, `windowseventlog`, `iis` | [otel-agent-windows.yaml](configs/otel-agent-windows.yaml) |
| **EC2 Linux** | systemd service | `otlp`, `hostmetrics`, `filelog`, `syslog` | [otel-agent-linux.yaml](configs/otel-agent-linux.yaml) |
| **EC2 Windows** | Windows Service (MSI) | `otlp`, `hostmetrics`, `windowseventlog`, `iis` | [otel-agent-windows.yaml](configs/otel-agent-windows.yaml) |
| **On-prem Linux** | systemd (via Ansible) | `otlp`, `hostmetrics`, `filelog`, `syslog` | [otel-agent-linux.yaml.j2](ansible/templates/otel-agent-linux.yaml.j2) |
| **On-prem Windows** | Windows Service (via Ansible) | `otlp`, `hostmetrics`, `windowseventlog`, `iis` | [otel-agent-windows.yaml.j2](ansible/templates/otel-agent-windows.yaml.j2) |

---

## Data Pipeline

### Telemetry Signals

```
 ┌─────────────────────────────────────────────────────────────────┐
 │                      Signal Flow                                │
 │                                                                  │
 │  METRICS:  App/Host ──▶ OTel Agent ──▶ Gateway ──▶ Mimir (S3)  │
 │            (otlp, hostmetrics, iis)        │         PromQL     │
 │                                             │                    │
 │  LOGS:     Files/Events ──▶ OTel Agent ──▶ Gateway ──▶ Loki (S3)│
 │            (filelog, windowseventlog, syslog)│         LogQL     │
 │                                             │                    │
 │  TRACES:   App SDK ──▶ OTel Agent ──▶ Gateway ──▶ Tempo (S3)   │
 │            (otlp)                    (tail sample)   TraceQL    │
 └─────────────────────────────────────────────────────────────────┘
```

### Cross-Signal Correlation

All three signals are linked in Grafana, enabling seamless drill-down:

```
                    Exemplars
    Mimir (Metrics) ◀─────────────▶ Tempo (Traces)
         │                               │
         │  Derived Fields       Trace-to-Logs
         │                               │
         └──────────▶ Loki (Logs) ◀──────┘
```

- **Metrics → Traces**: Exemplars in Prometheus metrics contain trace IDs; clicking a metric data point opens the trace
- **Logs → Traces**: Loki derived fields extract `traceID` from structured logs to open in Tempo
- **Traces → Logs**: Tempo correlations show associated log lines inline in the trace view
- **Traces → Metrics**: Tempo metrics generator produces RED metrics from spans, queryable in Mimir

---

## Auto-Instrumentation

### EKS (via OTel Operator)

Add annotations to pod specs — **no code changes required**:

```yaml
instrumentation.opentelemetry.io/inject-java: "true"      # Java
instrumentation.opentelemetry.io/inject-dotnet: "true"     # .NET Core
instrumentation.opentelemetry.io/inject-nodejs: "true"     # Node.js
```

The OTel Operator ([helm/otel-operator/instrumentation.yaml](helm/otel-operator/instrumentation.yaml)) automatically injects the language-specific agent at pod startup.

### ECS / EC2 / On-Prem

Set environment variables in task definitions or service configs:

| Language | Key Environment Variable |
|---|---|
| **Java** | `JAVA_TOOL_OPTIONS=-javaagent:/opt/opentelemetry-javaagent.jar` |
| **.NET Core** | `CORECLR_ENABLE_PROFILING=1` + `CORECLR_PROFILER=...` |
| **Node.js** | `NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register` |

### Legacy Apps (no code changes possible)

Agent-only collection — no distributed tracing, but provides:
- Host metrics (CPU, memory, disk, network) via `hostmetrics` receiver
- Application log file parsing via `filelog` receiver
- Windows Event Logs via `windowseventlog` receiver
- IIS metrics via `iis` receiver (if applicable)
- Prometheus `/metrics` scraping (if exposed by the app)

---

## Sampling Strategy

Multi-tier sampling reduces trace storage by **~95–98%** while retaining all actionable data:

| Traffic Type | Head Sampling (Agent) | Tail Sampling (Gateway) | Net Result |
|---|---|---|---|
| Error spans | 100% kept | 100% kept | **All errors kept** |
| High latency (>1s) | 50% kept | 100% kept | **~50% kept** |
| Normal traffic | 5% kept | 2% kept | **~0.1% kept** |
| Health checks | 0% (dropped) | N/A | **Dropped** |

**Head sampling** at the agent reduces volume before it leaves the host. **Tail sampling** at the gateway makes decisions based on complete trace data (error status, duration), ensuring high-value traces are always retained.

---

## Alerting

Alert rules ([configs/alert-rules.yaml](configs/alert-rules.yaml)) cover four categories:

| Category | Alert | Condition |
|---|---|---|
| **Service Health** | HighErrorRate | Error rate > 5% for 5m |
| | HighLatencyP99 | P99 latency > 2s for 5m |
| | TrafficDrop | Traffic dropped > 90% vs 1h ago |
| **Infrastructure** | HighCPU | CPU > 90% for 10m |
| | HighMemory | Memory > 90% for 10m |
| | DiskSpaceLow/Critical | Disk > 85% / 95% |
| **OTel Pipeline** | OTelAgentDown | Agent unreachable for 5m |
| | GatewayHighQueueUsage | Exporter queue > 80% capacity |
| | GatewayExportFailures | Failed span exports |
| | GatewayHighDropRate | Dropping > 10% of spans |
| **LGTM Backend** | MimirIngesterUnhealthy | Unhealthy ring members |
| | LokiIngestionRateHigh | Ingestion > 50 MB/s |
| | TempoCompactorNotRunning | No compaction in 2h |

**Routing** ([configs/alertmanager.yaml](configs/alertmanager.yaml)):
- Critical → PagerDuty (10s group wait, 1h repeat)
- Warning → Slack `#obs-alerts-warning`
- Infrastructure → Slack `#obs-alerts-infra`
- Inhibition: critical suppresses warning for the same alert/service/env

---

## Cost Analysis

### Monthly Infrastructure Costs (AWS us-east-1, self-hosted)

| Category | Components | Monthly Cost |
|---|---|---|
| **LGTM Compute (EKS)** | Mimir (ingesters, distributors, compactor, queriers), Loki (write/read/backend), Tempo (ingesters, distributors, queriers, compactor), Grafana, OTel Gateway | **~$2,300** |
| **Storage (S3 + EBS)** | S3 Standard (~2 TB), S3 IA (~4 TB), S3 Glacier (~8 TB), EBS gp3 PVs | **~$410** |
| **Networking** | NAT Gateway, Direct Connect transfer, internal NLB | **~$130** |
| **Total** | | **~$2,840/mo** |

> With 1-year Reserved Instances or Savings Plans: **~$1,900/mo** (~33% savings).

### Cost Comparison at 500 Hosts

```
  Self-hosted LGTM    ████████ $2,840/mo
  AWS CloudWatch+XRay ██████████████████ $4,000–$8,000/mo
  Grafana Cloud        ██████████████████████ $5,000–$12,000/mo
  New Relic            ████████████████████████████████ $8,000–$15,000/mo
  Datadog              ██████████████████████████████████████████████████ $12,000–$25,000/mo
```

Self-hosted LGTM is **2–8x cheaper** than managed alternatives at this scale, with the trade-off of operational responsibility for the backend infrastructure.

---

## Infrastructure as Code

The entire platform is defined as code using three tools:

| Tool | Scope | Key Files |
|---|---|---|
| **Terraform** | AWS infrastructure (VPC, EKS, S3, IAM, NLB, Route53, EC2 user data, ECS task defs) | [terraform/](terraform/) |
| **Helm** | Kubernetes workloads (LGTM stack, OTel Operator, Gateway) | [helm/](helm/) |
| **Ansible** | On-prem agent deployment (Linux systemd + Windows MSI) | [ansible/](ansible/) |

### Key IaC Patterns

- **Module composition**: `terraform/main.tf` chains networking → EKS → S3 → IAM with output references
- **IRSA (IAM Roles for Service Accounts)**: Each LGTM component gets its own scoped IAM role — no static AWS credentials in the cluster
- **Persistent queues**: All agents use `file_storage` extension with 2 GB disk buffer for resilience during gateway outages
- **Gateway DNS**: Route53 private zone provides `gateway.observability.internal:4317` — agents don't need to know gateway pod IPs

---

## Quick Start

### 1. Configure variables

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Edit terraform.tfvars — at minimum set org_prefix (used for S3 bucket names)
```

### 2. Deploy AWS infrastructure

```bash
make tf-init
make tf-plan
make tf-apply
```

Creates VPC, EKS cluster, S3 buckets, IAM roles, internal NLB, and Route53 private zone.

### 3. Deploy the LGTM stack and collection layer

```bash
make kubeconfig          # Configure kubectl for the EKS cluster
make helm-repos          # Add Grafana + OTel Helm repos (one-time)
make deploy-all          # Deploys everything: LGTM + OTel + alerts + dashboards
```

### 4. Deploy on-prem agents (optional)

```bash
# Edit ansible/inventory/hosts.yml with your on-prem hosts
make deploy-onprem
```

### 5. Validate

```bash
make validate            # Validate OTel Collector configs
make test-pipeline       # Send synthetic telemetry via telemetrygen
```

Access Grafana:

```bash
kubectl -n observability port-forward svc/grafana 3000:80
# Open http://localhost:3000
```

---

## Demo Mode

A cost-optimized demo environment (~$100-150/month vs ~$2,840/month production) that autoscales 2-4 Graviton Spot nodes. Includes Cluster Autoscaler for tight bin-packing — starts with 2 nodes and scales up only when pods are Pending. All features (auto-instrumentation, tail sampling, cross-signal correlation) work identically — only replica counts and resource limits are reduced.

```bash
# Deploy infrastructure (~20 min)
make tf-init && make tf-plan-demo && make tf-apply

# Configure kubectl
aws eks update-kubeconfig --name obs-lgtm-demo --region us-east-1

# Deploy LGTM + OTel stack (~15 min)
make helm-repos            # One-time
make deploy-all-demo

# Deploy sample apps + load generator
make deploy-demo-apps

# Access Grafana — http://localhost:3000 (admin / demo-admin-2025)
kubectl -n observability port-forward svc/grafana 3000:80

# (Optional) ArgoCD for deployment visualization
make install-argocd-demo && make argocd-apps-demo
kubectl -n argocd port-forward svc/argocd-server 8080:80
make argocd-password  # Retrieve admin password
# Access ArgoCD — http://localhost:8080

# Teardown (automated: empties S3, destroys infra, cleans orphaned EBS)
make teardown-demo
```

The [demo/](demo/) directory contains sample applications (auto-instrumented Node.js e-commerce shop, legacy nginx with agent-only collection, K6 load generator), Grafana query cheat sheets, ArgoCD setup, and full instructions. See [demo/README.md](demo/README.md) for details.

---

## Repository Structure

```
├── terraform/
│   ├── main.tf                          # Root orchestration (networking → EKS → S3 → IAM)
│   ├── aws/
│   │   ├── networking/                  # VPC, subnets, security groups, NLB, Route53
│   │   ├── eks-lgtm-cluster/           # EKS cluster with managed node groups
│   │   ├── s3-buckets/                 # Mimir/Loki/Tempo storage with lifecycle policies
│   │   └── iam-roles/                  # IRSA roles for S3 access
│   └── modules/
│       ├── otel-ec2-linux/             # User data for Linux OTel agent install
│       ├── otel-ec2-windows/           # User data for Windows OTel agent install
│       └── otel-ecs-sidecar/           # ECS task definition with OTel sidecar
├── helm/
│   ├── mimir/                          # Grafana Mimir values (metrics backend)
│   ├── loki/                           # Grafana Loki values (logs backend)
│   ├── tempo/                          # Grafana Tempo values (traces backend)
│   ├── grafana/                        # Grafana values (visualization + alerting)
│   ├── otel-operator/                  # OTel Operator + Instrumentation CR + DaemonSet CR
│   ├── otel-gateway/                   # OTel Gateway Collector (tail sampling, fan-out)
│   ├── cluster-autoscaler/             # Cluster Autoscaler values (demo — 2-4 node scaling)
│   └── argocd/                         # ArgoCD values + Application CRs (deployment visualization)
├── configs/
│   ├── otel-agent-linux.yaml           # Agent config: EC2/ECS EC2 Linux
│   ├── otel-agent-windows.yaml         # Agent config: EC2/ECS EC2/on-prem Windows
│   ├── otel-agent-fargate.yaml         # Agent config: ECS Fargate sidecar
│   ├── otel-agent-eks.yaml             # Agent config: standalone EKS DaemonSet
│   ├── otel-gateway.yaml               # Gateway config (standalone, mirrors Helm values)
│   ├── alert-rules.yaml                # Prometheus/Mimir alerting rules
│   └── alertmanager.yaml               # Alertmanager routing (PagerDuty + Slack)
├── dashboards/
│   ├── platform-overview.json          # Agent health across all platforms
│   ├── service-health.json             # RED metrics per service
│   └── infrastructure.json             # Host-level CPU/memory/disk/network
├── demo/
│   ├── README.md                       # Demo setup instructions and query cheat sheet
│   ├── quick-demo-app.yaml             # Standalone demo app (lightweight alternative)
│   └── sample-apps/
│       ├── nodejs-shop/                # 3-tier e-commerce (frontend → product-api → inventory)
│       ├── legacy-nginx/               # Agent-only collection (nginx + exporter + OTel sidecar)
│       └── load-generator.yaml         # K6 load generator (5 VUs, 5% error traffic)
├── scripts/
│   ├── empty-s3-only.sh               # Empty versioned S3 buckets (pre-destroy)
│   └── cleanup-ebs-volumes.sh         # Delete orphaned EBS volumes (post-destroy)
├── ansible/
│   ├── playbooks/                      # install-otel-linux.yml, install-otel-windows.yml
│   ├── templates/                      # Jinja2 agent configs + systemd unit
│   └── inventory/                      # hosts.yml (edit with your on-prem hosts)
├── docs/
│   ├── architecture.md                 # Full architecture documentation
│   ├── DEMO_GUIDE.md                   # 90-minute panel interview presentation guide
│   └── DEMO_DATA_GUIDE.md             # Data generation and Grafana query guide
└── Makefile                            # All deployment targets
```

### Make Targets

```
make help                    # Show all targets
make tf-init                 # Initialize Terraform
make tf-plan                 # Plan Terraform changes
make tf-apply                # Apply Terraform changes
make kubeconfig              # Configure kubectl for EKS
make helm-repos              # Add required Helm repositories
make install-lgtm            # Install Mimir + Loki + Tempo + Grafana
make install-otel            # Install OTel Operator + Gateway + DaemonSet + Instrumentation
make deploy-all              # Full deploy (LGTM + OTel + alerts + dashboards)
make deploy-onprem           # Ansible: deploy agents to on-prem hosts
make validate                # Validate all OTel Collector configs
make test-pipeline           # Send test telemetry via telemetrygen
make install-alerts          # Upload alert rules to Mimir
make install-dashboards      # Create Grafana dashboard ConfigMap

# Demo mode
make tf-plan-demo            # Plan with demo sizing (Spot, autoscaled 2-4 nodes)
make tf-plan-demo-ondemand   # Plan with On-Demand fallback (if Spot unavailable)
make deploy-all-demo         # Full deploy with autoscaler + minimal resources
make deploy-demo-apps        # Deploy sample apps + load generator
make destroy-demo-apps       # Remove sample apps
make install-argocd-demo     # Install ArgoCD (deployment visualization)
make argocd-apps-demo        # Create ArgoCD Application CRs
make argocd-password         # Retrieve ArgoCD admin password
make teardown-demo           # Destroy everything (S3 + infra + orphaned EBS)
make cleanup-orphaned-resources  # Clean up leftover S3/EBS without destroying
```

### Deployment Order

1. `terraform apply` — networking, EKS, S3, IAM
2. `helm install` — Mimir, Loki, Tempo, Grafana
3. `helm install` — OTel Operator, Gateway
4. `kubectl apply` — Instrumentation CR, DaemonSet CR
5. Terraform modules — EC2 agents (user data)
6. Terraform modules — ECS sidecar task definitions
7. `ansible-playbook` — On-prem Linux + Windows agents
