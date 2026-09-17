{{/*
Render the platform GatewayConfig for the parent-chart bootstrap hook.

The xks-gateway subchart suppresses its normal GatewayConfig manifest when it is
used by this chart. Keeping the manifest here lets the hook install the CRD and
then create the custom resource in the same Helm operation.
*/}}
{{- define "rhai-on-xks-chart.gatewayConfigManifest" -}}
{{- $xksGateway := index .Subcharts "xks-gateway" -}}
{{- $gw := index .Values "xks-gateway" "gateway" -}}
apiVersion: services.platform.opendatahub.io/v1alpha1
kind: GatewayConfig
metadata:
  # Name is enforced by CRD CEL validation: must be "default-gateway"
  name: default-gateway
  labels:
    {{- include "xks-gateway.labels" $xksGateway | nindent 4 }}
spec:
  domain: {{ $gw.domain | quote }}
  {{- with $gw.subdomain }}
  subdomain: {{ . | quote }}
  {{- end }}
  ingressMode: {{ $gw.ingressMode | default "LoadBalancer" }}
  certificate:
    type: {{ $gw.certificate.type | default "SelfSigned" }}
    {{- with $gw.certificate.secretName }}
    secretName: {{ . | quote }}
    {{- end }}
  oidc:
    issuerURL: {{ $gw.oidc.issuerURL | quote }}
    clientID: {{ $gw.oidc.clientID | quote }}
    clientSecretRef:
      name: {{ include "xks-gateway.oidcClientSecretRefName" $xksGateway | quote }}
      key: {{ $gw.oidc.clientSecretRef.key | default "client-secret" | quote }}
    secretNamespace: {{ include "xks-gateway.oidcSecretNamespace" $xksGateway | quote }}
  {{- if or $gw.cookie.expire $gw.cookie.refresh }}
  cookie:
    {{- with $gw.cookie.expire }}
    expire: {{ . | quote }}
    {{- end }}
    {{- with $gw.cookie.refresh }}
    refresh: {{ . | quote }}
    {{- end }}
  {{- end }}
  {{- with $gw.providerCASecretName }}
  providerCASecretName: {{ . | quote }}
  {{- end }}
  {{- if not (kindIs "invalid" $gw.verifyProviderCertificate) }}
  verifyProviderCertificate: {{ $gw.verifyProviderCertificate }}
  {{- end }}
  {{- if and $gw.networkPolicy $gw.networkPolicy.ingress }}
  networkPolicy:
    ingress:
      enabled: {{ $gw.networkPolicy.ingress.enabled }}
  {{- end }}
{{- end -}}
