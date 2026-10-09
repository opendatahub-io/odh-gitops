# Cluster Observability Operator ownership and migration

The Helm chart and Kustomize manifests use `openshift-cluster-observability-operator`
as the Cluster Observability Operator (COO) OperatorGroup name, matching the RHACM
multicluster observability addon. The namespace has the same name. The Subscription
and its package name remain `cluster-observability-operator`.

Older revisions created an OperatorGroup named `cluster-observability-operator`.
If RHACM also creates its OperatorGroup in this namespace, OLM finds two groups and
fails the operator's ClusterServiceVersion (CSV). See
[RHOAIENG-99507](https://redhat.atlassian.net/browse/RHOAIENG-99507) and the
[OLM OperatorGroup documentation](https://olm.operatorframework.io/docs/concepts/crds/operatorgroup/#toomanyoperatorgroups).

## Choose one owner

Matching names prevents two distinct OperatorGroups, but does not resolve competing
controllers managing the same OperatorGroup or Subscription. Choose one product to
manage COO installation and upgrades.

When RHACM already manages COO, configure the Helm chart to use that installation:

```yaml
dependencies:
  clusterObservability:
    enabled: false
```

This suppresses the chart's COO Namespace, OperatorGroup and Subscription, including
when monitoring is `Managed`. Monitoring configuration and its other dependencies
can still be managed by the chart. For Kustomize, omit the COO component from your
installation overlay when RHACM owns it.

When this repository owns COO, configure RHACM to leave its installation and
Subscription under that ownership before synchronizing the corrected manifests.
The Helm chart also supports an explicit name for a separately managed environment:

```yaml
dependencies:
  clusterObservability:
    olm:
      operatorGroupName: custom-coo-group
```

Keep exactly one OperatorGroup in the COO namespace. A custom name does not allow
multiple products to create separate groups in that namespace.

## Migrate an existing installation

1. Inspect the current resources and identify their managers:

   ```bash
   kubectl get operatorgroup,subscription,csv -n openshift-cluster-observability-operator
   kubectl get namespace openshift-cluster-observability-operator -o yaml
   kubectl get operatorgroup,subscription -n openshift-cluster-observability-operator -o yaml --show-managed-fields
   ```

   Review ownership, Argo CD tracking metadata and Subscription settings, including
   the channel, catalog source and install plan approval policy.

2. Coordinate the ownership decision with the RHACM and GitOps administrators.
   Update all desired configurations so no controller recreates the obsolete group.
   Pause automated synchronization and pruning during an ownership handoff. When
   disabling the chart's COO dependency, protect the existing namespace,
   Subscription and retained OperatorGroup from deletion by the previous manager.
   Removing them from rendered output is not itself an ownership transfer.

3. Synchronize the corrected configuration under the chosen owner. A name change
   creates a different Kubernetes object; it does not rename the existing group.
   Plain `kubectl apply -k` leaves the old group behind. Helm or Argo CD may remove
   it during upgrade or pruning, but verify the result before proceeding.

   For direct Helm releases, an existing RHACM-created resource is not automatically
   adopted. Prefer external ownership when RHACM remains responsible; any deliberate
   Helm adoption must be coordinated with the previous owner. See
   [Helm ownership options](https://docs.helm.sh/docs/helm/helm_upgrade/).

4. Once the retained OperatorGroup exists and no desired configuration references
   the obsolete group, remove the obsolete group if it remains:

   ```bash
   kubectl delete operatorgroup cluster-observability-operator \
     -n openshift-cluster-observability-operator --ignore-not-found
   ```

   Preserve the namespace, Subscription and retained OperatorGroup. Ensure the
   previous manager no longer tracks shared resources for deletion before restoring
   automated pruning.

5. Verify that exactly one OperatorGroup remains, the CSV reaches `Succeeded`, and
   Subscription reconciliation and upgrades resume. Allow several reconciliation
   cycles and confirm the obsolete group is not recreated:

   ```bash
   kubectl get operatorgroup,subscription,csv -n openshift-cluster-observability-operator
   ```

The chart does not run a cleanup hook: an existing group's ownership and the active
controllers must be checked before deletion.
