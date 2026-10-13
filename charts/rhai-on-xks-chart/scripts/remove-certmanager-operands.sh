#!/bin/bash
# Keep the CR until Helm deletes it; the operator recreates a missing default CR.
set -euo pipefail
certmanager=$(kubectl --request-timeout=10s get certmanagers.operator.openshift.io cluster --ignore-not-found -o name)
if [[ -n "$certmanager" ]]; then
  kubectl --request-timeout=10s patch "$certmanager" --type=merge -p '{"spec":{"managementState":"Removed"}}'
  certmanager_deadline=$((SECONDS + 300))
  finalizers="pending"
  while (( SECONDS < certmanager_deadline )); do
    finalizers=$(kubectl --request-timeout=10s get "$certmanager" --ignore-not-found -o jsonpath='{.metadata.finalizers}')
    [[ -n "$finalizers" && "$finalizers" != "[]" ]] || break
    sleep 5
  done
  if [[ -n "$finalizers" && "$finalizers" != "[]" ]]; then
    echo "Timed out waiting for cert-manager operand cleanup: $finalizers" >&2
    exit 1
  fi
  echo "Cert-manager operand cleanup complete."
fi
# Stop default-CR recreation before Helm deletes the now-finalized CR.
kubectl delete deployment cert-manager-operator-controller-manager \
  -n "${CERT_MANAGER_OPERATOR_NAMESPACE:-cert-manager-operator}" \
  --ignore-not-found --cascade=foreground --timeout=60s
