#!/usr/bin/env bash
# Sync ODH image pins for chart-managed components from the operator manifest config.
set -euo pipefail
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
yq="${script_dir}/../../../bin/yq"
manifest_config="${1:?Usage: $0 <manifests-config.yaml> [values-e2e.yaml]}"
values_file="${2:-${script_dir}/../test/values-e2e.yaml}"
images_file=$(mktemp)
trap 'rm -f "$images_file"' EXIT

# KServe/AIGateway controller images carry a component key. Ancillary services
# resolved from the CSV need explicit names; exclude model runtimes and other modules.
"$yq" '.imageOverrides | to_entries | map(select(
  .value.component == "kserve-module-operator" or .value.component == "aigateway" or
  .key == "RELATED_IMAGE_ODH_MODEL_SERVING_API_IMAGE" or
  (.key | test("^RELATED_IMAGE_ODH_(AI_GATEWAY_(CONTROLLER|PAYLOAD_PROCESSING)|MAAS_(API|CONTROLLER|DISCOVERY)|LLM_D_(ASYNC|BATCH_GATEWAY_(APISERVER|GC|OPERATOR|PROCESSOR)))_IMAGE$"))
)) | map({"name": .key, "value": (.value.odh.base + "@" + .value.odh.digest)})' "$manifest_config" > "$images_file"
if ! "$yq" -e 'length > 0 and (map(select(.value | test("^[^@[:space:]]+@sha256:[a-f0-9]{64}$") | not)) | length == 0)' "$images_file" >/dev/null; then
  echo "ERROR: Chart-managed ODH images must have a base and sha256 digest in $manifest_config" >&2
  exit 1
fi
IMAGES_FILE="$images_file" "$yq" -i '.rhaiOperator.relatedImages = load(strenv(IMAGES_FILE))' "$values_file"
