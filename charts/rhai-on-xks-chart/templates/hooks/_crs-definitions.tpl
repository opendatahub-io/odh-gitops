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
Emit a single kubectl apply for the Platform CR that includes all enabled modules.
Include with: {{- include "rhai-on-xks-chart.moduleApplyCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.moduleApplyCommands" -}}
{{- $root := . }}
{{- $registry := include "rhai-on-xks-chart.moduleCRRegistry" . | fromYaml }}
{{- $modulesSpec := dict }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $meta := index $registry $name }}
  {{- $modVals := index $.Values.components $name | default dict }}
  {{- if $modVals.enabled }}
    {{- $key := index $meta "platformModuleKey" }}
    {{- $modulesSpec = merge $modulesSpec (dict $key (dict "managementState" "Managed")) }}
  {{- end }}
{{- end }}
{{- if $modulesSpec }}
echo "Creating Platform CR with module configuration..."
kubectl apply -f - <<'EOF'
apiVersion: config.opendatahub.io/v1alpha1
kind: Platform
metadata:
  name: default-platform
  labels:
    {{- include "rhai-on-xks-chart.labels" $root | nindent 4 }}
spec:
  modules:
    {{- $modulesSpec | toYaml | nindent 4 }}
EOF
{{- end }}
{{- end -}}

{{/*
Emit kubectl delete for the Platform CR when any module is enabled.
Include with: {{- include "rhai-on-xks-chart.moduleDeleteCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.moduleDeleteCommands" -}}
{{- $registry := include "rhai-on-xks-chart.moduleCRRegistry" . | fromYaml }}
{{- range $name := keys $registry | sortAlpha }}
  {{- $modVals := index $.Values.components $name | default dict }}
  {{- if $modVals.enabled }}
echo "Deleting Platform CR 'default-platform'..."
kubectl delete platform default-platform --ignore-not-found --timeout=300s
    {{- break }}
  {{- end }}
{{- end }}
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
Do NOT range over this and access fields with .field syntax — use crApplyCommands / crDeleteCommands instead.
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
Emit kubectl apply commands for all enabled component CRs and provider KE CRs.
Include with: {{- include "rhai-on-xks-chart.crApplyCommands" . | nindent 14 }}
Component CRs are applied before provider KE CRs.
*/}}
{{- define "rhai-on-xks-chart.crApplyCommands" -}}
{{- $root := . }}
{{- $compRegistry := include "rhai-on-xks-chart.componentCRRegistry" . | fromYaml }}
{{- range $name := keys $compRegistry | sortAlpha }}
  {{- $meta := index $compRegistry $name }}
  {{- $compVals := index $.Values.components $name | default dict }}
  {{- if $compVals.enabled }}
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
{{- end -}}

{{/*
Emit kubectl delete commands for all enabled component CRs and provider KE CRs.
Include with: {{- include "rhai-on-xks-chart.crDeleteCommands" . | nindent 14 }}
*/}}
{{- define "rhai-on-xks-chart.crDeleteCommands" -}}
{{- $compRegistry := include "rhai-on-xks-chart.componentCRRegistry" . | fromYaml }}
{{- range $name := keys $compRegistry | sortAlpha }}
  {{- $meta := index $compRegistry $name }}
  {{- $compVals := index $.Values.components $name | default dict }}
  {{- if $compVals.enabled }}
echo "Deleting {{ index $meta "kind" }} CR '{{ index $meta "crName" }}'..."
kubectl delete {{ index $meta "resourceSingular" }} {{ index $meta "crName" }} --ignore-not-found --timeout=300s
  {{- end }}
{{- end }}
{{- $provider := include "rhai-on-xks-chart.activeProvider" . | fromYaml }}
{{- if and $provider (index $provider "keEnabled") }}
echo "Deleting {{ index $provider "keKind" }} CR '{{ index $provider "keName" }}'..."
kubectl delete {{ index $provider "keResourceSingular" }} {{ index $provider "keName" }} --ignore-not-found --timeout=300s
{{- end }}
{{- end -}}
