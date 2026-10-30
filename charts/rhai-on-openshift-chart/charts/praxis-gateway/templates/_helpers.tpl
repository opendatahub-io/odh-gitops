{{/*
Normalize values once per render, in place and idempotently: backends keyed by site
become the list the templates read, keys in sorted order.
*/}}
{{- define "praxis-gateway.normalize" -}}
{{- $v := .Values }}
{{- $cfg := $v.praxisConfig.render }}
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
{{- else if kindIs "slice" $cfg.backends }}
{{- $list := list }}
{{- range $cfg.backends }}
{{- $backend := deepCopy . }}
{{- $mode := ($backend.transport).mode | default "" }}
{{- if and $provider (eq ($backend.cluster | default "") "local") (not $mode) }}
{{- $_ := set $backend "transport" (merge (dict "mode" "plaintext") ($backend.transport | default dict)) }}
{{- end }}
{{- $list = append $list $backend }}
{{- end }}
{{- $_ := set $cfg "backends" $list }}
{{- end }}
{{- if not $v.service.type }}{{- $_ := set $v.service "type" (ternary "LoadBalancer" "ClusterIP" $provider) }}{{- end }}
{{- if hasSuffix "/grid-gateway" $v.image.repository }}{{- $_ := set $v.image "flavor" "grid-gateway" }}{{- end }}
{{- include "praxis-gateway.resolveMetricsListener" . }}
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
{{- $image := include "praxis-gateway.relatedImage" (dict "root" . "name" "RELATED_IMAGE_ODH_PRAXIS_AI_GRID_GATEWAY_IMAGE") -}}
{{- if $image -}}
{{- $image -}}
{{- else -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (default .Chart.AppVersion .Values.image.tag) }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Overlay-sync image reference.
Defaults the tag to the chart appVersion when empty.
*/}}
{{- define "praxis-gateway.overlaySyncImage" -}}
{{- $image := include "praxis-gateway.relatedImage" (dict "root" . "name" "RELATED_IMAGE_ODH_PRAXIS_AI_GRID_OVERLAY_SYNC_IMAGE") -}}
{{- if $image -}}
{{- $image -}}
{{- else -}}
{{- printf "%s:%s" .Values.overlay.sidecar.image.repository (default .Chart.AppVersion .Values.overlay.sidecar.image.tag) }}
{{- end }}
{{- end }}

{{/*
Site names the configured SPIFFE IDs belong to, newline separated.
*/}}
{{- define "praxis-gateway.peerSites" -}}
{{- $sites := list -}}
{{- range . -}}
{{- $rest := . | trimPrefix "spiffe://" -}}
{{- if eq $rest . -}}
{{- fail (printf "praxisConfig.render.peerTrust.spiffeIds: %q is not a spiffe:// identity" .) -}}
{{- end -}}
{{- $parts := splitList "/" $rest -}}
{{- if or (ne (len $parts) 3) (ne (index $parts 1) "site") (not (index $parts 2)) -}}
{{- fail (printf "praxisConfig.render.peerTrust.spiffeIds: %q is not spiffe://<trust-domain>/site/<name>" .) -}}
{{- end -}}
{{- $sites = append $sites (index $parts 2) -}}
{{- end -}}
{{- join "\n" ($sites | uniq) -}}
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
Validate praxisConfig: the source, and that each source gets only the settings it reads.
*/}}
{{- define "praxis-gateway.validateConfig" -}}
{{- $source := .Values.praxisConfig.source }}
{{- $render := .Values.praxisConfig.render | default dict }}
{{- $provider := eq ($render.role | default "consumer") "provider" }}
{{- $auth := $render.auth | default dict }}
{{- $peerTrust := $render.peerTrust | default dict }}
{{- $validateCA := $auth.validateCA | default dict }}
{{- $gridServing := $render.gridServing | default dict }}
{{- $telemetry := $render.telemetry | default dict }}
{{- with $telemetry.otlpEndpoint }}
{{- if not (hasPrefix "https://" .) }}
{{- fail "praxisConfig.render.telemetry.otlpEndpoint must use https://; plaintext telemetry can expose credentials" }}
{{- end }}
{{- end }}
{{- if $telemetry.enabled }}
{{- if ne .Values.image.flavor "grid-gateway" }}
{{- fail "praxisConfig.render.telemetry.enabled needs image.flavor grid-gateway, whose Grid gateway build includes the OTLP and AI routing span features" }}
{{- end }}
{{- if ne $source "render" }}
{{- fail "praxisConfig.render.telemetry.enabled needs praxisConfig.source render so the exporter settings are written to praxis.yaml" }}
{{- end }}
{{- end }}
{{- if not (has $source (list "byo" "operator" "render")) }}
{{- fail (printf "praxisConfig.source must be byo, operator, or render, got %q" (toString $source)) }}
{{- end }}
{{- if ne $source "render" }}
{{- range $key := list "model" }}
{{- if get $render $key }}
{{- fail (printf "praxisConfig.render.%s is set but praxisConfig.source is %s, which ignores it: set praxisConfig.source to render, or unset it" $key $source) }}
{{- end }}
{{- end }}
{{- if or $render.backends $auth.mode $telemetry.enabled $provider $gridServing.enabled $gridServing.backendCAs $peerTrust.certDigests $auth.validateUrl $validateCA.configMapName $validateCA.secretName }}
{{- fail (printf "praxisConfig.render settings are set but praxisConfig.source is %s, which ignores them: set praxisConfig.source to render, or unset them" $source) }}
{{- end }}
{{- end }}
{{- if eq $source "operator" }}
{{- if and .Values.service.enabled (has .Values.service.type (list "LoadBalancer" "NodePort")) (not .Values.praxisConfig.operator.allowUnauthenticatedExposure) }}
{{- fail (printf "praxisConfig.source operator with a %s Service exposes unauthenticated inference: the operator's praxis.yaml has no caller authentication. Use a ClusterIP Service behind an authenticating front, or set praxisConfig.operator.allowUnauthenticatedExposure" .Values.service.type) }}
{{- end }}
{{- if .Values.listenerTls.secretName }}
{{- fail "listenerTls.secretName is not supported with praxisConfig.source operator: the operator's praxis.yaml has no listener TLS. Terminate TLS in front of the gateway, or use source byo or render" }}
{{- end }}
{{- if .Values.upstreamCA.secretName }}
{{- fail "upstreamCA.secretName is not supported with praxisConfig.source operator: the operator's praxis.yaml has no upstream_ca_file. Use source byo or render." }}
{{- end }}
{{- else if and (eq $source "byo") (not .Values.praxisConfig.byo.configMapName) }}
{{- include "praxis-gateway.validateInlineConfig" . }}
{{- end }}
{{- if eq $source "render" }}
{{- if not (trim (toString .Values.grid.siteName)) }}
{{- fail "grid.siteName is required when praxisConfig.source is render, and cannot be blank" }}
{{- end }}
{{- if and (not $provider) (not $gridServing.enabled) (not (trim (toString $render.model))) }}
{{- fail "praxisConfig.render.model is required for a consumer without praxisConfig.render.gridServing, and cannot be blank" }}
{{- end }}
{{- if and (not ($render.backends | default list)) (not $gridServing.enabled) }}
{{- fail "praxisConfig.render.backends needs at least one backend when praxisConfig.source is render without gridServing" }}
{{- end }}
{{- include "praxis-gateway.validateBackendCAs" . }}
{{- if and (not $auth.mode) (not $provider) }}
{{- fail "praxisConfig.render.auth.mode is required when praxisConfig.source is render: api-key (needs an image with praxis-policy 0.4 or later) or none (only behind an authenticating front)" }}
{{- end }}
{{- if $provider }}
{{- if eq ($auth.mode | default "none") "api-key" }}
{{- fail "praxisConfig.render.auth.mode api-key is only supported for consumers; providers authenticate peers by grid identity" }}
{{- end }}
{{- if ne .Values.image.flavor "grid-gateway" }}
{{- fail "praxisConfig.render.role provider needs image.flavor grid-gateway" }}
{{- end }}
{{- if not .Values.gridIdentity.tlsSecretName }}
{{- fail "praxisConfig.render.role provider needs gridIdentity.tlsSecretName for its client identity and Grid CA" }}
{{- end }}
{{- if $gridServing.enabled }}
{{- /* The operator's provider file names the backends and the admitted sites, so the chart names neither. */}}
{{- if $render.backends }}
{{- fail "praxisConfig.render.role provider with gridServing serves the backends the operator's provider file names; unset praxisConfig.render.backends" }}
{{- end }}
{{- if ne ($peerTrust.mode | default "pin") "spiffe" }}
{{- fail "praxisConfig.render.role provider with gridServing admits peers by their Grid-CA SVID: set praxisConfig.render.peerTrust.mode spiffe" }}
{{- end }}
{{- if or $peerTrust.spiffeIds $peerTrust.allowAnyGridSite $peerTrust.certDigests }}
{{- fail "praxisConfig.render.role provider with gridServing admits the sites the operator's provider file lists; unset peerTrust spiffeIds, allowAnyGridSite and certDigests" }}
{{- end }}
{{- else if ne (len $render.backends) 1 }}
{{- fail "praxisConfig.render.role provider routes to exactly one local backend" }}
{{- end }}
{{- if .Values.listenerTls.secretName }}
{{- fail "praxisConfig.render.role provider serves the grid identity; unset listenerTls" }}
{{- end }}
{{- if and (eq ($peerTrust.mode | default "pin") "spiffe") (not $gridServing.enabled) }}
{{- if and (not $peerTrust.spiffeIds) (not $peerTrust.allowAnyGridSite) }}
{{- fail "praxisConfig.render.peerTrust spiffe mode needs spiffeIds, or allowAnyGridSite true to admit every Grid-CA site" }}
{{- end }}
{{- if and $peerTrust.spiffeIds $peerTrust.allowAnyGridSite }}
{{- fail "praxisConfig.render.peerTrust.allowAnyGridSite admits every Grid-CA site, so it cannot be set beside spiffeIds" }}
{{- end }}
{{- $_ := include "praxis-gateway.peerSites" ($peerTrust.spiffeIds | default list) }}
{{- else if and (not $gridServing.enabled) (not $peerTrust.certDigests) }}
{{- fail "praxisConfig.render.peerTrust pin mode needs certDigests" }}
{{- end }}
{{- else if $peerTrust.certDigests }}
{{- fail "praxisConfig.render.peerTrust.certDigests is only supported for role provider" }}
{{- end }}
{{- if and (not $provider) (eq $auth.mode "none") .Values.service.enabled (has .Values.service.type (list "LoadBalancer" "NodePort")) (not $auth.allowUnauthenticatedExposure) }}
{{- fail (printf "praxisConfig.render.auth.mode none with a %s Service exposes unauthenticated inference; use api-key, a ClusterIP Service behind an authenticating front, or set praxisConfig.render.auth.allowUnauthenticatedExposure" .Values.service.type) }}
{{- end }}
{{- if and $validateCA.configMapName $validateCA.secretName }}
{{- fail "praxisConfig.render.auth.validateCA: set configMapName or secretName, not both" }}
{{- end }}
{{- if and (ne ($auth.mode | default "") "api-key") (or $auth.validateUrl $validateCA.configMapName $validateCA.secretName) }}
{{- fail "praxisConfig.render.auth.validateUrl and validateCA require auth.mode api-key" }}
{{- end }}
{{- if eq $auth.mode "api-key" }}
{{- if not $auth.validateUrl }}
{{- fail "praxisConfig.render.auth.validateUrl is required when praxisConfig.render.auth.mode is api-key" }}
{{- end }}
{{- if not (hasPrefix "https://" $auth.validateUrl) }}
{{- fail "praxisConfig.render.auth.validateUrl must be https: a plaintext validate call ships the credential in the clear" }}
{{- end }}
{{- if regexMatch "^https://(\\[|[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+([:/]|$))" $auth.validateUrl }}
{{- fail "praxisConfig.render.auth.validateUrl must name a host, not an IP address: https to an IP literal has no SNI to verify" }}
{{- end }}
{{- /* The legacy 0.4.0 image predates praxis-policy 0.4, which adds identity/api-key. */}}
{{- if eq (include "praxis-gateway.image" .) "ghcr.io/praxis-proxy/ai:0.4.0" }}
{{- fail "praxisConfig.render.auth.mode api-key is unsupported on the legacy image ghcr.io/praxis-proxy/ai:0.4.0: its policy engine lacks identity/api-key (praxis-policy 0.4 or later). Set image to a build that registers it, or use auth.mode none behind an authenticating front." }}
{{- end }}
{{- end }}
{{- include "praxis-gateway.validateBackends" . }}
{{- end }}
{{- if and (eq $source "byo") .Values.praxisConfig.byo.configMapName }}
{{- if not (lookup "v1" "ConfigMap" .Release.Namespace .Values.praxisConfig.byo.configMapName) }}
{{- if lookup "v1" "Namespace" "" "kube-system" }}
{{- fail (printf "ConfigMap %q not found in namespace %q. Create it before installing praxis-gateway." .Values.praxisConfig.byo.configMapName .Release.Namespace) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Where praxis.yaml comes from: render (praxisConfig.source render), operator (the Grid
operator's ConfigMap), byoConfigMap (byo with praxisConfig.byo.configMapName), or byoInline
(byo with praxisConfig.byo.inline in a chart-managed ConfigMap).
*/}}
{{- define "praxis-gateway.configSource" -}}
{{- if eq .Values.praxisConfig.source "render" -}}
render
{{- else if eq .Values.praxisConfig.source "operator" -}}
operator
{{- else if .Values.praxisConfig.byo.configMapName -}}
byoConfigMap
{{- else -}}
byoInline
{{- end -}}
{{- end }}

{{/*
Fail early on a blank or unparseable praxisConfig.byo.inline, or one with no listener on
port.containerPort, instead of a pod that crash-loops or never turns ready.
*/}}
{{- define "praxis-gateway.validateInlineConfig" -}}
{{- $inline := toString (.Values.praxisConfig.byo.inline | default "") }}
{{- if not (trim $inline) }}
{{- fail "praxisConfig.byo.inline is empty: set it to a Praxis configuration, or set praxisConfig.byo.configMapName" }}
{{- end }}
{{- $parsed := fromYaml $inline }}
{{- if hasKey $parsed "Error" }}
{{- fail (printf "praxisConfig.byo.inline is not a valid YAML mapping: %s" (get $parsed "Error")) }}
{{- end }}
{{- $port := int .Values.port.containerPort }}
{{- $listeners := $parsed.listeners }}
{{- if not (kindIs "slice" $listeners) }}{{- $listeners = list }}{{- end }}
{{- $bound := false }}
{{- range $listeners }}
{{- if and (kindIs "map" .) (hasSuffix (printf ":%d" $port) (toString .address)) }}{{- $bound = true }}{{- end }}
{{- end }}
{{- if not $bound }}
{{- fail (printf "praxisConfig.byo.inline has no listener on port.containerPort %d, where the Service and probes connect: bind a listener address to port %d, or change port.containerPort" $port $port) }}
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
{{- $override := include "praxis-gateway.relatedImage" (dict "root" . "name" "RELATED_IMAGE_ODH_PRAXIS_AI_GRID_GATEWAY_IMAGE") -}}
{{- $auto := and (eq $e "auto") (not $override) (include "praxis-gateway.officialImageUser" .) (not (include "praxis-gateway.openshift" .)) -}}
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
Validate each backend's effective transport. mutual_tls presents the configured
grid identity and needs a sni naming the peer; plaintext must not
carry a sni.
*/}}
{{- define "praxis-gateway.validateBackends" -}}
{{- $tlsEnabled := not (empty .Values.gridIdentity.tlsSecretName) }}
{{- $seen := dict }}
{{- range .Values.praxisConfig.render.backends | default list }}
{{- if hasKey $seen .cluster }}
{{- fail (printf "praxisConfig.render.backends: cluster %q is listed twice; cluster names must be unique" .cluster) }}
{{- end }}
{{- $_ := set $seen .cluster true }}
{{- $mode := (.transport).mode | default (ternary "mutual_tls" "plaintext" $tlsEnabled) }}
{{- if and .site (not (.transport).mode) (not $tlsEnabled) }}
{{- fail (printf "backend %q serves the remote site %q but gridIdentity.tlsSecretName is empty, so it would use plaintext. Set gridIdentity.tlsSecretName for mTLS, or set transport.mode plaintext and site %q to send it in the clear" .cluster .site .site) }}
{{- end }}
{{- if eq $mode "mutual_tls" }}
{{- if not $tlsEnabled }}
{{- fail (printf "backend %q uses mutual_tls but gridIdentity.tlsSecretName is empty: no grid identity is mounted to present" .cluster) }}
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
{{- if and (eq $mode "mutual_tls") (ne ($.Values.praxisConfig.render.role | default "consumer") "provider") (not ($.Values.praxisConfig.render.gridServing).enabled) }}
{{- if not .site }}
{{- fail (printf "backend %q is a remote site over mutual_tls: set its site, the grid site name it serves" .cluster) }}
{{- end }}
{{- if eq .site $.Values.grid.siteName }}
{{- fail (printf "backend %q names site %q, which is this gateway's grid.siteName: a remote backend is another site" .cluster .site) }}
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
{{- if .Values.mountReconciliation.enabled }}
{{- if not .Values.mountReconciliation.network }}
{{- fail "mountReconciliation.network is required when mount reconciliation is enabled" }}
{{- end }}
{{- if ne (.Values.praxisConfig.render.role | default "consumer") "consumer" }}
{{- fail "mount reconciliation is supported for consumer gateways only" }}
{{- end }}
{{- $source := .Values.praxisConfig.source }}
{{- if eq $source "render" }}
{{- fail "mount reconciliation requires the operator-generated consumer ConfigMap, not praxisConfig.source render" }}
{{- end }}
{{- if and (eq $source "byo") (not .Values.praxisConfig.byo.configMapName) }}
{{- fail "praxisConfig.byo.configMapName must name consumerConfig.configMapName when mount reconciliation is enabled" }}
{{- end }}
{{- if and (eq $source "byo") (ne .Values.praxisConfig.byo.key "praxis.yaml") }}
{{- fail "praxisConfig.byo.key must be praxis.yaml when mount reconciliation is enabled" }}
{{- end }}
{{- end }}
{{- if and .Values.mountReconciliation.releaseHelmMounts (not .Values.mountReconciliation.enabled) }}
{{- fail "mountReconciliation.releaseHelmMounts requires mountReconciliation.enabled" }}
{{- end }}
{{- if and .Values.gridIdentity.caSecretName (not .Values.gridIdentity.tlsSecretName) }}
{{- fail "gridIdentity.tlsSecretName is required when gridIdentity.caSecretName is set" }}
{{- end }}
{{- if and .Values.overlay.configMapName .Values.overlay.sidecar.enabled (not .Values.grid.networkName) }}
{{- fail "grid.networkName is required when the overlay sidecar is on: set it, or set overlay.sidecar.enabled false." }}
{{- end }}
{{- if and .Values.overlay.configMapName .Values.overlay.sidecar.enabled (not .Values.grid.siteName) }}
{{- fail "grid.siteName is required when the overlay sidecar is on: set it, or set overlay.sidecar.enabled false." }}
{{- end }}
{{- if and .Values.overlay.configMapName (ne .Values.praxisConfig.source "byo") }}
{{- fail (printf "overlay.configMapName is only supported with praxisConfig.source byo; source %s writes candidates directly into praxis.yaml" .Values.praxisConfig.source) }}
{{- end }}
{{- $serving := include "praxis-gateway.gridServing" . | fromYaml }}
{{- if $serving.enabled }}
{{- $key := printf "praxisConfig.%s.gridServing" .Values.praxisConfig.source }}
{{- if ne .Values.gridIdentity.mountPath "/etc/praxis/tls" }}
{{- fail (printf "%s requires gridIdentity.mountPath=/etc/praxis/tls because its peer pollers read TLS files from that path" $key) }}
{{- end }}
{{- $name := include "praxis-gateway.servingConfigMap" . }}
{{- if not $name }}
{{- fail (printf "%s needs networkName or configMapName" $key) }}
{{- end }}
{{- if gt (len $name) 63 }}
{{- fail (printf "%s: the operator hash-suffixes %s; set configMapName to the ConfigMap labeled grid.praxis.fast/gateway" $key $name) }}
{{- end }}
{{- if not .Values.gridIdentity.tlsSecretName }}
{{- fail (printf "%s polls peers with the grid identity: set gridIdentity.tlsSecretName" $key) }}
{{- end }}
{{- if and (eq (.Values.praxisConfig.render.role | default "consumer") "provider") (not (or $serving.gatewayRefName $serving.configMapName)) }}
{{- fail (printf "%s on a provider reads the consumer gateway's serving ConfigMap: set gatewayRefName to that gateway's name, or configMapName" $key) }}
{{- end }}
{{- if ne .Values.image.flavor "grid-gateway" }}
{{- fail (printf "%s needs image.flavor grid-gateway" $key) }}
{{- end }}
{{- if and (eq .Values.praxisConfig.source "operator") (not .Values.mountReconciliation.enabled) }}
{{- fail "praxisConfig.operator.gridServing needs mountReconciliation.enabled: every operator praxis.yaml revision must roll the pod so it re-reads its provider-hop backends" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate praxisConfig.render.gridServing.backendCAs.
*/}}
{{- define "praxis-gateway.validateBackendCAs" -}}
{{- $serving := .Values.praxisConfig.render.gridServing | default dict }}
{{- if $serving.backendCAs }}
{{- if not $serving.enabled }}
{{- fail "praxisConfig.render.gridServing.backendCAs needs praxisConfig.render.gridServing.enabled: the CAs are for the operator's dials" }}
{{- end }}
{{- if .Values.mountReconciliation.enabled }}
{{- fail "praxisConfig.render.gridServing.backendCAs and mountReconciliation both mount /run/secrets/grid-backend-ca: let the operator mount the CAs, or disable mountReconciliation" }}
{{- end }}
{{- end }}
{{- $dirs := dict }}
{{- range $serving.backendCAs }}
{{- if eq (empty .secretName) (empty .configMapName) }}
{{- fail "praxisConfig.render.gridServing.backendCAs: set secretName or configMapName on each entry, not both" }}
{{- end }}
{{- $dir := include "praxis-gateway.backendCADir" . }}
{{- if hasKey $dirs $dir }}
{{- fail (printf "praxisConfig.render.gridServing.backendCAs: %s is listed twice; one entry per Secret or ConfigMap" $dir) }}
{{- end }}
{{- $_ := set $dirs $dir true }}
{{- end }}
{{- end }}

{{/*
A backendCAs entry's directory under /run/secrets/grid-backend-ca, named as the operator's dns_safe names it.
*/}}
{{- define "praxis-gateway.backendCADir" -}}
{{- regexReplaceAll "[^a-z0-9]+" (lower (.secretName | default .configMapName)) "-" | trimAll "-" | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
The operator's serving config ConfigMap for this gateway: grid-serving-<networkName>-<gatewayRefName>.
*/}}
{{- define "praxis-gateway.servingConfigMap" -}}
{{- $serving := include "praxis-gateway.gridServing" . | fromYaml -}}
{{- $operator := eq .Values.praxisConfig.source "operator" -}}
{{- $network := $serving.networkName | default (ternary .Values.mountReconciliation.network .Values.grid.networkName $operator) -}}
{{- $gateway := $serving.gatewayRefName | default (ternary .Values.mountReconciliation.gatewayRef "" $operator) | default (include "praxis-gateway.fullname" .) -}}
{{- if $serving.configMapName -}}
{{- $serving.configMapName -}}
{{- else if $network -}}
{{- printf "grid-serving-%s-%s" $network $gateway -}}
{{- end -}}
{{- end }}

{{/*
The gridServing block the selected source reads, as YAML: render's, operator's, or none.
*/}}
{{- define "praxis-gateway.gridServing" -}}
{{- $source := .Values.praxisConfig.source -}}
{{- if eq $source "render" -}}
{{- toYaml (.Values.praxisConfig.render.gridServing | default dict) -}}
{{- else if eq $source "operator" -}}
{{- toYaml ((.Values.praxisConfig.operator).gridServing | default dict) -}}
{{- end -}}
{{- end }}

{{/* Service annotations, the platform's merged under the Service's own. Only a LoadBalancer gets the platform's. */}}
{{- define "praxis-gateway.serviceAnnotations" -}}
{{- $svc := .Values.service -}}
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
Listener port name: port.name when set, else https when the listener terminates TLS.
*/}}
{{- define "praxis-gateway.portName" -}}
{{- .Values.port.name | default (ternary "https" "http" (not (empty .Values.listenerTls.secretName))) -}}
{{- end }}

{{/*
Probe with an empty tcpSocket pointed at the listener port.
*/}}
{{/*
Whether the gateway forwards to backend clusters: rendered backends, either source's gridServing,
or clusters in praxisConfig.byo.inline. Praxis /ready fails while any of them is down. Emits "true"
or nothing.
*/}}
{{- define "praxis-gateway.servesBackends" -}}
{{- $v := .Values -}}
{{- if or (and (eq $v.praxisConfig.source "render") $v.praxisConfig.render.backends) (include "praxis-gateway.gridServing" . | fromYaml).enabled -}}
true
{{- else if and (eq $v.praxisConfig.source "byo") (not $v.praxisConfig.byo.configMapName) ((fromYaml ($v.praxisConfig.byo.inline | default "")).clusters) -}}
true
{{- end -}}
{{- end }}

{{/*
Refuse a probe on Praxis /ready while the gateway forwards to backends: one failing
backend would take every pod out of service.
*/}}
{{- define "praxis-gateway.validateProbes" -}}
{{- if include "praxis-gateway.servesBackends" . }}
{{- range $name, $probe := pick (.Values.health | default dict) "readiness" "liveness" }}
{{- $probe = $probe | default dict }}
{{- $target := printf "%s %s" (($probe.httpGet).path | default "") (join " " (($probe.exec).command | default list)) }}
{{- if regexMatch "/ready([?/ ]|$)" $target }}
{{- fail (printf "health.%s must not probe Praxis /ready while the gateway forwards to backends: one failing backend would take every gateway pod out of service. Probe /healthy, which only checks that Praxis is up." $name) }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{- define "praxis-gateway.probe" -}}
{{- $probe := deepCopy (index . 0) -}}
{{- $root := index . 1 -}}
{{- $path := index . 2 -}}
{{- $admin := include "praxis-gateway.adminAddress" $root -}}
{{- if or $probe.httpGet $probe.exec $probe.grpc -}}
{{- $_ := unset $probe "tcpSocket" -}}
{{- else if and (hasKey $probe "tcpSocket") (not (($probe.tcpSocket | default dict).port)) -}}
{{- if $admin -}}
{{- /* A TCP connect to a TLS listener logs a failed handshake every period, so ask the admin listener instead. */ -}}
{{- $_ := unset $probe "tcpSocket" -}}
{{- $url := printf "http://%s%s" $admin $path -}}
{{- /* health.adminProbeCommand with the URL appended, else curl or wget, whichever the image has. */ -}}
{{- $cmd := (($root.Values.health).adminProbeCommand | default list) -}}
{{- if $cmd -}}
{{- $cmd = append $cmd $url -}}
{{- else -}}
{{- $cmd = list "/bin/sh" "-c" "if command -v curl >/dev/null 2>&1; then exec curl -fsS -m 2 -o /dev/null -H 'Host: 127.0.0.1' \"$1\"; else exec wget -q -T 2 --header 'Host: 127.0.0.1' -O /dev/null \"$1\"; fi" "probe" $url -}}
{{- end -}}
{{- $_ := set $probe "exec" (dict "command" $cmd) -}}
{{- if not (hasKey $probe "timeoutSeconds") -}}{{- $_ := set $probe "timeoutSeconds" 3 -}}{{- end -}}
{{- else if include "praxis-gateway.maybeTLSListener" $root -}}
{{- fail "health: the gateway serves TLS and the chart cannot see a loopback admin listener, so a TCP probe would fail a TLS handshake every period; give health.readiness and health.liveness an httpGet or exec probe, or add a loopback admin listener to praxisConfig.byo.inline" -}}
{{- else -}}
{{- $_ := set $probe "tcpSocket" (dict "port" (include "praxis-gateway.portName" $root)) -}}
{{- end -}}
{{- end -}}
{{- toYaml $probe -}}
{{- end }}

{{/*
Whether praxisConfig.byo.inline declares a TLS listener. A BYO ConfigMap is opaque, so it yields
nothing. Emits "true" or nothing.
*/}}
{{- define "praxis-gateway.maybeTLSListener" -}}
{{- $v := .Values -}}
{{- if and (eq $v.praxisConfig.source "byo") (not $v.praxisConfig.byo.configMapName) -}}
{{- range ((fromYaml ($v.praxisConfig.byo.inline | default "")).listeners | default list) -}}
{{- if .tls }}true{{ end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
Admin listener address the chart rendered itself.
*/}}
{{- define "praxis-gateway.renderedAdminAddress" -}}
127.0.0.1:9901
{{- end }}

{{/*
Loopback host:port of the admin listener when the chart knows the config: the rendered
config, else praxisConfig.byo.inline. A BYO ConfigMap is opaque, so it yields nothing.
*/}}
{{- define "praxis-gateway.adminAddress" -}}
{{- $v := .Values -}}
{{- $addr := "" -}}
{{- if eq $v.praxisConfig.source "render" -}}
{{- $addr = include "praxis-gateway.renderedAdminAddress" . -}}
{{- else if and (eq $v.praxisConfig.source "byo") (not $v.praxisConfig.byo.configMapName) -}}
{{- $admin := ((fromYaml ($v.praxisConfig.byo.inline | default "")).admin | default dict) -}}
{{- $addr = ($admin.metrics_address | default $admin.address | default "") | toString -}}
{{- end -}}
{{- if regexMatch "^(127\\.0\\.0\\.1|localhost|0\\.0\\.0\\.0):[0-9]+$" $addr -}}
{{- printf "127.0.0.1:%s" (regexReplaceAll "^.*:" $addr "") -}}
{{- end -}}
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
Provider credential path. Use an explicit mountPath or the Grid operator default.
*/}}
{{- define "praxis-gateway.providerCredentialPath" -}}
{{- $dir := trimAll "-" (regexReplaceAll "[^a-z0-9]+" (lower .secretName) "-") | trunc 63 | trimSuffix "-" -}}
{{- .mountPath | default (printf "/run/secrets/grid-credentials/%s" $dir) -}}
{{- end }}

{{/*
RUST_LOG for the gateway and overlay-sync: log.filter when set, else log.level, else empty (the binary default).
*/}}
{{- define "praxis-gateway.rustLog" -}}
{{- $log := .Values.log | default dict -}}
{{- $log.filter | default $log.level -}}
{{- end }}

{{/*
Resolve metricsListener.enabled and serviceMonitor.enabled to booleans. auto turns the
listener on for the grid-gateway image on OpenShift with the NetworkPolicy on, and fills
each unset value from the platform: a service serving cert, user workload monitoring, and
the service CA. Off OpenShift no cert source exists by default, so auto stays off.
*/}}
{{- define "praxis-gateway.resolveMetricsListener" -}}
{{- $v := .Values }}
{{- $m := $v.metricsListener }}
{{- if eq (toString $m.enabled) "auto" }}
{{- $openshift := include "praxis-gateway.openshift" . }}
{{- $grid := eq $v.image.flavor "grid-gateway" }}
{{- $on := and $grid $openshift $v.networkPolicy.enabled }}
{{- $_ := set $m "enabled" (not (empty $on)) }}
{{- if and $grid $openshift (not $v.networkPolicy.enabled) }}
{{- $_ := set $m "skipped" "networkPolicy.enabled is false" }}
{{- end }}
{{- if $m.enabled }}
{{- if not $m.existingSecret }}
{{- $annotations := $m.service.annotations | default dict }}
{{- /* The annotation names the Secret the platform creates, so the mount follows it. */}}
{{- $named := index $annotations "service.beta.openshift.io/serving-cert-secret-name" }}
{{- $secret := $named | default (printf "%s-metrics-tls" (include "praxis-gateway.fullname" .)) }}
{{- $_ := set $m "existingSecret" $secret }}
{{- $_ := set $annotations "service.beta.openshift.io/serving-cert-secret-name" $secret }}
{{- $_ := set $m.service "annotations" $annotations }}
{{- end }}
{{- if not $m.fromNamespaces }}
{{- $_ := set $m "fromNamespaces" (list "openshift-user-workload-monitoring") }}
{{- end }}
{{- if not $m.serviceMonitor.caConfigMap.name }}
{{- $_ := set $m.serviceMonitor "caConfigMap" (dict "name" "openshift-service-ca.crt" "key" "service-ca.crt") }}
{{- end }}
{{- end }}
{{- else }}
{{- $_ := set $m "enabled" (eq (toString $m.enabled) "true") }}
{{- end }}
{{- $sm := $m.serviceMonitor }}
{{- if eq (toString $sm.enabled) "auto" }}
{{- $_ := set $sm "enabled" (and $m.enabled (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1") (not (empty $sm.caConfigMap.name))) }}
{{- else }}
{{- $_ := set $sm "enabled" (eq (toString $sm.enabled) "true") }}
{{- end }}
{{- end }}

{{/*
The metrics listener needs the grid-gateway image, a cert, and the NetworkPolicy that
limits its port; without the policy any pod could scrape it.
*/}}
{{- define "praxis-gateway.validateMetricsListener" -}}
{{- $m := .Values.metricsListener }}
{{- if $m.enabled }}
{{- if ne .Values.image.flavor "grid-gateway" }}
{{- fail "metricsListener needs image.flavor grid-gateway" }}
{{- end }}
{{- if not $m.existingSecret }}
{{- fail "metricsListener.existingSecret is required: the listener serves TLS only" }}
{{- end }}
{{- if not .Values.networkPolicy.enabled }}
{{- fail "metricsListener needs networkPolicy.enabled, which limits the metrics port to metricsListener.fromNamespaces" }}
{{- end }}
{{- if not $m.fromNamespaces }}
{{- fail "metricsListener.fromNamespaces needs at least one namespace" }}
{{- end }}
{{- $taken := list (int .Values.port.containerPort) }}
{{- if and .Values.overlay.configMapName .Values.overlay.sidecar.enabled }}{{ $taken = append $taken 9091 }}{{ end }}
{{- if has (int $m.port) $taken }}
{{- fail (printf "metricsListener.port %d collides with another gateway pod port" (int $m.port)) }}
{{- end }}
{{- end }}
{{- if and $m.serviceMonitor.enabled (not $m.enabled) }}
{{- fail "metricsListener.serviceMonitor needs metricsListener.enabled" }}
{{- end }}
{{- if and $m.serviceMonitor.enabled (not $m.serviceMonitor.caConfigMap.name) }}
{{- fail "metricsListener.serviceMonitor.caConfigMap.name is required to verify the metrics cert" }}
{{- end }}
{{- end }}

{{/*
Name of the ConfigMap that holds praxis.yaml: praxisConfig.operator.configMapName or
praxisConfig.byo.configMapName, else
praxis-consumer-config for source operator (the Grid operator's default), else the
chart's own {fullname}-config for render and inline.
*/}}
{{- define "praxis-gateway.configMapName" -}}
{{- if eq .Values.praxisConfig.source "operator" -}}
{{- .Values.praxisConfig.operator.configMapName | default "praxis-consumer-config" -}}
{{- else if and (eq .Values.praxisConfig.source "byo") .Values.praxisConfig.byo.configMapName -}}
{{- .Values.praxisConfig.byo.configMapName -}}
{{- else -}}
{{- printf "%s-config" (include "praxis-gateway.fullname" .) -}}
{{- end -}}
{{- end }}

{{/* Full image references injected by downstream payloads; shared with sibling charts. */}}
{{- define "praxis-gateway.relatedImage" -}}
{{- range (.root.Values.global | default dict).relatedImages -}}
{{- if eq .name $.name -}}
{{- required (printf "%s requires a nonempty value" $.name) .value -}}
{{- end -}}
{{- end -}}
{{- end -}}
