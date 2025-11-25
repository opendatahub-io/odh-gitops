#!/usr/bin/env bash

# prepare-authorino-tls.sh - Prepare environment to enable TLS for Authorino
#
# Annotates the Authorino service to trigger TLS certificate generation,
# waits for the TLS certificate secret to be generated, and updates the
# RHCL kustomization.yaml to include the TLS configuration for Authorino.
#
# After running this script, reapply the configuration using kubectl (or oc):
#   kubectl apply -k configurations/rhcl-operator

set -e

KUADRANT_NS="${KUADRANT_NS:-kuadrant-system}"
K8S_CLI="${K8S_CLI:-kubectl}"

AUTHORINO_NAME="authorino"
SERVICE_NAME="${AUTHORINO_NAME}-authorino-authorization"
SECRET_NAME="${AUTHORINO_NAME}-server-cert"

echo ""
echo "Waiting for Authorino service to be created..."
timeout=300
while ! ${K8S_CLI} get svc/${SERVICE_NAME} -n ${KUADRANT_NS} &>/dev/null && [ $timeout -gt 0 ]; do
    echo "Waiting for ${SERVICE_NAME} service... ($timeout seconds remaining)"
    sleep 5
    ((timeout-=5))
done

if [ $timeout -le 0 ]; then
    echo "ERROR: Timeout waiting for Authorino service"
    exit 1
fi

echo "Authorino service found. Annotating service to trigger TLS certificate generation..."
${K8S_CLI} annotate svc/${SERVICE_NAME} \
    service.beta.openshift.io/serving-cert-secret-name=${SECRET_NAME} \
    -n ${KUADRANT_NS} --overwrite

echo ""
echo "Waiting for TLS certificate secret to be generated..."
timeout=120
while ! ${K8S_CLI} get secret ${SECRET_NAME} -n ${KUADRANT_NS} &>/dev/null && [ $timeout -gt 0 ]; do
    echo "Waiting for ${SECRET_NAME} secret... ($timeout seconds remaining)"
    sleep 5
    ((timeout-=5))
done

if [ $timeout -le 0 ]; then
    echo "ERROR: Timeout waiting for secret creation"
    exit 1
fi

echo "TLS certificate secret created successfully!"

KUSTOMIZATION_FILE="configurations/rhcl-operator/kustomization.yaml"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
KUSTOMIZATION_PATH="${REPO_ROOT}/${KUSTOMIZATION_FILE}"
echo ""
echo "Updating ${KUSTOMIZATION_FILE} to include TLS configuration for Authorino..."

if [ -f "$KUSTOMIZATION_PATH" ]; then
    if ! grep -q "tls-enabled/authorino-tls.yaml" "$KUSTOMIZATION_PATH"; then
        yq -i '.resources += ["tls-enabled/authorino-tls.yaml"]' "$KUSTOMIZATION_PATH"
        echo "File ${KUSTOMIZATION_FILE} updated successfully!"
    else
        echo "TLS configuration already included in ${KUSTOMIZATION_FILE}"
    fi
else
    echo "ERROR: Expected ${KUSTOMIZATION_FILE} file not found."
    exit 1
fi

echo ""
echo "Environment preparation for TLS completed. The RHCL kustomization.yaml has been updated to include the Authorino TLS configuration."
echo "To apply the updated configuration, run:"
echo "  ${K8S_CLI} apply -k configurations/rhcl-operator"
