#!/bin/bash
# Pre-upgrade hook: migrate cert-manager from CCM management to Helm subchart.
#
# When upgrading from 3.5 (cert-manager managed by CCM) to 3.6 (cert-manager
# as Helm subchart), this hook:
#   1. Adopts resources from a previous cert-manager Helm release, when present
#   2. Otherwise patches the active KubernetesEngine CR to set
#      certManager.managementPolicy=Unmanaged and waits for CCM cleanup
#   3. Shortens the stale leader-election Lease so the Helm-managed replacement
#      can acquire leadership without waiting for the old Lease to expire
#
# Expected env vars:
#   RELEASE_NAME      - Current Helm release name
#   RELEASE_NAMESPACE    - Current Helm release namespace
#   CERT_MANAGER_ENABLED - Whether the cert-manager subchart is enabled

set -euo pipefail

WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

# Cleanup is needed when the cert-manager subchart is disabled on upgrade.
if [[ "${CERT_MANAGER_ENABLED:-true}" == "false" ]]; then
  if kubectl get certmanager cluster &>/dev/null; then
    echo "Cleaning up cert-manager before disabling subchart..."
    kubectl patch certmanager cluster --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl delete certmanager cluster --timeout=30s 2>/dev/null || true
  fi
  echo "Deleting cert-manager operand deployments..."
  kubectl delete deployments -n cert-manager --all --timeout=60s 2>/dev/null || true
  echo "Removing cert-manager namespaces..."
  kubectl delete namespace cert-manager --ignore-not-found --timeout=60s 2>/dev/null || true
  kubectl delete namespace cert-manager-operator --ignore-not-found --timeout=60s 2>/dev/null || true
  echo "Cert-manager cleanup complete."
  exit 0
fi

# A previous standalone cert-manager Helm release needs to be adopted into the
# parent release before Helm renders the subchart resources. This is also the
# path used by the migration E2E test, which simulates CCM with a Helm release.
OLD_RELEASE="cert-manager-operator"
OLD_SECRETS=$(kubectl get secrets -A -l "owner=helm,name=${OLD_RELEASE}" \
  -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)

if [[ -n "$OLD_SECRETS" ]]; then
  echo "Migrating cert-manager resources to release '${RELEASE_NAME}'..."
  FAILURES=0

  adopt_resource() {
    local ns_args="$1"
    local resource="$2"

    if ! kubectl get $ns_args "$resource" &>/dev/null; then
      echo "  Skipping ${resource} ${ns_args} (not found)"
      return
    fi

    OWNER=$(kubectl get $ns_args "$resource" \
      -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)
    if [[ "$OWNER" == "${RELEASE_NAME}" ]]; then
      return
    fi

    echo "  Patching ${resource} ${ns_args}..."
    if ! kubectl annotate $ns_args "$resource" \
      meta.helm.sh/release-name="${RELEASE_NAME}" \
      meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" \
      --overwrite 2>&1; then
      echo "    FAILED to patch annotations on ${resource}"
      FAILURES=$((FAILURES + 1))
      return
    fi
    if ! kubectl label $ns_args "$resource" \
      app.kubernetes.io/managed-by=Helm \
      --overwrite 2>&1; then
      echo "    FAILED to patch label on ${resource}"
      FAILURES=$((FAILURES + 1))
    fi
  }

  adopt_resource "" "namespace/cert-manager-operator"
  adopt_resource "" "namespace/cert-manager"
  adopt_resource "-n cert-manager-operator" "serviceaccount/cert-manager-operator-controller-manager"
  adopt_resource "-n cert-manager" "serviceaccount/cert-manager"
  adopt_resource "-n cert-manager" "serviceaccount/cert-manager-cainjector"
  adopt_resource "-n cert-manager" "serviceaccount/cert-manager-webhook"
  adopt_resource "" "clusterrole/cert-manager-operator-controller-manager-clusterrole"
  adopt_resource "" "clusterrole/cert-manager-operator-metrics-reader"
  adopt_resource "" "clusterrolebinding/cert-manager-operator-controller-manager-clusterrolebinding"
  adopt_resource "-n cert-manager-operator" "role/cert-manager-operator-controller-manager-role"
  adopt_resource "-n cert-manager-operator" "rolebinding/cert-manager-operator-controller-manager-rolebinding"
  adopt_resource "-n cert-manager-operator" "service/cert-manager-operator-controller-manager-metrics-service"
  adopt_resource "-n cert-manager-operator" "deployment.apps/cert-manager-operator-controller-manager"
  adopt_resource "" "certmanager/cluster"

  if [[ "$FAILURES" -gt 0 ]]; then
    echo "ERROR: ${FAILURES} resource(s) failed to patch. Will retry (backoffLimit=3)."
    exit 1
  fi

  echo "  Deleting old release secrets for '${OLD_RELEASE}'..."
  kubectl delete secrets -A -l "owner=helm,name=${OLD_RELEASE}" 2>/dev/null || true
  echo "Migration complete."
  exit 0
fi

# Check if cert-manager-operator namespace exists at all.
if ! kubectl get namespace cert-manager-operator &>/dev/null; then
  echo "cert-manager-operator namespace not found; nothing to migrate."
  exit 0
fi

# KE_RESOURCE and KE_NAME are injected by the Helm Job template (provider-specific).
if [[ -z "${KE_RESOURCE:-}" ]] || [[ -z "${KE_NAME:-}" ]]; then
  echo "KE_RESOURCE or KE_NAME not set; skipping migration."
  exit 0
fi

KE_FULL="${KE_RESOURCE}/${KE_NAME}"

if ! kubectl get "$KE_FULL" &>/dev/null 2>&1; then
  echo "KubernetesEngine CR '${KE_FULL}' not found; skipping migration."
  exit 0
fi

echo "Found KubernetesEngine CR: ${KE_FULL}"

# Check current managementPolicy — only migrate if CCM is actively managing cert-manager.
# If already Unmanaged, nothing to do.
CURRENT_POLICY=$(kubectl get "$KE_FULL" \
  -o jsonpath='{.spec.dependencies.certManager.managementPolicy}' 2>/dev/null || true)

if [[ "$CURRENT_POLICY" != "Managed" ]]; then
  echo "certManager.managementPolicy is '${CURRENT_POLICY}'; nothing to migrate."
  exit 0
fi

# Patch KE CR to set certManager.managementPolicy=Unmanaged.
# This tells CCM to stop managing cert-manager and clean up its resources.
echo "Patching ${KE_FULL}: certManager.managementPolicy → Unmanaged..."
kubectl patch "$KE_FULL" --type=merge \
  -p '{"spec":{"dependencies":{"certManager":{"managementPolicy":"Unmanaged"}}}}' 2>&1

# Wait for CCM's foreground deletion of the cert-manager operator Deployment.
# No wait is needed when CCM has already removed it before the hook starts.
if ! deployment_names=$(kubectl get deployment -n cert-manager-operator \
  -l infrastructure.opendatahub.io/part-of -o name 2>&1); then
  echo "ERROR: Could not query the CCM cert-manager-operator Deployment: ${deployment_names}" >&2
  exit 1
fi
if [[ -n "$deployment_names" ]]; then
  echo "Waiting for CCM to remove cert-manager-operator deployment (timeout: ${WAIT_TIMEOUT}s)..."
  if kubectl wait --for=delete deployment -n cert-manager-operator \
    -l infrastructure.opendatahub.io/part-of --timeout="${WAIT_TIMEOUT}s"; then
    echo "cert-manager-operator deployment removed."
  elif ! remaining_deployment_names=$(kubectl get deployment -n cert-manager-operator \
    -l infrastructure.opendatahub.io/part-of -o name 2>&1); then
    echo "ERROR: Could not query the CCM cert-manager-operator Deployment after waiting: ${remaining_deployment_names}" >&2
    exit 1
  elif [[ -z "$remaining_deployment_names" ]]; then
    echo "cert-manager-operator deployment removed while starting the wait."
  else
    echo "ERROR: Timeout waiting for cert-manager-operator deployment to be removed."
    kubectl get deployment -n cert-manager-operator \
      -l infrastructure.opendatahub.io/part-of 2>/dev/null || true
    exit 1
  fi
else
  echo "cert-manager-operator deployment not found; continuing."
fi

# CCM cleanup can remove the old operator's RBAC before it gracefully releases
# this Lease. Foreground Deployment deletion waits for its blocking dependents.
if kubectl get lease cert-manager-operator-lock -n cert-manager-operator &>/dev/null; then
  echo "Shortening stale cert-manager-operator-lock Lease duration to 1 second..."
  if ! kubectl patch lease cert-manager-operator-lock -n cert-manager-operator \
    --type=merge \
    -p '{"spec":{"leaseDurationSeconds":1}}' 2>&1; then
    echo "WARNING: Could not shorten cert-manager-operator-lock Lease; continuing migration."
  fi
else
  echo "cert-manager-operator-lock Lease not found; nothing to shorten."
fi
echo "Migration complete. The replacement cert-manager operator will reconcile any remaining operands."
