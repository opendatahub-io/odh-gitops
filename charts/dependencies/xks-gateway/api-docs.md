# xks-gateway

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.1.0](https://img.shields.io/badge/AppVersion-0.1.0-informational?style=flat-square)

XKS Gateway onboarding chart - creates the gateway namespace and GatewayConfig CR for non-OpenShift Kubernetes environments.

## Maintainers

| Name | Email | Url |
| ---- | ------ | --- |
| Red Hat |  |  |

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| gateway.certificate.secretName | string | `""` | Name of TLS Secret (required when type is Provided) |
| gateway.certificate.type | string | `"SelfSigned"` | TLS strategy: SelfSigned (auto-generated) or Provided (BYO secret in gateway namespace) |
| gateway.cookie.expire | string | `"24h"` | Session cookie expiry duration (e.g., "24h", "8h") |
| gateway.cookie.refresh | string | `"1h"` | Access token refresh interval — must be less than the OIDC provider's Access Token Lifespan |
| gateway.domain | required | `""` | External hostname (e.g., example.com or *.example.com) |
| gateway.ingressMode | string | `"LoadBalancer"` | How the gateway is exposed externally on XKS (LoadBalancer only) |
| gateway.namespace | string | `"rh-ai-gateway"` | Namespace created by this chart; default location for the OIDC client secret (create after install or use secretNamespace) |
| gateway.networkPolicy.ingress.enabled | bool | `true` | Enable ingress NetworkPolicy for kube-auth-proxy |
| gateway.oidc.clientID | required | `""` | OIDC client ID |
| gateway.oidc.clientSecretRef | object | `{"key":"client-secret","name":""}` | Reference to a pre-existing Secret containing the OIDC client secret |
| gateway.oidc.clientSecretRef.key | string | `"client-secret"` | Key within the Secret that holds the client secret value |
| gateway.oidc.clientSecretRef.name | required | `""` | Name of the existing Kubernetes Secret |
| gateway.oidc.issuerURL | required | `""` | OIDC provider URL (e.g., https://keycloak.example.com/realms/rhai) |
| gateway.oidc.secretNamespace | string | `""` | Namespace where the client secret is located (defaults to gateway.namespace if empty) |
| gateway.providerCASecretName | string | `""` | Name of Secret containing CA cert for the auth provider (must have ca.crt key, in gateway namespace) |
| gateway.subdomain | string | `""` | Subdomain prefix for the gateway |
| gateway.verifyProviderCertificate | bool | `true` | Verify auth provider TLS certificate (set to false only for development) |

