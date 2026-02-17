# Unified Observability Platform — Deployment Makefile
# Usage: make <target>
#
# Demo mode (minimal sizing, ~$100-150/mo):
#   make tf-plan-demo && make tf-apply
#   make deploy-all-demo
#
# Production mode (full scale, ~$1,500+/mo):
#   make tf-plan && make tf-apply
#   make deploy-all

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

.PHONY: tf-init tf-plan tf-plan-demo tf-apply tf-apply-demo tf-destroy

tf-init: ## Initialize Terraform
	cd terraform && terraform init

tf-plan: ## Plan Terraform changes (production sizing)
	cd terraform && terraform plan -out=tfplan

tf-plan-demo: ## Plan Terraform changes (demo sizing — small instances)
	cd terraform && terraform plan -var-file=demo.tfvars -out=tfplan

tf-apply: ## Apply Terraform changes (production)
	cd terraform && terraform apply tfplan

tf-apply-demo: ## Apply Terraform changes (demo — uses demo.tfvars)
	cd terraform && terraform apply -var-file=demo.tfvars -auto-approve

tf-destroy: ## Destroy Terraform infrastructure (DANGEROUS)
	@echo "WARNING: This will destroy all infrastructure. Press Ctrl+C to cancel."
	@sleep 5
	cd terraform && terraform destroy

# ------- Kubernetes Setup -------

.PHONY: kubeconfig kubeconfig-demo namespace

kubeconfig: ## Configure kubectl for the EKS cluster
	aws eks update-kubeconfig --name $(CLUSTER_NAME) --region $(AWS_REGION)

kubeconfig-demo: ## Configure kubectl for the demo EKS cluster
	@CLUSTER=$$(cd terraform && terraform output -raw eks_cluster_name 2>/dev/null || echo "obs-lgtm-demo"); \
	aws eks update-kubeconfig --name $$CLUSTER --region $(AWS_REGION)

namespace: ## Create the observability namespace
	kubectl create namespace $(K8S_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -

# ------- LGTM Backend (Helm) — Production -------

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

# ------- LGTM Backend (Helm) — Demo -------

.PHONY: install-mimir-demo install-loki-demo install-tempo-demo install-grafana-demo install-lgtm-demo

install-mimir-demo: ## Install Mimir (demo sizing)
	helm upgrade --install mimir grafana/mimir-distributed \
		--namespace $(K8S_NAMESPACE) \
		--values helm/mimir/values.yaml \
		--values helm/mimir/values-demo.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-loki-demo: ## Install Loki (demo sizing — monolithic mode)
	helm upgrade --install loki grafana/loki \
		--namespace $(K8S_NAMESPACE) \
		--values helm/loki/values-demo-simple.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-tempo-demo: ## Install Tempo (demo sizing — monolithic mode)
	helm upgrade --install tempo grafana/tempo-distributed \
		--namespace $(K8S_NAMESPACE) \
		--values helm/tempo/values-demo-distributed.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-grafana-demo: ## Install Grafana (demo sizing)
	helm upgrade --install grafana grafana/grafana \
		--namespace $(K8S_NAMESPACE) \
		--values helm/grafana/values-demo-simple.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-lgtm-demo: install-mimir-demo install-loki-demo install-tempo-demo install-grafana-demo ## Install LGTM stack (demo sizing)

# ------- OTel Collection (Helm + kubectl) -------

.PHONY: install-otel-operator install-otel-gateway install-otel-gateway-demo install-otel-daemonset install-instrumentation install-otel install-otel-demo

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

install-otel-gateway-demo: ## Install OTel Gateway (demo sizing)
	helm upgrade --install otel-gateway open-telemetry/opentelemetry-collector \
		--namespace $(K8S_NAMESPACE) \
		--values helm/otel-gateway/values.yaml \
		--values helm/otel-gateway/values-demo.yaml \
		--timeout $(HELM_TIMEOUT) \
		--wait

install-otel-daemonset: ## Deploy OTel DaemonSet via Operator CR
	kubectl apply -f helm/otel-operator/collector-daemonset.yaml

install-instrumentation: ## Deploy auto-instrumentation CR
	kubectl apply -f helm/otel-operator/instrumentation.yaml

install-otel: install-otel-operator install-otel-gateway install-otel-daemonset install-instrumentation ## Install full OTel collection layer

install-otel-demo: install-otel-operator install-otel-gateway-demo install-otel-daemonset install-instrumentation ## Install OTel collection (demo sizing)

# ------- Alerting -------

.PHONY: install-alerts install-dashboards

install-alerts: ## Upload alert rules to Mimir
	@echo "Uploading alert rules to Mimir via Job..."
	kubectl apply -f helm/mimir/alert-upload-job.yaml
	@echo "Waiting for alert upload Job to complete..."
	kubectl wait --for=condition=complete --timeout=60s job/mimir-upload-alerts -n $(K8S_NAMESPACE) || \
		(kubectl logs -l app=mimir-alert-uploader -n $(K8S_NAMESPACE) --tail=50 && exit 1)
	@echo "✅ Alert rules uploaded successfully!"

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

.PHONY: deploy-all deploy-all-demo

deploy-all: kubeconfig namespace install-lgtm install-otel install-alerts install-dashboards ## Deploy everything (production sizing)
	@echo ""
	@echo "=== Deployment complete (PRODUCTION) ==="
	@echo "Grafana: kubectl -n $(K8S_NAMESPACE) port-forward svc/grafana 3000:80"
	@echo "Gateway: gateway.observability.internal:4317"

deploy-all-demo: kubeconfig-demo namespace install-lgtm-demo install-otel-demo install-alerts install-dashboards ## Deploy everything (demo sizing — minimal resources)
	@echo ""
	@echo "=== Deployment complete (DEMO) ==="
	@echo "Grafana: kubectl -n $(K8S_NAMESPACE) port-forward svc/grafana 3000:80"
	@echo "  Login: admin / demo-admin-2025"
	@echo "Gateway: otel-gateway.$(K8S_NAMESPACE).svc:4317"

# ------- Demo Apps -------

.PHONY: deploy-demo-apps destroy-demo-apps

deploy-demo-apps: ## Deploy sample apps + load generator for demo
	kubectl apply -f demo/sample-apps/nodejs-shop/frontend/deployment.yaml
	kubectl apply -f demo/sample-apps/nodejs-shop/product-api/deployment.yaml
	kubectl apply -f demo/sample-apps/nodejs-shop/inventory/deployment.yaml
	kubectl apply -f demo/sample-apps/legacy-nginx/deployment.yaml
	kubectl apply -f demo/sample-apps/load-generator.yaml
	@echo ""
	@echo "=== Demo apps deployed ==="
	@echo "Load generator running — dashboards will populate in ~5 minutes"

destroy-demo-apps: ## Remove sample apps + load generator
	kubectl delete -f demo/sample-apps/load-generator.yaml --ignore-not-found
	kubectl delete -f demo/sample-apps/legacy-nginx/deployment.yaml --ignore-not-found
	kubectl delete -f demo/sample-apps/nodejs-shop/inventory/deployment.yaml --ignore-not-found
	kubectl delete -f demo/sample-apps/nodejs-shop/product-api/deployment.yaml --ignore-not-found
	kubectl delete -f demo/sample-apps/nodejs-shop/frontend/deployment.yaml --ignore-not-found

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

# ------- Teardown -------

.PHONY: teardown-demo cleanup-orphaned-resources

cleanup-orphaned-resources: ## Clean up orphaned AWS resources (S3 objects, EBS volumes)
	@echo "Cleaning up orphaned AWS resources..."
	@./scripts/empty-s3-only.sh odontoagil-dev
	@./scripts/cleanup-ebs-volumes.sh odontoagil-dev obs-lgtm-demo

teardown-demo: ## Destroy demo environment completely
	@echo "WARNING: This will destroy the demo EKS cluster + all AWS resources. Press Ctrl+C to cancel."
	@sleep 5
	@echo "Emptying S3 buckets (required before destroy)..."
	@./scripts/empty-s3-only.sh odontoagil-dev
	@echo "Removing Kubernetes namespace from Terraform state (avoid timeout)..."
	-cd terraform && terraform state rm module.eks.kubernetes_namespace.observability 2>/dev/null || true
	@echo "Running Terraform destroy..."
	cd terraform && terraform destroy -var-file=demo.tfvars -auto-approve
	@echo "Cleaning up orphaned EBS volumes (post-destroy)..."
	@./scripts/cleanup-ebs-volumes.sh odontoagil-dev obs-lgtm-demo
