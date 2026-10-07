{{/*
Chart name, truncated to 63 characters.
*/}}
{{- define "grid-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name. Uses fullnameOverride if set, otherwise combines
release name and chart name (deduplicating when the release name already
contains the chart name).
*/}}
{{- define "grid-operator.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label value: name-version.
*/}}
{{- define "grid-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Standard Kubernetes labels applied to every resource.
*/}}
{{- define "grid-operator.labels" -}}
helm.sh/chart: {{ include "grid-operator.chart" . }}
{{ include "grid-operator.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels used by Deployment matchLabels and Service selectors.
These must remain stable across upgrades.
*/}}
{{- define "grid-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grid-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name. When create is true, defaults to the release fullname.
When create is false, defaults to "default" per Helm RBAC convention.
*/}}
{{- define "grid-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "grid-operator.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Operator container image reference. When digest is set, renders
repository@digest and ignores tag. Otherwise renders repository:tag
(tag defaults to Chart.AppVersion).
*/}}
{{- define "grid-operator.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/*
Signals are reached through the SWIM Service.
*/}}
{{- define "grid-operator.validateSignals" -}}
{{- if and (.Values.signals).enabled (not .Values.swim.service.enabled) }}
{{- fail "signals.enabled needs swim.service.enabled: peers and the local gateway reach signals through the SWIM Service" }}
{{- end }}
{{- if and (.Values.signals).enabled (eq .Values.swim.service.type "LoadBalancer") (eq .Values.swim.service.externalTrafficPolicy "Cluster") }}
{{- fail "signals on a LoadBalancer need swim.service.externalTrafficPolicy Local: the listener caps handshakes per source address" }}
{{- end }}
{{- end }}

{{/*
Validate image digest format when provided.
*/}}
{{- define "grid-operator.validateDigest" -}}
{{- if and .Values.image.digest (not (regexMatch "^sha256:[0-9a-f]{64}$" .Values.image.digest)) }}
{{- fail "image.digest must be in the form sha256:<64 hex characters>" }}
{{- end }}
{{- end }}

{{/*
Normalize values once per render, in place and idempotently. Enrollment, the
cross-cluster path, defaults the site name to swim.siteName (and back), the URL to the
in-cluster grid-enrollment Service, a LoadBalancer SWIM Service, and the grid-gateway
Service. Without enrollment nothing changes.
*/}}
{{- define "grid-operator.normalize" -}}
{{- $v := .Values }}
{{- $e := $v.enrollment | default dict }}
{{- $svc := $v.swim.service }}
{{- if $e.enabled }}
{{- if not $e.siteName }}{{- $_ := set $e "siteName" $v.swim.siteName }}{{- end }}
{{- if not $v.swim.siteName }}{{- $_ := set $v.swim "siteName" $e.siteName }}{{- end }}
{{- if not $v.rbac.enrollmentNamespace }}{{- $_ := set $v.rbac "enrollmentNamespace" "grid-enrollment" }}{{- end }}
{{- if not $e.url }}{{- $_ := set $e "url" (printf "https://grid-enrollment.%s.svc:8443" $v.rbac.enrollmentNamespace) }}{{- end }}
{{- if not $v.gateway.serviceName }}{{- $_ := set $v.gateway "serviceName" "grid-gateway" }}{{- end }}
{{- if kindIs "invalid" $svc.enabled }}{{- $_ := set $svc "enabled" true }}{{- if not $svc.type }}{{- $_ := set $svc "type" "LoadBalancer" }}{{- end }}{{- end }}
{{- end }}
{{- if kindIs "invalid" $svc.enabled }}{{- $_ := set $svc "enabled" false }}{{- end }}
{{- if not $svc.type }}{{- $_ := set $svc "type" "ClusterIP" }}{{- end }}
{{- end }}
