# odh-operator

![Version: 0.1.0](https://img.shields.io/badge/Version-0.1.0-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 3.4.0-ea.1](https://img.shields.io/badge/AppVersion-3.4.0--ea.1-informational?style=flat-square)

Open Data Hub Operator Helm chart (non-OLM installation)

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| enabled | bool | `true` |  |
| imagePullSecrets | list | `[]` |  |
| installCRDs | bool | `true` |  |
| labels | object | `{}` |  |
| namespace | string | `"opendatahub-operator-system"` |  |

