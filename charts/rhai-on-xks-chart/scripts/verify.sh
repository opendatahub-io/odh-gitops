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

# ─── Configuration ──────────────────────────────────────────────────────────

RELEASE_NAME="${RELEASE_NAME:-rhai-on-xks}"
NAMESPACE="${NAMESPACE:-rhai-on-xks}"
CLOUD_PROVIDER="${CLOUD_PROVIDER:-azure}"
TIMEOUT="${TIMEOUT:-300}"
CHART="${CHART:-./charts/rhai-on-xks-chart}"
VALUES_FILE="${VALUES_FILE:-}"
PULL_SECRET="${PULL_SECRET:-}"
# TODO: remove HELM_EXTRA_ARGS once workflows pass PULL_SECRET directly
HELM_EXTRA_ARGS="${HELM_EXTRA_ARGS:-}"
DELETE_TIMEOUT="${DELETE_TIMEOUT:-360s}"
CLEANUP_WAIT="${CLEANUP_WAIT:-90}"

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]]; then
  echo "ERROR: TIMEOUT must be a positive integer" >&2
  exit 1
fi
INTERVAL_INIT=2
INTERVAL_MAX=10

declare -A PROVIDER_CRDS=(
  [azure]="azurekubernetesengines.infrastructure.opendatahub.io"
  [coreweave]="coreweavekubernetesengines.infrastructure.opendatahub.io"
  [aws]="awskubernetesengines.infrastructure.opendatahub.io"
)

declare -A PROVIDER_CR_DISPLAY=(
  [azure]="AzureKubernetesEngine"
  [coreweave]="CoreWeaveKubernetesEngine"
  [aws]="AWSKubernetesEngine"
)

declare -A PROVIDER_KE_KIND=(
  [azure]="azurekubernetesengine"
  [coreweave]="coreweavekubernetesengine"
  [aws]="awskubernetesengine"
)

if [[ -z "${PROVIDER_CRDS[$CLOUD_PROVIDER]+_}" ]]; then
  echo "ERROR: unsupported CLOUD_PROVIDER '${CLOUD_PROVIDER}'. Valid values: ${!PROVIDER_CRDS[*]}" >&2
  exit 1
fi

KE_KIND="${PROVIDER_KE_KIND[$CLOUD_PROVIDER]}"
KE_NAME="default-${CLOUD_PROVIDER}kubernetesengine"
KE_CRD="${PROVIDER_CRDS[$CLOUD_PROVIDER]}"
CM_NS="rhai-cloudmanager-system"
PROV_PREFIX="${CLOUD_PROVIDER}.kubernetesEngine.spec.dependencies"

# ─── Colors ─────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Result tracking ───────────────────────────────────────────────────────

declare -a TEST_NAMES=()
declare -a TEST_RESULTS=()

record_result() {
  TEST_NAMES+=("$1")
  TEST_RESULTS+=("$2")
}

# ─── Helpers ────────────────────────────────────────────────────────────────

log()    { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
pass()   { echo -e "${GREEN}  ✓ $*${NC}"; }
fail()   { echo -e "${RED}  ✗ $*${NC}"; ASSERT_FAILED=1; }
warn()   { echo -e "${YELLOW}  ⚠ $*${NC}"; }
header() { echo -e "\n${BOLD}═══════════════════════════════════════════════════${NC}"; echo -e "${BOLD}  $*${NC}"; echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"; }

debug_namespace() {
  local ns="$1"
  local filter="${2:-}"
  local filter_args=()
  if [ -n "${filter}" ]; then
    filter_args=(-l "${filter}")
  fi
  echo "  DEBUG: pods in '${ns}'${filter:+ (filter: ${filter})}:"
  kubectl get pods -n "${ns}" ${filter_args[@]+"${filter_args[@]}"} -o wide 2>/dev/null || true
  for pod in $(kubectl get pods -n "${ns}" ${filter_args[@]+"${filter_args[@]}"} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
    local phase
    phase=$(kubectl get pod "${pod}" -n "${ns}" -o jsonpath='{.status.phase}' 2>/dev/null)
    echo "  --- pod: ${pod} (${phase}) ---"
    if [ "${phase}" != "Running" ] && [ "${phase}" != "Succeeded" ]; then
      echo "  DEBUG: describe pod ${pod}:"
      kubectl describe pod "${pod}" -n "${ns}" 2>/dev/null || true
    else
      kubectl logs "${pod}" -n "${ns}" --tail=50 --all-containers 2>/dev/null || true
    fi
  done
}

wait_for() {
  local description="$1"
  shift
  local elapsed=0
  local interval=$INTERVAL_INIT
  while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    echo "  Waiting for ${description}... (${elapsed}s/${TIMEOUT}s)"
    sleep "$interval"
    elapsed=$((elapsed + interval))
    interval=$((interval * 2))
    if [ "$interval" -gt "$INTERVAL_MAX" ]; then
      interval=$INTERVAL_MAX
    fi
  done
  return 1
}

wait_for_deployment() {
  local name="$1"
  local ns="$2"
  local expected_replicas="${3:-}"

  if ! wait_for "deployment ${name} in ${ns}" kubectl get deployment "${name}" -n "${ns}"; then
    fail "Deployment '${name}' not found in '${ns}'"
    return 1
  fi

  if ! wait_for "deployment ${name} rollout" kubectl rollout status deployment "${name}" -n "${ns}" --timeout=0s; then
    fail "Deployment '${name}' in '${ns}' did not become ready within ${TIMEOUT}s"
    kubectl get deployment "${name}" -n "${ns}" -o wide 2>/dev/null || true
    kubectl get pods -n "${ns}" 2>/dev/null || true
    return 1
  fi

  if [ -n "${expected_replicas}" ]; then
    actual=$(kubectl get deployment "${name}" -n "${ns}" -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
    if [ "${actual:-0}" -ne "${expected_replicas}" ]; then
      fail "Deployment '${name}' in '${ns}': expected ${expected_replicas} replicas, got ${actual:-0}"
      return 1
    fi
  fi

  pass "Deployment '${name}' in '${ns}' is ready"
  return 0
}

wait_for_all_deployments_in_namespace() {
  local ns="$1"
  local deployments
  if ! wait_for "deployments in ${ns}" kubectl get deployments -n "${ns}" -o name; then
    fail "No deployments found in namespace '${ns}'"
    return 1
  fi

  deployments=$(kubectl get deployments -n "${ns}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
  if [ -z "${deployments}" ]; then
    fail "No deployments found in namespace '${ns}'"
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
    fail "${description} not found"
    return 1
  fi

  check_cr_conditions() {
    local conditions
    conditions=$(kubectl get "${api_resource}" "${name}" -o jsonpath='{range .status.conditions[?(@.type=="Ready")]}{.status}{end}' 2>/dev/null)
    [ "${conditions}" = "True" ]
  }

  if ! wait_for "${description} to be Ready" check_cr_conditions; then
    fail "${description} did not become Ready within ${TIMEOUT}s"
    kubectl get "${api_resource}" "${name}" -o yaml 2>/dev/null || true
    return 1
  fi

  pass "${description} is Ready"
  return 0
}

assert_cr_not_degraded() {
  local api_resource="$1"
  local name="$2"
  local description="${3:-${api_resource}/${name}}"

  if ! wait_for "${description} to exist" kubectl get "${api_resource}" "${name}"; then
    fail "${description} not found"
    return 1
  fi

  local errors
  errors=$(kubectl get "${api_resource}" "${name}" \
    -o jsonpath='{range .status.conditions[?(@.type=="Degraded")]}{.status}{end}' 2>/dev/null)
  if [[ "$errors" == "True" ]]; then
    local msg
    msg=$(kubectl get "${api_resource}" "${name}" \
      -o jsonpath='{range .status.conditions[?(@.type=="Degraded")]}{.reason}: {.message}{end}' 2>/dev/null)
    fail "${description} is Degraded: ${msg}"
    return 1
  fi

  pass "${description} exists (not degraded)"
  return 0
}

# ─── Assertion helpers ──────────────────────────────────────────────────────

assert_exists() {
  local label="$1"
  shift
  if wait_for "${label} to exist" kubectl get "$@"; then
    pass "$label exists"
  else
    fail "$label should exist but not found"
  fi
}

assert_not_exists() {
  local label="$1"
  shift
  local kubectl_args=("$@")
  check_gone() { ! kubectl get "${kubectl_args[@]}" &>/dev/null; }
  if wait_for "${label} to be gone" check_gone; then
    pass "$label gone"
  else
    fail "$label should be gone but still exists"
  fi
}

assert_has_finalizer() {
  local resource="$1"
  local finalizer="$2"
  check_finalizer() {
    kubectl get "$resource" -o jsonpath='{.metadata.finalizers}' 2>/dev/null | grep -q "$finalizer"
  }
  if wait_for "$resource to have finalizer $finalizer" check_finalizer; then
    pass "$resource has finalizer $finalizer"
  else
    local actual
    actual=$(kubectl get "$resource" -o jsonpath='{.metadata.finalizers}' 2>/dev/null)
    fail "$resource missing finalizer $finalizer (got: $actual)"
  fi
}

assert_deployment_gone() {
  local ns="$1"
  shift
  local selector_args=("$@")
  local label_desc=""
  if [[ ${#selector_args[@]} -gt 0 ]]; then label_desc=" (${selector_args[*]})"; fi
  check_gone() {
    local count
    count=$(kubectl get deployment -n "$ns" ${selector_args[@]+"${selector_args[@]}"} --no-headers 2>/dev/null | wc -l | tr -d ' ')
    [[ "$count" == "0" ]]
  }
  if wait_for "deployments gone in $ns${label_desc}" check_gone; then
    pass "no deployments in $ns${label_desc}"
  else
    fail "deployments still exist in $ns${label_desc}"
    kubectl get deployment -n "$ns" ${selector_args[@]+"${selector_args[@]}"} --no-headers 2>/dev/null | sed 's/^/    /'
  fi
}

assert_no_stuck_istiorevision() {
  local revisions
  revisions=$(kubectl get istiorevision --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$revisions" == "0" ]]; then
    pass "no IstioRevision resources (clean)"
  else
    local stuck
    stuck=$(kubectl get istiorevision -o jsonpath='{range .items[*]}{.metadata.name}: {.metadata.finalizers}{"\n"}{end}' 2>/dev/null)
    if echo "$stuck" | grep -q "sailoperator.io"; then
      fail "IstioRevision stuck with finalizer:\n    $stuck"
    else
      pass "IstioRevision exists but no stuck finalizers"
    fi
  fi
}

# ─── Helm helpers ───────────────────────────────────────────────────────────

helm_deploy() {
  local extra_args=("$@")
  local values_args=()
  if [[ -n "$VALUES_FILE" ]]; then
    values_args+=(-f "$VALUES_FILE")
  fi
  local secret_args=()
  if [[ -n "$PULL_SECRET" ]]; then
    secret_args+=(--set-file "imagePullSecret.dockerConfigJson=${PULL_SECRET}")
  fi
  local helm_extra=()
  if [[ -n "$HELM_EXTRA_ARGS" ]]; then
    read -ra helm_extra <<< "$HELM_EXTRA_ARGS"
  fi
  log "helm upgrade --install $RELEASE_NAME"
  helm upgrade --install "$RELEASE_NAME" "$CHART" \
    -n "$NAMESPACE" --create-namespace \
    --set "${CLOUD_PROVIDER}.enabled=true" \
    ${values_args[@]+"${values_args[@]}"} \
    ${secret_args[@]+"${secret_args[@]}"} \
    ${helm_extra[@]+"${helm_extra[@]}"} \
    ${extra_args[@]+"${extra_args[@]}"} \
    --timeout 10m
}

wait_ke_ready() {
  log "Waiting for $KE_KIND/$KE_NAME to be Ready (timeout: ${TIMEOUT}s)..."
  wait_for_cr_ready "$KE_CRD" "$KE_NAME" "${PROVIDER_CR_DISPLAY[$CLOUD_PROVIDER]} '$KE_NAME'"
}

ensure_deployed() {
  local extra_args=("$@")
  local status
  status=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '.info.status' 2>/dev/null || echo "not-installed")
  if [[ "$status" != "deployed" && "$status" != "not-installed" ]]; then
    log "Release in broken state '$status' — cleaning up..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout 120s 2>/dev/null || true
    kubectl patch "$KE_KIND/$KE_NAME" --type=merge \
      -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    kubectl wait --for=delete "$KE_KIND/$KE_NAME" --timeout=60s 2>/dev/null || true
  fi
  if [[ "$status" == "deployed" && ${#extra_args[@]} -eq 0 ]]; then
    log "Release already deployed, verifying KE ready..."
    wait_ke_ready
    return 0
  fi
  helm_deploy ${extra_args[@]+"${extra_args[@]}"}
  wait_ke_ready
}

wait_reconciliation() {
  local seconds="${1:-$CLEANUP_WAIT}"
  log "Waiting ${seconds}s for reconciliation..."
  sleep "$seconds"
}

# ─── Test runner ────────────────────────────────────────────────────────────

ASSERT_FAILED=0

run_test() {
  local test_num="$1"
  local test_name="$2"
  local test_fn="$3"

  header "Test $test_num: $test_name"
  ASSERT_FAILED=0

  local test_exit=0
  $test_fn || test_exit=$?
  if [[ "$test_exit" -ne 0 ]]; then
    ASSERT_FAILED=1
  fi

  if [[ "$ASSERT_FAILED" -eq 0 ]]; then
    log "Result: ${GREEN}PASS${NC}"
    record_result "$test_num: $test_name" "PASS"
  else
    log "Result: ${RED}FAIL${NC}"
    record_result "$test_num: $test_name" "FAIL"
  fi
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

  # Dependency namespaces persist (cleanupNamespaces=false)
  assert_exists "istio-system namespace (persists)" namespace/istio-system

  # Wait for helm-managed namespaces to finish terminating before re-install
  log "Waiting for terminating namespaces to be fully gone..."
  for ns in redhat-ods-operator redhat-ods-applications "${CM_NS}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
      log "  waiting for namespace/$ns to terminate..."
      kubectl wait --for=delete "namespace/$ns" --timeout=120s 2>/dev/null \
        || warn "namespace/$ns still terminating after 120s"
    fi
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
}

# ─── Main ───────────────────────────────────────────────────────────────────

ALL_TESTS=(
  "1:Install check:test_1_install_check"
  "2:sail+lws Managed→Unmanaged→Managed:test_2_sail_lws_managed_unmanaged"
  "3:certManager Managed→Unmanaged→Managed:test_3_certmanager_managed_unmanaged"
  "4:Uninstall lifecycle (cleanup + cleanupNamespaces):test_4_uninstall_lifecycle"
)

# Validate prerequisites
if ! command -v helm &>/dev/null; then echo "ERROR: helm not found" >&2; exit 1; fi
if ! command -v kubectl &>/dev/null; then echo "ERROR: kubectl not found" >&2; exit 1; fi
if ! command -v jq &>/dev/null; then echo "ERROR: jq not found" >&2; exit 1; fi
if [[ -n "$CHART" && ! -d "$CHART" ]]; then echo "ERROR: Chart not found at: $CHART" >&2; exit 1; fi
if [[ -n "$VALUES_FILE" && ! -f "$VALUES_FILE" ]]; then echo "ERROR: Values file not found at: $VALUES_FILE" >&2; exit 1; fi
if [[ -n "$PULL_SECRET" && ! -f "$PULL_SECRET" ]]; then echo "ERROR: Pull secret not found at: $PULL_SECRET" >&2; exit 1; fi

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

# ─── Summary ────────────────────────────────────────────────────────────────

header "Results Summary"
printf "  %-55s %s\n" "TEST" "RESULT"
printf "  %-55s %s\n" "───────────────────────────────────────────────────────" "──────"
all_passed=true
for i in "${!TEST_NAMES[@]}"; do
  result="${TEST_RESULTS[$i]}"
  if [[ "$result" == "PASS" ]]; then
    color="$GREEN"
  else
    color="$RED"
    all_passed=false
  fi
  printf "  %-55s %s%s%s\n" "${TEST_NAMES[$i]}" "$color" "$result" "$NC"
done

echo ""
if [[ "$all_passed" == "true" ]]; then
  echo -e "${GREEN}All tests passed.${NC}"
  exit 0
else
  echo -e "${RED}Some tests failed.${NC}"
  exit 1
fi
