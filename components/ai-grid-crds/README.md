# Temporary AI Grid CRD carry

This opt-in Kustomize overlay carries the five Grid CRDs from
[`praxis-proxy/grid` at `399028f`](https://github.com/praxis-proxy/grid/tree/399028f1c959442b469bff56e4c0d6c5b5e37ac8/deploy/crds)
while the downstream RHOAI operator's manifest bundle catches up. The files in
`base/` are unchanged copies of that commit's `deploy/crds/` directory. The
schemas already exist upstream; this overlay only adds GitOps ownership metadata.

Updating the Grid runtime image does not update the platform's bundled schemas.
In particular, older schemas prune GridSite `spec.signalsEndpoint` and the
GridNetwork `spec.membership` declaration. Restarting
the Grid operator, or toggling the AI Gateway component's management state, does
not supply a newer manifest bundle.

## Enable

Add this directory as an additional source of each cluster's existing Argo CD
Application, alongside the RHOAI chart:

```yaml
repoURL: https://github.com/opendatahub-io/odh-gitops.git
targetRevision: feature-ai-grid
path: components/ai-grid-crds
```

The overlay is not included in the repository's default Kustomize installation
or any Helm chart. It changes no Deployments, identities, or membership settings.
The schemas match the commit above, including the optional GridNetwork
`spec.membership.mode` declaration. `scripts/update-ai-grid-charts.sh` refreshes
them from the same commit as the vendored charts. Before setting that declaration or enabling
bootstrap-owned grid identity, deploy operator and enrollment images that
support those features on every applicable cluster. Updating CRDs alone does
not change the running membership mode.

`opendatahub.io/managed: "false"` makes the platform deploy action skip these
individual CRDs. The AI Gateway component and its workloads remain Managed.
Argo uses server-side apply to take schema ownership from the platform and
applies the CRDs before ordinary resources. `Prune=false,Delete=false` retains
the CRDs, and therefore their custom resources, if this source or Application
is removed. Do not use force sync, replace, or CRD deletion to install this carry.

## Validate

```sh
kubectl kustomize components/ai-grid-crds
kubectl --context "$TARGET_CONTEXT" apply --server-side --force-conflicts \
  --field-manager=argocd-controller --dry-run=server -k components/ai-grid-crds
```

After Argo sync, check all five CRDs are Established and the GridSite schema has
`spec.signalsEndpoint` and the GridNetwork schema has `spec.membership.mode`.
Confirm the schemas and unmanaged annotation remain present
through platform reconciliation, and that Grid workloads remain ready. A server
dry run validates the schemas but does not prove reconciliation behavior.

## Return ownership to the platform

Removing this source alone deliberately leaves both the CRDs and their unmanaged
annotation in place. Complete the handoff explicitly:

1. Wait for the ODH-to-RHDS sync, promotion to `rhoai-3.6`, and deployment of a
   RHOAI operator image whose bundled Grid CRD schemas match this carry (or a
   reviewed newer version). Verify the bundle on every target cluster.
2. While Argo still renders this source, change the overlay annotation to
   `opendatahub.io/managed: "true"` through a PR and sync it. With matching schemas,
   the platform can resume ownership without a schema downgrade. If downstream
   is newer, first align the carried files so the two controllers agree.
3. Confirm platform reconciliation succeeds, then remove this source from the
   consuming ApplicationSet through a second PR. Keep the CRD deletion protections
   until Argo has stopped tracking the resources; do not approve pruning them.
   Argo may report retained CRDs as requiring pruning during this handoff.

Do not revert to the old schemas after using newly introduced fields: Kubernetes
can prune unsupported fields on subsequent custom-resource writes. Restore
platform ownership only after its bundle has caught up.
