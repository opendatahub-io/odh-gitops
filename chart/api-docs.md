# odh-rhoai-chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.2.0](https://img.shields.io/badge/AppVersion-3.2.0-informational?style=flat-square)

A Helm chart for installing ODH/RHOAI dependencies and component configurations

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| components.aipipelines | object | `{"managementState":"Managed"}` | AI Pipelines component |
| components.aipipelines.managementState | string | `"Managed"` | Management state for AI Pipelines (Managed or Removed) |
| components.kserve | object | `{"managementState":"Managed"}` | KServe model serving component |
| components.kserve.managementState | string | `"Managed"` | Management state for KServe (Managed or Removed). Auto-enables: certManager, leaderWorkerSet, jobSet, rhcl |
| components.kueue | object | `{"managementState":"Unmanaged"}` | Kueue job queuing component |
| components.kueue.managementState | string | `"Unmanaged"` | Management state for Kueue (Unmanaged or Removed). Auto-enables: kueue operator |
| dependencies.certManager | object | `{"enabled":"auto","olm":{"channel":"stable-v1","name":"openshift-cert-manager-operator","namespace":"cert-manager-operator"}}` | Cert Manager operator |
| dependencies.certManager.enabled | string | `"auto"` | Enable cert-manager: auto (if needed), true (always), false (never) |
| dependencies.clusterObservability | object | `{"enabled":"auto","olm":{"channel":"stable","name":"cluster-observability-operator","namespace":"openshift-cluster-observability-operator"}}` | Cluster Observability operator |
| dependencies.clusterObservability.enabled | string | `"auto"` | Enable cluster-observability: auto (if needed), true (always), false (never) |
| dependencies.customMetricsAutoscaler | object | `{"enabled":"auto","olm":{"channel":"stable","name":"openshift-custom-metrics-autoscaler-operator","namespace":"openshift-keda"}}` | Custom Metrics Autoscaler (KEDA) operator |
| dependencies.customMetricsAutoscaler.enabled | string | `"auto"` | Enable custom-metrics-autoscaler: auto (if needed), true (always), false (never) |
| dependencies.jobSet | object | `{"config":{"spec":{"logLevel":"Normal","operatorLogLevel":"Normal"}},"enabled":"auto","olm":{"channel":"tech-preview-v0.1","name":"job-set","namespace":"openshift-jobset-operator","targetNamespaces":["openshift-jobset-operator"]}}` | Job Set operator |
| dependencies.jobSet.config.spec | object | `{"logLevel":"Normal","operatorLogLevel":"Normal"}` | JobSetOperator CR spec |
| dependencies.jobSet.enabled | string | `"auto"` | Enable job-set: auto (if needed), true (always), false (never) |
| dependencies.kueue | object | `{"config":{"spec":{"config":{"integrations":{"frameworks":["Deployment","Pod","PyTorchJob","RayCluster","RayJob","StatefulSet"]}},"managementState":"Managed"}},"enabled":"auto","olm":{"channel":"stable-v1.1","name":"kueue-operator","namespace":"openshift-kueue-operator"}}` | Kueue operator |
| dependencies.kueue.config.spec | object | `{"config":{"integrations":{"frameworks":["Deployment","Pod","PyTorchJob","RayCluster","RayJob","StatefulSet"]}},"managementState":"Managed"}` | Kueue CR spec (user can add any fields) |
| dependencies.kueue.enabled | string | `"auto"` | Enable kueue: auto (if needed), true (always), false (never) |
| dependencies.leaderWorkerSet | object | `{"config":{"spec":{"logLevel":"Normal","managementState":"Managed","operatorLogLevel":"Normal"}},"enabled":"auto","olm":{"channel":"stable-v1.0","name":"leader-worker-set","namespace":"openshift-lws-operator","targetNamespaces":["openshift-lws-operator"]}}` | Leader Worker Set operator |
| dependencies.leaderWorkerSet.config.spec | object | `{"logLevel":"Normal","managementState":"Managed","operatorLogLevel":"Normal"}` | LeaderWorkerSetOperator CR spec |
| dependencies.leaderWorkerSet.enabled | string | `"auto"` | Enable leader-worker-set: auto (if needed), true (always), false (never) |
| dependencies.opentelemetry | object | `{"enabled":"auto","olm":{"channel":"stable","name":"opentelemetry-product","namespace":"openshift-opentelemetry-operator"}}` | OpenTelemetry operator |
| dependencies.opentelemetry.enabled | string | `"auto"` | Enable opentelemetry: auto (if needed), true (always), false (never) |
| dependencies.rhcl | object | `{"config":{"authorinoSpec":{"clusterWide":true,"listener":{"tls":{"certSecretRef":{"name":"authorino-server-cert"},"enabled":true}},"oidcServer":{"tls":{"enabled":false}},"replicas":1},"spec":{},"tlsEnabled":false},"enabled":"auto","olm":{"channel":"stable","name":"rhcl-operator","namespace":"kuadrant-system"}}` | RHCL (Kuadrant) operator |
| dependencies.rhcl.config.authorinoSpec | object | `{"clusterWide":true,"listener":{"tls":{"certSecretRef":{"name":"authorino-server-cert"},"enabled":true}},"oidcServer":{"tls":{"enabled":false}},"replicas":1}` | Authorino CR spec (only created if tlsEnabled: true) |
| dependencies.rhcl.config.spec | object | `{}` | Kuadrant CR spec (user can add any fields) |
| dependencies.rhcl.config.tlsEnabled | bool | `false` | Enable Authorino TLS configuration |
| dependencies.rhcl.enabled | string | `"auto"` | Enable rhcl: auto (if needed), true (always), false (never) |
| dependencies.tempo | object | `{"enabled":"auto","olm":{"channel":"stable","name":"tempo-product","namespace":"openshift-tempo-operator"}}` | Tempo operator |
| dependencies.tempo.enabled | string | `"auto"` | Enable tempo: auto (if needed), true (always), false (never) |
| global.installationType | string | `"olm"` | Installation type for dependencies (currently only olm is supported) |
| global.labels | object | `{}` | Common labels applied to all resources |
| global.olm.installPlanApproval | string | `"Automatic"` | Install plan approval mode (Automatic or Manual) |
| global.olm.source | string | `"redhat-operators"` | Default catalog source for OLM subscriptions |
| global.olm.sourceNamespace | string | `"openshift-marketplace"` | Namespace of the catalog source |
| global.skipCrdCheck | bool | `false` | Skip CRD existence check - render all CRs regardless. Set to true for ArgoCD or when running helm multiple times |
| operator.enabled | bool | `true` | Enable operator installation |
| operator.odh | object | `{"olm":{"channel":"fast-3","name":"opendatahub-operator","namespace":"openshift-operators","source":"community-operators"}}` | ODH operator settings |
| operator.rhoai | object | `{"olm":{"channel":"fast-3.x","name":"rhods-operator","namespace":"redhat-ods-operator","source":"redhat-operators"}}` | RHOAI operator settings |
| operator.type | string | `"rhoai"` | Operator type: odh (Open Data Hub) or rhoai (Red Hat OpenShift AI) |

