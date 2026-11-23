#!/usr/bin/env bash
set -euo pipefail

# Every request and sleep shares one deadline; a slow API cannot extend the loop.
deadline=$((SECONDS + TIMEOUT_SECONDS))
reason="initial readiness check"
last_failure=""
resources="certificates certificaterequests issuers"

request() {
  local remaining=$((deadline - SECONDS))
  ((remaining > 0)) || return 1
  local duration=$REQUEST_TIMEOUT_SECONDS
  if ((duration > remaining)); then duration=$remaining; fi
  # Match the XKS Job convention: bound the entire CLI process. A client-go
  # --request-timeout override can bypass the in-cluster config fallback.
  timeout --kill-after=1s "${duration}s" oc --cache-dir=/tmp/oc-cache "$@"
}

ready() {
  local resource condition discovery
  for resource in $resources; do
    reason="CRD ${resource}.cert-manager.io is absent or not Established"
    condition=$(request get customresourcedefinition "${resource}.cert-manager.io" \
      -o 'jsonpath={.status.conditions[?(@.type=="Established")].status}') || return 1
    [[ "$condition" == True ]] || return 1
  done

  reason="cert-manager.io/v1 API discovery is unavailable"
  discovery=$(request get --raw /apis/cert-manager.io/v1) || return 1
  for resource in $resources; do
    reason="cert-manager.io/v1 discovery does not advertise ${resource}"
    grep -Eq '"name"[[:space:]]*:[[:space:]]*"'"$resource"'"' <<< "$discovery" || return 1
  done
}

echo "Waiting up to ${TIMEOUT_SECONDS}s for cert-manager CRDs and API discovery"
while ! ready; do
  remaining=$((deadline - SECONDS))
  if ((remaining <= 0)); then
    echo "ERROR: cert-manager readiness timed out after ${TIMEOUT_SECONDS}s: ${last_failure:-$reason}." \
      "OpenTelemetry Subscription remains gated." >&2
    exit 1
  fi
  last_failure=$reason
  echo "Waiting: ${reason}; ${remaining}s remaining"
  delay=$POLL_INTERVAL_SECONDS
  if ((delay > remaining)); then delay=$remaining; fi
  sleep "$delay"
done
echo "cert-manager CRDs are Established and all required APIs are discoverable"
