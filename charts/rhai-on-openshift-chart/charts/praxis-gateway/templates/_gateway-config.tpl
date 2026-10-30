{{/*
The data of the chart-rendered gateway ConfigMap, also hashed into checksum/config.
*/}}
{{- define "praxis-gateway.gatewayConfigData" }}
{{- $cfg := .Values.praxisConfig.render }}
{{- $provider := eq ($cfg.role | default "consumer") "provider" }}
{{- $providerFile := and $provider ($cfg.gridServing).enabled }}
{{- $apiKey := and (not $provider) (eq ($cfg.auth.mode | default "none") "api-key") }}
{{- $telemetry := $cfg.telemetry | default dict }}
{{- $hasSamplingRate := and (hasKey $telemetry "samplingRate") (ne $telemetry.samplingRate nil) }}
{{- $hasBatchInterval := and (hasKey $telemetry "batchIntervalSecs") (ne $telemetry.batchIntervalSecs nil) }}
{{- $hasBatchSize := and (hasKey $telemetry "batchSize") (ne $telemetry.batchSize nil) }}
{{- $hasTelemetryValues := or $telemetry.otlpEndpoint $hasSamplingRate $telemetry.serviceName $telemetry.serviceVersion $telemetry.environment $hasBatchInterval $hasBatchSize }}
  praxis.yaml: |
    {{- with $.Values.upstreamCA.secretName }}
    runtime:
      upstream_ca_file: {{ printf "%s/%s" $.Values.upstreamCA.mountPath ($.Values.upstreamCA.key | default "ca.crt") | quote }}
    {{- end }}
    {{- if $telemetry.enabled }}
    telemetry:
      {{- if not $hasTelemetryValues }}
      {}
      {{- else }}
      {{- with $telemetry.otlpEndpoint }}
      otlp_endpoint: {{ . | quote }}
      {{- end }}
      {{- if $hasSamplingRate }}
      sampling_rate: {{ $telemetry.samplingRate }}
      {{- end }}
      {{- with $telemetry.serviceName }}
      service_name: {{ . | quote }}
      {{- end }}
      {{- with $telemetry.serviceVersion }}
      service_version: {{ . | quote }}
      {{- end }}
      {{- with $telemetry.environment }}
      environment: {{ . | quote }}
      {{- end }}
      {{- if $hasBatchInterval }}
      batch_interval_secs: {{ $telemetry.batchIntervalSecs }}
      {{- end }}
      {{- if $hasBatchSize }}
      batch_size: {{ $telemetry.batchSize }}
      {{- end }}
      {{- end }}
    {{- end }}
    admin:
      metrics_address: {{ include "praxis-gateway.renderedAdminAddress" . | quote }}
    listeners:
      - name: gateway
        address: "0.0.0.0:{{ .Values.port.containerPort }}"
        {{- if $provider }}
        tls:
          certificates:
            - cert_path: {{ printf "%s/tls.crt" .Values.gridIdentity.mountPath | quote }}
              key_path: {{ printf "%s/tls.key" .Values.gridIdentity.mountPath | quote }}
          client_ca:
            ca_path: {{ printf "%s/ca.crt" .Values.gridIdentity.mountPath | quote }}
          {{- if eq (($cfg.peerTrust).mode | default "pin") "spiffe" }}
          client_cert_mode: require_named
          {{- with ($cfg.peerTrust).spiffeIds }}
          trusted_spiffe_ids:
            {{- range . }}
            - {{ . | quote }}
            {{- end }}
          {{- end }}
          {{- else }}
          client_cert_mode: require
          {{- end }}
        {{- else if $.Values.listenerTls.secretName }}
        tls:
          certificates:
            - cert_path: {{ printf "%s/tls.crt" $.Values.listenerTls.mountPath | quote }}
              key_path: {{ printf "%s/tls.key" $.Values.listenerTls.mountPath | quote }}
        {{- end }}
        filter_chains: [main]
    {{- if $cfg.backends }}
    # Praxis runs health checks only for top-level clusters; load_balancer repeats them inline.
    clusters:
      {{- range $i, $backend := $cfg.backends }}
      {{- include "praxis-gateway.backendCluster" (dict "root" $ "i" $i "b" $backend) | trim | nindent 6 }}
      {{- end }}
    {{- end }}
    filter_chains:
      - name: main
        filters:
          {{- if $telemetry.enabled }}
          - filter: trace_context
          {{- end }}
          {{- if $providerFile }}
          {{- /* First, and the only filter that picks an upstream: the gateway refuses to start otherwise. */}}
          - filter: grid_provider
            allowed_paths:
              {{- range (($cfg.provider).allowedPaths | default (list "/v1/chat/completions" "/v1/completions" "/v1/models" "/v1/embeddings")) }}
              - {{ . | quote }}
              {{- end }}
          {{- with ($cfg.peerTrust).rateLimit }}
          - filter: rate_limit
            mode: global
            rate: {{ .rate }}
            burst: {{ .burst }}
          {{- end }}
          - filter: headers
            response_set:
              - name: X-Grid-Provider-Site
                value: {{ $.Values.grid.siteName | quote }}
          {{- else if $provider }}
          {{- if ne (($cfg.peerTrust).mode | default "pin") "spiffe" }}
          - filter: peer_identity_trust
            trusted_peers:
              {{- range ($cfg.peerTrust).certDigests }}
              - cert_digest: {{ . | quote }}
              {{- end }}
          {{- else if ($cfg.peerTrust).spiffeIds }}
          # Unconditional, and first: the handshake admits the listener's whole allowlist,
          # so this is the floor every narrower check sits on top of. A later per-candidate
          # block can only take sites away from what this already admits.
          - filter: peer_identity_trust
            trusted_peers:
              {{- range (splitList "\n" (include "praxis-gateway.peerSites" ($cfg.peerTrust).spiffeIds)) }}
              - organization: {{ . | quote }}
              {{- end }}
          {{- end }}
          {{- with ($cfg.peerTrust).rateLimit }}
          - filter: rate_limit
            mode: global
            rate: {{ .rate }}
            burst: {{ .burst }}
          {{- end }}
          - filter: static_response
            status: 405
            conditions:
              - unless:
                  methods: [GET, POST]
          # Exact paths: a traversal or a longer path never matches, so it gets a 404.
          - filter: router
            routes:
              {{- range (($cfg.provider).allowedPaths | default (list "/v1/chat/completions" "/v1/completions" "/v1/models" "/v1/embeddings")) }}
              - path: {{ . | quote }}
                cluster: {{ (first $cfg.backends).cluster | quote }}
              {{- end }}
          - filter: headers
            response_set:
              - name: X-Grid-Provider-Site
                value: {{ $.Values.grid.siteName | quote }}
          {{- else }}
          {{- if $apiKey }}
          - filter: policy
            config_path: /etc/praxis/policy.yaml
            require_protocol_metadata: false
            {{- if $cfg.auth.allowPrivateEndpoint }}
            allow_private_idp: true
            {{- end }}
          {{- end }}
          {{- if $cfg.auth.stripAuthorization }}
          # The caller's credential authenticates this hop only; never forward it upstream.
          - filter: headers
            request_remove: [Authorization]
          {{- end }}
          - filter: model_to_header
            header: X-Gateway-Model-Name
          {{- if ($.Values.praxisConfig.render.gridServing).enabled }}
          - filter: grid_site_route
            model_header: X-Gateway-Model-Name
            clusters:
              {{- if $cfg.backends }}
              {{- range $cfg.backends }}
              - {{ .cluster | quote }}
              {{- end }}
              {{- else }} []
              {{- end }}
            {{- with ($.Values.praxisConfig.render.gridServing).siteRoute }}
            {{- with .availability }}
            availability:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            {{- with .prefixAffinity }}
            prefix_affinity:
              {{- toYaml . | nindent 14 }}
            {{- end }}
            {{- end }}
          {{- else }}
          - filter: intelligent_route
            model_header: X-Gateway-Model-Name
            local_site: {{ $.Values.grid.siteName | quote }}
            candidates:
              {{- range $cfg.backends }}
              - { kind: inference_model, name: {{ $cfg.model | quote }}, site: {{ .site | default $.Values.grid.siteName | quote }}, cluster: {{ .cluster | quote }} }
              {{- end }}
          {{- end }}
          {{- end }}
          {{- if $cfg.backends }}
          - filter: load_balancer
            clusters:
              {{- range $i, $backend := $cfg.backends }}
              {{- include "praxis-gateway.backendCluster" (dict "root" $ "i" $i "b" $backend) | trim | nindent 14 }}
              {{- end }}
          {{- end }}
  {{- if $apiKey }}
  policy.yaml: |
    engine_settings:
      dispatch: policy
    plugins:
      - name: api-key
        kind: identity/api-key
        hooks: [identity.resolve]
        on_error: fail
        capabilities: [perform_http]
        config:
          credential:
            kind: header
            name: Authorization
          prefix: {{ $cfg.auth.prefix | default "Bearer " | quote }}
          provider:
            kind: http
            url: {{ $cfg.auth.validateUrl | quote }}
            key_field: key
            valid_field: valid
            timeout_secs: {{ $cfg.auth.timeoutSecs | default 5 }}
          record_map:
            subject:
              id: username
              roles: groups
          claims:
            include: [subscription, tenant, region, tokenBudget]
    global:
      authentication: [api-key]
      authorization:
        pre_invocation: ["require(authenticated)"]
      response:
        status: 401
        body: "{\"error\":\"authentication required\"}"
  {{- end }}
{{- end }}

{{/*
One backend cluster. Rendered top-level, where Praxis runs its health checks, and inline in
load_balancer, which selects by the same name and endpoint order.
*/}}
{{- define "praxis-gateway.backendCluster" }}
{{- $root := .root }}
{{- $i := .i }}
{{- $b := .b }}
{{- $mode := ($b.transport).mode | default (ternary "mutual_tls" "plaintext" (not (empty $root.Values.gridIdentity.tlsSecretName))) }}
{{- $hc := $b.healthCheck | default dict }}
{{- /* A mutual_tls backend is another site's gateway: bounded connects and a faster probe, since little traffic reaches it to trip the passive check. */}}
{{- $peer := eq $mode "mutual_tls" }}
{{- /* An omitted value is derived from the one set beside it, so a default never renders a pair Praxis refuses. */}}
{{- $connect := $b.connectTimeoutMs | default (ternary 2000 0 $peer) | int }}
{{- $total := $b.totalConnectTimeoutMs | default (ternary (max 4000 $connect) 0 $peer) | int }}
{{- $probeTimeout := $hc.timeoutMs | default 2000 | int }}
{{- $probeInterval := $hc.intervalMs | default (max (ternary 3000 5000 $peer) (add $probeTimeout 1000)) | int }}
{{- if ge $probeTimeout $probeInterval }}
{{- fail (printf "praxisConfig.render.backends: %s healthCheck.timeoutMs (%d) must be less than intervalMs (%d)" $b.cluster $probeTimeout $probeInterval) }}
{{- end }}
- name: {{ $b.cluster | quote }}
  {{- if eq $mode "mutual_tls" }}
  tls:
    ca:
      ca_path: {{ printf "%s/ca.crt" $root.Values.gridIdentity.mountPath | quote }}
    client_cert:
      cert_path: {{ printf "%s/tls.crt" $root.Values.gridIdentity.mountPath | quote }}
      key_path: {{ printf "%s/tls.key" $root.Values.gridIdentity.mountPath | quote }}
    sni: {{ include "praxis-gateway.backendSni" $b | quote }}
    verify: true
  {{- else if eq $mode "tls" }}
  tls:
    {{- with ($b.transport).ca }}
    ca:
      ca_path: {{ printf "/etc/praxis/backend-ca/%d/%s" $i (.key | default "ca.crt") | quote }}
    {{- end }}
    sni: {{ include "praxis-gateway.backendSni" $b | quote }}
    verify: true
  {{- end }}
  endpoints:
    {{- range $b.endpoints }}
    - {{ . | quote }}
    {{- end }}
  {{- if $b.trustPrivate }}
  trusted_private_endpoints:
    {{- range $b.endpoints }}
    {{- $host := include "praxis-gateway.endpointHost" . }}
    {{- if not (include "praxis-gateway.isIPHost" $host) }}
    - {{ $host | quote }}
    {{- end }}
    {{- end }}
  {{- end }}
  {{- with $connect }}
  connection_timeout_ms: {{ . }}
  {{- end }}
  {{- with $total }}
  total_connection_timeout_ms: {{ . }}
  {{- end }}
  health_check:
    {{- /* TLS backends default to a tcp probe. The active http probe is plaintext and cannot reach a TLS peer. A tcp connect works and still satisfies the present-health_check SSRF-skip guard. */}}
    {{- $hcType := $hc.type | default (ternary "http" "tcp" (eq $mode "plaintext")) }}
    type: {{ $hcType | quote }}
    {{- if eq $hcType "http" }}
    path: {{ $hc.path | default "/health" | quote }}
    {{- end }}
    interval_ms: {{ $probeInterval }}
    timeout_ms: {{ $probeTimeout }}
    healthy_threshold: {{ $hc.healthyThreshold | default 2 }}
    unhealthy_threshold: {{ $hc.unhealthyThreshold | default 3 }}
    {{- /* Passive checks mark an endpoint that refuses or fails requests down within a few of them. */}}
    passive_unhealthy_threshold: {{ $hc.passiveUnhealthyThreshold | default 2 }}
    passive_healthy_threshold: {{ $hc.passiveHealthyThreshold | default 2 }}
{{- end }}
