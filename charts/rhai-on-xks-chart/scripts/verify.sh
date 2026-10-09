#!/bin/bash
# Verify rhai-on-xks-chart installation and lifecycle in a Kubernetes cluster.
#
# Usage:
#   ./verify.sh              # run all active tests
#   ./verify.sh 1            # run only test 1 (install check)
#   ./verify.sh 2 3          # run tests 2 and 3
#   ./verify.sh 4            # standalone cert-manager; removes the test installation
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

# ─── Test 1: Install check and component removed ─────────────────────────────

test_1_install_check() {
  ensure_deployed || return 1

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
  if ! wait_for_cr_ready "kserves.components.platform.opendatahub.io" "default-kserve" "Kserve 'default-kserve'"; then
    debug_namespace "redhat-ods-operator"
    debug_namespace "redhat-ods-applications" "app.kubernetes.io/part-of=kserve"
    return 1
  fi

  # Inference Gateway Istio
  wait_for_deployment "inference-gateway-istio" "redhat-ods-applications" || return 1

  log "Uninstalling KServe through Helm"
  helm_deploy --set components.kserve.enabled=false || return 1
  kubectl wait --for=delete kserves.components.platform.opendatahub.io/default-kserve --timeout="${TIMEOUT}s" || return 1
  kubectl wait --for=delete deployment/kserve-module-controller-manager -n redhat-ods-applications --timeout="${TIMEOUT}s" || return 1

  log "Restoring KServe through Helm"
  helm_deploy || return 1
  wait_ke_ready || return 1
  wait_for_cr_ready "kserves.components.platform.opendatahub.io" "default-kserve" "KServe restored" || return 1
  wait_for_deployment "inference-gateway-istio" "redhat-ods-applications"
}

# ─── Tests 2 and 3: isolated dependency Managed→Unmanaged→Managed ────────────

test_dependency_cycle() {
  local dependency="$1"
  # Keep only the dependency under test managed; cert-manager remains for operator webhooks.
  local HELM_EXTRA_ARGS="$HELM_EXTRA_ARGS --set components.kserve.enabled=false --set components.aigateway.enabled=false"
  HELM_EXTRA_ARGS+=" --set ${PROV_PREFIX}.sailOperator.managementPolicy=Unmanaged --set ${PROV_PREFIX}.lws.managementPolicy=Unmanaged"
  HELM_EXTRA_ARGS+=" --set ${PROV_PREFIX}.gatewayAPI.managementPolicy=Unmanaged --set ${PROV_PREFIX}.rhcl.managementPolicy=Unmanaged"

  # helm_deploy appends explicit args after HELM_EXTRA_ARGS; Helm's last --set wins.
  # The selected dependency starts Managed without an intermediate all-Unmanaged upgrade.
  log "Deploying only ${dependency}"
  ensure_deployed --set "${PROV_PREFIX}.${dependency}.managementPolicy=Managed" || return 1

  log "${dependency} → Unmanaged"
  helm_deploy --set "${PROV_PREFIX}.${dependency}.managementPolicy=Unmanaged" || return 1
  wait_ke_ready || return 1

  if [[ "$dependency" == sailOperator ]]; then
    kubectl wait --for=delete istio/default --timeout="${TIMEOUT}s" || return 1
    kubectl wait --for=delete istiorevision --all --timeout="${TIMEOUT}s" || return 1
    kubectl wait --for=delete deployment/istiod -n istio-system --timeout="${TIMEOUT}s" || return 1
    assert_exists "istio-system namespace (persists)" namespace/istio-system
    assert_no_stuck_istiorevision
  else
    kubectl wait --for=delete leaderworkersetoperator/cluster --timeout="${TIMEOUT}s" || return 1
    assert_deployment_gone "openshift-lws-operator"
    assert_exists "openshift-lws-operator namespace (persists)" namespace/openshift-lws-operator
  fi

  log "${dependency} → Managed (revert)"
  helm_deploy --set "${PROV_PREFIX}.${dependency}.managementPolicy=Managed" || return 1
  wait_ke_ready || return 1
  if [[ "$dependency" == sailOperator ]]; then
    assert_cr_not_degraded "istio" "default" "Istio CR restored"
    wait_for_deployment "istiod" "istio-system"
  else
    assert_cr_not_degraded "leaderworkersetoperator" "cluster" "LeaderWorkerSetOperator CR restored"
    wait_for_all_deployments_in_namespace "openshift-lws-operator"
  fi
}

test_2_istio_managed_unmanaged() {
  test_dependency_cycle sailOperator
}

test_3_lws_managed_unmanaged() {
  test_dependency_cycle lws
}

# ─── Test 4: Standalone cert-manager (subchart disabled) ────────────────────

test_4_external_certmanager() {
  # Start a fresh installation, including when this test is selected on its own.
  # Disabling the subchart on an existing release would delete operand credentials.
  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
    log "Removing RHAI before installing standalone cert-manager"
    helm_deploy --reuse-values --set "uninstall.cleanupNamespaces=true" || return 1
    bash "${SCRIPT_DIR}/remove-certmanager-operands.sh" || return 1
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait --timeout "$DELETE_TIMEOUT" || return 1
  fi
  assert_deployment_gone "cert-manager-operator"
  [[ "$ASSERT_FAILED" -eq 0 ]] || return 1

  # CCM requires CertManager/cluster, so install the existing operator chart
  # independently. Its ServiceAccounts and credentials belong to this fixture.
  local certmanager_release="${RELEASE_NAME}-external-certmanager"
  local pull_args=(--set-json 'imagePullSecrets=[]')
  if [[ -n "$PULL_SECRET" ]]; then
    pull_args=(--set 'imagePullSecrets[0].name=external-cert-manager-pull-secret')
  fi
  log "Installing standalone cert-manager operator"
  # Standalone installation supplies its own credentials after Helm creates namespaces.
  helm upgrade --install "$certmanager_release" "${CHART}/../dependencies/cert-manager-operator" \
    -n "$NAMESPACE" --create-namespace "${pull_args[@]}" --timeout 10m || return 1
  if [[ -n "$PULL_SECRET" ]]; then
    for namespace in cert-manager-operator cert-manager; do
      kubectl create secret generic external-cert-manager-pull-secret -n "$namespace" \
        --type=kubernetes.io/dockerconfigjson --from-file=".dockerconfigjson=${PULL_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f - || return 1
    done
  fi
  wait_for_deployment "cert-manager-operator-controller-manager" "cert-manager-operator" || return 1
  for deployment in cert-manager cert-manager-cainjector cert-manager-webhook; do
    wait_for_deployment "$deployment" "cert-manager" || return 1
  done

  log "Installing RHAI with the cert-manager subchart disabled"
  helm_deploy --set "cert-manager-operator.enabled=false" --set "uninstall.cleanupNamespaces=true" || return 1
  wait_ke_ready || return 1
  # The operator must still be owned by the standalone release, not RHAI.
  local owner
  owner=$(kubectl get deployment cert-manager-operator-controller-manager -n cert-manager-operator \
    -o jsonpath='{.metadata.annotations.meta\.helm\.sh/release-name}') || return 1
  [[ "$owner" == "$certmanager_release" ]] || { fail "RHAI changed standalone cert-manager ownership"; return 1; }
  wait_for_deployment "rhai-operator" "redhat-ods-operator" || return 1
  wait_for_cr_ready "kserves.components.platform.opendatahub.io" "default-kserve" "Kserve 'default-kserve'" || return 1

  # Remove consumers first; standalone cert-manager must survive RHAI uninstall.
  # As with the other tests, failures retain resources for debugging.
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait --timeout "$DELETE_TIMEOUT" || return 1
  for deployment in cert-manager cert-manager-cainjector cert-manager-webhook; do
    wait_for_deployment "$deployment" "cert-manager" || return 1
  done
  bash "${SCRIPT_DIR}/remove-certmanager-operands.sh" || return 1
  helm uninstall "$certmanager_release" -n "$NAMESPACE" --wait --timeout "$DELETE_TIMEOUT" || return 1
  for namespace in cert-manager-operator cert-manager; do
    kubectl delete secret external-cert-manager-pull-secret -n "$namespace" --ignore-not-found || return 1
    assert_not_exists "${namespace} fixture pull secret" secret/external-cert-manager-pull-secret -n "$namespace"
  done
  kubectl delete namespace cert-manager-operator cert-manager --ignore-not-found --timeout="${TIMEOUT}s"
}

# ─── Test 5: Uninstall lifecycle ────────────────────────────────────────────

test_5_uninstall_lifecycle() {
  ensure_deployed || return 1

  # Phase A: uninstall without namespace cleanup (default)
  log "Phase A: helm uninstall (cleanupNamespaces=false)"
  # Cert-manager teardown is a manual prerequisite, not a chart hook.
  bash "${SCRIPT_DIR}/remove-certmanager-operands.sh" || return 1
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout "$DELETE_TIMEOUT" || return 1

  wait_reconciliation 15

  log "Verifying clean uninstall..."

  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null; then
    fail "Helm release $RELEASE_NAME still exists"
  else
    pass "Helm release $RELEASE_NAME removed"
  fi

  assert_not_exists "KubernetesEngine CR" "$KE_KIND/$KE_NAME"
  assert_not_exists "CertManager CR" certmanagers.operator.openshift.io/cluster
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
  helm_deploy --set "uninstall.cleanupNamespaces=true" || return 1
  wait_ke_ready || return 1

  log "Phase B: helm uninstall (cleanupNamespaces=true)"
  # Cert-manager teardown is a manual prerequisite, not a chart hook.
  bash "${SCRIPT_DIR}/remove-certmanager-operands.sh" || return 1
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --wait --timeout "$DELETE_TIMEOUT" || return 1

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
  "1:Install check and component removed:test_1_install_check"
  "2:Istio Managed→Unmanaged→Managed:test_2_istio_managed_unmanaged"
  "3:LWS Managed→Unmanaged→Managed:test_3_lws_managed_unmanaged"
  "4:Standalone cert-manager (subchart disabled):test_4_external_certmanager"
  "5:Uninstall lifecycle (cleanup + cleanupNamespaces):test_5_uninstall_lifecycle"
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
