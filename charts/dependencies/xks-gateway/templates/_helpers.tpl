{{/*
Expand the name of the chart.
*/}}
{{- define "xks-gateway.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "xks-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels applied to all resources.
*/}}
{{- define "xks-gateway.labels" -}}
helm.sh/chart: {{ include "xks-gateway.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Resolve the gateway namespace.
*/}}
{{- define "xks-gateway.namespace" -}}
{{- .Values.gateway.namespace | default "rh-ai-gateway" }}
{{- end }}

{{/*
Resolve the namespace for the OIDC client secret (defaults to gateway.namespace).
*/}}
{{- define "xks-gateway.oidcSecretNamespace" -}}
{{- $gw := .Values.gateway -}}
{{- $gw.oidc.secretNamespace | default (include "xks-gateway.namespace" .) }}
{{- end }}

{{/*
Resolve the OIDC client secret name referenced by GatewayConfig (defaults when chart-managed).
*/}}
{{- define "xks-gateway.oidcClientSecretRefName" -}}
{{- $gw := .Values.gateway -}}
{{- if $gw.oidc.oidcClientSecret -}}
{{- $gw.oidc.clientSecretRef.name | default "oidc-client-secret" -}}
{{- else -}}
{{- $gw.oidc.clientSecretRef.name -}}
{{- end -}}
{{- end -}}

{{/*
True when the chart is enabled AND gateway configuration is provided (domain is set).
When used as a subchart with default empty values, all resource templates are skipped
and only the CRD from crds/ is installed.
*/}}
{{- define "xks-gateway.configured" -}}
{{- if and .Values.enabled .Values.gateway.domain -}}true{{- end -}}
{{- end -}}

{{/*
True when this chart creates the OIDC client secret (oidcClientSecret set and target namespace is gateway.namespace).
*/}}
{{- define "xks-gateway.oidcSecretManaged" -}}
{{- $gw := .Values.gateway -}}
{{- if $gw.oidc.oidcClientSecret -}}
{{- $secretNs := include "xks-gateway.oidcSecretNamespace" . -}}
{{- $gatewayNs := include "xks-gateway.namespace" . -}}
{{- if eq $secretNs $gatewayNs -}}true{{- end -}}
{{- end -}}
{{- end -}}
