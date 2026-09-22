#!/bin/bash
# Shared helpers for rhai-on-openshift-chart verification scripts.
# Source this file from install-to-steady-state.sh and verify-upgrade.sh — do not execute directly.

# ─── Configuration ──────────────────────────────────────────────────────────

RELEASE_NAME="${RELEASE_NAME:-odh}"
NAMESPACE="${NAMESPACE:-opendatahub-gitops}"
CHART="${CHART:-./charts/rhai-on-openshift-chart}"

OPERATOR_TYPE="${OPERATOR_TYPE:-odh}"
K8S_CLI="${K8S_CLI:-oc}"

REPO_ROOT="${REPO_ROOT:-}"
VALUES_FILE="${VALUES_FILE:-}"
HELM_EXTRA_ARGS="${HELM_EXTRA_ARGS:-}"

HELM_INSTALL_VALUES_FILE="${HELM_INSTALL_VALUES_FILE:-docs/examples/values-all-components-managed.yaml}"
TIMEOUT="${TIMEOUT:-600}"
DELETE_TIMEOUT="${DELETE_TIMEOUT:-360s}"
HELM_TIMEOUT="${HELM_TIMEOUT:-10m}"

UPGRADE_FROM_CHART="${UPGRADE_FROM_CHART:-}"
UPGRADE_FROM_VERSION="${UPGRADE_FROM_VERSION:-}"

if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

if [[ "$OPERATOR_TYPE" == "rhoai" ]]; then
  APPLICATIONS_NAMESPACE="${APPLICATIONS_NAMESPACE:-redhat-ods-applications}"
else
  APPLICATIONS_NAMESPACE="${APPLICATIONS_NAMESPACE:-opendatahub}"
fi

DSC_RESOURCE="datasciencecluster/default-dsc"
DSCI_RESOURCE="dscinitialization/default-dsci"

if ! [[ "$TIMEOUT" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT" -eq 0 ]]; then
  echo "ERROR: TIMEOUT must be a positive integer" >&2
  exit 1
fi

if [[ "$OPERATOR_TYPE" != "odh" && "$OPERATOR_TYPE" != "rhoai" ]]; then
  echo "ERROR: OPERATOR_TYPE must be 'odh' or 'rhoai'" >&2
  exit 1
fi

INTERVAL_INIT=2
INTERVAL_MAX=10

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

ASSERT_FAILED=0

record_result() {
  TEST_NAMES+=("$1")
  TEST_RESULTS+=("$2")
}

# ─── Logging ──────────────────────────────────────────────────────────────

log()    { echo -e "${CYAN}[$(date +%H:%M:%S)]${NC} $*"; }
pass()   { echo -e "${GREEN}  ✓ $*${NC}"; }
fail()   { echo -e "${RED}  ✗ $*${NC}"; ASSERT_FAILED=1; }
warn()   { echo -e "${YELLOW}  ⚠ $*${NC}"; }
header() {
  echo -e "\n${BOLD}═══════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}  $*${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════${NC}"
}

# ─── Wait helpers ───────────────────────────────────────────────────────────

wait_for() {
  local description="$1"
  shift
  local elapsed=0
  local interval=$INTERVAL_INIT

  while [[ "$elapsed" -lt "$TIMEOUT" ]]; do
    if "$@" >/dev/null 2>&1; then
      return 0
    fi
    echo "  Waiting for ${description}... (${elapsed}s/${TIMEOUT}s)"
    sleep "$interval"
    elapsed=$((elapsed + interval))
    interval=$((interval * 2))
    if [[ "$interval" -gt "$INTERVAL_MAX" ]]; then
      interval=$INTERVAL_MAX
    fi
  done
  return 1
}

# ─── Kubernetes / UID helpers ───────────────────────────────────────────────

get_resource_uid() {
  local resource="$1"
  local output rc

  output=$("$K8S_CLI" get "$resource" -o jsonpath='{.metadata.uid}' 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    if echo "$output" | grep -qi "not found\|no resources found"; then
      echo ""
      return 0
    fi
    echo "ERROR: $K8S_CLI get $resource failed: $output" >&2
    return 1
  fi
  echo "$output"
}

assert_uid_unchanged() {
  local label="$1"
  local resource="$2"
  local old_uid="$3"
  local new_uid

  new_uid=$(get_resource_uid "$resource") || {
    fail "$label: kubectl error reading resource"
    return 1
  }
  if [[ -z "$new_uid" ]]; then
    fail "$label deleted during upgrade"
    return 1
  elif [[ "$new_uid" != "$old_uid" ]]; then
    fail "$label recreated during upgrade (uid changed: $old_uid → $new_uid)"
    return 1
  else
    pass "$label preserved (uid unchanged)"
    return 0
  fi
}

# ─── Helm helpers ───────────────────────────────────────────────────────────

build_helm_args_array() {
  local -n out=$1
  local values_path="$REPO_ROOT/$HELM_INSTALL_VALUES_FILE"
  local helm_extra=()

  out=()
  out+=(-f "$values_path")
  out+=(--set "components.ogx.dsc.managementState=Removed")
  out+=(--set "components.aigateway.dsc.modelsAsAService.managementState=Removed")

  if [[ -n "$VALUES_FILE" ]]; then
    out+=(-f "$VALUES_FILE")
  fi

  if [[ -n "$HELM_EXTRA_ARGS" ]]; then
    read -ra helm_extra <<< "$HELM_EXTRA_ARGS"
    out+=("${helm_extra[@]}")
  fi
}

helm_deploy() {
  local chart_ref="$CHART"
  local version_args=()
  local wait_args=()
  local force_args=()
  local helm_args=()

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chart)
        chart_ref="$2"
        shift 2
        ;;
      --version)
        version_args=(--version "$2")
        shift 2
        ;;
      --wait)
        wait_args=(--wait --timeout "$HELM_TIMEOUT")
        shift
        ;;
      --force-conflicts)
        force_args=(--force-conflicts)
        shift
        ;;
      *)
        break
        ;;
    esac
  done

  build_helm_args_array helm_args

  if [[ ${#version_args[@]} -gt 0 ]]; then
    log "helm upgrade --install $RELEASE_NAME $chart_ref (${version_args[*]})"
  else
    log "helm upgrade --install $RELEASE_NAME $chart_ref"
  fi

  if ! helm upgrade --install "$RELEASE_NAME" "$chart_ref" \
    -n "$NAMESPACE" --create-namespace \
    ${version_args[@]+"${version_args[@]}"} \
    "${helm_args[@]}" \
    ${wait_args[@]+"${wait_args[@]}"} \
    ${force_args[@]+"${force_args[@]}"} \
    --timeout "$HELM_TIMEOUT" \
    "$@"; then
    log "Helm deploy failed — dumping debug info..."
    dump_failure_context
    return 1
  fi
}

helm_release_status() {
  helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '.info.status' 2>/dev/null || echo "not-installed"
}

assert_helm_deployed() {
  local status
  status=$(helm_release_status)
  if [[ "$status" == "deployed" ]]; then
    pass "Helm release status: deployed"
    return 0
  fi
  fail "Helm release status: $status (expected: deployed)"
  return 1
}

ensure_helm_deployed() {
  local chart_ref="$CHART"
  local chart_version=""
  local status

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --chart)
        chart_ref="$2"
        shift 2
        ;;
      --version)
        chart_version="$2"
        shift 2
        ;;
      *)
        break
        ;;
    esac
  done

  status=$(helm_release_status)
  if [[ "$status" != "deployed" && "$status" != "not-installed" ]]; then
    log "Release in state '$status' — uninstalling before reinstall..."
    helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout "$DELETE_TIMEOUT" 2>/dev/null || true
  fi

  if [[ -n "$chart_version" ]]; then
    helm_deploy --chart "$chart_ref" --version "$chart_version"
  else
    helm_deploy --chart "$chart_ref"
  fi
}

dump_failure_context() {
  log "Dumping failure context..."
  echo "=== Helm release ==="
  helm status "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true
  helm history "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true
  helm get values "$RELEASE_NAME" -n "$NAMESPACE" 2>/dev/null || true

  echo ""
  echo "=== DSC / DSCI ==="
  "$K8S_CLI" get datasciencecluster,dscinitialization -o yaml 2>/dev/null || true

  echo ""
  echo "=== OLM subscriptions (filtered) ==="
  "$K8S_CLI" get subscriptions -A 2>/dev/null | grep -E 'opendatahub|cert-manager|rhcl|odh|NAME' || true
  "$K8S_CLI" get csv -A 2>/dev/null | grep -E 'opendatahub|cert-manager|rhcl|odh|NAME' || true

  echo ""
  echo "=== Dashboard deployment ==="
  "$K8S_CLI" get deployment odh-dashboard -n "$APPLICATIONS_NAMESPACE" 2>/dev/null || true
}

# ─── Test runner ────────────────────────────────────────────────────────────

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
  fi
  echo -e "${RED}Some tests failed.${NC}"
  return 1
}

# ─── Prerequisite checks ──────────────────────────────────────────────────

check_prerequisites() {
  if ! command -v helm &>/dev/null; then
    echo "ERROR: helm not found" >&2
    exit 1
  fi
  if ! command -v "$K8S_CLI" &>/dev/null; then
    echo "ERROR: $K8S_CLI not found" >&2
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    echo "ERROR: jq not found" >&2
    exit 1
  fi

  if [[ "$CHART" != oci://* && -n "$CHART" && ! -d "$CHART" ]]; then
    echo "ERROR: Chart directory not found: $CHART" >&2
    exit 1
  fi

  if [[ -n "$VALUES_FILE" && ! -f "$VALUES_FILE" ]]; then
    echo "ERROR: Values file not found: $VALUES_FILE" >&2
    exit 1
  fi

  local values_path="$REPO_ROOT/$HELM_INSTALL_VALUES_FILE"
  if [[ ! -f "$values_path" ]]; then
    echo "ERROR: HELM_INSTALL_VALUES_FILE not found: $values_path" >&2
    exit 1
  fi

  if ! "$K8S_CLI" cluster-info &>/dev/null; then
    echo "ERROR: Cannot reach cluster ($K8S_CLI cluster-info failed)" >&2
    exit 1
  fi
}
