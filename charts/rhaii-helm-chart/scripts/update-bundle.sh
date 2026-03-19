#!/usr/bin/env bash
# Update RHAI operator Helm chart from opendatahub-operator repo (or OLM bundle)
# and cloudmanager resources
#
# By default, operator templates are generated from the opendatahub-operator repo
# (config/rhai) using kustomize. Use --from-olm to extract from an OLM bundle instead.
#
# Usage:
#   ./update-bundle.sh <version> [options...]
#
# Options:
#   --odh-operator-dir <path>   Path to opendatahub-operator checkout
#                               (default: ../opendatahub-operator relative to repo root)
#   --from-olm                  Use OLM bundle instead of opendatahub-operator repo
#                               for operator templates. Requires podman.
#
# Examples:
#   ./update-bundle.sh v2.19.0
#   ./update-bundle.sh v2.19.0 --odh-operator-dir /path/to/opendatahub-operator
#   ./update-bundle.sh v2.19.0 --from-olm
#   BUNDLE_EXTRACT_REGISTRY_USERNAME=$USER BUNDLE_EXTRACT_REGISTRY_PASSWORD=$PASS \
#     ./update-bundle.sh v2.19.0 --from-olm

set -euo pipefail

VERSION="${1:?Usage: $0 <version> [extra-args...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${CHART_DIR}/../.." && pwd)"

BUNDLE_IMAGE="registry.redhat.io/rhoai/odh-operator-bundle:${VERSION}"
NAMESPACE="redhat-ods-operator"
FROM_OPERATOR=true

# helmtemplate-generator Go module (must match scripts/extract-olm-bundle.sh)
HELMTEMPLATE_GENERATOR_PKG="github.com/davidebianchi/helmtemplate-generator@97f92726d411785dd9eb359b371ba704c022fbcd"

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
        --from-olm)
            FROM_OPERATOR=false
            shift
            ;;
        *)
            EXTRA_ARGS+=("$1")
            shift
            ;;
    esac
done

# ==============================================================================
# Step 1: Generate operator templates
# ==============================================================================

if [[ "${FROM_OPERATOR}" == "true" ]]; then
    # --- From operator repo (kustomize) ---

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

    # Clean existing template subdirs (same as extract-olm-bundle.sh does)
    echo "Cleaning up existing templates..."
    for subdir in crds rbac manager webhooks; do
        rm -rf "${CHART_DIR}/templates/${subdir}"
    done
    if [[ -d "${CHART_DIR}/templates" ]]; then
        find "${CHART_DIR}/templates" -maxdepth 1 -name "*.yaml" ! -name "validation.yaml" -delete 2>/dev/null || true
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
else
    # --- From OLM bundle (existing behavior) ---
    "${REPO_ROOT}/scripts/extract-olm-bundle.sh" \
        --bundle "${BUNDLE_IMAGE}" \
        --version "${VERSION}" \
        --namespace "${NAMESPACE}" \
        --config "${SCRIPT_DIR}/helmtemplate-config.yaml" \
        --output "${CHART_DIR}" \
        --chart-description "Red Hat OpenShift AI Operator Helm chart (non-OLM installation)" \
        --use-user-auth \
        "${EXTRA_ARGS[@]}"
fi

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
