# ODH and RHOAI Chart

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.2.0](https://img.shields.io/badge/AppVersion-3.2.0-informational?style=flat-square)

A Helm chart for installing ODH/RHOAI dependencies and component configurations

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| AI Core Platform Team |  |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| components.aipipelines.managementState | string | `"Removed"` |  |
| components.kserve.managementState | string | `"Managed"` |  |
| components.kueue.managementState | string | `"Removed"` |  |
| dependencies.certManager.enabled | string | `"auto"` |  |
| dependencies.certManager.olm.channel | string | `"stable-v1"` |  |
| dependencies.certManager.olm.name | string | `"openshift-cert-manager-operator"` |  |
| dependencies.certManager.olm.namespace | string | `"cert-manager-operator"` |  |
| dependencies.clusterObservability.enabled | bool | `false` |  |
| dependencies.clusterObservability.olm.channel | string | `"stable"` |  |
| dependencies.clusterObservability.olm.name | string | `"cluster-observability-operator"` |  |
| dependencies.clusterObservability.olm.namespace | string | `"openshift-cluster-observability-operator"` |  |
| dependencies.customMetricsAutoscaler.enabled | bool | `false` |  |
| dependencies.customMetricsAutoscaler.olm.channel | string | `"stable"` |  |
| dependencies.customMetricsAutoscaler.olm.name | string | `"openshift-custom-metrics-autoscaler-operator"` |  |
| dependencies.customMetricsAutoscaler.olm.namespace | string | `"openshift-keda"` |  |
| dependencies.jobSet.config.spec.logLevel | string | `"Normal"` |  |
| dependencies.jobSet.config.spec.operatorLogLevel | string | `"Normal"` |  |
| dependencies.jobSet.enabled | string | `"auto"` |  |
| dependencies.jobSet.olm.channel | string | `"tech-preview-v0.1"` |  |
| dependencies.jobSet.olm.name | string | `"job-set"` |  |
| dependencies.jobSet.olm.namespace | string | `"openshift-jobset-operator"` |  |
| dependencies.kueue.config.spec.config.integrations.frameworks[0] | string | `"Deployment"` |  |
| dependencies.kueue.config.spec.config.integrations.frameworks[1] | string | `"Pod"` |  |
| dependencies.kueue.config.spec.config.integrations.frameworks[2] | string | `"PyTorchJob"` |  |
| dependencies.kueue.config.spec.config.integrations.frameworks[3] | string | `"RayCluster"` |  |
| dependencies.kueue.config.spec.config.integrations.frameworks[4] | string | `"RayJob"` |  |
| dependencies.kueue.config.spec.config.integrations.frameworks[5] | string | `"StatefulSet"` |  |
| dependencies.kueue.config.spec.managementState | string | `"Managed"` |  |
| dependencies.kueue.enabled | string | `"auto"` |  |
| dependencies.kueue.olm.channel | string | `"stable-v1.1"` |  |
| dependencies.kueue.olm.name | string | `"kueue-operator"` |  |
| dependencies.kueue.olm.namespace | string | `"openshift-kueue-operator"` |  |
| dependencies.leaderWorkerSet.config.spec.logLevel | string | `"Normal"` |  |
| dependencies.leaderWorkerSet.config.spec.managementState | string | `"Managed"` |  |
| dependencies.leaderWorkerSet.config.spec.operatorLogLevel | string | `"Normal"` |  |
| dependencies.leaderWorkerSet.enabled | string | `"auto"` |  |
| dependencies.leaderWorkerSet.olm.channel | string | `"stable-v1.0"` |  |
| dependencies.leaderWorkerSet.olm.name | string | `"leader-worker-set"` |  |
| dependencies.leaderWorkerSet.olm.namespace | string | `"openshift-lws-operator"` |  |
| dependencies.opentelemetry.enabled | bool | `false` |  |
| dependencies.opentelemetry.olm.channel | string | `"stable"` |  |
| dependencies.opentelemetry.olm.name | string | `"opentelemetry-product"` |  |
| dependencies.opentelemetry.olm.namespace | string | `"openshift-opentelemetry-operator"` |  |
| dependencies.rhcl.config.authorinoSpec.clusterWide | bool | `true` |  |
| dependencies.rhcl.config.authorinoSpec.listener.tls.certSecretRef.name | string | `"authorino-server-cert"` |  |
| dependencies.rhcl.config.authorinoSpec.listener.tls.enabled | bool | `true` |  |
| dependencies.rhcl.config.authorinoSpec.oidcServer.tls.enabled | bool | `false` |  |
| dependencies.rhcl.config.authorinoSpec.replicas | int | `1` |  |
| dependencies.rhcl.config.spec | object | `{}` |  |
| dependencies.rhcl.config.tlsEnabled | bool | `false` |  |
| dependencies.rhcl.enabled | string | `"auto"` |  |
| dependencies.rhcl.olm.channel | string | `"stable"` |  |
| dependencies.rhcl.olm.name | string | `"rhcl-operator"` |  |
| dependencies.rhcl.olm.namespace | string | `"kuadrant-system"` |  |
| dependencies.tempo.enabled | bool | `false` |  |
| dependencies.tempo.olm.channel | string | `"stable"` |  |
| dependencies.tempo.olm.name | string | `"tempo-product"` |  |
| dependencies.tempo.olm.namespace | string | `"openshift-tempo-operator"` |  |
| global.installationType | string | `"olm"` |  |
| global.labels | object | `{}` |  |
| global.olm.installPlanApproval | string | `"Automatic"` |  |
| global.olm.source | string | `"redhat-operators"` |  |
| global.olm.sourceNamespace | string | `"openshift-marketplace"` |  |
| operator.enabled | bool | `true` |  |
| operator.odh.olm.channel | string | `"fast-3"` |  |
| operator.odh.olm.name | string | `"opendatahub-operator"` |  |
| operator.odh.olm.namespace | string | `"openshift-operators"` |  |
| operator.odh.olm.source | string | `"community-operators"` |  |
| operator.rhoai.olm.channel | string | `"fast-3.x"` |  |
| operator.rhoai.olm.name | string | `"rhods-operator"` |  |
| operator.rhoai.olm.namespace | string | `"redhat-ods-operator"` |  |
| operator.rhoai.olm.source | string | `"redhat-operators"` |  |
| operator.type | string | `"rhoai"` |  |

