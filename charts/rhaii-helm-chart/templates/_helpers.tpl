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
Check if imagePullSecret is enabled (dockerConfigJson is provided).
*/}}
{{- define "rhaii-helm-chart.imagePullSecretEnabled" -}}
{{- if .Values.imagePullSecret.dockerConfigJson -}}
true
{{- end -}}
{{- end -}}

{{/*
Return the imagePullSecret name.
*/}}
{{- define "rhaii-helm-chart.imagePullSecretName" -}}
{{- .Values.imagePullSecret.name | default "rhaii-pull-secret" -}}
{{- end -}}

{{/*
Render imagePullSecrets block for pod specs.
Always outputs the block so that pre-created secrets are picked up.
*/}}
{{- define "rhaii-helm-chart.imagePullSecrets" -}}
imagePullSecrets:
  - name: {{ include "rhaii-helm-chart.imagePullSecretName" . }}
{{- end -}}

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
