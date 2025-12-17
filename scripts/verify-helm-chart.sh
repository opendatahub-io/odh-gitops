#!/bin/bash
# Verify Helm chart installation and DSC components readiness
#
# This script:
#   1. Checks the Helm release exists
#   2. Checks DataScienceCluster status

set -e

NAMESPACE="${NAMESPACE:-opendatahub-gitops}"
TIMEOUT="${TIMEOUT:-600}"  # 10 minutes default
INTERVAL="${INTERVAL:-10}"

echo "=== Verifying Helm Chart Installation ==="

# Check if helm CLI is installed
if ! command -v helm &>/dev/null; then
    echo "❌ helm CLI is not installed"
    exit 1
fi
echo "✅ helm CLI found: $(helm version --short)"

# Check if helm release exists
echo "Checking Helm release..."
if ! helm list -n "${NAMESPACE}" 2>/dev/null | grep -q rhoai; then
    echo "❌ Helm release 'rhoai' not found in namespace ${NAMESPACE}"
    exit 1
fi
echo "✅ Helm release found"

# Check DSC status
echo ""
echo "=== Checking DataScienceCluster Status ==="

# Wait for DSC CRD to exist
elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
    if oc get crd datascienceclusters.datasciencecluster.opendatahub.io &>/dev/null; then
        echo "✅ DataScienceCluster CRD exists"
        break
    fi
    echo "Waiting for DataScienceCluster CRD..."
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

if [ $elapsed -ge $TIMEOUT ]; then
    echo "⚠️ DataScienceCluster CRD not found (RHOAI operator may not be installed)"
    echo "=== Verification Complete (without DSC) ==="
    exit 0
fi

# Check if DSC exists
if ! oc get datasciencecluster default-dsc &>/dev/null; then
    echo "⚠️ DataScienceCluster 'default-dsc' not found (will be created on subsequent helm upgrade)"
    echo "=== Verification Complete (without DSC instance) ==="
    exit 0
fi

echo "DataScienceCluster 'default-dsc' found"

# Wait for DSC to be ready
elapsed=0
while [ $elapsed -lt $TIMEOUT ]; do
    phase=$(oc get datasciencecluster default-dsc -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$phase" = "Ready" ]; then
        echo "✅ DataScienceCluster is Ready"
        break
    fi
    echo "  DSC phase: ${phase:-Unknown} (waiting...)"
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

if [ $elapsed -ge $TIMEOUT ]; then
    echo "❌ Timeout waiting for DataScienceCluster to be Ready"
    oc get datasciencecluster default-dsc -o yaml
    exit 1
fi

# Show component statuses
echo ""
echo "=== DSC Component Status ==="
oc get datasciencecluster default-dsc -o jsonpath='{range .status.conditions[*]}{.type}: {.status} - {.reason}{"\n"}{end}' 2>/dev/null || true

echo ""
echo "=== Verification Complete ==="
echo "✅ Helm chart installation verified successfully!"
