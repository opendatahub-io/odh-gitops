{{/*
Expand the name of the chart.
*/}}
{{- define "rhai-on-xks-chart.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rhai-on-xks-chart.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rhai-on-xks-chart.labels" -}}
helm.sh/chart: {{ include "rhai-on-xks-chart.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Check if imagePullSecret is enabled (dockerConfigJson is provided).
*/}}
{{- define "rhai-on-xks-chart.imagePullSecretEnabled" -}}
{{- if .Values.imagePullSecret.dockerConfigJson -}}
true
{{- end -}}
{{- end -}}

{{/*
Return the imagePullSecret name.
*/}}
{{- define "rhai-on-xks-chart.imagePullSecretName" -}}
{{- .Values.imagePullSecret.name | default "rhaii-pull-secret" -}}
{{- end -}}

{{/*
Render imagePullSecrets block for pod specs.
Always outputs the block so that pre-created secrets are picked up.
*/}}
{{- define "rhai-on-xks-chart.imagePullSecrets" -}}
imagePullSecrets:
  - name: {{ include "rhai-on-xks-chart.imagePullSecretName" . }}
{{- end -}}

{{/*
Validate that exactly one cloud provider is enabled.
*/}}
{{- define "rhai-on-xks-chart.validateCloudProvider" -}}
{{- if and .Values.enabled (not (or .Values.azure.enabled .Values.coreweave.enabled)) -}}
{{- fail "Exactly one cloud provider must be enabled: set azure.enabled=true or coreweave.enabled=true" -}}
{{- end -}}
{{- if and .Values.enabled .Values.azure.enabled .Values.coreweave.enabled -}}
{{- fail "Only one cloud provider can be enabled at a time: set either azure.enabled=true or coreweave.enabled=true, not both" -}}
{{- end -}}
{{- end -}}
