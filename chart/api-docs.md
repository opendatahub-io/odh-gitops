# odh-rhoai-chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.2.0](https://img.shields.io/badge/AppVersion-3.2.0-informational?style=flat-square)

A Helm chart for installing ODH/RHOAI dependencies and component configurations

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| components.aipipelines | object | `{"dependencies":{},"dsc":{"managementState":"Managed"}}` | AI Pipelines component |
| components.aipipelines.dependencies | object | `{}` | Dependencies required by AI Pipelines |
| components.aipipelines.dsc | object | `{"managementState":"Managed"}` | DSC configuration for AI Pipelines |
| components.aipipelines.dsc.managementState | string | `"Managed"` | Management state for AI Pipelines (Managed or Removed) |
| components.feastoperator | object | `{"managementState":"Managed"}` | Feast Operator component |
| components.feastoperator.managementState | string | `"Managed"` | Management state for Feast Operator (Managed or Removed) |
| components.kserve | object | `{"dependencies":{"certManager":true,"customMetricsAutoscaler":true,"jobSet":true,"leaderWorkerSet":true,"rhcl":true},"dsc":{"managementState":"Managed","nim":{"managementState":"Managed"},"rawDeploymentServiceConfig":"Headless"}}` | KServe model serving component |
| components.kserve.dependencies | object | `{"certManager":true,"customMetricsAutoscaler":true,"jobSet":true,"leaderWorkerSet":true,"rhcl":true}` | Dependencies required by KServe (set to false to disable) |
| components.kserve.dsc | object | `{"managementState":"Managed","nim":{"managementState":"Managed"},"rawDeploymentServiceConfig":"Headless"}` | DSC configuration for KServe |
| components.kserve.dsc.managementState | string | `"Managed"` | Management state for KServe (Managed or Removed) |
| components.kserve.dsc.nim | object | `{"managementState":"Managed"}` | Enables NVIDIA NIM integration |
| components.kserve.dsc.nim.managementState | string | `"Managed"` | Management state for NIM (Managed or Removed) |
| components.kserve.dsc.rawDeploymentServiceConfig | string | `"Headless"` | Raw deployment service config for KServe (Headless or Headed) |
| components.kueue | object | `{"dependencies":{"certManager":true,"kueue":true},"dsc":{"managementState":"Unmanaged"}}` | Kueue job queuing component |
| components.kueue.dependencies | object | `{"certManager":true,"kueue":true}` | Dependencies required by Kueue |
| components.kueue.dsc | object | `{"managementState":"Unmanaged"}` | DSC configuration for Kueue |
| components.kueue.dsc.managementState | string | `"Unmanaged"` | Management state for Kueue (Unmanaged or Removed) |
| components.modelregistry | object | `{"defaults":{"odh":{"registriesNamespace":"odh-model-registry"},"rhoai":{"registriesNamespace":"rhoai-model-registries"}},"dependencies":{},"dsc":{"managementState":"Managed","registriesNamespace":null}}` | Model Registry component |
| components.modelregistry.defaults | object | `{"odh":{"registriesNamespace":"odh-model-registry"},"rhoai":{"registriesNamespace":"rhoai-model-registries"}}` | Operator-type-specific defaults for dsc fields |
| components.modelregistry.dependencies | object | `{}` | Dependencies required by Model Registry |
| components.modelregistry.dsc | object | `{"managementState":"Managed","registriesNamespace":null}` | DSC configuration for Model Registry |
| components.modelregistry.dsc.managementState | string | `"Managed"` | Management state for Model Registry (Managed or Removed) |
| components.modelregistry.dsc.registriesNamespace | string | `nil` | Registries namespace for Model Registry (overrides defaults) |
| dependencies.certManager | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable-v1","name":"openshift-cert-manager-operator","namespace":"cert-manager-operator"}}` | Cert Manager operator |
| dependencies.certManager.dependencies | object | `{}` | Dependencies required by cert-manager |
| dependencies.certManager.enabled | string | `"auto"` | Enable cert-manager: auto (if needed), true (always), false (never) |
| dependencies.clusterObservability | object | `{"dependencies":{"opentelemetry":true},"enabled":"auto","olm":{"channel":"stable","name":"cluster-observability-operator","namespace":"openshift-cluster-observability-operator"}}` | Cluster Observability operator |
| dependencies.clusterObservability.dependencies | object | `{"opentelemetry":true}` | Dependencies required by cluster-observability |
| dependencies.clusterObservability.enabled | string | `"auto"` | Enable cluster-observability: auto (if needed), true (always), false (never) |
| dependencies.customMetricsAutoscaler | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable","name":"openshift-custom-metrics-autoscaler-operator","namespace":"openshift-keda"}}` | Custom Metrics Autoscaler (KEDA) operator |
| dependencies.customMetricsAutoscaler.dependencies | object | `{}` | Dependencies required by custom-metrics-autoscaler |
| dependencies.customMetricsAutoscaler.enabled | string | `"auto"` | Enable custom-metrics-autoscaler: auto (if needed), true (always), false (never) |
| dependencies.jobSet | object | `{"config":{"spec":{"logLevel":"Normal","operatorLogLevel":"Normal"}},"dependencies":{},"enabled":"auto","olm":{"channel":"tech-preview-v0.1","name":"job-set","namespace":"openshift-jobset-operator","targetNamespaces":["openshift-jobset-operator"]}}` | Job Set operator |
| dependencies.jobSet.config.spec | object | `{"logLevel":"Normal","operatorLogLevel":"Normal"}` | JobSetOperator CR spec (user can add any fields supported by the CR) |
| dependencies.jobSet.dependencies | object | `{}` | Dependencies required by job-set |
| dependencies.jobSet.enabled | string | `"auto"` | Enable job-set: auto (if needed), true (always), false (never) |
| dependencies.kueue | object | `{"config":{"spec":{"config":{"integrations":{"frameworks":["Deployment","Pod","PyTorchJob","RayCluster","RayJob","StatefulSet","TrainJob"]}},"managementState":"Managed"}},"dependencies":{"certManager":true},"enabled":"auto","olm":{"channel":"stable-v1.2","name":"kueue-operator","namespace":"openshift-kueue-operator"}}` | Kueue operator |
| dependencies.kueue.config.spec | object | `{"config":{"integrations":{"frameworks":["Deployment","Pod","PyTorchJob","RayCluster","RayJob","StatefulSet","TrainJob"]}},"managementState":"Managed"}` | Kueue CR spec (user can add any fields) |
| dependencies.kueue.dependencies | object | `{"certManager":true}` | Dependencies required by kueue |
| dependencies.kueue.enabled | string | `"auto"` | Enable kueue: auto (if needed), true (always), false (never) |
| dependencies.leaderWorkerSet | object | `{"config":{"spec":{"logLevel":"Normal","managementState":"Managed","operatorLogLevel":"Normal"}},"dependencies":{"certManager":true},"enabled":"auto","olm":{"channel":"stable-v1.0","name":"leader-worker-set","namespace":"openshift-lws-operator","targetNamespaces":["openshift-lws-operator"]}}` | Leader Worker Set operator |
| dependencies.leaderWorkerSet.config.spec | object | `{"logLevel":"Normal","managementState":"Managed","operatorLogLevel":"Normal"}` | LeaderWorkerSetOperator CR spec |
| dependencies.leaderWorkerSet.dependencies | object | `{"certManager":true}` | Dependencies required by leader-worker-set |
| dependencies.leaderWorkerSet.enabled | string | `"auto"` | Enable leader-worker-set: auto (if needed), true (always), false (never) |
| dependencies.opentelemetry | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable","name":"opentelemetry-product","namespace":"openshift-opentelemetry-operator"}}` | OpenTelemetry operator |
| dependencies.opentelemetry.dependencies | object | `{}` | Dependencies required by opentelemetry |
| dependencies.opentelemetry.enabled | string | `"auto"` | Enable opentelemetry: auto (if needed), true (always), false (never) |
| dependencies.rhcl | object | `{"config":{"authorinoSpec":{"clusterWide":true,"listener":{"tls":{"certSecretRef":{"name":"authorino-server-cert"},"enabled":true}},"oidcServer":{"tls":{"enabled":false}},"replicas":1},"spec":{},"tlsEnabled":false},"dependencies":{"certManager":true,"leaderWorkerSet":true},"enabled":"auto","olm":{"channel":"stable","name":"rhcl-operator","namespace":"kuadrant-system"}}` | RHCL (Kuadrant) operator |
| dependencies.rhcl.config.authorinoSpec | object | `{"clusterWide":true,"listener":{"tls":{"certSecretRef":{"name":"authorino-server-cert"},"enabled":true}},"oidcServer":{"tls":{"enabled":false}},"replicas":1}` | Authorino CR spec (only created if tlsEnabled: true) |
| dependencies.rhcl.config.spec | object | `{}` | Kuadrant CR spec (user can add any fields) |
| dependencies.rhcl.config.tlsEnabled | bool | `false` | Enable Authorino TLS configuration |
| dependencies.rhcl.dependencies | object | `{"certManager":true,"leaderWorkerSet":true}` | Dependencies required by rhcl |
| dependencies.rhcl.enabled | string | `"auto"` | Enable rhcl: auto (if needed), true (always), false (never) |
| dependencies.tempo | object | `{"dependencies":{"opentelemetry":true},"enabled":"auto","olm":{"channel":"stable","name":"tempo-product","namespace":"openshift-tempo-operator"}}` | Tempo operator |
| dependencies.tempo.dependencies | object | `{"opentelemetry":true}` | Dependencies required by tempo |
| dependencies.tempo.enabled | string | `"auto"` | Enable tempo: auto (if needed), true (always), false (never) |
| global.installationType | string | `"olm"` | Installation type for dependencies (currently only olm is supported) |
| global.labels | object | `{}` | Common labels applied to all resources |
| global.olm.installPlanApproval | string | `"Automatic"` | Install plan approval mode (Automatic or Manual) |
| global.olm.source | string | `"redhat-operators"` | Default catalog source for OLM subscriptions |
| global.olm.sourceNamespace | string | `"openshift-marketplace"` | Namespace of the catalog source |
| global.skipCrdCheck | bool | `false` | Skip CRD existence check - render all CRs regardless. Set to true for ArgoCD or when running helm multiple times |
| operator.enabled | bool | `true` | Enable operator installation |
| operator.odh | object | `{"applicationsNamespace":"opendatahub","monitoringNamespace":"opendatahub","olm":{"channel":"fast-3","name":"opendatahub-operator","namespace":"opendatahub-operator-system","source":"community-operators"}}` | ODH operator settings |
| operator.rhoai | object | `{"applicationsNamespace":"redhat-ods-applications","monitoringNamespace":"redhat-ods-monitoring","olm":{"channel":"fast-3.x","name":"rhods-operator","namespace":"redhat-ods-operator","source":"redhat-operators"}}` | RHOAI operator settings |
| operator.type | string | `"odh"` | Operator type: odh (Open Data Hub) or rhoai (Red Hat OpenShift AI) |

