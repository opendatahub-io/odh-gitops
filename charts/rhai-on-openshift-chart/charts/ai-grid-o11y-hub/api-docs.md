# ai-grid-o11y-hub

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

Central LokiStack on an ACM hub that AI Grid spokes write MaaS usage logs to, with the ACM policy that configures them

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| commonLabels | object | `{}` | Labels added to every object this chart renders. |
| createNamespace | bool | `true` | Create `namespace`. Set false when it is managed elsewhere. |
| enabled | bool | `false` | Render this chart. The parent gates the subchart on the same key. |
| ingest.reader.create | bool | `false` | Create a read-only identity, for Grafana, a billing job or any other consumer that should not be able to write. Off by default: reads also work with any hub user who already holds the grant, so this is only needed for an unattended consumer. |
| ingest.reader.serviceAccountName | string | `""` | Reader ServiceAccount name. Defaults to `<lokiStack.name>-reader`. |
| ingest.writer.create | bool | `true` | Create the writer ServiceAccount, ClusterRole and binding. This is the identity every spoke presents, so without it no spoke can write. |
| ingest.writer.serviceAccountName | string | `""` | Writer ServiceAccount name. Defaults to `<lokiStack.name>-writer`. |
| lokiStack.enabled | bool | `true` | Render the store: the LokiStack, its object storage and the ingest identities. Set false to render nothing but the spoke policy, for a hub that forwards to a LokiStack this chart did not create — the endpoint is only a string, so the store may live anywhere. Everything under `objectStorage` and `ingest` is skipped with it. |
| lokiStack.limits | object | `{}` | `spec.limits`, passed through. Retention lives here and Loki keeps everything forever without it, e.g. `global: {retention: {days: 30}}`. The hub carries aggregated fleet volume, so this is a sizing decision the chart cannot make. |
| lokiStack.name | string | `"usage-logs"` | LokiStack name. It also prefixes the storage Secret, the ingest ClusterRoles and the Route the Loki operator creates, so the ingest endpoint is `https://<name>-<namespace>.apps.<hub-domain>/api/logs/v1/infrastructure/otlp`. |
| lokiStack.schemas | list | `[{"effectiveDate":"","version":"v13"}]` | Object storage schemas. `effectiveDate` must not be in the future at install time or the stack never becomes Ready, so it has no default and must be set. |
| lokiStack.size | string | `"1x.extra-small"` | Loki t-shirt size. `1x.extra-small` requests 1 CPU and 5.25Gi per ingester across three ingesters and will not schedule on a small hub; `1x.demo` carries identical ingestion limits (4 MB/s sustained, 6 MB burst, 5 MB per stream) with a single ingester and no resource requests at all, but has no redundancy and is documented by Loki as demo-only. |
| lokiStack.storageClassName | string | `"gp3-csi"` | StorageClass for the ingester, compactor and index-gateway volumes. Must be RWO. |
| lokiStack.template | object | `{}` | `spec.template`, passed through, for per-component replicas, tolerations and node placement. |
| namespace | string | `"ai-grid-o11y"` | Namespace holding the LokiStack, its storage Secret and the ingest identities. |
| objectStorage.obc.create | bool | `false` | Render an ObjectBucketClaim, for a hub with OpenShift Data Foundation. The claim's credentials are **not** copied into the storage Secret: ODF publishes them under different key names than Loki reads, and no controller translates them. See the chart README for the one command that does it. |
| objectStorage.obc.generateBucketName | string | `""` | Bucket name prefix; ODF appends a unique suffix. |
| objectStorage.obc.name | string | `""` | ObjectBucketClaim name. Defaults to `<lokiStack.name>-bucket`. |
| objectStorage.obc.storageClassName | string | `"openshift-storage.noobaa.io"` | ObjectBucketClaim StorageClass. |
| objectStorage.secret.accessKeyId | string | `""` | Access key id. |
| objectStorage.secret.accessKeySecret | string | `""` | Access key secret. |
| objectStorage.secret.bucketNames | string | `""` | Bucket name. |
| objectStorage.secret.create | bool | `false` | Render the storage Secret from the values below. Leave false and set `objectStorage.secretName` to bring your own, which is the right choice when the credentials come from a cloud credential operator. |
| objectStorage.secret.endpoint | string | `""` | S3 endpoint, e.g. `https://s3.openshift-storage.svc:443` for Multicloud Object Gateway or `https://s3.us-east-1.amazonaws.com`. |
| objectStorage.secret.region | string | `""` | Region, for endpoints that require it. |
| objectStorage.secretName | string | `""` | Name of the S3-shaped Secret the LokiStack reads. The Loki operator requires the keys `bucketnames`, `endpoint`, `access_key_id` and `access_key_secret`. |
| objectStorage.serviceCA.configMapName | string | `"openshift-service-ca-bundle"` | ConfigMap name. |
| objectStorage.serviceCA.enabled | bool | `false` | Render a service-CA ConfigMap and point `spec.storage.tls` at it. Needed when the S3 endpoint is an in-cluster Service, whose certificate the stack does not otherwise trust. An endpoint with a publicly trusted certificate needs neither. |
| spokePolicy.annotations | object | `{"policy.open-cluster-management.io/standards":"AI Grid"}` | Annotations added to the Policy, for ACM's governance catalogue. |
| spokePolicy.createNamespace | bool | `true` | Create `spokePolicy.namespace`. Set false when it is managed elsewhere. |
| spokePolicy.credentialSecretName | string | `"usage-logs-hub-credential"` | Name of the Secret in `spokePolicy.namespace` holding the writer token under key `token`. This chart does not create it, because a token is not a declarative object. ACM reads it with `fromSecret` and ships `$ocm_encrypted:` ciphertext, so the token is not replicated in clear text. |
| spokePolicy.deliverConfiguration | bool | `true` | Deliver the `usageLogs` patch to each spoke's DSCInitialization. Set false when the spoke's own install already carries that configuration: in a GitOps fleet Argo CD renders the DSCI from chart values and an ApplicationSet supplies the per-cluster attributes, so this patch would make Argo CD's `selfHeal` and this policy two writers on one object. With it off the policy delivers the token alone, and `spokePolicy.endpoint` is neither required nor read. |
| spokePolicy.deliverCredential | bool | `true` | Deliver the credential Secret to each spoke. Set false when the token reaches the spokes another way, such as External Secrets, and this policy should only set the configuration that names it. |
| spokePolicy.enabled | bool | `false` | Render the Placement and Policy. Needs ACM on this cluster and the spokes imported. The chart renders no ACM install, which is the established pattern in this repo. |
| spokePolicy.endpoint | string | `""` | The ingest endpoint spokes write to: the LokiStack Route host plus the tenant path and `/otlp`. The collector's otlphttp exporter appends `/v1/logs` itself, so do not include it. Not derived from the store this chart renders, because the Route's domain is the cluster's and may carry an infrastructure-specific prefix — read it with `oc get route <stack> -n <namespace>` after the LokiStack is Ready. Required when delivering configuration. Must have a hostname and the exact `/api/logs/v1/infrastructure/otlp` path, without a query or fragment. Not read when `deliverConfiguration` is false. |
| spokePolicy.name | string | `"ai-grid-maas-remote-usage-logs"` | Policy and ConfigurationPolicy name. |
| spokePolicy.namespace | string | `"ai-grid-policies"` | Namespace on this hub holding the Placement, Policy and the credential the Policy reads. ACM evaluates Policies per namespace, so it must carry a ManagedClusterSetBinding. |
| spokePolicy.placement.clusterSet | string | `"default"` | ManagedClusterSet the Placement selects from. A ManagedClusterSetBinding for it is rendered in `spokePolicy.namespace`. |
| spokePolicy.placement.createClusterSetBinding | bool | `true` | Create the ManagedClusterSetBinding. Set false when another release already binds this set in this namespace; two bindings for one set in one namespace conflict. |
| spokePolicy.placement.excludeLocalCluster | bool | `true` | Exclude the hub itself, which carries no MaaS, by requiring the `local-cluster` label to be absent. |
| spokePolicy.placement.matchLabels | object | `{"ai-grid.redhat.com/maas":"true"}` | Labels a ManagedCluster must carry to receive the policy. The default selects on "runs MaaS" rather than "is an AI Grid spoke": those are different predicates, and a cluster with the grid label but no MaaS install would make this policy permanently NonCompliant there. Nothing sets either label automatically. |
| spokePolicy.placement.name | string | `"ai-grid-maas-spokes"` | Placement and PlacementBinding name. |
| spokePolicy.pruneObjectBehavior | string | `"DeleteIfCreated"` | What happens to the delivered objects when the Policy is deleted. `DeleteIfCreated` removes those this policy created and leaves pre-existing ones; `DeleteAll` removes both; `None` orphans everything. Changes to a pre-existing DSCI are not undone: remove its forwarding references before deleting a policy-created credential Secret. See the README teardown sequence. |
| spokePolicy.remediationAction | string | `"enforce"` | `enforce` creates and repairs the delivered objects; `inform` only reports drift without changing anything, which is the safe way to preview a rollout. |
| spokePolicy.severity | string | `"medium"` | Policy severity, surfaced in ACM's governance view. |
| spokePolicy.spoke.attributes | object | `{"cluster_id":"{{ (lookup \"cluster.open-cluster-management.io/v1alpha1\" \"ClusterClaim\" \"\" \"id.k8s.io\").spec.value }}","cluster_name":"{{hub .ManagedClusterName hub}}"}` | Per-spoke resource attributes stamped on the forwarded copy, so records can be attributed to the cluster that produced them. The values are ACM templates resolved per cluster, not Helm templates: `cluster_name` comes from the Placement decision on the hub, `cluster_id` from a ClusterClaim lookup on the managed cluster itself. A spoke outside ACM has neither and must be configured directly. |
| spokePolicy.spoke.credentialSecretName | string | `"hub-usage-logs-auth"` | Name of the credential Secret created on the spoke. It must match `Monitoring.spec.usageLogs.credentialSecret`, which the same policy sets. Distinct from `spokePolicy.credentialSecretName`, which names the Secret on this hub that the policy reads the token from. |
| spokePolicy.spoke.dsciName | string | `"default-dsci"` | Name of the DSCInitialization the policy patches. |
| spokePolicy.spoke.exporterName | string | `"otlphttp/hub"` | Exporter name under `usageLogs.exporters`. `otlphttp/loki` is reserved for the spoke-local write and is rejected. |
| spokePolicy.spoke.monitoringNamespace | string | `"redhat-ods-monitoring"` | Namespace on the spoke that the usage-log collector reads its credential from. This is the operator's monitoring namespace: `redhat-ods-monitoring` for RHOAI, `opendatahub` for ODH. |
| spokePolicy.spoke.size | string | `""` | LokiStack t-shirt size for a spoke that also keeps a usage-log store of its own, set through the same patch. Unrelated to `lokiStack.size` here. A forwarding spoke has no such store and ignores it, so the empty default — which leaves the spoke's value alone — is what nearly every fleet wants. |

