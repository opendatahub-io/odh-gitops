{{/*
Chart name, truncated to 63 characters.
*/}}
{{- define "grid-enrollment.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "grid-enrollment.fullname" -}}
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

{{- define "grid-enrollment.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "grid-enrollment.labels" -}}
helm.sh/chart: {{ include "grid-enrollment.chart" . }}
{{ include "grid-enrollment.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{- define "grid-enrollment.selectorLabels" -}}
app.kubernetes.io/name: {{ include "grid-enrollment.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Selector labels for the enrollment workload: base selectors plus its component,
so it never overlaps the db pods (which carry component: db).
*/}}
{{- define "grid-enrollment.enrollmentSelectorLabels" -}}
{{ include "grid-enrollment.selectorLabels" . }}
app.kubernetes.io/component: enrollment
{{- end }}

{{/*
The listen port, parsed once from enrollment.listenAddr, so the container port,
Service port, and probes share one source.
*/}}
{{- define "grid-enrollment.listenPort" -}}
{{- (splitList ":" .Values.enrollment.listenAddr) | last -}}
{{- end }}

{{/*
The CA is provided (BYO) when a keySecretRef is set or method is "provided";
otherwise the bootstrap Job generates it.
*/}}
{{- define "grid-enrollment.caProvided" -}}
{{- or (eq .Values.ca.method "provided") (ne (default "" .Values.ca.provided.keySecretRef) "") -}}
{{- end }}

{{/*
Secret holding the CA signing key (tls.crt/tls.key). Provided ref wins.
*/}}
{{- define "grid-enrollment.caKeySecret" -}}
{{- if ne (default "" .Values.ca.provided.keySecretRef) "" -}}
{{- .Values.ca.provided.keySecretRef -}}
{{- else -}}
{{- .Values.ca.keySecretName -}}
{{- end }}
{{- end }}

{{/*
Secret holding the serving cert (tls.crt/tls.key). Provided ref wins.
*/}}
{{- define "grid-enrollment.servingSecret" -}}
{{- if ne (default "" .Values.serving.existingSecretRef) "" -}}
{{- .Values.serving.existingSecretRef -}}
{{- else -}}
{{- .Values.serving.secretName -}}
{{- end }}
{{- end }}

{{- define "grid-enrollment.serviceAccountName" -}}
{{- default (include "grid-enrollment.fullname" .) .Values.enrollment.serviceAccount.name }}
{{- end }}

{{/*
Bootstrap Job SA name.
*/}}
{{- define "grid-enrollment.bootstrapServiceAccountName" -}}
{{- printf "%s-ca-bootstrap" (include "grid-enrollment.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
In-cluster DNS name of the enrollment Service, used as the serving cert SAN.
*/}}
{{- define "grid-enrollment.serviceDns" -}}
{{- printf "%s.%s.svc" (include "grid-enrollment.fullname" .) .Release.Namespace }}
{{- end }}

{{/*
Builtin Postgres Service name.
*/}}
{{- define "grid-enrollment.dbHost" -}}
{{- printf "%s-db" (include "grid-enrollment.fullname" .) | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Secret holding DB_CONNECTION_URL. External ref wins; builtin uses the generated one.
*/}}
{{- define "grid-enrollment.dbUrlSecret" -}}
{{- if eq .Values.db.type "external" -}}
{{- required "db.external.connectionUrlSecretRef is required when db.type=external" .Values.db.external.connectionUrlSecretRef -}}
{{- else if .Values.db.builtin.auth.existingSecretRef -}}
{{- .Values.db.builtin.auth.existingSecretRef -}}
{{- else -}}
{{- printf "%s-db" (include "grid-enrollment.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end }}
{{- end }}

{{- define "grid-enrollment.dbUrlSecretKey" -}}
{{- if eq .Values.db.type "external" -}}
{{- default "DB_CONNECTION_URL" .Values.db.external.connectionUrlSecretKey -}}
{{- else -}}
DB_CONNECTION_URL
{{- end }}
{{- end }}

{{/*
Whether a Route renders: route.enabled true or false, or auto when the cluster serves
route.openshift.io/v1. Emits "true" or nothing.
*/}}
{{- define "grid-enrollment.routeEnabled" -}}
{{- $e := .Values.route.enabled -}}
{{- if or (eq (toString $e) "true") (and (eq (toString $e) "auto") (.Capabilities.APIVersions.Has "route.openshift.io/v1")) -}}
true
{{- end -}}
{{- end }}

{{/*
Fail closed: passthrough needs route.host so the serving cert SAN can cover it.
An ingress-generated host cannot be pinned, so the enrolling site (--cacert grid-ca)
would hit a SAN mismatch.
*/}}
{{- define "grid-enrollment.validateRoute" -}}
{{- $route := include "grid-enrollment.routeEnabled" . }}
{{- if and $route (eq .Values.route.tls.termination "passthrough") (not .Values.route.host) }}
{{- fail "route.host is required when a passthrough Route renders, so the serving cert SAN covers it: set route.host=<name>.apps.<cluster-domain>, or route.enabled=false (prefix both with the subchart name under an umbrella chart)" }}
{{- end }}
{{- if and $route (eq .Values.route.tls.termination "reencrypt") (not .Values.route.tls.destinationCACertificate) }}
{{- fail "reencrypt needs route.tls.destinationCACertificate (the grid CA bundle, ca.crt from Secret grid-ca-bundle); passthrough is recommended" }}
{{- end }}
{{- if and $route (eq .Values.route.tls.insecureEdgeTerminationPolicy "Allow") }}
{{- fail "route.tls.insecureEdgeTerminationPolicy=Allow is refused: it would serve the one-time enrollment token over plaintext. Use Redirect or None." }}
{{- end }}
{{- end }}

{{/*
Fail closed: local authz reads grid-admin tokens from a Secret the chart generates or
the user provides; with neither, the pod would mount a Secret that does not exist.
*/}}
{{- define "grid-enrollment.validateAuthz" -}}
{{- $tokens := .Values.enrollment.gridAdminTokens }}
{{- if and (eq .Values.enrollment.authz "local") (not $tokens.generate) (not $tokens.existingSecretRef) }}
{{- fail "enrollment.authz=local needs grid-admin tokens: set enrollment.gridAdminTokens.generate=true or enrollment.gridAdminTokens.existingSecretRef" }}
{{- end }}
{{- end }}

{{/*
Enrollment image: repository@digest when image.digest is set, else repository:tag.
*/}}
{{- define "grid-enrollment.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/*
Builtin Postgres image, pinned by imageDigest when set.
*/}}
{{- define "grid-enrollment.dbImage" -}}
{{- if .Values.db.builtin.imageDigest }}
{{- printf "%s@%s" .Values.db.builtin.image .Values.db.builtin.imageDigest }}
{{- else }}
{{- .Values.db.builtin.image }}
{{- end }}
{{- end }}

{{/*
Generated Secrets the bootstrap Job creates once. Each emits "true" or nothing.
*/}}
{{- define "grid-enrollment.generatesDbCredentials" -}}
{{- if and (eq .Values.db.type "builtin") (not .Values.db.builtin.auth.existingSecretRef) -}}
true
{{- end -}}
{{- end }}

{{- define "grid-enrollment.generatesAdminTokens" -}}
{{- $t := .Values.enrollment.gridAdminTokens -}}
{{- if and (eq .Values.enrollment.authz "local") $t.generate (not $t.existingSecretRef) -}}
true
{{- end -}}
{{- end }}

{{/*
The bootstrap Job runs to generate the CA or a credentials Secret. Emits "true" or nothing.
*/}}
{{- define "grid-enrollment.bootstrapRuns" -}}
{{- if or (ne (include "grid-enrollment.caProvided" .) "true") (include "grid-enrollment.generatesAdminTokens" .) -}}
true
{{- end -}}
{{- end }}

{{- define "grid-enrollment.adminTokensSecret" -}}
{{- printf "%s-grid-admin-tokens" (include "grid-enrollment.fullname" .) -}}
{{- end }}

{{/*
Normalize values once per render, in place and idempotently: host becomes a serving
name and the default Route host, and invites keyed by site become the list the invite
Job reads, keys in sorted order.
*/}}
{{- define "grid-enrollment.normalize" -}}
{{- $v := .Values }}
{{- if not $v.enrollment.service.type }}
{{- $lb := and $v.host (not (include "grid-enrollment.routeEnabled" .)) }}
{{- $_ := set $v.enrollment.service "type" (ternary "LoadBalancer" "ClusterIP" (not (not $lb))) }}
{{- end }}
{{- with $v.host }}
{{- $_ := set $v.serving "extraDnsNames" (append ($v.serving.extraDnsNames | default list) . | uniq) }}
{{- if not $v.route.host }}{{- $_ := set $v.route "host" . }}{{- end }}
{{- end }}
{{- if kindIs "map" $v.invites }}
{{- $list := list }}
{{- range $site := keys $v.invites | sortAlpha }}
{{- $i := get $v.invites $site | default dict }}
{{- $entry := dict "siteName" $site "gridNetworkRef" ($i.network | default "grid") }}
{{- with $i.expiresInSecs }}{{- $_ := set $entry "expiresInSecs" (int .) }}{{- end }}
{{- $list = append $list $entry }}
{{- end }}
{{- $_ := set $v "invites" $list }}
{{- end }}
{{- end }}
