#!/usr/bin/env bash
# Verify the committed GatewayConfig CRD matches the XKS CRD in opendatahub-operator.
#
# Usage:
#   ./verify-gatewayconfig-crd.sh /path/to/opendatahub-operator
#   OPERATOR_DIR=../opendatahub-operator ./verify-gatewayconfig-crd.sh
#
# Exits 0 when in sync; prints a diff and exits 1 when they diverge.

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
DST="${CHART_DIR}/crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml"

if [[ ! -f "${SRC}" ]]; then
	echo "ERROR: XKS GatewayConfig CRD not found at ${SRC}" >&2
	echo "In the operator repo run: make generate-xks-gateway-crd" >&2
	exit 1
fi

if [[ ! -f "${DST}" ]]; then
	echo "ERROR: Chart CRD not found at ${DST}" >&2
	exit 1
fi

TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

# Match sync-gatewayconfig-crd.sh normalization (drop YAML document separators).
sed '/^---[[:space:]]*$/d' "${SRC}" > "${TMP}"

if diff -u "${TMP}" "${DST}"; then
	echo "GatewayConfig CRD is in sync with ${SRC}"
else
	echo "ERROR: GatewayConfig CRD in ${DST} differs from operator source." >&2
	echo "Run: ${SCRIPT_DIR}/sync-gatewayconfig-crd.sh ${OPERATOR_DIR}" >&2
	exit 1
fi
