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

The GatewayConfig CRD is in `crds/` (not `templates/`) and the `GatewayConfig` is applied by a
subchart lifecycle hook. This keeps Helm from mapping the custom resource before the CRD exists.

- On install or upgrade with `enabled=true`, a pre-install/pre-upgrade hook applies the bundled CRD
  and waits for it to become Established. A post-install/post-upgrade hook then creates or updates
  `default-gateway`, after Helm has created the gateway namespace and chart-managed OIDC Secret.
- When `enabled=false` is applied during an upgrade, the hook deletes `default-gateway` but leaves
  the CRD installed. CRDs are intentionally retained because Helm does not delete CRDs.
- GatewayConfig schema changes merged into `rhods-operator` are automatically synchronized into this chart by the [GitOps sync workflow](https://github.com/red-hat-data-services/rhods-operator/blob/main/.github/workflows/trigger-gitops-sync.yaml).
- For local or manual updates, regenerate the CRD in the operator repository, then run `./scripts/sync-gatewayconfig-crd.sh /path/to/operator-repository` from this chart directory.
- If the gateway dependency is disabled, apply an updated CRD explicitly when you need to roll a
  schema change without enabling the gateway:
  `kubectl apply -f crds/customresourcedefinition-gatewayconfigs.services.platform.opendatahub.io.yaml`.

The same lifecycle hook is used when this chart is installed standalone or as a dependency of
`rhai-on-xks-chart`. The parent chart adds only a cleanup hook for the case where the dependency is
disabled, because a disabled subchart cannot render its own cleanup hook.

## OIDC client secret

**Recommended (production):** create a Kubernetes Secret in `rh-ai-gateway` and set `gateway.oidc.clientSecretRef.name` (and `key` if not `client-secret`).

**Dev/test only:** set `gateway.oidc.oidcClientSecret` (or `--set-file`) to have the chart create the Secret. The value is stored in the Helm release Secret.

## Namespace

When the gateway is configured, the chart creates `rh-ai-gateway`. The operator hardcodes this namespace; `gateway.namespace` cannot be changed.

The namespace has `helm.sh/resource-policy: keep` so `helm uninstall` does not delete workloads in `rh-ai-gateway`.

## Values

See the generated [API docs](api-docs.md#values) for the complete, current values reference.
