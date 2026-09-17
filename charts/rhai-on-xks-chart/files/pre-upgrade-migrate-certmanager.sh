#!/bin/bash
# Pre-upgrade hook: migrate cert-manager from CCM management to Helm subchart.
#
# When upgrading from 3.5 (cert-manager managed by CCM) to 3.6 (cert-manager
# as Helm subchart), this hook:
#   1. Patches the active KubernetesEngine CR to set certManager.managementPolicy=Unmanaged
#   2. Waits for CCM to remove the cert-manager-operator Deployment
#   3. Shortens the stale leader-election Lease so the Helm-managed replacement
#      can acquire leadership without waiting for the old Lease to expire
#
# Expected env vars:
#   RELEASE_NAME      - Current Helm release name
#   RELEASE_NAMESPACE - Current Helm release namespace

set -euo pipefail

WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

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
