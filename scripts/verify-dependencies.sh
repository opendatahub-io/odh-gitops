#!/usr/bin/env bash
#
# verify-dependencies.sh - Verify operator dependencies are installed and ready
#
# Verifies:
#   1. All operator CSVs reach "Succeeded" phase
#   2. Custom checks for specific operators (e.g., pod readiness)
#
# Requirements: Bash 4+, oc CLI
# Exit codes: 0 = success, 1 = failure
#

set -e

echo "Verifying dependencies..."

# ==============================================================================
# OPERATOR DEFINITIONS
# ==============================================================================

# Operators to verify: [subscription_name]="namespace pod_label_selector"
# To add an operator: Add a line below and custom checks in the "Custom Checks" section if needed
declare -A OPERATORS=(
    [openshift-cert-manager-operator]="cert-manager-operator name=cert-manager-operator"
    [kueue-operator]="openshift-kueue-operator name=openshift-kueue-operator"
    [cluster-observability-operator]="openshift-cluster-observability-operator app.kubernetes.io/name=observability-operator"
    [opentelemetry-product]="openshift-opentelemetry-operator app.kubernetes.io/name=opentelemetry-operator"
    [leader-worker-set]="openshift-lws-operator name=openshift-lws-operator"
    [job-set]="openshift-jobset-operator name=jobset-operator"
    [tempo-product]="openshift-tempo-operator app.kubernetes.io/name=tempo-operator"
    [openshift-custom-metrics-autoscaler-operator]="openshift-keda name=custom-metrics-autoscaler-operator"
    [rhcl-operator]="kuadrant-system app=kuadrant"
)


# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

# Wait for Kubernetes resources to exist (retries every 5s)
# Usage: wait_for_resource <namespace> <resource_type> <label> [timeout_seconds]
# Example: wait_for_resource "default" "pods" "app=myapp" 300
wait_for_resource() {
    local namespace=$1
    local resource_type=$2
    local label=$3
    local timeout=${4:-300}
    local description="resource ${resource_type} in namespace ${namespace} with label ${label}"
    local interval=5
    local elapsed=0

    echo "Waiting for ${description}..."
    while ! oc get ${resource_type} -n ${namespace} -l ${label} 2>/dev/null | grep -q .; do
        if [ $elapsed -ge $timeout ]; then
            echo "ERROR: ${description} not found after ${timeout}s"
            return 1
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
    done
    echo "✓ ${description} found"
    return 0
}

# Wait for CSV (ClusterServiceVersion) to reach "Succeeded" phase
# Usage: wait_for_csv_succeeded <namespace> <csv_name> [timeout_seconds]
# Example: wait_for_csv_succeeded "cert-manager" "cert-manager.v1.15.0" 300
wait_for_csv_succeeded() {
    local namespace=$1
    local csv_name=$2
    local timeout=${3:-300}
    local interval=5
    local elapsed=0

    echo "Waiting for CSV ${csv_name} in namespace ${namespace} to reach Succeeded phase..."

    while true; do
        # Check if CSV exists and get its phase
        local phase=$(oc get csv ${csv_name} -n ${namespace} -o jsonpath='{.status.phase}' 2>/dev/null)

        if [ "$phase" = "Succeeded" ]; then
            echo "✓ CSV ${csv_name} has reached Succeeded phase"
            return 0
        fi

        if [ $elapsed -ge $timeout ]; then
            echo "ERROR: CSV ${csv_name} did not reach Succeeded phase after ${timeout}s (current phase: ${phase:-not found})"
            return 1
        fi

        if [ -n "$phase" ] && [ "$phase" != "Succeeded" ]; then
            echo "  Current phase: ${phase} (waiting...)"
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done
}

# Wait for a Subscription's CSV to be assigned and reach "Succeeded" phase
# Usage: wait_for_subscription_csv <namespace> <subscription_name> [timeout_seconds]
# Example: wait_for_subscription_csv "cert-manager-operator" "openshift-cert-manager-operator"
wait_for_subscription_csv() {
    local namespace=$1
    local subscription_name=$2
    local timeout=${3:-300}
    local interval=5
    local elapsed=0

    echo "Waiting for Subscription ${subscription_name} in namespace ${namespace} to have a CSV..."

    # First, wait for the subscription to have a currentCSV
    while true; do
        local csv_name=$(oc get subscription ${subscription_name} -n ${namespace} -o jsonpath='{.status.currentCSV}' 2>/dev/null)

        if [ -n "$csv_name" ]; then
            echo "✓ Found CSV: ${csv_name}"
            break
        fi

        if [ $elapsed -ge $timeout ]; then
            echo "ERROR: Subscription ${subscription_name} did not get a CSV after ${timeout}s"
            return 1
        fi

        sleep $interval
        elapsed=$((elapsed + interval))
    done

    # Now wait for the CSV to reach Succeeded phase
    wait_for_csv_succeeded "${namespace}" "${csv_name}" "${timeout}"
    return $?
}

# ==============================================================================
# CSV VERIFICATION
# ==============================================================================

echo ""
echo "Step 1: Verifying operator CSVs..."
echo ""

for subscription_name in "${!OPERATORS[@]}"; do
    read -r namespace label_selector <<< "${OPERATORS[$subscription_name]}"

    echo "Waiting for ${subscription_name} to be ready..."
    if ! wait_for_subscription_csv "${namespace}" "${subscription_name}"; then
        exit 1
    fi
    echo "✓ ${subscription_name} CSV is ready"

    echo "Waiting for ${subscription_name} pods to be ready..."
    if ! wait_for_resource "${namespace}" "pods" "${label_selector}"; then
        exit 1
    fi
    echo "✓ ${subscription_name} pods are running"
done

# ==============================================================================
# CUSTOM CHECKS
# ==============================================================================

echo ""
echo "Step 2: Running custom verification checks..."
echo ""

# cert-manager: Verify pods are running (CSV success doesn't guarantee pod readiness)
echo "Checking cert-manager pods..."
if ! wait_for_resource "cert-manager" "pods" "app.kubernetes.io/instance=cert-manager"; then
    exit 1
fi
echo "✓ cert-manager pods are running"

echo ""
echo "✓ All dependencies are installed and ready"

# cluster-observability-operator: Verify pods are running
echo "Checking cluster-observability-operator pods..."
if ! wait_for_resource "openshift-cluster-observability-operator" "pods" "app.kubernetes.io/part-of=observability-operator"; then
    exit 1
fi
echo "✓ cluster-observability-operator pods are running"

# tempo-operator: Verify pods are running
echo "Checking tempo-operator pods..."
if ! wait_for_resource "openshift-tempo-operator" "pods" "app.kubernetes.io/part-of=tempo-operator"; then
    exit 1
fi
echo "✓ tempo-operator pods are running"

# custom-metrics-autoscaler: Verify all KEDA component pods are running
echo "Checking custom-metrics-autoscaler (KEDA) pods..."
if ! wait_for_resource "openshift-keda" "pods" "app=keda-operator"; then
    exit 1
fi
echo "✓ custom-metrics-autoscaler keda-operator pods are running"

if ! wait_for_resource "openshift-keda" "pods" "app=keda-metrics-apiserver"; then
    exit 1
fi
echo "✓ custom-metrics-autoscaler keda-metrics-apiserver pods are running"

if ! wait_for_resource "openshift-keda" "pods" "app=keda-admission-webhooks"; then
    exit 1
fi
echo "✓ custom-metrics-autoscaler keda-admission-webhooks pods are running"

# rhcl-operator: Verify pods are running
echo "Checking rhcl-operator pods..."
# check kuadrant-console-plugin pods
if ! wait_for_resource "kuadrant-system" "pods" "app=kuadrant-console-plugin"; then
    exit 1
fi
# check authorino-operator pods
if ! wait_for_resource "kuadrant-system" "pods" "control-plane=authorino-operator"; then
    exit 1
fi
# check dns-operator-controller pods
if ! wait_for_resource "kuadrant-system" "pods" "control-plane=dns-operator-controller-manager"; then
    exit 1
fi
# check limitador-operator pods
if ! wait_for_resource "kuadrant-system" "pods" "control-plane=controller-manager"; then
    exit 1
fi
echo "✓ rhcl-operator pods are running"
