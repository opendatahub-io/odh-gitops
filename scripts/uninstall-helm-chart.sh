#!/usr/bin/env bash
#
# uninstall-helm-chart.sh - Uninstall the RHOAI Helm chart and all dependencies
#
# This script performs a complete uninstall:
# 1. Removes DataScienceCluster and DSCInitialization CRs
# 2. Uninstalls the RHOAI/ODH operator
# 3. Removes dependencies using make remove-all-dependencies
# 4. Removes operator CRDs
# 5. Runs helm uninstall
#
# Usage:
#   ./uninstall-helm-chart.sh
#
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

HELM_RELEASE="${HELM_RELEASE:-odh}"
HELM_NAMESPACE="${HELM_NAMESPACE:-opendatahub-gitops}"


# Operator CRDs (created by ODH/RHOAI operator)
OPERATOR_CRDS=(
    "datascienceclusters.datasciencecluster.opendatahub.io"
    "dscinitializations.dscinitialization.opendatahub.io"
)

echo "=== Uninstalling RHOAI Helm Chart ==="
echo "Release: ${HELM_RELEASE}"
echo "Namespace: ${HELM_NAMESPACE}"
echo ""

# Helper to delete a resource if it exists
delete_if_exists() {
    local resource_type=$1
    local name=$2
    local namespace=$3

    if [ -n "$namespace" ]; then
        echo "Deleting ${resource_type}/${name} in ${namespace}..."
        oc delete "$resource_type" "$name" -n "$namespace" --ignore-not-found --timeout=60s
    else
        echo "Deleting ${resource_type}/${name}..."
        oc delete "$resource_type" "$name" --ignore-not-found --timeout=60s
    fi
}

# Helper to delete subscription and its associated CSV
delete_subscription_and_csv_and_namespace() {
    local subscription_name=$1
    local namespace=$2

    # Get CSV name before deleting the subscription
    local csv_name
    csv_name=$(oc get subscription "${subscription_name}" -n "${namespace}" -o jsonpath='{.status.currentCSV}' 2>/dev/null)

    # Delete subscription
    oc delete subscription "${subscription_name}" -n "${namespace}" --ignore-not-found

    # Delete CSV if found
    if [ -n "$csv_name" ]; then
        oc delete csv "${csv_name}" -n "${namespace}" --ignore-not-found
    fi

    # Delete namespace if found
    if [ -n "$namespace" ]; then
        oc delete namespace "${namespace}" --ignore-not-found
    fi
}

echo ""
echo "=== Step 1: Removing DataScienceCluster and DSCInitialization ==="

delete_if_exists datasciencecluster default-dsc ""
delete_if_exists dscinitialization default-dsci ""

echo ""
echo "=== Step 2: Uninstalling RHOAI/ODH Operator ==="

# Try RHOAI first
delete_subscription_and_csv_and_namespace "rhods-operator" "redhat-ods-operator"

# Try ODH
delete_subscription_and_csv_and_namespace "opendatahub-operator" "opendatahub-operator-system"

echo ""
echo "=== Step 3: Removing Dependencies ==="

cd "${REPO_ROOT}"
make remove-all-dependencies

echo ""
echo "=== Step 4: Removing Operator CRDs ==="

for crd in "${OPERATOR_CRDS[@]}"; do
    delete_if_exists crd "$crd" ""
done

echo "✓ Operator CRDs removed"

echo ""
echo "=== Step 5: Running Helm Uninstall ==="

if helm status "${HELM_RELEASE}" -n "${HELM_NAMESPACE}" &>/dev/null; then
    helm uninstall "${HELM_RELEASE}" -n "${HELM_NAMESPACE}"
    oc delete --ignore-not-found namespace "${HELM_NAMESPACE}"
    echo "✓ Helm release ${HELM_RELEASE} uninstalled"
else
    echo "⏭️ Helm release ${HELM_RELEASE} not found in namespace ${HELM_NAMESPACE}, skipping"
fi
