#!/bin/bash
# Verify rhai-on-xks-chart upgrade path from a previous released version.
#
# Installs the previous chart version from OCI registry, upgrades to the local
# chart, and verifies the platform is healthy with no resource loss.
#
# Usage:
#   ./verify-upgrade.sh
#
# Environment variables (in addition to those in verify-helpers.sh):
#   UPGRADE_FROM_CHART   - OCI chart URL for previous version (required)
#   UPGRADE_FROM_VERSION - Chart version to upgrade from (required)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-helpers.sh
source "${SCRIPT_DIR}/verify-helpers.sh"

UPGRADE_FROM_CHART="${UPGRADE_FROM_CHART:-}"
UPGRADE_FROM_VERSION="${UPGRADE_FROM_VERSION:-}"

if [[ -z "$UPGRADE_FROM_CHART" ]]; then
  echo "ERROR: UPGRADE_FROM_CHART is required (OCI chart URL)" >&2
  exit 1
fi
if [[ -z "$UPGRADE_FROM_VERSION" ]]; then
  echo "ERROR: UPGRADE_FROM_VERSION is required" >&2
  exit 1
fi

check_prerequisites

# ─── Helpers ────────────────────────────────────────────────────────────────

get_resource_uid() {
  local resource="$1"
  local output rc
  output=$(kubectl get "$resource" -o jsonpath='{.metadata.uid}' 2>&1)
  rc=$?
  if [[ $rc -ne 0 ]]; then
    if echo "$output" | grep -qi "not found\|no resources found"; then
      echo ""
      return 0
    fi
    echo "ERROR: kubectl get $resource failed: $output" >&2
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

helm_deploy_old_version() {
  helm_deploy --chart "$UPGRADE_FROM_CHART" --version "$UPGRADE_FROM_VERSION"
}

cleanup_upgrade_test() {
  log "Cleaning up upgrade test release..."
  helm uninstall "$RELEASE_NAME" -n "$NAMESPACE" --timeout "$DELETE_TIMEOUT" 2>/dev/null || true
  kubectl wait --for=delete "$KE_KIND/$KE_NAME" --timeout=60s 2>/dev/null || true
}

# ─── Test: Upgrade ──────────────────────────────────────────────────────────

test_1_upgrade() {
  # Phase 1: Install old version (ensure_deployed handles stale state from prior runs)
  log "Phase 1: Installing old chart version ${UPGRADE_FROM_VERSION}..."
  ensure_deployed --chart "$UPGRADE_FROM_CHART" --version "$UPGRADE_FROM_VERSION"

  # Phase 2: Record pre-upgrade state
  log "Phase 2: Recording pre-upgrade state..."

  local ns_resources=("namespace/istio-system")
  declare -A pre_uids=()

  for res in "${ns_resources[@]}"; do
    local uid
    uid=$(get_resource_uid "$res")
    if [[ -n "$uid" ]]; then
      pre_uids["$res"]="$uid"
      pass "$res exists before upgrade (uid=$uid)"
    else
      warn "$res not found before upgrade (may not exist in old version)"
    fi
  done

  local ke_uid
  ke_uid=$(get_resource_uid "$KE_KIND/$KE_NAME") || {
    fail "KE CR: kubectl error reading resource"
    return 1
  }
  if [[ -z "$ke_uid" ]]; then
    fail "KE CR not found before upgrade"
    return 1
  fi
  pass "KE CR exists before upgrade (uid=$ke_uid)"

  if ! wait_for "KServe CR to exist" kubectl get kserves.components.platform.opendatahub.io/default-kserve; then
    fail "KServe CR not found before upgrade"
    return 1
  fi
  local kserve_uid
  kserve_uid=$(get_resource_uid "kserves.components.platform.opendatahub.io/default-kserve") || {
    fail "KServe CR: kubectl error reading resource"
    return 1
  }
  if [[ -z "$kserve_uid" ]]; then
    fail "KServe CR: UID empty after wait"
    return 1
  fi
  pass "KServe CR exists before upgrade (uid=$kserve_uid)"

  # Phase 3: Upgrade to local chart
  log "Phase 3: Upgrading to local chart..."
  helm_deploy
  wait_ke_ready

  # Phase 4: Verify post-upgrade state
  log "Phase 4: Verifying post-upgrade state..."

  # Helm release
  local status
  status=$(helm status "$RELEASE_NAME" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '.info.status' 2>/dev/null || echo "unknown")
  if [[ "$status" == "deployed" ]]; then
    pass "Helm release status: deployed"
  else
    fail "Helm release status: $status (expected: deployed)"
  fi

  # Namespace UIDs
  for res in "${!pre_uids[@]}"; do
    assert_uid_unchanged "$res" "$res" "${pre_uids[$res]}"
  done

  # KE CR UID
  assert_uid_unchanged "KE CR ($KE_KIND/$KE_NAME)" "$KE_KIND/$KE_NAME" "$ke_uid"

  # KServe CR UID
  assert_uid_unchanged "KServe CR (default-kserve)" "kserves.components.platform.opendatahub.io/default-kserve" "$kserve_uid"

  # KServe not degraded
  assert_cr_not_degraded "kserves.components.platform.opendatahub.io" "default-kserve" "Kserve 'default-kserve'"
}

# ─── Main ───────────────────────────────────────────────────────────────────

ALL_TESTS=(
  "1:Upgrade verification:test_1_upgrade"
)

trap cleanup_upgrade_test EXIT

header "rhai-on-xks-chart Upgrade Verification"
echo "  Release:      $RELEASE_NAME"
echo "  Namespace:    $NAMESPACE"
echo "  Provider:     $CLOUD_PROVIDER"
echo "  Upgrade from: $UPGRADE_FROM_CHART (v${UPGRADE_FROM_VERSION})"
echo "  Upgrade to:   $CHART"
echo ""

for entry in "${ALL_TESTS[@]}"; do
  IFS=: read -r num name fn <<< "$entry"
  run_test "$num" "$name" "$fn"
done

print_summary
exit $?
