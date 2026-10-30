# grid-enrollment

![Version: 0.3.0-rc.3](https://img.shields.io/badge/Version-0.3.0--rc.3-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.3.0-rc.3](https://img.shields.io/badge/AppVersion-v0.3.0--rc.3-informational?style=flat-square)

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
| ca | object | `{"bootstrap":{"policy":{"enabled":true},"resources":{"limits":{"cpu":"500m","memory":"256Mi"},"requests":{"cpu":"100m","memory":"128Mi"}},"ttlSecondsAfterFinished":86400},"bundleSecretName":"grid-ca-bundle","commonName":"grid-ca","confirmRotation":"","forceRegenerate":false,"keySecretName":"grid-ca-key","method":"builtin","provided":{"keySecretRef":""}}` | ---------------------------------------------------------------------------- |
| ca.confirmRotation | string | `""` | The service records the SHA-256 of the CA's public key in the database and refuses to start with a CA on any other key. To start a new grid on purpose, set this to the OLD fingerprint the refusal names, exactly as printed. Clear it once the new CA serves. |
| commonLabels | object | `{}` |  |
| db | object | `{"builtin":{"auth":{"database":"enrollment","existingSecretRef":"","username":"enrollment"},"image":"quay.io/sclorg/postgresql-16-c9s:20260923","imageDigest":"","pullPolicy":"IfNotPresent","pvcAnnotations":{},"resources":{"limits":{"cpu":1,"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}},"storage":"8Gi","tls":{"servingSecretName":"grid-db-serving-tls"}},"external":{"caConfigMapKey":"ca.crt","caConfigMapName":"","connectionUrlSecretKey":"DB_CONNECTION_URL","connectionUrlSecretRef":""},"type":"builtin"}` | ---------------------------------------------------------------------------- |
| enrollment | object | `{"affinity":{},"authz":"kube","certLifetimeSecs":"","csrRecord":{"enabled":true,"policy":{"enabled":true},"signerName":"grid.praxis.fast/site"},"enrollmentAdmins":{"subjects":[]},"gridAdminTokens":{"existingSecretRef":"","generate":true},"gridAdmins":{"serviceAccount":{"create":false,"name":"grid-admin"},"subjects":[]},"inviteSecrets":{"namespace":""},"listenAddr":"0.0.0.0:8443","nodeSelector":{},"podSecurityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"replicaCount":1,"resources":{"limits":{"cpu":1,"memory":"512Mi"},"requests":{"cpu":"100m","memory":"256Mi"}},"rotation":{"enabled":true},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true},"service":{"annotations":{},"loadBalancerIP":"","loadBalancerSourceRanges":[],"type":""},"serviceAccount":{"create":true,"name":""},"tokenAudience":"grid-enrollment","tolerations":[]}` | ---------------------------------------------------------------------------- |
| enrollment.rotation.enabled | bool | `true` | Sites rotate their identity here with their current certificate over mutual TLS. A reencrypt Route drops that certificate, so the render refuses reencrypt while this is on. false refuses every rotation (503 rotation_disabled) for the whole grid; issued identities stay valid until they expire. |
| enrollment.service.loadBalancerSourceRanges | list | `[]` | CIDRs allowed to reach the endpoint, for a LoadBalancer. Empty accepts every address the load balancer is reachable from, which for an internet-facing one is the internet. The endpoint holds the Grid CA and mints identities, so narrowing this is worth the bookkeeping even though a token is still required.  It has to cover every site for the life of the grid, not just while one joins: sites rotate their identity through this same endpoint while enrollment.rotation.enabled, and whoever mints or revokes tokens reaches it too. Sites arrive from the address they egress on, so on a cloud that is each site's NAT address, and a site whose NAT address changes drops off the list silently. Nothing fails at the time; the site stops rotating and its identity expires at enrollment.certLifetimeSecs, 180 days by default, so the mistake surfaces months later. Keep it in step with the grid's membership, or leave it empty and put the restriction in front of the endpoint. |
| external | object | `{"certManager":{"ca":{"bootstrapIssuerName":"grid-root-selfsigned","certificateName":"grid-root-ca","commonName":"grid-root-ca","durationHours":87600,"mode":"Existing","renewBeforeHours":8760,"secretName":"grid-ca-key"},"certificate":{"durationHours":4320,"renewBeforeHours":1440},"enabled":false,"issuer":{"create":false,"group":"cert-manager.io","kind":"Issuer","name":"grid-ca"}},"delivery":{"caSecretName":"grid-ca","clusterSet":"default","createClusterSetBinding":true,"enabled":false,"identitySecretName":"grid-site-identity","includeLocalCluster":false,"namespace":""},"sites":{},"trustBundleSecretKey":"ca.crt","trustBundleSecretRef":""}` | External identities and optional cert-manager issuance, with managed-cluster delivery. |
| external.certManager.ca.mode | string | `"Existing"` | Generate is only for a new grid; Existing never writes the CA Secret. |
| external.certManager.enabled | bool | `false` | Optional integration; cert-manager must already be installed. |
| external.certManager.issuer.create | bool | `false` | False references an existing issuer; true creates a namespaced CA Issuer. |
| external.delivery.includeLocalCluster | bool | `false` | Permit delivery to the local cluster, using the same flow as other members. |
| external.sites | object | `{}` | Site names mapped to secretName, optional dnsNames, and optional managed cluster. |
| external.trustBundleSecretRef | string | `""` | Public trust bundle for externally supplied identities; never a signing key. |
| fullnameOverride | string | `""` |  |
| grid | object | `{"membership":{"source":"Swim"}}` | Grid-wide settings shared with the other grid charts. |
| grid.membership.source | string | `"Swim"` | Where sites learn their members, Swim or Local, as the grid-operator chart's grid.membership.source. Local creates and delivers no SWIM key. |
| gridIdentity | object | `{"configMapName":"grid-bootstrap-state","enabled":false}` | Persist grid identity once during bootstrap, separately from CA issuance. |
| gridIdentity.configMapName | string | `"grid-bootstrap-state"` | Pre-create this ConfigMap with an existing grid's gridId to keep that ID. |
| host | string | `""` | The enrollment name sites connect to. It joins the serving cert names and is the default route.host. |
| hubSite.caSecretName | string | `"grid-ca"` | Secret the grid CA is written to beside it. |
| hubSite.identitySecretName | string | `"grid-site-identity"` | Secret the site identity is written to. |
| hubSite.name | string | `""` | Hub site name. Empty disables it. Must not also be invited. |
| hubSite.namespace | string | `""` | Namespace of the hub's grid operator, where its identity Secrets go. Required when hubSite.name is set, with no default: it is grid or grid-system under a Helm install and odh-ai-grid or redhat-ai-grid under a platform install, which derives it from the applications namespace, so any default would deliver the hub's identity where nothing reads it on some install path. A platform namespace is refused. Must exist before install: the chart does not create it. |
| hubSite.seedSecretName | string | `"grid-reserved-seeds"` | Secret, in this namespace, for the seed that registers the hub's key so it can rotate. Bootstrap signs it with the CA key and the service applies only what verifies. A Secret, so replaying an old seed needs the Secret access that already reads the CA key. |
| hubSite.swimKeySecretName | string | `"grid-swim-key"` | Secret for the grid's SWIM key, created once here and in hubSite.namespace. Empty skips it. |
| image.digest | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"ghcr.io/praxis-proxy/grid-enrollment"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| initResources | object | `{"limits":{"cpu":"200m","memory":"128Mi"},"requests":{"cpu":"10m","memory":"32Mi"}}` | Resource budget for database readiness and TLS permission init containers. |
| invitePolicy | object | `{"clusterSet":"default","enabled":false,"namespace":""}` | Governance Policy delivering each invited site its token, the CA bundle and the gossip key. The site names come from `invites`, so they are not restated here. |
| invitePolicy.clusterSet | string | `"default"` | ManagedClusterSet the sites belong to. The binding is named for it. |
| invitePolicy.enabled | bool | `false` | Render the policy. Requires governance policy APIs on the hub and registered member clusters. |
| invitePolicy.namespace | string | `""` | Namespace on each site that its operator reads the Secrets from. Required when the policy is enabled, with no default: the grid operator's namespace is grid or grid-system under a Helm install and odh-ai-grid or redhat-ai-grid under a platform install, which derives it from the applications namespace, so any default would deliver every Secret where nothing reads it on some install path. A platform namespace is refused. |
| loadBalancerScope | string | `"internal"` | Reach of the enrollment load balancer on a cloud platform. `internal` keeps it on the cluster's private network, so sites need private connectivity between them. `external` makes it internet-facing. AWS sets the scope only when a load balancer is created: changing it means recreating the Service. |
| log | object | `{"filter":"","level":"info"}` | Logging, rendered as RUST_LOG. |
| log.filter | string | `""` | Full RUST_LOG directive, such as "info,enrollment=debug". When set, it replaces level. |
| log.level | string | `"info"` | Level for every module: error, warn, info, debug, or trace. |
| managedClusters | object | `{"clusterLabel":"grid.praxis.fast/member","clusterLabelValue":"true","clusterSet":"default","createClusterSetBinding":true,"enabled":false,"gatewayName":"grid-gateway","hubClusterName":"local-cluster","identitySecretPrefix":"grid-site-","networkName":"grid","workName":"grid-site-observer"}` | Bootstrap managed-cluster discovery, GridSite watches and peer distribution. Requires managed-cluster APIs and external mode. |
| managedClusters.createClusterSetBinding | bool | `true` | Bootstrap creates one shared binding unless another release owns it. |
| managedClusters.gatewayName | string | `"grid-gateway"` | Per-cluster gateway referenced by the enrolled GridNetwork; empty omits it. |
| managedClusters.hubClusterName | string | `"local-cluster"` | The hub must be registered with the policy add-on so it can reconcile dynamically generated Certificates, observers and their RBAC. |
| mode | string | `"service"` | Identity lifecycle backend: service runs the enrollment API and bootstrap; external consumes identity Secrets supplied by another issuer or PKI. |
| nameOverride | string | `""` |  |
| networkPolicy | object | `{"enabled":true,"from":[],"routerNamespaceSelector":{"matchLabels":{"network.openshift.io/policy-group":"ingress"}}}` | Restrict enrollment and database ingress. Add explicit clients for direct access. |
| networkPolicy.from | list | `[]` | Additional NetworkPolicyPeer entries for the enrollment HTTPS listener. |
| networkPolicy.routerNamespaceSelector | object | `{"matchLabels":{"network.openshift.io/policy-group":"ingress"}}` | Router namespaces allowed when the enrollment Route is enabled. |
| platform | string | `""` | Cloud whose load balancer settings LoadBalancer Services get: `aws` (an NLB, since the default carries no UDP), `azure`, `gcp`, or `any` for all three. Each cloud reads only its own keys, so `any` suits a render that runs on every cloud. |
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

