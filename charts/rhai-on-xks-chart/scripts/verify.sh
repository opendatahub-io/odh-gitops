#!/bin/bash
# Verify rhai-on-xks-chart installation and lifecycle in a Kubernetes cluster.
#
# Usage:
#   ./verify.sh              # run all tests (1-4)
#   ./verify.sh 1            # run only test 1 (install check)
#   ./verify.sh 2 4          # run tests 2 and 4
#
# Environment variables:
#   RELEASE_NAME     - Helm release name (default: rhai-on-xks)
#   NAMESPACE        - Helm release namespace (default: rhai-on-xks)
#   CLOUD_PROVIDER   - Cloud provider: azure, coreweave, or aws (default: azure)
#   TIMEOUT          - Max wait time in seconds per check (default: 300)
#   CHART            - Path to chart directory (default: ./charts/rhai-on-xks-chart)
#   VALUES_FILE      - Extra values file for helm deploy (default: empty)
#   PULL_SECRET      - Path to dockerconfigjson for image pull secret (default: empty)
#   HELM_EXTRA_ARGS  - Extra args passed to every helm deploy (default: empty, TODO: remove)
#   DELETE_TIMEOUT   - Helm uninstall timeout (default: 360s)
#   CLEANUP_WAIT     - Seconds to wait for reconciliation (default: 90)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-helpers.sh
source "${SCRIPT_DIR}/verify-helpers.sh"

# ─── Test 1: Install check ─────────────────────────────────────────────────

test_1_install_check() {
  ensure_deployed

  log "Verifying install..."

  # Helm release
  if helm list -n "${NAMESPACE}" 2>/dev/null | grep -qF "${RELEASE_NAME}"; then
    pass "Helm release '${RELEASE_NAME}' found"
  else
    fail "Helm release '${RELEASE_NAME}' not found in namespace '${NAMESPACE}'"
  fi

  # Namespaces
  for ns in "redhat-ods-operator" "redhat-ods-applications" "${NAMESPACE}" "${CM_NS}"; do
    assert_exists "Namespace '${ns}'" "namespace/${ns}"
  done

  # CRDs
  assert_exists "CRD kserves" crd/kserves.components.platform.opendatahub.io
  assert_exists "CRD ${KE_CRD}" "crd/${KE_CRD}"

  # Cloud manager deployment
  wait_for_deployment "${CLOUD_PROVIDER}-cloud-manager-operator" "${CM_NS}" 1

  # KE CR
  assert_has_finalizer "$KE_KIND/$KE_NAME" "platform.opendatahub.io/finalizer"

  # cert-manager
  wait_for_all_deployments_in_namespace "cert-manager"

  # RHAI operator
  wait_for_deployment "rhai-operator" "redhat-ods-operator"

  # KServe component CR
  if ! assert_cr_not_degraded "kserves.components.platform.opendatahub.io" "default-kserve" "Kserve 'default-kserve'"; then
    debug_namespace "redhat-ods-operator"
    debug_namespace "redhat-ods-applications" "app.kubernetes.io/part-of=kserve"
  fi

  # Inference Gateway Istio
  wait_for_deployment "inference-gateway-istio" "redhat-ods-applications"
}

# ─── Test 2: sail + lws Managed→Unmanaged→Managed ──────────────────────────

test_2_sail_lws_managed_unmanaged() {
  ensure_deployed \
    --set "${PROV_PREFIX}.lws.managementPolicy=Managed"

  log "Step 1: sailOperator + lws → Unmanaged"
  helm_deploy \
    --set "${PROV_PREFIX}.sailOperator.managementPolicy=Unmanaged" \
    --set "${PROV_PREFIX}.lws.managementPolicy=Unmanaged"

  log "Waiting for Istio CR deletion..."
  kubectl wait --for=delete istio/default --timeout="${TIMEOUT}s" 2>/dev/null \
    || { fail "Istio CR not deleted within timeout"; return; }

  log "Waiting for IstioRevision deletion..."
  kubectl wait --for=delete istiorevision --all --timeout="${TIMEOUT}s" 2>/dev/null \
    || { fail "IstioRevision not deleted within timeout"; return; }

  log "Waiting for istiod deletion..."
  kubectl wait --for=delete deployment/istiod -n istio-system --timeout="${TIMEOUT}s" 2>/dev/null \
    || { fail "istiod not deleted within timeout"; return; }

  log "Waiting for LWS cleanup..."
  kubectl wait --for=delete leaderworkersetoperator/cluster --timeout="${TIMEOUT}s" 2>/dev/null \
    || { fail "LeaderWorkerSetOperator CR not deleted within timeout"; return; }
  assert_deployment_gone "openshift-lws-operator"

  assert_exists "istio-system namespace (persists)" namespace/istio-system
  assert_exists "openshift-lws-operator namespace (persists)" namespace/openshift-lws-operator
  assert_no_stuck_istiorevision

  log "Step 2: sailOperator + lws → Managed (revert)"
  helm_deploy \
    --set "${PROV_PREFIX}.lws.managementPolicy=Managed"
  wait_ke_ready

  assert_cr_not_degraded "istio" "default" "Istio CR restored"
  wait_for_deployment "istiod" "istio-system"
  assert_cr_not_degraded "leaderworkersetoperator" "cluster" "LeaderWorkerSetOperator CR restored"
}

# ─── Test 3: certManager Managed→Unmanaged→Managed ─────────────────────────

test_3_certmanager_managed_unmanaged() {
  ensure_deployed

  log "Step 1: certManager → Unmanaged"
  helm_deploy \
    --set "${PROV_PREFIX}.certManager.managementPolicy=Unmanaged"

  log "Verifying certManager cleanup..."

  # NOTE: CertManager CR can still exists (CM-1019: cert-manager-operator may recreate it)

  assert_deployment_gone "cert-manager-operator"
  assert_exists "cert-manager-operator namespace (persists)" namespace/cert-manager-operator

  # Other deps unaffected
  assert_cr_not_degraded "istio" "default" "Istio CR (unaffected)"
  wait_for_deployment "istiod" "istio-system"

  log "Step 2: certManager → Managed (revert)"
  helm_deploy
  wait_ke_ready

  assert_cr_not_degraded "certmanager" "cluster" "CertManager CR restored"
}

# ─── Test 4: Uninstall lifecycle ────────────────────────────────────────────

test_4_uninstall_lifecycle() {
  ensure_deployed

  # Phase A: uninstall without namespace cleanup (default)
  log "Phase A: helm uninstall (cleanupNamespaces=false)"
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout "$DELETE_TIMEOUT"

  wait_reconciliation 15

  log "Verifying clean uninstall..."

  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
    fail "Helm release $RELEASE_NAME still exists"
  else
    pass "Helm release $RELEASE_NAME removed"
  fi

  assert_not_exists "KubernetesEngine CR" "$KE_KIND/$KE_NAME"
  assert_not_exists "Kserve CR" kserves.components.platform.opendatahub.io/default-kserve
  assert_not_exists "Istio CR" istio/default
  assert_not_exists "istiod deployment" deployment/istiod -n istio-system
  assert_no_stuck_istiorevision

  # All namespaces persist (cleanupNamespaces=false, keep annotation)
  assert_exists "istio-system namespace (persists)" namespace/istio-system
  for ns in redhat-ods-operator redhat-ods-applications "${CM_NS}"; do
    assert_exists "${ns} namespace (persists)" "namespace/${ns}"
  done

  # Phase B: reinstall with cleanupNamespaces=true, then uninstall
  log "Phase B: reinstall with cleanupNamespaces=true"
  helm_deploy --set "uninstall.cleanupNamespaces=true"
  wait_ke_ready

  log "Phase B: helm uninstall (cleanupNamespaces=true)"
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait --timeout "$DELETE_TIMEOUT"

  log "Verifying full cleanup including namespaces..."
  assert_not_exists "KubernetesEngine CR" "$KE_KIND/$KE_NAME"
  assert_not_exists "${CM_NS} namespace" "namespace/${CM_NS}"
  assert_not_exists "istio-system namespace" namespace/istio-system
  assert_not_exists "cert-manager-operator namespace" namespace/cert-manager-operator
  assert_not_exists "redhat-ods-operator namespace" namespace/redhat-ods-operator
  assert_not_exists "redhat-ods-applications namespace" namespace/redhat-ods-applications
}

# ─── Main ───────────────────────────────────────────────────────────────────

ALL_TESTS=(
  "1:Install check:test_1_install_check"
  "2:sail+lws Managed→Unmanaged→Managed:test_2_sail_lws_managed_unmanaged"
  "3:certManager Managed→Unmanaged→Managed:test_3_certmanager_managed_unmanaged"
  "4:Uninstall lifecycle (cleanup + cleanupNamespaces):test_4_uninstall_lifecycle"
)

check_prerequisites

# Determine which tests to run
TESTS_TO_RUN=()
if [[ $# -gt 0 ]]; then
  for arg in "$@"; do
    matched=false
    for entry in "${ALL_TESTS[@]}"; do
      IFS=: read -r num name fn <<< "$entry"
      if [[ "$num" == "$arg" ]]; then
        TESTS_TO_RUN+=("$entry")
        matched=true
      fi
    done
    if [[ "$matched" == "false" ]]; then
      echo "WARNING: unknown test number '$arg' (available: 1-${#ALL_TESTS[@]})" >&2
    fi
  done
else
  TESTS_TO_RUN=("${ALL_TESTS[@]}")
fi

if [[ ${#TESTS_TO_RUN[@]} -eq 0 ]]; then
  echo "No matching tests found for: $*"
  echo "Available tests: 1-${#ALL_TESTS[@]}"
  exit 1
fi

header "rhai-on-xks-chart Verification"
echo "  Release:   $RELEASE_NAME"
echo "  Namespace: $NAMESPACE"
echo "  Provider:  $CLOUD_PROVIDER"
echo "  Chart:     $CHART"
echo "  Tests:     ${#TESTS_TO_RUN[@]}"
echo ""

for entry in "${TESTS_TO_RUN[@]}"; do
  IFS=: read -r num name fn <<< "$entry"
  run_test "$num" "$name" "$fn"
done

print_summary
exit $?
