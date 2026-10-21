# K3s Infrastructure & Deployment Pipeline

A production-style decoupled architecture provisioning a single-node K3s Kubernetes cluster on AWS EC2 using Terraform, with containerized microservices deployed via GitHub Actions (`.github/workflows/deploy.yml`) and AWS Systems Manager (SSM).

---

## Architecture

The system decouples infrastructure provisioning from software delivery:

```
[ Developer / Git Push to main ]
                │
                ▼
[ GitHub Actions (.github/workflows/deploy.yml) ]
  ├── 1. validate: Node.js syntax & Terraform validation
  ├── 2. build-and-push: Docker images to GHCR (tagged with Git SHA and latest)
  └── 3. deploy: AWS SSM send-command -> EC2 (dynamically resolves Role=k3s-server)
                                            │
                                            ▼
                           [ AWS EC2 Instance: K3s Server ]
                             ├── Syncs & applies Kubernetes manifests (k8s/)
                             ├── Updates Deployments to Git SHA images
                             └── Verifies rollout status completion
```

### Components

1. **Infrastructure (Terraform in `terraform/`)**
   - **VPC & Networking:** Custom VPC (`10.0.0.0/16`), single public subnet (`10.0.1.0/24`), Internet Gateway, and Route Table.
   - **Compute:** Single EC2 instance (`t3.small`, Ubuntu 24.04 LTS) running K3s (control plane and worker on one node).
   - **Persistence & Lifecycle Protection:** `user_data_replace_on_change = false` with `ignore_changes = [user_data, ami]` to protect persistent local-path volumes (SQLite database) from accidental destruction during script updates or upstream AMI upgrades.
   - **Access & Security:** Static Elastic IP (EIP) mapped to the instance. Ingress Security Group opens ports 80 (HTTP) and 443 (HTTPS) to Traefik. Port 22 (SSH) and 6443 (Kubernetes API) remain closed by default.
   - **IAM & Instance Profile:** Attached with `AmazonSSMManagedInstanceCore` for agent-based management via AWS SSM (no bastion or open SSH ports required). IMDSv2 is strictly enforced.
   - **Hardened K3s Bootstrap (`user_data.sh`):** Installs base packages, AWS CLI, and K3s with default `0600` root-only kubeconfig permissions, preventing unprivileged processes from obtaining cluster-admin rights.

2. **Workloads (Kubernetes manifests in `k8s/`)**
   - **`backend` namespace:** Persistent SQLite volume (`PersistentVolumeClaim` backed by `local-path`), `duck-api` Deployment (single replica, Recreate strategy), and internal `ClusterIP` Service on port 3000.
   - **`frontend` namespace:** Stateless `duck-web` Deployment (2 replicas, RollingUpdate strategy), internal `ClusterIP` Service on port 80.
   - **Resource Management:** Memory requests and limits are strictly enforced to protect host memory. CPU limits are intentionally omitted to avoid Linux CFS quota throttling and latency spikes.
   - **Ingress:** Traefik Ingress routing external HTTP/HTTPS traffic to the frontend Service. Frontend queries backend internally via cluster DNS (`duck-api.backend.svc.cluster.local:3000`).

3. **Continuous Integration & Continuous Delivery (`.github/workflows/deploy.yml`)**
   - **`validate`**: Runs static syntax checks on Node.js application files (`node --check`) and Terraform configuration (`terraform fmt -check`, `terraform validate`).
   - **`build-and-push`**: Compiles Docker container images for both frontend and backend, pushes them to GitHub Container Registry (GHCR), and tags each with `${{ github.sha }}` and `latest`.
   - **`deploy`**: Authenticates to AWS, dynamically looks up the running instance ID by tag `Role=k3s-server`, synchronizes `k8s/*.yaml` manifests, updates image tags, and awaits rollout completion using `aws ssm wait command-executed`.

---

## Prerequisites

- **Terraform:** `>= 1.5.0`
- **AWS CLI:** `v2` configured with administrative permissions.
- **Node.js:** `>= 22.0.0` (for local development and validation).
- **Docker:** `>= 24.0` (for local container builds).
- **AWS SSM Session Manager Plugin:** Installed locally for shell access without SSH.
- **GitHub Repository Secrets (for CI/CD):**
  - `AWS_ACCESS_KEY_ID`: IAM access key with EC2 describe and SSM execution permissions.
  - `AWS_SECRET_ACCESS_KEY`: Corresponding secret access key.
  - `GITHUB_TOKEN`: Provided automatically by GitHub Actions with package write permissions.

---

## Quickstart

### 1. Provision Infrastructure

```bash
# Clone the repository
git clone <repository-url>
cd duckstore

# Configure variables
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Modify terraform/terraform.tfvars if required (region, instance type, etc.)

# Initialize and validate
terraform -chdir=terraform init
terraform -chdir=terraform validate

# Plan and apply
terraform -chdir=terraform plan -out=tfplan
terraform -chdir=terraform apply tfplan
```

Review the outputs for the allocated Elastic IP and store URL:
```bash
terraform -chdir=terraform output
```

### 2. Verify Node Bootstrap

Connect to the instance via AWS SSM:
```bash
aws ssm start-session \
  --target $(terraform -chdir=terraform output -raw instance_id) \
  --region $(terraform -chdir=terraform output -raw region)
```

Check bootstrap execution (commands on the host require `sudo` due to `0600` kubeconfig permissions):
```bash
cat /opt/duckstore/.bootstrap-status
sudo kubectl get nodes -o wide
```

### 3. Deploy Workloads via CI/CD

Push changes to the `main` branch to trigger the pipeline (`.github/workflows/deploy.yml`):
```bash
git add .
git commit -m "feat: infrastructure and deployment updates"
git push origin main
```

Monitor execution under the **Actions** tab in GitHub:
1. **validate:** Ensures Node.js and Terraform syntax standards.
2. **build-and-push:** Builds images and pushes them to GHCR.
3. **deploy:** Syncs manifests, updates deployment image tags, and waits for rollout:
   ```bash
   sudo kubectl -n backend rollout status deployment/duck-api
   sudo kubectl -n frontend rollout status deployment/duck-web
   ```

### 4. Teardown

To decommission all cloud resources and prevent ongoing costs:
```bash
terraform -chdir=terraform destroy -auto-approve
```
