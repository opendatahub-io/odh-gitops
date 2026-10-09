{{/*
Registry of cloud providers and their KubernetesEngine CR metadata.
Returns a YAML map keyed by provider name.
To add a new provider: add an entry here. All templates update automatically.
*/}}
{{- define "rhai-on-xks-chart.providerRegistry" -}}
aws:
  keKind: AWSKubernetesEngine
  keResource: awskubernetesengines
  keResourceSingular: awskubernetesengine
  keName: default-awskubernetesengine
azure:
  keKind: AzureKubernetesEngine
  keResource: azurekubernetesengines
  keResourceSingular: azurekubernetesengine
  keName: default-azurekubernetesengine
coreweave:
  keKind: CoreWeaveKubernetesEngine
  keResource: coreweavekubernetesengines
  keResourceSingular: coreweavekubernetesengine
  keName: default-coreweavekubernetesengine
{{- end -}}

{{/*
Registry of component CRs (components.platform.opendatahub.io API group).
Returns a YAML map keyed by component name.
To add a new component CR: add an entry here. All templates update automatically.
*/}}
{{- define "rhai-on-xks-chart.componentCRRegistry" -}}
aigateway:
  kind: AIGateway
  resource: aigateways
  resourceSingular: aigateway
  crName: default-aigateway
  apiGroup: components.platform.opendatahub.io
kserve:
  kind: Kserve
  resource: kserves
  resourceSingular: kserve
  crName: default-kserve
  apiGroup: components.platform.opendatahub.io
{{- end -}}

{{/*
Registry of module CRs managed via the Platform CR (config.opendatahub.io/v1alpha1).
AIGateway is a module, not a component — it is enabled by setting
spec.modules.<platformModuleKey>.managementState: Managed on the Platform CR.
To add a new module: add an entry here. All templates update automatically.
*/}}
{{- define "rhai-on-xks-chart.moduleCRRegistry" -}}
aigateway:
  platformModuleKey: aigateway
kserve:
  platformModuleKey: kserve
{{- end -}}

{{/*
Returns a JSON list of enabled module names for guard conditions.
*/}}
{{- define "rhai-on-xks-chart.enabledModuleCRs" -}}
{{- $registry := include "rhai-on-xks-chart.moduleCRRegistry" . | fromYaml }}
{{- $result := list }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $modVals := index $.Values.components $name | default dict }}
  {{- if $modVals.enabled }}
    {{- $result = append $result $name }}
  {{- end }}
{{- end }}
{{- $result | toJson }}
{{- end -}}

{{/*
Emit a single kubectl apply for the Platform CR.
The CR is always created so it is present in the cluster for the operator to
reconcile. Registered modules get managementState: Managed when enabled and
Removed when disabled, so Helm upgrades also clean up disabled modules.
Include with: {{- include "rhai-on-xks-chart.moduleApplyCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.moduleApplyCommands" -}}
{{- $root := . }}
{{- $registry := include "rhai-on-xks-chart.moduleCRRegistry" . | fromYaml }}
{{- $modulesSpec := dict }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $meta := index $registry $name }}
  {{- $modVals := index $.Values.components $name | default dict }}
  {{- $key := index $meta "platformModuleKey" }}
  {{- $state := ternary "Managed" "Removed" ($modVals.enabled | default false) }}
  {{- $modulesSpec = merge $modulesSpec (dict $key (dict "managementState" $state)) }}
{{- end }}
echo "Waiting for CRD platforms.config.opendatahub.io to be established..."
kubectl wait --for condition=established --timeout=300s crd/platforms.config.opendatahub.io
echo "Creating Platform CR..."
apply_deadline=$((SECONDS + 300))
last_error=""
while true; do
  remaining=$((apply_deadline - SECONDS))
  if (( remaining <= 0 )); then
    echo "Timed out applying Platform CR. Last error: $last_error" >&2
    exit 1
  fi
  attempt_timeout=$((remaining < 15 ? remaining : 15))
  # kubectl --request-timeout bypasses in-cluster configuration; bound the process instead.
  if apply_output=$(timeout --kill-after=5s "${attempt_timeout}s" kubectl apply -f - 2>&1 <<'EOF'
apiVersion: config.opendatahub.io/v1alpha2
kind: Platform
metadata:
  name: default
  labels:
    {{- include "rhai-on-xks-chart.labels" $root | nindent 4 }}
{{- if $modulesSpec }}
spec:
  modules:
    {{- $modulesSpec | toYaml | nindent 4 }}
{{- else }}
spec: {}
{{- end }}
EOF
  ); then
    echo "$apply_output"
    break
  else
    apply_output="${apply_output:-kubectl apply failed with exit code $?}"
  fi
  case "$apply_output" in
    *'Error from server (Forbidden)'*|*'Error from server (Invalid)'*|*' is forbidden:'*|*' is invalid:'*|*'The request is invalid'*|\
    *'ValidationError('*)
      echo "Platform apply failed permanently: $apply_output" >&2
      exit 1
      ;;
  esac
  if [[ -z "$last_error" ]]; then
    echo "Platform apply failed; retrying every 5 seconds: $apply_output" >&2
  fi
  last_error="$apply_output"
  sleep 5
done
{{- end -}}

{{/*
Emit kubectl delete for the Platform CR. Always runs on uninstall since the
Platform CR is always created (even with an empty modules spec).
Include with: {{- include "rhai-on-xks-chart.moduleDeleteCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.moduleDeleteCommands" -}}
echo "Deleting Platform CR 'default'..."
kubectl delete platform default --ignore-not-found --timeout=300s
{{- end -}}

{{/*
Return a YAML dict for the active cloud provider (the one with .enabled=true).
Returns empty string (→ empty map after fromYaml) if none enabled.
Exactly one expected (enforced by rhai-on-xks-chart.validateCloudProvider).

Fields: name, keKind, keResource, keResourceSingular, keName,
        keEnabled (bool), keSpec (kubernetesEngine.spec), cloudManagerNamespace.
*/}}
{{- define "rhai-on-xks-chart.activeProvider" -}}
{{- $registry := include "rhai-on-xks-chart.providerRegistry" . | fromYaml }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $meta := index $registry $name }}
  {{- $vals := index $.Values $name | default dict }}
  {{- if $vals.enabled -}}
    {{- dict
      "name" $name
      "keKind" (index $meta "keKind")
      "keResource" (index $meta "keResource")
      "keResourceSingular" (index $meta "keResourceSingular")
      "keName" (index $meta "keName")
      "keEnabled" (dig "kubernetesEngine" "enabled" false $vals)
      "keSpec" (dig "kubernetesEngine" "spec" nil $vals)
      "cloudManagerNamespace" (dig "cloudManager" "namespace" "" $vals)
    | toYaml }}
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Returns "true" if provider + KE are both enabled, empty string otherwise. Used for guard conditions only.
*/}}
{{- define "rhai-on-xks-chart.enabledProviderKECR" -}}
{{- $provider := include "rhai-on-xks-chart.activeProvider" . | fromYaml }}
{{- if and $provider (index $provider "keEnabled") -}}true{{- end }}
{{- end -}}

{{/*
Returns a JSON list of enabled component names for guard conditions (non-empty = at least one enabled).
Do NOT range over this and access fields with .field syntax — use crApplyCommands / componentDeleteCommands instead.
*/}}
{{- define "rhai-on-xks-chart.enabledComponentCRs" -}}
{{- $registry := include "rhai-on-xks-chart.componentCRRegistry" . | fromYaml }}
{{- $result := list }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $compVals := index $.Values.components $name | default dict }}
  {{- if $compVals.enabled }}
    {{- $result = append $result $name }}
  {{- end }}
{{- end }}
{{- $result | toJson }}
{{- end -}}

{{/*
Emit kubectl apply commands for provider KE CR, Platform CR, then component CRs.
Provider KE CR is applied first to trigger dependency deployment (cert-manager, istio, etc.).
Platform CR is applied next to trigger module operators (e.g. ai-gateway-operator).
Component CRs are applied last, after their CRDs are registered by the operators.
Disabled component CRs are deleted by the pre-upgrade hook before Helm removes their credentials.
Include with: {{- include "rhai-on-xks-chart.crApplyCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.crApplyCommands" -}}
{{- $root := . }}
{{- $provider := include "rhai-on-xks-chart.activeProvider" . | fromYaml }}
{{- if and $provider (index $provider "keEnabled") }}
echo "Creating {{ index $provider "keKind" }} CR..."
kubectl apply -f - <<'EOF'
apiVersion: infrastructure.opendatahub.io/v1alpha1
kind: {{ index $provider "keKind" }}
metadata:
  name: {{ index $provider "keName" }}
  labels:
    {{- include "rhai-on-xks-chart.labels" $root | nindent 4 }}
{{- $spec := index $provider "keSpec" }}
{{- if $spec }}
spec:
  {{- $spec | toYaml | nindent 2 }}
{{- else }}
spec: {}
{{- end }}
EOF
{{- end }}
{{- include "rhai-on-xks-chart.moduleApplyCommands" $root }}
{{- $compRegistry := include "rhai-on-xks-chart.componentCRRegistry" . | fromYaml }}
{{- range $name := keys $compRegistry | sortAlpha }}
  {{- $meta := index $compRegistry $name }}
  {{- $compVals := index $.Values.components $name | default dict }}
  {{- if $compVals.enabled }}
echo "Waiting for CRD {{ index $meta "resource" }}.{{ index $meta "apiGroup" }} to exist..."
elapsed=0; while [ $elapsed -lt 300 ]; do
  kubectl get crd/{{ index $meta "resource" }}.{{ index $meta "apiGroup" }} &>/dev/null && break
  sleep 5; elapsed=$((elapsed + 5))
done
echo "Waiting for CRD {{ index $meta "resource" }}.{{ index $meta "apiGroup" }} to be established..."
kubectl wait --for condition=established --timeout=300s crd/{{ index $meta "resource" }}.{{ index $meta "apiGroup" }}
echo "Creating {{ index $meta "kind" }} CR..."
kubectl apply -f - <<'EOF'
apiVersion: {{ index $meta "apiGroup" }}/v1alpha1
kind: {{ index $meta "kind" }}
metadata:
  name: {{ index $meta "crName" }}
  labels:
    {{- include "rhai-on-xks-chart.labels" $root | nindent 4 }}
{{- if $compVals.spec }}
spec:
  {{- $compVals.spec | toYaml | nindent 2 }}
{{- else }}
spec: {}
{{- end }}
EOF
  {{- end }}
{{- end }}
{{- end -}}

{{/* Delete disabled component CRs while their controllers still have credentials. */}}
{{- define "rhai-on-xks-chart.disabledComponentDeleteCommands" -}}
{{- $root := . }}
{{- $registry := include "rhai-on-xks-chart.componentCRRegistry" . | fromYaml }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $meta := index $registry $name }}
  {{- $compVals := index $.Values.components $name | default dict }}
  {{- if not $compVals.enabled }}
crd_name=$(kubectl get crd/{{ index $meta "resource" }}.{{ index $meta "apiGroup" }} --ignore-not-found -o name)
if [[ -n "$crd_name" ]]; then
  cr_labels=$(kubectl get {{ index $meta "resource" }}/{{ index $meta "crName" }} --ignore-not-found \
    -o jsonpath='{.metadata.labels.app\.kubernetes\.io/managed-by}{"|"}{.metadata.labels.helm\.sh/chart}')
  # Match the chart name across versions so upgrades can clean up older CRs.
  if [[ "$cr_labels" == {{ printf "%s|%s-" $root.Release.Service $root.Chart.Name | quote }}* ]]; then
    echo "Deleting disabled {{ index $meta "kind" }} CR..."
    kubectl delete {{ index $meta "resource" }}/{{ index $meta "crName" }} --ignore-not-found --timeout=300s
  elif [[ -n "$cr_labels" ]]; then
    echo "Skipping disabled {{ index $meta "kind" }} CR: not managed by this chart."
  fi
fi
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Emit kubectl delete commands for all enabled component CRs.
Include with: {{- include "rhai-on-xks-chart.componentDeleteCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.componentDeleteCommands" -}}
{{- $compRegistry := include "rhai-on-xks-chart.componentCRRegistry" . | fromYaml }}
{{- range $name := keys $compRegistry | sortAlpha }}
  {{- $meta := index $compRegistry $name }}
  {{- $compVals := index $.Values.components $name | default dict }}
  {{- if $compVals.enabled }}
echo "Deleting {{ index $meta "kind" }} CR '{{ index $meta "crName" }}'..."
kubectl delete {{ index $meta "resourceSingular" }} {{ index $meta "crName" }} --ignore-not-found --timeout=300s
  {{- end }}
{{- end }}
{{- end -}}

{{/*
Emit kubectl delete command for the provider KE CR.
Include with: {{- include "rhai-on-xks-chart.providerKEDeleteCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.providerKEDeleteCommands" -}}
{{- $provider := include "rhai-on-xks-chart.activeProvider" . | fromYaml }}
{{- if and $provider (index $provider "keEnabled") }}
echo "Deleting {{ index $provider "keKind" }} CR '{{ index $provider "keName" }}'..."
kubectl delete {{ index $provider "keResourceSingular" }} {{ index $provider "keName" }} --ignore-not-found --timeout=300s
{{- end }}
{{- end -}}
