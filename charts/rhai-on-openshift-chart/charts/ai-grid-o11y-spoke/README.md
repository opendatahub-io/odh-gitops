# ai-grid-o11y-spoke

**This one installs on a spoke.** Its sibling [ai-grid-o11y-hub](../ai-grid-o11y-hub) installs
on the hub, including the ACM policy that configures spokes remotely.

It has two independent halves, both about the one collector in `collector.namespace`, and
each with its own toggle:

| | |
|---|---|
| **metrics** | a `ScrapeConfig` and a `NetworkPolicy` that let ACM observability's metrics-collector agents federate RHOAI metrics off this cluster. `metrics.enabled`, on by default |
| **usage logs** | the monitoring namespace and the hub credential the usage-log collector mounts, in place *before* that collector starts. `credential.enabled`, off by default |

They share nothing but the namespace, and either can run alone. A spoke in an ACM fleet that
only federates metrics leaves `credential.enabled` off and is never asked for a hub token. A
spoke outside a fleet, installing this chart only to receive the usage-log credential, sets
`metrics.enabled: false` — the `ScrapeConfig` goes to
`open-cluster-management-observability`, which does not exist there, and needs the rhobs CRD.

Disabled by default. `ai-grid-o11y-spoke.enabled=true` turns it on.

## Why the usage-log half exists

A spoke's forwarding configuration is not here. It is
`services.monitoring.dsci.usageLogs` on the parent chart, which the platform operator hands
to `odh-observability`. A subchart cannot contribute to the `DSCInitialization`, which the
parent owns and renders by ranging over `services.monitoring.dsci`.

What a subchart *can* do is fix an ordering problem that has no other fix.

The monitoring namespace does not exist before the parent chart runs: nothing in the chart
creates it, and the operator creates it while reconciling the `DSCInitialization`. So there
is nowhere to put the hub credential beforehand. If `usageLogs.credentialSecret` names a
Secret that is not there yet, the collector's pods sit in `ContainerCreating` on
`FailedMount` — and because the local and the remote pipeline share one collector
deployment, the spoke then has **no usage logging at all**, not merely no forwarding.
Turning on forwarding breaks the thing that already worked.

Helm's install ordering places `Namespace` and `Secret` ahead of kinds it does not
recognise, such as `DSCInitialization`. Rendering both here therefore closes that window in
a single `helm install`, with no second pass and no manual step between.

```
 1. Namespace          redhat-ods-monitoring
 2. Secret             hub-usage-logs-auth
 3. DSCInitialization  default-dsci          <- operator now deploys the collector
```

## What it creates

| Object | Name | Notes |
|---|---|---|
| `ScrapeConfig` | `rhai-metrics` | metrics only, in `open-cluster-management-observability` |
| `NetworkPolicy` | `allow-acm-rhai-metrics` | metrics only, in `collector.namespace` |
| `Namespace` | `redhat-ods-monitoring` | usage logs only; `collector.createNamespace`, carries `helm.sh/resource-policy: keep` |
| `Secret` | `hub-usage-logs-auth` | usage logs only; key `token`, the hub writer token |

The namespace keeps `helm.sh/resource-policy: keep` because the operator puts everything it
deploys there. A `helm uninstall` that deleted it would take the collector, and everything
else RHOAI's monitoring stack runs there, with it.

**`collector.createNamespace` defaults to `false`**, which is right for most clusters this chart
is used on: its job is onboarding a spoke that already has a monitoring namespace. The operator
created that namespace long ago, Helm will not adopt a namespace it does not own, and with
`true` the upgrade fails outright with `invalid ownership metadata` *before* the credential this
chart exists to deliver is delivered. Measured on a live spoke: with `true`, enabling
`credential.enabled` failed the upgrade; with `false`, the same upgrade succeeded and placed the
Secret two seconds ahead of the collector's new pods.

**Set it to `true` only when this chart runs before the operator has reconciled the
`DSCInitialization`** — a brand-new spoke, where the monitoring namespace does not exist yet and
there is otherwise nowhere to put the credential. `docs/examples/values-ai-grid-o11y-spoke.yaml`
is that case and opts back in. Note that `credential.enabled` alone does **not** create the
namespace; the template requires both it and `collector.createNamespace`.

It must also be false on OSD and ROSA where the namespace is managed elsewhere: GitOps writes
to Red Hat managed namespaces are rejected, the same constraint `RHOAIENG-99507` addressed for
the operator namespace.

## The token

Minted on the hub, against the writer identity that chart creates:

```bash
TOKEN_FILE=$(mktemp)
oc create token usage-logs-writer -n ai-grid-o11y --duration=8760h > "$TOKEN_FILE"
```

`mktemp` creates a private file. The token is a required value with no default,
and it must not be committed:

```bash
helm upgrade --install rhoai ./charts/rhai-on-openshift-chart \
  -f docs/examples/values-ai-grid-o11y-spoke.yaml \
  --set-file ai-grid-o11y-spoke.credential.token="$TOKEN_FILE" \
  -n rhoai-gitops --create-namespace
rm -- "$TOKEN_FILE"
```

**`--set-file` keeps the token out of git, not out of the cluster.** Helm records every supplied
value in the release's own Secret (`sh.helm.release.v1.<release>.v<N>` in the release namespace),
so the token is readable there by anyone who can read Secrets in it — and by `helm get values`.
It is also retained in older revisions until they age out of history. Treat read access to the
release namespace as equivalent to holding the fleet writer token, and prefer the ACM policy
path (`ai-grid-o11y-hub.spokePolicy`) where the token never leaves the hub in clear.

**There is deliberately no `existingSecret` option.** It would look equivalent and quietly
give up the ordering guarantee above, since a Secret created outside the release may not
exist when the collector starts — which is the exact failure this chart exists to prevent.
Under GitOps, template the token from whatever secret manager is in use.

The Secret holds a **bare token** under `token`, not a header value: the collector reads it
through a `bearertokenauth` extension that prepends `Bearer` itself. Writing `Bearer <token>`
makes every write fail, and the hub answers `302` to a login path rather than `401`, so it
surfaces only as `otelcol_exporter_send_failed_log_records`.

Nothing rotates it and no object reports its age. The collector re-reads the mounted file, so
replacing this Secret reaches a running collector without a restart, but the schedule is an
operational commitment this chart cannot make.

## The forwarding configuration

Set on the parent chart, with `credentialSecret` matching `credential.secretName` here:

```yaml
services:
  monitoring:
    dsci:
      managementState: Managed
      usageLogs:
        # No storage: a spoke forwards to the hub and keeps no local store, so no
        # LokiStack is deployed and no object storage is needed.
        credentialSecret: hub-usage-logs-auth
        attributes:
          cluster_name: <spoke-name>
          cluster_id: <spoke-cluster-id>
        exporters:
          otlphttp/hub:
            endpoint: https://<hub-route>/api/logs/v1/infrastructure/otlp
```

Replace the identity placeholders with this spoke's name and cluster ID; read the ID with
`oc get clusterversion version -o jsonpath='{.spec.clusterID}'`.

Nothing checks that the two Secret names agree, because a subchart cannot see the parent's values.
A mismatch leaves the collector blocked on a Secret that will never appear.

Two things the endpoint gets wrong silently, and neither is checkable here:

- **A trailing `/v1/logs`.** The `otlphttp` exporter appends it, so a doubled suffix `404`s
  every record. The hub chart validates the endpoint it distributes; this path does not go
  through it.
- **The wrong tenant.** A record written to `application` instead of `infrastructure` is
  accepted with `204` and then matches no query, for any user.

## In an ACM fleet, you probably don't need this

A spoke that is an ACM managed cluster gets its credential and its `usageLogs` configuration
from the hub's `spokePolicy` — `fromSecret` delivers the token as encrypted ciphertext and
the policy patches the DSCI. The spoke then needs nothing under `usageLogs` of its own, so
this chart has nothing left to contribute there.

This chart is for a spoke outside ACM, a spoke being configured directly, or a first spoke
brought up before the policy exists.

## Values

See [api-docs.md](api-docs.md), generated by `make helm-docs`.
