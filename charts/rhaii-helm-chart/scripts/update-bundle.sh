#!/usr/bin/env bash
# Update RHAI operator Helm chart from OLM bundle and cloudmanager resources
#
# Usage:
#   ./update-bundle.sh <version> [extra-args...]
#
# Options:
#   --odh-operator-dir <path>   Path to opendatahub-operator checkout
#                               (default: ../opendatahub-operator relative to repo root)
#
# Examples:
#   ./update-bundle.sh v2.19.0
#   ./update-bundle.sh v2.19.0 --odh-operator-dir /path/to/opendatahub-operator
#   BUNDLE_EXTRACT_REGISTRY_USERNAME=$USER BUNDLE_EXTRACT_REGISTRY_PASSWORD=$PASS \
#     ./update-bundle.sh v2.19.0

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [extra-args...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CHART_DIR}/../.." && pwd)"

BUNDLE_IMAGE="registry.redhat.io/rhoai/odh-operator-bundle:${VERSION}"
NAMESPACE="redhat-ods-operator"

# helmtemplate-generator Go module (must match scripts/extract-olm-bundle.sh)
HELMTEMPLATE_GENERATOR_PKG="github.com/davidebianchi/helmtemplate-generator@3bc347fc1affd320b7829e64d262c9c5c6f4c40f"

# Cloud mappings: <cloud_name> <kustomize_subdir> <output_subdir>
CLOUD_TARGETS=(
    "azure azure cloudmanager/azure"
    "coreweave coreweave cloudmanager/coreweave"
)

# Default path to opendatahub-operator repo
ODH_OPERATOR_DIR="${REPO_ROOT}/../opendatahub-operator"

# ==============================================================================
# Parse extra args (extract --odh-operator-dir before passing rest to extract-olm-bundle)
# ==============================================================================

EXTRA_ARGS=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --odh-operator-dir)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --odh-operator-dir requires a value" >&2
                exit 1
            fi
            ODH_OPERATOR_DIR="$2"
            shift 2
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# ==============================================================================
# Step 1: Extract OLM bundle
# ==============================================================================

"${REPO_ROOT}/scripts/extract-olm-bundle.sh" \
    --bundle "${BUNDLE_IMAGE}" \
    --version "${VERSION}" \
    --namespace "${NAMESPACE}" \
    --config "${SCRIPT_DIR}/helmtemplate-config.yaml" \
    --output "${CHART_DIR}" \
    --chart-description "Red Hat OpenShift AI Operator Helm chart (non-OLM installation)" \
    --use-user-auth \
    "${EXTRA_ARGS[@]}"

# ==============================================================================
# Step 2: Generate cloudmanager templates from kustomize
# ==============================================================================

# Validate requirements
if ! command -v kustomize &> /dev/null; then
    echo "ERROR: kustomize is not installed or not in PATH" >&2
    exit 1
fi

if ! command -v go &> /dev/null; then
    echo "ERROR: go is not installed or not in PATH" >&2
    exit 1
fi

if [[ ! -d "${ODH_OPERATOR_DIR}" ]]; then
    echo "ERROR: opendatahub-operator directory not found at ${ODH_OPERATOR_DIR}" >&2
    echo "Clone it with: git clone git@github.com:davidebianchi/opendatahub-operator.git ${ODH_OPERATOR_DIR}" >&2
    exit 1
fi

echo ""
echo "=============================================================================="
echo "Cloudmanager Templates"
echo "=============================================================================="
echo ""
echo "Configuration:"
echo "  ODH Operator: ${ODH_OPERATOR_DIR}"
echo ""

# Clean up existing cloudmanager templates
echo "Cleaning up existing cloudmanager templates..."
rm -rf "${CHART_DIR}/templates/cloudmanager"
echo "  Done"
echo ""

for target_entry in "${CLOUD_TARGETS[@]}"; do
    read -r cloud_name kustomize_subdir output_subdir <<< "${target_entry}"

    kustomize_path="${ODH_OPERATOR_DIR}/config/cloudmanager/${kustomize_subdir}/default/"
    output_path="${CHART_DIR}/templates/${output_subdir}"

    echo "Processing ${cloud_name} (${kustomize_subdir})..."
    echo "  Kustomize: ${kustomize_path}"
    echo "  Output:    ${output_path}"

    if [[ ! -d "${kustomize_path}" ]]; then
        echo "ERROR: Kustomize directory not found: ${kustomize_path}" >&2
        exit 1
    fi

    # Create temp config with placeholders replaced
    temp_config=$(mktemp)
    trap 'rm -f "${temp_config}"' EXIT
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
