# Praxis Gateway Helm Chart

Deploys the [Praxis](https://github.com/praxis-proxy/praxis) proxy as a
Kubernetes Deployment and Service. Give it a Praxis configuration in the
values, point it at a ConfigMap you manage, or start from the built-in
configuration. It needs no operator, CRDs, or controllers, so it works on its
own as a gateway, a reverse proxy, or a place to try Praxis out.

The chart also carries optional settings for specific setups, such as an edge
gateway or a gateway in an AI Grid Network (AGN). See
[Optional uses](#optional-uses).

## Prerequisites

- Kubernetes >= 1.26
- Helm >= 3.12

## Quick start

Install from a local checkout:

```bash
helm install praxis-gateway charts/praxis-gateway \
  --namespace praxis --create-namespace
```

The built-in configuration answers `GET /` with a small JSON status and
everything else with 404. Send a request through the gateway:

```bash
kubectl -n praxis rollout status deployment/praxis-gateway
kubectl -n praxis port-forward service/praxis-gateway 8080:8080 &
curl http://127.0.0.1:8080/
# {"status": "ok", "server": "praxis"}
```

`helm test praxis-gateway -n praxis` runs the chart's connectivity check.

## Configuring Praxis

The chart mounts one Praxis configuration at `/etc/praxis/praxis.yaml`. The
first source that is set wins:

1. `gatewayConfig.render: true` renders an AGN routing configuration from
   values (see [AI Grid Network](#ai-grid-network-agn)). It also turns on by
   itself when there is no existing ConfigMap and the values set
   `gatewayConfig.backends`, `gatewayConfig.role: provider`, or `gridServing`.
   Setting `gatewayConfig.localSite` or `gatewayConfig.model` without any of
   those fails the install instead of quietly serving `config.inline`.
2. `config.existingConfigMap` mounts a ConfigMap you create and manage.
3. `config.inline` holds the configuration in the values. The chart stores it
   in its own ConfigMap. This is the default.

See the [Praxis configuration reference][praxis-config] and the
[example configurations][praxis-examples] for what a configuration can do.

[praxis-config]: https://github.com/praxis-proxy/praxis/blob/main/docs/operating/configuration.md
[praxis-examples]: https://github.com/praxis-proxy/praxis/tree/main/examples/configs

### Proxy to a Service

This configuration forwards every request to a Service in another namespace
and adds a response header:

```yaml
# praxis.yaml
listeners:
  - name: default
    address: "0.0.0.0:8080"
    filter_chains: [main]
filter_chains:
  - name: main
    filters:
      - filter: router
        routes:
          - path_prefix: "/"
            cluster: backend
      - filter: headers
        response_set:
          - name: X-Served-By
            value: praxis
      - filter: load_balancer
        clusters:
          - name: backend
            endpoints: ["my-app.my-namespace.svc:8080"]
insecure_options:
  # Service names resolve to private cluster addresses. See the note below.
  allow_private_upstreams: true
```

```bash
helm upgrade --install praxis-gateway charts/praxis-gateway \
  --namespace praxis --create-namespace \
  --set-file config.inline=praxis.yaml
```

A few things to keep in mind:

- Bind the listener to `0.0.0.0` on `port.containerPort` (8080 by default) so
  the Service and probes can reach it. Keep `admin` on loopback and reach it
  with `kubectl port-forward`.
- Praxis refuses upstream hostnames that resolve to private addresses, as a
  guard against server-side request forgery. Every in-cluster Service name
  resolves to one, so proxying to a Service by name needs
  `insecure_options.allow_private_upstreams: true`. A literal ClusterIP
  endpoint such as `10.96.12.34:8080` passes without it, but changes if the
  Service is recreated.
- Praxis also refuses endpoint names ending in `.local` at startup, which
  rules out the full `my-app.my-namespace.svc.cluster.local` form. Write
  Service names as `my-app.my-namespace.svc`; the pod's DNS search path
  completes them.
- Changing `config.inline` and running `helm upgrade` rolls the pods onto the
  new configuration without refusing requests (see `shutdownDelaySeconds`).

### Bring your own ConfigMap

```bash
kubectl -n praxis create configmap praxis-config --from-file=praxis.yaml
helm upgrade --install praxis-gateway charts/praxis-gateway \
  --namespace praxis --set config.existingConfigMap=praxis-config
```

Set `config.key` when the configuration lives under another key. The chart
does not manage this ConfigMap, so editing it does not restart the pods. The
default Praxis AI image watches its configuration file and reloads routes and
clusters once the kubelet refreshes the mounted ConfigMap, which took about a
minute in testing. Listener changes still need a restart. To apply an edit
right away, run `kubectl -n praxis rollout restart deployment/praxis-gateway`.

### Exposing the gateway

The chart creates a ClusterIP Service by default. Set `service.type` to
`LoadBalancer` or `NodePort`, or put an Ingress, Gateway API route, or
OpenShift Route in front of the ClusterIP Service. To terminate TLS in Praxis
itself, enable `gatewayConfig.listenerTls` with a TLS Secret. The certificate
mounts at `/etc/praxis/listener-tls`, and your listener references it:

```yaml
listeners:
  - name: default
    address: "0.0.0.0:8080"
    tls:
      certificates:
        - cert_path: /etc/praxis/listener-tls/tls.crt
          key_path: /etc/praxis/listener-tls/tls.key
    filter_chains: [main]
```

On OpenShift, `route` renders a Route to the Service; it needs TLS at the
gateway and `route.host`. `networkPolicy` limits which pods may reach the
listener where the CNI enforces NetworkPolicy.

## Image

The default image is the official Praxis AI release, `ghcr.io/praxis-proxy/ai`
at the chart's `appVersion` (0.4.0). Praxis AI is a Praxis build with the AI
filters included, and it runs any Praxis configuration. Praxis AI 0.4.0 is
built on Praxis 0.7.0; these are separate release versions.

`image.digest` defaults to empty so an `image.tag` override stays effective.
For immutable deployments, set `image.digest` explicitly to
`sha256:0f619d4a0b533093f94a76921cfbba0ecdec51557dffee1615a29721ee1fc878`.

Other Praxis builds work as long as they accept `--config <path>`, which the
chart passes through `args`. The core Praxis image's entrypoint already names
its own config path, so replace the entrypoint with `command`:

```bash
helm upgrade --install praxis-gateway charts/praxis-gateway \
  --namespace praxis --create-namespace \
  --set image.repository=ghcr.io/praxis-proxy/praxis \
  --set image.tag=0.7.1 \
  --set 'command={praxis}'
```

The chart uses [Semantic Versioning](https://semver.org/). Its `version`
identifies the chart package, while `appVersion` identifies the default
Praxis AI image; these values may advance independently.

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `replicaCount` | int | `1` | Gateway replicas. |
| `image.repository` | string | `ghcr.io/praxis-proxy/ai` | Image repository. |
| `image.tag` | string | `0.4.0` | Image tag (ignored when `image.digest` is set). |
| `image.digest` | string | `""` | Immutable digest (sha256:…). When set, tag is ignored. |
| `image.flavor` | string | `ai` | `ai` or `grid-gateway`, the grid build that `gatewayConfig.role: provider` and `gridServing` need. A repository ending in `/grid-gateway` sets it. |
| `image.pullPolicy` | string | `IfNotPresent` | Image pull policy. |
| `imagePullSecrets` | list | `[]` | Pull secrets for private registries. |
| `nameOverride` | string | `""` | Override chart name. |
| `fullnameOverride` | string | `""` | Override fully qualified app name. A grid gateway, a provider or a consumer with site backends, takes its release name. |
| `commonLabels` | object | `{}` | Labels added to all resources. |
| `podLabels` | object | `{}` | Additional pod labels. Selector labels cannot be overridden. |
| `podAnnotations` | object | `{}` | Pod annotations. |
| `podSecurityContext` | object | `{}` | Extra pod securityContext (`runAsUser`, `runAsGroup`, `fsGroup`, `supplementalGroups`). |
| `imageUser.enabled` | string or bool | `auto` | Set `imageUser.uid` and `imageUser.gid` as the Praxis container's `runAsUser` and `runAsGroup` when `podSecurityContext` sets no `runAsUser`. A `podSecurityContext.runAsGroup` replaces `imageUser.gid`. `auto` applies them only to the official `praxis-proxy` `ai`, `praxis`, and `grid-gateway` images or mirrors that keep that path, not their `-fips` tags, which run as 1001:1001, and not on OpenShift (`security.openshift.io/v1`), where the SCC assigns IDs. Other images keep the user they declare. `true` forces them for any image, such as one built `FROM` the official images that keeps the named user `praxis`. |
| `imageUser.uid` | int | `100` | Numeric user of the official Praxis images, which declare the named user `praxis`. |
| `imageUser.gid` | int | `101` | Numeric group of the official Praxis images. |
| `command` | list | `[]` | Container command, replacing the image entrypoint. Empty keeps the entrypoint. |
| `args` | list | `["--config", "/etc/praxis/praxis.yaml"]` | Container arguments. |
| `config.existingConfigMap` | string | `""` | Name of an existing ConfigMap with the Praxis config. Takes precedence over `config.inline`. Editing it does not restart the pods. |
| `config.key` | string | `praxis.yaml` | Key in the ConfigMap. |
| `config.inline` | string | answers `GET /` with a JSON status, else 404 | Praxis config stored in a chart-managed ConfigMap when neither `config.existingConfigMap` nor `gatewayConfig.render` applies. Changing it rolls the pods. |
| `gatewayConfig.render` | bool | `false` | Render the Praxis config from these values instead of a BYO ConfigMap. Also on when `config.existingConfigMap` is empty and the values configure grid routing (`gatewayConfig.backends`, `role: provider`, or `gridServing`). Never emits `insecure_options`. See [AI Grid Network](#ai-grid-network-agn). |
| `gatewayConfig.model` | string | **required** for a consumer without `gridServing` | Model advertised on the routing candidates. |
| `gatewayConfig.backends` | map | **required** when rendered | Backends keyed by site, each with `endpoint` and optional `healthCheck` and `transport`. A consumer's key is the site it reaches over mutual TLS. A provider's `local` key is its one plaintext backend. The older list of `cluster`, `endpoints` entries still renders. |
| `gatewayConfig.backends[].site` | string | `localSite` | Grid site the backend serves. A consumer's remote `mutual_tls` backend must name it, and it must differ from `localSite`. Its `transport.sni` defaults to `<site>.grid.internal`. |
| `gatewayConfig.backends[].transport` | object | `mutual_tls` with `tls.enabled`, else `plaintext` | `mode`: `mutual_tls` presents the grid identity, `tls` verifies the server cert with no client cert, `plaintext` is cleartext. `sni` names the peer cert (required for `mutual_tls` and for `tls` to an IP endpoint). `ca` (`configMap` or `secret`, `key`) is the CA for a `tls` backend. A `tls` backend trusts, first match wins: `transport.ca`, then `upstreamCA`, then the process store, which is the `auth.validateCA` bundle when that is set. |
| `gatewayConfig.backends[].connectTimeoutMs` | int | praxis default | Connect timeout, at most `totalConnectTimeoutMs` when you set both. |
| `gatewayConfig.backends[].trustPrivate` | bool | `false` | Let the backend's hostname endpoints resolve to private addresses. Needs a praxis build with `trusted_private_endpoints`, which 0.7.x lacks. Over plaintext it also needs `allowPlaintextTrust`. |
| `gatewayConfig.role` | string | `consumer` | `provider` serves grid peers on the grid identity and forwards to one local backend. |
| `gatewayConfig.peerTrust.mode` | string | `pin` | Provider peer allowlist. The grid-site `gridNetwork.peerTrust.mode` is the source of truth, and this must match it. `pin` lists leaf certificate digests in `certDigests`. `spiffe` lists SPIFFE IDs in `spiffeIds` and needs X.509-SVID leaves. |
| `gatewayConfig.peerTrust.digest` | string | `""` | Pin mode: lowercase hex SHA-256 of the allowed peer's DER leaf. `nextDigest` adds the next one during a rotation. |
| `gatewayConfig.peerTrust.certDigests` | list | `[]` | Pin mode: more allowed digests. |
| `gatewayConfig.peerTrust.spiffeId` | string | `""` | SPIFFE mode: an allowed SPIFFE ID. `spiffeIds` takes more. The render needs one unless `allowAnyGridSite`. |
| `gatewayConfig.peerTrust.allowAnyGridSite` | bool | `false` | SPIFFE mode with no IDs: accept any enrolled site. |
| `gatewayConfig.provider.allowedPaths` | list | chat, completions, models, embeddings | Exact paths a provider forwards, GET and POST only. Other paths get a 404, other methods a 405. |
| `gatewayConfig.localSite` | string | **required** when rendered | This gateway's site name. A consumer scores locality with it, and a provider returns it in `X-Grid-Provider-Site`. |
| `gatewayConfig.auth.mode` | string | **required** when rendered | `api-key` validates the caller's key and needs an image that registers `identity/api-key` (praxis-policy 0.4 or later); the render refuses it on the default `ai:0.4.0` image (by effective reference; a digest pin of that same image is not detected). `none` renders no policy filter, for use only behind an authenticating front. |
| `gatewayConfig.auth.allowUnauthenticatedExposure` | bool | `false` | With `none`, allow a LoadBalancer or NodePort Service. Without it the render fails. The guard sees only this chart's Service, not `oc expose`, another Service selecting the pod labels, an HTTPRoute, or a hand-made Service with `service.enabled=false`. Use `networkPolicy` for those. |
| `gatewayConfig.auth.stripAuthorization` | bool | `true` | Remove the caller's `Authorization` before routing, in either mode. Forwarded grid hops authenticate by mTLS identity. `false` forwards the caller's key or bearer to every backend and cross-site peer, so use it only when the backend validates that same credential. |
| `gatewayConfig.auth.validateUrl` | string | **required** for `api-key` | https validate endpoint. |
| `gatewayConfig.auth.allowPrivateEndpoint` | bool | `false` | Sets `allow_private_idp`, which is engine-wide: every policy callout in this gateway, not only `validateUrl`, may then reach private, loopback, link-local, and cloud metadata addresses. Turn it on only when every policy in the gateway is yours. |
| `gatewayConfig.auth.validateCA` | object | empty | CA for the validate call (`configMap` or `secret`, `key`). Set as `SSL_CERT_FILE`, which replaces the platform trust store for the validate call and https backends without a per-backend CA or `upstreamCA`. mutual_tls backends and `upstreamCA` are unaffected. See the recipe below. |
| `networkPolicy.enabled` | bool | `false` | Render a NetworkPolicy that limits which pods can reach the listener port, where the CNI enforces NetworkPolicy. It is not authentication. Node and host-network traffic handling is CNI-specific (OVN-Kubernetes: the `policy-group.network.openshift.io/host-network` label), and a LoadBalancer with `externalTrafficPolicy: Cluster` can SNAT clients to node IPs. |
| `networkPolicy.from` | list | `[]` | NetworkPolicyPeer entries allowed in. Required when enabled. With `auth.mode: none`, list only the authenticating front. `{podSelector: {}}` admits every pod in this namespace. An empty `namespaceSelector` and an `ipBlock` of `0.0.0.0/0` or `::/0` admit everyone and fail the render. An all-address `ipBlock` with `except` entries is allowed. The check reads selector emptiness and the cidr only, so `matchExpressions` that happen to select every pod pass. A provider gateway behind a LoadBalancer that SNATs clients to node IPs needs `ipBlock` peers for those node addresses. |
| `gatewayConfig.upstreamCA.secretName` | string | `""` | CA bundle for backend TLS without a per-cluster CA (`upstream_ca_file`). |
| `gatewayConfig.listenerTls.enabled` | bool | `false` | Terminate TLS at the listener from `existingSecret`, in render or BYO mode. Names the port `https`. The cert mounts at `listenerTls.mountPath` (`/etc/praxis/listener-tls`), so a BYO config moving off `tls.enabled` must point its listener `cert_path`/`key_path` there. On OpenShift, annotate the Service with `service.beta.openshift.io/serving-cert-secret-name`. |
| `port.containerPort` | int | `8080` | Container port. |
| `port.name` | string | `""` | Port name. Empty: `https` with `gatewayConfig.listenerTls.enabled`, else `http`. |
| `port.protocol` | string | `TCP` | Port protocol. |
| `service.enabled` | bool | `true` | Create a Service. |
| `service.type` | string | `""` | Service type. Empty: `LoadBalancer` for a provider, else `ClusterIP`. |
| `service.port` | int | `8080` | Service port. |
| `service.annotations` | object | `{}` | Service annotations. |
| `service.loadBalancerIP` | string | `""` | Static IP for LoadBalancer. |
| `route.enabled` | bool | `false` | Render an OpenShift Route to the Service. Needs TLS at the gateway and `route.host`. |
| `route.tls.termination` | string | `passthrough` | `passthrough`, or `reencrypt` with `route.tls.destinationCACertificate`. A provider allows only `passthrough`. |
| `overlay.enabled` | bool | `false` | Mount an AGN routing overlay ConfigMap. |
| `overlay.existingConfigMap` | string | `""` | Name of the overlay ConfigMap. |
| `overlay.mountPath` | string | `/etc/praxis/routing` | Mount path for overlay files. |
| `overlay.items` | list | routing-config.json, routing-overlay.json | Items to project. |
| `overlay.sidecar.enabled` | bool | `false` | Deliver validated overlays through an API-watch sidecar instead of kubelet ConfigMap projection. |
| `overlay.sidecar.image.repository` | string | `grid-overlay-sync` | Overlay-sync image repository. Use a published or locally built image appropriate to the deployment. |
| `overlay.sidecar.image.tag` | string | `v0.1.4` | Overlay-sync image tag. Use an immutable published tag for reproducible deployments. |
| `overlay.sidecar.image.pullPolicy` | string | `IfNotPresent` | Overlay-sync image pull policy. |
| `overlay.sidecar.dataKey` | string | `routing-overlay.json` | Content-addressed envelope key in the overlay ConfigMap. |
| `overlay.sidecar.expectedNetwork` | string | `""` | Required GridNetwork scope when the sidecar is enabled. |
| `overlay.sidecar.expectedLocalSite` | string | `""` | Required local-site scope when the sidecar is enabled. |
| `overlay.sidecar.resources` | object | small requests and limits | Resources for both the one-shot init container and continuous sidecar. |
| `gridServing.enabled` | bool | `false` | Mount the operator's serving config, set `GRID_SERVING_CONFIG`, and route with `grid_site_route`. Consumer role and `image.flavor: grid-gateway` only. Needs `tls.enabled`, `tls.existingSecret`, and `tls.caSecret`. |
| `gridServing.network` | string | `""` | GridNetwork name, which with `gatewayRef` names the operator's ConfigMap. |
| `gridServing.gatewayRef` | string | release fullname | This gateway's gatewayRef name in the GridNetwork. |
| `gridServing.configMap` | string | `""` | Overrides the derived `grid-serving-<network>-<gatewayRef>`. Needed when that name passes 63 characters. |
| `gridServing.mountPath` | string | `/etc/praxis/grid-serving` | Mount directory for the ConfigMap. |
| `tls.enabled` | bool | `false` | Mount a TLS Secret. |
| `tls.existingSecret` | string | `grid-site-identity` | Name of the TLS Secret, the site identity the grid operator writes. |
| `tls.caSecret` | string | `""` | Secret holding the Grid CA (`ca.crt`), projected beside `existingSecret`. A provider defaults to `grid-ca`. |
| `tls.mountPath` | string | `/etc/praxis/tls` | Mount path for TLS files. |
| `credentials` | list | `[]` | Existing Secrets mounted read-only (`name`, `mountPath`, `optional`), for example upstream credentials. |
| `health.readiness` | object | TCP socket on the listener port | Readiness probe. A `tcpSocket` without a port targets the listener port. Set to null to disable. |
| `health.liveness` | object | TCP socket on the listener port | Liveness probe. Set to null to disable. |
| `shutdownDelaySeconds` | int | `5` | Seconds a terminating pod keeps serving before Praxis gets SIGTERM, so Service endpoints drop it first and rollouts do not refuse requests. Runs the image's `sleep` as a preStop hook. `0` disables it, which an image without `sleep` (distroless or scratch) needs. |
| `terminationGracePeriodSeconds` | int | `null` | Seconds Kubernetes gives a terminating pod before killing it. Empty means 30 plus `shutdownDelaySeconds`, so Praxis keeps its default 30 second drain after the delay. Raise it for a longer Praxis `shutdown_timeout_secs`. Must exceed `shutdownDelaySeconds`. |
| `resources` | object | `{}` | Container resource requests and limits. |
| `nodeSelector` | object | `{}` | Node selector. |
| `affinity` | object | `{}` | Pod affinity rules. |
| `tolerations` | list | `[]` | Pod tolerations. |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints. |
| `priorityClassName` | string | `""` | Pod priority class. |

## Security

The chart enforces Kubernetes restricted security defaults:

- `runAsNonRoot: true`, running the official images as their numeric user
  (`imageUser`, 100:101) unless `podSecurityContext` sets `runAsUser` or the
  cluster is OpenShift, where the SCC assigns IDs. Other images keep the user
  they declare.
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- All Linux capabilities dropped
- `seccompProfile.type: RuntimeDefault`
- `automountServiceAccountToken: false`

When overlay-sync is enabled, the pod uses a dedicated ServiceAccount, but
automatic token mounting remains disabled. A short-lived projected token is
mounted only into the overlay-sync init and sidecar containers. The Praxis
container has no Kubernetes API credential and mounts the delivered overlay
directory read-only.

## Optional uses

These sections describe settings that matter only for particular setups.

### Edge gateway

An edge gateway is the entry point for clients outside the cluster. A typical
starting point runs more than one replica behind a LoadBalancer and
terminates TLS in Praxis:

```yaml
replicaCount: 2
topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: kubernetes.io/hostname
    whenUnsatisfiable: ScheduleAnyway
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: praxis-gateway
service:
  type: LoadBalancer
gatewayConfig:
  listenerTls:
    enabled: true
    existingSecret: edge-gateway-tls
```

Pair it with a configuration whose listener references the certificate, as
shown in [Exposing the gateway](#exposing-the-gateway).

### AI Grid Network (AGN)

AGN deploys this chart as its consumer (edge) and provider gateways. These
settings exist for that integration:

- `gatewayConfig.render` builds the AGN routing configuration
  (`intelligent_route` and `load_balancer`, with optional `api-key` caller
  authentication) from values, with `gatewayConfig.backends` keyed by site.
- `gatewayConfig.role: provider` serves grid peers on the site identity, admits
  them by `peerTrust`, and forwards to one local backend. It needs
  `image.flavor: grid-gateway`.
- `gridServing` routes each model to the least-loaded site from the operator's
  serving config (see [Cross-site routing in AGN](#cross-site-routing-in-agn)).
- `overlay` mounts the routing overlay the AGN Operator publishes, with an
  optional `grid-overlay-sync` sidecar for prompt delivery.
- `tls` mounts the site identity used for mTLS between grid sites.

The standard Praxis AI 0.4.0 image supports AGN provider selection and load
balancing and includes Basic Auth. It does not include the optional
`token-rate-limit-filter` required by the distributed token quota
qualification. That qualification is not supported by this default image; AGN
does not publish a replacement AI rollup.

### Edge and provider gateways in AGN

AGN runs this chart in two roles with different values:

**Edge gateway:**
- Listens on port 8080 (HTTP)
- Mounts an overlay ConfigMap from the AGN Operator
- Mounts a TLS Secret for upstream connections

**Provider gateway:**
- Listens on port 8443 (mTLS)
- Mounts a TLS Secret for client authentication
- Mounts credential Secrets for backend provider access
- Helm release name must match the mock-providers
  `networkPolicy.providerGateway.instanceLabel` (default: `provider-gateway`)
  so the NetworkPolicy allows traffic

### Resource names for the AGN Operator

The chart's fullname template produces `{release}-praxis-gateway` by
default (e.g., release `consumer-gateway` → Service name
`consumer-gateway-praxis-gateway`). Set `fullnameOverride` to control
the exact Service name:

```yaml
fullnameOverride: consumer-gateway   # Service name = consumer-gateway
```

The AGN Operator's `gateway.serviceName` must match the consumer
gateway's Service name. When using `fullnameOverride`, set
`gateway.serviceName` to the same value in the operator Helm values.

### Cross-site routing in AGN

With `gridServing.enabled`, the consumer gateway reads the serving config the
grid operator writes (under `signalTransport: poll`) and polls each peer's
`/v1/site/signals` over mTLS with the grid identity at `tls.mountPath`. It routes
each model to the least-loaded admitted site. The chosen candidate's cluster must
name a `gatewayConfig.backends` cluster, so give each backend the operator's
candidate cluster (the provider's `routingClusterRef`, else its name).

The gateway reads the file only at start. When the ConfigMap's
`grid.praxis-proxy.io/serving-digest` annotation changes, restart the gateway
(`kubectl rollout restart`).

Known limits:

- `grid_site_route` does not check provider health, so it can pick a site whose
  provider gateway is down. That request fails rather than failing over.
- The gateway matches a candidate's cluster to `gatewayConfig.backends` by name only.
  Nothing checks that the backend serves the candidate's site.
- Site certificates last 30 days and nothing renews them. The gateway reads its
  client certificate and the signals pollers read theirs once, at start, and a
  `pin` digest changes on renewal. After re-enrolling, update the digests and
  restart the gateways.

### Routing overlay delivery

Praxis can hot-reload a routing overlay as soon as its file changes. A normal
ConfigMap volume, however, is updated by the kubelet on an eventual refresh
cycle. That delay can be longer than a temporary provider-pressure event, so a
gateway may continue serving an old preference even though AGN has already
published a new overlay.

Enable `grid-overlay-sync` when prompt routing convergence matters:

```text
AGN Operator updates ConfigMap
             |
             | Kubernetes API watch
             v
      overlay-sync sidecar
        validate envelope
        atomic file replace
        retain last-known-good on failure
             |
             | shared emptyDir
             v
       Praxis hot reload
```

Example values:

```yaml
overlay:
  enabled: true
  existingConfigMap: grid-overlay-production-consumer-gateway
  mountPath: /etc/praxis/routing
  sidecar:
    enabled: true
    image:
      repository: registry.example.com/grid-overlay-sync
      tag: <version>
      pullPolicy: IfNotPresent
    dataKey: routing-overlay.json
    expectedNetwork: production
    expectedLocalSite: us-east-edge
```

When enabled, the chart creates:

- an `overlay-sync-init` init container that waits for the first valid overlay
  before Praxis starts;
- an `overlay-sync` sidecar that watches one named ConfigMap;
- a shared `emptyDir` used for atomic file publication;
- a dedicated ServiceAccount, Role, and RoleBinding; and
- sidecar readiness and liveness probes on port `9091`.

The sidecar validates maximum size, schema version, destination scope,
content-addressed revision, and SHA-256 digest. Invalid replacements do not
touch the serving file. ConfigMap deletion or temporary API loss marks the
sidecar degraded while retaining the last-known-good overlay.

This mechanism removes kubelet projection latency only after AGN applies a
ConfigMap. Total route-change time still includes metrics publication, the
provider scrape, AGN reconciliation, ConfigMap application, sidecar delivery,
and Praxis hot reload. Overlay-sync does not change the scrape or reconcile
intervals.

With `overlay.sidecar.enabled: false`, the chart retains the simpler direct
ConfigMap mount. Use that compatibility mode for static configuration or when
kubelet-controlled refresh latency is acceptable.

### KServe backend on OpenShift

A KServe LLMInferenceService serves HTTPS on :8000 with a cert from the OpenShift
service CA. Use the workload Service ClusterIP as the endpoint: praxis refuses a
hostname that resolves to a private address. Set `sni` to the Service DNS name, which
the cert carries, and trust the service CA that OpenShift injects into every namespace:

```yaml
gatewayConfig:
  backends:
    - cluster: local-qwen3
      endpoints: ["172.30.12.34:8000"]   # kubectl get svc qwen3-kserve-workload-svc -o jsonpath='{.spec.clusterIP}'
      transport:
        mode: tls
        sni: qwen3-kserve-workload-svc.llm.svc
        ca: { configMap: openshift-service-ca.crt, key: service-ca.crt }
```

The health check defaults to `tcp` for TLS backends.

#### validateCA bundle recipe

The bundle replaces the platform store, so include the image's roots with the
private CA:

```sh
podman run --rm --entrypoint cat <gateway image> /etc/ssl/certs/ca-certificates.crt > bundle.pem
cat service-ca.crt >> bundle.pem
kubectl create configmap gateway-validate-ca --from-file=ca.crt=bundle.pem
```

Then set `gatewayConfig.auth.validateCA.configMap=gateway-validate-ca`. If only
the validate call and mutual_tls backends make TLS calls, the service CA alone
is enough. Public https backends can instead take `upstreamCA`.

## Upgrading

- A rendered config requires `gatewayConfig.localSite`. It no longer defaults to `hub`.
- `gatewayConfig.role: provider` and `gridServing` require `image.flavor: grid-gateway`.
- A consumer without `gridServing` still requires `gatewayConfig.model`. A provider no longer does.

## Where this chart lives

The chart is developed in the
[praxis-proxy/grid](https://github.com/praxis-proxy/grid) repository and may
move to a dedicated Praxis repository later.
