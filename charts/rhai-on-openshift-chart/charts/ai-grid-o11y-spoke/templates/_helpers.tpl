{{- define "ai-grid-o11y-spoke.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ai-grid-o11y-spoke.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels. part-of matches ai-grid-o11y-hub, so both ends of the aggregation path can be
listed together.
*/}}
{{- define "ai-grid-o11y-spoke.labels" -}}
helm.sh/chart: {{ include "ai-grid-o11y-spoke.chart" . }}
app.kubernetes.io/name: {{ include "ai-grid-o11y-spoke.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: ai-grid-usage-logs
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
The hub token, required rather than defaulted.

--set-file keeps the token contents out of shell history and process arguments.
Helm still stores the supplied value in release history, as well as in the rendered
credential Secret; restrict access to both namespaces accordingly.
*/}}
{{- define "ai-grid-o11y-spoke.token" -}}
{{- .Values.credential.token | required "credential.token is required when ai-grid-o11y-spoke.credential.enabled is set: mint it on the hub with `oc create token <writer-sa> -n <o11y-namespace>` and pass it with --set-file ai-grid-o11y-spoke.credential.token=./token" -}}
{{- end }}
