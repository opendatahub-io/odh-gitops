#!/usr/bin/env bash
#
# extract-olm-bundle.sh - Extract OLM bundle resources and save as Helm chart templates
#
# Usage:
#   ./extract-olm-bundle.sh [options]
#
# Options:
#   -b, --bundle <image>         Full bundle image (required)
#   -c, --config <file>          helmtemplate-generator config file (required)
#   -n, --namespace <ns>         Target namespace (required)
#   -o, --output <dir>           Output chart directory (required)
#   -v, --version <version>      Bundle version for Chart.yaml appVersion (optional)
#   --chart-description <desc>   Chart description for Chart.yaml (optional)
#   --use-user-auth              Use current user's podman credentials
#   -h, --help                   Show this help message
#
# Environment variables:
#   BUNDLE_EXTRACT_REGISTRY_USERNAME    Registry username for authentication
#   BUNDLE_EXTRACT_REGISTRY_PASSWORD    Registry password for authentication
#                                       (credentials are passed via temporary env file)
#
# Requirements: podman, go
# Exit codes: 0 = success, 1 = failure
#

set -euo pipefail

# Error trap for better debugging
trap 'echo "ERROR: Script failed at line $LINENO" >&2; exit 1' ERR

# ==============================================================================
# CONFIGURATION
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# helmtemplate-generator Go module (used via go run)
HELMTEMPLATE_GENERATOR_PKG="github.com/davidebianchi/helmtemplate-generator@3bc347fc1affd320b7829e64d262c9c5c6f4c40f"

# OLM extractor image
OLM_EXTRACTOR_IMAGE="quay.io/lburgazzoli/olm-extractor:main"

# Template subdirectories (used for cleanup and creation)
TEMPLATE_SUBDIRS=("crds" "rbac" "manager" "webhooks")

# ==============================================================================
# VARIABLES
# ==============================================================================

BUNDLE_VERSION=""
BUNDLE_IMAGE=""
CONFIG_FILE=""
NAMESPACE=""
OUTPUT_DIR=""
CHART_DESCRIPTION=""
USE_USER_AUTH=false
RAW_YAML=""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Extract OLM bundle resources and save as Helm chart templates.

Options:
  -b, --bundle <image>         Full bundle image (required)
  -c, --config <file>          helmtemplate-generator config file (required)
  -n, --namespace <ns>         Target namespace (required)
  -o, --output <dir>           Output chart directory (required)
  -v, --version <version>      Bundle version for Chart.yaml appVersion (optional)
  --chart-description <desc>   Chart description for Chart.yaml (optional)
  --use-user-auth              Use current user's podman credentials
  -h, --help                   Show this help message

Environment variables:
  BUNDLE_EXTRACT_REGISTRY_USERNAME    Registry username for authentication
  BUNDLE_EXTRACT_REGISTRY_PASSWORD    Registry password for authentication
                                      (credentials are passed via temporary env file)

Examples:
  # Extract operator bundle
  $(basename "$0") --bundle quay.io/org/operator-bundle:v1.0.0 \\
    --config path/to/config.yaml --namespace my-operator --output charts/my-operator

  # Extract with authentication (using env vars)
  BUNDLE_EXTRACT_REGISTRY_USERNAME=\$USER BUNDLE_EXTRACT_REGISTRY_PASSWORD=\$PASS \\
    $(basename "$0") --bundle registry.redhat.io/org/bundle:v1.0.0 \\
    --config path/to/config.yaml --namespace my-operator --output charts/my-operator

  # Extract using existing podman credentials
  $(basename "$0") --bundle registry.redhat.io/org/bundle:v1.0.0 \\
    --config path/to/config.yaml --namespace my-operator --output charts/my-operator \\
    --use-user-auth
EOF
}

validate_requirements() {
    local errors=0

    # Check podman
    if ! command -v podman &> /dev/null; then
        echo "ERROR: podman is not installed or not in PATH"
        errors=$((errors + 1))
    fi

    # Check go (needed for go run helmtemplate-generator)
    if ! command -v go &> /dev/null; then
        echo "ERROR: go is not installed or not in PATH"
        errors=$((errors + 1))
    fi

    # Check required flags
    if [[ -z "${BUNDLE_IMAGE}" ]]; then
        echo "ERROR: --bundle is required"
        errors=$((errors + 1))
    fi

    if [[ -z "${CONFIG_FILE}" ]]; then
        echo "ERROR: --config is required"
        errors=$((errors + 1))
    elif [[ ! -f "${CONFIG_FILE}" ]]; then
        echo "ERROR: Config file not found at ${CONFIG_FILE}"
        errors=$((errors + 1))
    fi

    if [[ -z "${NAMESPACE}" ]]; then
        echo "ERROR: --namespace is required"
        errors=$((errors + 1))
    fi

    if [[ -z "${OUTPUT_DIR}" ]]; then
        echo "ERROR: --output is required"
        errors=$((errors + 1))
    fi

    if [[ ${errors} -gt 0 ]]; then
        echo ""
        show_help
        exit 1
    fi
}

cleanup_templates() {
    echo "Cleaning up existing templates..."

    # Remove existing template subdirectories
    for subdir in "${TEMPLATE_SUBDIRS[@]}"; do
        rm -rf "${OUTPUT_DIR}/templates/${subdir}"
    done

    # Remove any .yaml files at templates root (preserve _helpers.tpl, validation.yaml)
    if [[ -d "${OUTPUT_DIR}/templates" ]]; then
        find "${OUTPUT_DIR}/templates" -maxdepth 1 -name "*.yaml" ! -name "validation.yaml" -delete 2>/dev/null || true
    fi

    echo "  Done"
}

extract_bundle() {
    echo "Extracting OLM bundle..."
    echo "  Image: ${BUNDLE_IMAGE}"
    echo "  Namespace: ${NAMESPACE}"
    echo ""

    local volume_flags=()
    local env_file_flags=()
    local temp_env_file=""

    if [[ "${USE_USER_AUTH}" == "true" ]]; then
        # Mount user's containers auth file into the extractor
        local auth_file="${XDG_RUNTIME_DIR:-}/containers/auth.json"
        if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -f "${auth_file}" ]]; then
            auth_file="${HOME}/.config/containers/auth.json"
        fi
        if [[ -f "${auth_file}" ]]; then
            volume_flags+=("-v" "${auth_file}:/root/.docker/config.json:z")
            echo "  Using credentials from: ${auth_file}"
        else
            echo "WARNING: No podman auth file found. Run 'podman login' first."
        fi
    elif [[ -n "${BUNDLE_EXTRACT_REGISTRY_USERNAME:-}" && -n "${BUNDLE_EXTRACT_REGISTRY_PASSWORD:-}" ]]; then
        # Create a temporary env file to avoid exposing credentials in process list
        temp_env_file=$(mktemp)
        # Ensure cleanup on exit, error, or interrupt
        trap '[[ -n "${temp_env_file:-}" ]] && rm -f "${temp_env_file}"' EXIT
        chmod 600 "${temp_env_file}"
        printf 'BUNDLE_EXTRACT_REGISTRY_USERNAME=%s\n' "${BUNDLE_EXTRACT_REGISTRY_USERNAME}" > "${temp_env_file}"
        printf 'BUNDLE_EXTRACT_REGISTRY_PASSWORD=%s\n' "${BUNDLE_EXTRACT_REGISTRY_PASSWORD}" >> "${temp_env_file}"
        env_file_flags+=("--env-file" "${temp_env_file}")
        echo "  Using credentials from environment variables (via temporary file)"
    fi

    # Extract bundle using podman
    # Capture to RAW_YAML - only podman output is captured, not echo statements
    if ! RAW_YAML=$(podman run --rm \
        "${volume_flags[@]}" \
        "${env_file_flags[@]}" \
        "${OLM_EXTRACTOR_IMAGE}" run \
        "${BUNDLE_IMAGE}" \
        -n "${NAMESPACE}" \
        --cert-manager-enabled=true); then
        # Clean up temp env file if it exists
        [[ -n "${temp_env_file}" ]] && rm -f "${temp_env_file}"
        echo "ERROR: Failed to extract OLM bundle from ${BUNDLE_IMAGE}" >&2
        exit 1
    fi

    # Clean up temp env file if it exists
    [[ -n "${temp_env_file}" ]] && rm -f "${temp_env_file}"

    # Validate we got some YAML output
    if [[ -z "${RAW_YAML}" ]]; then
        echo "ERROR: No YAML output received from bundle extraction" >&2
        exit 1
    fi
}

generate_helm_chart() {
    # Derive chart name from output directory basename
    local chart_name
    chart_name="$(basename "${OUTPUT_DIR}")"

    local app_version="${BUNDLE_VERSION:-unknown}"
    # Remove leading 'v' from version for appVersion
    app_version="${app_version#v}"

    local description="${CHART_DESCRIPTION:-${chart_name} Helm chart}"

    # Resolve template-dir from the config file location
    local template_dir
    template_dir="$(cd "$(dirname "${CONFIG_FILE}")" && pwd)"

    echo "Running helmtemplate-generator..."
    echo "  Chart name: ${chart_name}"
    echo ""

    # Pipe extracted YAML through helmtemplate-generator
    local rc=0
    echo "${RAW_YAML}" | go run "${HELMTEMPLATE_GENERATOR_PKG}" \
        -c "${CONFIG_FILE}" \
        -o "${OUTPUT_DIR}" \
        --template-dir "${template_dir}" \
        --chart-name "${chart_name}" \
        --default-namespace "${NAMESPACE}" \
        --chart-description "${description}" \
        --app-version "${app_version}" \
        || rc=$?

    if [[ ${rc} -ne 0 ]]; then
        echo "ERROR: helmtemplate-generator failed" >&2
        exit ${rc}
    fi

    echo "  Done"
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --version requires a value"
                show_help
                exit 1
            fi
            BUNDLE_VERSION="$2"
            shift 2
            ;;
        -b|--bundle)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --bundle requires a value"
                show_help
                exit 1
            fi
            BUNDLE_IMAGE="$2"
            shift 2
            ;;
        -c|--config)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --config requires a value"
                show_help
                exit 1
            fi
            CONFIG_FILE="$2"
            shift 2
            ;;
        -n|--namespace)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --namespace requires a value"
                show_help
                exit 1
            fi
            NAMESPACE="$2"
            shift 2
            ;;
        -o|--output)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --output requires a value"
                show_help
                exit 1
            fi
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --chart-description)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --chart-description requires a value"
                show_help
                exit 1
            fi
            CHART_DESCRIPTION="$2"
            shift 2
            ;;
        --use-user-auth)
            USE_USER_AUTH=true
            shift
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

    echo "=============================================================================="
    echo "OLM Bundle Extractor"
    echo "=============================================================================="
    echo ""
    echo "Configuration:"
    echo "  Bundle:      ${BUNDLE_IMAGE}"
    echo "  Namespace:   ${NAMESPACE}"
    echo "  Output:      ${OUTPUT_DIR}"
    echo "  Config:      ${CONFIG_FILE}"
    echo ""

    # Create output directory
    mkdir -p "${OUTPUT_DIR}/templates"

    # Step 1: Clean up existing templates
    cleanup_templates
    echo ""

    # Step 2: Extract bundle
    extract_bundle
    echo ""

    # Step 3: Generate Helm chart (process YAML, apply templating, generate chart files)
    generate_helm_chart

    echo ""
    echo "=============================================================================="
    echo "Extraction complete"
    echo "=============================================================================="
    echo ""
    echo "Chart generated at: ${OUTPUT_DIR}"
    echo ""
    echo "Next steps:"
    echo "  1. Review generated templates"
    echo "  2. Run: helm lint ${OUTPUT_DIR}"
    echo "  3. Run: helm template test ${OUTPUT_DIR}"
    echo ""
}

main "$@"
