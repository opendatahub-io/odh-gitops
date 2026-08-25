#!/usr/bin/env bash
# Copy the XKS-tailored GatewayConfig CRD from opendatahub-operator into this chart.
#
# Source (operator):
#   config/crd/xks/services.platform.opendatahub.io_gatewayconfigs.yaml
# Destination (this chart):
#   templates/crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml
#
# The operator file is a plain CRD. This script wraps it with {{- if .Values.installCRDs }}.
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

SRC="${OPERATOR_DIR}/config/crd/xks/services.platform.opendatahub.io_gatewayconfigs.yaml"
DST="${CHART_DIR}/templates/crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml"

if [[ ! -f "${SRC}" ]]; then
	echo "ERROR: XKS GatewayConfig CRD not found at ${SRC}" >&2
	echo "In the operator repo run: make generate-xks-gateway-crd" >&2
	exit 1
fi

mkdir -p "${CHART_DIR}/templates/crds"

{
	echo '{{- if .Values.installCRDs }}'
	# Drop YAML document separators; Helm wraps a single object.
	sed '/^---[[:space:]]*$/d' "${SRC}"
	echo '{{- end }}'
} > "${DST}"

echo "Wrote ${DST}"
