# RHAI on XKS Helm Chart

Red Hat AI Inference Helm chart for non-OLM installation on external Kubernetes services (AWS, Azure, CoreWeave).

This chart installs the RHAI operator and its cloud manager components. Exactly one cloud provider (AWS, Azure, or CoreWeave) must be enabled.

## Table of Contents

- [RHAI on XKS Helm Chart](#rhai-on-xks-helm-chart)
  - [Table of Contents](#table-of-contents)
  - [Prerequisites](#prerequisites)
  - [Pull Secrets](#pull-secrets)
    - [Obtaining credentials](#obtaining-credentials)
    - [What the pull secret does](#what-the-pull-secret-does)
  - [Installation](#installation)
    - [AWS](#aws)
    - [Azure](#azure)
    - [CoreWeave](#coreweave)
  - [How It Works](#how-it-works)
    - [Inference Gateway](#inference-gateway)
  - [Managed Dependencies](#managed-dependencies)
  - [Configuration Reference](#configuration-reference)
  - [Testing with kind](#testing-with-kind)
  - [Upgrading](#upgrading)
    - [Upgrading from 3.5 to 3.6](#upgrading-from-35-to-36)
  - [Uninstall](#uninstall)
    - [Clean up CRDs](#clean-up-crds)
    - [Clean up namespaces](#clean-up-namespaces)

## Prerequisites

- Kubernetes cluster
- Helm 4.x
- Cluster-admin privileges (the chart creates CRDs, ClusterRoles, and namespaces)
- Pull secret for `registry.redhat.io` (see [Pull Secrets](#pull-secrets) below)
- For platform auth gateway: the `xks-gateway` subchart is included as an optional dependency
  (disabled by default). Set `xks-gateway.enabled=true`, along with `xks-gateway.gateway.domain`
  and OIDC values, to create gateway resources.

## Pull Secrets

> [!IMPORTANT]
> A pull secret is **required** to install this chart. The chart pulls images from `registry.redhat.io`, including the `ose-cli-rhel9:v4.21.0` image used by the post-install hook Job.

### Obtaining credentials

```bash
podman login registry.redhat.io --authfile /path/to/auth.json
```

### What the pull secret does

The `imagePullSecret.dockerConfigJson` parameter:

1. Creates a `kubernetes.io/dockerconfigjson` Secret named `rhai-pull-secret` in all chart-managed namespaces (operator, applications, release, cloud manager, dependency namespaces, and `rh-ai-gateway` when gateway is configured)
2. Adds `imagePullSecrets` to all chart-managed ServiceAccounts (RHAI operator, cloud manager, llmisvc-controller-manager, the post-install hook, and gateway service accounts in `rh-ai-gateway` when the auth gateway is configured)

The secret name defaults to `rhai-pull-secret` and **should not** be changed.

> [!NOTE]
> Pull secrets for dependency namespaces (`cert-manager-operator`, `cert-manager`, `istio-system`, `openshift-lws-operator`) are managed by this chart by default. To customize which dependency namespaces receive pull secrets, set `imagePullSecret.dependencyNamespaces`.

## Installation

> [!NOTE]
> All commands below assume you are in the repository root directory.

> [!IMPORTANT]
> The gateway route attachment policy (`allowedRoutes.namespaces.from`) is **required**. See the [Inference Gateway](#inference-gateway) section for configuration details.

### AWS

```bash
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --install --create-namespace \
  --namespace rhai-gitops \
  --set aws.enabled=true \
  --set-json 'components.kserve.gateway.allowedRoutes.namespaces={"from":"Selector","selector":{"matchLabels":{"inference-gateway-access":"true"}}}' \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

### Azure

```bash
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --install --create-namespace \
  --namespace rhai-gitops \
  --set azure.enabled=true \
  --set-json 'components.kserve.gateway.allowedRoutes.namespaces={"from":"Selector","selector":{"matchLabels":{"inference-gateway-access":"true"}}}' \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

### CoreWeave

```bash
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --install --create-namespace \
  --namespace rhai-gitops \
  --set coreweave.enabled=true \
  --set-json 'components.kserve.gateway.allowedRoutes.namespaces={"from":"Selector","selector":{"matchLabels":{"inference-gateway-access":"true"}}}' \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

> [!WARNING]
> `helm install --wait` is **not supported**. The chart uses post-install hook Jobs to create Custom Resources after the operators are deployed. These hooks require CRDs to be registered first, and the rhai-operator depends on cert-manager to start correctly. Using `--wait` may cause the installation to time out or fail.

## How It Works

The chart performs a **multi-phase installation**:

1. **Phase 1 — Helm install:** deploys all operator resources (Deployments, RBAC, CRDs, etc.)
2. **Phase 2 — Post-install hook (weight 1):** a Helm hook Job creates the Custom Resources (Kserve CR, KubernetesEngine CR) that configure the operators
3. **Phase 3 — Post-install hook (weight 2):** a Helm hook Job waits for dependencies (Gateway API CRDs, cert-manager CA secret, GatewayClass `istio`) and then creates the `inference-gateway` Gateway CR along with its supporting ConfigMaps

Phase 2 and 3 are necessary because the CRs depend on CRDs and resources that are only available after the operators are deployed and reconciled.

### Platform auth gateway (optional)

This is separate from the KServe **inference gateway** below.

| | Inference gateway | Platform auth gateway |
|---|---|---|
| Chart values | `gateway.hostname`, `gateway.tls` | `xks-gateway.gateway.*` (subchart) |
| Gateway CR | `inference-gateway` (apps namespace) | `default-gateway` (cluster-scoped, reconciled in `rh-ai-gateway`) |
| Purpose | KServe model inference HTTPRoutes | OIDC auth proxy + platform ingress (`kube-auth-proxy`) |

The `xks-gateway` subchart is included as an optional dependency (disabled by default). To configure the auth gateway, set these values during install/upgrade:

```bash
helm upgrade --install rhai-on-xks ./charts/rhai-on-xks-chart \
  --set xks-gateway.enabled=true \
  --set xks-gateway.gateway.domain=example.com \
  --set xks-gateway.gateway.oidc.issuerURL=https://keycloak.example.com/realms/rhai \
  --set xks-gateway.gateway.oidc.clientID=rhai-client \
  --set xks-gateway.gateway.oidc.clientSecretRef.name=my-oidc-secret
```

When `xks-gateway.enabled=false` (default), the GatewayConfig CRD and gateway controller are not
installed or enabled. If the subchart is enabled but `xks-gateway.gateway.domain` is empty, only
the GatewayConfig CRD is installed and the controller remains idle.

When upgrading an existing release that uses the platform auth gateway, set
`xks-gateway.enabled=true` explicitly to keep it enabled. The xks-gateway subchart pre-hook
applies the bundled GatewayConfig CRD and waits for it to become Established. Its post-hook then
creates or updates the `GatewayConfig` CR after the gateway namespace and managed OIDC Secret are
installed, so enabling the gateway does not require a separate bootstrap command. When the gateway
is disabled during an upgrade, the parent cleanup hook removes the release-owned `GatewayConfig`
while retaining the CRD.

### Inference Gateway

By default (`components.kserve.gateway.create: true`), the chart creates a Gateway CR named `inference-gateway` in the applications namespace. This gateway is required for KServe model inference traffic.

You **must** configure which namespaces can attach HTTPRoutes to the gateway via `components.kserve.gateway.allowedRoutes.namespaces.from`. The chart will fail if this is not set. Use `Selector` (recommended) to restrict by namespace labels, or `Same` to allow only the gateway's own namespace:

```yaml
components:
  kserve:
    gateway:
      allowedRoutes:
        namespaces:
          from: Selector
          selector:
            matchLabels:
              inference-gateway-access: "true"
```

When using `Selector`, the specified labels must be applied to each target namespace.

The hook:

1. Waits for Gateway API CRDs to be installed (by the cloud manager)
2. Waits for the cert-manager CA secret (`rhai-ca`)
3. Creates a CA bundle ConfigMap (`rhai-ca-bundle`)
4. Creates a gateway config ConfigMap (`inference-gateway-config`) with CA bundle mount for istio-proxy and Azure-specific health probe annotation (Azure only)
5. Waits for the `istio` GatewayClass (created by Sail Operator)
6. Creates the `inference-gateway` Gateway CR

To disable automatic gateway creation:

```yaml
components:
  kserve:
    gateway:
      create: false
```

### MaaS Gateway

When AI Gateway is enabled (`components.aigateway.enabled: true`), the chart creates a MaaS Gateway CR via a post-install hook. The same `allowedRoutes` configuration is **required**:

```yaml
components:
  aigateway:
    enabled: true
    modelsAsAService:
      gateway:
        allowedRoutes:
          namespaces:
            from: Selector
            selector:
              matchLabels:
                maas-gateway-access: "true"
```

When using `Selector`, the specified labels must be applied to each target namespace (e.g. `kubectl label ns <model-namespace> maas-gateway-access=true`).

## Managed Dependencies

The KubernetesEngine CRs (AWS, Azure, or CoreWeave) manage the following dependencies. Each can be set to `Managed` (operator handles installation and lifecycle) or `Unmanaged` (you manage it yourself):

| Dependency | Description |
| --- | --- |
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
        gatewayAPI:
          managementPolicy: Unmanaged
```

cert-manager is managed by the chart, not by the KubernetesEngine CR. To use an
existing cluster cert-manager installation, disable the cert-manager-operator
subchart before `helm upgrade`:

```yaml
cert-manager-operator:
  enabled: false
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
  --namespace rhai-gitops \
  --set azure.enabled=true \
  --set-json 'components.kserve.gateway.allowedRoutes.namespaces={"from":"Selector","selector":{"matchLabels":{"inference-gateway-access":"true"}}}' \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

## Upgrading

### Upgrading from 3.5 to 3.6

Version 3.6 moves cert-manager installation from a kubectl-based Job hook to a Helm subchart.
Because the cert-manager resources in 3.5 were created outside of Helm, they have no Helm
ownership metadata. Helm will refuse to adopt them during a standard upgrade.

For this one-time upgrade, pass `--take-ownership --force-conflicts` to let Helm claim those existing resources and resolve field manager conflicts:

```bash
helm upgrade rhaii ./charts/rhai-on-xks-chart/ \
  --namespace rhai-gitops \
  --take-ownership --force-conflicts \
  --set azure.enabled=true \
  --set-file imagePullSecret.dockerConfigJson=/path/to/auth.json
```

> [!NOTE]
> `--take-ownership` and `--force-conflicts` require Helm 4.x. These flags are only needed for
> the 3.5→3.6 upgrade; subsequent upgrades do not require them.

## Uninstall

```bash
helm uninstall rhaii -n rhai-gitops
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

**AWS:**
```bash
kubectl delete crd awskubernetesengines.infrastructure.opendatahub.io
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

### Clean up cert-manager-operator

If `cert-manager-operator.enabled` was `true` at any point, RHAI's cert-manager resources
(the `cert-manager-operator`/`cert-manager` namespaces, the `CertManager` CR, and its
cluster-scoped RBAC) are **not** automatically removed on `helm uninstall`, nor when later
setting `cert-manager-operator.enabled: false`. The chart never deletes them automatically —
on uninstall or otherwise. If you point `cert-manager-operator.enabled: false` at a cluster
where cert-manager was installed some other way (e.g. via OLM): treat it as unmanaged by this
chart and remove it yourself. As with chart-managed CRDs above, remove them manually if you no
longer need them:

```bash
# Remove the finalizer first so the CR is not stuck in Terminating after the operator is gone
kubectl patch certmanager cluster --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
# Delete the operator namespace to stop the operator before deleting the CR (otherwise it recreates it)
kubectl delete namespace cert-manager-operator
kubectl delete certmanager cluster --ignore-not-found
kubectl delete namespace cert-manager
kubectl delete clusterrole cert-manager-operator-controller-manager-clusterrole cert-manager-operator-metrics-reader
kubectl delete clusterrolebinding cert-manager-operator-controller-manager-clusterrolebinding
```
