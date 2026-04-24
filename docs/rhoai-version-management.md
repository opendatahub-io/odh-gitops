# RHOAI Version Management

This document describes how RHOAI versions are managed in this repository.

## Overview

The repository uses a **single source of truth** approach for RHOAI version management:

1. **Makefile `RHOAI_VERSION`** - Central version definition
2. **Automated Detection** - Tools to find latest versions from rhods-devops-infra releases.yaml
3. **Workflow Integration** - GitHub Actions automatically use the Makefile version

## Current Version

```bash
make print-rhoai-version
```

Current version: `3.4.0-ea.2`

## Version Management

### Check and Update to Latest Version

```bash
make update-rhoai-version
```

This single command:
1. **Detects** the latest version from [rhods-devops-infra releases.yaml](https://github.com/red-hat-data-services/rhods-devops-infra/blob/main/src/config/releases.yaml)
2. **Compares** it with the current `RHOAI_VERSION` in the Makefile  
3. **Updates** the Makefile only if a newer version is available
4. **Reports** the result with clear status messages

### Edge Case Handling

The system handles several edge cases automatically:

- **Empty releases array `[]`**: Ignores update and keeps current version
- **No releases found**: Keeps current version and shows warning
- **Multiple releases**: Automatically picks the latest using proper version sorting
- **Network errors**: Gracefully handles failures and keeps current version

## Workflow Integration

The `update-rhai-xks-bundle.yaml` workflow automatically uses `RHOAI_VERSION` from the Makefile as the default version for bundle updates:

- **Default**: Uses `make print-rhoai-version` 
- **Override**: Manual inputs can override the version/branch
- **Command**: `update-bundle.sh "{version}" --branch "{branch}"`

## Version Format Normalization

The system automatically normalizes release branch names to proper semver format:

| Release Branch | Normalized Version |
|----------------|-------------------|
| `rhoai-3.4` | `3.4.0` |
| `rhoai-3.4-ea.1` | `3.4.0-ea.1` |
| `rhoai-3.4-ea.2` | `3.4.0-ea.2` |
| `rhoai-2.25` | `2.25.0` |

### Version Ordering

The system follows RHOAI release ordering:
`3.4.0` → `3.5.0-ea.1` → `3.5.0-ea.2` → `3.5.0` → `3.6.0-ea.1`

## Release Management Workflow

When a new RHOAI version becomes available in rhods-devops-infra:

1. **Check and Update**: `make update-rhoai-version`
2. **Commit Change**: Update the Makefile in a PR  
3. **Automatic Sync**: Daily workflow will use the new version

### Example Workflow

```bash
# Check for updates and update if needed (single command!)
make update-rhoai-version
```

**Example outputs:**

**When update is available:**
```
Checking for RHOAI version updates from rhods-devops-infra releases.yaml...
Current RHOAI_VERSION: 3.4.0-ea.2
Found 5 releases in rhods-devops-infra  
Latest available: rhoai-3.5.0-ea.1 -> 3.5.0-ea.1
✅ Updated RHOAI_VERSION: 3.4.0-ea.2 -> 3.5.0-ea.1
```

**When already up to date:**
```
Checking for RHOAI version updates from rhods-devops-infra releases.yaml...
Current RHOAI_VERSION: 3.4.0-ea.2
Found 4 releases in rhods-devops-infra
Latest available: rhoai-3.4-ea.2 -> 3.4.0-ea.2  
✅ RHOAI_VERSION is already up to date: 3.4.0-ea.2
```

## Benefits

- ✅ **Single Source of Truth**: All tools and workflows reference the same version
- ✅ **Easy Updates**: One command updates the version across the entire repository  
- ✅ **Automatic Detection**: No need to manually track RHOAI releases
- ✅ **Consistent Formatting**: Automatic normalization to proper semver
- ✅ **Override Capability**: Manual control when needed for specific cases