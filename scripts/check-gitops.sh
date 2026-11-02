#!/usr/bin/env bash
# Verifies the Argo CD + Argo CD Image Updater pipeline is actually healthy
# on the live cluster, instead of inferring it from Git/CI alone (which can't
# see in-cluster state like credentials, pod health, or sync status).
#
# Usage: ./scripts/check-gitops.sh
# Exit code: 0 if every check passes, 1 if any check fails.

set -uo pipefail

PASS=0
FAIL=0

check() {
  local name="$1"
  local result="$2"
  local detail="${3:-}"
  if [ "$result" = "ok" ]; then
    printf "  \033[32m✓\033[0m %-40s %s\n" "$name" "$detail"
    PASS=$((PASS + 1))
  else
    printf "  \033[31m✗\033[0m %-40s %s\n" "$name" "$detail"
    FAIL=$((FAIL + 1))
  fi
}

echo "== Cluster connectivity =="
if kubectl cluster-info >/dev/null 2>&1; then
  check "kubectl can reach the cluster" ok
else
  check "kubectl can reach the cluster" fail "run 'make kubeconfig' first"
  echo
  echo "Cannot continue without cluster access. Aborting."
  exit 1
fi

echo
echo "== Argo CD core components (namespace: argocd) =="
for deploy in argocd-server argocd-repo-server argocd-application-controller; do
  ready=$(kubectl get deploy "$deploy" -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
  desired=$(kubectl get deploy "$deploy" -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
  if [ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
    check "$deploy" ok "$ready/$desired ready"
  else
    check "$deploy" fail "${ready:-0}/${desired:-?} ready -- not found or not healthy"
  fi
done
# argocd-application-controller is a StatefulSet in some install manifests, not a Deployment
if ! kubectl get deploy argocd-application-controller -n argocd >/dev/null 2>&1; then
  ready=$(kubectl get statefulset argocd-application-controller -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
  desired=$(kubectl get statefulset argocd-application-controller -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
  if [ -n "$ready" ] && [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
    check "argocd-application-controller (statefulset)" ok "$ready/$desired ready"
  else
    check "argocd-application-controller (statefulset)" fail "${ready:-0}/${desired:-?} ready"
  fi
fi

echo
echo "== Argo CD Image Updater =="
iu_ready=$(kubectl get deploy argocd-image-updater -n argocd -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "")
iu_desired=$(kubectl get deploy argocd-image-updater -n argocd -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "")
if [ -n "$iu_ready" ] && [ "$iu_ready" = "$iu_desired" ] && [ "$iu_ready" != "0" ]; then
  check "argocd-image-updater deployment" ok "$iu_ready/$iu_desired ready"
else
  check "argocd-image-updater deployment" fail "not installed or not healthy -- see 'make install-image-updater'"
fi

echo
echo "== duckstore Application sync/health =="
sync_status=$(kubectl get application duckstore -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "")
health_status=$(kubectl get application duckstore -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")
if [ "$sync_status" = "Synced" ]; then
  check "Application sync status" ok "Synced"
else
  check "Application sync status" fail "${sync_status:-not found}"
fi
if [ "$health_status" = "Healthy" ]; then
  check "Application health status" ok "Healthy"
else
  check "Application health status" fail "${health_status:-not found}"
fi

echo
echo "== Image Updater recent activity (last 5 min of logs) =="
if kubectl get deploy argocd-image-updater -n argocd >/dev/null 2>&1; then
  logs=$(kubectl logs -n argocd deploy/argocd-image-updater --since=5m 2>/dev/null || echo "")
  if echo "$logs" | grep -qi "duckstore"; then
    check "mentions the duckstore app" ok
  else
    check "mentions the duckstore app" fail "no recent log lines referencing duckstore -- may not have polled yet (default interval 2m) or image-list annotation isn't matching"
  fi
  if echo "$logs" | grep -qiE "error|unauthorized|authentication required|could not list tags|permission denied"; then
    echo "$logs" | grep -iE "error|unauthorized|authentication required|could not list tags|permission denied" | tail -5 | sed 's/^/      /'
    check "no auth/registry errors in recent logs" fail "see lines above -- likely missing IRSA for ECR or Git write-back credentials"
  else
    check "no auth/registry errors in recent logs" ok
  fi
else
  check "Image Updater log check" fail "deployment not found, skipped"
fi

echo
echo "== Workload pods =="
for ns in frontend backend; do
  not_ready=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | awk '$2 !~ /^([0-9]+)\/\1$/ || $3 != "Running" {print $1}')
  if [ -z "$not_ready" ]; then
    check "pods in $ns namespace" ok "all Running/Ready"
  else
    check "pods in $ns namespace" fail "not ready: $not_ready"
  fi
done

echo
echo "================================================================"
echo "  $PASS passed, $FAIL failed"
echo "================================================================"
[ "$FAIL" -eq 0 ]
