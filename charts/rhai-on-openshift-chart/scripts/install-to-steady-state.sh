#!/bin/bash
# Install rhai-on-openshift-chart and bring the platform to steady state.
#
# Port of Makefile helm-install-verify Steps 1–6. Used by helm-install-verify and
# verify-upgrade.sh (baseline and post-upgrade steady state).
#
# Usage:
#   ./install-to-steady-state.sh
#
# Environment variables (see verify-helpers.sh):
#   CHART          - Local chart path or OCI URL (default: ./charts/rhai-on-openshift-chart)
#   CHART_VERSION  - OCI chart version when CHART is an oci:// URL (optional)
#   OPERATOR_TYPE  - odh or rhoai
#   HELM_EXTRA_ARGS, VALUES_FILE, REPO_ROOT, K8S_CLI, NAMESPACE, RELEASE_NAME

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=verify-helpers.sh
source "${SCRIPT_DIR}/verify-helpers.sh"

CHART_VERSION="${CHART_VERSION:-}"

HELM_CHART_ARGS=()
if [[ -n "$CHART_VERSION" ]]; then
  HELM_CHART_ARGS=(--chart "$CHART" --version "$CHART_VERSION")
elif [[ "$CHART" == oci://* ]]; then
  echo "ERROR: CHART_VERSION is required when CHART is an OCI URL" >&2
  exit 1
fi

log "=== Step 1: Install operators ==="
helm_deploy "${HELM_CHART_ARGS[@]}"

log "=== Step 2: Wait for CRDs (dependency) ==="
"${REPO_ROOT}/scripts/wait-for-crds.sh"
bash "${REPO_ROOT}/scripts/verify-dependencies.sh"

log "=== Step 3: Enable DSC and DSCInitialization ==="
helm_deploy "${HELM_CHART_ARGS[@]}"

log "=== Step 4: Verify operator and DSC installation, reducing dashboard replicas to 1 ==="
log "Waiting for odh-dashboard deployment in namespace ${APPLICATIONS_NAMESPACE}..."
while ! "$K8S_CLI" get deployment odh-dashboard -n "$APPLICATIONS_NAMESPACE" >/dev/null 2>&1; do
  echo "Waiting for odh-dashboard deployment..."
  sleep 5
done
"$K8S_CLI" scale deployment odh-dashboard -n "$APPLICATIONS_NAMESPACE" --replicas=1
"$K8S_CLI" describe nodes | grep -A 9 "Allocated resources:" || true
NAMESPACE="$NAMESPACE" OPERATOR_TYPE="$OPERATOR_TYPE" make -C "$REPO_ROOT" helm-verify

log "=== Step 5: Enable Authorino TLS ==="
"$K8S_CLI" delete pod -l app=kuadrant -n kuadrant-system 2>/dev/null || true
K8S_CLI="$K8S_CLI" make -C "$REPO_ROOT" prepare-authorino-tls KUSTOMIZE_MODE=false

log "=== Step 6: Final helm upgrade with wait condition ==="
helm_deploy "${HELM_CHART_ARGS[@]}" --wait
