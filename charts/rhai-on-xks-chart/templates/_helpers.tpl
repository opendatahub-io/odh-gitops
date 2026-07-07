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
Render a dockerconfigjson Secret for a given namespace.
Pass a dict with "root" (top-level context), "namespace", and optional "annotations" (dict).
*/}}
{{- define "rhai-on-xks-chart.imagePullSecretResource" -}}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "rhai-on-xks-chart.imagePullSecretName" .root }}
  namespace: {{ .namespace }}
  labels:
    {{- include "rhai-on-xks-chart.labels" .root | nindent 4 }}
  {{- with .annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
type: kubernetes.io/dockerconfigjson
data:
  .dockerconfigjson: {{ .root.Values.imagePullSecret.dockerConfigJson | b64enc }}
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
Collect dependency namespaces from enabled providers.
Pass a dict with "root" (top-level context) and optional "managedOnly" (bool).
When managedOnly is true, only dependencies with managementPolicy: Managed are included.
Returns a JSON object with key "items" containing unique namespace strings.
Usage:
  (include "rhai-on-xks-chart.kubernetesEngineDependencyNamespaces" (dict "root" . "managedOnly" true) | fromJson).items
*/}}
{{- define "rhai-on-xks-chart.kubernetesEngineDependencyNamespaces" -}}
{{- $namespaces := list }}
{{- $managedOnly := .managedOnly | default false }}
{{- $provider := include "rhai-on-xks-chart.activeProvider" .root | fromYaml }}
{{- if and $provider (index $provider "keEnabled") }}
  {{- $provVals := index $.root.Values (index $provider "name") | default dict }}
  {{- range $depName, $dep := (dig "kubernetesEngine" "spec" "dependencies" (dict) $provVals) }}
    {{- if or (not $managedOnly) (eq (dig "managementPolicy" "" $dep) "Managed") }}
      {{- with (dig "configuration" "namespace" "" $dep) }}
        {{- $namespaces = append $namespaces . }}
      {{- end }}
    {{- end }}
  {{- end }}
{{- end }}
{{- dict "items" ($namespaces | uniq) | toJson }}
{{- end -}}

{{/*
Return the KubernetesEngine CRD plural resource name for the active cloud provider.
*/}}
{{- define "rhai-on-xks-chart.keResourceName" -}}
{{- $provider := include "rhai-on-xks-chart.activeProvider" . | fromYaml }}
{{- if and $provider (index $provider "keEnabled") -}}
  {{- index $provider "keResource" -}}
{{- end }}
{{- end -}}

{{/*
Validate that exactly one cloud provider is enabled.
*/}}
{{- define "rhai-on-xks-chart.validateCloudProvider" -}}
{{- $registry := include "rhai-on-xks-chart.providerRegistry" . | fromYaml }}
{{- $enabledCount := 0 -}}
{{- $enabledNames := list -}}
{{- range $name := keys $registry | sortAlpha }}
  {{- $providerVals := index $.Values $name | default dict }}
  {{- if $providerVals.enabled }}
    {{- $enabledCount = add $enabledCount 1 }}
    {{- $enabledNames = append $enabledNames $name }}
  {{- end }}
{{- end }}
{{- if and .Values.enabled (eq (int $enabledCount) 0) -}}
{{- fail (printf "Exactly one cloud provider must be enabled: set %s" (join ".enabled=true, " (keys $registry | sortAlpha) | printf "%s.enabled=true")) -}}
{{- end -}}
{{- if and .Values.enabled (gt (int $enabledCount) 1) -}}
{{- fail (printf "Only one cloud provider can be enabled at a time: set either %s, not multiple" (join ".enabled=true, " $enabledNames | printf "%s.enabled=true")) -}}
{{- end -}}
{{- end -}}
