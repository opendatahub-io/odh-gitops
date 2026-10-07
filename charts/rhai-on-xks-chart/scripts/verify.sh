#!/bin/bash
# Verify rhai-on-xks-chart installation and lifecycle in a Kubernetes cluster.
#
# Usage:
#   ./verify.sh              # run all tests (1-4) on a disposable cluster
#   ./verify.sh 4            # run only the MaaS namespace bootstrap test (cleans up the release first)
#   ./verify.sh 1            # run only test 1 (install check)
#   ./verify.sh 2 3          # run tests 2 and 3
#
# Test 4 uninstalls RELEASE_NAME and deletes redhat-ai-gateway-infra, including
# its contents. Run this script only against a disposable test cluster.
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

# ─── Test 4: MaaS namespace bootstrap ──────────────────────────────────────

test_4_maas_bootstrap() {
  if [[ -z "$PULL_SECRET" ]]; then
    fail "MaaS bootstrap test requires PULL_SECRET"
    return 1
  fi

  # Exercise installation with no existing release, MaaS namespace, or pull Secrets.
  # Other retained namespaces and CRDs can remain from the default installation tests.
  log "Cleaning up the test release and MaaS infrastructure namespace"
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --ignore-not-found \
    --cascade foreground --wait --timeout "$DELETE_TIMEOUT" || return 1
  kubectl delete namespace redhat-ai-gateway-infra --ignore-not-found \
    --wait=true --timeout="${TIMEOUT}s" || return 1

  if helm status "$RELEASE_NAME" -n "$NAMESPACE" &>/dev/null \
    || kubectl get namespace redhat-ai-gateway-infra &>/dev/null \
    || kubectl get secret rhai-pull-secret -n "$NAMESPACE" &>/dev/null \
    || kubectl get secret rhai-maas-ns-pull-secret -n "$NAMESPACE" &>/dev/null; then
    fail "MaaS bootstrap test requires a fresh release and infrastructure namespace"
    return 1
  fi

  # Only the namespace hook runs; no component CRs or gateway resources are created.
  local bootstrap_args=(
    --set "cert-manager-operator.enabled=false"
    --set "${CLOUD_PROVIDER}.kubernetesEngine.enabled=false"
    --set "hooks.postInstallCrs.enabled=false"
    --set "components.kserve.enabled=false"
    --set "components.aigateway.enabled=true"
    --set "components.aigateway.spec.modelsAsAService.managementState=Managed"
    --set "components.aigateway.modelsAsAService.gateway.create=false"
  )

  log "Installing MaaS namespace bootstrap without a pre-existing pull Secret"
  helm_deploy "${bootstrap_args[@]}" || return 1
  assert_exists "MaaS infrastructure namespace" namespace/redhat-ai-gateway-infra
  assert_exists "MaaS pull Secret" secret/rhai-pull-secret -n redhat-ai-gateway-infra
  assert_exists "MaaS ServiceAccount" serviceaccount/maas-api -n redhat-ai-gateway-infra
  assert_exists "Release pull Secret" secret/rhai-pull-secret -n "$NAMESPACE"
  assert_not_exists "Bootstrap pull Secret (cleaned up)" secret/rhai-maas-ns-pull-secret -n "$NAMESPACE"
  assert_not_exists "Namespace Job (cleaned up)" job/rhai-pre-install-maas-ns -n "$NAMESPACE"
  [[ "$ASSERT_FAILED" -eq 0 ]] || return 1

  local secret_uid
  secret_uid=$(kubectl get secret rhai-pull-secret -n "$NAMESPACE" -o jsonpath='{.metadata.uid}') || return 1

  log "Upgrading MaaS namespace bootstrap with the release pull Secret already present"
  helm_deploy "${bootstrap_args[@]}" || return 1
  if [[ "$(kubectl get secret rhai-pull-secret -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')" != "$secret_uid" ]]; then
    fail "Release pull Secret was replaced during upgrade"
    return 1
  fi
  pass "Release pull Secret UID preserved during upgrade"
  assert_not_exists "Bootstrap pull Secret (cleaned up after upgrade)" secret/rhai-maas-ns-pull-secret -n "$NAMESPACE"
  assert_not_exists "Namespace Job (cleaned up after upgrade)" job/rhai-pre-install-maas-ns -n "$NAMESPACE"
  [[ "$ASSERT_FAILED" -eq 0 ]] || return 1

  log "Failing the namespace hook with an unpullable image"
  if helm upgrade "$RELEASE_NAME" "$CHART" -n "$NAMESPACE" --reuse-values \
    --set "hooks.cliImage=invalid.invalid/maas-bootstrap:missing" --timeout 20s; then
    fail "Upgrade with an unpullable hook image unexpectedly succeeded"
    return 1
  fi
  if [[ "$(kubectl get job rhai-pre-install-maas-ns -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].image}')" != "invalid.invalid/maas-bootstrap:missing" ]]; then
    fail "Failed upgrade did not reach the namespace hook"
    return 1
  fi
  if [[ "$(kubectl get secret rhai-pull-secret -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')" != "$secret_uid" ]]; then
    fail "Release pull Secret was removed or replaced during failed upgrade"
    return 1
  fi
  pass "Release pull Secret UID preserved during failed upgrade"

  log "Retrying the upgrade after namespace hook failure"
  helm_deploy "${bootstrap_args[@]}" || return 1
  if [[ "$(kubectl get secret rhai-pull-secret -n "$NAMESPACE" -o jsonpath='{.metadata.uid}')" != "$secret_uid" ]]; then
    fail "Release pull Secret was replaced during upgrade retry"
    return 1
  fi
  pass "Release pull Secret UID preserved during upgrade retry"
  assert_not_exists "Bootstrap pull Secret (cleaned up after retry)" secret/rhai-maas-ns-pull-secret -n "$NAMESPACE"
  assert_not_exists "Namespace Job (cleaned up after retry)" job/rhai-pre-install-maas-ns -n "$NAMESPACE"
  [[ "$ASSERT_FAILED" -eq 0 ]] || return 1

  # Simulate an interrupted bootstrap leaving its hook Secret behind.
  kubectl create secret generic rhai-maas-ns-pull-secret -n "$NAMESPACE" --from-literal=interrupted=true || return 1
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout "$DELETE_TIMEOUT" || return 1
  assert_not_exists "Leftover bootstrap pull Secret (removed on uninstall)" secret/rhai-maas-ns-pull-secret -n "$NAMESPACE"
}

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

  # Revert sail before LWS: on 4-CPU CI nodes, LWS's two 1-CPU replicas otherwise
  # claim the CPU istiod needs and leave it Pending.
  log "Step 2: sailOperator → Managed (revert)"
  helm_deploy \
    --set "${PROV_PREFIX}.lws.managementPolicy=Unmanaged"
  wait_ke_ready

  assert_cr_not_degraded "istio" "default" "Istio CR restored"
  wait_for_deployment "istiod" "istio-system"

  log "Step 3: lws → Managed (revert)"
  helm_deploy \
    --set "${PROV_PREFIX}.lws.managementPolicy=Managed"
  wait_ke_ready

  assert_cr_not_degraded "leaderworkersetoperator" "cluster" "LeaderWorkerSetOperator CR restored"
}

# ─── Test 3: External cert-manager (subchart disabled) ─────────────────────

test_3_external_certmanager() {
  log "Deploying with cert-manager-operator.enabled=false (external cert-manager scenario)"
  helm_deploy \
    --set "cert-manager-operator.enabled=false"

  # cert-manager-operator subchart resources must not be deployed
  assert_deployment_gone "cert-manager-operator"

  # cert-manager workloads must still be running (
  wait_for_all_deployments_in_namespace "cert-manager"

  # RHAI operator must still be healthy because cert-manager is running externally
  wait_for_deployment "rhai-operator" "redhat-ods-operator"
  assert_cr_not_degraded "kserves.components.platform.opendatahub.io" "default-kserve" "Kserve 'default-kserve'"

  log "Reverting to default (enabled)"
  helm_deploy
}

# ─── Test 5: Uninstall lifecycle ────────────────────────────────────────────

test_5_uninstall_lifecycle() {
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
  "3:external cert-manager (subchart disabled):test_3_external_certmanager"
  "4:MaaS namespace bootstrap:test_4_maas_bootstrap"
  # TODO: this would not work correctly, since KServe is blocking the deletion.
  # "5:Uninstall lifecycle (cleanup + cleanupNamespaces):test_5_uninstall_lifecycle"
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
      echo "WARNING: unknown test number '$arg' (available: 1-4)" >&2
    fi
  done
else
  TESTS_TO_RUN=("${ALL_TESTS[@]}")
fi

if [[ ${#TESTS_TO_RUN[@]} -eq 0 ]]; then
  echo "No matching tests found for: $*"
  echo "Available tests: 1-4"
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
