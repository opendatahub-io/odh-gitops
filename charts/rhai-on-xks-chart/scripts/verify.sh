#!/bin/bash
# Verify rhai-on-xks-chart installation in a Kubernetes cluster.
#
# Environment variables:
#   RELEASE_NAME     - Helm release name (default: rhai-on-xks)
#   NAMESPACE        - Helm release namespace (default: rhai-on-xks)
#   CLOUD_PROVIDER   - Cloud provider: azure or coreweave (default: azure)
#   TIMEOUT          - Max wait time in seconds per check (default: 300)

set -euo pipefail

RELEASE_NAME="${RELEASE_NAME:-rhai-on-xks}"
NAMESPACE="${NAMESPACE:-rhai-on-xks}"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-azure}"
TIMEOUT="${TIMEOUT:-300}"
if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: TIMEOUT must be a positive integer" >&2
  exit 1
fi
INTERVAL=10

ERRORS=0

log_ok()   { echo "  OK: $1"; }
log_fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }

wait_for() {
  local description="$1"
  shift
  local elapsed=0
  while [ $elapsed -lt "$TIMEOUT" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    echo "  Waiting for ${description}... (${elapsed}s/${TIMEOUT}s)"
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
  done
  return 1
}

wait_for_deployment() {
  local name="$1"
  local ns="$2"
  local expected_replicas="${3:-}"

  if ! wait_for "deployment ${name} in ${ns}" kubectl get deployment "${name}" -n "${ns}"; then
    log_fail "Deployment '${name}' not found in '${ns}'"
    return 1
  fi

  if ! wait_for "deployment ${name} rollout" kubectl rollout status deployment "${name}" -n "${ns}" --timeout=0s; then
    log_fail "Deployment '${name}' in '${ns}' did not become ready within ${TIMEOUT}s"
    kubectl get deployment "${name}" -n "${ns}" -o wide 2>/dev/null || true
    kubectl get pods -n "${ns}" 2>/dev/null || true
    return 1
  fi

  if [ -n "${expected_replicas}" ]; then
    actual=$(kubectl get deployment "${name}" -n "${ns}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    if [ "${actual:-0}" -ne "${expected_replicas}" ]; then
      log_fail "Deployment '${name}' in '${ns}': expected ${expected_replicas} replicas, got ${actual:-0}"
      return 1
    fi
  fi

  log_ok "Deployment '${name}' in '${ns}' is ready"
  return 0
}

wait_for_all_deployments_in_namespace() {
  local ns="$1"
  local deployments
  if ! wait_for "deployments in ${ns}" kubectl get deployments -n "${ns}" -o name; then
    log_fail "No deployments found in namespace '${ns}'"
    return 1
  fi

  deployments=$(kubectl get deployments -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  if [ -z "${deployments}" ]; then
    log_fail "No deployments found in namespace '${ns}'"
    return 1
  fi

  while IFS= read -r deploy; do
    [ -z "${deploy}" ] && continue
    wait_for_deployment "${deploy}" "${ns}"
  done <<< "${deployments}"
}

echo "=== Verifying rhai-on-xks-chart Installation ==="
echo "Release: ${RELEASE_NAME} | Namespace: ${NAMESPACE} | Cloud: ${CLOUD_PROVIDER}"
echo ""

# --- Helm release ---
echo "--- Helm Release ---"
if helm list -n "${NAMESPACE}" 2>/dev/null | grep -qF "${RELEASE_NAME}"; then
  log_ok "Helm release '${RELEASE_NAME}' found"
else
  log_fail "Helm release '${RELEASE_NAME}' not found in namespace '${NAMESPACE}'"
fi

# --- Namespaces ---
echo "--- Namespaces ---"
EXPECTED_NAMESPACES=("redhat-ods-operator" "redhat-ods-applications" "${NAMESPACE}")
if [ "${CLOUD_PROVIDER}" = "azure" ] || [ "${CLOUD_PROVIDER}" = "coreweave" ]; then
  EXPECTED_NAMESPACES+=("rhai-cloudmanager-system")
fi

for ns in "${EXPECTED_NAMESPACES[@]}"; do
  if kubectl get namespace "${ns}" >/dev/null 2>&1; then
    log_ok "Namespace '${ns}' exists"
  else
    log_fail "Namespace '${ns}' not found"
  fi
done

# --- CRDs ---
echo "--- CRDs ---"
if kubectl get crd kserves.components.platform.opendatahub.io >/dev/null 2>&1; then
  log_ok "CRD 'kserves.components.platform.opendatahub.io' exists"
else
  log_fail "CRD 'kserves.components.platform.opendatahub.io' not found"
fi

if [ "${CLOUD_PROVIDER}" = "azure" ]; then
  if kubectl get crd azurekubernetesengines.infrastructure.opendatahub.io >/dev/null 2>&1; then
    log_ok "CRD 'azurekubernetesengines.infrastructure.opendatahub.io' exists"
  else
    log_fail "CRD 'azurekubernetesengines.infrastructure.opendatahub.io' not found"
  fi
  if kubectl get crd coreweavekubernetesengines.infrastructure.opendatahub.io >/dev/null 2>&1; then
    log_fail "CRD 'coreweavekubernetesengines.infrastructure.opendatahub.io' should NOT exist for azure provider"
  else
    log_ok "CRD 'coreweavekubernetesengines.infrastructure.opendatahub.io' correctly absent"
  fi
elif [ "${CLOUD_PROVIDER}" = "coreweave" ]; then
  if kubectl get crd coreweavekubernetesengines.infrastructure.opendatahub.io >/dev/null 2>&1; then
    log_ok "CRD 'coreweavekubernetesengines.infrastructure.opendatahub.io' exists"
  else
    log_fail "CRD 'coreweavekubernetesengines.infrastructure.opendatahub.io' not found"
  fi
  if kubectl get crd azurekubernetesengines.infrastructure.opendatahub.io >/dev/null 2>&1; then
    log_fail "CRD 'azurekubernetesengines.infrastructure.opendatahub.io' should NOT exist for coreweave provider"
  else
    log_ok "CRD 'azurekubernetesengines.infrastructure.opendatahub.io' correctly absent"
  fi
fi

# --- Step 1: Cloud manager deployment ---
echo "--- Cloud Manager ---"
CM_NS="rhai-cloudmanager-system"
if [ "${CLOUD_PROVIDER}" = "azure" ]; then
  wait_for_deployment "azure-cloud-manager-operator" "${CM_NS}" 1
  if kubectl get deployment coreweave-cloud-manager-operator -n "${CM_NS}" >/dev/null 2>&1; then
    log_fail "Deployment 'coreweave-cloud-manager-operator' should NOT exist for azure provider"
  else
    log_ok "Deployment 'coreweave-cloud-manager-operator' correctly absent"
  fi
elif [ "${CLOUD_PROVIDER}" = "coreweave" ]; then
  wait_for_deployment "coreweave-cloud-manager-operator" "${CM_NS}" 1
  if kubectl get deployment azure-cloud-manager-operator -n "${CM_NS}" >/dev/null 2>&1; then
    log_fail "Deployment 'azure-cloud-manager-operator' should NOT exist for coreweave provider"
  else
    log_ok "Deployment 'azure-cloud-manager-operator' correctly absent"
  fi
fi

# --- Step 2: Infrastructure deployments ---
echo "--- Infrastructure Deployments ---"
infra_deployments=$(kubectl get deployments -A -l infrastructure.opendatahub.io/part-of -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null || echo "")
if [ -z "${infra_deployments}" ]; then
  echo "  No deployments with label 'infrastructure.opendatahub.io/part-of' found yet, waiting..."
  if wait_for "infrastructure deployments" bash -c "kubectl get deployments -A -l infrastructure.opendatahub.io/part-of -o name 2>/dev/null | grep -q ."; then
    infra_deployments=$(kubectl get deployments -A -l infrastructure.opendatahub.io/part-of -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}{"\n"}{end}' 2>/dev/null)
  fi
fi

if [ -n "${infra_deployments}" ]; then
  while IFS= read -r entry; do
    [ -z "${entry}" ] && continue
    ns="${entry%%/*}"
    name="${entry##*/}"
    wait_for_deployment "${name}" "${ns}"
  done <<< "${infra_deployments}"
else
  log_fail "No infrastructure deployments found"
fi

# --- Step 3: cert-manager deployments ---
echo "--- cert-manager ---"
wait_for_all_deployments_in_namespace "cert-manager"

# --- Step 4: rhai-operator ---
echo "--- RHAI Operator ---"
wait_for_deployment "rhai-operator" "redhat-ods-operator" 3

# --- Step 5: Applications namespace deployments ---
echo "--- Applications ---"
wait_for_all_deployments_in_namespace "redhat-ods-applications"

# --- Summary ---
echo ""
echo "==============================="
if [ $ERRORS -eq 0 ]; then
  echo "All checks passed"
  exit 0
else
  echo "${ERRORS} check(s) failed"
  exit 1
fi
