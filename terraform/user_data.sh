#!/usr/bin/env bash
# =============================================================================
# K3s Node Bootstrap
# =============================================================================
# Runs once via cloud-init on EC2 first boot.
# Responsible ONLY for:
#   1. System packages & tooling
#   2. Installing K3s single-node cluster
#   3. Ensuring the cluster and control plane reach Ready state
# =============================================================================

set -euo pipefail

exec > >(tee -a /var/log/duckstore-bootstrap.log) 2>&1
echo "=== Bootstrap starting at $(date -Is) ==="

ELASTIC_IP="${elastic_ip}"
K3S_VERSION="${k3s_version}"
DOMAIN_NAME="${domain_name}"
DISABLE_METRICS_SERVER="${disable_metrics_server}"

BOOTSTRAP_DIR=/opt/duckstore
STATUS_FILE="$BOOTSTRAP_DIR/.bootstrap-status"

mkdir -p "$BOOTSTRAP_DIR"
echo "starting" > "$STATUS_FILE"

fail() {
  echo "FAILED at step: $1" | tee "$STATUS_FILE"
  exit 1
}

# =============================================================================
# 1. System Packages
# =============================================================================
echo "--- Installing system packages ---"

wait_for_apt() {
  local waited=0
  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
     || fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do
    if [ "$waited" -ge 300 ]; then
      echo "apt lock still held after 300s, continuing anyway"
      return 0
    fi
    echo "waiting for apt lock... ($waited s)"
    sleep 5
    waited=$((waited + 5))
  done
}

export DEBIAN_FRONTEND=noninteractive
wait_for_apt
apt-get update -y || fail "apt-get update"

wait_for_apt
apt-get install -y ca-certificates curl unzip jq git || fail "apt-get install"

if ! command -v aws >/dev/null 2>&1; then
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    || fail "download awscli"
  unzip -q /tmp/awscliv2.zip -d /tmp || fail "unzip awscli"
  /tmp/aws/install || fail "install awscli"
  rm -rf /tmp/aws /tmp/awscliv2.zip
fi
aws --version

# =============================================================================
# 2. Install K3s
# =============================================================================
echo "--- Installing K3s ---"

INSTALL_ARGS="--tls-san $ELASTIC_IP"
if [ -n "$DOMAIN_NAME" ]; then
  INSTALL_ARGS="$INSTALL_ARGS --tls-san $DOMAIN_NAME"
fi

if [ "$DISABLE_METRICS_SERVER" = "true" ]; then
  INSTALL_ARGS="$INSTALL_ARGS --disable metrics-server"
  echo "metrics-server disabled"
fi

if [ "$K3S_VERSION" = "stable" ]; then
  curl -sfL https://get.k3s.io | INSTALL_K3S_CHANNEL=stable sh -s - $INSTALL_ARGS \
    || fail "k3s install"
else
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - $INSTALL_ARGS \
    || fail "k3s install"
fi

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' > /etc/profile.d/k3s.sh
chmod 644 /etc/profile.d/k3s.sh

# =============================================================================
# 3. Wait for Cluster Readiness
# =============================================================================
echo "--- Waiting for K3s readiness ---"

echo "Waiting for kubeconfig..."
for i in $(seq 1 60); do
  [ -f /etc/rancher/k3s/k3s.yaml ] && break
  sleep 2
done
[ -f /etc/rancher/k3s/k3s.yaml ] || fail "kubeconfig timeout"

echo "Waiting for Kubernetes API..."
api_up=0
for i in $(seq 1 60); do
  if kubectl get --raw='/readyz' >/dev/null 2>&1; then
    api_up=1
    echo "API server responsive after $((i * 5))s"
    break
  fi
  sleep 5
done
[ "$api_up" = "1" ] || fail "K3s API timeout"

echo "Waiting for node registration..."
node_seen=0
for i in $(seq 1 60); do
  if [ -n "$(kubectl get nodes -o name 2>/dev/null)" ]; then
    node_seen=1
    echo "Node registered after $((i * 5))s"
    break
  fi
  sleep 5
done
[ "$node_seen" = "1" ] || fail "Node registration timeout"

echo "Waiting for node Ready condition..."
kubectl wait --for=condition=Ready node --all --timeout=300s || fail "Node ready timeout"
kubectl get nodes -o wide

# =============================================================================
# Completion
# =============================================================================
{
  echo "ready"
  echo "finished_at=$(date -Is)"
  echo "elastic_ip=$ELASTIC_IP"
} > "$STATUS_FILE"

echo "=== Bootstrap complete at $(date -Is) ==="
