TF      := terraform -chdir=terraform
REGION  := $(shell $(TF) output -raw region 2>/dev/null || echo eu-west-1)
CLUSTER := $(shell $(TF) output -raw eks_cluster_name 2>/dev/null || echo duckstore-prod-eks)

.DEFAULT_GOAL := help
.PHONY: help init plan apply destroy output kubeconfig status dev-backend dev-frontend

help: ## Show help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

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

# --- Operations --------------------------------------------------------------

kubeconfig: ## Update local kubeconfig for the EKS cluster
	aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER)

status: ## Show cluster workload status
	kubectl get pods,svc,ingress -n frontend
	@echo "---"
	kubectl get pods,svc,pvc,storageclass -n backend

# --- Local Development -------------------------------------------------------

dev-backend: ## Run API locally on :3001
	cd app/backend && npm install && DB_PATH=./local.db PORT=3001 node server.js

dev-frontend: ## Run frontend locally on :3002
	cd app/frontend && npm install && PORT=3002 BACKEND_URL=http://127.0.0.1:3001 node server.js
