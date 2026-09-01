# rhai-on-xks-chart

![Version: 3.5.0](https://img.shields.io/badge/Version-3.5.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.5.0](https://img.shields.io/badge/AppVersion-3.5.0-informational?style=flat-square)

RHAI on XKS Helm chart for non-OLM installation on non-OpenShift Kubernetes services (AWS, Azure, CoreWeave).

## Requirements

| Repository | Name | Version |
|------------|------|---------|
| file://../dependencies/cert-manager-operator | cert-manager-operator | 1.1.0 |
| file://../dependencies/xks-gateway | xks-gateway | 0.1.0 |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| aws.cloudManager.image | string | `"quay.io/opendatahub/opendatahub-operator:latest"` |  |
| aws.cloudManager.imagePullPolicy | string | `"Always"` |  |
| aws.cloudManager.namespace | string | `"rhai-cloudmanager-system"` |  |
| aws.cloudManager.replicas | int | `1` |  |
| aws.cloudManager.resources.limits.cpu | string | `"500m"` |  |
| aws.cloudManager.resources.limits.memory | string | `"1Gi"` |  |
| aws.cloudManager.resources.requests.cpu | string | `"100m"` |  |
| aws.cloudManager.resources.requests.memory | string | `"512Mi"` |  |
| aws.enabled | bool | `false` |  |
| aws.kubernetesEngine.enabled | bool | `true` |  |
| aws.kubernetesEngine.spec.dependencies.certManager.configuration | object | `{}` |  |
| aws.kubernetesEngine.spec.dependencies.certManager.managementPolicy | string | `"Unmanaged"` |  |
| aws.kubernetesEngine.spec.dependencies.gatewayAPI.configuration | object | `{}` |  |
| aws.kubernetesEngine.spec.dependencies.gatewayAPI.managementPolicy | string | `"Managed"` |  |
| aws.kubernetesEngine.spec.dependencies.lws.configuration.namespace | string | `"openshift-lws-operator"` |  |
| aws.kubernetesEngine.spec.dependencies.lws.managementPolicy | string | `"Unmanaged"` |  |
| aws.kubernetesEngine.spec.dependencies.sailOperator.configuration.namespace | string | `"istio-system"` |  |
| aws.kubernetesEngine.spec.dependencies.sailOperator.managementPolicy | string | `"Managed"` |  |
| azure.cloudManager.image | string | `"quay.io/opendatahub/opendatahub-operator:latest"` |  |
| azure.cloudManager.imagePullPolicy | string | `"Always"` |  |
| azure.cloudManager.namespace | string | `"rhai-cloudmanager-system"` |  |
| azure.cloudManager.replicas | int | `1` |  |
| azure.cloudManager.resources.limits.cpu | string | `"500m"` |  |
| azure.cloudManager.resources.limits.memory | string | `"1Gi"` |  |
| azure.cloudManager.resources.requests.cpu | string | `"100m"` |  |
| azure.cloudManager.resources.requests.memory | string | `"256Mi"` |  |
| azure.enabled | bool | `false` |  |
| azure.kubernetesEngine.enabled | bool | `true` |  |
| azure.kubernetesEngine.spec.dependencies.certManager.configuration | object | `{}` |  |
| azure.kubernetesEngine.spec.dependencies.certManager.managementPolicy | string | `"Unmanaged"` |  |
| azure.kubernetesEngine.spec.dependencies.gatewayAPI.configuration | object | `{}` |  |
| azure.kubernetesEngine.spec.dependencies.gatewayAPI.managementPolicy | string | `"Managed"` |  |
| azure.kubernetesEngine.spec.dependencies.lws.configuration.namespace | string | `"openshift-lws-operator"` |  |
| azure.kubernetesEngine.spec.dependencies.lws.managementPolicy | string | `"Unmanaged"` |  |
| azure.kubernetesEngine.spec.dependencies.sailOperator.configuration.namespace | string | `"istio-system"` |  |
| azure.kubernetesEngine.spec.dependencies.sailOperator.managementPolicy | string | `"Managed"` |  |
| cert-manager-operator.bundle.version | string | `"v1.18.1"` |  |
| cert-manager-operator.enabled | bool | `true` |  |
| cert-manager-operator.imagePullSecrets[0].name | string | `"rhai-pull-secret"` |  |
| cert-manager-operator.operandNamespace | string | `"cert-manager"` |  |
| cert-manager-operator.operatorNamespace | string | `"cert-manager-operator"` |  |
| components.aigateway.enabled | bool | `false` |  |
| components.aigateway.modelsAsAService.gateway.allowedRoutes.namespaces | object | `{}` |  |
| components.aigateway.modelsAsAService.gateway.create | bool | `true` |  |
| components.aigateway.modelsAsAService.gateway.gatewayClassName | string | `"istio"` |  |
| components.aigateway.modelsAsAService.gateway.name | string | `"maas-default-gateway"` |  |
| components.aigateway.modelsAsAService.gateway.namespace | string | `""` |  |
| components.aigateway.spec.modelsAsAService.managementState | string | `"Managed"` |  |
| components.kserve.enabled | bool | `true` |  |
| components.kserve.gateway.allowedRoutes.namespaces | object | `{}` |  |
| components.kserve.gateway.create | bool | `true` |  |
| components.kserve.spec | object | `{}` |  |
| coreweave.cloudManager.image | string | `"quay.io/opendatahub/opendatahub-operator:latest"` |  |
| coreweave.cloudManager.imagePullPolicy | string | `"Always"` |  |
| coreweave.cloudManager.namespace | string | `"rhai-cloudmanager-system"` |  |
| coreweave.cloudManager.replicas | int | `1` |  |
| coreweave.cloudManager.resources.limits.cpu | string | `"500m"` |  |
| coreweave.cloudManager.resources.limits.memory | string | `"1Gi"` |  |
| coreweave.cloudManager.resources.requests.cpu | string | `"100m"` |  |
| coreweave.cloudManager.resources.requests.memory | string | `"256Mi"` |  |
| coreweave.enabled | bool | `false` |  |
| coreweave.kubernetesEngine.enabled | bool | `true` |  |
| coreweave.kubernetesEngine.spec.dependencies.certManager.configuration | object | `{}` |  |
| coreweave.kubernetesEngine.spec.dependencies.certManager.managementPolicy | string | `"Unmanaged"` |  |
| coreweave.kubernetesEngine.spec.dependencies.gatewayAPI.configuration | object | `{}` |  |
| coreweave.kubernetesEngine.spec.dependencies.gatewayAPI.managementPolicy | string | `"Managed"` |  |
| coreweave.kubernetesEngine.spec.dependencies.lws.configuration.namespace | string | `"openshift-lws-operator"` |  |
| coreweave.kubernetesEngine.spec.dependencies.lws.managementPolicy | string | `"Unmanaged"` |  |
| coreweave.kubernetesEngine.spec.dependencies.sailOperator.configuration.namespace | string | `"istio-system"` |  |
| coreweave.kubernetesEngine.spec.dependencies.sailOperator.managementPolicy | string | `"Managed"` |  |
| enabled | bool | `true` |  |
| gateway.hostname | string | `""` |  |
| gateway.tls.additionalSANs | list | `[]` |  |
| gateway.tls.enabled | bool | `true` |  |
| gateway.tls.issuerRef.kind | string | `"ClusterIssuer"` |  |
| gateway.tls.issuerRef.name | string | `"rhai-ca-issuer"` |  |
| hooks.cliImage | string | `"registry.redhat.io/openshift4/ose-cli-rhel9:v4.20@sha256:d876c1d98b39d65c00c4261431bb84b90284699f3aef84d8701a25c786fb79a1"` |  |
| hooks.postInstallCrs.enabled | bool | `true` |  |
| hooks.resources.limits.cpu | string | `"200m"` |  |
| hooks.resources.limits.memory | string | `"512Mi"` |  |
| hooks.resources.requests.cpu | string | `"50m"` |  |
| hooks.resources.requests.memory | string | `"64Mi"` |  |
| imagePullSecret.dependencyNamespaces | list | `[]` |  |
| imagePullSecret.dockerConfigJson | string | `""` |  |
| imagePullSecret.name | string | `"rhai-pull-secret"` |  |
| installCRDs | bool | `true` |  |
| labels | object | `{}` |  |
| rhaiOperator.applicationsNamespace | string | `"redhat-ods-applications"` |  |
| rhaiOperator.image | string | `"quay.io/opendatahub/opendatahub-operator:latest"` |  |
| rhaiOperator.imagePullPolicy | string | `"Always"` |  |
| rhaiOperator.initResources.limits.cpu | string | `"100m"` |  |
| rhaiOperator.initResources.limits.memory | string | `"512Mi"` |  |
| rhaiOperator.initResources.requests.cpu | string | `"10m"` |  |
| rhaiOperator.initResources.requests.memory | string | `"64Mi"` |  |
| rhaiOperator.namespace | string | `"redhat-ods-operator"` |  |
| rhaiOperator.relatedImages | list | `[]` |  |
| rhaiOperator.replicas | int | `1` |  |
| rhaiOperator.resources.limits.cpu | string | `"500m"` |  |
| rhaiOperator.resources.limits.memory | string | `"1Gi"` |  |
| rhaiOperator.resources.requests.cpu | string | `"300m"` |  |
| rhaiOperator.resources.requests.memory | string | `"256Mi"` |  |
| uninstall.cleanupNamespaces | bool | `false` |  |
| xks-gateway.enabled | bool | `true` |  |
| xks-gateway.gateway.certificate.secretName | string | `""` |  |
| xks-gateway.gateway.certificate.type | string | `"SelfSigned"` |  |
| xks-gateway.gateway.cookie.expire | string | `"24h"` |  |
| xks-gateway.gateway.cookie.refresh | string | `"1h"` |  |
| xks-gateway.gateway.domain | string | `""` |  |
| xks-gateway.gateway.ingressMode | string | `"LoadBalancer"` |  |
| xks-gateway.gateway.namespace | string | `"rh-ai-gateway"` |  |
| xks-gateway.gateway.networkPolicy.ingress.enabled | bool | `true` |  |
| xks-gateway.gateway.oidc.clientID | string | `""` |  |
| xks-gateway.gateway.oidc.clientSecretRef.key | string | `"client-secret"` |  |
| xks-gateway.gateway.oidc.clientSecretRef.name | string | `""` |  |
| xks-gateway.gateway.oidc.issuerURL | string | `""` |  |
| xks-gateway.gateway.oidc.oidcClientSecret | string | `""` |  |
| xks-gateway.gateway.oidc.secretNamespace | string | `""` |  |
| xks-gateway.gateway.providerCASecretName | string | `""` |  |
| xks-gateway.gateway.subdomain | string | `""` |  |
| xks-gateway.gateway.verifyProviderCertificate | bool | `true` |  |

