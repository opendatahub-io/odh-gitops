# ai-grid-o11y-spoke

**This chart installs on a spoke.** Its sibling [ai-grid-o11y-hub](../ai-grid-o11y-hub)
installs on the hub, including the ACM policy that can configure usage-log forwarding.

The spoke chart provides three capabilities with separate switches:

| Capability | What it renders |
|---|---|
| Metrics collection | NetworkPolicy and ScrapeConfig by default (`metrics.enabled`); disable the ScrapeConfig with `collector.scrapeConfig.enabled: false` |
| Usage-log credential | The monitoring namespace and hub credential mounted by the collector; `credential.enabled`, off by default |
| Tenant metrics queries | A Perses datasource, Gateway route and policy, label proxy, and mTLS relay to hub Thanos; `metricsQuery.enabled`, off by default |

Metrics collection and usage-log delivery share `collector.namespace`; tenant query resources
run in the configured route and tenant-admin namespaces. The query path does not require a
`ScrapeConfig`. An ACM-managed spoke can receive usage-log configuration from the hub policy
without setting `credential.enabled` here. A spoke outside ACM that only needs direct
usage-log delivery should set `metrics.enabled: false`.

The parent chart disables this subchart by default. Set `ai-grid-o11y-spoke.enabled: true`
to include it. When installing the spoke chart alone, the metrics collection and credential
templates use their feature switches; query resources also require `enabled: true`.

`collector.scrapeConfig.enabled` defaults to true so an upgrade retains the chart-managed
`ScrapeConfig`. It requires the `open-cluster-management-observability` namespace and the
rhobs CRD. Set it false for query-only installs without that namespace, or after migrating
collection to ACM management. Configure and verify the ACM replacement first: ACM MCO
manages the ScrapeConfig on the hub and distributes collection settings to selected spokes
through an add-on Placement. Disabling this value removes the chart-managed ScrapeConfig.

## Why the usage-log credential is created here

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
| `ScrapeConfig` | `rhai-metrics` | metrics collection only when `metrics.enabled` and `collector.scrapeConfig.enabled`; in `open-cluster-management-observability` |
| `NetworkPolicy` | `allow-acm-rhai-metrics` | metrics collection when `metrics.enabled`; in `collector.namespace` |
| `Namespace` | `redhat-ods-monitoring` | usage logs only; `collector.createNamespace`, carries `helm.sh/resource-policy: keep` |
| `Secret` | `hub-usage-logs-auth` | usage logs only; key `token`, the hub writer token |
| `Namespace` | `ai-grid-o11y-tenant-admin` (default) | tenant queries only when `tenantAdminNamespace.create` |
| `PersesDatasource` | `grid-tenant-hub-metrics` | tenant queries, in the tenant-admin namespace |
| `HTTPRoute` + `AuthPolicy` | `grid-tenant-metrics` | tenant queries, in the route namespace |
| `ConfigMap`, `Deployment`, `Service`, `NetworkPolicy` | query proxy and relay | tenant queries, in the route namespace |

The monitoring namespace keeps `helm.sh/resource-policy: keep` because the operator puts
everything it deploys there. A `helm uninstall` that deleted it would take the collector,
and everything else RHOAI's monitoring stack runs there, with it.

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

## In an ACM fleet, you probably do not need direct credential delivery

A spoke that is an ACM managed cluster gets its credential and its `usageLogs` configuration
from the hub's `spokePolicy` — `fromSecret` delivers the token as encrypted ciphertext and
the policy patches the DSCI. The spoke then needs nothing under `usageLogs` of its own, so
this chart has nothing left to contribute there.

Direct credential delivery is for a spoke outside ACM, a spoke being configured directly,
or a first spoke brought up before the policy exists.

## Tenant metrics queries

For a standalone install, set both `enabled: true` and `metricsQuery.enabled: true`.
Through the parent chart, set `ai-grid-o11y-spoke.enabled: true` and
`ai-grid-o11y-spoke.metricsQuery.enabled: true`. Query access does not require spoke
metrics collection. For a query-only standalone release, use these switches alongside
the required hostnames, authentication, datasource selector, and certificate Secret names:

```yaml
enabled: true
metrics:
  enabled: false
collector:
  scrapeConfig:
    enabled: false
metricsQuery:
  enabled: true
```

The query path consists of a project-scoped `PersesDatasource` in
`tenantAdminNamespace.name` (default `ai-grid-o11y-tenant-admin`), a GET-only
`/metrics` `HTTPRoute` and `AuthPolicy`, and one query
Service/Deployment/NetworkPolicy. The query pod
runs `prom-label-proxy` in front of a loopback NGINX mTLS relay. The route
and query Service share a namespace, so no `ReferenceGrant` is needed. The
proxy adds a matcher for `metricsQuery.proxy.label` (default `organization_id`)
before NGINX sends the query to the hub. The relay verifies the hub TLS
certificate and presents a client certificate to the hub's protected Route.
The hub mTLS ingress forwards
approved read endpoints to ACM Thanos Query. The chart derives the
datasource URL as `https://<metricsRoute.hostname>/metrics`.

Create these Secrets in the route namespace before enabling queries:

- `metricsQuery.clientTLSSecretName`: `tls.crt` and `tls.key` for a client
  certificate signed by the CA trusted at the hub;
- `metricsQuery.serverCASecretName`: `ca.crt` for the hub Route server.

Set `metricsQuery.hubHostname` to the exact hub Route host and
`metricsRoute.hostname` to the spoke Gateway host. The relay connects to the
hub with HTTPS and verifies that hostname. The default NetworkPolicy permits
only pods of `maas-default-gateway` in `openshift-ingress` to reach the proxy.
Adjust the namespace and pod selectors if the Gateway runs elsewhere.

Set `metricsQuery.proxy.label` to the label stored in hub Thanos. The proxy and
relay listen on different ports in the same pod.
`metricsQuery.proxy.listenPort` is exposed through the query Service;
`metricsQuery.listenPort` is loopback-only. The pinned proxy image does not
configure an upstream mTLS client certificate,
so the NGINX relay remains necessary.

The relay caches the hub Route DNS answer for 30 seconds and re-resolves it
on later requests. `metricsQuery.dnsResolver` defaults to
`dns-default.openshift-dns.svc`; override it if the spoke uses a different
resolver. The relay drops all caller headers and sets the hub `Host` header.
The tenant scope is enforced by `prom-label-proxy` before the request reaches
the relay; browser session cookies and `X-Scope-OrgID` do not cross the
spoke-to-hub boundary. The hub trusts the client certificate, so a holder of
that certificate can query the permitted Thanos read endpoints without the
spoke filter. Keep the client key available only to the relay.

The proxy permits only the data-free `/-/healthy` path without a tenant
matcher. Label discovery uses filtered `/api/v1/labels` and
`/api/v1/label/<name>/values` requests; the Thanos backend must support
`match[]` on those APIs. `/api/v1/metadata` remains unavailable because an
unfiltered metadata response could disclose other tenants' metric names and
descriptions.

When the MaaS Gateway listener selects namespaces by
`maas.opendatahub.io/gateway-access=true`, the route namespace needs that
label. With `tenantAdminNamespace.create: true`, this chart adds it to the
tenant-admin namespace. When another component owns the namespace, configure
the label there. If `metricsRoute.namespace` points elsewhere, that namespace
must be admitted by the Gateway and contain the chart's query resources.

The route's AuthPolicy validates the shared OIDC identity and requires the
organization-qualified `ai-grid-dashboard-viewer` group. Supply the live
authentication rule, issuer, audience, and a CEL `scopeExpression` that
extracts the selected organization's QGUID from verified `auth.identity`.
The chart builds the viewer-group check from that expression and the approved
OIDC `<organization-id>/<group>` format. Optional `authorization` rules can
add restrictions; they cannot remove the viewer check. The policy checks the
verified issuer and audience, rejects caller-supplied `X-Scope-OrgID`, and
injects the trusted value. Neither `admins` alone nor a static tenant ID
grants viewer access. The GET-only check appears in both the HTTPRoute and
AuthPolicy.

The Perses project is a separate authorization boundary. The running Perses
instance must grant only viewer users access to the project datasource;
Kubernetes RoleBindings do not authorize OIDC users inside Perses. Integrate
Perses authentication and project access, then verify viewer-only access
separately from datasource reconciliation. Serve Perses and `/metrics` from
the same browser origin, or configure and verify browser CORS and credentials.
The GET-only `HTTPRoute` does not match browser `OPTIONS` preflights. A
cross-origin `directUrl` request with an `Authorization` header needs separate
preflight handling before the browser will send its GET request. A successful
bearer-token GET proves the API path, not browser datasource access.

Use the shared OIDC issuer and organization claim in `metricsAuthPolicy` so the
Gateway derives the tenant header from verified identity.

## Values

See [api-docs.md](api-docs.md), generated by `make helm-docs`.
