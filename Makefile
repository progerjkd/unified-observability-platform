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
HELM_TIMEOUT   ?= 3m
HELM_TIMEOUT_DEMO ?= 15m
ORG_PREFIX     ?= obs-platform
AWS_PROFILE    ?= default
DEMO_APP_DIR   := demo/sample-apps/nodejs-shop
DEMO_SERVICES  := frontend product-api inventory
IMAGE_TAG      ?= latest
ECR_REGISTRY    = $(shell aws sts get-caller-identity --query Account --output text).dkr.ecr.$(AWS_REGION).amazonaws.com
HELM_RETRIES   ?= 3

# Helm install with retry — handles cold-start failures when cluster autoscaler
# is still provisioning nodes (pods fail once, Helm --wait treats it as fatal)
define helm_install_retry
	@for i in $$(seq 1 $(HELM_RETRIES)); do \
		echo ">>> Attempt $$i/$(HELM_RETRIES): helm upgrade --install $(1)"; \
		if helm upgrade --install $(1) $(2) \
			--namespace $(K8S_NAMESPACE) \
			$(3) \
			--timeout $(HELM_TIMEOUT_DEMO) \
			--wait; then \
			break; \
		else \
			if [ $$i -eq $(HELM_RETRIES) ]; then \
				echo ">>> FAILED after $(HELM_RETRIES) attempts"; \
				exit 1; \
			fi; \
			echo ">>> Retrying in 15s (waiting for nodes to be ready)..."; \
			sleep 15; \
		fi; \
	done
endef

# ------- Help -------

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

# ------- Infrastructure (Terraform) -------

.PHONY: tf-init tf-plan tf-plan-demo tf-plan-demo-ondemand tf-apply tf-apply-demo tf-destroy

tf-init: ## Initialize Terraform
	cd terraform && terraform init

tf-plan: ## Plan Terraform changes (production sizing)
	cd terraform && terraform plan -out=tfplan

tf-plan-demo: ## Plan Terraform changes (demo sizing — Spot instances)
	cd terraform && terraform plan -var-file=demo.tfvars -out=tfplan

tf-plan-demo-ondemand: ## Plan Terraform changes (demo sizing — On-Demand fallback)
	cd terraform && terraform plan -var-file=demo.tfvars -var-file=demo-ondemand.tfvars -out=tfplan

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

# ------- ArgoCD (visualization) -------

.PHONY: install-argocd-demo argocd-apps-demo argocd-password

install-argocd-demo: ## Install ArgoCD (demo — minimal resources)
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	@for i in $$(seq 1 $(HELM_RETRIES)); do \
		echo ">>> Attempt $$i/$(HELM_RETRIES): helm upgrade --install argocd"; \
		if helm upgrade --install argocd argo/argo-cd \
			--namespace argocd \
			--values helm/argocd/values-demo.yaml \
			--timeout $(HELM_TIMEOUT_DEMO) \
			--wait; then \
			break; \
		else \
			if [ $$i -eq $(HELM_RETRIES) ]; then echo ">>> FAILED after $(HELM_RETRIES) attempts"; exit 1; fi; \
			echo ">>> Retrying in 15s..."; sleep 15; \
		fi; \
	done

argocd-apps-demo: ## Create ArgoCD Applications for demo components
	kubectl apply -f helm/argocd/applications-demo.yaml

argocd-password: ## Retrieve ArgoCD admin password
	@echo "ArgoCD admin password:"
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

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
	$(call helm_install_retry,mimir,grafana/mimir-distributed,--version 5.8.0 --values helm/mimir/values.yaml --values helm/mimir/values-demo.yaml)

install-loki-demo: ## Install Loki (demo sizing — monolithic mode)
	$(call helm_install_retry,loki,grafana/loki,--values helm/loki/values-demo-simple.yaml)

install-tempo-demo: ## Install Tempo (demo sizing — distributed, 1 replica)
	$(call helm_install_retry,tempo,grafana/tempo-distributed,--values helm/tempo/values-demo-distributed.yaml)

install-grafana-demo: ## Install Grafana (demo sizing)
	$(call helm_install_retry,grafana,grafana/grafana,--values helm/grafana/values-demo-simple.yaml)

install-lgtm-demo: install-mimir-demo install-loki-demo install-tempo-demo install-grafana-demo ## Install LGTM stack (demo sizing)

# ------- OTel Collection (Helm + kubectl) -------

.PHONY: install-otel-operator install-otel-gateway install-otel-gateway-demo install-otel-daemonset install-instrumentation install-instrumentation-default install-otel-agent-rbac install-otel install-otel-demo

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
	$(call helm_install_retry,otel-gateway,open-telemetry/opentelemetry-collector,--values helm/otel-gateway/values.yaml --values helm/otel-gateway/values-demo.yaml)

install-otel-daemonset: ## Deploy OTel DaemonSet via Operator CR
	kubectl apply -f helm/otel-operator/collector-daemonset.yaml

install-instrumentation: ## Deploy auto-instrumentation CR
	kubectl apply -f helm/otel-operator/instrumentation.yaml

install-otel: install-otel-operator install-otel-gateway install-otel-daemonset install-instrumentation ## Install full OTel collection layer

install-otel-agent-rbac: ## Create ClusterRole/Binding for OTel agent (k8sattributes, kubeletstats)
	kubectl apply -f helm/otel-operator/agent-rbac.yaml

install-instrumentation-default: ## Deploy auto-instrumentation CR in default namespace
	kubectl apply -f helm/otel-operator/instrumentation-default.yaml

install-otel-demo: install-otel-operator install-otel-gateway-demo install-otel-daemonset install-instrumentation install-otel-agent-rbac ## Install OTel collection (demo sizing)

# ------- Cluster Autoscaler -------

.PHONY: install-cluster-autoscaler-demo

install-cluster-autoscaler-demo: ## Install Cluster Autoscaler (demo — scales 2-4 nodes)
	helm upgrade --install cluster-autoscaler autoscaler/cluster-autoscaler \
		--namespace kube-system \
		--values helm/cluster-autoscaler/values-demo.yaml \
		--timeout $(HELM_TIMEOUT_DEMO) \
		--wait

# ------- Alerting -------

.PHONY: install-alerts install-dashboards

install-alerts: ## Upload alert rules to Mimir
	@echo "Uploading alert rules to Mimir via Job..."
	kubectl delete job mimir-upload-alerts -n $(K8S_NAMESPACE) 2>/dev/null || true
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

.PHONY: deploy-all deploy-all-demo undeploy-demo deploy-quick-demo-app ecr-login build-demo-images push-demo-images

deploy-all: kubeconfig namespace install-lgtm install-otel install-alerts install-dashboards ## Deploy everything (production sizing)
	@echo ""
	@echo "=== Deployment complete (PRODUCTION) ==="
	@echo "Grafana: kubectl -n $(K8S_NAMESPACE) port-forward svc/grafana 3000:80"
	@echo "Gateway: gateway.observability.internal:4317"

deploy-quick-demo-app: ## Deploy quick demo app + load generator
	kubectl apply -f demo/quick-demo-app.yaml

deploy-all-demo: kubeconfig-demo namespace install-cluster-autoscaler-demo install-lgtm-demo install-otel-demo install-instrumentation-default install-alerts install-dashboards deploy-quick-demo-app ## Deploy everything (demo sizing — minimal resources)
	@echo ""
	@echo "=== Deployment complete (DEMO) ==="
	@echo "Grafana: kubectl -n $(K8S_NAMESPACE) port-forward svc/grafana 3000:80"
	@echo "  Login: admin / demo-admin-2025"
	@echo "Gateway: otel-gateway-opentelemetry-collector.$(K8S_NAMESPACE).svc:4317"

undeploy-demo: ## Remove all demo Helm releases, CRs, and demo apps
	@echo "Removing demo apps..."
	-kubectl delete -f demo/quick-demo-app.yaml --ignore-not-found 2>/dev/null
	-kubectl delete deployment frontend product-api inventory --ignore-not-found 2>/dev/null
	-kubectl delete service frontend product-api inventory --ignore-not-found 2>/dev/null
	@echo "Removing Instrumentation CRs..."
	-kubectl delete instrumentation otel-instrumentation -n default --ignore-not-found 2>/dev/null
	-kubectl delete instrumentation otel-instrumentation -n $(K8S_NAMESPACE) --ignore-not-found 2>/dev/null
	@echo "Removing OTel DaemonSet CR..."
	-kubectl delete opentelemetrycollector otel-agent -n $(K8S_NAMESPACE) --ignore-not-found 2>/dev/null
	@echo "Removing agent RBAC..."
	-kubectl delete -f helm/otel-operator/agent-rbac.yaml --ignore-not-found 2>/dev/null
	@echo "Removing alert rules job and configmaps..."
	-kubectl delete job mimir-upload-alerts -n $(K8S_NAMESPACE) --ignore-not-found 2>/dev/null
	-kubectl delete configmap mimir-alert-rules -n $(K8S_NAMESPACE) --ignore-not-found 2>/dev/null
	-kubectl delete configmap grafana-dashboards -n $(K8S_NAMESPACE) --ignore-not-found 2>/dev/null
	@echo "Uninstalling Helm releases..."
	-helm uninstall otel-gateway -n $(K8S_NAMESPACE) 2>/dev/null
	-helm uninstall opentelemetry-operator -n $(K8S_NAMESPACE) 2>/dev/null
	-helm uninstall grafana -n $(K8S_NAMESPACE) 2>/dev/null
	-helm uninstall tempo -n $(K8S_NAMESPACE) 2>/dev/null
	-helm uninstall loki -n $(K8S_NAMESPACE) 2>/dev/null
	-helm uninstall mimir -n $(K8S_NAMESPACE) 2>/dev/null
	-helm uninstall cluster-autoscaler -n kube-system 2>/dev/null
	@echo "Deleting PVCs..."
	-kubectl delete pvc --all -n $(K8S_NAMESPACE) 2>/dev/null
	@echo ""
	@echo "=== Demo undeployed ==="
	@echo "Run 'make deploy-all-demo' to redeploy from scratch"

# ------- Demo App Images (Docker + ECR) -------

.PHONY: ecr-login build-demo-images push-demo-images

ecr-login: ## Authenticate Docker to ECR
	aws ecr get-login-password --region $(AWS_REGION) | docker login --username AWS --password-stdin $(ECR_REGISTRY)

build-demo-images: ## Build all demo app images (ARM64 for Graviton nodes)
	@for svc in $(DEMO_SERVICES); do \
		echo "Building $$svc (linux/arm64)..."; \
		docker buildx build \
			--platform linux/arm64 \
			-t $(ECR_REGISTRY)/$(ORG_PREFIX)-demo/$$svc:$(IMAGE_TAG) \
			$(DEMO_APP_DIR)/$$svc \
			--load; \
	done
	@echo "All demo images built."

push-demo-images: ecr-login ## Push all demo app images to ECR
	@for svc in $(DEMO_SERVICES); do \
		echo "Pushing $$svc..."; \
		docker push $(ECR_REGISTRY)/$(ORG_PREFIX)-demo/$$svc:$(IMAGE_TAG); \
	done
	@echo "All demo images pushed to ECR."

# ------- Demo Apps -------

.PHONY: deploy-demo-apps destroy-demo-apps

deploy-demo-apps: ## Deploy sample apps + load generator for demo
	@ECR_URI=$(ECR_REGISTRY)/$(ORG_PREFIX)-demo; \
	for svc in $(DEMO_SERVICES); do \
		echo "Deploying $$svc with image $$ECR_URI/$$svc:$(IMAGE_TAG)..."; \
		sed "s|YOUR_REGISTRY|$$ECR_URI|g" $(DEMO_APP_DIR)/$$svc/deployment.yaml | kubectl apply -f -; \
	done
	kubectl apply -f demo/sample-apps/legacy-nginx/deployment.yaml
	-kubectl delete job load-generator -n $(K8S_NAMESPACE) --ignore-not-found --wait=true 2>/dev/null
	kubectl apply -f demo/sample-apps/load-generator.yaml
	@echo ""
	@echo "=== Demo apps deployed ==="
	@echo "Load generator running — dashboards will populate in ~5 minutes"

destroy-demo-apps: ## Remove sample apps + load generator
	kubectl delete -f demo/sample-apps/load-generator.yaml --ignore-not-found
	kubectl delete -f demo/sample-apps/legacy-nginx/deployment.yaml --ignore-not-found
	-kubectl delete deployment frontend product-api inventory --ignore-not-found
	-kubectl delete service frontend product-api inventory --ignore-not-found

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
	helm repo add autoscaler https://kubernetes.github.io/autoscaler
	helm repo add argo https://argoproj.github.io/argo-helm
	helm repo update

# ------- Teardown -------

.PHONY: teardown-demo cleanup-orphaned-resources

cleanup-orphaned-resources: ## Clean up orphaned AWS resources (S3 objects, EBS volumes)
	@echo "Cleaning up orphaned AWS resources..."
	@./scripts/empty-s3-only.sh $(AWS_PROFILE)
	@./scripts/cleanup-ebs-volumes.sh $(AWS_PROFILE) obs-lgtm-demo

teardown-demo: ## Destroy demo environment completely
	@echo "WARNING: This will destroy the demo EKS cluster + all AWS resources. Press Ctrl+C to cancel."
	@sleep 5
	@echo "Emptying S3 buckets (required before destroy)..."
	@./scripts/empty-s3-only.sh $(AWS_PROFILE)
	@echo "Removing Kubernetes namespace from Terraform state (avoid timeout)..."
	-cd terraform && terraform state rm module.eks.kubernetes_namespace.observability 2>/dev/null || true
	@echo "Running Terraform destroy..."
	cd terraform && terraform destroy -var-file=demo.tfvars -auto-approve
	@echo "Cleaning up orphaned EBS volumes (post-destroy)..."
	@./scripts/cleanup-ebs-volumes.sh $(AWS_PROFILE) obs-lgtm-demo
