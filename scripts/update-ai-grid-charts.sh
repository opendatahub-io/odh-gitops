#!/bin/bash
# Vendor the AI Grid charts from praxis-proxy/grid as unpacked subcharts of
# rhai-on-openshift-chart, so installs need no `helm dependency build`, and
# refresh the dependency versions, docs and snapshots.
# Usage: ./scripts/update-ai-grid-charts.sh <git-ref>
# Examples:
#   ./scripts/update-ai-grid-charts.sh v0.2.0
#   GRID_REPO=../grid ./scripts/update-ai-grid-charts.sh main

set -euo pipefail

REF="${1:?usage: $0 <git-ref>}"
GRID_REPO="${GRID_REPO:-https://github.com/praxis-proxy/grid.git}"
YQ="${YQ:-yq}"
CHARTS=(grid-enrollment grid-operator praxis-gateway)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$ROOT/charts/rhai-on-openshift-chart"
DEPS_DIR="$PARENT/charts"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Fetching $GRID_REPO at $REF"
git clone --quiet --filter=blob:none --no-checkout "$GRID_REPO" "$TMP_DIR/grid"
SHA=$(git -C "$TMP_DIR/grid" rev-parse --verify "$REF^{commit}")
echo "Resolved $REF to $SHA"

for chart in "${CHARTS[@]}"; do
  rm -rf "${DEPS_DIR:?}/$chart"
  mkdir -p "$DEPS_DIR/$chart"
  git -C "$TMP_DIR/grid" archive "$SHA" "charts/$chart" | tar -x --strip-components=2 -C "$DEPS_DIR/$chart"

  version=$("$YQ" '.version' "$DEPS_DIR/$chart/Chart.yaml")
  "$YQ" -i "(.dependencies[] | select(.name == \"$chart\") | .version) = \"$version\"" "$PARENT/Chart.yaml"
  echo "  $chart $version"
done

make -C "$ROOT" helm-docs >/dev/null
make -C "$ROOT" chart-snapshots CHART_NAME=rhai-on-openshift-chart >/dev/null

echo "Updated AI Grid charts to $SHA. Review with: git diff --stat"
