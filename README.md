# AWS EKS Infrastructure & GitOps Continuous Promotion Pipeline

An enterprise-grade decoupled architecture provisioning a highly available Amazon EKS cluster on AWS using Terraform, with containerized microservices published to AWS ECR and continuously promoted via Kargo and Argo CD.

---

## Architecture

The system decouples infrastructure provisioning, continuous integration, and continuous promotion using GitOps:

```
[ Developer / Git Push to main (app/ changes) ]
                      │
                      ▼
[ GitHub Actions (.github/workflows/deploy.yml) ]
  ├── 1. validate: Node.js syntax & Terraform validation
  └── 2. build-and-push: Multi-stage Docker images to AWS ECR (Git SHA & latest)
                                │
                                ▼
                     [ AWS ECR Repositories ]
               (duckstore-backend & duckstore-frontend)
                                │
                                ▼
                    [ Kargo Continuous Promotion ]
                      ├── 1. Warehouse: monitors ECR digests
                      ├── 2. Stage (prod): clones Git repo
                      ├── 3. yaml-update: updates k8s/*.yaml
                      └── 4. git-commit & push [skip ci]
                                │
                                ▼
                     [ Git Repository (main) ]
                                │
                                ▼
                  [ Argo CD (GitOps Controller) ]
                      ├── Auto-syncs k8s/ manifests
                      └── Enforces desired state & self-healing
                                │
                                ▼
                  [ Amazon EKS Cluster (Prod) ]
                    ├── Multi-AZ Managed Node Groups
                    ├── AWS EBS CSI Driver (gp3 volumes)
                    └── AWS ALB Ingress (duck-web & duck-api)
```

### Components

1. **Infrastructure (Terraform in `terraform/`)**
   - **VPC & Networking:** Custom VPC (`10.0.0.0/16`), Multi-AZ subnets across 2 Availability Zones (2 Public `10.0.1.0/24`, `10.0.2.0/24` with Internet Gateway; 2 Private `10.0.10.0/24`, `10.0.20.0/24` with AWS NAT Gateway). Subnets are tagged for AWS Load Balancer Controller integration (`kubernetes.io/role/elb = 1` and `kubernetes.io/role/internal-elb = 1`). Detailed network specifications are documented in `VPC_README.md`.
   - **Compute (Amazon EKS):** Managed Kubernetes control plane (`duckstore-prod-eks`, Kubernetes v1.31) with cluster creator admin permissions enabled via EKS access entries. Managed Node Group (`t3.medium`, auto-scaling min 1, desired 2, max 4) distributed across private subnets with IMDSv2 enforced.
   - **Container Registry (AWS ECR in `terraform/ecr.tf`):** Dedicated private repositories for `duckstore-backend` and `duckstore-frontend` with image scanning on push enabled (`scan_on_push = true`) and a lifecycle policy retaining the last 10 tagged images while expiring untagged images.
   - **Storage & CSI Driver:** OpenID Connect (OIDC) provider and IAM Roles for Service Accounts (IRSA) provisioning the AWS EBS CSI Driver add-on (`aws_eks_addon.ebs_csi`), enabling automated dynamic provisioning of persistent `gp3` volumes.

2. **Workloads & Security (Kubernetes manifests in `k8s/`)**
   - **`backend` namespace:** Persistent SQLite volume (`PersistentVolumeClaim` backed by `gp3` EBS CSI), `duck-api` Deployment (single replica, Recreate strategy, `imagePullPolicy: Always`), and internal `ClusterIP` Service on port 3000.
   - **`frontend` namespace:** Stateless `duck-web` Deployment (2 replicas, RollingUpdate strategy, `imagePullPolicy: Always`), internal `ClusterIP` Service on port 80.
   - **Network Isolation (`k8s/40-network-policy.yaml`):** Hardened `NetworkPolicy` in namespace `backend` denying arbitrary ingress and strictly permitting incoming traffic on port 3000 only from Pods matching `app: duck-web` in namespace `frontend`.
   - **Ingress (`k8s/30-ingress.yaml`):** AWS Application Load Balancer via AWS Load Balancer Controller (`ingressClassName: alb`, `scheme: internet-facing`, `target-type: ip`) routing root HTTP traffic `/` directly to the `duck-web` service with automated health checking on `/healthz`.

3. **Continuous Integration (GitHub Actions in `.github/workflows/deploy.yml`)**
   - **Infinite Loop Prevention:** Configured `paths-ignore` for `k8s/**`, `kargo/**`, `argocd/**`, and documentation (`*.md`), preventing GitOps promotion commits from triggering redundant CI image builds.
   - **`validate` job:** Runs static syntax checks on Node.js backend/frontend (`node --check`) and validates Terraform code (`terraform fmt -check`, `terraform validate`).
   - **`build-and-push` job:** Compiles multi-stage container images, authenticates to AWS ECR, and pushes images tagged with both the immutable Git commit SHA (`${{ github.sha }}`) and `latest`.

4. **Continuous Promotion & GitOps (Kargo & Argo CD)**
   - **Kargo (`kargo/`):**
     - `duckstore-warehouse`: Subscribes to newly pushed container image digests from both ECR repositories.
     - `prod` Stage: Executes automated promotion steps (`git-clone`, `yaml-update` for `10-backend.yaml` and `20-frontend.yaml` with the discovered freight image tags, and `git-commit` with `[skip ci]` followed by `git-push` to `main`).
     - `secrets.yaml`: Configures repository access tokens and ECR image registry credentials labeled for Kargo (`kargo.akuity.io/cred-type: git` and `image`).
   - **Argo CD (`argocd/application.yaml`):**
     - Declarative `Application` monitoring the `k8s/` directory on `main`.
     - Continuous auto-synchronization with `prune: true`, `selfHeal: true`, and exponential retry backoff.

---

## Prerequisites

- **Terraform:** `>= 1.5.0`
- **AWS CLI:** `v2` configured with administrative permissions.
- **kubectl:** `>= 1.30.0`
- **Helm:** `>= 3.12.0` (for installing Argo CD and Kargo).
- **Node.js:** `>= 22.0.0` (for local development and validation).
- **Docker:** `>= 24.0` (for local container builds).
- **GitHub Repository Secrets (for CI/CD):**
  - `AWS_ACCESS_KEY_ID`: IAM access key with permissions to push to AWS ECR.
  - `AWS_SECRET_ACCESS_KEY`: Corresponding AWS secret access key.

---

## Quickstart

### 1. Provision Infrastructure

```bash
# Clone the repository
git clone <repository-url>
cd duckstore

# Configure variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Modify terraform/terraform.tfvars if required (region, instance types, etc.)

# Initialize and validate
terraform -chdir=terraform init
terraform -chdir=terraform validate

# Plan and apply
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
```

Review the outputs for ECR URLs, EKS endpoint, and kubeconfig update command:
```bash
terraform -chdir=terraform output
```

### 2. Connect to the EKS Cluster

```bash
# Update local kubeconfig
aws eks update-kubeconfig \
  --region $(terraform -chdir=terraform output -raw region) \
  --name $(terraform -chdir=terraform output -raw eks_cluster_name)

# Verify cluster connectivity and worker nodes
kubectl get nodes -o wide
```

### 3. Bootstrap GitOps (Argo CD & Kargo)

Install Argo CD and Kargo on the cluster (or use `make install-argocd && make install-kargo`):

```bash
# Install Argo CD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD server readiness
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Retrieve initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Install Kargo via Helm
helm repo add akuity https://akuity.github.io/kargo-charts
helm repo update
helm upgrade --install kargo akuity/kargo --namespace kargo --create-namespace --wait
```

### 4. Configure Credentials & Apply GitOps Workflows

Configure credentials and apply the GitOps pipeline (or run `make apply-gitops`):

```bash
# 1. Create Kargo Project
kubectl apply -f kargo/project.yaml

# 2. Configure Git & ECR credentials
cp kargo/secrets.yaml.template kargo/secrets.yaml
# Edit kargo/secrets.yaml with your GitHub Personal Access Token (PAT with repo write permissions)
kubectl apply -f kargo/secrets.yaml

# 3. Apply Kargo Warehouse & Production Stage
kubectl apply -f kargo/warehouse.yaml
kubectl apply -f kargo/stage-prod.yaml

# 4. Apply Argo CD Application
kubectl apply -f argocd/application.yaml
```

### 5. Trigger CI & Verify Continuous Promotion

Push changes in `app/` to trigger the pipeline (`.github/workflows/deploy.yml`):

```bash
git add app/
git commit -m "feat: update duckstore catalog"
git push origin main
```

Monitor execution:
1. **CI Pipeline (GitHub Actions):** Validates syntax, builds Docker images, and pushes to AWS ECR.
2. **Kargo Promotion:** Detects new image digests, updates `k8s/10-backend.yaml` and `k8s/20-frontend.yaml`, and commits to `main` with `[skip ci]`.
3. **Argo CD:** Automatically synchronizes updated manifests to the EKS cluster:
   ```bash
   kubectl get application duckstore -n argocd
   kubectl get pods -n backend
   kubectl get pods -n frontend
   ```

### 6. Teardown

To decommission all cloud resources and prevent ongoing costs:

```bash
terraform -chdir=terraform destroy -auto-approve
```
