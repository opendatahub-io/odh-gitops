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
{{- .Values.imagePullSecret.name | default "rhai-pull-secret" -}}
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
Add the allowedRoutes block for a Gateway listener can be used by both HTTP and HTTPS listeners
currently is only for kserve, might need adapt for other components
*/}}
{{- define "rhai-on-xks-chart.gatewayAllowedRoutes" -}}
{{- $ns := .Values.components.kserve.gateway.allowedRoutes.namespaces -}}
{{- if and (eq $ns.from "Selector") (not $ns.selector) -}}
{{- fail "allowedRoutes.namespaces.selector is required when from is set to Selector" -}}
{{- end -}}
allowedRoutes:
  namespaces:
    from: {{ $ns.from }}
{{- if and (eq $ns.from "Selector") $ns.selector }}
    selector:
      {{- toYaml $ns.selector | nindent 6 }}
{{- end }}
{{- end -}}

{{/*
Validate that exactly one cloud provider is enabled.
*/}}
{{- define "rhai-on-xks-chart.validateCloudProvider" -}}
{{- if and .Values.enabled (not (or .Values.azure.enabled .Values.coreweave.enabled .Values.aws.enabled)) -}}
{{- fail "Exactly one cloud provider must be enabled: set azure.enabled=true, coreweave.enabled=true, or aws.enabled=true" -}}
{{- end -}}
{{- $enabledCount := 0 -}}
{{- if .Values.azure.enabled }}{{- $enabledCount = add $enabledCount 1 -}}{{- end -}}
{{- if .Values.coreweave.enabled }}{{- $enabledCount = add $enabledCount 1 -}}{{- end -}}
{{- if .Values.aws.enabled }}{{- $enabledCount = add $enabledCount 1 -}}{{- end -}}
{{- if and .Values.enabled (gt (int $enabledCount) 1) -}}
{{- fail "Only one cloud provider can be enabled at a time: set either azure.enabled=true, coreweave.enabled=true, or aws.enabled=true, not multiple" -}}
{{- end -}}
{{- end -}}
