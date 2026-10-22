# Grid Enrollment Helm Chart

Helm chart for the grid enrollment service: the enrollment authority for a grid,
its self-provisioned Grid CA, and a Postgres store. No values are required: given the
namespaces under Prerequisites, an install stands up a site ready to enroll.

## Prerequisites

- Kubernetes >= 1.26, or >= 1.30 at the chart's defaults. The CSR signer and the
  bootstrap confinement both render `admissionregistration.k8s.io/v1`
  ValidatingAdmissionPolicy, which is Stable from 1.30. On an older cluster set
  `enrollment.csrRecord.enabled=false` and `ca.bootstrap.policy.enabled=false`, which is
  why `kubeVersion` stays at 1.26: the floor is conditional on those values and
  `kubeVersion` cannot express that.
- Helm >= 3.12
- An etcd encryption-at-rest provider on the cluster before holding the CA key in a Secret (see Security below)
- `hubSite.namespace`, the grid operator's own namespace, when `hubSite.name` is set. That
  operator's own release owns it, so this chart does not create it, and it has to exist at
  install time rather than at first use: the pre-install hook renders RBAC into it, so a
  missing namespace fails the hook rather than the workload.

  ```bash
  kubectl create namespace odh-ai-grid    # named per install path; see Hub site identity
  ```

  The invite namespace is created for you, since nothing else owns it.

## Install

Batteries included. Off OpenShift no values are required:

```bash
helm install grid charts/grid-enrollment --namespace grid-enroll --create-namespace
```

The default install generates the Grid CA, the endpoint serving cert, and the
Postgres credentials through a pre-install hook, deploys Postgres, and runs the
service over TLS. Under `enrollment.authz=local` the hook also generates a
grid-admin token. The hook creates each Secret once and never rotates it, so
`helm template` and Argo CD render the same manifests on every sync. `helm install
--dry-run` and the NOTES output show the endpoint and the trust anchor.

`host` names the enrollment endpoint sites connect to. It joins the serving cert names,
is the default `route.host`, and makes the enrollment Service a LoadBalancer when no
Route renders. `invites` takes sites keyed by name, for example
`--set invites.east2.network=grid`.

## Route

`route.enabled` defaults to `auto`: the chart renders a passthrough Route only when
the cluster serves `route.openshift.io/v1`, and `true` or `false` forces it. A
rendered passthrough Route needs `route.host`, which the bootstrap adds to the
serving cert SAN:

```bash
helm install grid charts/grid-enrollment --namespace grid-enroll --create-namespace \
  --set route.host=enrollment.apps.<cluster-domain>
```

The bootstrap Job's RBAC remains after both successful and failed hooks until
the next hook run. Helm does not remove hook resources during uninstall, so the
RBAC also remains after `helm uninstall`. This keeps it available for retries
and avoids Helm 3.19 and later deleting earlier successful hooks when a later
hook fails. If you uninstall the release and want to remove the privileged
bootstrap identity, delete the `ServiceAccount`, `Role`, and `RoleBinding`
named `<release>-grid-enrollment-ca-bootstrap` in the release namespace. When
`hubSite.name` is set, delete the matching `-hub-site` `Role` and `RoleBinding`
in the hub-site namespace on every uninstall, before deleting the release
namespace: they name the ServiceAccount only by namespace and name, so
whoever creates that namespace again inherits their access. Retry a failed
bootstrap with
`helm upgrade`, not by re-running the Job.

`helm template` sees no cluster APIs, so `auto` renders no Route there. GitOps
renders for OpenShift pass `--api-versions route.openshift.io/v1` (Argo CD passes
the cluster's APIs itself). `reencrypt` terminates at the router and breaks the
site's grid-CA pin, so keep `passthrough`. `edge` is rejected: enrollment serves
TLS only.

## Topology

One install is one enrollment authority with one Grid CA. Sites are joining
members that enroll against it, each getting a unique SPIFFE identity signed by
the shared Grid CA. Peers trust each other by CA chain and SPIFFE SAN. Do not
install the chart once per site. That creates independent CAs.

## CA and key separation

The bootstrap writes three Secrets:

- `grid-ca-key` (tls.crt, tls.key): the CA signing key. Only the enrollment pod mounts it.
- `grid-ca-bundle` (ca.crt): the public trust anchor for the gateway and peers. Never the key.
- `enrollment-serving-tls` (tls.crt, tls.key): the endpoint's grid-CA-signed serving cert.

Generation is idempotent and runs only when the CA is absent. `ca.forceRegenerate`
replaces the CA in place, which invalidates every certificate it has issued.
The service records the fingerprint of the CA's public key in the database and
refuses a CA with another key unless `ca.confirmRotation` is set to the old
fingerprint. A CA certificate renewed on the same key is accepted.

## Bring your own (overrides)

Each override takes a Secret reference, so no key material is inlined in values.

| Value | Default | Override |
|-------|---------|----------|
| `ca.provided.keySecretRef` | generate | pre-created CA Secret (tls.crt, tls.key) |
| `serving.existingSecretRef` | issued from the CA | pre-created serving Secret |
| `db.type` | `builtin` Postgres | `external` + `db.external.connectionUrlSecretRef` |
| `db.builtin.pvcAnnotations` | none | annotations on the builtin DB PVC, which holds every site record; under Argo CD set `argocd.argoproj.io/sync-options: Prune=false,Delete=false` |
| `platform` | none | `aws`, `azure`, `gcp`, or `any` for all three: that cloud's load balancer keys on the enrollment Service when it is a LoadBalancer (`host` set, no Route); `enrollment.service.annotations` override them |
| `loadBalancerScope` | `internal`: the load balancer stays on the private network | `external`: internet-facing. AWS fixes the scope at creation, so changing it means recreating the Service |
| `enrollment.authz` | `kube` (SAR, needs the sar-feature image) | `local` (standalone grid-admin token table) |
| `enrollment.csrRecord.enabled` | `true` under `authz=kube`: each enrollment is recorded as a `CertificateSigningRequest`, approved and completed by the service, off the request path. The API server deletes an issued request about an hour after approval; the API server's audit log keeps the history when its policy covers these writes at `Request` level or above with a persistent backend. The service's own enrollment record is separate and always kept | `false` keeps no Kubernetes record; also the setting for Kubernetes 1.26 to 1.29, which lack the policy API |
| `enrollment.csrRecord.signerName` | `grid.praxis.fast/site` | one per enrollment service on a cluster, since the policy admits only this release's service for it |
| `enrollment.csrRecord.policy.enabled` | `true`: two `ValidatingAdmissionPolicies`, one letting only the service file under the signer name, one confining the service to that name (Kubernetes 1.30). Required while the record is on | `false` is refused; turn the record off on clusters without the v1 policy API |
| `enrollment.gridAdminTokens.existingSecretRef` | generated (local authz) | pre-created token Secret (`name:token` lines, optional `roles` key, see below) |

The installing principal must itself hold `approve` and `sign` on the signer name, or RBAC escalation prevention refuses the record roles.

## Local grid-admin roles

Under `enrollment.authz=local` the Secret's `tokens` key holds one `name:token` line per admin, where the token is everything after the first colon and may contain any character, including `:`. Roles live in an optional `roles` key of `name:role[,role]` lines, with roles from `grid-admin` and `enrollment-admin`, matching the Roles kube mode binds. A name with no roles line is `grid-admin`: mint and revoke tokens, and read enrollments. Deleting an enrollment, or minting with `allowDeletedName`, needs `enrollment-admin`. Role names are exact and lowercase. An unknown, repeated, or empty role list fails startup, as does a roles line naming an admin the token table does not. Keeping roles out of the token line means a token's meaning never depends on the token's own characters. The generated table holds one `admin:<token>` line, a grid-admin without `enrollment-admin`, as kube mode binds `enrollment-admin` to nobody by default. To delete enrollments, add a `security:<token>` line to `tokens` and a `security:enrollment-admin` line to `roles`, then restart the service.

## Site invites

Each `invites` entry (`siteName`, `gridNetworkRef`, optional `expiresInSecs` up to 604800, optional `allowDeletedName` to invite a site whose enrollment was deleted) has a post-install and post-upgrade Job mint a one-time site token into Secret `grid-invite-<siteName>` (key `token`). The Job skips sites whose Secret already exists, so an upgrade mints only for new sites. It also skips, without failing, a site that is enrolled, one whose live token it cannot store because its Secret was deleted (rerun after that token expires), and one whose enrollment was deleted. An entry with `allowDeletedName` also needs the invite ServiceAccount bound to the enrollment-admin Role. Invites need `enrollment.authz=kube`. Before Helm 3.19, a failed invite run leaves its hook RBAC in place until the next run. [Site Enrollment](../../docs/installation/enrollment.md#invite-a-site-on-the-hub) covers delivery and revocation.

## Hub site identity

The hub hosts enrollment, so it cannot enroll itself. Set `hubSite.name` and the bootstrap Job issues the hub's site identity straight from the grid CA, with the same SPIFFE name, key usage, and lifetime an enrolled site receives. It writes Secret `grid-site-identity` and the CA Secret `grid-ca` to `hubSite.namespace`. It also creates the grid's 32-byte SWIM key once, as `hubSite.swimKeySecretName` (default `grid-swim-key`), in both the release namespace, where a delivery channel such as an ACM Policy can copy it to sites, and `hubSite.namespace`. In `hubSite.namespace` the Job holds `create` on any Secret, since `create` cannot be scoped by name, `get` and `update` on the identity and CA Secrets, `delete` on the identity Secret to replace a placeholder, and `get` on the SWIM key Secret. A ValidatingAdmissionPolicy confines that unscopable `create` to the Secret names this chart renders, in the two namespaces it renders them in, and to the `Opaque` and `kubernetes.io/tls` types the bootstrap writes. The type constraint is load bearing, not belt and braces: this account also holds `delete` on the identity Secret, so a name-only rule would let it delete that name and recreate it as a `kubernetes.io/service-account-token` annotated for another ServiceAccount, which the token controller then fills with a non-expiring token for that account. Install the hub operator with `enrollment.enabled=false`. The chart does not create `hubSite.namespace`, since the hub operator's release owns it, so create it before installing this chart (`kubectl create namespace grid`); its hook RBAC fails otherwise. The enrollment service reserves the name too, refusing to mint or redeem a token for it, so no invite can issue a second identity for the hub.

The invite token Secrets live in a namespace of their own, `<release-namespace>-invites`
unless `enrollment.inviteSecrets.namespace` names another. The chart creates it, since
nothing else owns it, and the render refuses both the release namespace and
`hubSite.namespace` for it. Naming one explicitly makes it yours: the chart then creates
nothing, since a namespace you already filled is not this release's to take over. Create
it before installing in that case.

That separation is not tidiness. The service needs `get`, `create` and `delete` on Secrets
there unscoped by name, because invite names are per site, and admission can confine the
writes but never the `get`, since admission does not run on reads. Sharing the release
namespace would let the service read the Grid CA signing key; sharing `hubSite.namespace`
would let it read the hub's identity and the grid CA the bootstrap writes there.

The namespace is a regular resource annotated `helm.sh/resource-policy: keep`, not a
hook. Helm cannot disable `before-hook-creation`, which deletes a hook resource it finds
before creating it, and the Secrets here are unredeemed invite tokens: as a hook it would
lose them on a reinstall after an uninstall, and on every Argo CD sync that maps
`pre-install` to `PreSync`. Nothing in the pre-install phase writes here, so nothing needs
it to be a hook. `keep` also means it outlives an uninstall, so the tokens survive one. A
reinstall under the same release name and namespace adopts it; under a different release
name Helm refuses the install on ownership rather than deleting it. Changing
`enrollment.inviteSecrets.namespace` on an existing release needs the new namespace created
by hand; the Role apply fails if it is missing.

**Upgrading from a release that kept invites in the release namespace.** The service now
reads them from the invite namespace, so a `grid-invite-*` Secret still sitting in the
release namespace is invisible to it and that site cannot redeem its token. Minting a
replacement while the old one is live is refused, so redeem or revoke outstanding invites
before upgrading, or copy the Secrets across:

```bash
kubectl -n <release-namespace> get secret -o name \
  | grep '^secret/grid-invite-' \
  | sed 's|^secret/||' \
  | while read -r n; do
      kubectl -n <release-namespace> get secret "$n" -o json \
        | jq 'del(.metadata.namespace, .metadata.uid, .metadata.resourceVersion,
                  .metadata.creationTimestamp, .metadata.ownerReferences)' \
        | kubectl -n <release-namespace>-invites create -f -
    done
```


`hubSite.namespace` and `invitePolicy.namespace` are the grid operator's namespace on
each cluster, not this release's. A Helm install puts the operator in `grid` or
`grid-system`, whichever its own values chose. A platform install derives the namespace
from the applications namespace instead, so it is `odh-ai-grid` under OpenDataHub and
`redhat-ai-grid` under Red Hat OpenShift AI, and the operator reads the Secrets only
there. Set the value to match, since neither the chart nor the operator reconciles a
mismatch: the Secrets land where nothing reads them and the site never gets an identity.
A platform namespace (`default`, `kube-*`, `openshift-*`) is refused, because the
bootstrap's namespace-wide `create` on Secrets does not belong in one.

### Removing the admission policies

`ca.bootstrap.policy.enabled` renders the policies; it does not reconcile them. They are
pre-install hooks, because each has to admit the writes of a hook that runs after it, so
Helm neither updates nor deletes them: setting the value false stops rendering a policy
but leaves one already on the cluster in place, and `helm uninstall` leaves both behind.
The invite namespace is a pre-install hook too, so it also survives an uninstall, along
with the invite tokens in it. An orphaned policy matches nothing, since its condition pins a ServiceAccount username that
no longer resolves, but a stale one denies a renamed Secret on the next upgrade. On
a cluster without `admissionregistration.k8s.io/v1`, or when changing a Secret name with
the policies off, delete them by hand:

```
kubectl delete validatingadmissionpolicybinding \
  <release>-grid-enrollment-<namespace>-bootstrap-secrets \
  <release>-grid-enrollment-<namespace>-invite-secrets
kubectl delete validatingadmissionpolicy \
  <release>-grid-enrollment-<namespace>-bootstrap-secrets \
  <release>-grid-enrollment-<namespace>-invite-secrets
```

The invite namespace outlives an uninstall too. Deleting it destroys every invite token
still in it, so do that only once no site is waiting to redeem one:

```bash
kubectl delete namespace <namespace>-invites
```

The identity is created once and rotates like an enrolled one: bootstrap signs a seed with the CA key into the `hubSite.seedSecretName` Secret, the service registers the hub's key from it, and the hub's operator rotates through the enrollment service. Under `pin` peer trust the hub's operator does not rotate, so re-issue the identity and update the peers' pins before it expires. A hub frozen after a rotation fork recovers only by a re-issue: delete its identity Secret and upgrade. Deleting the seed Secret alone re-signs the same key and leaves the freeze in place. The Job keeps an expired identity but fails on one issued to another name or by another CA. To re-issue it, delete the Secret before the next upgrade, or set `ca.forceRegenerate`, which re-issues every certificate. Do not also invite `hubSite.name`: the chart refuses it, because an invite would mint a second identity for the same name. A provided CA is refused too, since the Job has no signing key.

To stop all rotation from the hub, set `enrollment.rotation.enabled=false`. The service refuses every rotation with 503 `rotation_disabled`, and every site keeps its current identity until it expires. [Turn rotation off](../../docs/installation/enrollment.md#turn-rotation-off) has the details.

## Limitations

The builtin Postgres serves TLS with a cert the bootstrap Job issues from the
generated CA, and the service refuses a plaintext DB. A provided CA
(`ca.method=provided`) does not run the bootstrap Job, so it issues no DB cert.
Provided-CA installs must therefore use an external DB (`db.type=external`) whose
URL sets `sslmode=verify-full`.

Postgres reads its serving cert at pod start. Each bootstrap run compares the
builtin DB Deployment's `grid.praxis.fast/db-serving-cert-sha256` pod
annotation with the cert in its Secret and rolls the Deployment when they
differ, for example after a re-issue or a CA regeneration. A sync that replaces
the Deployment (Argo CD `Replace=true`) drops the annotation, so the next
bootstrap run restarts Postgres once more, harmlessly.

The bootstrap runs as one Helm hook Job, replaced on each upgrade or Argo CD
sync. It adopts the DB and grid-admin token Secrets an earlier chart version
rendered. `helm
uninstall` does not delete it, so a finished Job stays for
`ca.bootstrap.ttlSecondsAfterFinished`, a day by default, for its logs.

After a CA change, the enrollment service's first DB reconnect can fail
verify-full until the grid-ca-bundle mount refreshes, typically within 1-2
minutes. The connection pool retries on its own.

## Security

This Helm-Secret path is the dev and interim posture. Key separation, secretRef
only overrides, and generate-if-absent idempotence hold even here. A Kubernetes
Secret is base64, not encrypted, unless the cluster runs an etcd encryption
provider. Enable it before holding the CA key this way. For GA the CA signing key
belongs in a non-exportable KMS or HSM key rather than a Secret.

## Dependency

The bootstrap Job runs `enrollment bootstrap` from the enrollment image, so a
runtime install depends on that subcommand (the image's `bootstrap` feature) and,
for the default `authz=kube`, the `sar` feature.
