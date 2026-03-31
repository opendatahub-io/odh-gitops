# RHAII Helm Chart

Red Hat AI Inference Helm chart for non-OLM installation.

This chart installs the RHAI operator and its cloud manager components. Exactly one cloud provider (Azure or CoreWeave) must be enabled.

## Table of Contents

- [RHAI On XKS Helm Chart](#rhai-on-xks-chart)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Pull Secrets](#pull-secrets)
  - [Installation](#installation)
    - [Azure](#azure)
    - [CoreWeave](#coreweave)
  - [How It Works](#how-it-works)
  - [Managed Dependencies](#managed-dependencies)
  - [Configuration Reference](#configuration-reference)
  - [Testing with kind](#testing-with-kind)
  - [Uninstall](#uninstall)

## Prerequisites

- Kubernetes cluster
- Helm 4.x
- Cluster-admin privileges (the chart creates CRDs, ClusterRoles, and namespaces)
- Pull secret for `registry.redhat.io` (see [Pull Secrets](#pull-secrets) below)

## Pull Secrets

> [!IMPORTANT]
> A pull secret is **required** to install this chart. The chart pulls images from `registry.redhat.io`, including the `ose-cli-rhel9:v4.21.0` image used by the post-install hook Job.

### Obtaining credentials

```bash
podman login registry.redhat.io --authfile /path/to/auth.json
```

### What the pull secret does

The `imagePullSecret.dockerConfigJson` parameter:

1. Creates a `kubernetes.io/dockerconfigjson` Secret named `rhaii-pull-secret` in all chart-managed namespaces (operator, applications, release, cloud manager and all dependency namespaces)
2. Adds `imagePullSecrets` to all chart-managed ServiceAccounts (RHAI operator, cloud manager, llmisvc-controller-manager, and the post-install hook)

The secret name defaults to `rhaii-pull-secret` and **should not** be changed.

> [!NOTE]
> Pull secrets for dependency namespaces (`cert-manager-operator`, `cert-manager`, `istio-system`, `openshift-lws-operator`) are managed by this chart by default. To customize which dependency namespaces receive pull secrets, set `imagePullSecret.dependencyNamespaces`.

## Installation

> [!NOTE]
> All commands below assume you are in the repository root directory.

### Azure

```bash
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set azure.enabled=true \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

### CoreWeave

```bash
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set coreweave.enabled=true \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

> [!WARNING]
> `helm install --wait` is **not supported**. The chart uses post-install hook Jobs to create Custom Resources after the operators are deployed. These hooks require CRDs to be registered first, and the rhai-operator depends on cert-manager to start correctly. Using `--wait` may cause the installation to time out or fail.

## How It Works

The chart performs a **two-phase installation**:

1. **Phase 1 — Helm install:** deploys all operator resources (Deployments, RBAC, CRDs, etc.)
2. **Phase 2 — Post-install hook:** a Helm hook Job runs after install/upgrade to create the Custom Resources that configure the operators

This two-phase approach is necessary because the CRs depend on CRDs that are only available after the operators are deployed.

## Managed Dependencies

The KubernetesEngine CRs (Azure or CoreWeave) manage the following dependencies. Each can be set to `Managed` (operator handles installation and lifecycle) or `Unmanaged` (you manage it yourself):

| Dependency | Description |
| --- | --- |
| `certManager` | Certificate management (cert-manager) |
| `gatewayAPI` | Gateway API CRDs and controller |
| `lws` | LeaderWorkerSet (LWS) operator |
| `sailOperator` | Sail Operator (Istio service mesh) |

To opt out of a managed dependency, set its `managementPolicy` to `Unmanaged`:

```yaml
azure:
  enabled: true
  kubernetesEngine:
    spec:
      dependencies:
        certManager:
          managementPolicy: Unmanaged
```

## Configuration Reference

For the configuration reference, please refer to the [API reference](api-docs.md) file and the [values.yaml](values.yaml) file.

## Testing with kind

You can test the chart locally using [kind](https://kind.sigs.k8s.io/).

```bash
# Create a local cluster
kind create cluster --name rhoai

# Install the chart (see "Pull Secrets" section for private registry auth)
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set azure.enabled=true \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

## Uninstall

```bash
helm uninstall rhaii -n rhaii
```

### Clean up CRDs

CRDs are **not** removed on uninstall (`helm.sh/resource-policy: keep`). To remove them manually:

**Chart-managed CRDs:**
```bash
kubectl delete crd kserves.components.platform.opendatahub.io
```
**Operator-created CRDs (created by rhai-operator during KServe deployment):**
```bash
kubectl delete crd llminferenceservices.serving.kserve.io
kubectl delete crd llminferenceserviceconfigs.serving.kserve.io
```

**Azure:**
```bash
kubectl delete crd azurekubernetesengines.infrastructure.opendatahub.io
```

**CoreWeave:**
```bash
kubectl delete crd coreweavekubernetesengines.infrastructure.opendatahub.io
```

### Clean up namespaces

The namespaces created by the chart are not automatically removed. Clean up the namespaces as needed based on your configuration.
