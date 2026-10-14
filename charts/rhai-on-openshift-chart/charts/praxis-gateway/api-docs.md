# praxis-gateway

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.4.0](https://img.shields.io/badge/AppVersion-0.4.0-informational?style=flat-square)

Deploys the Praxis proxy as a Kubernetes Deployment and Service, configured from Helm values or an existing ConfigMap. Works on its own as a gateway or reverse proxy; no operator or CRDs required.

**Homepage:** <https://github.com/praxis-proxy/grid>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Praxis Proxy |  | <https://github.com/praxis-proxy> |

## Source Code

* <https://github.com/praxis-proxy/grid>
* <https://github.com/praxis-proxy/ai>

## Requirements

Kubernetes: `>=1.26.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Pod affinity rules. |
| args | list | `["--config","/etc/praxis/praxis.yaml"]` | Container arguments. Defaults to the config file path. |
| command | list | `[]` | Container command, replacing the image entrypoint. Empty keeps the entrypoint. Set it for images whose entrypoint already passes a config path, for example ["praxis"] for the core image ghcr.io/praxis-proxy/praxis. |
| commonLabels | object | `{}` | Labels added to all chart-managed resources. |
| config | object | `{"existingConfigMap":"","inline":"admin:\n  address: \"127.0.0.1:9901\"\nlisteners:\n  - name: default\n    address: \"0.0.0.0:8080\"\n    filter_chains: [default]\nfilter_chains:\n  - name: default\n    filters:\n      - filter: static_response\n        status: 200\n        headers:\n          - name: Content-Type\n            value: application/json\n        body: '{\"status\": \"ok\", \"server\": \"praxis\"}'\n        conditions:\n          - when:\n              path: \"/\"\n      - filter: static_response\n        status: 404\n        headers:\n          - name: Content-Type\n            value: application/json\n        body: '{\"error\": \"not found\"}'\n","key":"praxis.yaml"}` | Praxis configuration (praxis.yaml). The first source that is set wins: gatewayConfig.render, then config.existingConfigMap, then config.inline. render also turns on by itself when existingConfigMap is empty and gatewayConfig configures grid routing (backends, role provider, or gridServing). Setting gatewayConfig.localSite or model without any of those fails the install rather than serving config.inline. Changing a config the chart renders (render or inline) rolls the pods. |
| config.existingConfigMap | string | `""` | Name of an existing ConfigMap holding the Praxis configuration. The chart mounts it but does not manage it, so editing it does not restart the pods. |
| config.inline | string | `"admin:\n  address: \"127.0.0.1:9901\"\nlisteners:\n  - name: default\n    address: \"0.0.0.0:8080\"\n    filter_chains: [default]\nfilter_chains:\n  - name: default\n    filters:\n      - filter: static_response\n        status: 200\n        headers:\n          - name: Content-Type\n            value: application/json\n        body: '{\"status\": \"ok\", \"server\": \"praxis\"}'\n        conditions:\n          - when:\n              path: \"/\"\n      - filter: static_response\n        status: 404\n        headers:\n          - name: Content-Type\n            value: application/json\n        body: '{\"error\": \"not found\"}'\n"` | set-file config.inline=praxis.yaml. |
| config.key | string | `"praxis.yaml"` | Key within existingConfigMap that holds praxis.yaml. |
| credentials | list | `[]` | Existing Secrets mounted read-only into the Praxis container, for example upstream API credentials that the Praxis config references. |
| env | list | `[]` | credentials and other deployment-managed secrets. |
| fullnameOverride | string | `""` | Override the fully qualified app name, which also names the Service. Empty keeps the release-based name: {release}-praxis-gateway, or the release name when it already contains the chart name or the gateway is a grid gateway. |
| gatewayConfig.auth.allowPrivateEndpoint | bool | `false` | Let the validate call reach a private address (an in-cluster Service). Sets the policy filter's allow_private_idp, which is engine-wide: every policy callout may then reach any private, loopback, or link-local address, not only validateUrl. |
| gatewayConfig.auth.allowUnauthenticatedExposure | bool | `false` | With mode none, allow a LoadBalancer or NodePort Service. Without it the render fails, since that exposes unauthenticated inference. The guard only sees this chart's Service; see networkPolicy for exposure created outside the chart. |
| gatewayConfig.auth.mode | string | `""` | Caller authentication, required when render is true. api-key validates the caller's key against validateUrl and needs an image whose policy engine registers identity/api-key (praxis-policy 0.4 or later); the render refuses it on the default ai:0.4.0 image. none renders no policy filter and belongs only behind an authenticating front. TODO: default to api-key once the default image carries praxis-policy 0.4. |
| gatewayConfig.auth.prefix | string | `"Bearer "` | Credential prefix the resolver strips before lookup. |
| gatewayConfig.auth.stripAuthorization | bool | `true` | Remove the caller's Authorization header before routing, in either mode. The key authenticates this hop only. Forwarded grid hops authenticate by mTLS identity. false forwards the caller's key or bearer to every backend and cross-site peer; use it only when the backend validates that same credential. |
| gatewayConfig.auth.timeoutSecs | int | `5` | Validate call timeout (seconds). |
| gatewayConfig.auth.validateCA | object | `{"configMap":"","key":"ca.crt","mountPath":"/etc/praxis/validate-ca","secret":""}` | CA that signs the validate endpoint's certificate (for example the OpenShift service CA). Mounted and set as SSL_CERT_FILE, which REPLACES the platform trust store for the process: the validate call and https backends without a per-backend CA or upstreamCA use it; mutual_tls backends and upstreamCA do not. Build the bundle as the image's /etc/ssl/certs/ca-certificates.crt plus the service CA, or set upstreamCA for public https backends. Set configMap or secret, not both. Empty keeps the platform store. |
| gatewayConfig.auth.validateCA.configMap | string | `""` | ConfigMap holding the bundle (for example one annotated service.beta.openshift.io/inject-cabundle, key service-ca.crt). |
| gatewayConfig.auth.validateCA.key | string | `"ca.crt"` | Key holding the PEM bundle. |
| gatewayConfig.auth.validateCA.mountPath | string | `"/etc/praxis/validate-ca"` | Mount path for the bundle. |
| gatewayConfig.auth.validateCA.secret | string | `""` | Secret holding the bundle. |
| gatewayConfig.auth.validateUrl | string | `""` | identity/validate endpoint URL (a backend answering the validate contract: POST {"key":...} returns {"valid":...}). Must be https, or the render fails, since a plaintext validate call ships the credential in the clear. |
| gatewayConfig.listenerTls | object | `{"enabled":false,"existingSecret":"","mountPath":"/etc/praxis/listener-tls"}` | Inbound TLS on the gateway listener. The default posture assumes an inbound TLS front (an OpenShift Route or a Gateway) terminates TLS and forwards to this plaintext listener. Enable to terminate TLS at the gateway itself from a mounted server cert (tls.crt/tls.key in the Secret). Works with render consumers and BYO, which must reference mountPath (a BYO config moving off tls.enabled must change its listener cert paths to it). Enabling it names the container port https. On OpenShift, set service.annotations service.beta.openshift.io/serving-cert-secret-name to the Secret name and the service CA issues the cert. Render providers use tls.existingSecret and reject gatewayConfig.listenerTls.enabled. |
| gatewayConfig.listenerTls.enabled | bool | `false` | Terminate TLS at the gateway listener instead of at an inbound front. |
| gatewayConfig.listenerTls.existingSecret | string | `""` | Existing Secret holding the server certificate (tls.crt) and key (tls.key). |
| gatewayConfig.listenerTls.mountPath | string | `"/etc/praxis/listener-tls"` | Mount path for the listener certificate. |
| gatewayConfig.localSite | string | `""` | This gateway's site name, required when render is true. |
| gatewayConfig.model | string | `""` | Model advertised on the routing candidates. A consumer without gridServing needs it. |
| gatewayConfig.peerTrust | object | `{"allowAnyGridSite":false,"certDigests":[],"digest":"","mode":"pin","nextDigest":"","rateLimit":{},"spiffeId":"","spiffeIds":[]}` | Grid peers a provider accepts, each with a Grid-CA client certificate. |
| gatewayConfig.peerTrust.allowAnyGridSite | bool | `false` | spiffe mode with no spiffeIds: accept any site the Grid CA signed. Names no site, so the chain gets no peer check; cannot be set beside spiffeIds. |
| gatewayConfig.peerTrust.certDigests | list | `[]` | pin mode: lowercase hex SHA-256 of each allowed peer's leaf certificate (DER). |
| gatewayConfig.peerTrust.digest | string | `""` | pin mode: one allowed leaf digest, added to certDigests. |
| gatewayConfig.peerTrust.mode | string | `"pin"` | pin (certDigests) or spiffe (spiffeIds, experimental). Match the GridNetwork peerTrust.mode. |
| gatewayConfig.peerTrust.nextDigest | string | `""` | pin mode: the next leaf digest during a rotation. |
| gatewayConfig.peerTrust.rateLimit | object | `{}` | Optional inbound budget shared by all peers, for example { rate: 20, burst: 40 }. |
| gatewayConfig.peerTrust.spiffeId | string | `""` | spiffe mode: one allowed SPIFFE ID, added to spiffeIds. |
| gatewayConfig.peerTrust.spiffeIds | list | `[]` | spiffe mode: allowed peer SPIFFE IDs (spiffe://grid.internal/site/<name>). The handshake admits exactly these, and the filter chain names the same sites, so a narrower per-candidate check can only take sites away from what is admitted here. |
| gatewayConfig.provider | object | `{"allowedPaths":["/v1/chat/completions","/v1/completions","/v1/models","/v1/embeddings"]}` | Provider role settings. |
| gatewayConfig.provider.allowedPaths | list | `["/v1/chat/completions","/v1/completions","/v1/models","/v1/embeddings"]` | Exact paths forwarded to the local backend, GET and POST only. Other paths get a 404. |
| gatewayConfig.render | bool | `false` | Render praxis.yaml + policy.yaml from these values instead of config. Also on when config.existingConfigMap is empty and backends, role provider, or gridServing is set. Changing the rendered config rolls the pods. |
| gatewayConfig.role | string | `"consumer"` | consumer routes callers. provider serves grid peers on the grid identity and forwards to one backend. |
| gatewayConfig.telemetry | object | `{"allowInsecure":false,"batchIntervalSecs":null,"batchSize":null,"enabled":false,"environment":"","otlpEndpoint":"","samplingRate":null,"serviceName":"","serviceVersion":""}` | Opt in to OTLP tracing in the generated praxis.yaml. Requires image.flavor: grid-gateway, whose Grid image build includes the Praxis OTLP exporter and Praxis AI routing-span features. Credentials belong in env as Secret-backed OTEL_EXPORTER_OTLP_HEADERS, never here. |
| gatewayConfig.telemetry.allowInsecure | bool | `false` | Permit HTTP only for a trusted local collector. Never send credentials over plaintext. |
| gatewayConfig.telemetry.batchIntervalSecs | string | `nil` | Batch export interval in seconds; must be positive. |
| gatewayConfig.telemetry.batchSize | string | `nil` | Maximum spans per export batch; must be positive. |
| gatewayConfig.telemetry.environment | string | `""` | deployment.environment resource attribute. |
| gatewayConfig.telemetry.otlpEndpoint | string | `""` | OTLP/gRPC endpoint. Empty uses OTEL_EXPORTER_OTLP_ENDPOINT from env. |
| gatewayConfig.telemetry.samplingRate | string | `nil` | Root sampling probability in the inclusive range 0.0..1.0. |
| gatewayConfig.telemetry.serviceName | string | `""` | OpenTelemetry service.name resource attribute. |
| gatewayConfig.telemetry.serviceVersion | string | `""` | OpenTelemetry service.version resource attribute. |
| gatewayConfig.upstreamCA | object | `{"key":"ca.crt","mountPath":"/etc/praxis/upstream-ca","secretName":""}` | CA bundle for backend TLS without a per-cluster CA. Sets praxis upstream_ca_file, which replaces the system trust store for proxied upstreams. It does not apply to the api-key validate call; use auth.validateCA for that. |
| gatewayConfig.upstreamCA.key | string | `"ca.crt"` | Key within the Secret that holds the PEM bundle. |
| gatewayConfig.upstreamCA.mountPath | string | `"/etc/praxis/upstream-ca"` | Mount path for the CA bundle. |
| gatewayConfig.upstreamCA.secretName | string | `""` | Existing Secret holding the CA bundle. Empty keeps the system trust store. |
| gridServing | object | `{"configMap":"","enabled":false,"gatewayRef":"","mountPath":"/etc/praxis/grid-serving","network":"","siteRoute":{"availability":{},"prefixAffinity":{}}}` | Operator-rendered serving config for grid_site_route. See the README Cross-Site Routing section. |
| gridServing.configMap | string | `""` | The operator's ConfigMap, overriding grid-serving-<network>-<gatewayRef>. |
| gridServing.enabled | bool | `false` | Mount the serving config and set GRID_SERVING_CONFIG. |
| gridServing.gatewayRef | string | `""` | This gateway's gatewayRef name in the GridNetwork. Defaults to the release fullname. |
| gridServing.mountPath | string | `"/etc/praxis/grid-serving"` | Mount directory for the ConfigMap. |
| gridServing.network | string | `""` | GridNetwork name, which with gatewayRef names the operator's ConfigMap. |
| gridServing.siteRoute | object | `{"availability":{},"prefixAffinity":{}}` | Tuning for the grid_site_route filter block: availability and prefixAffinity, keys as the filter reads them. Fields and defaults in examples/gateway/grid-site-route.yaml. |
| gridServing.siteRoute.availability | object | `{}` | Site availability. Every field defaults; `shedding` is the one switch. |
| gridServing.siteRoute.prefixAffinity | object | `{}` | Prefix affinity. |
| health | object | `{"adminProbeCommand":[],"liveness":{"initialDelaySeconds":5,"periodSeconds":10,"tcpSocket":{}},"readiness":{"initialDelaySeconds":3,"periodSeconds":5,"tcpSocket":{}}}` | Probe configuration. |
| health.adminProbeCommand | list | `[]` | Command for the admin-listener probe; the URL is appended as its last argument. Empty uses /bin/sh with curl or wget. Set it for an image with neither, for example a distroless image that ships its own HTTP check. |
| health.liveness | object | `{"initialDelaySeconds":5,"periodSeconds":10,"tcpSocket":{}}` | Liveness probe settings. Set to null to disable. Chosen the same way as readiness, but always asks /healthy. |
| health.readiness | object | `{"initialDelaySeconds":3,"periodSeconds":5,"tcpSocket":{}}` | Readiness probe settings. Set to null to disable. A tcpSocket without a port becomes an HTTP probe of the loopback admin listener when the chart sees one (rendered config or config.inline). It asks /healthy when the gateway forwards to backends (rendered backends, gridServing, or config.inline clusters; /ready fails while any backend is down), else /ready, and runs /bin/sh with curl or wget, whichever the image has; see adminProbeCommand. When the chart sees no admin listener, it stays a plain TCP connect to the listener port, which checks no path. A config.inline TLS listener without a visible admin listener is refused, since a TCP probe fails its handshake every period. Give tcpSocket a port, or another handler, to keep your own probe. |
| image | object | `{"digest":"","flavor":"ai","pullPolicy":"IfNotPresent","repository":"ghcr.io/praxis-proxy/ai","tag":"0.4.0"}` | Gateway container image settings. |
| image.digest | string | `""` | Immutable image digest (sha256:<64 hex>). When set, tag is ignored. |
| image.flavor | string | `"ai"` | ai (praxis-proxy/ai) or grid-gateway, the grid build that role provider and gridServing need. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `"ghcr.io/praxis-proxy/ai"` | Image repository. |
| image.tag | string | `"0.4.0"` | Image tag. Used when digest is empty. |
| imagePullSecrets | list | `[]` | Pull secrets for private registries. |
| imageUser | object | `{"enabled":"auto","gid":101,"uid":100}` | Numeric user and group for the Praxis container when podSecurityContext sets no runAsUser; a podSecurityContext runAsGroup still replaces gid. The official Praxis images run as the named user praxis (100:101). The kubelet can only enforce runAsNonRoot against a numeric user, and refuses to start the container when it has none. |
| imageUser.enabled | string | `"auto"` | auto applies uid and gid only to the official praxis-proxy ai, praxis, and grid-gateway images (mirrors that keep that path count), not their -fips tags, which run as 1001:1001, and not on OpenShift (security.openshift.io/v1 is served), where the restricted SCC assigns IDs from the namespace range. Other images keep the user they declare. true forces it for any image, such as one built FROM the official images that keeps the named user praxis; false never applies it. helm template without --api-versions security.openshift.io/v1 renders auto as on. |
| imageUser.gid | int | `101` | runAsGroup for the Praxis container. |
| imageUser.uid | int | `100` | runAsUser for the Praxis container. |
| log | object | `{"filter":"","level":""}` | Logging, rendered as RUST_LOG on the gateway and overlay-sync containers. An env entry named RUST_LOG takes precedence on the gateway. Praxis adds config.runtime.log_overrides per module on top, and its admin listener can change the level at runtime without a restart. |
| log.filter | string | `""` | Full RUST_LOG directive, such as "info,praxis_filter=debug". When set, it replaces level. |
| log.level | string | `""` | Level for every module: off, error, warn, info, debug, or trace. Empty leaves RUST_LOG unset, so the binary uses its own default (info). |
| metricsListener | object | `{"enabled":false,"existingSecret":"","fromNamespaces":[],"mountPath":"/etc/praxis/metrics-tls","port":9443,"service":{"annotations":{}},"serviceMonitor":{"caConfigMap":{"key":"ca.crt","name":""},"enabled":false,"interval":"30s","scrapeTimeout":""}}` | TLS listener serving only GET /metrics, for an in-cluster Prometheus. The admin listener cannot be scraped from outside the pod. Needs the grid-gateway image and networkPolicy.enabled, since the port is reachable only from fromNamespaces. |
| metricsListener.enabled | bool | `false` | Serve the listener. |
| metricsListener.existingSecret | string | `""` | Secret holding tls.crt and tls.key, for example the serving cert that service.annotations requests on OpenShift. Required when enabled. |
| metricsListener.fromNamespaces | list | `[]` | Namespaces, by name, whose pods may reach the port. Required when enabled. |
| metricsListener.mountPath | string | `"/etc/praxis/metrics-tls"` | Mount path for the cert. The listener reloads it when it changes. |
| metricsListener.port | int | `9443` | Container and Service port. |
| metricsListener.service.annotations | object | `{}` | Annotations on the ClusterIP metrics Service. |
| metricsListener.serviceMonitor.caConfigMap | object | `{"key":"ca.crt","name":""}` | ConfigMap holding the CA that signed the metrics cert. Required when enabled. |
| metricsListener.serviceMonitor.enabled | bool | `false` | Render a monitoring.coreos.com/v1 ServiceMonitor for the metrics Service. |
| metricsListener.serviceMonitor.interval | string | `"30s"` | Scrape interval. |
| metricsListener.serviceMonitor.scrapeTimeout | string | `""` | Scrape timeout. Unset leaves Prometheus's default of 10s, which Prometheus refuses when it exceeds the interval, so an interval under 10s needs this set to at most the interval. |
| mountReconciliation | object | `{"enabled":false,"gatewayRef":"","managedCredentialNames":[],"network":"","operator":{"namespace":"grid-system","serviceAccount":"grid-operator"},"rbac":{"create":true},"releaseHelmMounts":false}` | Delegate generated Secret mounts to the Grid operator for an opted-in GridNetwork gateway. Grid owns only its reserved volumes and mounts. |
| mountReconciliation.enabled | bool | `false` | Annotate this Deployment so the operator can verify explicit ownership. |
| mountReconciliation.gatewayRef | string | `""` | GridNetwork gatewayRefs name. Defaults to this chart's Deployment name. |
| mountReconciliation.managedCredentialNames | list | `[]` | Credential Secret names whose mounts Grid now owns. Other entries in credentials remain Helm-managed and are rendered as before. These mounts are omitted only when releaseHelmMounts is true. |
| mountReconciliation.network | string | `""` | GridNetwork name that delegates this gateway's generated mounts. |
| mountReconciliation.operator | object | `{"namespace":"grid-system","serviceAccount":"grid-operator"}` | The operator ServiceAccount the Role binds. The defaults match the grid-operator chart installed as release grid-operator in grid-system. |
| mountReconciliation.rbac | object | `{"create":true}` | Create a Role and RoleBinding in the release namespace that let the AGN Operator's ServiceAccount get and patch this chart's Deployment and no other. The operator's own charts grant no unrestricted Deployment access; rotation retains a grant on the named gateway. Set false to bring your own Role (the README shows it), for example when the installer may not create RBAC. |
| mountReconciliation.releaseHelmMounts | bool | `false` | Release selected Helm-managed credential mounts, and TLS mounts when gridServing is disabled, after Grid reports the generated config Ready. Keep false during the preparation rollout. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| networkPolicy | object | `{"enabled":true,"from":[{"podSelector":{"matchLabels":{"grid.opendatahub.io/gateway-client":"true"}}},{"namespaceSelector":{"matchLabels":{"network.openshift.io/policy-group":"ingress"}}}]}` | NetworkPolicy that limits which pods can reach the listener port, where the CNI enforces NetworkPolicy. It is not authentication. With auth.mode none it narrows exposure the Service guard cannot see (oc expose, another Service, an HTTPRoute): list only the authenticating front. Node and host-network traffic handling is CNI-specific (OVN-Kubernetes: the policy-group.network.openshift.io/host-network namespace label), and a LoadBalancer with externalTrafficPolicy Cluster can SNAT clients to node IPs. |
| networkPolicy.enabled | bool | `true` | Render the NetworkPolicy. |
| networkPolicy.from | list | `[{"podSelector":{"matchLabels":{"grid.opendatahub.io/gateway-client":"true"}}},{"namespaceSelector":{"matchLabels":{"network.openshift.io/policy-group":"ingress"}}}]` | NetworkPolicyPeer entries allowed to reach the listener. Required when enabled. {podSelector: {}} admits every pod in this namespace. An empty namespaceSelector and an ipBlock of 0.0.0.0/0 or ::/0 admit everyone and fail the render. |
| nodeSelector | object | `{}` | Node selector for pod scheduling. |
| overlay | object | `{"enabled":false,"existingConfigMap":"","items":[{"key":"routing-config.json","path":"routing-config.json"},{"key":"routing-overlay.json","path":"routing-overlay.json"}],"mountPath":"/etc/praxis/routing","sidecar":{"dataKey":"routing-overlay.json","enabled":false,"expectedLocalSite":"","expectedNetwork":"","image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/praxis-proxy/grid-overlay-sync","tag":"v0.2.0"},"resources":{"limits":{"cpu":"50m","memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}}}` | Optional routing overlay ConfigMap mount, as published by the AGN operator for its edge gateways. |
| overlay.enabled | bool | `false` | Enable overlay ConfigMap mount. |
| overlay.existingConfigMap | string | `""` | Name of the existing overlay ConfigMap. |
| overlay.items | list | `[{"key":"routing-config.json","path":"routing-config.json"},{"key":"routing-overlay.json","path":"routing-overlay.json"}]` | Items to project from the ConfigMap (used when sidecar is disabled). |
| overlay.mountPath | string | `"/etc/praxis/routing"` | Mount path for overlay files. |
| overlay.sidecar | object | `{"dataKey":"routing-overlay.json","enabled":false,"expectedLocalSite":"","expectedNetwork":"","image":{"pullPolicy":"IfNotPresent","repository":"ghcr.io/praxis-proxy/grid-overlay-sync","tag":"v0.2.0"},"resources":{"limits":{"cpu":"50m","memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}}` | Overlay sync sidecar settings. When enabled, the sidecar watches the ConfigMap via the Kubernetes API and writes validated overlays to a shared emptyDir, replacing the kubelet volume sync. |
| overlay.sidecar.dataKey | string | `"routing-overlay.json"` | ConfigMap data key containing the overlay envelope. |
| overlay.sidecar.enabled | bool | `false` | Enable the overlay-sync sidecar. |
| overlay.sidecar.expectedLocalSite | string | `""` | Expected local site name for scope validation. |
| overlay.sidecar.expectedNetwork | string | `""` | Expected GridNetwork name for scope validation. |
| overlay.sidecar.image | object | `{"pullPolicy":"IfNotPresent","repository":"ghcr.io/praxis-proxy/grid-overlay-sync","tag":"v0.2.0"}` | Sidecar container image. |
| overlay.sidecar.image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| overlay.sidecar.image.repository | string | `"ghcr.io/praxis-proxy/grid-overlay-sync"` | Image repository. |
| overlay.sidecar.image.tag | string | `"v0.2.0"` | Image tag. Empty uses the chart appVersion, which is the praxis version, not a grid-overlay-sync tag, so keep this set. |
| overlay.sidecar.resources | object | `{"limits":{"cpu":"50m","memory":"32Mi"},"requests":{"cpu":"10m","memory":"16Mi"}}` | Sidecar resource requests and limits. |
| podAnnotations | object | `{}` | Annotations on the gateway pod template. |
| podLabels | object | `{}` | Additional labels on the gateway pod template. Selector labels cannot be overridden. |
| podSecurityContext | object | `{}` | Extra pod-level securityContext fields (e.g. runAsUser, runAsGroup). runAsNonRoot and seccompProfile are always set by the chart. |
| port | object | `{"containerPort":8080,"name":"","protocol":"TCP"}` | Primary listener port configuration. |
| port.containerPort | int | `8080` | Container port number. |
| port.name | string | `""` | Port name. Empty: https when gatewayConfig.listenerTls.enabled, else http. |
| port.protocol | string | `"TCP"` | Port protocol. |
| priorityClassName | string | `""` | Priority class for the gateway pod. |
| replicaCount | int | `1` | Number of gateway replicas. |
| resources | object | `{"limits":{"cpu":2,"memory":"1Gi"},"requests":{"cpu":"100m","memory":"128Mi"}}` | Container resource requests and limits. |
| route | object | `{"annotations":{},"enabled":false,"externalTls":false,"host":"","tls":{"destinationCACertificate":"","termination":"passthrough"}}` | OpenShift Route to the Service, for a stable HTTPS name. The gateway terminates TLS. |
| route.annotations | object | `{}` | Route annotations. |
| route.enabled | bool | `false` | Render the Route. Needs the route.openshift.io/v1 API. |
| route.externalTls | bool | `false` | Attest that an inline/external config serves TLS on the Service port with a cert for route.host. |
| route.host | string | `""` | External hostname, a name on the gateway certificate. Required when enabled. |
| route.tls.destinationCACertificate | string | `""` | PEM CA that signed the gateway certificate. Required for reencrypt, unless the listener cert is the one the Service's serving-cert-secret-name annotation issues. |
| route.tls.termination | string | `"passthrough"` | passthrough keeps TLS and client certificates end to end. reencrypt terminates at the router. |
| service | object | `{"annotations":{},"enabled":true,"loadBalancerIP":"","port":8080,"type":""}` | Gateway Service configuration. |
| service.annotations | object | `{}` | Service annotations. |
| service.enabled | bool | `true` | Create a Service for the gateway. |
| service.loadBalancerIP | string | `""` | Static IP for LoadBalancer type. |
| service.port | int | `8080` | Service port number. |
| service.type | string | `""` | Service type. Empty: LoadBalancer for a provider, which peers dial, else ClusterIP. |
| shutdownDelaySeconds | int | `5` | Seconds a terminating pod keeps serving before Praxis is told to stop. Praxis closes its listener as soon as it gets SIGTERM, but Service endpoints take a moment to drop the pod, so without a delay every rollout refuses a few requests. Runs the image's sleep binary as a preStop hook, and the default terminationGracePeriodSeconds grows to cover it. 0 disables it, which an image without sleep (distroless or scratch) needs. |
| terminationGracePeriodSeconds | string | `nil` | Seconds Kubernetes gives a terminating pod before killing it. Empty: 30 plus shutdownDelaySeconds, so Praxis still gets its default 30 seconds (shutdown_timeout_secs) to drain in-flight requests after the delay. Raise it if your Praxis config sets a longer shutdown_timeout_secs. Must exceed shutdownDelaySeconds. |
| tls | object | `{"caSecret":"","enabled":false,"existingSecret":"grid-site-identity","mountPath":"/etc/praxis/tls"}` | Optional TLS Secret mounted at tls.mountPath: the grid site identity, or a client identity for upstream mTLS that the Praxis config references. |
| tls.caSecret | string | `""` | Secret holding the Grid CA (ca.crt), projected beside existingSecret. A provider defaults to grid-ca. |
| tls.enabled | bool | `false` | Enable TLS Secret mount. |
| tls.existingSecret | string | `"grid-site-identity"` | Name of the existing TLS Secret, the site identity the grid operator writes. |
| tls.mountPath | string | `"/etc/praxis/tls"` | Mount path for TLS files. |
| tolerations | list | `[]` | Pod tolerations. |
| topologySpreadConstraints | list | `[]` | Topology spread constraints. |

