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

#  Get latest released version from RHOAI-Build-Config with retry logic
RAW_CONTENT=""
CURL_RETRIES=3
CURL_RETRY_DELAY=5

for attempt in $(seq 1 $CURL_RETRIES); do
    echo "Fetching version data from RHOAI-Build-Config (attempt $attempt/$CURL_RETRIES)..."

    # Use robust curl options with proper error handling
    set +e  # Temporarily disable exit on error to handle curl failures gracefully
    RAW_CONTENT=$(curl -s --fail --max-time 30 --retry 0 \
        https://raw.githubusercontent.com/red-hat-data-services/RHOAI-Build-Config/main/pcc/shipped_rhoai_versions_granular.txt 2>/dev/null)
    CURL_EXIT_CODE=$?
    set -e  # Re-enable exit on error

    if [[ $CURL_EXIT_CODE -eq 0 && -n "$RAW_CONTENT" ]]; then
        echo "Successfully fetched version data"
        break
    else
        echo "Attempt $attempt failed (curl exit code: $CURL_EXIT_CODE)"
        if [[ $attempt -lt $CURL_RETRIES ]]; then
            echo "Retrying in ${CURL_RETRY_DELAY}s..."
            sleep $CURL_RETRY_DELAY
        else
            echo "ERROR: Failed to fetch version data after $CURL_RETRIES attempts"
            exit 1
        fi
        RAW_CONTENT=""
    fi
done

# Extract version with safe parsing (handle pipeline failures)
set +e  # Temporarily disable pipefail to handle parsing failures gracefully
LATEST_RELEASED=$(echo "$RAW_CONTENT" | grep -E "^v[0-9]+\.[0-9]+\.[0-9]+(-ea\.[0-9]+)?$" | tail -1 | sed 's/^v//')
PARSE_EXIT_CODE=$?
set -e  # Re-enable pipefail

# Validate parsing succeeded and result is valid
if [[ $PARSE_EXIT_CODE -ne 0 || -z "$LATEST_RELEASED" ]]; then
    echo "ERROR: Failed to parse version from fetched content"
    echo "Available versions in response:"
    echo "$RAW_CONTENT" | head -n 10
    exit 1
fi

echo "Latest released version: $LATEST_RELEASED"

# Apply RHOAI release progression logic
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
    # Use printf to safely write to GITHUB_ENV with proper quoting
    printf 'LATEST_RELEASED=%s\n' "$LATEST_RELEASED" >> "$GITHUB_ENV"
    printf 'VERSION=%s\n' "$VERSION" >> "$GITHUB_ENV"
    printf 'BRANCH=%s\n' "$BRANCH" >> "$GITHUB_ENV"
    echo "Environment variables exported to GITHUB_ENV"
else
    echo "Note: GITHUB_ENV not set (running outside GitHub Actions)"
    echo "Environment variables:"
    echo "  LATEST_RELEASED=$LATEST_RELEASED"
    echo "  VERSION=$VERSION"
    echo "  BRANCH=$BRANCH"
fi

echo "Version detection completed successfully"
