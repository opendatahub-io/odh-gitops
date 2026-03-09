# Inference Only Stack

## Table of Contents

- [Inference Only Stack](#inference-only-stack)
    - [Overview](#overview)
    - [Prerequisites](#prerequisites)
    - [What Gets Installed](#what-gets-installed)
    - [Values Override](#values-override)
    - [Scripted Installation (Helm)](#scripted-installation-helm)
    - [Enabling Authorino TLS](#enabling-authorino-tls)
    - [Verification](#verification)
    - [Troubleshooting](#troubleshooting)

## Overview

The inference-only stack deploys KServe with distributed inference (llm-d) without the full RHOAI/ODH platform. This is
useful when you only need model serving capabilities and want to avoid installing components like pipelines,
workbenches, dashboards, training operators, and monitoring.

The stack installs a minimal set of dependency operators required by KServe:

| Operator                         | Purpose                                     | Namespace                |
|----------------------------------|---------------------------------------------|--------------------------|
| cert-manager                     | Certificate management and TLS provisioning | `cert-manager-operator`  |
| Leader Worker Set                | Distributed inference workflows             | `openshift-lws-operator` |
| Red Hat Connectivity Link (RHCL) | API management (Kuadrant/Authorino)         | `kuadrant-system`        |

## Prerequisites

- OpenShift cluster (version 4.19 or later)
- `kubectl` or `oc` CLI installed
- Cluster admin permissions
- Helm v4

## What Gets Installed

The values override configures the chart to install:

1. **Dependency operators** (via OLM): cert-manager, Leader Worker Set, RHCL (Kuadrant)
2. **ODH/RHOAI operator** (via OLM)
3. **DSCInitialization** (DSCI) with monitoring disabled
4. **DataScienceCluster** (DSC) with only KServe set to `Managed`

All other components (AI Pipelines, Dashboard, Feast, Kueue, Model Registry, Ray, Trainer, Training Operator, TrustyAI,
Workbenches, MLflow, LlamaStack) are set to `Removed`.

## Values Override

The values override file is located at
[`docs/examples/values-inference-only.yaml`](examples/values-inference-only.yaml).

> [!NOTE]
> The YAML below is a copy of the values file for reference. If you modify the values, ensure you also update the source
> file at `docs/examples/values-inference-only.yaml`.

Below is the full content with field-by-field explanations:

```yaml
# -- Operator configuration
operator:
  enabled: true
  type: rhoai  # Change to "odh" for Open Data Hub

# -- Disable monitoring (not needed for inference-only)
services:
  monitoring:
    dependencies:
      clusterObservability: false
      opentelemetry: false
      tempo: false
    dsci:
      managementState: Removed

components:
  kserve:
    dependencies:
      certManager: true
      leaderWorkerSet: true
      rhcl: true
      customMetricsAutoscaler: false  # Disabled for now
      jobSet: false  # Not needed for inference-only
    dsc:
      managementState: Managed
      modelsAsService:
        managementState: Removed
      nim:
        managementState: Removed

  # -- Disable all non-inference components
  aipipelines:
    dsc:
      managementState: Removed

  dashboard:
    dsc:
      managementState: Removed

  feastoperator:
    dsc:
      managementState: Removed

  kueue:
    dsc:
      managementState: Removed

  modelregistry:
    dsc:
      managementState: Removed

  ray:
    dsc:
      managementState: Removed

  trainer:
    dsc:
      managementState: Removed

  trainingoperator:
    dsc:
      managementState: Removed

  trustyai:
    dsc:
      managementState: Removed

  workbenches:
    dsc:
      managementState: Removed

  mlflowoperator:
    dsc:
      managementState: Removed

  llamastackoperator:
    dsc:
      managementState: Removed
```

> [!NOTE]
> The chart's tri-state dependency resolution (`auto`/`true`/`false`) handles transitive dependencies automatically. For
> example, RHCL auto-pulls cert-manager and Leader Worker Set as its own dependencies. Setting components to `Removed`
> prevents their dependencies from being installed.

## Scripted Installation (Helm)

### 1. Clone the repository

```bash
git clone https://github.com/opendatahub-io/odh-gitops.git
cd odh-gitops
```

### 2. Install operators (first Helm run)

The first run installs the OLM subscriptions (Namespace, OperatorGroup, Subscription). CRs are skipped because their
CRDs do not exist yet.

```bash
helm upgrade --install rhoai ./charts/odh-rhoai \
  -f docs/examples/values-inference-only.yaml \
  -n opendatahub-gitops --create-namespace
```

### 3. Wait for CRDs

Wait for the operators to install and register their CRDs before creating CRs:

```bash
kubectl wait --for=condition=Established \
  crd/leaderworkersetoperators.operator.openshift.io --timeout=300s

kubectl wait --for=condition=Established \
  crd/kuadrants.kuadrant.io --timeout=300s

kubectl wait --for=condition=Established \
  crd/datascienceclusters.datasciencecluster.opendatahub.io --timeout=300s

kubectl wait --for=condition=Established \
  crd/dscinitializations.dscinitialization.opendatahub.io --timeout=300s
```

> [!NOTE]
> You can also use the provided script `./scripts/wait-for-crds.sh` which waits for all known CRDs.

### 4. Create CRs (second Helm run)

Now that CRDs exist, the second run creates the CR resources (DSCInitialization, DataScienceCluster, Kuadrant,
LeaderWorkerSetOperator, etc.):

```bash
helm upgrade --install rhoai ./charts/odh-rhoai \
  -f docs/examples/values-inference-only.yaml \
  -n opendatahub-gitops
```

### 5. Enable Authorino TLS (post-install)

> [!WARNING]
> This step is required for KServe to function correctly. See [Enabling Authorino TLS](#enabling-authorino-tls)
> for why this is a post-install step.

```bash
KUSTOMIZE_MODE=false ./scripts/prepare-authorino-tls.sh
```

### 6. Verify the installation

See [Verification](#verification) for commands to confirm everything is running.

## Enabling Authorino TLS

The Kuadrant operator automatically creates the Authorino resource when the Kuadrant CR is applied. Because Authorino is
created by the operator (not by the Helm chart), TLS must be enabled as a post-install step after Authorino exists.

### CLI method

Use the provided script which handles waiting for resources, annotating the service, and patching the Authorino CR:

```bash
KUSTOMIZE_MODE=false ./scripts/prepare-authorino-tls.sh
```

The script:

1. Waits for the Authorino service to be created
2. Annotates the service to trigger TLS certificate generation
3. Waits for the TLS certificate secret
4. Patches the Authorino CR to enable TLS

## Verification

### Check operator CSVs

Verify that all operators are installed and in `Succeeded` phase:

```bash
kubectl get csv -A | grep -E "(cert-manager|leader-worker|rhcl|opendatahub|rhods)"
```

### Check Authorino TLS

Verify that Authorino has TLS enabled:

```bash
kubectl get authorino authorino -n kuadrant-system \
  -o jsonpath='{.spec.listener.tls}'
```

### Check DataScienceCluster status

```bash
kubectl get datasciencecluster -o jsonpath='{.items[0].status.phase}'
```

### Comprehensive verification

Use the provided verification script for a full check of all operator subscriptions and pod readiness:

```bash
./scripts/verify-dependencies.sh
```

## Troubleshooting

### CRs not being created

If CR resources (DataScienceCluster, Kuadrant, LeaderWorkerSetOperator, etc.) are not being created after the Helm
install:

1. Verify the operator is installed and the CRD exists:

   ```bash
   kubectl get crd datascienceclusters.datasciencecluster.opendatahub.io
   kubectl get crd kuadrants.kuadrant.io
   ```

2. Run `helm upgrade` again. CRs are skipped until their CRDs exist:

   ```bash
   helm upgrade --install rhoai ./charts/odh-rhoai \
     -f docs/examples/values-inference-only.yaml \
     -n opendatahub-gitops
   ```

### Authorino TLS issues

If Authorino TLS is not working:

1. Check that the service annotation exists:

   ```bash
   kubectl get svc authorino-authorino-authorization -n kuadrant-system \
     -o jsonpath='{.metadata.annotations}'
   ```

2. Check that the TLS secret was created:

   ```bash
   kubectl get secret authorino-server-cert -n kuadrant-system
   ```

3. Verify the Authorino CR has TLS enabled:

   ```bash
   kubectl get authorino authorino -n kuadrant-system \
     -o jsonpath='{.spec.listener.tls}'
   ```

4. If the secret does not exist, re-run the TLS preparation script:

   ```bash
   KUSTOMIZE_MODE=false ./scripts/prepare-authorino-tls.sh
   ```

### Dependencies not being installed

If a dependency operator is not being installed:

1. Verify the component requiring it has `managementState: Managed` (not `Removed`)
2. Check that the dependency is not explicitly set to `false` in the component's `dependencies`
3. Verify the top-level `dependencies.<name>.enabled` is not set to `false`
