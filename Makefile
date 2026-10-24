TF      := terraform -chdir=terraform
REGION  := $(shell $(TF) output -raw region 2>/dev/null || echo eu-west-1)
CLUSTER := $(shell $(TF) output -raw eks_cluster_name 2>/dev/null || echo duckstore-prod-eks)

.DEFAULT_GOAL := help
.PHONY: help init plan apply destroy output kubeconfig status install-argocd install-kargo apply-gitops dev-backend dev-frontend

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# --- Infrastructure ----------------------------------------------------------

init: ## terraform init
	$(TF) init

plan: ## terraform plan
	$(TF) plan

apply: ## terraform apply
	$(TF) apply

destroy: ## Tear down infrastructure
	$(TF) destroy

output: ## Show Terraform outputs
	$(TF) output

# --- Operations & Cluster Access ---------------------------------------------

kubeconfig: ## Update local kubeconfig for the EKS cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)

status: ## Show cluster workload status
	kubectl get pods,svc,ingress -n frontend
	@echo "---"
	kubectl get pods,svc,pvc,storageclass -n backend

# --- GitOps Bootstrapping (Argo CD & Kargo) -----------------------------------

install-argocd: ## Install Argo CD into the cluster
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

install-kargo: ## Install Kargo via Helm
	helm repo add akuity https://akuity.github.io/kargo-charts
	helm repo update
	helm upgrade --install kargo akuity/kargo --namespace kargo --create-namespace

apply-gitops: ## Apply Kargo and Argo CD manifests
	kubectl apply -f kargo/project.yaml
	@if [ -f kargo/secrets.yaml ]; then kubectl apply -f kargo/secrets.yaml; else echo "Note: kargo/secrets.yaml not found. Copy from kargo/secrets.yaml.template"; fi
	kubectl apply -f kargo/warehouse.yaml
	kubectl apply -f kargo/stage-prod.yaml
	kubectl apply -f argocd/application.yaml

# --- Local Development -------------------------------------------------------

dev-backend: ## Run API locally on :3001
	cd app/backend && npm install && DB_PATH=./local.db PORT=3001 node server.js

dev-frontend: ## Run frontend locally on :3002
	cd app/frontend && npm install && PORT=3002 BACKEND_URL=http://127.0.0.1:3001 node server.js
