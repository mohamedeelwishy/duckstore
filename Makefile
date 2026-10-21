TF      := terraform -chdir=terraform
REGION  := $(shell $(TF) output -raw region 2>/dev/null || echo eu-west-1)
NODE_ID := $(shell $(TF) output -raw instance_id 2>/dev/null)

.DEFAULT_GOAL := help
.PHONY: help init plan apply destroy check-orphans output url ssm logs status dev-backend dev-frontend

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
	@echo ""
	@$(MAKE) --no-print-directory check-orphans

check-orphans: ## Verify no orphaned instances, Elastic IPs, or EBS volumes
	@echo "=== Instances ==="
	@aws ec2 describe-instances --region $(REGION) \
	  --filters "Name=instance-state-name,Values=running,stopped,stopping" \
	  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name]' \
	  --output text || true
	@echo "=== Elastic IPs ==="
	@aws ec2 describe-addresses --region $(REGION) \
	  --query 'Addresses[].[PublicIp,InstanceId]' --output text || true
	@echo "=== Unattached Volumes ==="
	@aws ec2 describe-volumes --region $(REGION) \
	  --filters "Name=status,Values=available" \
	  --query 'Volumes[].[VolumeId,Size]' --output text || true

output: ## Show Terraform outputs
	$(TF) output

url: ## Print store URL
	@$(TF) output -raw store_url && echo

# --- Operations --------------------------------------------------------------

ssm: ## Open an SSM session to the node
	aws ssm start-session --target $(NODE_ID) --region $(REGION)

logs: ## Tail bootstrap logs
	aws ssm start-session --target $(NODE_ID) --region $(REGION) \
	  --document-name AWS-StartInteractiveCommand \
	  --parameters command='sudo tail -f /var/log/duckstore-bootstrap.log'

status: ## Show cluster workload status
	aws ssm start-session --target $(NODE_ID) --region $(REGION) \
	  --document-name AWS-StartInteractiveCommand \
	  --parameters command='sudo kubectl get pods,svc,ingress -n frontend && sudo kubectl get pods,svc,pvc -n backend'

# --- Local Development -------------------------------------------------------

dev-backend: ## Run API locally on :3001
	cd app/backend && npm install && DB_PATH=./local.db PORT=3001 node server.js

dev-frontend: ## Run frontend locally on :3002
	cd app/frontend && npm install && PORT=3002 BACKEND_URL=http://127.0.0.1:3001 node server.js
