#!/bin/bash
# Check bootstrap preparation without contacting a Kubernetes cluster.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFY_SCRIPT="${SCRIPT_DIR}/../scripts/verify.sh"
# Load only the bootstrap function, not the cluster prerequisites or test runner.
eval "$(awk '/^test_4_maas_bootstrap\(\)/ { inside=1 } inside { print } inside && /^}$/ { exit }' "$VERIFY_SCRIPT")"

PULL_SECRET=fixture
RELEASE_NAME=test-release
NAMESPACE=test-namespace
DELETE_TIMEOUT=30s
TIMEOUT=30
CLOUD_PROVIDER=azure
log() { :; }
fail() { :; }
helm() {
  case "$1" in
    uninstall)
      EVENTS+=(uninstall)
      [[ "$FAIL_AT" != uninstall ]] || return 1
      RELEASE_PRESENT=false
      ;;
    status) [[ "$RELEASE_PRESENT" == true ]] ;;
    *) echo "Unexpected helm command: $*" >&2; exit 1 ;;
  esac
}
kubectl() {
  case "$1 $2" in
    'delete namespace')
      EVENTS+=(delete-namespace)
      [[ "$FAIL_AT" != namespace ]] || return 1
      NAMESPACE_PRESENT=false
      ;;
    'get namespace') [[ "$NAMESPACE_PRESENT" == true ]] ;;
    'get secret')
      [[ "$RELEASE_PRESENT" == true \
        || ( "$FAIL_AT" == release-secret && "$3" == rhai-pull-secret ) \
        || ( "$FAIL_AT" == bootstrap-secret && "$3" == rhai-maas-ns-pull-secret ) ]]
      ;;
    *) echo "Unexpected kubectl command: $*" >&2; exit 1 ;;
  esac
}
helm_deploy() {
  EVENTS+=(install)
  [[ "$RELEASE_PRESENT" == false && "$NAMESPACE_PRESENT" == false ]] || exit 1
  # Stop here: this check tests preparation, not the existing bootstrap lifecycle.
  return 1
}

check_preparation() {
  local description="$1" expected="$2"
  RELEASE_PRESENT="$3"
  NAMESPACE_PRESENT="$3"
  FAIL_AT="$4"
  EVENTS=()
  if test_4_maas_bootstrap; then
    echo "Unexpected success: $description" >&2
    exit 1
  fi
  if [[ "${EVENTS[*]}" != "$expected" ]]; then
    echo "FAIL: $description: expected '$expected', got '${EVENTS[*]}'" >&2
    exit 1
  fi
  echo "PASS: $description"
}

check_preparation 'clean up prior installation before fresh install' 'uninstall delete-namespace install' true none
check_preparation 'fresh cluster remains supported' 'uninstall delete-namespace install' false none
check_preparation 'uninstall failure stops preparation' 'uninstall' true uninstall
check_preparation 'namespace deletion failure prevents install' 'uninstall delete-namespace' true namespace
check_preparation 'leftover release Secret prevents install' 'uninstall delete-namespace' true release-secret
check_preparation 'leftover bootstrap Secret prevents install' 'uninstall delete-namespace' true bootstrap-secret
PULL_SECRET=''
check_preparation 'missing credentials prevent cleanup' '' true none

# The default runner must preserve the existing installation/lifecycle tests first.
ORDER=$(sed -n '/^ALL_TESTS=(/,/^)/p' "$VERIFY_SCRIPT" | sed -n 's/^  "\([0-9]\):.*/\1/p' | paste -sd ' ')
[[ "$ORDER" == '1 2 3 4' ]] || { echo "FAIL: default test order is '$ORDER'" >&2; exit 1; }
echo 'PASS: default test order is 1 2 3 4'
