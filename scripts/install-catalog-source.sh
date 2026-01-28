#!/usr/bin/env bash
#
# install-catalog-source.sh - Install a CatalogSource for the OpenDataHub operator
#
# Usage:
#   ./install-catalog-source.sh [options]
#
# Options:
#   -i, --image     Catalog image (default: quay.io/opendatahub/opendatahub-operator-catalog:latest)
#   -h, --help      Show this help message
#
# Requirements: oc CLI
# Exit codes: 0 = success, 1 = failure
#

set -e

# ==============================================================================
# DEFAULT VALUES
# ==============================================================================

DEFAULT_IMAGE="quay.io/opendatahub/opendatahub-operator-catalog:latest"

CATALOG_IMAGE="${DEFAULT_IMAGE}"

CATALOG_SOURCE_NAME="opendatahub-catalog-test"
CATALOG_SOURCE_NAMESPACE="openshift-marketplace"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

show_help() {
    cat << EOF
Usage: $(basename "$0") [options]

Install a CatalogSource for the OpenDataHub operator.

Options:
  -i, --image     Catalog image (default: ${DEFAULT_IMAGE})
  -h, --help      Show this help message

Examples:
  # Install with defaults
  $(basename "$0")

  # Install with custom image
  $(basename "$0") --image quay.io/opendatahub/opendatahub-operator-catalog:v2.10.0
EOF
}

# ==============================================================================
# ARGUMENT PARSING
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--image)
            CATALOG_IMAGE="$2"
            shift 2
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

echo "Installing CatalogSource for OpenDataHub operator..."
echo "  Image: ${CATALOG_IMAGE}"
echo ""

# Create the CatalogSource
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${CATALOG_SOURCE_NAME}
  namespace: ${CATALOG_SOURCE_NAMESPACE}
  labels:
    app.kubernetes.io/name: opendatahub
    app.kubernetes.io/component: catalog
spec:
  sourceType: grpc
  image: ${CATALOG_IMAGE}
  displayName: OpenDataHub Operator Catalog
  publisher: OpenDataHub GitOps Test
  updateStrategy:
    registryPoll:
      interval: 30m
EOF

echo ""
echo "✓ CatalogSource '${CATALOG_SOURCE_NAME}' created in namespace '${CATALOG_SOURCE_NAMESPACE}'"
echo ""
