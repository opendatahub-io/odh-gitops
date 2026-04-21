#!/usr/bin/env bash

set -euo pipefail

# detect-rhoai-version.sh [version] [branch]
#
# Detects the next target RHOAI version using "plus one" logic
# Accepts optional overrides for version and branch
# Outputs environment variables for GitHub Actions workflow
#
# Arguments:
#   version - Optional version override (e.g., 3.4.0-ea.2)
#   branch  - Optional branch override (e.g., rhoai-3.4)
#
# Environment Variables Set:
#   LATEST_RELEASED - Latest released version from RHOAI-Build-Config
#   VERSION         - Final version to use (detected or override)
#   BRANCH          - Final branch to use (detected or override)
#
# Exit Codes:
#   0 - Success
#   1 - Failed to detect version or parse format

VERSION_OVERRIDE="${1:-}"
BRANCH_OVERRIDE="${2:-}"

echo "Detecting latest RHOAI version from Build Config..."

# Step 1: Get latest released version from RHOAI-Build-Config
LATEST_RELEASED=$(curl -s https://raw.githubusercontent.com/red-hat-data-services/RHOAI-Build-Config/main/pcc/shipped_rhoai_versions_granular.txt | \
                 grep -E "^v[0-9]+\.[0-9]+\.[0-9]+(-ea\.[0-9]+)?$" | \
                 tail -1 | sed 's/^v//')

if [[ -z "$LATEST_RELEASED" ]]; then
    echo "ERROR: Failed to detect latest RHOAI version from Build Config"
    echo "This could be due to network issues or repository unavailability"
    echo "Use manual workflow_dispatch with explicit version if urgent update needed"
    exit 1
fi

echo "Latest released version: $LATEST_RELEASED"

# Step 2: Apply RHOAI release progression logic
# Pattern: X.Y.0-ea.1 → X.Y.0-ea.2 → X.Y.0 → X.(Y+1).0-ea.1
if [[ "$LATEST_RELEASED" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-ea\.1$ ]]; then
    # X.Y.0-ea.1 → X.Y.0-ea.2
    TARGET_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}-ea.2"
    TARGET_BRANCH="rhoai-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}-ea.2"
    echo "Progression: EA.1 → EA.2"
elif [[ "$LATEST_RELEASED" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)-ea\.2$ ]]; then
    # X.Y.0-ea.2 → X.Y.0 (stable)
    TARGET_VERSION="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    TARGET_BRANCH="rhoai-${BASH_REMATCH[1]}.${BASH_REMATCH[2]}"
    echo "Progression: EA.2 → Stable"
elif [[ "$LATEST_RELEASED" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    # X.Y.0 → X.(Y+1).0-ea.1 (next series)
    NEXT_MINOR=$((${BASH_REMATCH[2]} + 1))
    TARGET_VERSION="${BASH_REMATCH[1]}.${NEXT_MINOR}.0-ea.1"
    TARGET_BRANCH="rhoai-${BASH_REMATCH[1]}.${NEXT_MINOR}-ea.1"
    echo "Progression: Stable → Next Series EA.1"
else
    echo "ERROR: Could not parse version format: $LATEST_RELEASED"
    echo "Expected format: X.Y.Z or X.Y.Z-ea.N"
    echo "Use manual workflow_dispatch with explicit version if needed"
    exit 1
fi

# Apply overrides if provided
VERSION="${VERSION_OVERRIDE:-$TARGET_VERSION}"
BRANCH="${BRANCH_OVERRIDE:-$TARGET_BRANCH}"

echo "Latest released: $LATEST_RELEASED"
echo "Detected target: $TARGET_VERSION"
echo "Detected branch: $TARGET_BRANCH"

if [[ -n "$VERSION_OVERRIDE" ]]; then
    echo "Version override: $VERSION"
fi
if [[ -n "$BRANCH_OVERRIDE" ]]; then
    echo "Branch override: $BRANCH"
fi

echo "Final version: $VERSION"
echo "Final branch: $BRANCH"

# Export for GitHub Actions workflow
if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "LATEST_RELEASED=$LATEST_RELEASED" >> "$GITHUB_ENV"
    echo "VERSION=$VERSION" >> "$GITHUB_ENV"
    echo "BRANCH=$BRANCH" >> "$GITHUB_ENV"
    echo "Environment variables exported to GITHUB_ENV"
else
    echo "Environment variables:"
    echo "  LATEST_RELEASED=$LATEST_RELEASED"
    echo "  VERSION=$VERSION"
    echo "  BRANCH=$BRANCH"
fi

echo "Version detection completed successfully"
