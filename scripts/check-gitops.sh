#!/usr/bin/env bash
# =============================================================================
# scripts/check-gitops.sh
# =============================================================================
# Verifies the health and operational status of Argo CD and Kargo CD on the
# active Kubernetes cluster, ensuring that components are 100% healthy,
# connected, and not stuck in "Progressing" or "Degraded" states.
#
# Usage: ./scripts/check-gitops.sh
# Exit code: 0 if all checks pass, 1 if any check fails.
# =============================================================================

set -uo pipefail

PASS=0
FAIL=0

check() {
  local name="$1"
  local result="$2"
  local detail="${3:-}"
  if [ "$result" = "ok" ]; then
    printf "  \033[32m✓\033[0m %-44s %s\n" "$name" "$detail"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✗\033[0m %-44s %s\n" "$name" "$detail"
    FAIL=$((FAIL + 1))
  fi
}

echo "================================================================"
echo "  Argo CD & Kargo CD GitOps Health Verification"
echo "================================================================"

echo
echo "== 1. Cluster Connectivity =="
if kubectl cluster-info >/dev/null 2>&1; then
  check "Kubernetes API server reachable" ok
else
  check "Kubernetes API server reachable" fail "cannot reach cluster via kubectl"
  echo
  echo "Aborting check: Cluster access required."
  exit 1
fi

echo
echo "== 2. Argo CD Core Components (namespace: argocd) =="
for deploy in argocd-server argocd-repo-server argocd-redis argocd-applicationset-controller; do
  ready=$(kubectl get deploy "$deploy" -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
  desired=$(kubectl get deploy "$deploy" -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
  if [ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
    check "$deploy" ok "$ready/$desired ready"
  else
    check "$deploy" fail "${ready:-0}/${desired:-?} ready"
  fi
done

# Check application-controller (Deployment or StatefulSet)
if kubectl get statefulset argocd-application-controller -n argocd >/dev/null 2>&1; then
  ready=$(kubectl get statefulset argocd-application-controller -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
  desired=$(kubectl get statefulset argocd-application-controller -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
  if [ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
    check "argocd-application-controller" ok "$ready/$desired ready"
  else
    check "argocd-application-controller" fail "${ready:-0}/${desired:-?} ready"
  fi
elif kubectl get deploy argocd-application-controller -n argocd >/dev/null 2>&1; then
  ready=$(kubectl get deploy argocd-application-controller -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
  desired=$(kubectl get deploy argocd-application-controller -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
  if [ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
    check "argocd-application-controller" ok "$ready/$desired ready"
  else
    check "argocd-application-controller" fail "${ready:-0}/${desired:-?} ready"
  fi
else
  check "argocd-application-controller" fail "not found in namespace argocd"
fi

echo
echo "== 3. Kargo CD Components (namespace: kargo) =="
for deploy in kargo-api kargo-controller kargo-management-controller; do
  ready=$(kubectl get deploy "$deploy" -n kargo -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
  desired=$(kubectl get deploy "$deploy" -n kargo -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
  if [ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
    check "$deploy" ok "$ready/$desired ready"
  else
    check "$deploy" fail "${ready:-0}/${desired:-?} ready -- see 'make install-kargo'"
  fi
done

echo
echo "== 4. Kargo Project & Pipelines (namespace: duckstore) =="
if kubectl get project duckstore >/dev/null 2>&1; then
  check "Kargo Project 'duckstore'" ok "created"
else
  check "Kargo Project 'duckstore'" fail "missing -- run 'kubectl apply -f kargo/project.yaml'"
fi

if kubectl get warehouse duckstore-warehouse -n duckstore >/dev/null 2>&1; then
  check "Kargo Warehouse 'duckstore-warehouse'" ok "created"
else
  check "Kargo Warehouse 'duckstore-warehouse'" fail "missing -- run 'kubectl apply -f kargo/warehouse.yaml'"
fi

if kubectl get stage prod -n duckstore >/dev/null 2>&1; then
  check "Kargo Stage 'prod'" ok "created"
else
  check "Kargo Stage 'prod'" fail "missing -- run 'kubectl apply -f kargo/stage-prod.yaml'"
fi

echo
echo "== 5. Argo CD Application Sync & Health =="
sync_status=$(kubectl get application duckstore -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
health_status=$(kubectl get application duckstore -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")

if [ "$sync_status" = "Synced" ]; then
  check "Application sync status" ok "Synced"
else
  check "Application sync status" fail "${sync_status:-not found}"
fi

if [ "$health_status" = "Healthy" ]; then
  check "Application health status" ok "Healthy (Out of Progressing)"
else
  check "Application health status" fail "${health_status:-Progressing or Not Found}"
fi

echo
echo "== 6. Workload Pods (Namespaces: backend & frontend) =="
for ns in backend frontend; do
  if kubectl get ns "$ns" >/dev/null 2>&1; then
    not_ready=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '$2 !~ /^([0-9]+)\/\1$/ || $3 != "Running" {print $1}' || echo "")
    if [ -z "$not_ready" ]; then
      total=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      check "Workload pods in '$ns'" ok "$total pods Running/Ready"
    else
      check "Workload pods in '$ns'" fail "unready pods: $not_ready"
    fi
  else
    check "Namespace '$ns'" fail "namespace not created"
  fi
done

echo
echo "================================================================"
echo "  Summary: $PASS passed, $FAIL failed"
echo "================================================================"

[ "$FAIL" -eq 0 ]
