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
