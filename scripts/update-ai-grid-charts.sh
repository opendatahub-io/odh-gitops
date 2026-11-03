#!/bin/bash
# Vendor the AI Grid charts from praxis-proxy/grid as unpacked subcharts of
# rhai-on-openshift-chart, so installs need no `helm dependency build`, copy its
# CRDs into components/ai-grid-crds, and refresh the dependency versions, docs
# and snapshots.
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

# The CRD carry tracks the same commit, so charts and schemas never skew.
CRDS="$ROOT/components/ai-grid-crds"
rm -f "$CRDS"/base/*.yaml
git -C "$TMP_DIR/grid" archive "$SHA" deploy/crds | tar -x --strip-components=2 -C "$CRDS/base"
sed -i -E "s#\[\`praxis-proxy/grid\` at \`[0-9a-f]+\`\]\(https://github.com/praxis-proxy/grid/tree/[0-9a-f]+/deploy/crds\)#[\`praxis-proxy/grid\` at \`${SHA:0:7}\`](https://github.com/praxis-proxy/grid/tree/${SHA}/deploy/crds)#" "$CRDS/README.md"
grep -q "tree/${SHA}/deploy/crds" "$CRDS/README.md" || { echo "CRD carry README names no commit link to update" >&2; exit 1; }

# The routing dashboard reads gateway series by name; fail the bump that renames one.
DASHBOARD="$PARENT/dashboards/ai-grid-routing.yaml"
METRICS_SRC="crates/gateway/crates/ai-grid-filters/src/lib.rs"
emitted=$(git -C "$TMP_DIR/grid" show "$SHA:$METRICS_SRC" | grep -oE '"grid_[a-z_]+"' | tr -d '"' | sort -u)
[[ -n "$emitted" ]] || { echo "No grid metric names in $METRICS_SRC at $SHA" >&2; exit 1; }
missing=$(comm -23 <(grep -oE 'grid_[a-z_]+' "$DASHBOARD" | sort -u) <(echo "$emitted"))
if [[ -n "$missing" ]]; then
  echo "$DASHBOARD reads series the gateway at $SHA does not emit:" >&2
  echo "$missing" >&2
  exit 1
fi

python3 "$ROOT/scripts/adapt-ai-grid-charts.py"
# Preserve reviewed downstream hardening until it is carried upstream. Fail on
# patch drift instead of silently dropping controls during a version bump.
git -C "$ROOT" apply "$ROOT/scripts/ai-grid-hardening.patch"
python3 "$ROOT/scripts/adapt-ai-grid-charts.py"
helm dependency update --skip-refresh "$PARENT"

make -C "$ROOT" helm-docs >/dev/null
make -C "$ROOT" chart-snapshots CHART_NAME=rhai-on-openshift-chart >/dev/null

echo "Updated AI Grid charts to $SHA. Review with: git diff --stat"
