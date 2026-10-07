# grid-operator Helm Chart

Helm chart for deploying the `grid-operator` multi-site AI inference routing
controller on Kubernetes.

## Prerequisites

- Kubernetes >= 1.26
- Helm >= 3.12

## Install

By semantic version (OCI):

```bash
helm install grid-operator \
  oci://ghcr.io/praxis-proxy/charts/grid-operator \
  --version <version> \
  --namespace grid-system \
  --create-namespace
```

By immutable digest (requires Helm >= 3.13):

```bash
helm install grid-operator \
  oci://ghcr.io/praxis-proxy/charts/grid-operator@sha256:<digest> \
  --namespace grid-system \
  --create-namespace
```

From a local checkout:

```bash
helm install grid-operator charts/grid-operator \
  --namespace grid-system \
  --create-namespace
```

## Versioning

The chart follows [Semantic Versioning](https://semver.org/). In
`Chart.yaml`, `version` identifies the Helm chart package and `appVersion`
identifies the default `ghcr.io/praxis-proxy/grid-operator` image. The two
versions may advance independently, but Grid releases keep them aligned when
the chart and operator ship together.

## Verify

```bash
kubectl api-resources --api-group=grid.praxis-proxy.io
kubectl get deployment grid-operator -n grid-system
helm test grid-operator -n grid-system
```

## Uninstall

```bash
helm uninstall grid-operator -n grid-system
```

Helm removes the namespaced resources and, with `crds.keep: true` (the
default), keeps the CRDs and every custom resource. To remove CRDs and all
custom resources:

```bash
kubectl delete crd agenttoolproviders.grid.praxis-proxy.io \
  gridnetworks.grid.praxis-proxy.io gridsites.grid.praxis-proxy.io \
  inferenceproviders.grid.praxis-proxy.io
```

## Upgrade

```bash
helm upgrade grid-operator \
  oci://ghcr.io/praxis-proxy/charts/grid-operator \
  --version <new-version> \
  --namespace grid-system
```

### Grid SWIM and signals

- The Deployment uses the Recreate strategy, so an upgrade stops the old pod
  before the new one starts. Two pods would gossip two identities for one site.
- With a LoadBalancer SWIM Service the operator waits for its address and never
  falls back to the Pod IP. `GRID_SWIM_ADVERTISE_ADDR` still carries the Pod IP
  for an older binary.
- The operator holds SWIM until the GridNetwork key loads. Set
  `swim.requireKey: false` to opt out.
- Peers learn each site's signals endpoint over SWIM, and dial port 9091 on a
  site that advertises none.
- The signals listener binds `[::]:9091`, or `0.0.0.0:9091` without IPv6.
- Unparseable `GRID_SIGNALS_*` settings fail at startup.

### Gateway namespace

The operator looks for the gateway Service in the release namespace unless
`gateway.namespace` is set. Earlier charts left it to the binary default,
`grid-system`. If the release is outside `grid-system` and the gateway runs
there, set `gateway.namespace=grid-system` when you upgrade.

### CRDs

The CRDs are chart templates, so `helm upgrade` and an Argo CD sync upgrade
them. Set `crds.enabled: false` when a platform owns them, such as the RHOAI
`aiGrid` component, or for a second release in the same cluster.

Releases before this chart version installed the CRDs from `crds/`, so Helm
does not own them yet. First check that no other release owns them. The
release annotation must be empty or this release:

```bash
kubectl get crd agenttoolproviders.grid.praxis-proxy.io gridnetworks.grid.praxis-proxy.io \
  gridsites.grid.praxis-proxy.io inferenceproviders.grid.praxis-proxy.io \
  -o custom-columns='NAME:.metadata.name,RELEASE:.metadata.annotations.meta\.helm\.sh/release-name'
```

Then adopt them once. With Helm 3.17 or later:

```bash
helm upgrade grid-operator oci://ghcr.io/praxis-proxy/charts/grid-operator \
  --version <new-version> --namespace grid-system --take-ownership
```

With an older Helm, mark them as owned by the release, then upgrade as usual:

```bash
RELEASE=grid-operator; NAMESPACE=grid-system; for crd in agenttoolproviders gridnetworks gridsites inferenceproviders; do kubectl label crd "${crd}.grid.praxis-proxy.io" app.kubernetes.io/managed-by=Helm --overwrite; kubectl annotate crd "${crd}.grid.praxis-proxy.io" meta.helm.sh/release-name="${RELEASE}" meta.helm.sh/release-namespace="${NAMESPACE}" --overwrite; done
```

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| `crds.enabled` | bool | `true` | Install and upgrade the Grid CRDs. `false` when a platform owns them. |
| `crds.keep` | bool | `true` | Keep the CRDs on `helm uninstall` and an Argo CD delete or prune. |
| `rbac.enrollmentNamespace` | string | `""` | The grid-enrollment namespace. The render fails if the operator would get Secret access there. |
| `replicaCount` | int | `1` | Operator replicas. Must be 1 (schema-enforced). |
| `image.repository` | string | `ghcr.io/praxis-proxy/grid-operator` | Image repository. |
| `image.tag` | string | `""` | Image tag. Defaults to chart appVersion. |
| `image.digest` | string | `""` | Immutable digest. When set, tag is ignored. Must match `sha256:<64 hex>`. |
| `image.pullPolicy` | string | `IfNotPresent` | Image pull policy. |
| `imagePullSecrets` | list | `[]` | Pull secrets for private registries. |
| `nameOverride` | string | `""` | Override chart name in resource names. |
| `fullnameOverride` | string | `""` | Override fully qualified app name. |
| `commonLabels` | object | `{}` | Labels added to all resources. |
| `podLabels` | object | `{}` | Labels on the operator pod. |
| `podAnnotations` | object | `{}` | Annotations on the operator pod. |
| `serviceAccount.create` | bool | `true` | Create a ServiceAccount. |
| `serviceAccount.name` | string | `""` | ServiceAccount name. Defaults to fullname when `create` is true, `"default"` when false. |
| `serviceAccount.annotations` | object | `{}` | ServiceAccount annotations (e.g. IAM role binding). |
| `rbac.create` | bool | `true` | Create RBAC resources. |
| `resourceNamespaces` | list | `[]` | Additional namespaces for resource access. The release namespace is always included. |
| `log.level` | string | `info` | RUST_LOG filter directive. |
| `metrics.bindAddress` | string | `0.0.0.0:9090` | Metrics server bind address. |
| `metrics.service.enabled` | bool | `true` | Create a metrics ClusterIP Service. |
| `metrics.service.port` | int | `9090` | Metrics Service port. |
| `metrics.service.annotations` | object | `{}` | Metrics Service annotations. |
| `swim.bindAddress` | string | `0.0.0.0:7946` | SWIM protocol bind address. |
| `swim.advertiseAddress` | string | `""` | Externally reachable SWIM address. Defaults to the SWIM Service LoadBalancer address, else Pod IP. |
| `swim.requireKey` | bool | `true` | Hold SWIM traffic until the GridNetwork key loads or the network declares none. |
| `swim.siteName` | string | `""` | Bootstrap SWIM site name. |
| `swim.seeds` | string | `""` | Bootstrap SWIM seed endpoints (comma-separated `ip:port`, `[ipv6]:port`, or `hostname:port`). |
| `swim.service.enabled` | bool | `false` | Create a SWIM Service. |
| `swim.service.type` | string | `ClusterIP` | SWIM Service type. |
| `swim.service.port` | int | `7946` | SWIM Service port. |
| `swim.service.annotations` | object | `{}` | SWIM Service annotations. |
| `swim.service.loadBalancerIP` | string | `""` | Static IP for LoadBalancer. Deprecated in Kubernetes, so prefer `metallb.io/loadBalancerIPs`. |
| `swim.service.externalTrafficPolicy` | string | `""` | External traffic policy. Defaults to Local for LoadBalancer. |
| `swim.service.loadBalancerSourceRanges` | list | `[]` | Optional CIDRs allowed to reach the SWIM and signals LoadBalancer, where the implementation enforces them. |
| `signals.enabled` | bool | `false` | For signalTransport poll. Adds a TCP port named `signals` to the SWIM Service and points this site's gateway at it. Needs `swim.service.enabled`. A LoadBalancer must support mixed UDP and TCP ports. |
| `signals.port` | int | `9091` | Signals port on the SWIM Service. Peers learn the LoadBalancer address and this port over gossip. |
| `signals.advertiseAddress` | string | `""` | Signals endpoint gossiped to peers. Set it with `swim.advertiseAddress` or a NodePort Service, where the operator discovers no LoadBalancer address. |
| `gateway.address` | string | `""` | Advertised gateway address override. Maps to `GRID_GATEWAY_ADDRESS`. |
| `gateway.serviceName` | string | `""` | Provider gateway Service name the operator resolves and advertises to remote sites. Maps to `GRID_GATEWAY_SERVICE_NAME`. |
| `gateway.namespace` | string | `""` | Namespace of the provider gateway Service. Empty uses the release namespace. Outside the resource namespaces, the operator gets only `get` on that one Service there. Maps to `GRID_GATEWAY_NAMESPACE`. |
| `gateway.allowSystemNamespace` | bool | `false` | Allow `gateway.namespace` to be `default`, `kube-*`, or `openshift-*`. |
| `gateway.port` | string | `""` | Provider gateway Service port advertised to remote sites. Empty uses 8080. Maps to `GRID_GATEWAY_PORT`. |
| `health.liveness.initialDelaySeconds` | int | `5` | Liveness probe initial delay. |
| `health.liveness.periodSeconds` | int | `10` | Liveness probe period. |
| `health.readiness.initialDelaySeconds` | int | `5` | Readiness probe initial delay. |
| `health.readiness.periodSeconds` | int | `10` | Readiness probe period. |
| `serviceMonitor.enabled` | bool | `false` | Create a Prometheus ServiceMonitor. |
| `serviceMonitor.labels` | object | `{}` | Additional ServiceMonitor labels. |
| `serviceMonitor.namespace` | string | `""` | ServiceMonitor namespace override. |
| `serviceMonitor.interval` | string | `""` | Prometheus scrape interval. |
| `serviceMonitor.scrapeTimeout` | string | `""` | Prometheus scrape timeout. |
| `resources` | object | `{}` | Container resource requests and limits. |
| `nodeSelector` | object | `{}` | Node selector for scheduling. |
| `affinity` | object | `{}` | Pod affinity rules. |
| `tolerations` | list | `[]` | Pod tolerations. |
| `topologySpreadConstraints` | list | `[]` | Topology spread constraints. |
| `priorityClassName` | string | `""` | Pod priority class. |
| `enrollment.enabled` | bool | `false` | Enroll on startup when the GridNetwork's `siteSecretRef` Secret is absent. |
| `enrollment.url` | string | `""` | Enrollment service base URL (https). |
| `enrollment.siteName` | string | `""` | Site name the token pins, at most 51 characters. |
| `enrollment.caBundle` | object | `{configMap: "", secret: "", key: ca.crt}` | CA bundle that pins the enrollment server, from exactly one of `configMap` and `secret`. |
| `enrollment.gridCaBundle` | object | `{configMap: "", secret: "", key: ca.crt}` | Grid CA the returned CA must match, from at most one source. Defaults to `caBundle`. |
| `enrollment.tokenSecretRef` | object | `{name: "", key: token}` | Secret in the release namespace holding the one-time site token. |

## Auto-enroll

With `enrollment.enabled`, the operator enrolls on startup when the GridNetwork's `spec.tls.siteSecretRef` Secret is absent, and reports ready after it enrolls. That Secret and `caSecretRef` must be in the release namespace. With `rbac.create=false`, grant the operator get, create, and patch on Secrets. [Site Enrollment](../../docs/installation/enrollment.md#enroll-a-site) covers the hub and site steps.

## RBAC and namespace access

The chart creates two ClusterRoles:

1. **CRD access** (`<release>-crd`): cluster-wide get/list/watch/patch on
   GridNetworks and InferenceProviders; get/list/watch/patch/create/update on
   GridSites; get/patch on all three status subresources.
2. **Resource access** (`<release>-resources`): get/create/patch on Secrets;
   get on Services; create/patch on Events (`events.k8s.io`);
   get/create/patch/update on ConfigMaps.

Resource access is bound via RoleBindings. The release namespace always gets
a RoleBinding. Additional namespaces are added through `resourceNamespaces`:

```bash
helm upgrade grid-operator charts/grid-operator \
  --set "resourceNamespaces={app-ns,data-ns}" \
  --namespace grid-system
```

The `default` namespace is **not** implicitly included. Users must list it
in `resourceNamespaces` if the operator needs access there.

## Security

The chart enforces OpenShift-compatible restricted security defaults:

- `runAsNonRoot: true` (no fixed UID, so OpenShift can assign one)
- `readOnlyRootFilesystem: true`
- `allowPrivilegeEscalation: false`
- All Linux capabilities dropped
- `seccompProfile.type: RuntimeDefault`

## Monitoring

Enable a Prometheus ServiceMonitor (requires the Prometheus Operator CRD):

```yaml
serviceMonitor:
  enabled: true
  interval: 30s
```

## SWIM Service

Expose the SWIM port for cross-cluster mesh connectivity:

```yaml
swim:
  service:
    enabled: true
    type: LoadBalancer
    annotations:
      metallb.io/loadBalancerIPs: "192.0.2.10"
```

With a LoadBalancer Service and no `swim.advertiseAddress`, the operator
advertises the Service's LoadBalancer address and port. It reports not ready
until the address appears, logging an error after 3 minutes, and exits when
the address later changes so the restarted pod advertises the new one. A
hostname resolves once at startup, so it needs a stable IP. An explicit
`swim.advertiseAddress` always wins. Set it for a NodePort Service, which
otherwise advertises the Pod IP, not routable from remote clusters. Pin the
LoadBalancer IP with an annotation such as `metallb.io/loadBalancerIPs`.
The SWIM LoadBalancer Service publishes not-ready addresses, because some
implementations, such as k3s servicelb, publish an address only for an endpoint.

Signals on a LoadBalancer require `externalTrafficPolicy: Local`, the chart
default. The listener caps handshakes per source address, and `Cluster` SNAT
gives many peers one source. Set `swim.service.loadBalancerSourceRanges` to the peers'
egress CIDRs where the implementation enforces it.

The chart creates a Service but does not configure cross-cluster networking,
DNS, or firewall rules. Those remain deployment-platform responsibilities.
