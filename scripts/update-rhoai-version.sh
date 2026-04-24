#!/usr/bin/env bash
set -euo pipefail

echo "Checking for RHOAI version updates from ODH-Build-Config..."

# Get current version from Makefile
CURRENT_VERSION=$(make -s print-rhoai-version)
echo "Current RHOAI_VERSION: $CURRENT_VERSION"

# Fetch latest version from ODH-Build-Config
NEW_VERSION=$(curl -sSL "https://raw.githubusercontent.com/opendatahub-io/ODH-Build-Config/main/bundle/bundle-patch.yaml" | yq '.patch.version' 2>/dev/null || echo "")

# Validate format and fallback if needed
if [[ ! "$NEW_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-ea\.[0-9]+)?$ ]]; then
    echo "Error: Unable to fetch valid version from ODH-Build-Config"
    echo "   Keeping current RHOAI_VERSION: $CURRENT_VERSION"
    exit 1
fi

echo "Latest available: $NEW_VERSION"

# Check if update needed
if [[ "$NEW_VERSION" == "$CURRENT_VERSION" ]]; then
    echo "RHOAI_VERSION is already up to date: $NEW_VERSION"
    exit 0
fi

echo "Updated RHOAI_VERSION: $CURRENT_VERSION -> $NEW_VERSION"

# Update Makefile: RHOAI_VERSION ?= X.Y.Z-ea.N
sed -i.bak "s/^RHOAI_VERSION ?= .*/RHOAI_VERSION ?= $NEW_VERSION/" Makefile

# Update Chart.yaml: both version and appVersion use the same NEW_VERSION
yq eval -i ".version = \"$NEW_VERSION\"" charts/rhai-on-xks-chart/Chart.yaml
yq eval -i ".appVersion = \"$NEW_VERSION\"" charts/rhai-on-xks-chart/Chart.yaml

# Cleanup
rm -f Makefile.bak

echo "Updated files:"
echo "  - Makefile: RHOAI_VERSION = $NEW_VERSION"
echo "  - Chart.yaml: version = $NEW_VERSION, appVersion = $NEW_VERSION"