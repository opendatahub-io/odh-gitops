#!/usr/bin/env bash
# Usage: bash update-e2e-images.sh <manifests-config.yaml> [values-e2e.yaml]
# Sync each platform's image pins into its OLM Subscription configuration.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YQ="${YQ:-${SCRIPT_DIR}/../../../bin/yq}"
CONFIG="${1:?Usage: $0 <manifests-config.yaml> [values-e2e.yaml]}"
VALUES="${2:-${SCRIPT_DIR}/../test/values-e2e.yaml}"

# Build and validate in a temporary file before touching the committed values.
E2E_IMAGES_FILE=$(mktemp)
export E2E_IMAGES_FILE
trap 'rm -f "$E2E_IMAGES_FILE" "${VALUES_TEMP:-}"' EXIT

# Convert imageOverrides keys into env names and join each platform's base@digest.
# Entries absent from a platform are omitted from that platform's list.
"$YQ" '
  (.imageOverrides // {} | to_entries) as $images |
  {
    "odh": ($images | map(select(.value.odh != null)) |
      map({"name": .key, "value": (.value.odh.base + "@" + .value.odh.digest)})),
    "rhoai": ($images | map(select(.value.rhoai != null)) |
      map({"name": .key, "value": (.value.rhoai.base + "@" + .value.rhoai.digest)}))
  }
' "$CONFIG" > "$E2E_IMAGES_FILE"

# Require both platforms, valid digests, and registry hosts from the allowlist:
# quay.io and registry.redhat.io. This does not check signatures or availability.
if ! "$YQ" -e '
  (.odh | length > 0) and (.rhoai | length > 0) and
  ([.[] | .[] | select(
    (.name | test("^RELATED_IMAGE_[A-Z0-9_]+$") | not) or
    (.value | test("^(quay[.]io|registry[.]redhat[.]io)/[^[:space:]@]+@sha256:[a-f0-9]{64}$") | not)
  )] | length == 0)
' "$E2E_IMAGES_FILE" >/dev/null; then
  echo "ERROR: Expected nonempty ODH and RHOAI image overrides with valid names, sha256 digests, and approved registry hosts" >&2
  exit 1
fi

# Replace the generated env lists entirely, removing stale pins and manual entries.
# Other values remain intact; recursive style resets keep these lists in block YAML.
# Write beside the original and rename only after success, preserving its file mode.
VALUES_TEMP=$(mktemp "${VALUES}.XXXXXX")
cp -p "$VALUES" "$VALUES_TEMP"
"$YQ" -i '
  .operator.odh.olm.config.env = load(strenv(E2E_IMAGES_FILE)).odh |
  .operator.rhoai.olm.config.env = load(strenv(E2E_IMAGES_FILE)).rhoai |
  (.operator.odh.olm.config.env | ...) style = "" |
  (.operator.rhoai.olm.config.env | ...) style = ""
' "$VALUES_TEMP"
mv "$VALUES_TEMP" "$VALUES"
