# Unified Observability Platform — Deployment Makefile
# Usage: make <target>

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Variables (override via env or make VAR=value)
AWS_REGION     ?= us-east-1
CLUSTER_NAME   ?= obs-lgtm
K8S_NAMESPACE  ?= observability
HELM_TIMEOUT   ?= 10m

# ------- Help -------

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ------- Infrastructure (Terraform) -------

.PHONY: tf-init tf-plan tf-apply tf-destroy

tf-init: ## Initialize Terraform
	cd terraform && terraform init

tf-plan: ## Plan Terraform changes
	cd terraform && terraform plan -out=tfplan

tf-apply: ## Apply Terraform changes
	cd terraform && terraform apply tfplan

tf-destroy: ## Destroy Terraform infrastructure (DANGEROUS)
	@echo "WARNING: This will destroy all infrastructure. Press Ctrl+C to cancel."
	@sleep 5
	cd terraform && terraform destroy

# ------- Kubernetes Setup -------

.PHONY: kubeconfig namespace

kubeconfig: ## Configure kubectl for the EKS cluster
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(AWS_REGION)

namespace: ## Create the observability namespace
	kubectl create namespace $(K8S_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# ------- LGTM Backend (Helm) -------

.PHONY: install-mimir install-loki install-tempo install-grafana install-lgtm

install-mimir: ## Install Grafana Mimir
	helm upgrade --install mimir grafana/mimir-distributed \
		--namespace $(K8S_NAMESPACE) \
		--values helm/mimir/values.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-loki: ## Install Grafana Loki
	helm upgrade --install loki grafana/loki \
		--namespace $(K8S_NAMESPACE) \
		--values helm/loki/values.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-tempo: ## Install Grafana Tempo
	helm upgrade --install tempo grafana/tempo-distributed \
		--namespace $(K8S_NAMESPACE) \
		--values helm/tempo/values.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-grafana: ## Install Grafana
	helm upgrade --install grafana grafana/grafana \
		--namespace $(K8S_NAMESPACE) \
		--values helm/grafana/values.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-lgtm: install-mimir install-loki install-tempo install-grafana ## Install full LGTM stack

# ------- OTel Collection (Helm + kubectl) -------

.PHONY: install-otel-operator install-otel-gateway install-otel-daemonset install-instrumentation install-otel

install-otel-operator: ## Install OpenTelemetry Operator
	helm upgrade --install opentelemetry-operator open-telemetry/opentelemetry-operator \
		--namespace $(K8S_NAMESPACE) \
		--values helm/otel-operator/values.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-otel-gateway: ## Install OTel Gateway Collector
	helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
		--namespace $(K8S_NAMESPACE) \
		--values helm/otel-gateway/values.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-otel-daemonset: ## Deploy OTel DaemonSet via Operator CR
	kubectl apply -f helm/otel-operator/collector-daemonset.yaml

install-instrumentation: ## Deploy auto-instrumentation CR
	kubectl apply -f helm/otel-operator/instrumentation.yaml

install-otel: install-otel-operator install-otel-gateway install-otel-daemonset install-instrumentation ## Install full OTel collection layer

# ------- Alerting -------

.PHONY: install-alerts install-dashboards

install-alerts: ## Upload alert rules to Mimir
	@echo "Uploading alert rules to Mimir ruler..."
	kubectl -n $(K8S_NAMESPACE) exec deploy/mimir-ruler -- \
		mimirtool rules load --address=http://localhost:8080 configs/alert-rules.yaml

install-dashboards: ## Create Grafana dashboard ConfigMap
	kubectl -n $(K8S_NAMESPACE) create configmap grafana-dashboards \
		--from-file=dashboards/ \
		--dry-run=client -o yaml | kubectl apply -f -

# ------- On-Prem (Ansible) -------

.PHONY: deploy-onprem-linux deploy-onprem-windows deploy-onprem

deploy-onprem-linux: ## Deploy OTel agents to on-prem Linux hosts
	cd ansible && ansible-playbook playbooks/install-otel-linux.yml -i inventory/hosts.yml

deploy-onprem-windows: ## Deploy OTel agents to on-prem Windows hosts
	cd ansible && ansible-playbook playbooks/install-otel-windows.yml -i inventory/hosts.yml

deploy-onprem: deploy-onprem-linux deploy-onprem-windows ## Deploy OTel agents to all on-prem hosts

# ------- Full Deployment -------

.PHONY: deploy-all

deploy-all: kubeconfig namespace install-lgtm install-otel install-alerts install-dashboards ## Deploy everything (AWS infra must be applied first)
	@echo ""
	@echo "=== Deployment complete ==="
	@echo "Grafana: kubectl -n $(K8S_NAMESPACE) port-forward svc/grafana 3000:80"
	@echo "Gateway: gateway.observability.internal:4317"

# ------- Validation -------

.PHONY: validate test-pipeline

validate: ## Validate all configs
	@echo "Validating OTel configs..."
	@for f in configs/otel-*.yaml; do \
		echo "  Checking $$f..."; \
		docker run --rm -v $$(pwd)/configs:/configs otel/opentelemetry-collector-contrib:latest validate --config /configs/$$(basename $$f) || exit 1; \
	done
	@echo "All configs valid."

test-pipeline: ## Send test telemetry via telemetrygen
	@echo "Sending test traces..."
	docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
		traces --otlp-endpoint localhost:4317 --otlp-insecure --traces 10 --service test-service
	@echo "Sending test metrics..."
	docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
		metrics --otlp-endpoint localhost:4317 --otlp-insecure --metrics 100
	@echo "Sending test logs..."
	docker run --rm --network host ghcr.io/open-telemetry/opentelemetry-collector-contrib/telemetrygen:latest \
		logs --otlp-endpoint localhost:4317 --otlp-insecure --logs 50
	@echo "Check Grafana to verify telemetry arrived."

# ------- Helm Repos -------

.PHONY: helm-repos

helm-repos: ## Add required Helm repositories
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo update
