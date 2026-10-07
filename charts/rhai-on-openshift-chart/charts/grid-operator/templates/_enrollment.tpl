{{/* Enrollment values with defaults: the grid-ca-bundle Secret and grid-invite-<siteName>. */}}
{{- define "grid-operator.enrollment.settings" -}}
{{- $e := deepCopy (.Values.enrollment | default dict) }}
{{- $b := $e.caBundle | default dict }}
{{- if not (or $b.configMap $b.secret) }}
{{- $_ := set $e "caBundle" (merge (dict "secret" "grid-ca-bundle") $b) }}
{{- end }}
{{- $t := $e.tokenSecretRef | default dict }}
{{- if and (not $t.name) $e.siteName }}
{{- $_ := set $e "tokenSecretRef" (merge (dict "name" (printf "grid-invite-%s" $e.siteName)) $t) }}
{{- end }}
{{- toYaml $e }}
{{- end }}

{{- define "grid-operator.enrollment.validate" -}}
{{- $e := include "grid-operator.enrollment.settings" . | fromYaml }}
{{- if $e.enabled }}
{{- if not (hasPrefix "https://" ($e.url | default "")) }}
{{- fail "enrollment.url must be an https URL when enrollment.enabled is true" }}
{{- end }}
{{- if not $e.siteName }}
{{- fail "enrollment.siteName is required when enrollment.enabled is true" }}
{{- end }}
{{- if not (dig "tokenSecretRef" "name" "" $e) }}
{{- fail "enrollment.tokenSecretRef.name is required when enrollment.enabled is true" }}
{{- end }}
{{- if not (or (dig "caBundle" "configMap" "" $e) (dig "caBundle" "secret" "" $e)) }}
{{- fail "enrollment.caBundle needs a configMap or a secret when enrollment.enabled is true" }}
{{- end }}
{{- end }}
{{- end }}

{{/* Emits "true" or nothing. */}}
{{- define "grid-operator.enrollment.hasGridCa" -}}
{{- $e := include "grid-operator.enrollment.settings" . | fromYaml }}
{{- if or (dig "gridCaBundle" "configMap" "" $e) (dig "gridCaBundle" "secret" "" $e) -}}
true
{{- end -}}
{{- end }}

{{- define "grid-operator.enrollment.env" -}}
{{- $e := include "grid-operator.enrollment.settings" . | fromYaml }}
{{- if $e.enabled }}
- name: GRID_ENROLL_ENABLED
  value: "true"
- name: GRID_ENROLL_URL
  value: {{ $e.url | quote }}
- name: GRID_ENROLL_SITE_NAME
  value: {{ $e.siteName | quote }}
- name: GRID_ENROLL_CA_FILE
  value: /etc/grid-enroll/pin/ca.crt
{{- if include "grid-operator.enrollment.hasGridCa" . }}
- name: GRID_ENROLL_GRID_CA_FILE
  value: /etc/grid-enroll/grid-ca/ca.crt
{{- end }}
- name: GRID_ENROLL_TOKEN_SECRET
  value: {{ dig "tokenSecretRef" "name" "" $e | quote }}
- name: GRID_ENROLL_TOKEN_SECRET_KEY
  value: {{ dig "tokenSecretRef" "key" "token" $e | quote }}
{{- end }}
{{- end }}

{{- define "grid-operator.enrollment.volumeMounts" -}}
{{- if (include "grid-operator.enrollment.settings" . | fromYaml).enabled }}
- name: enroll-pin
  mountPath: /etc/grid-enroll/pin
  readOnly: true
{{- if include "grid-operator.enrollment.hasGridCa" . }}
- name: enroll-grid-ca
  mountPath: /etc/grid-enroll/grid-ca
  readOnly: true
{{- end }}
{{- end }}
{{- end }}

{{- define "grid-operator.enrollment.bundleVolume" -}}
{{- $b := .bundle | default dict }}
- name: {{ .name }}
  {{- if dig "configMap" "" $b }}
  configMap:
    name: {{ $b.configMap | quote }}
  {{- else }}
  secret:
    secretName: {{ dig "secret" "" $b | quote }}
  {{- end }}
    items:
      - key: {{ dig "key" "ca.crt" $b | quote }}
        path: ca.crt
{{- end }}

{{- define "grid-operator.enrollment.volumes" -}}
{{- $e := include "grid-operator.enrollment.settings" . | fromYaml }}
{{- if $e.enabled }}
{{ include "grid-operator.enrollment.bundleVolume" (dict "name" "enroll-pin" "bundle" $e.caBundle) }}
{{- if include "grid-operator.enrollment.hasGridCa" . }}
{{ include "grid-operator.enrollment.bundleVolume" (dict "name" "enroll-grid-ca" "bundle" $e.gridCaBundle) }}
{{- end }}
{{- end }}
{{- end }}
