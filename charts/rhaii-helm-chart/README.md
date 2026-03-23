# RHAII Helm Chart

Red Hat OpenShift AI Operator Helm chart for non-OLM installation.

This chart installs the RHAI operator and its cloud manager components. Exactly one cloud provider (Azure or CoreWeave) must be enabled.

## Table of Contents

- [RHAII Helm Chart](#rhaii-helm-chart)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
    - [Azure](#azure)
    - [CoreWeave](#coreweave)
  - [Pull Secrets](#pull-secrets)
  - [How It Works](#how-it-works)
  - [Managed Dependencies](#managed-dependencies)
  - [Configuration Reference](#configuration-reference)
  - [Testing with kind](#testing-with-kind)
  - [Uninstall](#uninstall)

## Prerequisites

- Kubernetes cluster (or OpenShift)
- Helm 4.x
- Cluster-admin privileges (the chart creates CRDs, ClusterRoles, and namespaces)

## Installation

### Azure

```bash
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set azure.enabled=true
```

### CoreWeave

```bash
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set coreweave.enabled=true
```

> [!WARNING]
> `helm install --wait` is **not supported**. The chart uses post-install hook Jobs to create Custom Resources after the operators are deployed. These hooks require CRDs to be registered first, and the rhods-operator depends on cert-manager to start correctly. Using `--wait` may cause the installation to time out or fail.

## Pull Secrets

To pull images from private registries, pass your docker config JSON file during install:

```bash
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set azure.enabled=true \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

This will:

1. Create a `kubernetes.io/dockerconfigjson` Secret named `rhaii-pull-secret` in all chart-managed namespaces (operator, applications, release, cloud manager and all dependency namespaces)
2. Add `imagePullSecrets` to all chart-managed ServiceAccounts (RHAI operator, cloud manager and llmisvc-controller-manager in the applications namespace)

The secret name defaults to `rhaii-pull-secret` and **must not** be changed.

> [!NOTE]
> Pull secrets for dependency namespaces (`cert-manager-operator`, `cert-manager`, `istio-system`, `openshift-lws-operator`) are managed by this chart by default. To customize which dependency namespaces receive pull secrets, set `imagePullSecret.dependencyNamespaces`.

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
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set azure.enabled=true \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

## Uninstall

```bash
helm uninstall rhaii -n rhaii
```

CRDs are **not** removed on uninstall (`helm.sh/resource-policy: keep`). To remove them manually:

```bash
kubectl delete crd kserves.components.platform.opendatahub.io
kubectl delete crd azurekubernetesengines.infrastructure.opendatahub.io
kubectl delete crd coreweavekubernetesengines.infrastructure.opendatahub.io
```
