# rhai-on-openshift-chart

![Version: 3.4.0](https://img.shields.io/badge/Version-3.4.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.4.0](https://img.shields.io/badge/AppVersion-3.4.0-informational?style=flat-square)

A Helm chart for installing ODH/RHOAI dependencies and component configurations

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| components.aiHub | object | `{"defaults":{"odh":{"instancesNamespace":"odh-model-registry"},"rhoai":{"instancesNamespace":"rhoai-model-registries"}},"dependencies":{},"dsc":{"instancesNamespace":null,"managementState":null}}` | AI Hub component (Model Registry; replaces modelregistry from DSC v2) |
| components.aiHub.defaults | object | `{"odh":{"instancesNamespace":"odh-model-registry"},"rhoai":{"instancesNamespace":"rhoai-model-registries"}}` | Operator-type-specific defaults for dsc fields |
| components.aiHub.dependencies | object | `{}` | Dependencies required by AI Hub |
| components.aiHub.dsc | object | `{"instancesNamespace":null,"managementState":null}` | DSC configuration for AI Hub |
| components.aiHub.dsc.instancesNamespace | string | `nil` | Immutable in the operator while managementState is Managed. |
| components.aiHub.dsc.managementState | string | `nil` | Management state for AI Hub. Null uses profile default. |
| components.aigateway | object | `{"dependencies":{"certManager":null,"leaderWorkerSet":null,"rhcl":null},"dsc":{"batchGateway":{"managementState":null},"managementState":null,"modelsAsAService":{"managementState":null}},"modelsAsAService":{"gateway":{"annotations":{"opendatahub.io/managed":"false","security.opendatahub.io/authorino-tls-bootstrap":"true"},"create":"auto","name":"maas-default-gateway","namespace":"openshift-ingress","openshiftRoute":{"enabled":false,"gatewayParametersName":"maas-gateway-options","host":"","name":"maas-gateway-route","servingCertSecretName":"maas-gw-service-tls"},"spec":{"gatewayClassName":"maas-gateway-class","listeners":[{"allowedRoutes":{"namespaces":null},"name":"https","port":443,"protocol":"HTTPS"}]}},"gatewayClass":{"create":"auto","name":"maas-gateway-class","spec":{"controllerName":"openshift.io/gateway-controller/v1"}}}}` | AI Gateway component (manages MaaS and BatchGateway sub-components) |
| components.aigateway.dsc | object | `{"batchGateway":{"managementState":null},"managementState":null,"modelsAsAService":{"managementState":null}}` | DSC configuration for AI Gateway |
| components.aigateway.dsc.managementState | string | `nil` | Management state for AI Gateway. Null uses profile default. |
| components.aigateway.dsc.modelsAsAService | object | `{"managementState":null}` | Models as a Service sub-component (moved from kserve.modelsAsService in 3.5) |
| components.aigateway.dsc.modelsAsAService.managementState | string | `nil` | Management state for Models as a Service. Null uses profile default. |
| components.aigateway.modelsAsAService | object | `{"gateway":{"annotations":{"opendatahub.io/managed":"false","security.opendatahub.io/authorino-tls-bootstrap":"true"},"create":"auto","name":"maas-default-gateway","namespace":"openshift-ingress","openshiftRoute":{"enabled":false,"gatewayParametersName":"maas-gateway-options","host":"","name":"maas-gateway-route","servingCertSecretName":"maas-gw-service-tls"},"spec":{"gatewayClassName":"maas-gateway-class","listeners":[{"allowedRoutes":{"namespaces":null},"name":"https","port":443,"protocol":"HTTPS"}]}},"gatewayClass":{"create":"auto","name":"maas-gateway-class","spec":{"controllerName":"openshift.io/gateway-controller/v1"}}}` | Gateway and GatewayClass resources for MaaS (created independently of DSC) |
| components.aigateway.modelsAsAService.gateway | object | `{"annotations":{"opendatahub.io/managed":"false","security.opendatahub.io/authorino-tls-bootstrap":"true"},"create":"auto","name":"maas-default-gateway","namespace":"openshift-ingress","openshiftRoute":{"enabled":false,"gatewayParametersName":"maas-gateway-options","host":"","name":"maas-gateway-route","servingCertSecretName":"maas-gw-service-tls"},"spec":{"gatewayClassName":"maas-gateway-class","listeners":[{"allowedRoutes":{"namespaces":null},"name":"https","port":443,"protocol":"HTTPS"}]}}` | Gateway configuration for the LLMInferenceService. |
| components.aigateway.modelsAsAService.gateway.create | string | `"auto"` | Create the Gateway: auto (if modelsAsAService is Managed), true (always), false (never) |
| components.aigateway.modelsAsAService.gateway.openshiftRoute | object | `{"enabled":false,"gatewayParametersName":"maas-gateway-options","host":"","name":"maas-gateway-route","servingCertSecretName":"maas-gw-service-tls"}` | Optional OpenShift ClusterIP service and re-encrypt Route exposure. |
| components.aigateway.modelsAsAService.gateway.spec.listeners[0].allowedRoutes.namespaces | string | `nil` | REQUIRED: set `from` to Selector (recommended) or Same. Template will fail if not set. When using Selector, the specified labels must be applied to each target namespace. |
| components.aigateway.modelsAsAService.gatewayClass | object | `{"create":"auto","name":"maas-gateway-class","spec":{"controllerName":"openshift.io/gateway-controller/v1"}}` | GatewayClass configuration for the LLMInferenceService. |
| components.aigateway.modelsAsAService.gatewayClass.create | string | `"auto"` | Create the GatewayClass: auto (if modelsAsAService is Managed), true (always), false (never) |
| components.aipipelines | object | `{"dependencies":{},"dsc":{"managementState":null}}` | AI Pipelines component |
| components.aipipelines.dependencies | object | `{}` | Dependencies required by AI Pipelines |
| components.aipipelines.dsc.managementState | string | `nil` | Management state for AI Pipelines. Null uses profile default. |
| components.dashboard | object | `{"dependencies":{},"dsc":{"maasPortal":{"managementState":null},"standard":{"managementState":null}}}` | the core Dashboard and the MaaS Consumer Portal are managed independently) |
| components.dashboard.dependencies | object | `{}` | Dependencies required by Dashboard |
| components.dashboard.dsc | object | `{"maasPortal":{"managementState":null},"standard":{"managementState":null}}` | DSC configuration for Dashboard |
| components.dashboard.dsc.maasPortal.managementState | string | `nil` | Management state for the MaaS Consumer Portal. Null uses profile default. |
| components.dashboard.dsc.standard.managementState | string | `nil` | Management state for the core Dashboard. Null uses profile default. |
| components.data | object | `{"dependencies":{},"dsc":{"dataRegistry":{"managementState":null},"featureStore":{"managementState":null}}}` | Replaces feastoperator (featureStore) from DSC v2; dataRegistry is new in v3. |
| components.data.dependencies | object | `{}` | Dependencies required by Data |
| components.data.dsc | object | `{"dataRegistry":{"managementState":null},"featureStore":{"managementState":null}}` | DSC configuration for Data |
| components.data.dsc.dataRegistry.managementState | string | `nil` | Management state for Data Registry. Null uses profile default. |
| components.data.dsc.featureStore.managementState | string | `nil` | Management state for Feature Store. Null uses profile default. |
| components.kserve | object | `{"dependencies":{"certManager":true,"customMetricsAutoscaler":false,"jobSet":null,"leaderWorkerSet":false,"rhcl":true},"dsc":{"managementState":null,"nim":{"managementState":null},"rawDeploymentServiceConfig":"Headless"},"gateway":{"create":"auto","labels":{"istio.io/rev":"openshift-gateway"},"name":"openshift-ai-inference","namespace":"openshift-ingress","spec":{"gatewayClassName":"openshift-ai-inference","listeners":[{"allowedRoutes":{"namespaces":null},"name":"https","port":443,"protocol":"HTTPS"}]}},"gatewayClass":{"create":"auto","name":"openshift-ai-inference","spec":{"controllerName":"openshift.io/gateway-controller/v1"}}}` | KServe model serving component |
| components.kserve.dependencies | object | `{"certManager":true,"customMetricsAutoscaler":false,"jobSet":null,"leaderWorkerSet":false,"rhcl":true}` | Dependencies required by KServe (set to false to disable) |
| components.kserve.dependencies.jobSet | string | `nil` | JobSet dependency. Null uses profile default (true for default, false for rhaii). |
| components.kserve.dsc | object | `{"managementState":null,"nim":{"managementState":null},"rawDeploymentServiceConfig":"Headless"}` | DSC configuration for KServe |
| components.kserve.dsc.managementState | string | `nil` | Management state for KServe. Null uses profile default. |
| components.kserve.dsc.nim | object | `{"managementState":null}` | Enables NVIDIA NIM integration |
| components.kserve.dsc.nim.managementState | string | `nil` | Management state for NIM. Null uses profile default. |
| components.kserve.dsc.rawDeploymentServiceConfig | string | `"Headless"` | Raw deployment service config for KServe (Headless or Headed) |
| components.kserve.gateway | object | `{"create":"auto","labels":{"istio.io/rev":"openshift-gateway"},"name":"openshift-ai-inference","namespace":"openshift-ingress","spec":{"gatewayClassName":"openshift-ai-inference","listeners":[{"allowedRoutes":{"namespaces":null},"name":"https","port":443,"protocol":"HTTPS"}]}}` | Gateway configuration for KServe inference. |
| components.kserve.gateway.create | string | `"auto"` | Flag to create the Gateway (auto, true, false). If auto, it will be created if KServe is Managed. |
| components.kserve.gateway.spec.listeners[0].allowedRoutes.namespaces | string | `nil` | REQUIRED: set `from` to Selector (recommended) or Same. Template will fail if not set. When using Selector, the specified labels must be applied to each target namespace. |
| components.kserve.gatewayClass | object | `{"create":"auto","name":"openshift-ai-inference","spec":{"controllerName":"openshift.io/gateway-controller/v1"}}` | GatewayClass configuration for KServe inference |
| components.kserve.gatewayClass.create | string | `"auto"` | Create the GatewayClass: auto (if KServe is Managed), true (always), false (never) |
| components.kserve.gatewayClass.name | string | `"openshift-ai-inference"` | GatewayClass name |
| components.kserve.gatewayClass.spec | object | `{"controllerName":"openshift.io/gateway-controller/v1"}` | GatewayClass spec |
| components.kueue | object | `{"dependencies":{"certManager":true,"kueue":true},"dsc":{"defaultClusterQueueName":"default","defaultLocalQueueName":"default","managementState":null}}` | Kueue job queuing component |
| components.kueue.dependencies | object | `{"certManager":true,"kueue":true}` | Dependencies required by Kueue |
| components.kueue.dsc | object | `{"defaultClusterQueueName":"default","defaultLocalQueueName":"default","managementState":null}` | DSC configuration for Kueue |
| components.kueue.dsc.managementState | string | `nil` | Management state for Kueue. Null uses profile default. |
| components.mcplifecycleoperator | object | `{"dependencies":{},"dsc":{"managementState":null}}` | MCP Lifecycle Operator component (new in DSC v3) |
| components.mcplifecycleoperator.dependencies | object | `{}` | Dependencies required by MCP Lifecycle Operator |
| components.mcplifecycleoperator.dsc | object | `{"managementState":null}` | DSC configuration for MCP Lifecycle Operator |
| components.mcplifecycleoperator.dsc.managementState | string | `nil` | Management state for MCP Lifecycle Operator. Null uses profile default. |
| components.mlflowoperator | object | `{"dependencies":{},"dsc":{"managementState":null}}` | MLflow Operator component |
| components.mlflowoperator.dependencies | object | `{}` | Dependencies required by MLflow Operator |
| components.mlflowoperator.dsc | object | `{"managementState":null}` | DSC configuration for MLflow Operator |
| components.mlflowoperator.dsc.managementState | string | `nil` | Management state for MLflow Operator. Null uses profile default. |
| components.ogx | object | `{"dependencies":{"nfd":true,"nvidiaGPUOperator":true},"dsc":{"managementState":null}}` | OGX component |
| components.ogx.dependencies | object | `{"nfd":true,"nvidiaGPUOperator":true}` | Dependencies required by OGX |
| components.ogx.dsc | object | `{"managementState":null}` | DSC configuration for OGX |
| components.ogx.dsc.managementState | string | `nil` | Management state for OGX. Null uses profile default. |
| components.ray | object | `{"dependencies":{"certManager":true},"dsc":{"managementState":null}}` | Ray component |
| components.ray.dependencies | object | `{"certManager":true}` | Dependencies required by Ray |
| components.ray.dsc | object | `{"managementState":null}` | DSC configuration for Ray |
| components.ray.dsc.managementState | string | `nil` | Management state for Ray. Null uses profile default. |
| components.sparkoperator | object | `{"dependencies":{},"dsc":{"managementState":"Removed"}}` | Spark Operator component |
| components.sparkoperator.dependencies | object | `{}` | Dependencies required by Spark Operator |
| components.sparkoperator.dsc | object | `{"managementState":"Removed"}` | DSC configuration for Spark Operator |
| components.sparkoperator.dsc.managementState | string | `"Removed"` | Management state for Spark Operator (Managed or Removed) |
| components.trainer | object | `{"dependencies":{"certManager":true,"jobSet":true},"dsc":{"managementState":null}}` | Trainer component |
| components.trainer.dependencies | object | `{"certManager":true,"jobSet":true}` | Dependencies required by Trainer |
| components.trainer.dsc | object | `{"managementState":null}` | DSC configuration for Trainer |
| components.trainer.dsc.managementState | string | `nil` | Management state for Trainer. Null uses profile default. |
| components.trustyai | object | `{"dependencies":{},"dsc":{"eval":{"lmeval":{"permitCodeExecution":"deny","permitOnline":"deny"}},"managementState":null}}` | TrustyAI component |
| components.trustyai.dependencies | object | `{}` | Dependencies required by TrustyAI |
| components.trustyai.dsc | object | `{"eval":{"lmeval":{"permitCodeExecution":"deny","permitOnline":"deny"}},"managementState":null}` | DSC configuration for TrustyAI |
| components.trustyai.dsc.eval | object | `{"lmeval":{"permitCodeExecution":"deny","permitOnline":"deny"}}` | Evaluation configuration for TrustyAI evaluations |
| components.trustyai.dsc.managementState | string | `nil` | Management state for TrustyAI. Null uses profile default. |
| components.workbenches | object | `{"defaults":{"odh":{"workbenchNamespace":"opendatahub"},"rhoai":{"workbenchNamespace":"rhods-notebooks"}},"dependencies":{},"dsc":{"managementState":null,"workbenchNamespace":null,"workbenchesV2":{"managementState":null}}}` | Workbenches component |
| components.workbenches.defaults | object | `{"odh":{"workbenchNamespace":"opendatahub"},"rhoai":{"workbenchNamespace":"rhods-notebooks"}}` | Operator-type-specific defaults for dsc fields |
| components.workbenches.dependencies | object | `{}` | Dependencies required by Workbenches |
| components.workbenches.dsc | object | `{"managementState":null,"workbenchNamespace":null,"workbenchesV2":{"managementState":null}}` | DSC configuration for Workbenches |
| components.workbenches.dsc.managementState | string | `nil` | Management state for Workbenches. Null uses profile default. |
| components.workbenches.dsc.workbenchNamespace | string | `nil` | Workbench namespace for Workbenches (overrides defaults) |
| components.workbenches.dsc.workbenchesV2 | object | `{"managementState":null}` | Workbenches V2 (new in DSC v3) |
| components.workbenches.dsc.workbenchesV2.managementState | string | `nil` | Management state for Workbenches V2 (Managed or Removed). Null uses profile default. |
| dependencies.certManager | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable-v1","name":"openshift-cert-manager-operator","namespace":"cert-manager-operator"}}` | Cert Manager operator |
| dependencies.certManager.dependencies | object | `{}` | Dependencies required by cert-manager |
| dependencies.certManager.enabled | string | `"auto"` | Enable cert-manager: auto (if needed), true (always), false (never) |
| dependencies.clusterObservability | object | `{"dependencies":{"opentelemetry":true},"enabled":"auto","olm":{"channel":"stable","name":"cluster-observability-operator","namespace":"openshift-cluster-observability-operator"}}` | Cluster Observability operator |
| dependencies.clusterObservability.dependencies | object | `{"opentelemetry":true}` | Dependencies required by cluster-observability |
| dependencies.clusterObservability.enabled | string | `"auto"` | Enable cluster-observability: auto (if needed), true (always), false (never) |
| dependencies.customMetricsAutoscaler | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable","name":"openshift-custom-metrics-autoscaler-operator","namespace":"openshift-keda"}}` | Custom Metrics Autoscaler (KEDA) operator |
| dependencies.customMetricsAutoscaler.dependencies | object | `{}` | Dependencies required by custom-metrics-autoscaler |
| dependencies.customMetricsAutoscaler.enabled | string | `"auto"` | Enable custom-metrics-autoscaler: auto (if needed), true (always), false (never) |
| dependencies.jobSet | object | `{"config":{"spec":{"logLevel":"Normal","operatorLogLevel":"Normal"}},"dependencies":{"certManager":true},"enabled":"auto","olm":{"channel":"stable-v1.0","name":"job-set","namespace":"openshift-jobset-operator","targetNamespaces":["openshift-jobset-operator"]}}` | Job Set operator |
| dependencies.jobSet.config.spec | object | `{"logLevel":"Normal","operatorLogLevel":"Normal"}` | JobSetOperator CR spec (user can add any fields supported by the CR) |
| dependencies.jobSet.dependencies | object | `{"certManager":true}` | Dependencies required by job-set |
| dependencies.jobSet.enabled | string | `"auto"` | Enable job-set: auto (if needed), true (always), false (never) |
| dependencies.kueue | object | `{"config":{"spec":{"config":{"integrations":{"frameworks":["Deployment","Pod","PyTorchJob","RayCluster","RayJob","StatefulSet","TrainJob"]}},"managementState":"Managed"}},"dependencies":{"certManager":true},"enabled":"auto","olm":{"channel":"stable-v1.4","name":"kueue-operator","namespace":"openshift-kueue-operator"}}` | Kueue operator |
| dependencies.kueue.config.spec | object | `{"config":{"integrations":{"frameworks":["Deployment","Pod","PyTorchJob","RayCluster","RayJob","StatefulSet","TrainJob"]}},"managementState":"Managed"}` | Kueue CR spec (user can add any fields) |
| dependencies.kueue.dependencies | object | `{"certManager":true}` | Dependencies required by kueue |
| dependencies.kueue.enabled | string | `"auto"` | Enable kueue: auto (if needed), true (always), false (never) |
| dependencies.leaderWorkerSet | object | `{"config":{"spec":{"logLevel":"Normal","managementState":"Managed","operatorLogLevel":"Normal"}},"dependencies":{"certManager":true},"enabled":"auto","olm":{"channel":"stable-v1.0","name":"leader-worker-set","namespace":"openshift-lws-operator","targetNamespaces":["openshift-lws-operator"]}}` | Leader Worker Set operator |
| dependencies.leaderWorkerSet.config.spec | object | `{"logLevel":"Normal","managementState":"Managed","operatorLogLevel":"Normal"}` | LeaderWorkerSetOperator CR spec |
| dependencies.leaderWorkerSet.dependencies | object | `{"certManager":true}` | Dependencies required by leader-worker-set |
| dependencies.leaderWorkerSet.enabled | string | `"auto"` | Enable leader-worker-set: auto (if needed), true (always), false (never) |
| dependencies.loki | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable-6.5","createNamespace":true,"createOperatorGroup":true,"name":"loki-operator","namespace":"openshift-operators-redhat"}}` | Loki operator |
| dependencies.loki.dependencies | object | `{}` | Dependencies required by loki |
| dependencies.loki.enabled | string | `"auto"` | Enable loki: auto (if needed), true (always), false (never) |
| dependencies.loki.olm.createNamespace | bool | `true` | Whether Helm should create the operator namespace. Set to false if the namespace already exists. |
| dependencies.loki.olm.createOperatorGroup | bool | `true` | Whether Helm should create an OperatorGroup in the namespace. Set to false if an OperatorGroup already exists in the namespace. |
| dependencies.nfd | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable","name":"nfd","namespace":"openshift-nfd","targetNamespaces":["openshift-nfd"]}}` | Node Feature Discovery operator (required for GPU support) |
| dependencies.nfd.dependencies | object | `{}` | Dependencies required by NFD |
| dependencies.nfd.enabled | string | `"auto"` | Enable NFD: auto (if needed), true (always), false (never) |
| dependencies.nvidiaGPUOperator | object | `{"dependencies":{"nfd":true},"enabled":"auto","olm":{"channel":"v25.10","name":"gpu-operator-certified","namespace":"nvidia-gpu-operator","source":"certified-operators","targetNamespaces":["nvidia-gpu-operator"]}}` | NVIDIA GPU operator (required for GPU support) |
| dependencies.nvidiaGPUOperator.dependencies | object | `{"nfd":true}` | Dependencies required by GPU operator |
| dependencies.nvidiaGPUOperator.enabled | string | `"auto"` | Enable GPU operator: auto (if needed), true (always), false (never) |
| dependencies.opentelemetry | object | `{"dependencies":{},"enabled":"auto","olm":{"channel":"stable","name":"opentelemetry-product","namespace":"openshift-opentelemetry-operator"}}` | OpenTelemetry operator |
| dependencies.opentelemetry.dependencies | object | `{}` | Dependencies required by opentelemetry |
| dependencies.opentelemetry.enabled | string | `"auto"` | Enable opentelemetry: auto (if needed), true (always), false (never) |
| dependencies.rhcl | object | `{"config":{"authorinoSpec":{"clusterWide":true,"listener":{"tls":{"certSecretRef":{"name":"authorino-server-cert"},"enabled":true}},"oidcServer":{"tls":{"enabled":false}},"replicas":1},"spec":{},"tlsEnabled":false},"dependencies":{"certManager":true},"enabled":"auto","olm":{"channel":"stable","name":"rhcl-operator","namespace":"kuadrant-system"}}` | RHCL (Kuadrant) operator |
| dependencies.rhcl.config.authorinoSpec | object | `{"clusterWide":true,"listener":{"tls":{"certSecretRef":{"name":"authorino-server-cert"},"enabled":true}},"oidcServer":{"tls":{"enabled":false}},"replicas":1}` | Authorino CR spec (only created if tlsEnabled: true) |
| dependencies.rhcl.config.spec | object | `{}` | Kuadrant CR spec (user can add any fields) |
| dependencies.rhcl.config.tlsEnabled | bool | `false` | Enable Authorino TLS configuration |
| dependencies.rhcl.dependencies | object | `{"certManager":true}` | Dependencies required by rhcl |
| dependencies.rhcl.enabled | string | `"auto"` | Enable rhcl: auto (if needed), true (always), false (never) |
| dependencies.tempo | object | `{"dependencies":{"opentelemetry":true},"enabled":"auto","olm":{"channel":"stable","name":"tempo-product","namespace":"openshift-tempo-operator"}}` | Tempo operator |
| dependencies.tempo.dependencies | object | `{"opentelemetry":true}` | Dependencies required by tempo |
| dependencies.tempo.enabled | string | `"auto"` | Enable tempo: auto (if needed), true (always), false (never) |
| labels | object | `{}` | Common labels applied to all resources |
| olm.installPlanApproval | string | `"Automatic"` | Install plan approval mode (Automatic or Manual) |
| olm.source | string | `"redhat-operators"` | Default catalog source for OLM subscriptions |
| olm.sourceNamespace | string | `"openshift-marketplace"` | Namespace of the catalog source |
| operator.enabled | bool | `true` | Enable operator installation |
| operator.odh | object | `{"applicationsNamespace":"opendatahub","monitoringNamespace":"opendatahub","olm":{"channel":"fast-3","name":"opendatahub-operator","namespace":"opendatahub-operator-system","source":"community-operators"}}` | ODH operator settings |
| operator.rhoai | object | `{"applicationsNamespace":"redhat-ods-applications","monitoringNamespace":"redhat-ods-monitoring","olm":{"channel":"beta","name":"rhods-operator","namespace":"redhat-ods-operator","source":"redhat-operators"}}` | RHOAI operator settings |
| operator.type | string | `"odh"` | Operator type: odh (Open Data Hub) or rhoai (Red Hat OpenShift AI) |
| profile | string | `"default"` | Deploy profile: sets default managementState for components and services. Options: default (all Removed), rhaii (KServe for inference/model serving) Explicit managementState values override the profile. |
| services.monitoring | object | `{"dependencies":{"certManager":true,"clusterObservability":true,"loki":true,"opentelemetry":true,"tempo":true},"dsci":{"alerting":{},"managementState":null,"metrics":{},"traces":{}}}` | Monitoring service configuration |
| services.monitoring.dsci.managementState | string | `nil` | Management state for monitoring. Null uses profile default or Removed. |
| skipCrdCheck | bool | `false` | Skip CRD existence check - render all CRs regardless. Set to true for ArgoCD. |
| tags.install-with-helm-dependencies | bool | `false` | Install operators using Helm chart dependencies instead of OLM. Set to true when OLM is not available in the cluster. Default is false (use OLM Subscriptions when available). |
| trustedCABundle | object | `{"customCABundle":"","managementState":"Managed"}` | Trusted CA bundle configuration |
| trustedCABundle.customCABundle | string | `""` | A custom CA bundle that will be available for all components in the Data Science Cluster (DSC). |
| trustedCABundle.managementState | string | `"Managed"` | Management state for trusted CA bundle (Managed or Removed) |

