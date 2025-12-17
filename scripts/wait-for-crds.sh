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

# Dependency CRDs (created by dependency operators, needed for dependency CRs)
DEPENDENCY_CRDS=(
    "kueues.kueue.openshift.io"
    "leaderworkersetoperators.operator.openshift.io"
    "jobsetoperators.operator.openshift.io"
    "kuadrants.kuadrant.io"
)

# Operator CRDs (created by ODH/RHOAI operator, needed for DSC/DSCI)
OPERATOR_CRDS=(
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

# Parse arguments
MODE="${1:-dependency}"  # default: dependency only

case "$MODE" in
    --all)
        CRDS=("${DEPENDENCY_CRDS[@]}" "${OPERATOR_CRDS[@]}")
        echo "Waiting for all CRDs (dependency + operator)..."
        ;;
    --operator)
        CRDS=("${OPERATOR_CRDS[@]}")
        echo "Waiting for operator CRDs..."
        ;;
    *)
        CRDS=("${DEPENDENCY_CRDS[@]}")
        echo "Waiting for dependency CRDs..."
        ;;
esac

echo ""

for crd in "${CRDS[@]}"; do
    wait_for_crd "$crd"
done

echo ""
echo "✓ CRD check complete"
