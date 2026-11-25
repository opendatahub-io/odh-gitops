{{/* Same identity profile for explicit sites and inventory-discovered sites. */}}
{{- define "grid-enrollment.siteCertificate" -}}
{{- $root := .root -}}
{{- $cm := $root.Values.external.certManager -}}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ .secretName | quote }}
  namespace: {{ $root.Release.Namespace | quote }}
  labels:
    {{- include "grid-enrollment.labels" $root | nindent 4 }}
spec:
  secretName: {{ .secretName | quote }}
  commonName: {{ .name | quote }}
  subject:
    organizations: [{{ .name | quote }}]
  uris: [{{ printf "spiffe://grid.internal/site/%s" .name | quote }}]
  dnsNames:
    {{- $names := prepend (.dnsNames | default list) (printf "%s.grid.internal" .name) }}
    {{- if eq $root.Values.grid.membership.source "Local" }}
    {{- $names = append $names (printf "%s-signals.grid.internal" .name) }}
    {{- end }}
    {{- toYaml ($names | uniq) | nindent 4 }}
  duration: {{ printf "%dh" (int $cm.certificate.durationHours) | quote }}
  renewBefore: {{ printf "%dh" (int $cm.certificate.renewBeforeHours) | quote }}
  privateKey:
    algorithm: ECDSA
    size: 256
    encoding: PKCS8
    rotationPolicy: Always
  usages: [digital signature, client auth, server auth]
  issuerRef:
    name: {{ $cm.issuer.name | quote }}
    kind: {{ $cm.issuer.kind | quote }}
    group: {{ $cm.issuer.group | quote }}
{{- end }}
