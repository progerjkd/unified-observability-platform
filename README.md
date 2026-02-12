# Unified Observability Platform

Vendor-neutral observability platform providing **metrics, logs, and traces** across ~500 compute instances spanning AWS and on-premises infrastructure. Uses [OpenTelemetry](https://opentelemetry.io/) for collection and the Grafana **LGTM stack** (Mimir, Loki, Tempo, Grafana) as the backend.

## Architecture

```
 COMPUTE INSTANCES (~500)
 ┌──────────────────────────────────────────────────────────────┐
 │  EKS · ECS Fargate · ECS EC2 · EC2 · On-Prem (Linux/Win)     │
 │                                                              │
 │  App + OTel SDK Auto-Instrumentation (Java/.NET/Node.js)     │
 │  Legacy Apps → Agent-only (host metrics, logs, events)       │
 │              ┌─────────────────────┐                         │
 │              │  OTel Agent (local) │                         │
 │              └────────┬────────────┘                         │
 └───────────────────────┼──────────────────────────────────────┘
                         │ OTLP gRPC :4317
           ┌─────────────┴──────────────┐
           │     OTel Gateway (3x)      │
           │  Tail sampling · Filtering │
           └─────────────┬──────────────┘
                         │ OTLP HTTP
     ┌───────────────────┼───────────────────┐
     │                   │                   │
 ┌───▼─────┐     ┌──────▼──┐      ┌────────▼──┐
 │  Mimir  │     │  Loki   │      │  Tempo    │
 │ Metrics │     │  Logs   │      │  Traces   │
 └───┬─────┘     └────┬────┘      └─────┬─────┘
     └────────────┬───┴─────────────────┘
              S3 Buckets
     ┌────────────▼────────────────────┐
     │           Grafana               │
     │  Dashboards · Alerts · Explore  │
     └─────────────────────────────────┘
```

See [docs/architecture.md](docs/architecture.md) for the full architecture, component inventory, data flow, auto-instrumentation guide, and sampling strategy.

## Supported Platforms

| Platform        | Agent Deployment            | Config                                         |
| --------------- | --------------------------- | ---------------------------------------------- |
| EKS Linux       | DaemonSet via OTel Operator | `helm/otel-operator/collector-daemonset.yaml`  |
| ECS Fargate     | Sidecar container           | `configs/otel-agent-fargate.yaml`              |
| ECS EC2 Linux   | ECS daemon task             | `configs/otel-agent-linux.yaml`                |
| ECS EC2 Windows | Windows Service (MSI)       | `configs/otel-agent-windows.yaml`              |
| EC2 Linux       | systemd service             | `configs/otel-agent-linux.yaml`                |
| EC2 Windows     | Windows Service (MSI)       | `configs/otel-agent-windows.yaml`              |
| On-prem Linux   | systemd (Ansible)           | `ansible/templates/otel-agent-linux.yaml.j2`   |
| On-prem Windows | Windows Service (Ansible)   | `ansible/templates/otel-agent-windows.yaml.j2` |

## Prerequisites

- AWS account with appropriate IAM permissions
- Terraform >= 1.5
- Helm >= 3.12
- kubectl
- Ansible >= 2.14 (for on-prem deployments)
- Docker (for config validation)
- Direct Connect established between on-prem and AWS

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

This creates the VPC, EKS cluster, S3 buckets, IAM roles, internal NLB, and Route53 private zone.

### 3. Deploy the LGTM stack and OTel collection layer

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
│   └── otel-gateway/                   # OTel Gateway Collector (tail sampling, fan-out)
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
├── ansible/
│   ├── playbooks/                      # install-otel-linux.yml, install-otel-windows.yml
│   ├── templates/                      # Jinja2 agent configs + systemd unit
│   └── inventory/                      # hosts.yml (edit with your on-prem hosts)
├── docs/
│   └── architecture.md                 # Full architecture documentation
└── Makefile                            # All deployment targets
```

## Auto-Instrumentation

### EKS (via OTel Operator)

Add annotations to pod specs — no code changes required:

```yaml
instrumentation.opentelemetry.io/inject-java: "true" # Java
instrumentation.opentelemetry.io/inject-dotnet: "true" # .NET Core
instrumentation.opentelemetry.io/inject-nodejs: "true" # Node.js
```

### ECS / EC2 / On-Prem

Set environment variables in task definitions or service configs:

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

### Legacy Apps (no code changes possible)

Agent-only collection — no distributed tracing, but provides:

- Host metrics (CPU, memory, disk, network)
- Application log file parsing
- Windows Event Logs
- IIS metrics (if applicable)
- Prometheus `/metrics` scraping (if exposed)

## Sampling Strategy

| Traffic Type       | Head (Agent) | Tail (Gateway) | Net Result      |
| ------------------ | ------------ | -------------- | --------------- |
| Error spans        | 100%         | 100%           | All errors kept |
| High latency (>1s) | 50%          | 100%           | ~50% kept       |
| Normal traffic     | 5%           | 2%             | ~0.1% kept      |
| Health checks      | 0%           | N/A            | Dropped         |

## Alerting

Alert rules are defined in `configs/alert-rules.yaml` and cover four categories:

- **Service health** — error rate > 5%, p99 latency > 2s, traffic drop > 90%
- **Infrastructure** — CPU/memory > 90%, disk > 85%/95%
- **OTel pipeline** — agent down, gateway queue > 80%, export failures, drop rate > 10%
- **LGTM backend** — unhealthy Mimir ingesters, Loki ingestion spike, Tempo compactor stalled

Routing (`configs/alertmanager.yaml`): critical alerts go to PagerDuty, warnings to Slack.

## Cross-Signal Correlation

Grafana is pre-configured with links between all three signals:

- **Metrics → Traces**: Click exemplar data points to jump to the corresponding trace in Tempo
- **Logs → Traces**: Derived fields extract `traceID` from structured logs to link to Tempo
- **Traces → Logs**: View logs associated with a trace inline via Tempo-to-Loki correlation
- **Traces → Metrics**: Tempo metrics generator produces RED metrics queryable in Mimir

## Make Targets

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
```

## Deployment Order

1. `terraform apply` — networking, EKS, S3, IAM
2. `helm install` — Mimir, Loki, Tempo, Grafana
3. `helm install` — OTel Operator, Gateway
4. `kubectl apply` — Instrumentation CR, DaemonSet CR
5. Terraform modules — EC2 agents (user data)
6. Terraform modules — ECS sidecar task definitions
7. `ansible-playbook` — On-prem Linux + Windows agents
