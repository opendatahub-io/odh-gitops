# grid-enrollment

![Version: 0.2.0](https://img.shields.io/badge/Version-0.2.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.2.0](https://img.shields.io/badge/AppVersion-v0.2.0-informational?style=flat-square)

Grid enrollment service with self-provisioned Grid CA and Postgres

**Homepage:** <https://github.com/praxis-proxy/grid>

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Praxis Proxy |  |  |

## Source Code

* <https://github.com/praxis-proxy/grid>

## Requirements

Kubernetes: `>=1.26.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| ca | object | `{"bootstrap":{"resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"ttlSecondsAfterFinished":86400},"bundleSecretName":"grid-ca-bundle","commonName":"grid-ca","forceRegenerate":false,"keySecretName":"grid-ca-key","method":"builtin","provided":{"keySecretRef":""}}` | ---------------------------------------------------------------------------- |
| commonLabels | object | `{}` |  |
| db | object | `{"builtin":{"auth":{"database":"enrollment","existingSecretRef":"","username":"enrollment"},"image":"quay.io/sclorg/postgresql-16-c9s:20260923","imageDigest":"","pullPolicy":"IfNotPresent","pvcAnnotations":{},"resources":{"limits":{"cpu":1,"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}},"storage":"8Gi","tls":{"servingSecretName":"grid-db-serving-tls"}},"external":{"caConfigMapKey":"ca.crt","caConfigMapName":"","connectionUrlSecretKey":"DB_CONNECTION_URL","connectionUrlSecretRef":""},"type":"builtin"}` | ---------------------------------------------------------------------------- |
| enrollment | object | `{"affinity":{},"authz":"kube","certLifetimeSecs":"","csrRecord":{"enabled":true,"policy":{"enabled":true},"signerName":"grid.praxis.fast/site"},"enrollmentAdmins":{"subjects":[]},"gridAdminTokens":{"existingSecretRef":"","generate":true},"gridAdmins":{"serviceAccount":{"create":false,"name":"grid-admin"},"subjects":[]},"listenAddr":"0.0.0.0:8443","nodeSelector":{},"podSecurityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"replicaCount":1,"resources":{"limits":{"cpu":1,"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}},"rotation":{"enabled":true},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true},"service":{"loadBalancerIP":"","type":""},"serviceAccount":{"create":true,"name":""},"tokenAudience":"grid-enrollment","tolerations":[]}` | ---------------------------------------------------------------------------- |
| enrollment.rotation.enabled | bool | `true` | Sites rotate their identity here with their current certificate over mutual TLS. A reencrypt Route drops that certificate, so the render refuses reencrypt while this is on. false refuses every rotation (503 rotation_disabled) for the whole grid; issued identities stay valid until they expire. |
| fullnameOverride | string | `""` |  |
| host | string | `""` | The enrollment name sites connect to. It joins the serving cert names and is the default route.host. |
| hubSite | object | `{"caSecretName":"grid-ca","identitySecretName":"grid-site-identity","name":"","namespace":"grid","seedSecretName":"grid-reserved-seeds","swimKeySecretName":"grid-swim-key"}` | The hub's own site identity, issued by the bootstrap Job straight from the grid CA, so the hub never enrolls or needs an invite. It rotates like an enrolled site. Delete the Secret and upgrade to re-issue it. |
| hubSite.caSecretName | string | `"grid-ca"` | Secret the grid CA is written to beside it. |
| hubSite.identitySecretName | string | `"grid-site-identity"` | Secret the site identity is written to. |
| hubSite.name | string | `""` | Hub site name. Empty disables it. Must not also be invited. |
| hubSite.namespace | string | `"grid"` | Namespace of the hub's grid operator. Must exist before install: the chart does not create it. |
| hubSite.seedSecretName | string | `"grid-reserved-seeds"` | Secret, in this namespace, for the seed that registers the hub's key so it can rotate. Bootstrap signs it with the CA key and the service applies only what verifies. A Secret, so replaying an old seed needs the Secret access that already reads the CA key. |
| hubSite.swimKeySecretName | string | `"grid-swim-key"` | Secret for the grid's SWIM key, created once here and in hubSite.namespace. Empty skips it. |
| image.digest | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/praxis-proxy/grid-enrollment"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| initResources | object | `{"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Resource budget for database readiness and TLS permission init containers. |
| invitePolicy | object | `{"clusterSet":"default","enabled":false,"namespace":"grid"}` | ACM Policy delivering each invited site its token, the CA bundle and the gossip key. The site names come from `invites`, so they are not restated here. |
| invitePolicy.clusterSet | string | `"default"` | ManagedClusterSet the sites belong to. The binding is named for it. |
| invitePolicy.enabled | bool | `false` | Render the policy. Needs ACM on this cluster and the sites imported. |
| invitePolicy.namespace | string | `"grid"` | Namespace on each site that its operator reads the Secrets from. |
| log | object | `{"filter":"","level":"info"}` | Logging, rendered as RUST_LOG. |
| log.filter | string | `""` | Full RUST_LOG directive, such as "info,enrollment=debug". When set, it replaces level. |
| log.level | string | `"info"` | Level for every module: off, error, warn, info, debug, or trace. |
| nameOverride | string | `""` |  |
| networkPolicy | object | `{"enabled":true,"from":[],"routerNamespaceSelector":{"matchLabels":{"network.openshift.io/policy-group":"ingress"}}}` | Restrict enrollment and database ingress. Add explicit clients for direct access. |
| networkPolicy.from | list | `[]` | Additional NetworkPolicyPeer entries for the enrollment HTTPS listener. |
| networkPolicy.routerNamespaceSelector | object | `{"matchLabels":{"network.openshift.io/policy-group":"ingress"}}` | Router namespaces allowed when the enrollment Route is enabled. |
| route | object | `{"annotations":{},"enabled":"auto","host":"","rateLimit":{"concurrentTcp":10,"enabled":true,"rateTcp":20},"tls":{"destinationCACertificate":"","insecureEdgeTerminationPolicy":"None","termination":"passthrough"}}` | ---------------------------------------------------------------------------- |
| route.annotations | object | `{}` | Extra Route annotations. They override rateLimit's annotations on a key clash. |
| route.enabled | string | `"auto"` | auto renders the Route when the cluster serves route.openshift.io/v1; true or false forces it. helm template without --api-versions route.openshift.io/v1 renders auto as off. |
| route.host | string | `""` | External hostname. Required for passthrough when a Route renders (auto-added to the serving cert SAN). A DNS-1123 subdomain, no wildcard. |
| route.rateLimit | object | `{"concurrentTcp":10,"enabled":true,"rateTcp":20}` | Per-source-IP connection limits in the OpenShift router (they apply to passthrough). Clients behind one SNAT address share a limit. |
| route.rateLimit.concurrentTcp | int | `10` | Concurrent TCP connections per source IP. |
| route.rateLimit.rateTcp | int | `20` | TCP connection rate per source IP, in the router's rate window. |
| route.tls.destinationCACertificate | string | `""` | PEM CA for reencrypt to verify the backend (grid-CA bundle, ca.crt from Secret grid-ca-bundle). Required for reencrypt. |
| route.tls.insecureEdgeTerminationPolicy | string | `"None"` | Redirect or None. Allow is refused: plaintext would leak the token. |
| route.tls.termination | string | `"passthrough"` | passthrough keeps the grid-CA cert and the one-time token end-to-end. reencrypt terminates at the router: it exposes the enrollment token to the ingress and breaks the site's out-of-band grid-CA pin. edge is rejected, since enrollment serves TLS only. |
| serving | object | `{"existingSecretRef":"","extraDnsNames":[],"secretName":"enrollment-serving-tls"}` | ---------------------------------------------------------------------------- |

