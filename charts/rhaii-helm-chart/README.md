# RHAII Helm Chart

Red Hat OpenShift AI Operator Helm chart for non-OLM installation.

This chart installs the RHAI operator and its cloud manager components. Exactly one cloud provider (Azure or CoreWeave) must be enabled.

## Prerequisites

- Kubernetes cluster
- Helm 3.x
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

> **Note:** `helm install --wait` (or `helm upgrade --install --wait` the first time) is not supported at this stage. The chart uses post-install hooks (Jobs) to create Custom Resources after the operators are deployed. These hooks require the CRDs to be registered, but without the Custom Resource the rhods-operator will not start correctly because it needs the cert-manager, which means the `--wait` flag may cause the installation to time out or fail.

## What the Chart Installs

The chart deploys the following resources:

1. **RHAI Operator** — Deployment, ServiceAccount, RBAC, webhooks, and CRDs in the operator namespace
2. **Cloud Manager** (Azure or CoreWeave) — Deployment, ServiceAccount, RBAC, and CRDs for the selected cloud provider
3. **Post-install Job** — A Helm hook that automatically creates the required Custom Resources (Kserve, AzureKubernetesEngine, or CoreWeaveKubernetesEngine) after install/upgrade

### Custom Resources Created by Post-install Hook

The post-install Job creates the following CRs (configurable via values):

- **Kserve** — Created when `components.kserve.enabled=true` (default)
- **AzureKubernetesEngine** — Created when `azure.enabled=true` and `azure.kubernetesEngine.enabled=true` (default)
- **CoreWeaveKubernetesEngine** — Created when `coreweave.enabled=true` and `coreweave.kubernetesEngine.enabled=true` (default)

You can customize the spec of each CR through values. For example:

```yaml
azure:
  enabled: true
  kubernetesEngine:
    spec:
      dependencies:
        certManager:
          managementPolicy: Unmanaged
```

Set `managementPolicy: Unmanaged` for any dependency you want to manage yourself.

## Configuration

| Parameter | Description | Default |
| --- | --- | --- |
| `enabled` | Enable/disable all resource creation | `true` |
| `installCRDs` | Install CRDs with the chart | `true` |
| `labels` | Common labels applied to all resources | `{}` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |
| **RHAI Operator** | | |
| `rhaiOperator.namespace` | Operator namespace | `redhat-ods-operator` |
| `rhaiOperator.applicationsNamespace` | Applications namespace | `redhat-ods-applications` |
| `rhaiOperator.image` | Operator container image | `quay.io/opendatahub/opendatahub-operator:latest` |
| `rhaiOperator.relatedImages` | Related images env vars (`RELATED_IMAGE_*`) | `{}` |
| **Components** | | |
| `components.kserve.enabled` | Create Kserve CR via post-install hook | `true` |
| `components.kserve.spec` | Kserve CR spec | `{}` |
| **Azure** | | |
| `azure.enabled` | Enable Azure cloud provider | `false` |
| `azure.cloudManager.namespace` | Azure Cloud Manager namespace | `rhai-cloudmanager-system` |
| `azure.cloudManager.image` | Azure Cloud Manager image | `quay.io/opendatahub/opendatahub-operator:latest` |
| `azure.kubernetesEngine.enabled` | Create AzureKubernetesEngine CR via post-install hook | `true` |
| `azure.kubernetesEngine.spec` | AzureKubernetesEngine CR spec | See [values.yaml](values.yaml) |
| **CoreWeave** | | |
| `coreweave.enabled` | Enable CoreWeave cloud provider | `false` |
| `coreweave.cloudManager.namespace` | CoreWeave Cloud Manager namespace | `rhai-cloudmanager-system` |
| `coreweave.cloudManager.image` | CoreWeave Cloud Manager image | `quay.io/opendatahub/opendatahub-operator:latest` |
| `coreweave.kubernetesEngine.enabled` | Create CoreWeaveKubernetesEngine CR via post-install hook | `true` |
| `coreweave.kubernetesEngine.spec` | CoreWeaveKubernetesEngine CR spec | See [values.yaml](values.yaml) |

## Testing with kind

You can test the chart locally using [kind](https://kind.sigs.k8s.io/).

### Create a cluster

```bash
kind create cluster --name rhoai --config ./kind.config.yaml
```

An example `kind.config.yaml` that uses local container registry credentials:

```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    extraMounts:
      - hostPath: /path/to/your/auth.json
        containerPath: /var/lib/kubelet/config.json
```

This mounts a local `auth.json` into the kind node so it can pull images from private registries. Set `hostPath` to the actual path of your container credentials file (e.g. `$HOME/.config/containers/auth.json` or `$XDG_RUNTIME_DIR/containers/auth.json`, depending on your system).

Alternatively, the chart supports `imagePullSecrets` — see the [Configuration](#configuration) section.

### Install the chart

```bash
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace \
  --namespace rhaii \
  --set azure.enabled=true
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
