# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

Infrastructure-as-Code for a unified observability platform (metrics, logs, traces) spanning ~500 compute instances across AWS (EKS, ECS Fargate, ECS EC2, bare EC2) and on-premises (Linux + Windows). Uses OpenTelemetry for collection and the Grafana LGTM stack (Mimir/Loki/Tempo) as backend. See `docs/architecture.md` for the full architecture.

## Commands

```bash
make help                  # Show all available targets

# Infrastructure
make tf-init && make tf-plan && make tf-apply   # Deploy AWS infra (VPC, EKS, S3, IAM)

# Backend + Collection (requires EKS to be up)
make helm-repos            # Add Grafana + OTel Helm repos (one-time)
make deploy-all            # Full deploy: LGTM stack + OTel gateway/operator + alerts + dashboards

# Individual components
make install-lgtm          # Just the backend (Mimir, Loki, Tempo, Grafana)
make install-otel          # Just the collection layer (Operator, Gateway, DaemonSet, Instrumentation CR)

# On-prem agents
make deploy-onprem         # Ansible: install OTel agents on on-prem Linux + Windows hosts

# Validation
make validate              # Validate all OTel Collector configs via Docker
make test-pipeline         # Send synthetic traces/metrics/logs via telemetrygen
```

Terraform vars go in `terraform/terraform.tfvars` (see `terraform/terraform.tfvars.example`). The `org_prefix` variable is required — it prefixes S3 bucket names for global uniqueness.

## Architecture — Three Layers

**Collection → Gateway → Backend**

1. **Collection layer** — OTel Collector agents on every compute instance, one config per platform type:
   - `configs/otel-agent-linux.yaml` — EC2 Linux, ECS EC2 Linux (systemd, hostmetrics, filelog, syslog)
   - `configs/otel-agent-windows.yaml` — EC2/ECS EC2/On-prem Windows (MSI, hostmetrics, windowseventlog, iis)
   - `configs/otel-agent-fargate.yaml` — ECS Fargate sidecar (awsecscontainermetrics)
   - `configs/otel-agent-eks.yaml` — Standalone DaemonSet config (alternative to Operator-managed version)
   - `helm/otel-operator/collector-daemonset.yaml` — **Primary** EKS agent: Operator-managed DaemonSet with kubeletstats, k8sattributes, filelog
   - On-prem agents use Jinja2 templates in `ansible/templates/` with host-specific vars

2. **Gateway layer** — `helm/otel-gateway/values.yaml`: 3-replica Deployment with HPA. Receives OTLP from all agents. Performs tail sampling (100% errors, 2% normal), filters health-check spans, fans out to three backends.

3. **Backend layer** — LGTM on EKS:
   - `helm/mimir/values.yaml` → Metrics (PromQL). S3 storage via IRSA.
   - `helm/loki/values.yaml` → Logs (LogQL). S3 storage.
   - `helm/tempo/values.yaml` → Traces (TraceQL). S3 storage. Metrics generator produces RED metrics into Mimir.
   - `helm/grafana/values.yaml` → Visualization. Pre-provisioned datasources with cross-signal correlation (exemplars, derived fields, trace-to-logs).

## Key Patterns

- **All agents export OTLP to `gateway.observability.internal:4317`** — a Route53 private zone record pointing to an internal NLB (defined in `terraform/aws/networking/`).
- **IRSA for S3 access** — each LGTM component has its own IAM role mapped to a K8s service account (`terraform/aws/iam-roles/`). No static credentials.
- **Persistent queues** — agents use `file_storage` extension for disk-backed buffering during gateway outages.
- **ECS Fargate sidecars** — `terraform/modules/otel-ecs-sidecar/` creates task definitions with the app container + OTel collector sidecar. The `app_auto_instrumentation_env` variable injects language-specific env vars.
- **Auto-instrumentation on EKS** — `helm/otel-operator/instrumentation.yaml` defines the Instrumentation CR; pods opt in via annotations.
- **Terraform module composition** — `terraform/main.tf` orchestrates networking → EKS → S3 → IAM with output chaining. Agent modules (`otel-ec2-linux`, `otel-ec2-windows`) produce `user_data` outputs for EC2 launch templates.

## When Modifying

- OTel Collector configs (`configs/`) follow receivers → processors → exporters → service pipeline structure. The gateway config is duplicated in `helm/otel-gateway/values.yaml` (Helm-managed) and `configs/otel-gateway.yaml` (standalone) — keep them in sync.
- Ansible templates (`ansible/templates/*.j2`) mirror `configs/otel-agent-*.yaml` but use Jinja2 variables — changes to agent configs should be reflected in both places.
- Alert rules in `configs/alert-rules.yaml` use PromQL and reference metric names produced by OTel Collector (`system_cpu_utilization`, `otelcol_*`) and Tempo metrics generator (`traces_spanmetrics_*`).
- Grafana dashboards in `dashboards/*.json` are provisioned via ConfigMap — edit JSON directly, then `make install-dashboards`.
- Helm values reference template variables like `${org_prefix}`, `${mimir_irsa_role_arn}` — these are placeholders to be substituted during deployment (e.g., via envsubst or Helmfile).
