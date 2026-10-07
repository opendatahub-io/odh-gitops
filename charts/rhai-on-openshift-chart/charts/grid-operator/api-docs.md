# grid-operator

![Version: 0.1.4](https://img.shields.io/badge/Version-0.1.4-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.1.4](https://img.shields.io/badge/AppVersion-v0.1.4-informational?style=flat-square)

Grid operator for multi-site AI inference routing with Praxis

**Homepage:** <https://github.com/praxis-proxy/grid>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Praxis Proxy |  | <https://github.com/praxis-proxy> |

## Source Code

* <https://github.com/praxis-proxy/grid>

## Requirements

Kubernetes: `>=1.26.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Pod affinity rules. |
| commonLabels | object | `{}` | Labels added to all chart-managed resources. |
| crds | object | `{"enabled":true,"keep":true}` | Grid CRDs. |
| crds.enabled | bool | `true` | Install and upgrade the CRDs. Set false when the platform owns them, or for a second release in the cluster. |
| crds.keep | bool | `true` | Keep the CRDs on helm uninstall and an Argo CD delete or prune. |
| enrollment | object | `{"caBundle":{"configMap":"","key":"ca.crt","secret":""},"enabled":false,"gridCaBundle":{"configMap":"","key":"ca.crt","secret":""},"siteName":"","tokenSecretRef":{"key":"token","name":""},"url":""}` | Site auto-enroll on startup. |
| enrollment.caBundle | object | `{"configMap":"","key":"ca.crt","secret":""}` | CA pinning the enrollment server, and the grid CA by default. With neither set, Secret grid-ca-bundle. |
| enrollment.caBundle.configMap | string | `""` | ConfigMap holding the bundle. Set this or secret. |
| enrollment.caBundle.key | string | `"ca.crt"` | Key holding the PEM bundle. |
| enrollment.caBundle.secret | string | `""` | Secret holding the bundle. |
| enrollment.enabled | bool | `false` | Enroll when the site identity Secret is absent. |
| enrollment.gridCaBundle | object | `{"configMap":"","key":"ca.crt","secret":""}` | Grid CA anchor, when it differs from caBundle. |
| enrollment.gridCaBundle.configMap | string | `""` | ConfigMap holding the grid CA. Set this or secret. |
| enrollment.gridCaBundle.key | string | `"ca.crt"` | Key holding the PEM bundle. |
| enrollment.gridCaBundle.secret | string | `""` | Secret holding the grid CA. |
| enrollment.siteName | string | `""` | Site name the token pins, at most 51 characters. Defaults to swim.siteName. |
| enrollment.tokenSecretRef | object | `{"key":"token","name":""}` | Secret holding the one-time site token. |
| enrollment.tokenSecretRef.key | string | `"token"` | Key holding the token. |
| enrollment.tokenSecretRef.name | string | `""` | Secret name. Defaults to grid-invite-<siteName>. |
| enrollment.url | string | `""` | Enrollment service https base URL. Defaults to the in-cluster grid-enrollment Service in rbac.enrollmentNamespace, the hub's own. |
| fullnameOverride | string | `""` | Override the fully qualified app name. |
| gateway | object | `{"address":"","allowSystemNamespace":false,"namespace":"","port":"","serviceName":""}` | Advertised gateway address configuration. |
| gateway.address | string | `""` | Gateway address override. |
| gateway.allowSystemNamespace | bool | `false` | Allow gateway.namespace to be default, kube-*, or openshift-*. |
| gateway.namespace | string | `""` | Namespace of the gateway Service. Empty uses the release namespace. Maps to GRID_GATEWAY_NAMESPACE. |
| gateway.port | string | `""` | Gateway port for operator-to-gateway discovery. Maps to GRID_GATEWAY_PORT. |
| gateway.serviceName | string | `""` | Gateway Kubernetes Service name for the operator to discover. Maps to GRID_GATEWAY_SERVICE_NAME. Defaults to grid-gateway with enrollment on. |
| health | object | `{"liveness":{"initialDelaySeconds":5,"periodSeconds":10},"readiness":{"initialDelaySeconds":5,"periodSeconds":10}}` | Probe timing configuration. |
| health.liveness | object | `{"initialDelaySeconds":5,"periodSeconds":10}` | Liveness probe settings. |
| health.liveness.initialDelaySeconds | int | `5` | Initial delay before the first liveness probe. |
| health.liveness.periodSeconds | int | `10` | Period between liveness probes. |
| health.readiness | object | `{"initialDelaySeconds":5,"periodSeconds":10}` | Readiness probe settings. |
| health.readiness.initialDelaySeconds | int | `5` | Initial delay before the first readiness probe. |
| health.readiness.periodSeconds | int | `10` | Period between readiness probes. |
| image | object | `{"digest":"","pullPolicy":"IfNotPresent","repository":"ghcr.io/praxis-proxy/grid-operator","tag":""}` | Operator container image settings. |
| image.digest | string | `""` | Immutable image digest (sha256:<64 hex>). When set, tag is ignored. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.repository | string | `"ghcr.io/praxis-proxy/grid-operator"` | Image repository. |
| image.tag | string | `""` | Image tag. Defaults to the chart appVersion when empty. |
| imagePullSecrets | list | `[]` | Pull secrets for private registries. |
| log | object | `{"level":"info"}` | Logging configuration. |
| log.level | string | `"info"` | RUST_LOG filter directive. |
| metrics | object | `{"bindAddress":"0.0.0.0:9090","service":{"annotations":{},"enabled":true,"port":9090}}` | Metrics and health server configuration. |
| metrics.bindAddress | string | `"0.0.0.0:9090"` | Metrics server bind address (host:port). |
| metrics.service | object | `{"annotations":{},"enabled":true,"port":9090}` | Metrics ClusterIP Service. |
| metrics.service.annotations | object | `{}` | Service annotations. |
| metrics.service.enabled | bool | `true` | Create a ClusterIP Service for the metrics port. |
| metrics.service.port | int | `9090` | Service port number. |
| nameOverride | string | `""` | Override the chart name used in resource names. |
| nodeSelector | object | `{}` | Node selector for pod scheduling. |
| podAnnotations | object | `{}` | Annotations added to the operator pod template. |
| podLabels | object | `{}` | Labels added to the operator pod template. |
| priorityClassName | string | `""` | Priority class for the operator pod. |
| rbac | object | `{"create":true,"enrollmentNamespace":""}` | RBAC configuration. |
| rbac.create | bool | `true` | Create ClusterRoles, ClusterRoleBindings, and RoleBindings. |
| rbac.enrollmentNamespace | string | `""` | The grid-enrollment namespace. The render fails if the operator would get Secret access there. Defaults to grid-enrollment with enrollment on. |
| replicaCount | int | `1` | Number of operator replicas. Must be 1 until multi-replica operation is qualified. |
| resourceNamespaces | list | `[]` | Additional namespaces where the operator needs Secret, ConfigMap, Event, and Service access. The release namespace is always included. |
| resources | object | `{}` | Container resource requests and limits. |
| serviceAccount | object | `{"annotations":{},"create":true,"name":""}` | ServiceAccount configuration. |
| serviceAccount.annotations | object | `{}` | Annotations on the ServiceAccount (e.g. for IAM role binding). |
| serviceAccount.create | bool | `true` | Create a ServiceAccount for the operator. |
| serviceAccount.name | string | `""` | ServiceAccount name. When create is true, defaults to the release fullname. When create is false, defaults to "default". |
| serviceMonitor | object | `{"enabled":false,"interval":"","labels":{},"namespace":"","scrapeTimeout":""}` | Prometheus ServiceMonitor (requires the Prometheus Operator CRD). |
| serviceMonitor.enabled | bool | `false` | Create a ServiceMonitor resource. |
| serviceMonitor.interval | string | `""` | Prometheus scrape interval. |
| serviceMonitor.labels | object | `{}` | Additional labels on the ServiceMonitor. |
| serviceMonitor.namespace | string | `""` | ServiceMonitor namespace override. |
| serviceMonitor.scrapeTimeout | string | `""` | Prometheus scrape timeout. |
| signals | object | `{"advertiseAddress":"","enabled":false,"port":9091}` | mTLS signals endpoint, for a GridNetwork with signalTransport poll. |
| signals.advertiseAddress | string | `""` | Signals endpoint gossiped to peers (ip:port, [ipv6]:port, or dns-name:port). Set it when swim.advertiseAddress is set or the Service is not a LoadBalancer. |
| signals.enabled | bool | `false` | Serve signals on the SWIM Service. Needs swim.service.enabled and, for a LoadBalancer, mixed UDP and TCP support. |
| signals.port | int | `9091` | Signals TCP port on the SWIM Service, gossiped to peers with its LoadBalancer address. |
| swim | object | `{"advertiseAddress":"","bindAddress":"0.0.0.0:7946","requireKey":true,"seeds":"","service":{"annotations":{},"externalTrafficPolicy":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":7946},"siteName":""}` | SWIM protocol configuration. |
| swim.advertiseAddress | string | `""` | SWIM advertise endpoint (ip:port, [ipv6]:port, or hostname:port). Defaults to the LoadBalancer SWIM Service address, else the Pod IP. |
| swim.bindAddress | string | `"0.0.0.0:7946"` | SWIM bind address (host:port). |
| swim.requireKey | bool | `true` | Hold SWIM traffic until the GridNetwork key loads or the network declares none. false opts out. |
| swim.seeds | string | `""` | Bootstrap SWIM seed endpoints (comma-separated ip:port, [ipv6]:port, or hostname:port). |
| swim.service | object | `{"annotations":{},"externalTrafficPolicy":"","loadBalancerIP":"","loadBalancerSourceRanges":[],"port":7946}` | SWIM Service. |
| swim.service.annotations | object | `{}` | Service annotations. |
| swim.service.externalTrafficPolicy | string | `""` | External traffic policy. Defaults to Local for LoadBalancer, omitted for ClusterIP and NodePort. |
| swim.service.loadBalancerIP | string | `""` | Static LoadBalancer IP. Deprecated in Kubernetes, so prefer a metallb.io/loadBalancerIPs annotation. |
| swim.service.loadBalancerSourceRanges | list | `[]` | Optional CIDRs allowed to reach the SWIM and signals LoadBalancer, where it enforces them. |
| swim.service.port | int | `7946` | Service port number. |
| swim.siteName | string | `""` | Bootstrap SWIM site name. Defaults to enrollment.siteName when enrollment is on. |
| tolerations | list | `[]` | Pod tolerations. |
| topologySpreadConstraints | list | `[]` | Topology spread constraints. |

