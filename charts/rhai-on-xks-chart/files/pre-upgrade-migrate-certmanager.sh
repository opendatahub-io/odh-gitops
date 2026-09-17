#!/bin/bash
# Pre-upgrade hook: migrate cert-manager from CCM management to Helm subchart.
#
# When upgrading from 3.5 (cert-manager managed by CCM) to 3.6 (cert-manager
# as Helm subchart), this hook:
#   1. Patches the active KubernetesEngine CR to set certManager.managementPolicy=Unmanaged
#   2. Waits for CCM to remove the cert-manager-operator Deployment
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

# Wait for CCM to remove the cert-manager operator deployment.
echo "Waiting for CCM to clean up cert-manager-operator deployment (timeout: ${WAIT_TIMEOUT}s)..."
ELAPSED=0
while [[ $ELAPSED -lt $WAIT_TIMEOUT ]]; do
  DEPLOY_COUNT=$(kubectl get deployments -n cert-manager-operator \
    -l infrastructure.opendatahub.io/part-of \
    --no-headers 2>/dev/null | wc -l || echo "0")
  if [[ "$DEPLOY_COUNT" -eq 0 ]]; then
    echo "cert-manager-operator deployment removed."
    break
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

if [[ $ELAPSED -ge $WAIT_TIMEOUT ]]; then
  echo "ERROR: Timeout waiting for cert-manager-operator deployment to be removed."
  echo "Remaining deployments:"
  kubectl get deployments -n cert-manager-operator 2>/dev/null || true
  exit 1
fi

echo "Migration complete. Remaining cert-manager workloads will be adopted by Helm via --take-ownership."
