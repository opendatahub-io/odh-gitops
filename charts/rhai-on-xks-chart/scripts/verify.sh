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
ERROR_MESSAGES=()

log_ok()   { echo "  OK: $1"; }
log_fail() { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); ERROR_MESSAGES+=("$1"); }

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

wait_for_cr_ready() {
  local api_resource="$1"
  local name="$2"
  local description="${3:-${api_resource}/${name}}"

  if ! wait_for "${description} to exist" kubectl get "${api_resource}" "${name}"; then
    log_fail "${description} not found"
    return 1
  fi

  check_cr_conditions() {
    local conditions
    conditions=$(kubectl get "${api_resource}" "${name}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null)
    [ "${conditions}" = "True" ]
  }

  if ! wait_for "${description} to be Ready" check_cr_conditions; then
    log_fail "${description} did not become Ready within ${TIMEOUT}s"
    kubectl get "${api_resource}" "${name}" -o yaml 2>/dev/null || true
    return 1
  fi

  log_ok "${description} is Ready"
  return 0
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

# --- Step 2: Cloud provider CR status ---
echo "--- Cloud Provider CR ---"
if [ "${CLOUD_PROVIDER}" = "azure" ]; then
  wait_for_cr_ready "azurekubernetesengines.infrastructure.opendatahub.io" "default-azurekubernetesengine" "AzureKubernetesEngine 'default-azurekubernetesengine'"
elif [ "${CLOUD_PROVIDER}" = "coreweave" ]; then
  wait_for_cr_ready "coreweavekubernetesengines.infrastructure.opendatahub.io" "default-coreweavekubernetesengine" "CoreWeaveKubernetesEngine 'default-coreweavekubernetesengine'"
fi

# --- Step 3: cert-manager deployments ---
echo "--- cert-manager ---"
wait_for_all_deployments_in_namespace "cert-manager"

# --- Step 4: rhai-operator ---
echo "--- RHAI Operator ---"
wait_for_deployment "rhai-operator" "redhat-ods-operator" 3

# --- Step 5: KServe component CR status ---
echo "--- KServe Component ---"
wait_for_cr_ready "kserves.components.platform.opendatahub.io" "default-kserve" "Kserve 'default-kserve'"

# --- Step 6: Inference Gateway Istio ---
echo "--- Inference Gateway Istio ---"
wait_for_deployment "inference-gateway-istio" "redhat-ods-applications"

# --- Summary ---
echo ""
echo "==============================="
if [ $ERRORS -eq 0 ]; then
  echo "All checks passed"
  exit 0
else
  echo "${ERRORS} check(s) failed:"
  for msg in "${ERROR_MESSAGES[@]}"; do
    echo "  - ${msg}"
  done
  exit 1
fi
