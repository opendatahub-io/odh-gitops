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

{{/* Service annotations, the platform's merged under the Service's own. Only a LoadBalancer gets the platform's. */}}
{{- define "grid-enrollment.serviceAnnotations" -}}
{{- $svc := .Values.enrollment.service -}}
{{- $own := $svc.annotations | default dict -}}
{{- $platform := dict -}}
{{- $cloud := .Values.platform | default "" -}}
{{- $internal := eq (.Values.loadBalancerScope | default "internal") "internal" -}}
{{- if eq $svc.type "LoadBalancer" -}}
{{- /* Each cloud reads only its own keys, so "any" carries all of them. */ -}}
{{- if has $cloud (list "aws" "any") -}}
{{- $_ := set $platform "service.beta.kubernetes.io/aws-load-balancer-type" "nlb" -}}
{{- /* Explicit false: the AWS Load Balancer Controller treats an absent annotation as internal. */ -}}
{{- $_ := set $platform "service.beta.kubernetes.io/aws-load-balancer-internal" (toString $internal) -}}
{{- end -}}
{{- if and $internal (has $cloud (list "azure" "any")) -}}
{{- $_ := set $platform "service.beta.kubernetes.io/azure-load-balancer-internal" "true" -}}
{{- end -}}
{{- if and $internal (has $cloud (list "gcp" "any")) -}}
{{- $_ := set $platform "networking.gke.io/load-balancer-type" "Internal" -}}
{{- /* Sites sit in different regions, and a GCP internal load balancer serves only its own without this. */ -}}
{{- $_ := set $platform "networking.gke.io/internal-load-balancer-allow-global-access" "true" -}}
{{- end -}}
{{- end -}}
{{- $merged := merge (deepCopy $own) $platform -}}
{{- if $merged }}
{{- toYaml $merged }}
{{- end }}
{{- end -}}

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
{{- if and $route (eq .Values.route.tls.termination "reencrypt") (dig "rotation" "enabled" true .Values.enrollment) }}
{{- fail "route.tls.termination=reencrypt drops the client certificate sites rotate their identity with; use passthrough, or set enrollment.rotation.enabled=false" }}
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
The bootstrap Job persists grid identity and optionally generates service credentials.
*/}}
{{- define "grid-enrollment.bootstrapRuns" -}}
{{- if or .Values.gridIdentity.enabled (and (eq .Values.mode "service") (or (ne (include "grid-enrollment.caProvided" .) "true") (include "grid-enrollment.generatesAdminTokens" .))) -}}
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
{{- /* Without SWIM there is no SWIM key to create or deliver. */}}
{{- if eq (dig "membership" "source" "Swim" ($v.grid | default dict)) "Local" }}{{- $_ := set $v.hubSite "swimKeySecretName" "" }}{{- end }}
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
{{- with $i.allowDeletedName }}{{- $_ := set $entry "allowDeletedName" true }}{{- end }}
{{- with $i.cluster }}{{- $_ := set $entry "cluster" . }}{{- end }}
{{- $list = append $list $entry }}
{{- end }}
{{- $_ := set $v "invites" $list }}
{{- end }}
{{- include "grid-enrollment.validateDeliveryNamespaces" . }}
{{- end }}

{{/*
Namespace for the per-site invite token Secrets, defaulting beside the release rather
than inside it. The service needs get, create and delete there unscoped by name, because
invite names are per site, and admission cannot constrain a read, so sharing a namespace
with either the Grid CA signing key or the hub's identity would let the service read it.
invite-namespace.yaml creates this namespace.
*/}}
{{- define "grid-enrollment.inviteSecretsNamespace" -}}
{{- $ns := .Values.enrollment.inviteSecrets.namespace | default (printf "%s-invites" .Release.Namespace | trunc 63 | trimSuffix "-") -}}
{{- if eq $ns .Release.Namespace }}
{{- fail "enrollment.inviteSecrets.namespace must not be the release namespace: the enrollment service holds get on every Secret there, and that namespace holds the Grid CA signing key. Leave it empty for <release-namespace>-invites, or name a namespace that holds only invite tokens." }}
{{- end }}
{{- /* The same read reaches the hub identity and the grid CA the bootstrap writes there. */}}
{{- if and .Values.hubSite.name (eq $ns .Values.hubSite.namespace) }}
{{- fail "enrollment.inviteSecrets.namespace must not be hubSite.namespace: the enrollment service holds get on every Secret there, and the bootstrap writes the hub's identity and the grid CA into it. Leave it empty for <release-namespace>-invites, or name a namespace that holds only invite tokens." }}
{{- end }}
{{- $ns -}}
{{- end }}

{{/* The namespaces a grid operator actually runs in, named in every refusal that wants one. */}}
{{- define "grid-enrollment.operatorNamespaceHint" -}}
It must be the grid operator's own namespace: grid or grid-system under a Helm install, odh-ai-grid or redhat-ai-grid under a platform install, which derives it from the applications namespace rather than sharing it.
{{- end }}

{{/*
Refuse a Secret delivery target that belongs to the platform. The bootstrap's Role in
hubSite.namespace carries namespace-wide create on Secrets, since Kubernetes cannot
scope create by name, so a mistyped target hands that grant to a namespace holding
another component's Secrets.
*/}}
{{- define "grid-enrollment.refuseDeliveryNamespace" -}}
{{- $ns := .ns }}
{{/*
A guard against a typo, not a security boundary: whoever supplies these values also
supplies ca.bootstrap.policy.enabled. The applications namespaces are on the list because
a platform install derives its grid namespace FROM one of them, so they are the plausible
wrong answer rather than an unlikely one.
*/}}
{{- $reserved := list "default" "openshift" "kubernetes" "opendatahub" "redhat-ods-applications" "open-cluster-management" "multicluster-engine" }}
{{- if or (has $ns $reserved) (hasPrefix "kube-" $ns) (hasPrefix "openshift-" $ns) }}
{{- fail (printf "%s=%q is a platform namespace, and this chart puts Secrets and a Role granting create on Secrets there. %s" .key $ns .hint) }}
{{- end }}
{{- end }}

{{/*
Every namespace the chart puts a Secret or a Secret-granting Role in. Called from
normalize rather than from one template, so the refusal does not depend on which
templates happen to render.
*/}}
{{- define "grid-enrollment.validateDeliveryNamespaces" -}}
{{/*
Required, with no default. The grid operator's namespace differs per install path and the
chart cannot read the cluster to tell which path it is on, so any default is wrong
somewhere and wrong silently: the Secrets land where no operator reads them, the site
never gets an identity, and nothing says so.
*/}}
{{- if and .Values.hubSite.name (not .Values.hubSite.namespace) }}
{{- fail (printf "hubSite.namespace is required when hubSite.name is set. %s" (include "grid-enrollment.operatorNamespaceHint" .)) }}
{{- end }}
{{- if and .Values.invitePolicy.enabled (not .Values.invitePolicy.namespace) }}
{{- fail (printf "invitePolicy.namespace is required when invitePolicy.enabled is true. %s" (include "grid-enrollment.operatorNamespaceHint" .)) }}
{{- end }}
{{- include "grid-enrollment.refuseDeliveryNamespace" (dict "key" "enrollment.inviteSecrets.namespace" "ns" (include "grid-enrollment.inviteSecretsNamespace" .) "hint" "Give the invite tokens a namespace of their own, holding nothing else.") }}
{{- if .Values.hubSite.name }}
{{- include "grid-enrollment.refuseDeliveryNamespace" (dict "key" "hubSite.namespace" "ns" .Values.hubSite.namespace "hint" (include "grid-enrollment.operatorNamespaceHint" .)) }}
{{- end }}
{{- if .Values.invitePolicy.enabled }}
{{- include "grid-enrollment.refuseDeliveryNamespace" (dict "key" "invitePolicy.namespace" "ns" .Values.invitePolicy.namespace "hint" (include "grid-enrollment.operatorNamespaceHint" .)) }}
{{- end }}
{{- end }}

{{/*
Refuse a hub site the chart cannot issue: a provided CA keeps the signing key out of
reach, and an invite for the same name would mint a second identity for it.
*/}}
{{- define "grid-enrollment.validateHubSite" -}}
{{- with .Values.hubSite.name }}
{{- if eq (include "grid-enrollment.caProvided" $) "true" }}
{{- fail "hubSite.name needs the bootstrap CA: a provided CA cannot issue the hub identity" }}
{{- end }}
{{- range $.Values.invites }}
{{- if eq .siteName $.Values.hubSite.name }}
{{- fail (printf "hubSite.name %q is also invited: the hub takes its identity from the CA, so drop its invite" .siteName) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
RUST_LOG for the chart's Rust binaries: log.filter when set, else log.level.
*/}}
{{- define "grid-enrollment.rustLog" -}}
{{- $log := .Values.log | default dict -}}
{{- $log.filter | default $log.level | default "info" -}}
{{- end }}

{{/*
Pod security context for the helm tests. The chart's own context plus a non-root UID,
because the test image is busybox and runAsNonRoot alone would refuse to start it. An
explicit runAsUser wins, so an override still decides.
*/}}
{{- define "grid-enrollment.testPodSecurityContext" -}}
{{- $ctx := deepCopy (.Values.enrollment.podSecurityContext | default dict) -}}
{{- if not (hasKey $ctx "runAsUser") }}{{- $_ := set $ctx "runAsUser" 65534 -}}{{- end }}
{{- toYaml $ctx -}}
{{- end }}
