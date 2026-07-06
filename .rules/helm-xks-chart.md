---
paths: ["charts/rhai-on-xks-chart/**"]
---
## rhai-on-xks-chart (non-OCP Kubernetes)

Template prefix: `rhai-on-xks-chart.` for all helpers.

### Structure

- `templates/manager/` — RHAI operator deployment, namespaces, services.
- `templates/rbac/` — ServiceAccount, ClusterRole, ClusterRoleBinding.
- `templates/crds/` — CRDs bundled in chart.
- `templates/hooks/` — post-install Jobs (CRs creation, gateway setup).
  - `_crs-definitions.tpl` — **single source of truth** for provider and component CR metadata; add new providers/CRs here only. All templates update automatically.
- `templates/webhooks/` — MutatingWebhookConfiguration.
- `templates/cloudmanager/{azure,coreweave}/` — cloud-specific resources (RBAC, CRDs, deployment).
- `templates/pull-secret.yaml` — optional image pull secret.
- `templates/validation.yaml` — calls `validateCloudProvider`.

### Cloud provider pattern

Exactly one of `aws.enabled`, `azure.enabled`, or `coreweave.enabled` must be true. Validated by `validateCloudProvider` helper.
Use `activeProvider | fromYaml` to access the active provider — avoid ranging over all providers or checking `.Values.<provider>.enabled` directly.

**To add a new provider:** add one entry to `providerRegistry` in `templates/hooks/_crs-definitions.tpl`. No other templates need changing.

### Component CR pattern

Component CRs (e.g. Kserve from `components.platform.opendatahub.io`) are created/deleted via post-install and pre-delete hook jobs.

**To add a new component CR:** add one entry to `componentCRRegistry` in `templates/hooks/_crs-definitions.tpl`. No other templates need changing.

### Key helpers

**`templates/_helpers.tpl`:**

- `validateCloudProvider`: fails if zero or multiple providers enabled.
- `keResourceName`: returns plural KE resource name for the active provider.
- `kubernetesEngineDependencyNamespaces`: collects namespaces from enabled provider KE dependencies.
- `imagePullSecretEnabled` / `imagePullSecretName` / `imagePullSecrets`: image pull secret helpers.

**`templates/hooks/_crs-definitions.tpl`:**

- `providerRegistry` / `componentCRRegistry`: static YAML maps — CR kind, resource name (plural + singular), default CR name, API group.
- `activeProvider`: returns YAML dict for the one enabled provider. Parse with `| fromYaml`. Fields: `name`, `keKind`, `keResource`, `keResourceSingular`, `keName`, `keEnabled` (bool), `keSpec`, `cloudManagerNamespace`. Returns empty map if no provider enabled.
- `enabledProviderKECR`: returns `"true"` (truthy) or empty string when provider + KE are both enabled. Used as a boolean guard only — do not parse or inspect contents.
- `enabledComponentCRs`: returns a JSON list of enabled component names. Parse with `fromJson` before use in guards (`if or $componentCRs $providerKECR`). Do not range over or access fields — use `crApplyCommands` / `crDeleteCommands` instead.
- `crApplyCommands` / `crDeleteCommands`: emit kubectl apply/delete bash commands for all enabled CRs. Include with `| trimPrefix "\n" | nindent 14`.

### Image updates

`make update-image` fetches images from Build-Config repo into `values-<branch>.yaml` override files.
Override files (e.g. `values-rhoai-3.4.yaml`) are copies of `values.yaml` with patched image fields.

### Validation

```bash
make chart-snapshots CHART_NAME=rhai-on-xks-chart
make chart-test CHART_NAME=rhai-on-xks-chart
make helm-docs
```
