# odh-gitops

GitOps repo for OpenDataHub/RHOAI dependencies and Helm charts. Kustomize layers + Helm charts for OCP operator deployment.

## Build & Test

```bash
make validate-all          # YAML lint + kustomize build + kube-linter
make chart-test            # Helm snapshot tests
make chart-snapshots       # Regenerate snapshots
make helm-docs             # Regenerate api-docs.md (commit result)
helm lint ./charts/<chart> # Lint single chart
helm template ./charts/rhai-on-openshift-chart -f docs/examples/values-all-components-managed.yaml --set skipCrdCheck=true
```

## Conventions

- Commits: conventional format `type(JIRA-ID): description`. All non-chore commits need Jira link.
- YAML indent: 2 spaces. Line length max 180.
- Kustomize: no namespace in `kustomization.yaml`, set in individual resource files.
- Helm dependencies: tri-state `enabled` (auto/true/false). Use `shouldInstall` helper.
- Helm docs: run `make helm-docs` after values.yaml changes, commit generated `api-docs.md`.

## Before writing code

Read existing files in same area to match patterns. Key examples:

- Kustomize dependency: `components/operators/cert-manager/`, `dependencies/operators/kueue-operator/`
- Kustomize config: `configurations/kueue-operator/`
- Helm dependency template: `charts/rhai-on-openshift-chart/templates/dependencies/cert-manager/operator.yaml`
- Helm helpers: `charts/rhai-on-openshift-chart/templates/definitions/_helpers.tpl`
- Helm values schema: `charts/rhai-on-openshift-chart/values.schema.json`
- Snapshot config: `scripts/snapshot-config.yaml`
- Adding new dependency: see `CONTRIBUTING.md`

## Architecture

- `components/operators/` — reusable Kustomize components per operator
- `dependencies/operators/` — composed Kustomize overlays (reference components, add patches)
- `configurations/` — post-CRD operator config (CRs that need OLM-installed CRDs)
- `charts/rhai-on-openshift-chart/` — Helm chart for OCP (OLM-based)
- `charts/rhai-on-xks-chart/` — Helm chart for non-OCP Kubernetes
- `scripts/` — verification, snapshot, and maintenance scripts
- `bin/` — local tool binaries (gitignored content, committed wrappers)
