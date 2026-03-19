# RHAII Helm Chart

Red Hat OpenShift AI Operator Helm chart for non-OLM installation.

This chart installs the RHAI operator and its cloud manager components. Exactly one cloud provider (Azure or CoreWeave) must be enabled.

## Installation

### Azure

```bash
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace --wait \
  --namespace rhaii \
  --set azure.enabled=true
```

### CoreWeave

```bash
helm upgrade rhaii ./charts/rhaii-helm-chart/ \
  --install --create-namespace --wait \
  --namespace rhaii \
  --set coreweave.enabled=true
```

## Post-install: Create Custom Resources

After installing the chart, you must create the required custom resources.

### Kserve (required)

```bash
kubectl apply -f - <<EOF
apiVersion: components.platform.opendatahub.io/v1alpha1
kind: Kserve
metadata:
  name: default-kserve
spec: {}
EOF
```

### AzureKubernetesEngine (when `azure.enabled=true`)

```bash
kubectl apply -f - <<EOF
apiVersion: infrastructure.opendatahub.io/v1alpha1
kind: AzureKubernetesEngine
metadata:
  name: default-azurekubernetesengine
spec:
  dependencies:
    certManager:
      configuration: {}
      managementPolicy: Managed
    gatewayAPI:
      configuration: {}
      managementPolicy: Managed
    lws:
      configuration: {}
      managementPolicy: Managed
    sailOperator:
      configuration: {}
      managementPolicy: Managed
EOF
```

### CoreWeaveKubernetesEngine (when `coreweave.enabled=true`)

```bash
kubectl apply -f - <<EOF
apiVersion: infrastructure.opendatahub.io/v1alpha1
kind: CoreWeaveKubernetesEngine
metadata:
  name: default-coreweavekubernetesengine
spec:
  dependencies:
    certManager:
      configuration: {}
      managementPolicy: Managed
    gatewayAPI:
      configuration: {}
      managementPolicy: Managed
    lws:
      configuration: {}
      managementPolicy: Managed
    sailOperator:
      configuration: {}
      managementPolicy: Managed
EOF
```

Set `managementPolicy: Unmanaged` for any dependency you want to manage yourself.

## Configuration

| Parameter | Description | Default |
|---|---|---|
| `enabled` | Enable/disable all resource creation | `true` |
| `installCRDs` | Install CRDs with the chart | `true` |
| `labels` | Common labels applied to all resources | `{}` |
| `rhaiOperator.namespace` | Operator namespace | `redhat-ods-operator` |
| `rhaiOperator.applicationsNamespace` | Applications namespace | `redhat-ods-applications` |
| `rhaiOperator.image` | Operator container image | `quay.io/opendatahub/opendatahub-operator:latest` |
| `azure.enabled` | Enable Azure cloud provider | `false` |
| `azure.cloudManager.namespace` | Azure Cloud Manager namespace | `cloudmanager-operator-system` |
| `azure.cloudManager.image` | Azure Cloud Manager image | `quay.io/opendatahub/opendatahub-operator:latest` |
| `coreweave.enabled` | Enable CoreWeave cloud provider | `false` |
| `coreweave.cloudManager.namespace` | CoreWeave Cloud Manager namespace | `cloudmanager-operator-system` |
| `coreweave.cloudManager.image` | CoreWeave Cloud Manager image | `quay.io/opendatahub/opendatahub-operator:latest` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |

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
