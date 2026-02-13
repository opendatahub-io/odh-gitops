#!/usr/bin/env bash
#
# extract-olm-bundle.sh - Extract OLM bundle resources and save as Helm chart templates
#
# Usage:
#   ./extract-olm-bundle.sh [options]
#
# Options:
#   -t, --type <odh|rhoai>       Operator type (required)
#   -v, --version <version>      Bundle version (required unless --bundle is set)
#   -b, --bundle <image>         Full bundle image (overrides type+version)
#   -n, --namespace <ns>         Target namespace (optional, defaults based on type)
#   -o, --output <dir>           Output chart directory (default: charts/<type>-operator)
#   --use-user-auth              Use current user's podman credentials
#   -h, --help                   Show this help message
#
# Environment variables:
#   BUNDLE_EXTRACT_REGISTRY_USERNAME    Registry username for authentication
#   BUNDLE_EXTRACT_REGISTRY_PASSWORD    Registry password for authentication
#
# Requirements: podman, yq (bin/yq)
# Exit codes: 0 = success, 1 = failure
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

# Use gsed on macOS (Darwin), sed on Linux
if [[ "$(uname -s)" == "Darwin" ]]; then
    SED="gsed"
else
    SED="sed"
fi

# Default bundle image bases
ODH_BUNDLE_BASE="quay.io/opendatahub/opendatahub-operator-bundle"
RHOAI_BUNDLE_BASE="registry.redhat.io/rhoai/odh-operator-bundle"

# Default namespaces
ODH_NAMESPACE="opendatahub-operator-system"
RHOAI_NAMESPACE="redhat-ods-operator"

# OLM extractor image
OLM_EXTRACTOR_IMAGE="quay.io/lburgazzoli/olm-extractor:main"

# Template subdirectories (used for cleanup and creation)
TEMPLATE_SUBDIRS=("crds" "rbac" "manager" "webhooks")

# External template files directory
TEMPLATES_DIR="${SCRIPT_DIR}/templates"

# ==============================================================================
# VARIABLES
# ==============================================================================

OPERATOR_TYPE=""
BUNDLE_VERSION=""
BUNDLE_IMAGE=""
NAMESPACE=""
OUTPUT_DIR=""
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
  -t, --type <odh|rhoai>       Operator type (required)
  -v, --version <version>      Bundle version (required unless --bundle is set, e.g., v3.3.0)
  -b, --bundle <image>         Full bundle image (overrides type+version, makes --version optional)
  -n, --namespace <ns>         Target namespace (optional, defaults based on type)
  -o, --output <dir>           Output chart directory (default: charts/<type>-operator)
  --use-user-auth              Use current user's podman credentials
  -h, --help                   Show this help message

Environment variables:
  BUNDLE_EXTRACT_REGISTRY_USERNAME    Registry username for authentication
  BUNDLE_EXTRACT_REGISTRY_PASSWORD    Registry password for authentication

Examples:
  # Extract ODH operator bundle
  $(basename "$0") --type odh --version v3.3.0

  # Extract RHOAI operator bundle with authentication (using env vars)
  BUNDLE_EXTRACT_REGISTRY_USERNAME=\$USER BUNDLE_EXTRACT_REGISTRY_PASSWORD=\$PASS $(basename "$0") --type rhoai --version v2.19.0

  # Extract RHOAI operator bundle using existing podman credentials
  $(basename "$0") --type rhoai --version v2.19.0 --use-user-auth

  # Extract using a custom bundle image
  $(basename "$0") --type odh --bundle quay.io/opendatahub/opendatahub-operator-bundle@sha256:abc123
EOF
}

validate_requirements() {
    local errors=0

    # Check bash version (4.0+ required for ${var,,} lowercase syntax)
    if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
        echo "ERROR: bash 4.0+ is required (found ${BASH_VERSION})"
        errors=$((errors + 1))
    fi

    # Check podman
    if ! command -v podman &> /dev/null; then
        echo "ERROR: podman is not installed or not in PATH"
        errors=$((errors + 1))
    fi

    # Check yq
    if [[ ! -x "${YQ}" ]]; then
        echo "ERROR: yq not found at ${YQ}"
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

    # Check type is set
    if [[ -z "${OPERATOR_TYPE}" ]]; then
        echo "ERROR: --type is required"
        errors=$((errors + 1))
    elif [[ "${OPERATOR_TYPE}" != "odh" && "${OPERATOR_TYPE}" != "rhoai" ]]; then
        echo "ERROR: --type must be 'odh' or 'rhoai', got '${OPERATOR_TYPE}'"
        errors=$((errors + 1))
    fi

    # Check version or bundle is set
    if [[ -z "${BUNDLE_IMAGE}" && -z "${BUNDLE_VERSION}" ]]; then
        echo "ERROR: --version is required unless --bundle is provided"
        errors=$((errors + 1))
    fi

    if [[ ${errors} -gt 0 ]]; then
        echo ""
        show_help
        exit 1
    fi
}

set_defaults() {
    # Set bundle image based on type and version
    if [[ -z "${BUNDLE_IMAGE}" ]]; then
        if [[ "${OPERATOR_TYPE}" == "odh" ]]; then
            BUNDLE_IMAGE="${ODH_BUNDLE_BASE}:${BUNDLE_VERSION}"
        else
            BUNDLE_IMAGE="${RHOAI_BUNDLE_BASE}:${BUNDLE_VERSION}"
        fi
    fi

    # Set namespace based on type
    if [[ -z "${NAMESPACE}" ]]; then
        if [[ "${OPERATOR_TYPE}" == "odh" ]]; then
            NAMESPACE="${ODH_NAMESPACE}"
        else
            NAMESPACE="${RHOAI_NAMESPACE}"
        fi
    fi

    # Set output directory
    if [[ -z "${OUTPUT_DIR}" ]]; then
        OUTPUT_DIR="${REPO_ROOT}/charts/${OPERATOR_TYPE}-operator"
    fi
}

cleanup_templates() {
    echo "Cleaning up existing templates..."

    # Remove existing template subdirectories
    for subdir in "${TEMPLATE_SUBDIRS[@]}"; do
        rm -rf "${OUTPUT_DIR}/templates/${subdir}"
    done

    # Remove any .yaml files at templates root (preserve _helpers.tpl)
    if [[ -d "${OUTPUT_DIR}/templates" ]]; then
        find "${OUTPUT_DIR}/templates" -maxdepth 1 -name "*.yaml" -delete 2>/dev/null || true
    fi

    echo "  Done"
}

extract_bundle() {
    echo "Extracting OLM bundle..."
    echo "  Image: ${BUNDLE_IMAGE}"
    echo "  Namespace: ${NAMESPACE}"
    echo ""

    local volume_flags=""
    local auth_env_flags=""

    if [[ "${USE_USER_AUTH}" == "true" ]]; then
        # Mount user's containers auth file into the extractor
        local auth_file="${XDG_RUNTIME_DIR}/containers/auth.json"
        if [[ ! -f "${auth_file}" ]]; then
            auth_file="${HOME}/.config/containers/auth.json"
        fi
        if [[ -f "${auth_file}" ]]; then
            volume_flags="-v ${auth_file}:/run/containers/0/auth.json:ro"
            echo "  Using credentials from: ${auth_file}"
        else
            echo "WARNING: No podman auth file found. Run 'podman login' first."
        fi
    elif [[ -n "${BUNDLE_EXTRACT_REGISTRY_USERNAME:-}" && -n "${BUNDLE_EXTRACT_REGISTRY_PASSWORD:-}" ]]; then
        auth_env_flags="-e BUNDLE_EXTRACT_REGISTRY_USERNAME=${BUNDLE_EXTRACT_REGISTRY_USERNAME} -e BUNDLE_EXTRACT_REGISTRY_PASSWORD=${BUNDLE_EXTRACT_REGISTRY_PASSWORD}"
        echo "  Using credentials from environment variables"
    fi

    # Extract bundle using podman
    # Capture to RAW_YAML - only podman output is captured, not echo statements
    # shellcheck disable=SC2086
    if ! RAW_YAML=$(podman run --rm \
        ${volume_flags} \
        ${auth_env_flags} \
        "${OLM_EXTRACTOR_IMAGE}" run \
        "${BUNDLE_IMAGE}" \
        -n "${NAMESPACE}" \
        --cert-manager-enabled=false); then
        echo "ERROR: Failed to extract OLM bundle from ${BUNDLE_IMAGE}" >&2
        exit 1
    fi

    # Validate we got some YAML output
    if [[ -z "${RAW_YAML}" ]]; then
        echo "ERROR: No YAML output received from bundle extraction" >&2
        exit 1
    fi
}

get_target_dir() {
    local kind="$1"
    local name="$2"

    case "${kind}" in
        CustomResourceDefinition)
            echo "crds"
            ;;
        Role|RoleBinding|ClusterRole|ClusterRoleBinding|ServiceAccount)
            echo "rbac"
            ;;
        Deployment|Namespace)
            echo "manager"
            ;;
        ValidatingWebhookConfiguration|MutatingWebhookConfiguration)
            echo "webhooks"
            ;;
        Service)
            # Services with "webhook" in name go to webhooks/
            if [[ "${name}" == *webhook* ]]; then
                echo "webhooks"
            else
                echo "manager"  # Empty means templates root
            fi
            ;;
        *)
            echo ""  # Empty means templates root
            ;;
    esac
}

wrap_with_helm_conditional() {
    local kind="$1"
    local content="$2"

    local conditional
    if [[ "${kind}" == "CustomResourceDefinition" ]]; then
        conditional='{{- if .Values.installCRDs }}'
    else
        conditional='{{- if .Values.enabled }}'
    fi

    echo "${conditional}"
    echo "${content}"
    echo '{{- end }}'
}

process_yaml_documents() {
    local raw_yaml="$1"
    local processed=0

    # Create output directories
    for subdir in "${TEMPLATE_SUBDIRS[@]}"; do
        mkdir -p "${OUTPUT_DIR}/templates/${subdir}"
    done

    echo "Processing YAML documents..."

    # Process documents sequentially until exhausted
    local index=0
    while true; do
        local doc
        doc=$(echo "${raw_yaml}" | "${YQ}" eval "select(documentIndex == ${index})" -)

        # Exit loop if no more documents
        if [[ -z "${doc}" || "${doc}" == "null" ]]; then
            break
        fi

        # Get kind and name
        local kind name
        kind=$(echo "${doc}" | "${YQ}" eval '.kind // ""' -)
        name=$(echo "${doc}" | "${YQ}" eval '.metadata.name // ""' -)

        # Skip if kind or name is empty and warn
        if [[ -z "${kind}" || -z "${name}" ]]; then
            echo "  WARNING: Skipping document at index ${index} - missing kind or name" >&2
            index=$((index + 1))
            continue
        fi

        local target_dir
        target_dir=$(get_target_dir "${kind}" "${name}")

        # Build filename: lowercase kind-name.yaml (bash 4+ lowercase)
        local kind_lower="${kind,,}"
        local filename="${kind_lower}-${name}.yaml"

        # Determine full path
        local output_path
        if [[ -n "${target_dir}" ]]; then
            output_path="${OUTPUT_DIR}/templates/${target_dir}/${filename}"
        else
            output_path="${OUTPUT_DIR}/templates/${filename}"
        fi

        # Wrap with Helm conditional and write
        wrap_with_helm_conditional "${kind}" "${doc}" > "${output_path}"
        echo "  Created: ${output_path}"

        processed=$((processed + 1))
        index=$((index + 1))
    done

    echo ""
    echo "Processed ${processed} resources"
}

# ==============================================================================
# HELM SUBSTITUTIONS CONFIGURATION
# ==============================================================================
# Define substitutions in a declarative way. Each entry specifies:
#   type@pattern@match@replacement@kind_filter@description
#
# Types:
#   sed        - Simple text replacement using sed (good for string substitutions)
#   sed-insert - Insert a line before the matched pattern (good for adding new fields)
#   sed-delete - Delete lines matching the pattern
#
# To add new substitutions, simply add entries to this function.
# ==============================================================================

get_helm_substitutions() {
    local chart_name="$1"
    local namespace="$2"

    # Escape namespace for sed regex (handle all special regex chars)
    # Characters that need escaping in sed regex: . * [ ] ^ $ \ / &
    local ns_escaped
    ns_escaped=$(printf '%s' "${namespace}" | "${SED}" 's/[.[\*^$()+?{|/\\]/\\&/g')

    # Format: type@pattern@match@replacement@kind_filter@description
    # - type: sed or sed-insert
    # - pattern: the grep pattern to match
    # - match: the value to match/replace (for sed, literal string; unused for sed-insert)
    # - replacement: the new value (CHART_NAME placeholder will be replaced)
    # - kind_filter: optional, only apply to files containing this kind
    # - description: human-readable description
    #
    # NOTE: For sed substitutions, we use the literal namespace in 'match' field
    # and escape it at runtime in apply_substitution_sed
    cat << EOF
sed@namespace: ${ns_escaped}\$@namespace: ${namespace}@namespace: {{ include "CHART_NAME.namespace" . }}@@Replace namespace references
sed@name: ${ns_escaped}\$@name: ${namespace}@name: {{ include "CHART_NAME.namespace" . }}@Namespace@Replace Namespace resource name
sed-delete@^[[:space:]]*imagePullSecrets:@@@Deployment@Remove existing imagePullSecrets from Deployments
sed-insert@serviceAccountName:@@{{- include "CHART_NAME.imagePullSecrets" . | nindent 6 }}@Deployment@Add imagePullSecrets to Deployments
EOF
}

apply_substitution_sed() {
    local file="$1"
    local pattern="$2"
    local match="$3"
    local replacement="$4"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        # Escape special characters for sed substitution
        # Use a delimiter that won't appear in Helm templates: ASCII 001 (SOH)
        local delim=$'\x01'

        # Escape the match string for sed (literal matching)
        local match_escaped
        match_escaped=$(printf '%s' "${match}" | "${SED}" 's/[&/\]/\\&/g')

        # Escape the replacement string for sed (& and \ are special)
        local replacement_escaped
        replacement_escaped=$(printf '%s' "${replacement}" | "${SED}" 's/[&\]/\\&/g')

        "${SED}" -i.bak "s${delim}${match_escaped}${delim}${replacement_escaped}${delim}g" "${file}"
        rm -f "${file}.bak"
        return 0
    fi
    return 1
}

apply_substitution_sed_insert() {
    local file="$1"
    local pattern="$2"
    local insertion="$3"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        # Get the indentation of the pattern line and apply it to the insertion
        local indent
        indent=$(grep "${pattern}" "${file}" | head -1 | "${SED}" 's/\([[:space:]]*\).*/\1/')

        # Insert the line before the pattern match with proper indentation
        "${SED}" -i.bak "/${pattern}/i\\
${indent}${insertion}
" "${file}"
        rm -f "${file}.bak"
        return 0
    fi
    return 1
}

apply_substitution_sed_delete() {
    local file="$1"
    local pattern="$2"

    if grep -q "${pattern}" "${file}" 2>/dev/null; then
        "${SED}" -i.bak "/${pattern}/d" "${file}"
        rm -f "${file}.bak"
        return 0
    fi
    return 1
}

apply_helm_templating() {
    local chart_name="${OPERATOR_TYPE}-operator"
    local templates_dir="${OUTPUT_DIR}/templates"

    echo "Applying Helm templating..."

    # Get substitutions with chart name placeholder replaced
    local substitutions
    substitutions=$(get_helm_substitutions "${chart_name}" "${NAMESPACE}" | "${SED}" "s/CHART_NAME/${chart_name}/g")

    # Process each YAML file
    while IFS= read -r -d '' file; do
        local modified=false

        # Apply each substitution (using @ as delimiter to avoid conflicts with | in Helm templates)
        while IFS='@' read -r type pattern match replacement kind_filter description; do
            [[ -z "${type}" ]] && continue

            # Check kind filter if specified
            if [[ -n "${kind_filter}" ]] && ! grep -q "kind: ${kind_filter}" "${file}" 2>/dev/null; then
                continue
            fi

            case "${type}" in
                sed)
                    if apply_substitution_sed "${file}" "${pattern}" "${match}" "${replacement}"; then
                        modified=true
                    fi
                    ;;
                sed-insert)
                    if apply_substitution_sed_insert "${file}" "${pattern}" "${replacement}"; then
                        modified=true
                    fi
                    ;;
                sed-delete)
                    if apply_substitution_sed_delete "${file}" "${pattern}"; then
                        modified=true
                    fi
                    ;;
            esac
        done <<< "${substitutions}"

        if [[ "${modified}" == "true" ]]; then
            echo "  Templated: $(basename "${file}")"
        fi
    done < <(find "${templates_dir}" -name "*.yaml" -type f -print0)

    echo "  Done"
}

generate_chart_yaml() {
    local chart_name="${OPERATOR_TYPE}-operator"
    local description
    local app_version="${BUNDLE_VERSION:-unknown}"

    if [[ "${OPERATOR_TYPE}" == "odh" ]]; then
        description="Open Data Hub Operator Helm chart (non-OLM installation)"
    else
        description="Red Hat OpenShift AI Operator Helm chart (non-OLM installation)"
    fi

    # Remove leading 'v' from version for appVersion
    app_version="${app_version#v}"

    local chart_yaml="${OUTPUT_DIR}/Chart.yaml"

    cat > "${chart_yaml}" << EOF
apiVersion: v2
name: ${chart_name}
description: ${description}
type: application
version: 0.1.0
appVersion: "${app_version}"
EOF

    echo "Created: ${chart_yaml}"
}

generate_helpers_tpl() {
    local chart_name="${OPERATOR_TYPE}-operator"
    local helpers_file="${OUTPUT_DIR}/templates/_helpers.tpl"
    local template_file="${TEMPLATES_DIR}/_helpers.tpl.tmpl"

    if [[ ! -f "${template_file}" ]]; then
        echo "ERROR: Template file not found at ${template_file}" >&2
        exit 1
    fi

    "${SED}" "s/CHART_NAME/${chart_name}/g" "${template_file}" > "${helpers_file}"
    echo "Created: ${helpers_file}"
}

generate_values_yaml() {
    local values_file="${OUTPUT_DIR}/values.yaml"
    local template_file="${TEMPLATES_DIR}/values.yaml.tmpl"
    local default_namespace

    if [[ "${OPERATOR_TYPE}" == "odh" ]]; then
        default_namespace="${ODH_NAMESPACE}"
    else
        default_namespace="${RHOAI_NAMESPACE}"
    fi

    if [[ ! -f "${template_file}" ]]; then
        echo "ERROR: Template file not found at ${template_file}" >&2
        exit 1
    fi

    "${SED}" "s/DEFAULT_NAMESPACE/${default_namespace}/g" "${template_file}" > "${values_file}"
    echo "Created: ${values_file}"
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--type)
            if [[ -z "${2:-}" ]]; then
                echo "ERROR: --type requires a value"
                show_help
                exit 1
            fi
            OPERATOR_TYPE="$2"
            shift 2
            ;;
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
    set_defaults

    echo "=============================================================================="
    echo "OLM Bundle Extractor"
    echo "=============================================================================="
    echo ""
    echo "Configuration:"
    echo "  Type:        ${OPERATOR_TYPE}"
    echo "  Bundle:      ${BUNDLE_IMAGE}"
    echo "  Namespace:   ${NAMESPACE}"
    echo "  Output:      ${OUTPUT_DIR}"
    echo ""

    # Create output directory
    mkdir -p "${OUTPUT_DIR}/templates"

    # Step 1: Clean up existing templates
    cleanup_templates
    echo ""

    # Step 2: Extract bundle
    extract_bundle
    echo ""

    # Step 3: Process YAML documents
    process_yaml_documents "${RAW_YAML}"
    echo ""

    # Step 4: Apply Helm templating (replace hardcoded values with templates)
    apply_helm_templating
    echo ""

    # Step 5: Generate chart files
    echo "Generating chart files..."
    generate_chart_yaml
    generate_helpers_tpl
    generate_values_yaml

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
