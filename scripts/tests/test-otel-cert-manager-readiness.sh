#!/usr/bin/env bash
# Local render and executable gate tests. Requires Helm, GNU timeout and the
# repository's yq. Kubernetes calls use a Bash mock without cluster credentials.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CHART="${REPO_ROOT}/charts/rhai-on-openshift-chart"
SCRIPT="${CHART}/files/wait-for-cert-manager.sh"
YQ="${REPO_ROOT}/bin/yq"
RESOURCES=(certificates certificaterequests issuers)
TEST_TMP=$(mktemp -d)
REAL_SLEEP=$(command -v sleep)
test_name="setup"
passed=0
case_count=0
trap 'rm -rf "${TEST_TMP}"' EXIT
trap 'echo "FAIL: ${test_name} at line ${LINENO}" >&2' ERR

fail() {
    echo "FAIL: ${test_name}: $*" >&2
    exit 1
}

assert_equal() {
    [[ "$1" == "$2" ]] || fail "${3:-values differ}: expected [$2], got [$1]"
}

assert_contains() {
    grep -Fq -- "$2" "$1" || { cat "$1" >&2; fail "missing message: $2"; }
}

assert_yaml() {
    "$YQ" -e "$2" "$1" > /dev/null || fail "${3:-YAML assertion failed}: $2"
}

for tool in helm timeout; do
    command -v "$tool" > /dev/null || fail "$tool is required (timeout is provided by GNU coreutils)"
done
[[ -x "$YQ" ]] || fail "yq is missing; run make yq"

# Golden snapshots cover manifest variants; this assertion checks the dependency
# relationship explicitly, including resources that could hold up the Sync Job.
test_sync_ordering() {
    local profile kind name sync_wave expected
    for profile in ai-grid-ingress ai-grid-inference ai-grid-combined; do
        helm template gate-test "$CHART" --set skipCrdCheck=true --set "profile=$profile" \
            --set praxis-gateway.grid.siteName=test --set praxis-provider-gateway.grid.siteName=test > "${TEST_TMP}/render.yaml"
        "$YQ" ea -o=json -I=0 '[.] | map(select(. != null))' "${TEST_TMP}/render.yaml" > "${TEST_TMP}/render"
        assert_yaml "${TEST_TMP}/render" '[.[] | select(.kind == "Subscription" and
            (.metadata.name == "openshift-cert-manager-operator" or .metadata.name == "opentelemetry-product"))] | length == 2'
        assert_yaml "${TEST_TMP}/render" '[.[] | select(.kind == "Job" and .metadata.name == "gate-test-otel-cert-manager")] | length == 1'
        "$YQ" '.[] | select(.kind == "Job" and .metadata.name == "gate-test-otel-cert-manager")' "${TEST_TMP}/render" > "${TEST_TMP}/job"
        assert_yaml "${TEST_TMP}/job" '.metadata.annotations."argocd.argoproj.io/hook" == "Sync" and
            .metadata.annotations."argocd.argoproj.io/hook-delete-policy" == "BeforeHookCreation" and
            (.metadata.annotations | has("helm.sh/hook")) == false and .spec.backoffLimit == 0 and .spec.activeDeadlineSeconds == 630'
        assert_equal "$("$YQ" -r '.spec.template.spec.containers[0].args[0]' "${TEST_TMP}/job")" "$(cat "$SCRIPT")" \
            "rendered Job must run the tested script"
        while IFS='|' read -r kind name sync_wave; do
            case "$kind/$name" in
                Job/gate-test-otel-cert-manager) expected=-20 ;;
                Subscription/opentelemetry-product) expected=-10 ;;
                Namespace/cert-manager-operator|Namespace/openshift-opentelemetry-operator|\
                OperatorGroup/openshift-cert-manager-operator|OperatorGroup/opentelemetry-product|\
                Subscription/openshift-cert-manager-operator|*/gate-test-otel-cert-manager*) expected=-30 ;;
                *) ((sync_wave > -20)) || fail "unrelated $kind/$name can hold up the gate"; continue ;;
            esac
            assert_equal "$sync_wave" "$expected" "$profile: wave of $kind/$name"
        done < <("$YQ" -r '.[] | [.kind, .metadata.name, (.metadata.annotations."argocd.argoproj.io/sync-wave" // "0")] |
            join("|")' "${TEST_TMP}/render")
    done
}

# Replace only the network boundary. Reject all calls except the three named CRD
# reads and discovery: no SA lookup, Deployment reads, permission reviews or writes.
mkdir -p "${TEST_TMP}/bin"
cat > "${TEST_TMP}/bin/oc" <<'MOCK_OC'
#!/usr/bin/env bash
set -euo pipefail
unexpected() { echo "unexpected mock oc call: $*" >&2; exit 2; }
printf '%q ' "$@" >> "${FAKE_CASE}/calls"
printf '\n' >> "${FAKE_CASE}/calls"
[[ "${1-}" == --cache-dir=/tmp/oc-cache ]] || unexpected "$@"
shift
poll=0
if [[ -f "${FAKE_CASE}/poll" ]]; then read -r poll < "${FAKE_CASE}/poll"; fi
mode=$FAKE_MODE
if ((poll >= FAKE_RECOVER_AFTER)); then mode=success; fi
if [[ "$mode" == hang ]]; then "$REAL_SLEEP" 30; fi
if [[ "${1-}" == get && "${2-}" == customresourcedefinition ]]; then
    case "${3-}" in certificates.cert-manager.io|certificaterequests.cert-manager.io|issuers.cert-manager.io) ;;
        *) unexpected "$@" ;; esac
    if [[ "${3-}" == "${FAKE_RESOURCE}.cert-manager.io" ]]; then
        case "$mode" in
            absent) echo 'NotFound: CRD is absent' >&2; exit 1 ;;
            unestablished) printf False; exit 0 ;;
            forbidden-crd) echo 'Forbidden: cannot read cert-manager CRD' >&2; exit 1 ;;
        esac
    fi
    printf True
elif [[ "$*" == 'get --raw /apis/cert-manager.io/v1' ]]; then
    if [[ "$mode" == discovery-error ]]; then exit 1; fi
    if [[ "$mode" == forbidden-discovery ]]; then echo 'Forbidden: cannot read cert-manager discovery' >&2; exit 1; fi
    printf '{"resources":['
    separator=""
    for resource in certificates certificaterequests issuers; do
        if [[ "$mode" == discovery-missing && "$resource" == "$FAKE_RESOURCE" ]]; then continue; fi
        printf '%s{"name":"%s"}' "$separator" "$resource"
        separator=,
    done
    printf ']}'
else
    unexpected "$@"
fi
MOCK_OC
cat > "${TEST_TMP}/bin/sleep" <<'MOCK_SLEEP'
#!/usr/bin/env bash
set -euo pipefail
poll=0
if [[ -f "${FAKE_CASE}/poll" ]]; then read -r poll < "${FAKE_CASE}/poll"; fi
printf '%s\n' "$((poll + 1))" > "${FAKE_CASE}/poll"
"$REAL_SLEEP" 0.1
MOCK_SLEEP
chmod +x "${TEST_TMP}/bin/oc" "${TEST_TMP}/bin/sleep"

run_gate() {
    local mode=${1:-success} budget=${2:-5} recover=${3:-10000} resource=${4:-certificates}
    case_count=$((case_count + 1))
    gate_case="${TEST_TMP}/case-${case_count}"
    mkdir -p "$gate_case"
    gate_status=0
    timeout --kill-after=1s "$((budget + 5))s" env PATH="${TEST_TMP}/bin:${PATH}" \
        REAL_SLEEP="$REAL_SLEEP" FAKE_CASE="$gate_case" FAKE_MODE="$mode" FAKE_RECOVER_AFTER="$recover" FAKE_RESOURCE="$resource" \
        TIMEOUT_SECONDS="$budget" POLL_INTERVAL_SECONDS=1 REQUEST_TIMEOUT_SECONDS=10 \
        bash "$SCRIPT" > "${gate_case}/stdout" 2> "${gate_case}/stderr" || gate_status=$?
    [[ "$gate_status" != 124 && "$gate_status" != 137 ]] || fail "gate exceeded outer watchdog"
    if grep -Fq 'unexpected mock oc call' "${gate_case}/stderr"; then
        cat "${gate_case}/stderr" >&2
        fail "unexpected Kubernetes request"
    fi
}

assert_gate_success() {
    if ((gate_status != 0)); then cat "${gate_case}/stdout" "${gate_case}/stderr" >&2; fail "gate failed"; fi
}

assert_gate_timeout() {
    ((gate_status != 0)) || fail "gate unexpectedly succeeded"
    assert_contains "${gate_case}/stderr" "timed out after ${1}s"
    assert_contains "${gate_case}/stderr" "$2"
    if grep -Fq 'are discoverable' "${gate_case}/stdout"; then fail "failure reported readiness"; fi
}

test_success_without_operator_service_account_existing() {
    run_gate
    assert_gate_success
    local first=$gate_case resource
    assert_equal "$(awk 'END {print NR}' "${first}/calls")" 4 "success requires three CRD reads and discovery"
    for resource in "${RESOURCES[@]}"; do
        assert_contains "${first}/calls" "${resource}.cert-manager.io"
    done
    assert_contains "${first}/calls" 'get --raw /apis/cert-manager.io/v1'
    run_gate
    assert_gate_success
    diff -u "${first}/calls" "${gate_case}/calls"
}

test_prerequisites_become_available_after_polling() {
    local mode
    for mode in absent unestablished discovery-error discovery-missing; do
        run_gate "$mode" 5 1
        assert_gate_success
        assert_contains "${gate_case}/stdout" 'Waiting:'
    done
}

test_failures_are_bounded_and_explain_the_blocker() {
    local mode message
    while IFS='|' read -r mode message; do
        run_gate "$mode" 1
        assert_gate_timeout 1 "$message"
        if grep -Fq -- --request-timeout "${gate_case}/calls"; then fail "CLI request-timeout bypasses in-cluster config"; fi
    done <<'FAILURES'
absent|CRD certificates
unestablished|not Established
discovery-error|API discovery is unavailable
discovery-missing|does not advertise certificates
FAILURES
}

test_each_required_crd_and_discovered_resource() {
    local resource
    for resource in "${RESOURCES[@]}"; do
        run_gate absent 1 10000 "$resource"
        assert_gate_timeout 1 "CRD ${resource}.cert-manager.io"
        run_gate discovery-missing 1 10000 "$resource"
        assert_gate_timeout 1 "does not advertise ${resource}"
    done
}

test_gate_read_permission_denials_fail_closed() {
    local mode
    for mode in forbidden-crd forbidden-discovery; do
        run_gate "$mode" 1
        assert_gate_timeout 1 'cert-manager'
        assert_contains "${gate_case}/stderr" 'Forbidden:'
    done
}

test_hung_api_call_cannot_exceed_polling_budget() {
    run_gate hang 1
    assert_gate_timeout 1 'CRD certificates'
}

for test_name in \
    test_sync_ordering \
    test_success_without_operator_service_account_existing \
    test_prerequisites_become_available_after_polling \
    test_failures_are_bounded_and_explain_the_blocker \
    test_each_required_crd_and_discovered_resource \
    test_gate_read_permission_denials_fail_closed \
    test_hung_api_call_cannot_exceed_polling_budget; do
    echo "Running ${test_name}"
    "$test_name"
    passed=$((passed + 1))
    echo "PASS: ${test_name}"
done
echo "All ${passed} cert-manager readiness tests passed"
