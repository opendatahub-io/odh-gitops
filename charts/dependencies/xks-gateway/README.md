# xks-gateway

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

XKS Gateway onboarding chart - installs the GatewayConfig CRD, gateway namespace, and GatewayConfig CR for non-OpenShift Kubernetes.

## Usage

This chart is a **subchart** of `rhai-on-xks-chart` (disabled by default in the parent chart). Configure it via `xks-gateway.gateway.*` values when installing the parent chart:

```bash
helm upgrade --install rhai-on-xks ./charts/rhai-on-xks-chart \
  --set xks-gateway.enabled=true \
  --set xks-gateway.gateway.domain=example.com \
  --set xks-gateway.gateway.oidc.issuerURL=https://keycloak.example.com/realms/rhai \
  --set xks-gateway.gateway.oidc.clientID=rhai-client \
  --set xks-gateway.gateway.oidc.clientSecretRef.name=my-oidc-secret
```

When the chart is enabled and `gateway.domain` is empty, only the GatewayConfig CRD is installed and no gateway resources are created. It can also be installed standalone for testing.

## CRD handling

The GatewayConfig CRD is in `crds/` (not `templates/`) so `helm install` applies it **before** the `GatewayConfig` CR.

- Use `--skip-crds` on later installs/upgrades if the CRD already exists.
- GatewayConfig schema changes merged into `rhods-operator` are automatically synchronized into this chart by the [GitOps sync workflow](https://github.com/red-hat-data-services/rhods-operator/blob/main/.github/workflows/trigger-gitops-sync.yaml).
- For local or manual updates, regenerate the CRD in the operator repository, then run `./scripts/sync-gatewayconfig-crd.sh /path/to/operator-repository` from this chart directory.
- Helm does **not** upgrade files in `crds/` on `helm upgrade`. To roll a schema change on an existing cluster, apply the updated CRD explicitly: `kubectl apply -f crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml`.

## OIDC client secret

**Recommended (production):** create a Kubernetes Secret in `rh-ai-gateway` and set `gateway.oidc.clientSecretRef.name` (and `key` if not `client-secret`).

**Dev/test only:** set `gateway.oidc.oidcClientSecret` (or `--set-file`) to have the chart create the Secret. The value is stored in the Helm release Secret.

## Namespace

When the gateway is configured, the chart creates `rh-ai-gateway`. The operator hardcodes this namespace; `gateway.namespace` cannot be changed.

The namespace has `helm.sh/resource-policy: keep` so `helm uninstall` does not delete workloads in `rh-ai-gateway`.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Red Hat |  |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `true` | Enable or disable the chart. When used as a dependency of `rhai-on-xks-chart`, this controls whether the GatewayConfig CRD, gateway namespace, GatewayConfig CR, and OIDC resources are created. |
| gateway.certificate.secretName | string | `""` | Name of TLS Secret (required when type is Provided) |
| gateway.certificate.type | string | `"SelfSigned"` | TLS strategy: SelfSigned (auto-generated) or Provided (BYO secret in gateway namespace) |
| gateway.cookie.expire | string | `"24h"` | Session cookie expiry duration (e.g., "24h", "8h") |
| gateway.cookie.refresh | string | `"1h"` | Access token refresh interval — must be less than the OIDC provider's Access Token Lifespan |
| gateway.domain | required | `""` | External hostname (e.g., example.com or *.example.com) |
| gateway.ingressMode | string | `"LoadBalancer"` | How the gateway is exposed externally on XKS (LoadBalancer only) |
| gateway.namespace | string | `"rh-ai-gateway"` | Namespace created when the gateway is configured. Must be rh-ai-gateway to match the operator (not configurable). |
| gateway.networkPolicy.ingress.enabled | bool | `true` | Enable ingress NetworkPolicy for kube-auth-proxy |
| gateway.oidc.clientID | required | `""` | OIDC client ID |
| gateway.oidc.clientSecretRef | object | `{"key":"client-secret","name":""}` | Reference to the OIDC client secret (BYO mode) or chart-created secret name (managed mode) |
| gateway.oidc.clientSecretRef.key | string | `"client-secret"` | Key within the Secret that holds the client secret value |
| gateway.oidc.clientSecretRef.name | string | `""` | Name of the Kubernetes Secret. Required when oidcClientSecret is not set; defaults to oidc-client-secret when oidcClientSecret is set. |
| gateway.oidc.issuerURL | required | `""` | OIDC provider URL (e.g., https://keycloak.example.com/realms/rhai) |
| gateway.oidc.oidcClientSecret | string | `""` | OIDC client secret value for chart-managed Secret (dev/test). Prefer clientSecretRef for production. |
| gateway.oidc.secretNamespace | string | `""` | Namespace where the client secret is located (defaults to gateway.namespace if empty) |
| gateway.providerCASecretName | string | `""` | Name of Secret containing CA cert for the auth provider (must have ca.crt key, in gateway namespace) |
| gateway.subdomain | string | `""` | Subdomain prefix for the gateway |
| gateway.verifyProviderCertificate | bool | `true` | Verify auth provider TLS certificate (set to false only for development) |
