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
# Install dependencies with default settings. We need to install the dependencies before the operator is installed.
helm upgrade --install rhoai ./chart -n opendatahub-gitops --create-namespace --set operator.enabled=false

# Wait for operators to be ready, then run again to create CRs and also install the operator
helm upgrade --install rhoai ./chart -n opendatahub-gitops --set operator.enabled=true

# Wait for operator to be ready, then run again to create the DSC
helm upgrade --install rhoai ./chart -n opendatahub-gitops
```

## Installation Flow

Due to CRD dependencies (operators create CRDs that are needed for CR resources), installation requires multiple runs:

```bash
# Single idempotent command - run multiple times
helm upgrade --install rhoai ./chart -n opendatahub-gitops --create-namespace --set operator.enabled=false
sleep 120
for i in {1..5}; do
  helm upgrade --install rhoai ./chart -n opendatahub-gitops --create-namespace --set operator.enabled=true
  sleep 60
done
```

**What happens:**
1. **First run**: Operators are installed via OLM (Namespace, OperatorGroup, Subscription). CRs are skipped because CRDs don't exist yet.
2. **Subsequent runs**: Once operators are ready and CRDs exist, CR configurations are created.
3. **Later runs**: Idempotent - no changes if everything is already deployed.

### Enable Authorino TLS

To enable Authorino TLS, annotate the `authorino-authorino-authorization` service with `service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert`:

```bash
kubectl annotate svc/authorino-authorino-authorization \
    service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
    -n kuadrant-system
```

Then, set `dependencies.rhcl.config.tlsEnabled` to `true`.

Once this is done, upgrade the chart:

```bash
helm upgrade --install rhoai ./chart -n rhoai-system
```

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

This chart works with ArgoCD but requires specific configuration:

### Why `skipCrdCheck: true` is required

ArgoCD renders Helm templates **without cluster access**, so the `lookup` function (used to check if CRDs exist) always returns empty results. You must set `global.skipCrdCheck: true` to render all CRs upfront.

### Why `SkipDryRunOnMissingResource` is required

ArgoCD performs dry-run validation before applying resources. CRs whose CRDs don't exist yet will fail validation. The `SkipDryRunOnMissingResource=true` sync option skips dry-run for these resources.

### Example ArgoCD Application

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
        global:
          skipCrdCheck: true
        components:
          kserve:
            managementState: Managed
  destination:
    server: https://kubernetes.default.svc
    namespace: rhoai-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - SkipDryRunOnMissingResource=true
```

ArgoCD automatically retries failed resources, so after operators install their CRDs, subsequent syncs will successfully apply the CRs.

### Enable Authorino TLS in ArgoCD

To enable Authorino TLS, annotate the `authorino-authorino-authorization` service with `service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert`:

```bash
kubectl annotate svc/authorino-authorino-authorization \
    service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
    -n kuadrant-system
```

Once the secret is created, set `dependencies.rhcl.config.tlsEnabled` to `true` in the ArgoCD application values.

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
