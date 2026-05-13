---
paths: ["charts/rhai-on-openshift-chart/**"]
---
## rhai-on-openshift-chart (OCP/OLM-based)

Template prefix: `rhoai-dependencies.` for all helpers.

### Dependency templates

Follow `templates/dependencies/cert-manager/operator.yaml` pattern:
- `operator.yaml`: gate with `shouldInstall` + `isOlmMode`, call `rhoai-dependencies.operator.olm`.
- `config.yaml` (optional): gate with `shouldInstall` + `crdExists`, render CR with `$dep.config.spec`.
- Pass all OLM fields: `name`, `namespace`, `channel`, `version`, `targetNamespaces`, `config`, `root`.

### Adding dependency

1. Add to `values.yaml` under `dependencies.yourOperator` (enabled: auto, olm config, optional config/dependencies).
2. Create `templates/dependencies/your-operator/operator.yaml` (and `config.yaml` if CR needed).
3. Update `values.schema.json`.
4. Run `make helm-docs`.

### Adding component

1. Add to `values.yaml` under `components.yourComponent` (dependencies, dsc, optional defaults per operator type).
2. Add to `templates/operator/datasciencecluster.yaml` using `componentDSCConfig`.
3. Add to `docs/examples/values-all-components-managed.yaml`.
4. Update `values.schema.json`.
5. Run `make helm-docs`.

### Adding profile

1. Create `profiles/<name>.yaml` — only override components/services that differ from default (Removed).
2. Add name to `profile` enum in `values.schema.json`.
3. Add snapshot entry in `scripts/snapshot-config.yaml`.

### Key helpers (in `templates/definitions/`)

- `shouldInstall`: tri-state (true/false/auto) → resolves via component/service/transitive deps.
- `isOlmMode`: true when `tags.install-with-helm-dependencies` is false (default).
- `crdExists`: checks CRD presence or `skipCrdCheck` flag. Use in config.yaml templates.
- `componentDSCConfig`: merges user values > operator-type defaults > profile defaults.
- `effectiveComponentManagementState` / `effectiveServiceManagementState`: resolves null states via profiles.
- `operator.olm`: generates Namespace + OperatorGroup + Subscription.

### Validation

```bash
make chart-snapshots CHART_NAME=rhai-on-openshift-chart
make chart-test CHART_NAME=rhai-on-openshift-chart
make helm-docs
helm template ./charts/rhai-on-openshift-chart -f docs/examples/values-all-components-managed.yaml --set skipCrdCheck=true
```
