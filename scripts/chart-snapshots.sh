#!/usr/bin/env bash
#
# chart-snapshots.sh - Generate or test Helm chart snapshots
#
# Usage:
#   ./scripts/chart-snapshots.sh [--generate|--test] [--chart <name>]
#
# Options:
#   --generate          Generate snapshots (update .snap.yaml files)
#   --test              Test snapshots (compare against existing)
#   --chart <name>      Process only the specified chart (default: all charts)
#   -h, --help          Show this help message
#
# Configuration:
#   Reads snapshot definitions from scripts/snapshot-config.yaml
#
# Requirements: helm, yq (bin/yq), gsed (macOS) or sed (Linux)
#

set -euo pipefail

# Error trap for better debugging
trap 'echo "ERROR: Script failed at line $LINENO" >&2; exit 1' ERR

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
YQ="${REPO_ROOT}/bin/yq"
CHARTS_DIR="${REPO_ROOT}/charts"
CONFIG_FILE="${SCRIPT_DIR}/snapshot-config.yaml"

# Use gsed on macOS (Darwin), sed on Linux
if [[ "$(uname -s)" == "Darwin" ]]; then
    SED="gsed"
else
    SED="sed"
fi

# ==============================================================================
# VARIABLES
# ==============================================================================

MODE=""
CHART_FILTER=""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Generate or test Helm chart snapshots.

Options:
  --generate          Generate snapshots (update .snap.yaml files)
  --test              Test snapshots (compare against existing)
  --chart <name>      Process only the specified chart (default: all charts)
  -h, --help          Show this help message

Configuration:
  Reads snapshot definitions from scripts/snapshot-config.yaml

Examples:
  # Generate snapshots for all charts
  $(basename "$0") --generate

  # Test snapshots for all charts
  $(basename "$0") --test

  # Generate snapshots for specific chart
  $(basename "$0") --generate --chart odh-operator

  # Test snapshots for specific chart
  $(basename "$0") --test --chart odh-rhoai
EOF
}

validate_requirements() {
    local errors=0

    # Check helm
    if ! command -v helm &> /dev/null; then
        echo "ERROR: helm is not installed or not in PATH"
        errors=$((errors + 1))
    fi

    # Check yq
    if [[ ! -x "${YQ}" ]]; then
        echo "ERROR: yq not found at ${YQ}. Run 'make yq' to install."
        errors=$((errors + 1))
    fi

    # Check sed (gsed on macOS)
    if ! command -v "${SED}" &> /dev/null; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo "ERROR: gsed is not installed. Install with: brew install gnu-sed"
        else
            echo "ERROR: sed is not installed or not in PATH"
        fi
        errors=$((errors + 1))
    fi

    # Check config file exists
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "ERROR: Config file not found at ${CONFIG_FILE}"
        errors=$((errors + 1))
    fi

    # Check mode is set
    if [[ -z "${MODE}" ]]; then
        echo "ERROR: Either --generate or --test is required"
        errors=$((errors + 1))
    fi

    if [[ ${errors} -gt 0 ]]; then
        echo ""
        show_help
        exit 1
    fi
}

# Get list of charts from config
get_charts() {
    "${YQ}" eval '.charts | keys | .[]' "${CONFIG_FILE}"
}

# Get test values file for a chart (empty if not defined)
get_test_values_file() {
    local chart_name="$1"
    "${YQ}" eval ".charts.${chart_name}.testValuesFile // \"\"" "${CONFIG_FILE}"
}

# Get number of snapshots for a chart
get_snapshot_count() {
    local chart_name="$1"
    "${YQ}" eval ".charts.${chart_name}.snapshots | length" "${CONFIG_FILE}"
}

# Get snapshot name by index
get_snapshot_name() {
    local chart_name="$1"
    local index="$2"
    "${YQ}" eval ".charts.${chart_name}.snapshots[${index}].name" "${CONFIG_FILE}"
}

# Get snapshot set flags by index (returns empty string if no flags)
get_snapshot_flags() {
    local chart_name="$1"
    local index="$2"
    local flags=""

    # Read each flag and build --set arguments
    while IFS= read -r flag; do
        if [[ -n "${flag}" && "${flag}" != "null" ]]; then
            flags="${flags} --set ${flag}"
        fi
    done < <("${YQ}" eval ".charts.${chart_name}.snapshots[${index}].setFlags[]?" "${CONFIG_FILE}")

    echo "${flags}"
}

# Build helm template command for a chart
build_helm_cmd() {
    local chart_name="$1"
    local chart_path="${CHARTS_DIR}/${chart_name}"
    local test_values_file

    test_values_file=$(get_test_values_file "${chart_name}")

    local cmd="helm template -f ${chart_path}/values.yaml"

    # Add test values file if it exists
    if [[ -n "${test_values_file}" && -f "${chart_path}/${test_values_file}" ]]; then
        cmd="${cmd} -f ${chart_path}/${test_values_file}"
    fi

    # Add standard options
    cmd="${cmd} --name-template=release-test -n default"

    echo "${cmd}"
}

# Redact helm chart version in output
redact_version() {
    local file="$1"
    "${SED}" -i.bak "s|helm\.sh\/chart\:.*|helm\.sh\/chart\: HELM_CHART_VERSION_REDACTED|" "${file}"
    rm -f "${file}.bak"
}

# Process a single snapshot
process_snapshot() {
    local chart_name="$1"
    local snapshot_index="$2"
    local chart_path="${CHARTS_DIR}/${chart_name}"
    local snapshot_dir="${chart_path}/test/snapshots"

    local snapshot_name
    snapshot_name=$(get_snapshot_name "${chart_name}" "${snapshot_index}")

    local set_flags
    set_flags=$(get_snapshot_flags "${chart_name}" "${snapshot_index}")

    local helm_cmd
    helm_cmd=$(build_helm_cmd "${chart_name}")

    local snapshot_file="${snapshot_dir}/${snapshot_name}.snap.yaml"

    echo "  ==> ${snapshot_name}"

    if [[ "${MODE}" == "generate" ]]; then
        # Ensure snapshot directory exists
        mkdir -p "${snapshot_dir}"

        # Generate snapshot
        # shellcheck disable=SC2086
        eval "${helm_cmd} ${set_flags} ${chart_path}" > "${snapshot_file}"

        # Redact version
        redact_version "${snapshot_file}"

        echo "      Created: ${snapshot_file}"
    else
        # Test mode - generate temp file and compare
        local temp_file
        temp_file=$(mktemp)

        # Generate to temp file
        # shellcheck disable=SC2086
        eval "${helm_cmd} ${set_flags} ${chart_path}" > "${temp_file}"

        # Redact version
        redact_version "${temp_file}"

        # Compare with existing snapshot
        if [[ ! -f "${snapshot_file}" ]]; then
            echo "      ERROR: Snapshot file not found: ${snapshot_file}"
            rm -f "${temp_file}"
            return 1
        fi

        if diff -q "${temp_file}" "${snapshot_file}" > /dev/null 2>&1; then
            echo "      PASS"
        else
            echo "      FAIL: Differences found"
            echo ""
            diff "${temp_file}" "${snapshot_file}" || true
            echo ""
            rm -f "${temp_file}"
            return 1
        fi

        rm -f "${temp_file}"
    fi

    return 0
}

# Clean existing snapshots for a chart
clean_snapshots() {
    local chart_name="$1"
    local chart_path="${CHARTS_DIR}/${chart_name}"
    local snapshot_dir="${chart_path}/test/snapshots"

    if [[ -d "${snapshot_dir}" ]]; then
        echo "  Cleaning existing snapshots in ${snapshot_dir}..."
        rm -f "${snapshot_dir}"/*.snap.yaml
    fi
}

# Process all snapshots for a chart
process_chart() {
    local chart_name="$1"
    local chart_path="${CHARTS_DIR}/${chart_name}"

    # Check chart exists
    if [[ ! -d "${chart_path}" ]]; then
        echo "ERROR: Chart directory not found: ${chart_path}"
        return 1
    fi

    local snapshot_count
    snapshot_count=$(get_snapshot_count "${chart_name}")

    echo ""
    echo "Processing chart: ${chart_name} (${snapshot_count} snapshots)"
    echo "----------------------------------------"

    # In generate mode, clean existing snapshots first to avoid stale files
    if [[ "${MODE}" == "generate" ]]; then
        clean_snapshots "${chart_name}"
    fi

    local failed=0
    for ((i = 0; i < snapshot_count; i++)); do
        if ! process_snapshot "${chart_name}" "${i}"; then
            failed=$((failed + 1))
        fi
    done

    if [[ ${failed} -gt 0 ]]; then
        echo ""
        echo "FAILED: ${failed} snapshot(s) did not match for ${chart_name}"
        return 1
    fi

    return 0
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --generate)
            MODE="generate"
            shift
            ;;
        --test)
            MODE="test"
            shift
            ;;
        --chart)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --chart requires a value"
                show_help
                exit 1
            fi
            CHART_FILTER="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    validate_requirements

    local mode_display
    if [[ "${MODE}" == "generate" ]]; then
        mode_display="Generating"
    else
        mode_display="Testing"
    fi

    echo "=============================================================================="
    echo "Chart Snapshots - ${mode_display}"
    echo "=============================================================================="

    local charts_to_process
    if [[ -n "${CHART_FILTER}" ]]; then
        charts_to_process="${CHART_FILTER}"
    else
        charts_to_process=$(get_charts)
    fi

    local total_failed=0
    for chart in ${charts_to_process}; do
        if ! process_chart "${chart}"; then
            total_failed=$((total_failed + 1))
        fi
    done

    echo ""
    echo "=============================================================================="
    if [[ ${total_failed} -gt 0 ]]; then
        echo "FAILED: ${total_failed} chart(s) had snapshot failures"
        exit 1
    else
        if [[ "${MODE}" == "generate" ]]; then
            echo "All snapshots generated successfully!"
        else
            echo "All snapshot tests passed!"
        fi
    fi
    echo "=============================================================================="
}

main "$@"
