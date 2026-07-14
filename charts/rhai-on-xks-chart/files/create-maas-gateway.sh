{{- $appNs := .Values.rhaiOperator.applicationsNamespace -}}
{{- $tls := .Values.gateway.tls -}}
{{- $maasGwNs := .Values.components.maas.gateway.namespace -}}
{{- $certSecret := "maas-gateway-cert-secret" -}}
{{- $webhookCertSecret := "maas-controller-webhook-cert" -}}
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

webhook_cert_ready() {
  [ "$(kubectl get certificate {{ $webhookCertSecret }} -n "$APP_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]
}

maas_gw_cert_ready() {
  [ "$(kubectl get certificate maas-gateway-cert -n "$MAAS_GW_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]
}

echo "=== MaaS Gateway & Webhook Certificate Setup ==="

echo "Step 1: Create MaaS gateway namespace..."
kubectl create namespace "$MAAS_GW_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Step 2: Create CA bundle ConfigMaps..."
wait_for "cert-manager CA secret" kubectl get secret rhai-ca -n cert-manager
kubectl get secret rhai-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d > /tmp/ca.crt
if kubectl get secret opendatahub-ca -n cert-manager >/dev/null 2>&1; then
  kubectl get secret opendatahub-ca -n cert-manager -o jsonpath='{.data.ca\.crt}' | base64 -d >> /tmp/ca.crt
  echo "Included opendatahub-ca in CA bundle."
fi
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

echo "Step 5: Create MaaS controller webhook Certificate..."
kubectl apply -f - <<'EOF'
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $webhookCertSecret }}
  namespace: {{ $appNs | quote }}
spec:
  secretName: {{ $webhookCertSecret }}
  issuerRef:
    name: {{ $tls.issuerRef.name | quote }}
    kind: {{ $tls.issuerRef.kind | quote }}
    group: cert-manager.io
  dnsNames:
    - "maas-controller-webhook-service.{{ $appNs }}.svc"
    - "maas-controller-webhook-service.{{ $appNs }}.svc.cluster.local"
EOF
wait_for "MaaS webhook Certificate to be Ready" webhook_cert_ready

echo "Step 6: Create MaaS API serving Certificate..."
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

echo "Step 7: Create MaaS Gateway..."
kubectl apply -f - <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: maas-default-gateway
  namespace: {{ $maasGwNs | quote }}
spec:
  gatewayClassName: istio
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: All
{{- if $tls.enabled }}
    - name: https
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: All
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

echo "Step 8: Copy pull secret to MaaS gateway namespace..."
if kubectl get secret rhai-pull-secret -n "$APP_NAMESPACE" >/dev/null 2>&1; then
  DOCKER_CONFIG=$(kubectl get secret rhai-pull-secret -n "$APP_NAMESPACE" -o jsonpath='{.data.\.dockerconfigjson}')
  kubectl create secret docker-registry rhai-pull-secret \
    --from-literal=.dockerconfigjson="$(echo "$DOCKER_CONFIG" | base64 -d)" \
    -n "$MAAS_GW_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  echo "Pull secret copied."
else
  echo "No rhai-pull-secret found, skipping."
fi

echo "Step 9: Configure Authorino CA trust for MaaS API callbacks..."
KUADRANT_NS="kuadrant-system"
if kubectl get namespace "$KUADRANT_NS" >/dev/null 2>&1; then
  kubectl create configmap rhai-ca-bundle --from-file=ca.crt=/tmp/ca.crt \
    -n "$KUADRANT_NS" --dry-run=client -o yaml | kubectl apply -f -

  SYSTEM_CA=$(kubectl exec -n "$KUADRANT_NS" deploy/authorino -- cat /etc/pki/tls/certs/ca-bundle.crt 2>/dev/null || true)
  RHAI_CA=$(cat /tmp/ca.crt)
  if [ -n "$SYSTEM_CA" ]; then
    printf '%s\n%s' "$SYSTEM_CA" "$RHAI_CA" > /tmp/combined-ca.crt
    kubectl create configmap authorino-ca-bundle --from-file=ca-bundle.crt=/tmp/combined-ca.crt \
      -n "$KUADRANT_NS" --dry-run=client -o yaml | kubectl apply -f -

    kubectl patch authorino authorino -n "$KUADRANT_NS" --type='merge' -p='{"spec":{"volumes":{"items":[{"name":"combined-ca","mountPath":"/etc/pki/tls/custom","configMaps":["authorino-ca-bundle"],"items":[{"key":"ca-bundle.crt","path":"ca-bundle.crt"}]}]}}}'
    kubectl set env deployment/authorino -n "$KUADRANT_NS" SSL_CERT_FILE=/etc/pki/tls/custom/ca-bundle.crt
    echo "Authorino CA trust configured."
  else
    echo "WARNING: Could not read Authorino system CA, skipping combined CA bundle."
  fi
else
  echo "Kuadrant namespace not found, skipping Authorino CA trust."
fi

echo "=== MaaS Gateway setup complete ==="
