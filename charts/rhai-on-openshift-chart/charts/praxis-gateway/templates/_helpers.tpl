{{/*
Normalize values once per render, in place and idempotently: backends keyed by site
become the list the templates read, keys in sorted order. A provider, or a consumer
with a site backend, gets the grid identity. render follows a missing BYO config when
the values configure grid routing (backends, the provider role, or gridServing);
otherwise config.inline serves.
*/}}
{{- define "praxis-gateway.normalize" -}}
{{- $v := .Values }}
{{- $cfg := $v.gatewayConfig }}
{{- $provider := eq ($cfg.role | default "consumer") "provider" }}
{{- if kindIs "map" $cfg.backends }}
{{- $list := list }}
{{- range $key := keys $cfg.backends | sortAlpha }}
{{- $b := deepCopy (get $cfg.backends $key | default dict) }}
{{- $eps := $b.endpoints | default list }}
{{- with $b.endpoint }}{{- $eps = append $eps . }}{{- end }}
{{- $_ := unset $b "endpoint" }}
{{- $_ := set $b "endpoints" $eps }}
{{- $_ := set $b "cluster" ($b.cluster | default $key) }}
{{- $mode := ($b.transport).mode | default "" }}
{{- if and $provider (eq $key "local") (not $mode) }}
{{- $_ := set $b "transport" (merge (dict "mode" "plaintext") ($b.transport | default dict)) }}
{{- else if and (not $provider) (not (has $mode (list "tls" "plaintext"))) }}
{{- $_ := set $b "site" ($b.site | default $key) }}
{{- end }}
{{- $list = append $list $b }}
{{- end }}
{{- $_ := set $cfg "backends" $list }}
{{- end }}
{{- if include "praxis-gateway.gridIdentity" . }}
{{- $_ := set $v.tls "enabled" true }}
{{- if not $v.tls.caSecret }}{{- $_ := set $v.tls "caSecret" "grid-ca" }}{{- end }}
{{- end }}
{{- $gridRouting := or $cfg.backends $provider ($v.gridServing).enabled }}
{{- if and (not ($v.config).existingConfigMap) $gridRouting }}{{- $_ := set $cfg "render" true }}{{- end }}
{{- if not $v.service.type }}{{- $_ := set $v.service "type" (ternary "LoadBalancer" "ClusterIP" $provider) }}{{- end }}
{{- if hasSuffix "/grid-gateway" $v.image.repository }}{{- $_ := set $v.image "flavor" "grid-gateway" }}{{- end }}
{{- $t := $cfg.peerTrust | default dict }}
{{- $digests := concat ($t.certDigests | default list) (compact (list $t.digest $t.nextDigest)) | uniq }}
{{- $ids := concat ($t.spiffeIds | default list) (compact (list $t.spiffeId)) | uniq }}
{{- if $cfg.peerTrust }}
{{- $_ := set $cfg.peerTrust "certDigests" $digests }}
{{- $_ := set $cfg.peerTrust "spiffeIds" $ids }}
{{- end }}
{{- end }}

{{/*
Chart name, truncated to 63 characters.
*/}}
{{- define "praxis-gateway.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name.
*/}}
{{- define "praxis-gateway.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else if include "praxis-gateway.gridIdentity" . }}
{{- /* A grid gateway is named after its release, the name the grid operator looks up. */}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
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
{{- define "praxis-gateway.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Standard Kubernetes labels applied to every resource.
*/}}
{{- define "praxis-gateway.labels" -}}
helm.sh/chart: {{ include "praxis-gateway.chart" . }}
{{ include "praxis-gateway.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Selector labels used by Deployment matchLabels and Service selectors.
*/}}
{{- define "praxis-gateway.selectorLabels" -}}
app.kubernetes.io/name: {{ include "praxis-gateway.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Container image reference.
Defaults the tag to the chart appVersion when no digest or tag is set.
*/}}
{{- define "praxis-gateway.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}

{{/*
Overlay-sync image reference.
Defaults the tag to the chart appVersion when empty.
*/}}
{{- define "praxis-gateway.overlaySyncImage" -}}
{{- printf "%s:%s" .Values.overlay.sidecar.image.repository (default .Chart.AppVersion .Values.overlay.sidecar.image.tag) }}
{{- end }}

{{/*
Validate image digest format when provided.
*/}}
{{- define "praxis-gateway.validateDigest" -}}
{{- if and .Values.image.digest (not (regexMatch "^sha256:[0-9a-f]{64}$" .Values.image.digest)) }}
{{- fail "image.digest must be in the form sha256:<64 hex characters>" }}
{{- end }}
{{- end }}

{{/*
Validate required config ConfigMap name.
*/}}
{{- define "praxis-gateway.validateConfig" -}}
{{- if .Values.gatewayConfig.render }}
{{- $consumer := ne (.Values.gatewayConfig.role | default "consumer") "provider" }}
{{- if and $consumer (not (.Values.gridServing).enabled) (not (trim (toString .Values.gatewayConfig.model))) }}
{{- fail "gatewayConfig.model is required for a consumer without gridServing, and cannot be blank" }}
{{- end }}
{{- if not (.Values.gatewayConfig.backends | default list) }}
{{- fail "gatewayConfig.backends needs at least one backend when gatewayConfig.render is true" }}
{{- end }}
{{- $auth := .Values.gatewayConfig.auth }}
{{- if and (not $auth.mode) (ne (.Values.gatewayConfig.role | default "consumer") "provider") }}
{{- fail "gatewayConfig.auth.mode is required when gatewayConfig.render is true: api-key (needs an image with praxis-policy 0.4 or later) or none (only behind an authenticating front)" }}
{{- end }}
{{- $provider := eq (.Values.gatewayConfig.role | default "consumer") "provider" }}
{{- if $provider }}
{{- if ne .Values.image.flavor "grid-gateway" }}
{{- fail "gatewayConfig.role provider needs image.flavor grid-gateway" }}
{{- end }}
{{- if not (and .Values.tls.enabled .Values.tls.existingSecret (include "praxis-gateway.caSecret" .)) }}
{{- fail "gatewayConfig.role provider needs the grid identity: tls.enabled, tls.existingSecret (the site identity), and tls.caSecret (the Grid CA)" }}
{{- end }}
{{- if ne (len .Values.gatewayConfig.backends) 1 }}
{{- fail "gatewayConfig.role provider routes to exactly one local backend" }}
{{- end }}
{{- if .Values.gatewayConfig.listenerTls.enabled }}
{{- fail "gatewayConfig.role provider serves the grid identity; unset gatewayConfig.listenerTls" }}
{{- end }}
{{- $trust := .Values.gatewayConfig.peerTrust | default dict }}
{{- if eq ($trust.mode | default "pin") "spiffe" }}
{{- if and (not $trust.spiffeIds) (not $trust.allowAnyGridSite) }}
{{- fail "gatewayConfig.peerTrust spiffe mode needs spiffeIds, or allowAnyGridSite true to admit every Grid-CA site" }}
{{- end }}
{{- else if not $trust.certDigests }}
{{- fail "gatewayConfig.peerTrust pin mode needs certDigests" }}
{{- end }}
{{- end }}
{{- if and (not $provider) (eq $auth.mode "none") .Values.service.enabled (has .Values.service.type (list "LoadBalancer" "NodePort")) (not $auth.allowUnauthenticatedExposure) }}
{{- fail (printf "gatewayConfig.auth.mode none with a %s Service exposes unauthenticated inference; use api-key, a ClusterIP Service behind an authenticating front, or set gatewayConfig.auth.allowUnauthenticatedExposure" .Values.service.type) }}
{{- end }}
{{- if and $auth.validateCA.configMap $auth.validateCA.secret }}
{{- fail "gatewayConfig.auth.validateCA: set configMap or secret, not both" }}
{{- end }}
{{- if eq $auth.mode "api-key" }}
{{- if not .Values.gatewayConfig.auth.validateUrl }}
{{- fail "gatewayConfig.auth.validateUrl is required when gatewayConfig.auth.mode is api-key" }}
{{- end }}
{{- if not (hasPrefix "https://" .Values.gatewayConfig.auth.validateUrl) }}
{{- fail "gatewayConfig.auth.validateUrl must be https: a plaintext validate call ships the credential in the clear" }}
{{- end }}
{{- if regexMatch "^https://(\\[|[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+([:/]|$))" .Values.gatewayConfig.auth.validateUrl }}
{{- fail "gatewayConfig.auth.validateUrl must name a host, not an IP address: https to an IP literal has no SNI to verify" }}
{{- end }}
{{- /* The chart-default image predates praxis-policy 0.4, which adds identity/api-key. */}}
{{- if eq (include "praxis-gateway.image" .) "ghcr.io/praxis-proxy/ai:0.4.0" }}
{{- fail "gatewayConfig.auth.mode api-key is unsupported on the default image ghcr.io/praxis-proxy/ai:0.4.0: its policy engine lacks identity/api-key (praxis-policy 0.4 or later). Set image to a build that registers it, or use auth.mode none behind an authenticating front." }}
{{- end }}
{{- end }}
{{- include "praxis-gateway.validateBackends" . }}
{{- else if not .Values.config.existingConfigMap }}
{{- include "praxis-gateway.validateInlineConfig" . }}
{{- end }}
{{- end }}

{{/*
Where praxis.yaml comes from: render (gatewayConfig.render), existing
(config.existingConfigMap), or inline (config.inline in a chart-managed ConfigMap).
*/}}
{{- define "praxis-gateway.configSource" -}}
{{- if .Values.gatewayConfig.render -}}
render
{{- else if .Values.config.existingConfigMap -}}
existing
{{- else -}}
inline
{{- end -}}
{{- end }}

{{/*
Fail early on a blank or unparseable config.inline, or one with no listener on
port.containerPort, instead of a pod that crash-loops or never turns ready. Also fail
on grid settings that only the rendered config reads, which inline would drop quietly.
*/}}
{{- define "praxis-gateway.validateInlineConfig" -}}
{{- range $key := list "localSite" "model" }}
{{- if get $.Values.gatewayConfig $key }}
{{- fail (printf "gatewayConfig.%s is set but config.inline is serving, and inline ignores it: add gatewayConfig.backends, role provider, or gridServing to render the grid config, or unset gatewayConfig.%s" $key $key) }}
{{- end }}
{{- end }}
{{- $inline := toString (.Values.config.inline | default "") }}
{{- if not (trim $inline) }}
{{- fail "config.inline is empty: set it to a Praxis configuration, or set config.existingConfigMap" }}
{{- end }}
{{- $parsed := fromYaml $inline }}
{{- if hasKey $parsed "Error" }}
{{- fail (printf "config.inline is not a valid YAML mapping: %s" (get $parsed "Error")) }}
{{- end }}
{{- $port := int .Values.port.containerPort }}
{{- $listeners := $parsed.listeners }}
{{- if not (kindIs "slice" $listeners) }}{{- $listeners = list }}{{- end }}
{{- $bound := false }}
{{- range $listeners }}
{{- if and (kindIs "map" .) (hasSuffix (printf ":%d" $port) (toString .address)) }}{{- $bound = true }}{{- end }}
{{- end }}
{{- if not $bound }}
{{- fail (printf "config.inline has no listener on port.containerPort %d, where the Service and probes connect: bind a listener address to port %d, or change port.containerPort" $port $port) }}
{{- end }}
{{- end }}

{{/*
Whether the Praxis container gets imageUser's numeric IDs: only when podSecurityContext
sets no runAsUser, and imageUser.enabled is true, or auto on an official image off
OpenShift. The kubelet needs a numeric user to enforce runAsNonRoot, and a pod
runAsGroup does not provide one. Emits "true" or nothing.
*/}}
{{- define "praxis-gateway.applyImageUser" -}}
{{- $psc := .Values.podSecurityContext | default dict -}}
{{- $e := toString (.Values.imageUser | default dict).enabled -}}
{{- $auto := and (eq $e "auto") (include "praxis-gateway.officialImageUser" .) (not (include "praxis-gateway.openshift" .)) -}}
{{- if and (not (hasKey $psc "runAsUser")) (or (eq $e "true") $auto) -}}
true
{{- end -}}
{{- end }}

{{/*
Whether the image is one whose user imageUser's defaults describe: the official
praxis-proxy ai, praxis, or grid-gateway repository, or a mirror that keeps that path.
-fips tags are left out, since their UBI build runs as 1001:1001. Any other image keeps
the user it declares. Emits "true" or nothing.
*/}}
{{- define "praxis-gateway.officialImageUser" -}}
{{- if and (regexMatch "(^|/)praxis-proxy/(ai|praxis|grid-gateway)$" .Values.image.repository) (not (hasSuffix "-fips" (toString .Values.image.tag))) -}}
true
{{- end -}}
{{- end }}

{{/*
Whether the cluster is OpenShift, where the restricted SCC assigns pod UIDs from the
namespace range and rejects fixed ones outside it. Emits "true" or nothing.
*/}}
{{- define "praxis-gateway.openshift" -}}
{{- if .Capabilities.APIVersions.Has "security.openshift.io/v1" -}}
true
{{- end -}}
{{- end }}

{{/*
Validate each backend's effective transport. mutual_tls presents the gateway's
grid identity (the tls mount) and needs a sni naming the peer; plaintext must not
carry a sni.
*/}}
{{- define "praxis-gateway.validateBackends" -}}
{{- $tlsEnabled := .Values.tls.enabled }}
{{- $seen := dict }}
{{- range .Values.gatewayConfig.backends | default list }}
{{- if hasKey $seen .cluster }}
{{- fail (printf "gatewayConfig.backends: cluster %q is listed twice; cluster names must be unique" .cluster) }}
{{- end }}
{{- $_ := set $seen .cluster true }}
{{- $mode := (.transport).mode | default (ternary "mutual_tls" "plaintext" $tlsEnabled) }}
{{- if eq $mode "mutual_tls" }}
{{- if not $tlsEnabled }}
{{- fail (printf "backend %q uses mutual_tls but tls.enabled is false: no grid identity is mounted to present" .cluster) }}
{{- end }}
{{- if not (or (.transport).sni .site) }}
{{- fail (printf "backend %q uses mutual_tls but sets no transport.sni or site to verify the peer against" .cluster) }}
{{- end }}
{{- else if eq $mode "plaintext" }}
{{- if (.transport).sni }}
{{- fail (printf "backend %q is plaintext but sets transport.sni; sni belongs to a TLS transport" .cluster) }}
{{- end }}
{{- else if eq $mode "tls" }}
{{- if include "praxis-gateway.isIPHost" (include "praxis-gateway.backendSni" .) }}
{{- fail (printf "backend %q uses tls to an IP endpoint without transport.sni: set transport.sni to a DNS name on the certificate, or use the Service hostname as the endpoint" .cluster) }}
{{- end }}
{{- else }}
{{- fail (printf "backend %q transport.mode must be mutual_tls, tls, or plaintext, got %q" .cluster $mode) }}
{{- end }}
{{- if and (eq $mode "mutual_tls") (ne ($.Values.gatewayConfig.role | default "consumer") "provider") (not ($.Values.gridServing).enabled) }}
{{- if not .site }}
{{- fail (printf "backend %q is a remote site over mutual_tls: set its site, the grid site name it serves" .cluster) }}
{{- end }}
{{- if eq .site $.Values.gatewayConfig.localSite }}
{{- fail (printf "backend %q names site %q, which is this gateway's localSite: a remote backend is another site" .cluster .site) }}
{{- end }}
{{- end }}
{{- if and .connectTimeoutMs .totalConnectTimeoutMs (gt (int .connectTimeoutMs) (int .totalConnectTimeoutMs)) }}
{{- fail (printf "backend %q connectTimeoutMs must not exceed totalConnectTimeoutMs" .cluster) }}
{{- end }}
{{- if .trustPrivate }}
{{- $hosts := list }}
{{- range .endpoints }}{{- $h := include "praxis-gateway.endpointHost" . }}{{- if not (include "praxis-gateway.isIPHost" $h) }}{{- $hosts = append $hosts $h }}{{- end }}{{- end }}
{{- if not $hosts }}
{{- fail (printf "backend %q sets trustPrivate but has no hostname endpoint; an IP endpoint is never resolved" .cluster) }}
{{- end }}
{{- if and (eq $mode "plaintext") (not .allowPlaintextTrust) }}
{{- fail (printf "backend %q sets trustPrivate over plaintext: whoever controls the name's DNS gets the traffic unverified; use tls, or set allowPlaintextTrust for a Service you own" .cluster) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate enabled mounts have a non-empty resource name.
*/}}
{{- define "praxis-gateway.validateMounts" -}}
{{- if and .Values.overlay.enabled (not .Values.overlay.existingConfigMap) }}
{{- fail "overlay.existingConfigMap is required when overlay.enabled is true" }}
{{- end }}
{{- if and .Values.overlay.enabled .Values.overlay.sidecar.enabled (not .Values.overlay.sidecar.expectedNetwork) }}
{{- fail "overlay.sidecar.expectedNetwork is required when overlay sidecar is enabled" }}
{{- end }}
{{- if and .Values.overlay.enabled .Values.overlay.sidecar.enabled (not .Values.overlay.sidecar.expectedLocalSite) }}
{{- fail "overlay.sidecar.expectedLocalSite is required when overlay sidecar is enabled" }}
{{- end }}
{{- if and .Values.tls.enabled (not .Values.tls.existingSecret) }}
{{- fail "tls.existingSecret is required when tls.enabled is true" }}
{{- end }}
{{- with (.Values.gridServing | default dict) }}
{{- if .enabled }}
{{- $name := include "praxis-gateway.servingConfigMap" $ }}
{{- if not $name }}
{{- fail "gridServing needs gridServing.network, the GridNetwork name, or gridServing.configMap" }}
{{- end }}
{{- if gt (len $name) 63 }}
{{- fail (printf "gridServing: the operator hash-suffixes %s; set gridServing.configMap to the ConfigMap labeled grid.praxis-proxy.io/gateway" $name) }}
{{- end }}
{{- if not (and $.Values.tls.enabled $.Values.tls.existingSecret $.Values.tls.caSecret) }}
{{- fail "gridServing polls peers with the grid identity: set tls.enabled, tls.existingSecret, and tls.caSecret" }}
{{- end }}
{{- if eq ($.Values.gatewayConfig.role | default "consumer") "provider" }}
{{- fail "gridServing routes callers across sites; it applies to the consumer role only" }}
{{- end }}
{{- if ne $.Values.image.flavor "grid-gateway" }}
{{- fail "gridServing needs image.flavor grid-gateway" }}
{{- end }}
{{- end }}
{{- end }}
{{- if and .Values.gatewayConfig.listenerTls.enabled (not .Values.gatewayConfig.listenerTls.existingSecret) }}
{{- fail "gatewayConfig.listenerTls.existingSecret is required when gatewayConfig.listenerTls.enabled is true" }}
{{- end }}
{{- end }}

{{/*
The operator's serving config ConfigMap for this gateway: grid-serving-<network>-<gatewayRef>.
*/}}
{{- define "praxis-gateway.servingConfigMap" -}}
{{- $serving := .Values.gridServing | default dict -}}
{{- if $serving.configMap -}}
{{- $serving.configMap -}}
{{- else if $serving.network -}}
{{- printf "grid-serving-%s-%s" $serving.network ($serving.gatewayRef | default (include "praxis-gateway.fullname" .)) -}}
{{- end -}}
{{- end }}

{{/*
Listener port name: port.name when set, else https when the listener terminates TLS.
*/}}
{{- define "praxis-gateway.portName" -}}
{{- .Values.port.name | default (ternary "https" "http" .Values.gatewayConfig.listenerTls.enabled) -}}
{{- end }}

{{/*
Probe with an empty tcpSocket pointed at the listener port.
*/}}
{{- define "praxis-gateway.probe" -}}
{{- $probe := deepCopy (index . 0) -}}
{{- $root := index . 1 -}}
{{- if or $probe.httpGet $probe.exec $probe.grpc -}}
{{- $_ := unset $probe "tcpSocket" -}}
{{- else if and (hasKey $probe "tcpSocket") (not (($probe.tcpSocket | default dict).port)) -}}
{{- $_ := set $probe "tcpSocket" (dict "port" (include "praxis-gateway.portName" $root)) -}}
{{- end -}}
{{- toYaml $probe -}}
{{- end }}

{{/*
Whether a label selector matches everything: absent, {}, or empty matchLabels and
matchExpressions. Emits "true" or nothing.
*/}}
{{- define "praxis-gateway.selectsAll" -}}
{{- $sel := . | default dict -}}
{{- if and (not $sel.matchLabels) (not $sel.matchExpressions) -}}
true
{{- end -}}
{{- end }}

{{/*
SNI for a tls backend: transport.sni, else the first endpoint's host.
*/}}
{{- define "praxis-gateway.backendSni" -}}
{{- if (.transport).sni -}}
{{- .transport.sni -}}
{{- else if and .site (not (has ((.transport).mode | default "") (list "tls" "plaintext"))) -}}
{{- printf "%s.grid.internal" .site -}}
{{- else -}}
{{- include "praxis-gateway.endpointHost" (first .endpoints) -}}
{{- end -}}
{{- end }}

{{/*
An endpoint's host: port and one trailing root dot removed.
*/}}
{{- define "praxis-gateway.endpointHost" -}}
{{- regexReplaceAll "\\.?:[0-9]+$" . "" -}}
{{- end }}

{{/*
"true" for an IP literal host: bracketed IPv6 or dotted digits.
*/}}
{{- define "praxis-gateway.isIPHost" -}}
{{- if regexMatch "^(\\[|[0-9.]+$)" . }}true{{ end -}}
{{- end }}

{{/*
Grid CA Secret: tls.caSecret, or grid-ca for a provider, which always needs one.
*/}}
{{- define "praxis-gateway.caSecret" -}}
{{- .Values.tls.caSecret | default (ternary "grid-ca" "" (eq (.Values.gatewayConfig.role | default "consumer") "provider")) -}}
{{- end }}

{{/*
A grid gateway: a provider, or a consumer with a site backend. Emits "true" or nothing.
*/}}
{{- define "praxis-gateway.gridIdentity" -}}
{{- $cfg := .Values.gatewayConfig }}
{{- $grid := eq ($cfg.role | default "consumer") "provider" }}
{{- if kindIs "map" $cfg.backends }}{{- if $cfg.backends }}{{- $grid = true }}{{- end }}{{- end }}
{{- if kindIs "slice" $cfg.backends }}{{- range $cfg.backends }}{{- if .site }}{{- $grid = true }}{{- end }}{{- end }}{{- end }}
{{- if $grid }}true{{- end }}
{{- end }}
