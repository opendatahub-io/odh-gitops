#!/usr/bin/env bash
#
# wait-for-crds.sh - Wait for CRDs to be created by operators
#
# This script waits for CRDs that are created by operators installed via OLM.
# These CRDs are required before their corresponding CRs can be applied.
#
# Usage:
#   ./wait-for-crds.sh              # Wait for dependency CRDs only
#   ./wait-for-crds.sh --all        # Wait for both dependency and operator CRDs
#   ./wait-for-crds.sh --operator   # Wait for operator CRDs only
#

set -e

TIMEOUT="${TIMEOUT:-300}"
INTERVAL="${INTERVAL:-5}"

CRDS=(
    "kueues.kueue.openshift.io"
    "leaderworkersetoperators.operator.openshift.io"
    "jobsetoperators.operator.openshift.io"
    "kuadrants.kuadrant.io"
    # "nodefeaturediscoveries.nfd.openshift.io"
    # "clusterpolicies.nvidia.com"
    "datascienceclusters.datasciencecluster.opendatahub.io"
    "dscinitializations.dscinitialization.opendatahub.io"
)

wait_for_crd() {
    local crd_name=$1
    local elapsed=0

    while [ $elapsed -lt $TIMEOUT ]; do
        if oc get crd "$crd_name" &>/dev/null; then
            echo "✓ CRD $crd_name exists"
            return 0
        fi
        sleep $INTERVAL
        elapsed=$((elapsed + INTERVAL))
    done

    echo "⚠️ CRD $crd_name not found after ${TIMEOUT}s (operator may not be installed)"
    return 0  # Don't fail - CRD might not be needed if operator not installed
}

for crd in "${CRDS[@]}"; do
    wait_for_crd "$crd"
done

echo ""
echo "✓ CRD check complete"
