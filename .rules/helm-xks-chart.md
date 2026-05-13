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
- `templates/webhooks/` — MutatingWebhookConfiguration.
- `templates/cloudmanager/{azure,coreweave}/` — cloud-specific resources (RBAC, CRDs, deployment).
- `templates/pull-secret.yaml` — optional image pull secret.
- `templates/validation.yaml` — calls `validateCloudProvider`.

### Cloud provider pattern

Exactly one of `azure.enabled` or `coreweave.enabled` must be true. Validated by `validateCloudProvider` helper.
Cloud-specific templates gated with `{{- if .Values.<provider>.enabled }}`.

### Key helpers (`_helpers.tpl`)

- `validateCloudProvider`: fails if zero or multiple providers enabled.
- `imagePullSecretEnabled`: checks `imagePullSecret.dockerConfigJson`.
- `imagePullSecretName`: defaults to `rhai-pull-secret`.
- `imagePullSecrets`: renders pod spec block.

### Image updates

`make update-image` fetches images from Build-Config repo into `values-<branch>.yaml` override files.
Override files (e.g. `values-rhoai-3.4.yaml`) are copies of `values.yaml` with patched image fields.

### Validation

```bash
make chart-snapshots CHART_NAME=rhai-on-xks-chart
make chart-test CHART_NAME=rhai-on-xks-chart
make helm-docs
```
