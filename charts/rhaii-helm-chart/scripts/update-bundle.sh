#!/usr/bin/env bash
# Update RHAII operator Helm chart from opendatahub-operator repo and cloudmanager resources.
#
# By default, the opendatahub-operator repo is shallow-cloned from GitHub.
# Use --odh-operator-dir to point to a local checkout instead.
#
# Usage:
#   ./update-bundle.sh <version> [options...]
#
# Options:
#   --odh-operator-dir <path>   Path to a local opendatahub-operator checkout.
#                               Skips cloning from GitHub when set.
#   --branch <branch>           Branch to clone (default: main).
#                               Ignored when --odh-operator-dir is set.
#
# Examples:
#   ./update-bundle.sh v2.19.0
#   ./update-bundle.sh v2.19.0 --branch feat/my-branch
#   ./update-bundle.sh v2.19.0 --odh-operator-dir /path/to/opendatahub-operator

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [options...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

NAMESPACE="redhat-ods-operator"

# helmtemplate-generator Go module
HELMTEMPLATE_GENERATOR_PKG="github.com/davidebianchi/helmtemplate-generator@7d76ac29fe5f7cdc6a6c9b953f8dc715ee348bef"

# Cloud mappings: <cloud_name> <kustomize_subdir> <output_subdir>
CLOUD_TARGETS=(
    "azure azure cloudmanager/azure"
    "coreweave coreweave cloudmanager/coreweave"
)

# Defaults
ODH_REPO_URL="git@github.com:opendatahub-io/opendatahub-operator.git"
ODH_BRANCH="main"
ODH_OPERATOR_DIR=""
LOCAL_MODE=false

# ==============================================================================
# Parse args
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --odh-operator-dir)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --odh-operator-dir requires a value" >&2
                exit 1
            fi
            ODH_OPERATOR_DIR="$2"
            LOCAL_MODE=true
            shift 2
            ;;
        --branch)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --branch requires a value" >&2
                exit 1
            fi
            ODH_BRANCH="$2"
            shift 2
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ==============================================================================
# Validate requirements
# ==============================================================================

if ! command -v kustomize &> /dev/null; then
    echo "ERROR: kustomize is not installed or not in PATH" >&2
    exit 1
fi
if ! command -v go &> /dev/null; then
    echo "ERROR: go is not installed or not in PATH" >&2
    exit 1
fi

# ==============================================================================
# Resolve opendatahub-operator directory
# ==============================================================================

if [[ "${LOCAL_MODE}" == "true" ]]; then
    if [[ ! -d "${ODH_OPERATOR_DIR}" ]]; then
        echo "ERROR: opendatahub-operator directory not found at ${ODH_OPERATOR_DIR}" >&2
        exit 1
    fi
    echo "Using local opendatahub-operator: ${ODH_OPERATOR_DIR}"
else
    ODH_OPERATOR_DIR="$(mktemp -d)"
    trap 'rm -rf "${ODH_OPERATOR_DIR}"' EXIT

    echo "Cloning opendatahub-operator (branch: ${ODH_BRANCH})..."
    git clone --depth 1 --branch "${ODH_BRANCH}" "${ODH_REPO_URL}" "${ODH_OPERATOR_DIR}"
    echo "  Done"
    echo ""
fi

# ==============================================================================
# Step 1: Generate operator templates
# ==============================================================================

echo "Running 'make manifests-all' in opendatahub-operator..."
make -C "${ODH_OPERATOR_DIR}" manifests-all
echo "  Done"
echo ""

RHAI_KUSTOMIZE_PATH="${ODH_OPERATOR_DIR}/config/rhaii/rhoai/default/"
if [[ ! -d "${RHAI_KUSTOMIZE_PATH}" ]]; then
    echo "ERROR: Kustomize directory not found: ${RHAI_KUSTOMIZE_PATH}" >&2
    exit 1
fi

echo "=============================================================================="
echo "Operator Templates (from operator repo)"
echo "=============================================================================="
echo ""
echo "Configuration:"
echo "  Source:      ${RHAI_KUSTOMIZE_PATH}"
echo "  Namespace:   ${NAMESPACE}"
echo "  Output:      ${CHART_DIR}"
echo "  Config:      ${SCRIPT_DIR}/helmtemplate-config.yaml"
echo ""

# Clean existing template subdirs
echo "Cleaning up existing templates..."
for subdir in crds rbac manager webhooks; do
    rm -rf "${CHART_DIR}/templates/${subdir}"
done
if [[ -d "${CHART_DIR}/templates" ]]; then
    find "${CHART_DIR}/templates" -maxdepth 1 -name "*.yaml" ! -name "validation.yaml" ! -name "pull-secret.yaml" -delete 2>/dev/null || true
fi
mkdir -p "${CHART_DIR}/templates"
echo "  Done"
echo ""

APP_VERSION="${VERSION#v}"

echo "Running kustomize build and helmtemplate-generator..."
kustomize build "${RHAI_KUSTOMIZE_PATH}" | go run "${HELMTEMPLATE_GENERATOR_PKG}" \
    -c "${SCRIPT_DIR}/helmtemplate-config.yaml" \
    -o "${CHART_DIR}" \
    --template-dir "${SCRIPT_DIR}" \
    --chart-name "rhaii-helm-chart" \
    --default-namespace "${NAMESPACE}" \
    --chart-description "Red Hat OpenShift AI Operator Helm chart (non-OLM installation)" \
    --app-version "${APP_VERSION}"

echo "  Done"

# ==============================================================================
# Step 2: Generate cloudmanager templates from kustomize
# ==============================================================================

echo ""
echo "=============================================================================="
echo "Cloudmanager Templates"
echo "=============================================================================="
echo ""
echo "Configuration:"
echo "  ODH Operator: ${ODH_OPERATOR_DIR}"
echo ""

for target_entry in "${CLOUD_TARGETS[@]}"; do
    read -r cloud_name kustomize_subdir output_subdir <<< "${target_entry}"

    kustomize_path="${ODH_OPERATOR_DIR}/config/cloudmanager/${kustomize_subdir}/rhoai/"
    output_path="${CHART_DIR}/templates/${output_subdir}"

    # Clean only auto-generated subdirectories, preserving manually-created files (e.g. CR templates)
    echo "Cleaning up auto-generated templates for ${cloud_name}..."
    for subdir in crds manager rbac webhooks; do
        rm -rf "${output_path}/${subdir}"
    done
    echo "  Done"
    echo ""

    echo "Processing ${cloud_name} (${kustomize_subdir})..."
    echo "  Kustomize: ${kustomize_path}"
    echo "  Output:    ${output_path}"

    if [[ ! -d "${kustomize_path}" ]]; then
        echo "ERROR: Kustomize directory not found: ${kustomize_path}" >&2
        exit 1
    fi

    # Create temp config with placeholders replaced
    temp_config=$(mktemp)
    sed -e "s/CLOUD_NAME/${cloud_name}/g" \
        -e "s|CLOUD_DIR|${output_subdir}|g" \
        "${SCRIPT_DIR}/helmtemplate-config-cloudmanager.yaml" > "${temp_config}"

    # Run kustomize and pipe through helmtemplate-generator
    kustomize build "${kustomize_path}" | go run "${HELMTEMPLATE_GENERATOR_PKG}" \
        -c "${temp_config}" \
        -o "${CHART_DIR}" \
        --template-dir "${SCRIPT_DIR}" \
        --chart-name "rhaii-helm-chart" \
        --default-namespace "${NAMESPACE}"

    rm -f "${temp_config}"

    echo "  Done"
    echo ""
done

echo "=============================================================================="
echo "Cloudmanager extraction complete"
echo "=============================================================================="
echo ""
