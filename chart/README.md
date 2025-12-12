# RHOAI Dependencies Helm Chart

A Helm chart for installing ODH/RHOAI dependencies and component configurations on OpenShift.

## Overview

This chart provides a flexible way to install the operators and configurations required by OpenShift AI (RHOAI) and Open Data Hub (ODH). It supports:

- **Component-based installation**: Enable high-level components (kserve, kueue, aipipelines, ...) and their dependencies are automatically installed
- **Tri-state dependency management**: Dependencies can be `auto` (install if needed), `true` (always install), or `false` (skip - user has it already)
- **OLM installation**: Operators are installed via Operator Lifecycle Manager (OLM)
- **Idempotent installation**: Run the same command multiple times until all resources are applied

## Quick Start

```bash
# Install with default settings
helm upgrade --install rhoai ./chart -n rhoai-system --create-namespace

# Wait for operators to be ready, then run again to create CRs
helm upgrade --install rhoai ./chart -n rhoai-system --create-namespace
```

## Installation Flow

Due to CRD dependencies (operators create CRDs that are needed for CR resources), installation requires multiple runs:

```bash
# Single idempotent command - run multiple times
for i in {1..5}; do
  helm upgrade --install rhoai ./chart -n rhoai-system --create-namespace
  sleep 60
done
```

**What happens:**
1. **First run**: Operators are installed via OLM (Namespace, OperatorGroup, Subscription). CRs are skipped because CRDs don't exist yet.
2. **Subsequent runs**: Once operators are ready and CRDs exist, CR configurations are created.
3. **Later runs**: Idempotent - no changes if everything is already deployed.

## Configuration

### Operator

Choose between ODH (Open Data Hub) or RHOAI (Red Hat OpenShift AI) operator:

```yaml
operator:
  enabled: true
  type: rhoai  # odh | rhoai
```

| Type | Operator | Namespace | Source |
|------|----------|-----------|--------|
| `odh` | opendatahub-operator | openshift-operators | community-operators |
| `rhoai` | rhods-operator | redhat-ods-operator | redhat-operators |

### Components

High-level features that:

1. Configure the DataScienceCluster (DSC) `managementState`
2. Automatically enable their required dependencies when active (Managed or Unmanaged)

| managementState | Dependencies auto-enabled | Available for |
|-----------------|---------------------------|---------------|
| `Managed` | Yes | kserve, aipipelines |
| `Unmanaged` | Yes | kueue |
| `Removed` | No | all |

| Component | Description | Dependencies |
|-----------|-------------|--------------|
| `kserve` | KServe model serving | certManager, leaderWorkerSet, jobSet, rhcl |
| `kueue` | Kueue job queuing | kueue |
| `aipipelines` | AI Pipelines | - |

### Dependencies

Operators that can be installed. Use tri-state `enabled` field:

| Value | Behavior |
|-------|----------|
| `auto` | Install if required by an enabled component (default) |
| `true` | Always install |
| `false` | Never install (user has it already) |

### Example: Enable kserve

```yaml
# values.yaml
components:
  kserve:
    managementState: Managed

# Dependencies certManager, leaderWorkerSet, jobSet, rhcl
# will be auto-installed because kserve is Managed
```

### Example: Skip a dependency you already have

```yaml
# values.yaml
components:
  kserve:
    managementState: Managed

dependencies:
  certManager:
    enabled: false  # I already have cert-manager installed
```

### Example: Install a dependency without a component

```yaml
# values.yaml
components:
  kserve:
    managementState: Removed

dependencies:
  certManager:
    enabled: true  # Force install even though no component needs it
```

### Example: Enable kueue with custom spec

```yaml
# values.yaml
components:
  kueue:
    managementState: Unmanaged

dependencies:
  kueue:
    enabled: auto
    config:
      # spec accepts any fields supported by the Kueue CR
      spec:
        managementState: Managed
        config:
          integrations:
            frameworks:
              - Deployment
              - Pod
              - PyTorchJob
```

### Example: Enable RHCL with TLS

```yaml
# values.yaml
components:
  kserve:
    managementState: Managed

dependencies:
  rhcl:
    enabled: auto
    config:
      tlsEnabled: true
      # Kuadrant CR spec (optional)
      spec: {}
      # Authorino CR spec (used when tlsEnabled: true)
      authorinoSpec:
        replicas: 2
        clusterWide: true
```

## Values Reference

### Global Settings

```yaml
global:
  # Installation type (currently only olm is supported)
  installationType: olm
  
  # OLM settings
  olm:
    installPlanApproval: Automatic
    source: redhat-operators
    sourceNamespace: openshift-marketplace
  
  # Common labels for all resources
  labels: {}
```

### Components

Components configure the DataScienceCluster (DSC) and trigger automatic dependency installation.

```yaml
components:
  kserve:
    managementState: Managed  # Managed | Removed
  
  kueue:
    managementState: Removed  # Unmanaged | Removed
  
  aipipelines:
    managementState: Removed  # Managed | Removed
```

When `managementState` is `Managed` or `Unmanaged`, the component's dependencies are auto-enabled. When `Removed`, they are not.

### Dependencies

To configure dependencies, refer to the [api docs](api-docs.md).

## ArgoCD Usage

This chart works with ArgoCD. For the multi-apply pattern, you can either:

1. **Use sync waves** to order dependencies before configurations
2. **Run multiple syncs** - ArgoCD will eventually converge to the desired state

Example ArgoCD Application:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoai-dependencies
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/odh-gitops
    targetRevision: main
    path: chart
    helm:
      values: |
        components:
          kserve:
            enabled: true
  destination:
    server: https://kubernetes.default.svc
    namespace: rhoai-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## Troubleshooting

### CRs not being created

If CR resources (Kueue, Kuadrant, etc.) are not being created:

1. Check if the operator is installed and ready:
   ```bash
   kubectl get csv -A | grep kueue
   ```

2. Check if the CRD exists:
   ```bash
   kubectl get crd kueues.kueue.openshift.io
   ```

3. Run `helm upgrade` again - CRs are skipped until CRDs exist.

### Dependency not being installed

If a dependency is not being installed:

1. Check if the component that requires it is enabled
2. Check if the dependency is explicitly set to `false`
3. Verify the dependency is in the component's dependency map
