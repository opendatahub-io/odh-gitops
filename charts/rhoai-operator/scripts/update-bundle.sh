#!/bin/bash
# Update Helm chart with new bundle version
# Usage: ./update-bundle.sh [version]
# Examples:
#   ./update-bundle.sh v3.4.0-ea.1
#   ./update-bundle.sh v3.3.0

set -euo pipefail

VERSION="${1:-v3.4.0-ea.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bundle image from quay.io (public, no auth required)
BUNDLE_IMAGE="quay.io/opendatahub/opendatahub-operator-bundle:${VERSION}"

echo "============================================"
echo "  Updating RHOAI Operator Helm Chart"
echo "============================================"
echo "Version: $VERSION"
echo "Bundle: $BUNDLE_IMAGE"
echo ""

# Create temp directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract manifests using olm-extractor
echo "[1/3] Extracting manifests..."
podman run --rm --pull=always \
  quay.io/lburgazzoli/olm-extractor:main \
  run "$BUNDLE_IMAGE" \
  -n opendatahub-operator \
  2>/dev/null | grep -v "^time=" > "$TMP_DIR/manifests.yaml"

# Validate extraction produced output
if [ ! -s "$TMP_DIR/manifests.yaml" ]; then
  echo "ERROR: Extraction produced empty manifests. Check bundle image."
  exit 1
fi

echo "Extracted $(wc -l < "$TMP_DIR/manifests.yaml") lines"

# Clean: remove all CRDs and templates (only after successful extraction)
echo "[2/3] Cleaning old manifests..."
find "$CHART_DIR/crds" -name "*.yaml" -delete 2>/dev/null || true
find "$CHART_DIR/templates" -name "*.yaml" \
  ! -name "namespace.yaml" \
  ! -name "issuer-opendatahub-operator-controller-manager-selfsigned.yaml" \
  -delete 2>/dev/null || true

# Split manifests, templatize namespace references
echo "[3/3] Splitting into CRDs and templates..."

export TMP_DIR CHART_DIR
python3 << 'PYEOF'
import yaml
import os
import sys

tmp_dir = os.environ.get('TMP_DIR', '/tmp')
chart_dir = os.environ.get('CHART_DIR', '.')

input_file = f'{tmp_dir}/manifests.yaml'
crds_dir = f'{chart_dir}/crds'
templates_dir = f'{chart_dir}/templates'

os.makedirs(crds_dir, exist_ok=True)
os.makedirs(templates_dir, exist_ok=True)

with open(input_file, 'r') as f:
    content = f.read()

docs = content.split('\n---\n')
crd_count = 0
other_count = 0

# Skip Issuer — preserved as custom template (olm-extractor strips selfSigned: {})
skip_resources = [
    ('Issuer', 'opendatahub-operator-controller-manager-selfsigned'),
]

for doc in docs:
    if not doc.strip():
        continue
    try:
        obj = yaml.safe_load(doc)
        if not obj:
            continue
        kind = obj.get('kind', 'unknown')
        name = obj.get('metadata', {}).get('name', 'unknown')

        # Skip preserved custom templates
        if (kind, name) in skip_resources:
            continue

        filename = f"{kind.lower()}-{name.replace('.', '-')[:50]}.yaml"

        if kind == 'CustomResourceDefinition':
            filepath = os.path.join(crds_dir, filename)
            crd_count += 1
            with open(filepath, 'w') as out:
                out.write(doc.strip() + '\n')
        elif kind == 'Namespace':
            continue
        else:
            filepath = os.path.join(templates_dir, filename)
            other_count += 1
            # Templatize namespace references
            content = doc.strip()
            content = content.replace('namespace: opendatahub-operator', 'namespace: {{ .Values.namespace }}')
            # Templatize cert-manager CA injection annotation
            content = content.replace('inject-ca-from: opendatahub-operator/', 'inject-ca-from: "{{ .Values.namespace }}/')\
                      .replace('service-cert\n', 'service-cert"\n')
            # Templatize certificate dnsNames
            content = content.replace('.opendatahub-operator.svc', '.{{ .Values.namespace }}.svc')

            # Fix ServiceAccount missing namespace (olm-extractor bug)
            if kind == 'ServiceAccount':
                obj_check = yaml.safe_load(content)
                if 'namespace' not in obj_check.get('metadata', {}):
                    content = content.replace(
                        f'  name: {name}',
                        f'  name: {name}\n  namespace: {{{{ .Values.namespace }}}}'
                    )

            with open(filepath, 'w') as out:
                out.write(content + '\n')

    except Exception as e:
        print(f"Error processing manifest: {e}", file=sys.stderr)
        sys.exit(1)

print(f"Created {crd_count} CRDs")
print(f"Created {other_count} templates")
PYEOF

# Update bundle.version in values.yaml
sed -i '/^bundle:/,/^[a-z]/{s/  version: ".*"/  version: "'"$VERSION"'"/}' "$CHART_DIR/values.yaml"

echo ""
echo "============================================"
echo "  Update Complete!"
echo "============================================"
echo ""
echo "Chart updated at: $CHART_DIR"
echo "New version: $VERSION"
echo ""
echo "Next steps:"
echo "  1. Review extracted manifests"
echo "  2. Test with: helm template rhoai-operator $CHART_DIR"
