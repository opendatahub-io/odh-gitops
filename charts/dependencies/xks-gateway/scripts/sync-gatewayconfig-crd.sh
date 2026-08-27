#!/usr/bin/env bash
# Copy the GatewayConfig CRD from opendatahub-operator into this chart.
#
# Source (operator):
#   config/crd/bases/services.platform.opendatahub.io_gatewayconfigs.yaml
# Destination (this chart):
#   crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml
#
# The operator file is a plain CRD. It MUST live in Helm's crds/ directory (not
# templates/) so helm install applies it before the GatewayConfig CR. CRDs in
# templates/ are validated in the same pass as the CR and fail on a fresh cluster:
#   no matches for kind "GatewayConfig" in version "services.platform.opendatahub.io/v1alpha1"
#
# Skip CRD install when it already exists: helm upgrade --install ... --skip-crds
# Helm does not upgrade files in crds/ on helm upgrade; re-run this script and
# kubectl apply the CRD (or helm install on a new release) to roll schema changes.
#
# Usage:
#   ./sync-gatewayconfig-crd.sh /path/to/opendatahub-operator
#   OPERATOR_DIR=../opendatahub-operator ./sync-gatewayconfig-crd.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OPERATOR_DIR="${1:-${OPERATOR_DIR:-}}"
if [[ -z "${OPERATOR_DIR}" ]]; then
	echo "Usage: $0 /path/to/opendatahub-operator" >&2
	echo "   or: OPERATOR_DIR=/path/to/opendatahub-operator $0" >&2
	exit 1
fi

SRC="${OPERATOR_DIR}/config/crd/bases/services.platform.opendatahub.io_gatewayconfigs.yaml"
DST="${CHART_DIR}/crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml"
# Legacy location from when the CRD was templated; must not ship both.
OLD_DST="${CHART_DIR}/templates/crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml"

if [[ ! -f "${SRC}" ]]; then
	echo "ERROR: GatewayConfig CRD not found at ${SRC}" >&2
	echo "In the operator repo run: make manifests" >&2
	exit 1
fi

mkdir -p "${CHART_DIR}/crds"

# Drop YAML document separators; Helm crds/ is untemplated raw YAML.
sed '/^---[[:space:]]*$/d' "${SRC}" > "${DST}"

if [[ -f "${OLD_DST}" ]]; then
	rm -f "${OLD_DST}"
	echo "Removed legacy ${OLD_DST}"
fi

echo "Wrote ${DST}"
