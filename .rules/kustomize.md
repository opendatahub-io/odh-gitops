---
paths: ["components/**", "dependencies/**", "configurations/**"]
---
New operator: component in `components/operators/<name>/`, overlay in `dependencies/operators/<name>/`.
No namespace in kustomization.yaml — set in individual resource files.
Add to parent kustomization: `dependencies/operators/kustomization.yaml` and `configurations/kustomization.yaml`.
Update `scripts/verify-dependencies.sh` for new operators.
Validate: `make validate-all`.
