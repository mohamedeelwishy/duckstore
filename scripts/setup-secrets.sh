#!/usr/bin/env bash
# =============================================================================
# scripts/setup-secrets.sh
# =============================================================================
# Securely provisions credentials for Kargo CD and Kubernetes workloads
# directly into the cluster from environment variables.
#
# Under NO circumstances are plaintext secrets written to git-tracked files.
#
# Environment variables used:
#   GITHUB_USERNAME         (e.g., mohamedeelwishy)
#   GITHUB_TOKEN            (Personal Access Token with 'repo' scope)
#   AWS_ACCESS_KEY_ID       (IAM Access Key with ECR read permissions)
#   AWS_SECRET_ACCESS_KEY   (IAM Secret Key)
#   AWS_REGION              (Default: eu-west-1)
# =============================================================================

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-west-1}"
ECR_REGISTRY="307498582744.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo "== Secure GitOps Secret Provisioning =="

# 1. Prompt or load credentials securely if not already in environment
if [ -z "${GITHUB_USERNAME:-}" ]; then
  read -r -p "Enter GitHub Username: " GITHUB_USERNAME
fi

if [ -z "${GITHUB_TOKEN:-}" ]; then
  read -r -s -p "Enter GitHub Token (PAT): " GITHUB_TOKEN
  echo
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
  read -r -p "Enter AWS Access Key ID: " AWS_ACCESS_KEY_ID
fi

if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  read -r -s -p "Enter AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
  echo
fi

# Ensure target namespaces exist
kubectl create namespace duckstore --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace backend --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace frontend --dry-run=client -o yaml | kubectl apply -f -

# 2. Provision Kargo Git Credentials (namespace: duckstore)
echo "Configuring Kargo GitHub credentials..."
kubectl create secret generic github-repo-credentials \
  --namespace duckstore \
  --from-literal=repoURL="https://github.com/mohamedeelwishy/duckstore.git" \
  --from-literal=username="${GITHUB_USERNAME}" \
  --from-literal=password="${GITHUB_TOKEN}" \
  --dry-run=client -o yaml | \
  kubectl label -f - --local kargo.akuity.io/cred-type=git -o yaml | \
  kubectl apply -f -

# 3. Provision Kargo ECR Discovery Credentials (namespace: duckstore)
echo "Configuring Kargo ECR credentials..."
kubectl create secret generic ecr-credentials \
  --namespace duckstore \
  --from-literal=repoURL="${ECR_REGISTRY}" \
  --from-literal=repoURLIsRegex="false" \
  --from-literal=awsRegion="${AWS_REGION}" \
  --from-literal=awsAccessKeyID="${AWS_ACCESS_KEY_ID}" \
  --from-literal=awsSecretAccessKey="${AWS_SECRET_ACCESS_KEY}" \
  --dry-run=client -o yaml | \
  kubectl label -f - --local kargo.akuity.io/cred-type=image -o yaml | \
  kubectl apply -f -

# 4. Optional: Generate ECR Docker Registry Secret for Pod image pull
if command -v aws >/dev/null 2>&1; then
  echo "Generating ECR docker-registry pull secret for backend and frontend..."
  ECR_PASSWORD=$(AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID}" AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY}" \
    aws ecr get-login-password --region "${AWS_REGION}" 2>/dev/null || echo "")

  if [ -n "${ECR_PASSWORD}" ]; then
    for ns in backend frontend; do
      kubectl create secret docker-registry ecr-registry-secret \
        --namespace "${ns}" \
        --docker-server="${ECR_REGISTRY}" \
        --docker-username="AWS" \
        --docker-password="${ECR_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -
    done
    echo "ECR docker-registry secret provisioned in backend and frontend namespaces."
  fi
fi

echo "✓ All GitOps secrets successfully provisioned in the cluster."
