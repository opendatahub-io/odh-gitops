#!/bin/bash
# Update Helm chart with new bundle version
# Usage: ./update-bundle.sh [version]
# Examples:
#   ./update-bundle.sh 3.2.1
#   ./update-bundle.sh 3.3.0

set -e

VERSION="${1:-3.2.1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# Bundle image from registry.redhat.io
BUNDLE_IMAGE="registry.redhat.io/openshift-service-mesh/istio-sail-operator-bundle:${VERSION}"

echo "============================================"
echo "  Updating Sail Operator Helm Chart"
echo "============================================"
echo "Version: $VERSION"
echo "Bundle: $BUNDLE_IMAGE"
echo ""

# Check for auth (persistent location first, then session)
if [ -f ~/.config/containers/auth.json ]; then
  AUTH_FILE=~/.config/containers/auth.json
elif [ -f "${XDG_RUNTIME_DIR}/containers/auth.json" ]; then
  AUTH_FILE="${XDG_RUNTIME_DIR}/containers/auth.json"
else
  echo "ERROR: Not logged in to registry.redhat.io"
  echo "Run: podman login registry.redhat.io"
  echo "Then: cp ~/pull-secret.txt ~/.config/containers/auth.json"
  exit 1
fi

AUTH_ARG="-v ${AUTH_FILE}:/root/.docker/config.json:z"

# Create temp directory
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Extract manifests
echo "[1/4] Extracting manifests..."
podman run --rm --pull=always $AUTH_ARG \
  quay.io/lburgazzoli/olm-extractor:main \
  run "$BUNDLE_IMAGE" \
  -n istio-system \
  --exclude '.kind == "ConsoleCLIDownload"' \
  2>/dev/null | grep -v "^time=" > "$TMP_DIR/manifests.yaml"

# Validate extraction produced output
if [ ! -s "$TMP_DIR/manifests.yaml" ]; then
  echo "ERROR: Extraction produced empty manifests. Check bundle image and registry access."
  exit 1
fi

echo "Extracted $(wc -l < "$TMP_DIR/manifests.yaml") lines"

# Clean: remove all CRDs and templates (only after successful extraction)
echo "[2/4] Cleaning old manifests..."
find "$CHART_DIR/crds" -name "*.yaml" -delete 2>/dev/null || true
find "$CHART_DIR/templates" -name "*.yaml" \
  ! -name "namespace.yaml" \
  -delete 2>/dev/null || true

# Split manifests (no templatization)
echo "[3/4] Splitting into CRDs and templates..."

export TMP_DIR CHART_DIR
python3 << 'PYEOF'
import yaml
import os

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

for doc in docs:
    if not doc.strip():
        continue
    try:
        obj = yaml.safe_load(doc)
        if not obj:
            continue
        kind = obj.get('kind', 'unknown')
        name = obj.get('metadata', {}).get('name', 'unknown')
        filename = f"{kind.lower()}-{name.replace('.', '-')[:50]}.yaml"

        if kind == 'CustomResourceDefinition':
            filepath = os.path.join(crds_dir, filename)
            crd_count += 1
            with open(filepath, 'w') as out:
                out.write(doc.strip() + '\n')
        elif kind == 'Namespace':
            # Skip — managed by templates/namespace.yaml
            continue
        elif kind == 'ServiceAccount' and name == 'istiod':
            # Skip istiod SA — managed separately
            continue
        else:
            filepath = os.path.join(templates_dir, filename)
            other_count += 1
            # Templatize namespace references
            content = doc.strip()
            content = content.replace('namespace: istio-system', 'namespace: {{ .Values.namespace }}')
            with open(filepath, 'w') as out:
                out.write(content + '\n')

    except Exception as e:
        print(f"Error processing manifest: {e}", file=__import__('sys').stderr)
        __import__('sys').exit(1)

print(f"Created {crd_count} CRDs")
print(f"Created {other_count} templates")
PYEOF

# Update bundle.version in values.yaml
sed -i '/^bundle:/,/^[a-z]/{s/  version: ".*"/  version: "'"$VERSION"'"/}' "$CHART_DIR/values.yaml"

# ============================================
# Download Gateway API CRDs
# ============================================
echo ""
echo "[4/4] Downloading Gateway API CRDs..."

# Read versions from values.yaml
GWAPI_VERSION=$(grep -A1 '^gatewayAPI:' "$CHART_DIR/values.yaml" | grep 'version:' | head -1 | sed 's/.*"\(.*\)".*/\1/')
GWAPI_CHANNEL=$(grep -A2 '^gatewayAPI:' "$CHART_DIR/values.yaml" | grep 'channel:' | head -1 | sed 's/.*"\(.*\)".*/\1/')
GWAPI_CHANNEL="${GWAPI_CHANNEL:-standard}"

# Ensure version has 'v' prefix (GitHub tags require it)
if [[ "$GWAPI_VERSION" =~ ^[0-9] ]]; then
  GWAPI_VERSION="v${GWAPI_VERSION}"
fi

GWAPI_CRD_DIR="$CHART_DIR/templates/gateway-api-crds"
rm -rf "$GWAPI_CRD_DIR"
mkdir -p "$GWAPI_CRD_DIR"

# Download Gateway API CRDs
GWAPI_BASE_URL="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api/${GWAPI_VERSION}/config/crd/${GWAPI_CHANNEL}"
echo "  Gateway API ${GWAPI_VERSION} (${GWAPI_CHANNEL} channel)..."

for crd_file in $(curl -sL "https://api.github.com/repos/kubernetes-sigs/gateway-api/contents/config/crd/${GWAPI_CHANNEL}?ref=${GWAPI_VERSION}" | \
  python3 -c "import sys,json; [print(f['name']) for f in json.load(sys.stdin) if f['name'].endswith('.yaml') and f['name'] != 'kustomization.yaml']"); do
  echo "    Downloading ${crd_file}..."
  curl -sL "${GWAPI_BASE_URL}/${crd_file}" -o "$GWAPI_CRD_DIR/${crd_file}"
done

GWAPI_CRD_COUNT=$(find "$GWAPI_CRD_DIR" -name "*.yaml" | wc -l)
echo "  Downloaded ${GWAPI_CRD_COUNT} Gateway API CRDs"

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
echo "  2. Test with: helm template sail-operator $CHART_DIR"
