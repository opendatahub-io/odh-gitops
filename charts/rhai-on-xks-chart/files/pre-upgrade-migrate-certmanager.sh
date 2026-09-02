#!/bin/bash
# Pre-upgrade hook for cert-manager migration.
# Adopts existing cert-manager resources into the current Helm release.
#
# Expected env vars:
#   RELEASE_NAME      - Current Helm release name
#   RELEASE_NAMESPACE - Current Helm release namespace

set -euo pipefail

# ── Migration path: adopt existing cert-manager resources into this release ──

# Check if cert-manager namespaces exist - if not, nothing to migrate
if ! kubectl get namespace cert-manager &>/dev/null && ! kubectl get namespace cert-manager-operator &>/dev/null; then
  echo "No cert-manager namespaces found; skipping migration."
  exit 0
fi

echo "Migrating cert-manager resources to release '${RELEASE_NAME}'..."

FAILURES=0

resource_is_ccm_managed() {
  local ns_args="$1"
  local resource="$2"
  local part_of

  part_of=$(kubectl get $ns_args "$resource" -o jsonpath='{.metadata.labels.infrastructure\.opendatahub\.io/part-of}' 2>/dev/null || true)
  [[ -n "$part_of" ]]
}

adopt_resource() {
  local ns_args="$1"
  local resource="$2"

  if ! kubectl get $ns_args "$resource" &>/dev/null; then
    echo "  Skipping ${resource} ${ns_args} (not found)"
    return
  fi

  OWNER=$(kubectl get $ns_args "$resource" -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}' 2>/dev/null || true)
  if [[ "$OWNER" == "${RELEASE_NAME}" ]]; then
    return
  fi

  if ! resource_is_ccm_managed $ns_args "$resource"; then
    echo "  Skipping ${resource} ${ns_args} (not CCM-managed)"
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

# Adopt each resource the cert-manager-operator subchart creates.
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

echo "Migration complete."
