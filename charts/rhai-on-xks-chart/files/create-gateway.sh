{{- $appNs := .Values.rhaiOperator.applicationsNamespace -}}
{{- $tls := .Values.gateway.tls -}}
{{- $hostname := .Values.gateway.hostname -}}
{{- $internalIssuer := eq $tls.issuerRef.name "rhai-ca-issuer" -}}
{{- /* Internal secret name for the cert: created by Certificate, read by every gateway HTTPS listener. Not user-configurable. */ -}}
{{- $certSecret := "inference-gateway-cert-secret" -}}
set -euo pipefail
TIMEOUT=300
INTERVAL=5
ELAPSED=0

echo "Step 1: Waiting for Gateway API CRDs required by Gateway CR 'inference-gateway'..."
until kubectl get crd gateways.gateway.networking.k8s.io >/dev/null 2>&1; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out waiting for Gateway API CRDs after ${TIMEOUT}s"
    exit 1
  fi
  echo "CRD not yet available, retrying in ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo "Gateway API CRDs are available."

####
echo "Step 2: Waiting for cert-manager CA secret required by Gateway CR 'inference-gateway'..."
ELAPSED=0
until kubectl get secret rhai-ca -n cert-manager >/dev/null 2>&1; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out waiting for CA secret after ${TIMEOUT}s"
    exit 1
  fi
  echo "CA secret not yet available, retrying in ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo "CA secret is available."

####
echo "Step 3: Creating CA bundle ConfigMap for Gateway CR 'inference-gateway'..."
kubectl get secret rhai-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca.crt
kubectl create configmap rhai-ca-bundle --from-file=ca.crt=/tmp/ca.crt -n {{ $appNs }} --dry-run=client -o yaml | kubectl apply -f -
echo "CA bundle ConfigMap created."

####
echo "Step 4: Create ConfigMap used by Gateway CR 'inference-gateway'..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: inference-gateway-config
  namespace: {{ $appNs }}
data:
  deployment: |
    spec:
      template:
        spec:
          volumes:
          - name: rhai-ca-bundle
            configMap:
              name: rhai-ca-bundle
          containers:
          - name: istio-proxy
            volumeMounts:
            - name: rhai-ca-bundle
              mountPath: /var/run/secrets/rhai
              readOnly: true
{{- if .Values.azure.enabled }}
  service: |
    metadata:
      annotations:
        service.beta.kubernetes.io/port_80_health-probe_protocol: tcp
{{- end }}
EOF
echo "ConfigMap used by Gateway CR 'inference-gateway' created."


{{- if $tls.enabled }}
echo "Waiting for {{ $tls.issuerRef.kind }} '{{ $tls.issuerRef.name }}' to be Ready before creating the Certificate..."
ELAPSED=0
until [ "$(kubectl get {{ $tls.issuerRef.kind | lower }} {{ $tls.issuerRef.name }}{{ if eq $tls.issuerRef.kind "Issuer" }} -n {{ $appNs }}{{ end }} -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out waiting for {{ $tls.issuerRef.kind }} '{{ $tls.issuerRef.name }}' to be Ready after ${TIMEOUT}s"
    exit 1
  fi
  echo "{{ $tls.issuerRef.kind }} not yet Ready, retrying in ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo "{{ $tls.issuerRef.kind }} '{{ $tls.issuerRef.name }}' is Ready."
{{- end }}

{{- if $tls.enabled }}
{{- if and (not $internalIssuer) (not $hostname) (not $tls.additionalSANs) }}
{{- fail "gateway.tls.issuerRef is non-default (external) but neither gateway.hostname nor gateway.tls.additionalSANs is set; the certificate would have no dnsNames" }}
{{- end }}
####
echo "Step 5: Creating Certificate for Gateway TLS..."
{{- if and $hostname $internalIssuer }}
echo "WARNING: gateway.hostname is set but issuerRef '{{ $tls.issuerRef.name }}' is the internal CA; the certificate is only trusted inside the cluster. Set gateway.tls.issuerRef to a public/enterprise issuer for external clients."
{{- end }}
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: inference-gateway-cert
  namespace: {{ $appNs }}
spec:
  secretName: {{ $certSecret }}
  issuerRef:
    name: {{ $tls.issuerRef.name }}
    kind: {{ $tls.issuerRef.kind }}
    group: cert-manager.io
  dnsNames:
  {{- if $internalIssuer }}  
    - "*.{{ $appNs }}.svc.cluster.local"
    - "*.{{ $appNs }}.svc"
  {{- end }}
  {{- if $hostname }}
    - {{ $hostname | quote }}
    {{- if hasPrefix "*." $hostname }}
    - {{ $hostname | trimPrefix "*." | quote }}
    {{- end }}
  {{- end }}
  {{- range $tls.additionalSANs }}
    - {{ . | quote }}
  {{- end }}
EOF
echo "Certificate 'inference-gateway-cert' created."

echo "Waiting for {{ $certSecret }} Secret to be created by cert-manager..."
ELAPSED=0
until kubectl get secret {{ $certSecret }} -n {{ $appNs }} >/dev/null 2>&1; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out waiting for {{ $certSecret }} Secret after ${TIMEOUT}s"
    exit 1
  fi
  echo "Secret not yet available, retrying in ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo "{{ $certSecret }} Secret is available."
{{- end }}

####
echo "Step 6: Waiting for GatewayClass 'istio' required by Gateway CR 'inference-gateway'..."
ELAPSED=0
until kubectl get gatewayclass istio >/dev/null 2>&1; do
  if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
    echo "ERROR: Timed out waiting for GatewayClass 'istio' after ${TIMEOUT}s"
    exit 1
  fi
  echo "GatewayClass 'istio' not yet available, retrying in ${INTERVAL}s... (${ELAPSED}/${TIMEOUT}s)"
  sleep "$INTERVAL"
  ELAPSED=$((ELAPSED + INTERVAL))
done
echo "GatewayClass 'istio' is available."

####
echo "Step 7: Creating Gateway CR 'inference-gateway'..."
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: inference-gateway
  namespace: {{ $appNs }}
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
{{- if .Values.components.kserve.gateway.allowedRoutes.namespaces.from }}
{{- if and (eq .Values.components.kserve.gateway.allowedRoutes.namespaces.from "Selector") (not .Values.components.kserve.gateway.allowedRoutes.namespaces.selector) }}
{{- fail "allowedRoutes.namespaces.selector is required when from is set to Selector" }}
{{- end }}
      allowedRoutes:
        namespaces:
          from: {{ .Values.components.kserve.gateway.allowedRoutes.namespaces.from }}
{{- if and (eq .Values.components.kserve.gateway.allowedRoutes.namespaces.from "Selector") .Values.components.kserve.gateway.allowedRoutes.namespaces.selector }}
          selector:
            {{- toYaml .Values.components.kserve.gateway.allowedRoutes.namespaces.selector | nindent 12 }}
{{- end }}
{{- end }}
{{- if $tls.enabled }}
    - name: https
      port: 443
      protocol: HTTPS
{{- if .Values.components.kserve.gateway.allowedRoutes.namespaces.from }}
{{- if and (eq .Values.components.kserve.gateway.allowedRoutes.namespaces.from "Selector") (not .Values.components.kserve.gateway.allowedRoutes.namespaces.selector) }}
{{- fail "allowedRoutes.namespaces.selector is required when from is set to Selector" }}
{{- end }}
      allowedRoutes:
        namespaces:
          from: {{ .Values.components.kserve.gateway.allowedRoutes.namespaces.from }}
{{- if and (eq .Values.components.kserve.gateway.allowedRoutes.namespaces.from "Selector") .Values.components.kserve.gateway.allowedRoutes.namespaces.selector }}
          selector:
            {{- toYaml .Values.components.kserve.gateway.allowedRoutes.namespaces.selector | nindent 12 }}
{{- end }}
{{- end }}
      tls:
        certificateRefs:
          - group: ''
            kind: Secret
            name: {{ $certSecret }}
        mode: Terminate
{{- end }}
  infrastructure:
    labels:
      serving.kserve.io/gateway: kserve-ingress-gateway
    parametersRef:
      group: ""
      kind: ConfigMap
      name: inference-gateway-config
EOF
echo "Gateway CR 'inference-gateway' created successfully."
