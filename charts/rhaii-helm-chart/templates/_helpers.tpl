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
Environment variables for disabled components and services
*/}}
{{- define "rhaii-helm-chart.disabledResourcesEnv" -}}
- name: RHAI_DISABLE_DSC_RESOURCE
  value: "true"
- name: RHAI_DISABLE_DSCI_RESOURCE
  value: "true"
{{- $components := list "dashboard" "datasciencepipelines" "feastoperator" "kserve" "kueue" "llamastackoperator" "mlflowoperator" "modelcontroller" "modelregistry" "modelsasservice" "ray" "sparkoperator" "trainer" "trainingoperator" "trustyai" "workbenches" -}}
{{- range $components }}
- name: RHAI_DISABLE_{{ . | upper }}_COMPONENT
  value: "true"
{{- end }}
{{- $services := list "auth" "certconfigmapgenerator" "gateway" "monitoring" "setupcontroller" -}}
{{- range $services }}
- name: RHAI_DISABLE_{{ . | upper }}_SERVICE
  value: "true"
{{- end }}
{{- end }}