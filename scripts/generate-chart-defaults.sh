#!/usr/bin/env bash
#
# Generate or validate chart-defaults.yaml for the RHOAI umbrella chart.
#
# Helm does not expose values.yaml to .Files.Get, and it coalesces subchart
# defaults into .Values before rendering. This script captures that complete
# default layer once so the profile loader can distinguish user overrides.

set -euo pipefail

check=false
chart_dir="charts/rhai-on-openshift-chart"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check)
            check=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--check] [chart-dir]"
            exit 0
            ;;
        *)
            if [[ -d "$1" ]]; then
                chart_dir="$1"
                shift
            else
                echo "ERROR: unknown argument or missing directory: $1" >&2
                exit 1
            fi
            ;;
    esac
done

defaults_file="${chart_dir}/chart-defaults.yaml"
if [[ ! -f "${chart_dir}/values.yaml" ]]; then
    echo "ERROR: ${chart_dir}/values.yaml does not exist" >&2
    exit 1
fi

tmp_dir=$(mktemp -d)
trap 'rm -rf "${tmp_dir}"' EXIT
cp -a "${chart_dir}" "${tmp_dir}/chart"

cat > "${tmp_dir}/chart/templates/zz-chart-defaults.yaml" <<'EOF'
{{ .Values | toYaml }}
EOF

helm template chart-defaults "${tmp_dir}/chart" \
    --set skipCrdCheck=false \
    --show-only templates/zz-chart-defaults.yaml \
    | sed '1,2d' > "${tmp_dir}/chart-defaults.yaml"

if [[ "${check}" == "true" ]]; then
    if ! cmp -s "${tmp_dir}/chart-defaults.yaml" "${defaults_file}"; then
        echo "ERROR: ${defaults_file} is stale. Run: make chart-defaults" >&2
        diff -u "${defaults_file}" "${tmp_dir}/chart-defaults.yaml" >&2 || true
        exit 1
    fi
    echo "Chart defaults are current"
else
    cp "${tmp_dir}/chart-defaults.yaml" "${defaults_file}"
    echo "Generated ${defaults_file}"
fi
