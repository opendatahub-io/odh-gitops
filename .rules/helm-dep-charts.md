---
paths: ["charts/dependencies/**"]
---
## charts/dependencies/ — standalone operator charts (non-OLM)

Each subdirectory is an independent Helm chart extracted from OLM bundles for vanilla Kubernetes (no OLM).

### Chart structure

- `crds/` — CRD YAMLs (raw, not templated).
- `templates/` — Deployments, RBAC, Services, operator CRs. Namespace refs templated via `{{ .Values.operatorNamespace }}`.
- `scripts/update-bundle.sh` — extracts manifests from registry bundle image using `olm-extractor`. Splits into CRDs vs templates, templatizes namespaces, adds imagePullSecrets to ServiceAccounts.
- `test/snapshots/` — snapshot test files.
- `values.yaml` — minimal: `operatorNamespace`, `operandNamespace` (if different), `imagePullSecrets`, `bundle.version`.

### Patterns

- Templates are mostly static YAML with namespace templating only (`{{ .Values.operatorNamespace }}`).
- No complex helpers — each chart is self-contained.
- CRDs go in `crds/` (Helm manages them separately), NOT in `templates/`.
- Operator CR templates (e.g. `certmanager.yaml`, `leaderworkersetoperator.yaml`) are simple static specs.
- ServiceAccounts include `{{- with .Values.imagePullSecrets }}` block.

### Updating a dependency

Run `scripts/update-bundle.sh <version>` — requires `podman login registry.redhat.io`.
After update: review extracted manifests, run snapshot tests.

### Validation

```bash
helm template <chart-name> charts/dependencies/<chart-name>
make chart-snapshots
make chart-test
```
