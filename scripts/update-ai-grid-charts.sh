#!/bin/bash
# Vendor the AI Grid charts from praxis-proxy/grid as unpacked subcharts of
# rhai-on-openshift-chart, so installs need no `helm dependency build`, and
# refresh the dependency versions, docs and snapshots.
# This overwrites the vendored charts: review `git diff` for local edits it drops.
# Usage: ./scripts/update-ai-grid-charts.sh <git-ref>
# Examples:
#   ./scripts/update-ai-grid-charts.sh v0.2.0
#   GRID_REPO=../grid ./scripts/update-ai-grid-charts.sh main

set -euo pipefail

REF="${1:?usage: $0 <git-ref>}"
GRID_REPO="${GRID_REPO:-https://github.com/praxis-proxy/grid.git}"
YQ="${YQ:-yq}"
CHARTS=(grid-enrollment praxis-gateway)

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT="$ROOT/charts/rhai-on-openshift-chart"
DEPS_DIR="$PARENT/charts"
# Helm binary — repo-local pinned version (installed via `make helm`);
# set HELM explicitly to use another binary
HELM="${HELM:-$ROOT/bin/helm}"
if ! command -v "${HELM}" &>/dev/null; then
  echo "ERROR: helm not found at ${HELM}. Run 'make helm' to install it." >&2
  exit 1
fi

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Fetching $GRID_REPO at $REF"
CLONE_FLAGS=(--quiet --filter=blob:none --no-checkout)
if [[ -d "$GRID_REPO" ]]; then
  # Local checkouts are commonly shallow; a normal local clone preserves their
  # objects without triggering partial-clone fetches from a promisor remote.
  CLONE_FLAGS=(--quiet)
fi
git clone "${CLONE_FLAGS[@]}" "$GRID_REPO" "$TMP_DIR/grid"
SHA=$(git -C "$TMP_DIR/grid" rev-parse --verify "$REF^{commit}")
if [[ "$REF" =~ ^[0-9a-fA-F]{40}$ ]] && [[ "${REF,,}" != "$SHA" ]]; then
  echo "Resolved commit does not match requested SHA" >&2
  exit 1
fi
echo "Resolved $REF to $SHA"

for chart in "${CHARTS[@]}"; do
  rm -rf "${DEPS_DIR:?}/$chart"
  mkdir -p "$DEPS_DIR/$chart"
  git -C "$TMP_DIR/grid" archive "$SHA" "charts/$chart" | tar -x --strip-components=2 -C "$DEPS_DIR/$chart"

  # Test-only files are not shipped in the vendored production charts.
  rm -rf "${DEPS_DIR:?}/$chart/tests" "${DEPS_DIR:?}/$chart/templates/tests"

  version=$("$YQ" '.version' "$DEPS_DIR/$chart/Chart.yaml")
  "$YQ" -i "(.dependencies[] | select(.name == \"$chart\") | .version) = \"$version\"" "$PARENT/Chart.yaml"
  echo "  $chart $version"
done

python3 "$ROOT/scripts/adapt-ai-grid-charts.py"
"${HELM}" dependency update --skip-refresh "$PARENT"

make -C "$ROOT" helm-docs >/dev/null
make -C "$ROOT" chart-snapshots CHART_NAME=rhai-on-openshift-chart >/dev/null

echo "Updated AI Grid charts to $SHA. Review with: git diff --stat"
