#!/usr/bin/env bash
# Update RHAI operator Helm chart from RHDS rhods-operator git repo and cloudmanager resources.
#
# By default, the rhods-operator repo is shallow-cloned from GitHub.
# Use --odh-operator-dir to point to a local checkout instead.
#
# Usage:
#   ./update-bundle.sh <version> [options...]
#
# Options:
#   --odh-operator-dir <path>   Path to a local rhods-operator checkout.
#                               Skips cloning from GitHub when set.
#   --branch <branch>           Branch to clone (default: rhoai-3.4-ea.2).
#                               Ignored when --odh-operator-dir is set.
#
# Examples:
#   ./update-bundle.sh 3.4.0-ea.2
#   ./update-bundle.sh 3.4.0 --branch rhoai-3.4
#   ./update-bundle.sh 3.4.0-ea.2 --odh-operator-dir /path/to/rhods-operator

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
ODH_REPO_URL="https://github.com/red-hat-data-services/rhods-operator.git"
ODH_BRANCH="rhoai-3.4"
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
# Resolve rhods-operator directory
# ==============================================================================

if [[ "${LOCAL_MODE}" == "true" ]]; then
    if [[ ! -d "${ODH_OPERATOR_DIR}" ]]; then
        echo "ERROR: rhods-operator directory not found at ${ODH_OPERATOR_DIR}" >&2
        exit 1
    fi
    echo "Using local rhods-operator: ${ODH_OPERATOR_DIR}"
else
    ODH_OPERATOR_DIR="$(mktemp -d)"
    trap 'rm -rf "${ODH_OPERATOR_DIR}"' EXIT

    echo "Cloning rhods-operator (branch: ${ODH_BRANCH})..."
    git clone --depth 1 --branch "${ODH_BRANCH}" "${ODH_REPO_URL}" "${ODH_OPERATOR_DIR}"
    echo "  Done"
    echo ""
fi

# ==============================================================================
# Step 1: Generate operator templates
# ==============================================================================

echo "Running 'make manifests-all' in rhods-operator..."
make -C "${ODH_OPERATOR_DIR}" manifests-all
echo "  Done"
echo ""

echo "Generating kustomization.yaml from templates..."
# Generate main operator kustomization (creates config/rhoai/manager/kustomization.yaml)
make -C "${ODH_OPERATOR_DIR}" manager-kustomization ODH_PLATFORM_TYPE=rhoai
# Generate cloudmanager kustomizations
for cloud in azure coreweave; do
    cp -f "${ODH_OPERATOR_DIR}/config/cloudmanager/${cloud}/manager/kustomization.yaml.in" \
          "${ODH_OPERATOR_DIR}/config/cloudmanager/${cloud}/manager/kustomization.yaml"
done
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
    --chart-name "rhai-on-xks-helm-chart" \
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
echo "  RHOAI Operator: ${ODH_OPERATOR_DIR}"
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
        --chart-name "rhai-on-xks-chart" \
        --default-namespace "${NAMESPACE}"

    rm -f "${temp_config}"

    echo "  Done"
    echo ""
done

echo "=============================================================================="
echo "Cloudmanager extraction complete"
echo "=============================================================================="
echo ""
