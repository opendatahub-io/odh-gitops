# Grid Enrollment Helm Chart

Helm chart for the grid enrollment service: the enrollment authority for a grid,
its self-provisioned Grid CA, and a Postgres store. A zero-config install stands
up a site ready to enroll.

## Prerequisites

- Kubernetes >= 1.26
- Helm >= 3.12
- An etcd encryption-at-rest provider on the cluster before holding the CA key in a Secret (see Security below)

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

The bootstrap Job's RBAC is removed once the hook finishes, whether it succeeded or
failed, so retry a failed bootstrap with `helm upgrade`, not by re-running the Job.

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

## Bring your own (overrides)

Each override takes a Secret reference, so no key material is inlined in values.

| Value | Default | Override |
|-------|---------|----------|
| `ca.provided.keySecretRef` | generate | pre-created CA Secret (tls.crt, tls.key) |
| `serving.existingSecretRef` | issued from the CA | pre-created serving Secret |
| `db.type` | `builtin` Postgres | `external` + `db.external.connectionUrlSecretRef` |
| `enrollment.authz` | `kube` (SAR, needs the sar-feature image) | `local` (standalone grid-admin token table) |
| `enrollment.gridAdminTokens.existingSecretRef` | generated (local authz) | pre-created token Secret (name:token lines) |

## Site invites

Each `invites` entry (`siteName`, `gridNetworkRef`, optional `expiresInSecs` up to 604800) has a post-install and post-upgrade Job mint a one-time site token into Secret `grid-invite-<siteName>` (key `token`). The Job skips sites whose Secret already exists, so an upgrade mints only for new sites. Invites need `enrollment.authz=kube`. Before Helm 3.19, a failed invite run leaves its hook RBAC in place until the next run. [Site Enrollment](../../docs/installation/enrollment.md#invite-a-site-on-the-hub) covers delivery and revocation.

## Limitations

The builtin Postgres serves TLS with a cert the bootstrap Job issues from the
generated CA, and the service refuses a plaintext DB. A provided CA
(`ca.method=provided`) does not run the bootstrap Job, so it issues no DB cert.
Provided-CA installs must therefore use an external DB (`db.type=external`) whose
URL sets `sslmode` (verify-full for FIPS).

Postgres reads its serving cert at pod start. Each bootstrap run compares the
builtin DB Deployment's `grid.praxis-proxy.io/db-serving-cert-sha256` pod
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
