{{- $appNs := .Values.rhaiOperator.applicationsNamespace -}}
{{- $tls := .Values.gateway.tls -}}
{{- $maasGwNs := "openshift-ingress" -}}
{{- $maasGwName := .Values.components.aigateway.modelsAsAService.gateway.name -}}
{{- $maasGwClass := .Values.components.aigateway.modelsAsAService.gateway.gatewayClassName -}}
{{- $certSecret := "maas-gateway-cert-secret" -}}
set -euo pipefail
TIMEOUT=300
INTERVAL=5

APP_NAMESPACE={{ $appNs | quote }}
MAAS_GW_NAMESPACE={{ $maasGwNs | quote }}

wait_for() {
  local desc="$1"; shift
  local elapsed=0
  echo "Waiting for ${desc}..."
  until "$@" >/dev/null 2>&1; do
    if [ "$elapsed" -ge "$TIMEOUT" ]; then
      echo "ERROR: Timed out waiting for ${desc} after ${TIMEOUT}s"
      exit 1
    fi
    echo "${desc} not yet available, retrying in ${INTERVAL}s... (${elapsed}/${TIMEOUT}s)"
    sleep "$INTERVAL"
    elapsed=$((elapsed + INTERVAL))
  done
  echo "${desc} is available."
}

maas_gw_cert_ready() {
  [ "$(kubectl get certificate maas-gateway-cert -n "$MAAS_GW_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]
}

echo "=== MaaS Gateway Setup ==="

echo "Step 1: Create MaaS gateway namespace..."
kubectl create namespace "$MAAS_GW_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Step 2: Create CA bundle ConfigMaps..."
wait_for "cert-manager CA secret" kubectl get secret rhai-ca -n cert-manager
kubectl get secret rhai-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca.crt
kubectl create configmap rhai-ca-bundle --from-file=ca.crt=/tmp/ca.crt -n "$APP_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create configmap rhai-ca-bundle --from-file=ca.crt=/tmp/ca.crt -n "$MAAS_GW_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
echo "CA bundle ConfigMaps created."

echo "Step 3: Create MaaS gateway config ConfigMap..."
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: maas-gateway-config
  namespace: {{ $maasGwNs | quote }}
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
              mountPath: /var/run/secrets/opendatahub
              readOnly: true
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
echo "MaaS gateway ConfigMap created."

{{- if $tls.enabled }}
echo "Step 4: Create MaaS gateway TLS Certificate..."
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: maas-gateway-cert
  namespace: {{ $maasGwNs | quote }}
spec:
  secretName: {{ $certSecret | quote }}
  issuerRef:
    name: {{ $tls.issuerRef.name | quote }}
    kind: {{ $tls.issuerRef.kind | quote }}
    group: cert-manager.io
  dnsNames:
    - "*.{{ $maasGwNs }}.svc.cluster.local"
    - "*.{{ $maasGwNs }}.svc"
EOF
wait_for "MaaS gateway Certificate to be Ready" maas_gw_cert_ready
{{- end }}

echo "Step 5: Create MaaS API serving Certificate..."
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: maas-api-serving-cert
  namespace: {{ $appNs | quote }}
spec:
  secretName: maas-api-serving-cert
  issuerRef:
    name: {{ $tls.issuerRef.name | quote }}
    kind: {{ $tls.issuerRef.kind | quote }}
    group: cert-manager.io
  dnsNames:
    - "maas-api.{{ $appNs }}.svc"
    - "maas-api.{{ $appNs }}.svc.cluster.local"
EOF

echo "Step 6: Create MaaS Gateway..."
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: {{ $maasGwName | quote }}
  namespace: {{ $maasGwNs | quote }}
spec:
  gatewayClassName: {{ $maasGwClass | quote }}
  listeners:
    - name: http
      port: 80
      protocol: HTTP
{{- if .Values.components.aigateway.modelsAsAService.gateway.allowedRoutes.namespaces.from }}
{{- include "rhai-on-xks-chart.gatewayAllowedRoutes" (dict "allowedRoutes" .Values.components.aigateway.modelsAsAService.gateway.allowedRoutes) | nindent 6 }}
{{- end }}
{{- if $tls.enabled }}
    - name: https
      port: 443
      protocol: HTTPS
{{- if .Values.components.aigateway.modelsAsAService.gateway.allowedRoutes.namespaces.from }}
{{- include "rhai-on-xks-chart.gatewayAllowedRoutes" (dict "allowedRoutes" .Values.components.aigateway.modelsAsAService.gateway.allowedRoutes) | nindent 6 }}
{{- end }}
      tls:
        certificateRefs:
          - group: ''
            kind: Secret
            name: {{ $certSecret | quote }}
        mode: Terminate
{{- end }}
  infrastructure:
    parametersRef:
      group: ""
      kind: ConfigMap
      name: maas-gateway-config
EOF
echo "MaaS Gateway created successfully."

echo "Step 7: Copy pull secret to MaaS gateway namespace..."
if kubectl get secret rhai-pull-secret -n "$APP_NAMESPACE" >/dev/null 2>&1; then
  DOCKER_CONFIG=$(kubectl get secret rhai-pull-secret -n "$APP_NAMESPACE" -o jsonpath='{.data.\.dockerconfigjson}')
  kubectl create secret docker-registry rhai-pull-secret \
    --from-literal=.dockerconfigjson="$(echo "$DOCKER_CONFIG" | base64 -d)" \
    -n "$MAAS_GW_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo "Pull secret copied."
else
  echo "No rhai-pull-secret found, skipping."
fi

echo "Step 8: Configure Authorino CA trust for MaaS API callbacks..."
KUADRANT_NS="kuadrant-system"
if kubectl get namespace "$KUADRANT_NS" >/dev/null 2>&1; then
  kubectl create configmap rhai-ca-bundle --from-file=ca.crt=/tmp/ca.crt \
    -n "$KUADRANT_NS" --dry-run=client -o yaml | kubectl apply -f -

  kubectl patch deployment authorino -n "$KUADRANT_NS" --type=json -p='[
    {"op":"add","path":"/spec/template/spec/volumes/-","value":{"name":"rhai-ca","configMap":{"name":"rhai-ca-bundle"}}},
    {"op":"add","path":"/spec/template/spec/containers/0/volumeMounts/-","value":{"name":"rhai-ca","mountPath":"/etc/pki/tls/custom","readOnly":true}},
    {"op":"add","path":"/spec/template/spec/containers/0/env/-","value":{"name":"SSL_CERT_FILE","value":"/etc/pki/tls/custom/ca.crt"}}
  ]'
  echo "Authorino CA trust configured."
else
  echo "Kuadrant namespace not found, skipping Authorino CA trust."
fi

echo "=== MaaS Gateway setup complete ==="
