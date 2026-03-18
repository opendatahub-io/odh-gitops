{{/*
Expand the name of the chart.
*/}}
{{- define "rhaii-helm-chart.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rhaii-helm-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rhaii-helm-chart.labels" -}}
helm.sh/chart: {{ include "rhaii-helm-chart.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Validate that exactly one cloud provider is enabled.
*/}}
{{- define "rhaii-helm-chart.validateCloudProvider" -}}
{{- if and .Values.enabled (not (or .Values.azure.enabled .Values.coreweave.enabled)) -}}
{{- fail "Exactly one cloud provider must be enabled: set azure.enabled=true or coreweave.enabled=true" -}}
{{- end -}}
{{- if and .Values.enabled .Values.azure.enabled .Values.coreweave.enabled -}}
{{- fail "Only one cloud provider can be enabled at a time: set either azure.enabled=true or coreweave.enabled=true, not both" -}}
{{- end -}}
{{- end -}}
