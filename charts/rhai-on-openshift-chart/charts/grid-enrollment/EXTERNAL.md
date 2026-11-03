# External identities

The enrollment chart supports two identity backends. `mode: service` preserves
the enrollment service, its CA bootstrap Job, database, and invite flow.
`mode: external` consumes identities supplied by another PKI. It does not
deploy the service, database, invite Jobs, or their RBAC. Both modes fit the
same lifecycle: bootstrap, enroll, and decommission.

## Bootstrap

A management-only hub can host bootstrap and enrollment policies without local
Grid workloads. The hub policy targets `managedClusters.hubClusterName`;
grid membership uses the separate member-label selector. Leave that label off
the hub to enroll only spokes. If the hub also hosts Grid workloads, select it
as a member and it receives the same identity and GridNetwork as any other
cluster. The hub needs the governance policy add-on and any optional PKI
integration.

Enable `gridIdentity.enabled` to create the grid ID once in the immutable
`grid-bootstrap-state` ConfigMap. Bootstrap reads and writes only that
ConfigMap: when it is absent, bootstrap generates a UUID v4 and saves it.
Retries reuse the saved value, including concurrent bootstrap runs. A malformed
existing ConfigMap is an error, never a reason to mint another ID. Bootstrap
reads no Grid object, so the hub needs no Grid CRD. Back up this ConfigMap with
the CA and retain it through CA rotation.

To keep an existing grid's ID, create the ConfigMap before the first
`gridIdentity.enabled` run, with that ID under `gridId`. Bootstrap mints a new
ID when the ConfigMap is absent, and creating it afterwards cannot replace one
already saved. Apply the same object bootstrap writes:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grid-bootstrap-state
  namespace: <release-namespace>
  labels:
    app.kubernetes.io/managed-by: grid-enrollment-bootstrap
  annotations:
    helm.sh/resource-policy: keep
    argocd.argoproj.io/sync-options: Prune=false,Delete=false
immutable: true
data:
  gridId: <existing-grid-id>
```

Bootstrap uses a pre-created ConfigMap unchanged, and refuses one without
`immutable: true`. A ConfigMap created by an earlier release's
`kubectl create configmap` instructions is mutable, so make it immutable in
place before upgrading. Do not delete and recreate it: bootstrap could mint a
new ID in between.

```bash
kubectl -n <release-namespace> patch configmap grid-bootstrap-state --type merge -p '{"immutable":true}'
```

The existing ID is each
member GridNetwork's `spec.gridId` when set, otherwise its `status.gridId`.
Every member must report the same ID. The member policy checks every
GridNetwork on the member. It refuses a GridNetwork with another name, and
refuses to touch one whose ID differs from the saved one, reporting `existing
grid ID <old> differs from bootstrap state <new>`.

To recover from that refusal, pick one side. To keep the member's grid, delete
`grid-bootstrap-state` and create it again, immutable, with `<old>`. Bootstrap
mints a new ID when the ConfigMap is absent, so do this only while bootstrap
cannot run: no `helm upgrade` of this release and no Argo sync of its
Application between the delete and the create. To move the member to `<new>`,
delete its GridNetwork; the policy recreates it with the saved ID. Moving a
member drops the state its peers hold under the old ID.

Earlier releases also created a hook ClusterRole and ClusterRoleBinding that
let bootstrap read the GridNetwork. Helm does not delete a hook resource that a
chart stops rendering, so remove that pair after the upgrade:

```bash
name=<release-namespace>-<bootstrap-service-account>
prefix=$(printf %s "${name:0:54}" | sed -e 's/-$//' -e 's/\./\\./g')
kubectl get clusterrole,clusterrolebinding -o name | grep -E "/${prefix}-[0-9a-f]{8}$"
```

That lists the pair the earlier chart named after the release. Check it, then
delete each object it printed:

```bash
for object in $(kubectl get clusterrole,clusterrolebinding -o name | grep -E "/${prefix}-[0-9a-f]{8}$"); do
  kubectl delete "$object"
done
```

In external mode the existing bootstrap Job uses `--skip-ca` and has no Secret
permissions. In service mode that same Job also handles CA and credentials.
Use an image that supports `--grid-id-config-map` before enabling it.
Upgrade the chart and the bootstrap image together. This chart no longer grants
GridNetwork read access or passes `--grid-network`, so a v0.3.0-rc.2 or earlier
image, which reads the GridNetwork named by its `grid` default, fails with 403.
For managed clusters, the enrollment policy creates a complete GridNetwork
with the saved ID, Local membership, polling, SPIFFE trust, and references to
the delivered identity and CA Secrets. It waits for those Secrets before
creating the network. `managedClusters.gatewayName` defaults to `grid-gateway`;
the gateway reference uses each cluster's name as its site name. Enrollment
retains the network on decommission. Other delivery systems must copy the saved
value into each member's GridNetwork (or the chart's
`grid.id` value). The ID is independent of the CA and is immutable once declared.

For externally supplied identities, provision the shared trust bundle and the
site identity Secrets through your PKI integration. The chart reads references;
private keys never belong in values or Git. Managed-cluster delivery expects
each identity Secret to contain `tls.crt` and `tls.key`, and the trust Secret
to contain `ca.crt` (or the configured `external.trustBundleSecretKey`).

Cert-manager is an optional integration, installed separately. An existing
Issuer, ClusterIssuer, or external issuer can be referenced without the chart
owning it:

```yaml
mode: external
external:
  certManager:
    enabled: true
    issuer:
      create: false
      name: site-issuer
      kind: ClusterIssuer
      group: cert-manager.io
```

To expose an existing Grid CA through a namespaced Issuer, use:

```yaml
mode: external
external:
  certManager:
    enabled: true
    issuer:
      create: true
      name: grid-ca
    ca:
      mode: Existing
      secretName: grid-ca-key
```

This creates only an Issuer when no sites are configured. It does not write,
renew, or take ownership of the existing CA Secret. The Secret must contain
`tls.crt` and `tls.key` and be in the release namespace.

For a **new grid only**, `external.certManager.ca.mode: Generate` creates a
self-signed root CA and its Issuer. Its signing key is reused on renewal.
Helm and Argo retention annotations preserve the generated CA Certificate,
Secret, and self-signed Issuer during ordinary uninstall and pruning. Keep a
backup: explicit Kubernetes deletion and namespace deletion are not covered.
CA rotation remains a coordinated trust migration.

## Enroll

Declare sites by their Grid identity name. `secretName` defaults to
`grid-site-<site>`. With the optional integration enabled, the chart requests a
Certificate for each site. Otherwise the referenced Secret must already be
supplied by your PKI integration.

```yaml
mode: external
external:
  sites:
    site-a:
      secretName: site-a-identity
      dnsNames: [signals.example.com]
      cluster: managed-a
  trustBundleSecretRef: grid-public-trust
  delivery:
    enabled: true
    namespace: grid-system
    clusterSet: default
    # Set false if another Application already owns the binding.
    createClusterSetBinding: false
```

Certificates use the Grid profile: one organization and SPIFFE URI naming the
site, its `<site>.grid.internal` DNS SAN, and client/server authentication
usages. The optional integration creates ECDSA keys and renews them with the
certificates. External issuers must permit this profile. Additional listener
DNS names belong in `dnsNames`; they do not change the site's identity.

The policy delivers the identity and public trust bundle only to the named managed
cluster. Hub `fromSecret` templates encrypt Secret values; the CA signing key
is never included in the delivery policy. Policies follow Secret updates, so
renewal does not require a Helm hook. When the chart creates a CA Issuer, the
delivery bundle comes from that CA Secret's public `tls.crt`. Otherwise an
explicit public trust bundle is required, including with an external issuer.

Leave `cluster` empty for an identity issued locally on the hub. Certificate
Secrets always live in the release namespace; local identity consumers must
read them there. Each managed cluster receives one identity. The chart rejects policy names
whose namespace-qualified form exceeds the 63-character policy label limit. Removing a site
from this map alone is not a complete decommission operation.

## Managed clusters

Set `managedClusters.enabled: true` to bootstrap inventory-based enrollment and
peer distribution. The chart can be deployed by Helm or a GitOps reconciler;
there is no Argo-specific controller or ApplicationSet in this flow. This
integration requires Placement, governance policy, and ManifestWork APIs,
including `ReadOnly` work with `feedbackScrapeType: Watch`. The hub must itself
be registered with the governance policy add-on. All selected clusters need
that add-on, the work agent, the Grid CRDs, and the Local-mode operator.

The supported onboarding flow starts when a newly registered cluster is
selected for membership. Platform deployment supplies its operator and CRDs.
Before writing Grid custom resources, the enrollment policy waits for both
the GridNetwork and GridSite CRDs to report `Established=True`. The watched
lookups resume delivery when those CRDs become ready; identity delivery can
proceed independently because it uses core Kubernetes resources.

```yaml
mode: external
fullnameOverride: grid-bootstrap
gridIdentity:
  enabled: true
grid:
  membership:
    source: Local
managedClusters:
  enabled: true
  clusterSet: default
  clusterLabel: grid.praxis.fast/member
  clusterLabelValue: 'true'
  hubClusterName: local-cluster
external:
  delivery:
    namespace: grid-system
  certManager:
    enabled: true
    issuer:
      create: true
      name: grid-ca
    ca:
      mode: Existing
      secretName: grid-ca-key
```

Keep `external.sites` empty and `external.delivery.enabled: false` in this
mode. The selected ManagedCluster name is also its Grid site identity. Use DNS
label names of at most 51 characters. The hub reads the selected inventory,
requests one identity per cluster, and creates a read-only observer of each
cluster's own GridSite. Without cert-manager, your PKI must supply Secrets named
`<managedClusters.identitySecretPrefix><cluster-name>` and a public trust bundle.
The certificate profile includes both the gateway and signals DNS names in
Local mode. Renewing at one third of the lifetime remaining matches the
operator's external-renewal deadline.

Each member owns its local GridSite, including its public gateway and signals
endpoints. An observer watches changes and returns only selected public spec
fields. The hub distributes remote records to the other selected members and
supplies `grid-operator-config` with their site name. It never copies a record
back to its source or replicates health/status. The Local operator then polls
the peer's provider catalog and signals; no InferenceProvider copies or SWIM
key distribution are needed.

The template ServiceAccount can list cluster inventory and read only the named
observer across namespaces. The chart installs this permission in its ClusterRole
so template resolution does not depend on the hub policy first creating per-member
RBAC. The templates still select members by label and cluster set. The account
cannot read Secrets or modify ManifestWorks. Identity policies use encrypted
`fromSecret` templates in the issuer namespace. Existing CA resources remain
outside membership pruning.

The inventory and membership policies carry a `policy.open-cluster-management.io/trigger-update`
annotation derived from the lookup permissions. A chart update that changes those
permissions also requests hub-template reprocessing, including when an earlier
permission error prevented the dependency watch from starting.

An endpoint change updates remote GridSites; removing optional fields clears
them rather than retaining stale endpoints or trust pins. Removing a member's
selection label or inventory entry withdraws its remote records and stops
renewal by deleting the generated Certificate and observer. This is eventually
consistent: policies can reconcile in either order. Check peer withdrawal
before treating a removal as complete. An unavailable member retains its last
observed public endpoints; disappearance of its source GridSite withdraws that
record when the work agent reports missing feedback.

See the [ManifestWork documentation] for feedback behavior and limits. A work
agent can fall back to polling when its watch limit is reached.

[ManifestWork documentation]: https://open-cluster-management.io/docs/concepts/work-distribution/manifestwork/


## Decommission

Managed-cluster policies implement inventory withdrawal and stopping renewal.
The full ordered decommission flow still requires operator coordination:

1. Withdraw the site's membership from every remaining peer and verify it has
   reconciled, so the site's existing certificate no longer grants access.
2. Stop issuance/renewal and delivery for that site. Remove its Certificate or
   revoke renewal through the external PKI integration.
3. Remove the site's identity Secrets and configuration, then remove its
   managed-cluster registration.

Deleting a Certificate stops renewal but does not cryptographically revoke an
issued certificate. Cert-manager normally retains its Secret, and governance policy
removal is not a guarantee of remote object deletion. Shared CA resources
remain outside the site's lifecycle.

## Upgrade members that hold the grid ID in status

Operators before v0.3.0-rc.2 minted the grid ID into `status.gridId` only.
#474 (in v0.3.0-rc.2) removed that minting, so rc.2 operators stopped running
those status-only members. This release's operator copies a status-only ID
into an empty `spec.gridId` once, which restores them. A CEL rule keeps
`spec.gridId` fixed after that.

Upgrade in this order:

1. Upgrade the operator on every member, and wait until each member's
   GridNetwork shows the copied `spec.gridId`.
2. Create `grid-bootstrap-state` with that ID, as described in Bootstrap.
3. Upgrade this chart on the hub with `gridIdentity.enabled`.

Once a member's `spec.gridId` is set, the CEL rule refuses any write that
changes it, including one from an rc.2 hub policy that predates the guard.
A member that is still status-only has no such protection.

An rc.2 hub that already ran with `gridIdentity.enabled` may have moved
status-only members to its ID. Audit by comparing each member's IDs with the
saved one. On the hub:

```bash
kubectl -n <release-namespace> get configmap grid-bootstrap-state -o jsonpath='{.data.gridId}{"\n"}'
```

On each member:

```bash
kubectl get gridnetworks -o custom-columns=NAME:.metadata.name,SPEC:.spec.gridId,STATUS:.status.gridId
```

A member whose `spec.gridId` matches the ConfigMap while its `status.gridId`
differs was moved and has not yet reconciled. After it reconciles, status
mirrors spec and this comparison no longer shows the move, so also compare
against the grid ID recorded before the upgrade.

A member whose GridNetwork comes from the `grid-site` chart through Argo CD
must set `gridNetwork.gridId` to its current `status.gridId` in the same change
that upgrades the operator, or ignore `/spec/gridId`. See
[0.3.x CRD Field Migration](../../docs/installation/migration-0.3.x.md#grid-id-on-gitops-managed-members).

## Migrate an existing installation

Keep the same CA. Existing service-enrolled sites still renew through the
enrollment service until their identity ownership has been migrated; do not
switch that service's Helm release to external mode prematurely, because
doing so removes the service and its database resources.

For the temporary ODH bootstrap Application, keep its Application name,
release name, destination, and `grid-ca` Issuer name. Change its source to the
existing enrollment chart and select the Existing CA example above. This
updates the same Issuer in place and leaves the enrollment service running in
its original Application. Remove the obsolete standalone chart only after
this source change has synced successfully.

Validate locally with `helm unittest charts/grid-enrollment`. The disposable
Kind test at `tests/cert-manager-e2e.sh` exercises issuance, renewal, external
issuer ownership, and CA retention. Set `LEGACY_CHART` to the old bootstrap
chart path to also verify migration preserves the existing Issuer UID and CA.

`python3 charts/grid-enrollment/tests/managed_clusters_test.py` renders the chart
and executes its hub templates against API fixtures for enrollment, endpoint
changes, missing feedback, selection, identity delivery, and withdrawal. It
requires Go and PyYAML. These tests and server-side dry runs do not replace a
live managed-cluster reconciliation test before the runtime cutover.
