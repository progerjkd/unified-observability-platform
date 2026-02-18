# Unified Observability Platform — Architecture

## Overview

This platform provides unified metrics, logs, and traces collection across a heterogeneous
environment of ~500 compute instances spanning AWS and on-premises infrastructure.

### Design Principles
- **Vendor-neutral**: OpenTelemetry for collection, LGTM stack for backend — no proprietary lock-in
- **Portable storage**: S3-compatible object storage (AWS S3 + MinIO for on-prem)
- **Defense in depth**: Local buffering at agents, tail sampling at gateway, backpressure handling
- **Minimal code changes**: Auto-instrumentation for modern apps, agent-only for legacy

---

## Visual Architecture Diagrams

Detailed AWS architecture diagrams are available in the [`diagrams/`](diagrams/) folder:

- **[AWS Infrastructure](diagrams/aws_infrastructure.png)** - Complete infrastructure with VPC, EKS, S3, IAM, KMS
- **[Data Flow](diagrams/data_flow.png)** - Telemetry flow from ~500 agents → gateway → LGTM backend
- **[EKS Cluster](diagrams/eks_cluster.png)** - Node groups and LGTM component placement
- **[Network Architecture](diagrams/network_architecture.png)** - VPC layout across 3 AZs with subnets and routing

These diagrams are generated as code using the [diagrams](https://diagrams.mingrammer.com/) Python library. See [`diagrams/README.md`](diagrams/README.md) for regeneration instructions.

---

## Architecture Diagram (Text)

```
┌──────────────────────────────────────────────────────────────────────┐
│                     COMPUTE INSTANCES (~500)                         │
│                                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────┐ │
│  │ EKS      │  │ ECS      │  │ ECS EC2  │  │ EC2 Bare │  │On-Prem│ │
│  │ Linux    │  │ Fargate  │  │ Lin/Win  │  │ Lin/Win  │  │Lin/Win│ │
│  │ DaemonSet│  │ Sidecar  │  │ Daemon   │  │ systemd/ │  │sysd/  │ │
│  │ +Operator│  │          │  │ Task/MSI │  │ MSI      │  │MSI    │ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └───┬───┘ │
│       └──────────────┴──────────────┴──────────────┴────────────┘     │
│                              │ OTLP gRPC :4317                       │
└──────────────────────────────┼───────────────────────────────────────┘
                               │
          ┌────────────────────┴────────────────────┐
          │                                          │
  ┌───────▼──────────────┐              ┌────────────▼─────────────┐
  │  AWS GATEWAY CLUSTER  │              │  ON-PREM GATEWAY (opt.)  │
  │  3 replicas + HPA     │              │  3 replicas + LB         │
  │  Tail sampling        │              │  Tail sampling            │
  │  Health-check filter  │              │  Health-check filter      │
  │  Attribute transform  │              │  Attribute transform      │
  └───────┬──────────────┘              └──────────┬───────────────┘
          │                                         │
          └───────────────┬─────────────────────────┘
                          │ OTLP HTTP
          ┌───────────────▼───────────────────────┐
          │         LGTM BACKEND (EKS)            │
          │                                        │
          │  ┌──────────┐  ┌───────┐  ┌─────────┐ │
          │  │  Mimir   │  │ Loki  │  │  Tempo  │ │
          │  │ (metrics)│  │ (logs)│  │ (traces)│ │
          │  └────┬─────┘  └──┬────┘  └────┬────┘ │
          │       └───────────┼─────────────┘      │
          │              S3 Buckets                 │
          └───────────────┬───────────────────────┘
                          │
          ┌───────────────▼───────────────────────┐
          │            GRAFANA                     │
          │  Dashboards · Alerts · Explore         │
          │  Exemplars · Derived Fields · Topology │
          └────────────────────────────────────────┘
```

---

## Component Inventory

### Collection Layer (OpenTelemetry Collector)

| Platform | Deployment | Config File |
|---|---|---|
| EKS Linux | DaemonSet via OTel Operator | `helm/otel-operator/collector-daemonset.yaml` |
| ECS Fargate | Sidecar in task definition | `configs/otel-agent-fargate.yaml` |
| ECS EC2 Linux | ECS daemon task | `configs/otel-agent-linux.yaml` |
| ECS EC2 Windows | Windows Service (MSI) | `configs/otel-agent-windows.yaml` |
| EC2 Linux | systemd service | `configs/otel-agent-linux.yaml` |
| EC2 Windows | Windows Service (MSI) | `configs/otel-agent-windows.yaml` |
| On-prem Linux | systemd (Ansible) | `ansible/templates/otel-agent-linux.yaml.j2` |
| On-prem Windows | Windows Service (Ansible) | `ansible/templates/otel-agent-windows.yaml.j2` |
| Gateway | K8s Deployment (3 replicas) | `helm/otel-gateway/values.yaml` |

### Backend Layer (LGTM Stack)

| Component | Helm Chart | Values File |
|---|---|---|
| Mimir (metrics) | `grafana/mimir-distributed` | `helm/mimir/values.yaml` |
| Loki (logs) | `grafana/loki` | `helm/loki/values.yaml` |
| Tempo (traces) | `grafana/tempo-distributed` | `helm/tempo/values.yaml` |
| Grafana | `grafana/grafana` | `helm/grafana/values.yaml` |

### Infrastructure Layer (Terraform)

| Module | Path | Purpose |
|---|---|---|
| Networking | `terraform/aws/networking/` | VPC, subnets, SGs, NLB, Route53 |
| EKS Cluster | `terraform/aws/eks-lgtm-cluster/` | EKS for LGTM backend |
| S3 Buckets | `terraform/aws/s3-buckets/` | Object storage for Mimir/Loki/Tempo |
| IAM Roles | `terraform/aws/iam-roles/` | IRSA for S3 access |
| EC2 Linux Agent | `terraform/modules/otel-ec2-linux/` | User data for Linux OTel install |
| EC2 Windows Agent | `terraform/modules/otel-ec2-windows/` | User data for Windows OTel install |
| ECS Sidecar | `terraform/modules/otel-ecs-sidecar/` | Task definition with OTel sidecar |

---

## Data Flow

### Telemetry Signals

1. **Metrics**: App → OTel SDK → Agent (OTLP) → Gateway → Mimir (PromQL-compatible)
2. **Logs**: App log files / Event Logs → Agent (filelog/windowseventlog) → Gateway → Loki (LogQL)
3. **Traces**: App → OTel SDK → Agent (OTLP) → Gateway (tail sampling) → Tempo (TraceQL)

### Cross-Signal Correlation

- **Metrics → Traces**: Exemplars in Prometheus metrics contain trace IDs
- **Logs → Traces**: Loki derived fields extract `traceID` from structured logs
- **Traces → Logs**: Tempo correlations link to Loki using trace ID
- **Traces → Metrics**: Tempo metrics generator creates RED metrics from spans

---

## Auto-Instrumentation

### EKS (via OTel Operator)
Add annotations to pod specs:
```yaml
instrumentation.opentelemetry.io/inject-java: "true"    # Java
instrumentation.opentelemetry.io/inject-dotnet: "true"   # .NET Core
instrumentation.opentelemetry.io/inject-nodejs: "true"   # Node.js
```

### ECS / EC2 / On-Prem
Set environment variables in task definition or service config:

**Java:**
```
JAVA_TOOL_OPTIONS=-javaagent:/opt/opentelemetry-javaagent.jar
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

**.NET Core:**
```
CORECLR_ENABLE_PROFILING=1
CORECLR_PROFILER={918728DD-259F-4A6A-AC2B-B85E1B658318}
CORECLR_PROFILER_PATH=/opt/otel-dotnet/OpenTelemetry.AutoInstrumentation.Native.so
OTEL_SERVICE_NAME=my-service
```

**Node.js:**
```
NODE_OPTIONS=--require @opentelemetry/auto-instrumentations-node/register
OTEL_SERVICE_NAME=my-service
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

### Legacy Apps (no code changes)
Agent-only collection. No distributed tracing. Available signals:
- Host metrics (CPU, memory, disk, network)
- Application log files (parsed by filelog receiver)
- Windows Event Logs
- IIS metrics (if applicable)
- Prometheus `/metrics` endpoint (if exposed)

---

## Sampling Strategy

| Traffic Type | Head (Agent) | Tail (Gateway) | Net Result |
|---|---|---|---|
| Error spans | 100% | 100% | All errors kept |
| High latency (>1s) | 50% | 100% | ~50% kept |
| Normal traffic | 5% | 2% | ~0.1% kept |
| Health checks | 0% | N/A | Dropped |

---

## Deployment

### Prerequisites
1. AWS account with appropriate permissions
2. Terraform >= 1.5
3. Helm >= 3.12
4. kubectl configured for EKS
5. Ansible >= 2.14 (for on-prem)
6. Direct Connect established to on-prem

### Deployment Order
1. `terraform apply` — networking, EKS, S3, IAM
2. `helm install` — Mimir, Loki, Tempo, Grafana
3. `helm install` — OTel Operator, Gateway
4. `kubectl apply` — Instrumentation CR, DaemonSet CR
5. Terraform modules — EC2 agents (user data)
6. Terraform modules — ECS sidecar task definitions
7. `ansible-playbook` — On-prem Linux + Windows agents
