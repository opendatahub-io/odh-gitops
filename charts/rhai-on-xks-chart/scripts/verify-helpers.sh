#!/bin/bash
# Shared helpers for rhai-on-xks-chart verification scripts.
# Source this file from verify.sh and verify-upgrade.sh — do not execute directly.

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

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -eq 0 ]]; then
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

  if ! kubectl rollout status deployment "${name}" -n "${ns}" --timeout="${TIMEOUT}s"; then
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
  if ! errors=$(kubectl get "${api_resource}" "${name}" \
    -o jsonpath='{range .status.conditions[?(@.type=="Degraded")]}{.status}{end}' 2>&1); then
    fail "${description} status query failed: ${errors}"
    return 1
  fi
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
  check_gone() {
    local output rc
    output=$(kubectl get "${kubectl_args[@]}" 2>&1)
    rc=$?
    if [[ $rc -ne 0 ]] && echo "$output" | grep -qi "not found\|no resources found"; then
      return 0
    fi
    return 1
  }
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
    kubectl get "$resource" -o jsonpath='{.metadata.finalizers[*]}' 2>/dev/null | tr ' ' '\n' | grep -qxF "$finalizer"
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
    local output
    output=$(kubectl get deployment -n "$ns" ${selector_args[@]+"${selector_args[@]}"} --no-headers 2>/dev/null) || return 0
    local count
    count=$(echo "$output" | grep -c . || true)
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
  local rev_output rev_rc
  rev_output=$(kubectl get istiorevision --no-headers 2>&1)
  rev_rc=$?
  if [[ $rev_rc -ne 0 ]]; then
    if echo "$rev_output" | grep -qi "not found\|no resources found\|the server doesn't have a resource type"; then
      pass "no IstioRevision CRD or resources (clean)"
      return
    fi
    fail "kubectl error checking IstioRevision: $rev_output"
    return
  fi
  local revisions
  revisions=$(echo "$rev_output" | grep -c . || true)
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
  local chart_ref="$CHART"
  local version_args=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chart) chart_ref="$2"; shift 2 ;;
      --version) version_args=(--version "$2"); shift 2 ;;
      *) break ;;
    esac
  done
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
  log "helm upgrade --install $RELEASE_NAME ${version_args[*]:+(${version_args[*]})}"
  helm upgrade --install "$RELEASE_NAME" "$chart_ref" \
    -n "$NAMESPACE" --create-namespace \
    --set "${CLOUD_PROVIDER}.enabled=true" \
    ${version_args[@]+"${version_args[@]}"} \
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
    kubectl wait --for=delete "$KE_KIND/$KE_NAME" --timeout=60s 2>/dev/null || true
  fi
  if [[ "$status" == "deployed" && ${#extra_args[@]} -eq 0 ]]; then
    log "Release already deployed, verifying KE ready..."
    wait_ke_ready
    return $?
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

# ─── Summary printer ──────────────────────────────────────────────────────

print_summary() {
  header "Results Summary"
  printf "  %-55s %s\n" "TEST" "RESULT"
  printf "  %-55s %s\n" "───────────────────────────────────────────────────────" "──────"
  local all_passed=true
  for i in "${!TEST_NAMES[@]}"; do
    local result="${TEST_RESULTS[$i]}"
    local color
    if [[ "$result" == "PASS" ]]; then
      color="$GREEN"
    else
      color="$RED"
      all_passed=false
    fi
    printf "  %-55s %b%s%b\n" "${TEST_NAMES[$i]}" "$color" "$result" "$NC"
  done

  echo ""
  if [[ "$all_passed" == "true" ]]; then
    echo -e "${GREEN}All tests passed.${NC}"
    return 0
  else
    echo -e "${RED}Some tests failed.${NC}"
    return 1
  fi
}

# ─── Prerequisite checks ──────────────────────────────────────────────────

check_prerequisites() {
  if ! command -v helm &>/dev/null; then echo "ERROR: helm not found" >&2; exit 1; fi
  if ! command -v kubectl &>/dev/null; then echo "ERROR: kubectl not found" >&2; exit 1; fi
  if ! command -v jq &>/dev/null; then echo "ERROR: jq not found" >&2; exit 1; fi
  if [[ -n "$CHART" && ! -d "$CHART" ]]; then echo "ERROR: Chart not found at: $CHART" >&2; exit 1; fi
  if [[ -n "$VALUES_FILE" && ! -f "$VALUES_FILE" ]]; then echo "ERROR: Values file not found at: $VALUES_FILE" >&2; exit 1; fi
  if [[ -n "$PULL_SECRET" && ! -f "$PULL_SECRET" ]]; then echo "ERROR: Pull secret not found at: $PULL_SECRET" >&2; exit 1; fi
}
