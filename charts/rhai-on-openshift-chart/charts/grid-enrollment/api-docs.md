# grid-enrollment

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: v0.1.0](https://img.shields.io/badge/AppVersion-v0.1.0-informational?style=flat-square)

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
| ca | object | `{"bootstrap":{"resources":{},"ttlSecondsAfterFinished":86400},"bundleSecretName":"grid-ca-bundle","commonName":"grid-ca","forceRegenerate":false,"keySecretName":"grid-ca-key","method":"builtin","provided":{"keySecretRef":""}}` | ---------------------------------------------------------------------------- |
| commonLabels | object | `{}` |  |
| db | object | `{"builtin":{"auth":{"database":"enrollment","existingSecretRef":"","username":"enrollment"},"image":"quay.io/sclorg/postgresql-16-c9s:20260923","imageDigest":"","pullPolicy":"IfNotPresent","resources":{},"storage":"8Gi","tls":{"servingSecretName":"grid-db-serving-tls"}},"external":{"caConfigMapKey":"ca.crt","caConfigMapName":"","connectionUrlSecretKey":"DB_CONNECTION_URL","connectionUrlSecretRef":""},"type":"builtin"}` | ---------------------------------------------------------------------------- |
| enrollment | object | `{"affinity":{},"authz":"kube","certLifetimeSecs":"","gridAdminTokens":{"existingSecretRef":"","generate":true},"gridAdmins":{"serviceAccount":{"create":false,"name":"grid-admin"},"subjects":[]},"listenAddr":"0.0.0.0:8443","nodeSelector":{},"podSecurityContext":{"runAsNonRoot":true,"seccompProfile":{"type":"RuntimeDefault"}},"replicaCount":1,"resources":{},"securityContext":{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true},"service":{"loadBalancerIP":"","type":""},"serviceAccount":{"create":true,"name":""},"tokenAudience":"grid-enrollment","tolerations":[]}` | ---------------------------------------------------------------------------- |
| fullnameOverride | string | `""` |  |
| host | string | `""` | The enrollment name sites connect to. It joins the serving cert names and is the default route.host. |
| image.digest | string | `""` |  |
| image.pullPolicy | string | `"IfNotPresent"` |  |
| image.repository | string | `"quay.io/praxis-proxy/grid-enrollment"` |  |
| image.tag | string | `""` |  |
| imagePullSecrets | list | `[]` |  |
| nameOverride | string | `""` |  |
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

