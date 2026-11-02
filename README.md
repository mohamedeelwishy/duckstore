# AWS EKS Infrastructure & GitOps Continuous Promotion Pipeline

An enterprise-grade decoupled architecture provisioning a highly available Amazon EKS cluster on AWS using Terraform, with containerized microservices published to AWS ECR and continuously promoted via Argo CD Image Updater and Argo CD.

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
                 [ Argo CD Image Updater ]
                      ├── Polls both ECR repos directly (image-list annotation)
                      ├── digest strategy tracks the :latest tag's digest
                      ├── Resolves new tag@digest for helm/duckstore/values.yaml
                      └── write-back-method: git -- commits to main
                                │
                                ▼
                     [ Git Repository (main) ]
                                │
                                ▼
                  [ Argo CD (GitOps Controller) ]
                      ├── Auto-syncs helm/duckstore Helm chart
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

2. **Workloads & Security (Helm Chart in `helm/duckstore/`)**
   - **`backend` namespace:** Persistent SQLite volume (`PersistentVolumeClaim` backed by `gp3` EBS CSI), `duck-api` Deployment (single replica, Recreate strategy, `imagePullPolicy: Always`), and internal `ClusterIP` Service on port 3000.
   - **`frontend` namespace:** Stateless `duck-web` Deployment (2 replicas, RollingUpdate strategy, `imagePullPolicy: Always`), internal `ClusterIP` Service on port 80.
   - **Network Isolation (`templates/networkpolicy.yaml`):** Hardened `NetworkPolicy` in namespace `backend` denying arbitrary ingress and strictly permitting incoming traffic on port 3000 only from Pods matching `app: duck-web` in namespace `frontend`.
   - **Ingress (`templates/ingress.yaml`):** AWS Application Load Balancer via AWS Load Balancer Controller (`ingressClassName: alb`, `scheme: internet-facing`, `target-type: ip`) routing root HTTP traffic `/` directly to the `duck-web` service with automated health checking on `/healthz`.

3. **Continuous Integration (GitHub Actions in `.github/workflows/deploy.yml`)**
   - **Infinite Loop Prevention:** Configured `paths-ignore` for `helm/**`, `argocd/**`, and documentation (`*.md`), preventing GitOps promotion commits from triggering redundant CI image builds.
   - **`validate` job:** Runs static syntax checks on Node.js backend/frontend (`node --check`) and validates Terraform code (`terraform fmt -check`, `terraform validate`).
   - **`build-and-push` job:** Compiles multi-stage container images, authenticates to AWS ECR, and pushes images tagged with both the immutable Git commit SHA (`${{ github.sha }}`) and `latest`.

4. **Continuous Promotion & GitOps (Argo CD Image Updater & Argo CD)**
   - **Argo CD Image Updater (annotations on `argocd/application.yaml`):**
     - `image-list`: subscribes directly to both `duckstore-backend` and `duckstore-frontend` ECR repositories -- no separate controller/CRDs beyond the Image Updater deployment itself.
     - `update-strategy: digest` tracks the `:latest` tag's digest (CI always pushes both `:<sha>` and `:latest`), so a new push is detected even though the tag string never changes.
     - `helm.image-name` / `helm.image-tag`: maps each tracked image to the exact Helm value keys (`backend.image.repository`/`.tag`, `frontend.image.repository`/`.tag`) to update.
     - `write-back-method: git` + `git-branch: main`: commits the resolved `tag@digest` into `helm/duckstore/values.yaml` on `main`, keeping Git as the single source of truth and the change auditable in `git log`.
     - Requires AWS credentials on the Image Updater ServiceAccount to read ECR (IRSA recommended) and Git write credentials for the push-back commit.
   - **Argo CD (`argocd/application.yaml`):**
     - Declarative `Application` monitoring the `helm/duckstore` directory on `main`.
     - Continuous auto-synchronization with `prune: true`, `selfHeal: true`, and exponential retry backoff.

---

## Prerequisites

- **Terraform:** `>= 1.5.0`
- **AWS CLI:** `v2` configured with administrative permissions.
- **kubectl:** `>= 1.30.0`
- **Helm:** not required for GitOps bootstrap itself (Argo CD / Image Updater install via raw manifests), but used by the `helm/duckstore` chart Argo CD renders.
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

### 3. Bootstrap GitOps (Argo CD & Argo CD Image Updater)

Install Argo CD and Image Updater on the cluster (or use `make install-argocd && make install-image-updater`):

```bash
# Install Argo CD
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for Argo CD server readiness
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd

# Retrieve initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

# Install Argo CD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

### 4. Configure Credentials & Apply GitOps Workflows

Configure credentials and apply the GitOps pipeline (or run `make apply-gitops`):

```bash
# 1. Grant the Image Updater ServiceAccount (argocd-image-updater, namespace argocd)
#    ECR read access -- IRSA is the recommended path (attach an IAM role with
#    AmazonEC2ContainerRegistryReadOnly to the ServiceAccount via an
#    eks.amazonaws.com/role-arn annotation), matching how the EBS CSI driver
#    is already wired up for this cluster in terraform/.

# 2. Give Image Updater write access to this Git repo for its write-back
#    commits (a Deploy Key or PAT), per:
#    https://argocd-image-updater.readthedocs.io/en/stable/configuration/git/

# 3. Apply the Argo CD Application (Image Updater annotations are already in
#    argocd/application.yaml)
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
1. **CI Pipeline (GitHub Actions):** Validates syntax, builds Docker images, and pushes to AWS ECR (`:<sha>` and `:latest`).
2. **Argo CD Image Updater:** Detects the `:latest` tag's new digest, updates `helm/duckstore/values.yaml`, and commits to `main`.
   ```bash
   kubectl logs -n argocd deploy/argocd-image-updater -f
   ```
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
