#!/bin/bash
# Verify rhai-on-openshift-chart upgrade path from a previous released OCI version.
#
# Installs the previous chart from the OCI registry, reaches steady state, upgrades
# to the local chart, and verifies DSC/DSCI UIDs are preserved and DSC is Ready.
#
# Usage:
#   ./verify-upgrade.sh
#
# Environment variables (see verify-helpers.sh):
#   UPGRADE_FROM_CHART   - OCI chart URL for previous version (required)
#   UPGRADE_FROM_VERSION - Chart version to upgrade from (required)
#   CHART                - Local chart path to upgrade to (default: ./charts/rhai-on-openshift-chart)
#   CLEANUP_ON_EXIT      - If true, helm uninstall on exit (default: false)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-helpers.sh
source "${SCRIPT_DIR}/verify-helpers.sh"

LOCAL_CHART="$CHART"
CLEANUP_ON_EXIT="${CLEANUP_ON_EXIT:-false}"

if [[ -z "$UPGRADE_FROM_CHART" ]]; then
  echo "ERROR: UPGRADE_FROM_CHART is required (OCI chart URL)" >&2
  exit 1
fi
if [[ -z "$UPGRADE_FROM_VERSION" ]]; then
  echo "ERROR: UPGRADE_FROM_VERSION is required" >&2
  exit 1
fi
if [[ "$UPGRADE_FROM_CHART" != oci://* ]]; then
  echo "ERROR: UPGRADE_FROM_CHART must be an OCI chart URL (oci://...)" >&2
  exit 1
fi
if [[ ! -d "$LOCAL_CHART" ]]; then
  echo "ERROR: Local upgrade target chart not found: $LOCAL_CHART" >&2
  exit 1
fi

check_prerequisites

# ─── Helpers ────────────────────────────────────────────────────────────────

cleanup_upgrade_test() {
  if [[ "$CLEANUP_ON_EXIT" != "true" ]]; then
    return 0
  fi
  log "Cleaning up upgrade test release..."
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout "$DELETE_TIMEOUT" 2>/dev/null || true
}

record_pre_upgrade_uids() {
  local dsc_uid dsci_uid

  dsc_uid=$(get_resource_uid "$DSC_RESOURCE") || {
    fail "DSC: $K8S_CLI error reading resource"
    return 1
  }
  if [[ -z "$dsc_uid" ]]; then
    fail "DSC not found before upgrade ($DSC_RESOURCE)"
    return 1
  fi
  pass "DSC exists before upgrade (uid=$dsc_uid)"

  dsci_uid=$(get_resource_uid "$DSCI_RESOURCE") || {
    fail "DSCI: $K8S_CLI error reading resource"
    return 1
  }
  if [[ -z "$dsci_uid" ]]; then
    fail "DSCI not found before upgrade ($DSCI_RESOURCE)"
    return 1
  fi
  pass "DSCI exists before upgrade (uid=$dsci_uid)"

  PRE_DSC_UID="$dsc_uid"
  PRE_DSCI_UID="$dsci_uid"
}

# ─── Test: Upgrade ──────────────────────────────────────────────────────────

test_1_upgrade() {
  local helm_force_args=()

  if [[ "${FORCE_CONFLICTS:-false}" == "true" ]]; then
    helm_force_args=(--force-conflicts)
  fi

  # Phase 1: Install baseline from OCI (operators pass)
  log "Phase 1: Installing ${UPGRADE_FROM_VERSION} from OCI..."
  CHART="$UPGRADE_FROM_CHART"
  CHART_VERSION="$UPGRADE_FROM_VERSION"
  if ! ensure_helm_deployed --chart "$UPGRADE_FROM_CHART" --version "$UPGRADE_FROM_VERSION"; then
    fail "Failed to install baseline chart from OCI"
    return 1
  fi

  # Phase 2: Steady state on baseline
  log "Phase 2: Reaching steady state on baseline (${UPGRADE_FROM_VERSION})..."
  if ! bash "${SCRIPT_DIR}/install-to-steady-state.sh"; then
    fail "Failed to reach steady state on baseline chart"
    return 1
  fi

  # Phase 3: Record pre-upgrade state
  log "Phase 3: Recording pre-upgrade state..."
  if ! record_pre_upgrade_uids; then
    return 1
  fi

  local status
  status=$(helm_release_status)
  if [[ "$status" != "deployed" ]]; then
    fail "Helm release status before upgrade: $status (expected: deployed)"
    return 1
  fi
  pass "Helm release status before upgrade: deployed"

  # Phase 4: Upgrade to local chart
  log "Phase 4: Upgrading to local chart (${LOCAL_CHART})..."
  CHART="$LOCAL_CHART"
  unset CHART_VERSION
  if ! helm_deploy "${helm_force_args[@]}"; then
    fail "Helm upgrade to local chart failed"
    return 1
  fi

  # Phase 5: Post-upgrade steady state
  log "Phase 5: Post-upgrade steady state..."
  if ! bash "${SCRIPT_DIR}/install-to-steady-state.sh"; then
    fail "Failed to reach steady state after upgrade"
    return 1
  fi

  # Phase 6: Verify post-upgrade state
  log "Phase 6: Verifying post-upgrade state..."
  assert_helm_deployed || return 1
  assert_uid_unchanged "DSC" "$DSC_RESOURCE" "$PRE_DSC_UID" || return 1
  assert_uid_unchanged "DSCI" "$DSCI_RESOURCE" "$PRE_DSCI_UID" || return 1

  if ! NAMESPACE="$NAMESPACE" OPERATOR_TYPE="$OPERATOR_TYPE" \
    bash "${REPO_ROOT}/scripts/verify-helm-chart.sh"; then
    fail "verify-helm-chart.sh failed (DSC not Ready)"
    return 1
  fi
  pass "DSC verification passed (verify-helm-chart.sh)"
}

# ─── Main ───────────────────────────────────────────────────────────────────

ALL_TESTS=(
  "1:Upgrade verification:test_1_upgrade"
)

trap cleanup_upgrade_test EXIT

header "rhai-on-openshift-chart Upgrade Verification"
echo "  Release:      $RELEASE_NAME"
echo "  Namespace:    $NAMESPACE"
echo "  Operator:     $OPERATOR_TYPE"
echo "  Upgrade from: $UPGRADE_FROM_CHART (${UPGRADE_FROM_VERSION})"
echo "  Upgrade to:   $LOCAL_CHART"
echo ""

for entry in "${ALL_TESTS[@]}"; do
  IFS=: read -r num name fn <<< "$entry"
  run_test "$num" "$name" "$fn"
done

print_summary
exit $?
