{{/*
Expand the name of the chart.
*/}}
{{- define "rhoai-dependencies.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "rhoai-dependencies.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "rhoai-dependencies.labels" -}}
helm.sh/chart: {{ include "rhoai-dependencies.chart" . }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.labels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
=============================================================================
Get effective installation type for a dependency
Uses dependency-specific override if set, otherwise global default
=============================================================================
Arguments (passed as dict):
  - dependency: the dependency configuration object
  - global: the global configuration object
*/}}
{{- define "rhoai-dependencies.installationType" -}}
{{- $dependency := .dependency -}}
{{- $global := .global -}}
{{- if $dependency.installationType -}}
{{- $dependency.installationType -}}
{{- else -}}
{{- $global.installationType -}}
{{- end -}}
{{- end }}

{{/*
=============================================================================
Merge dependency OLM config with root-level OLM defaults
=============================================================================
*/}}
{{- define "rhoai-dependencies.olmConfig" -}}
{{- $rootOlm := .root.Values.olm | default dict -}}
{{- $dependency := .dependency.olm | default dict | deepCopy -}}
{{- $merged := merge $dependency $rootOlm -}}
{{- toYaml $merged -}}
{{- end }}

{{/*
=============================================================================
Get profile defaults for a component or service.
Returns YAML with dsc/dsci managementState and optional sub-component
states and dependency overrides.
=============================================================================
Arguments (passed as dict):
  - root: root context ($)
  - name: the component or service name
*/}}
{{- define "rhoai-dependencies.profileComponentDefaults" -}}
{{- $profile := .root.Values.profile | default "default" -}}
{{- $profileFile := printf "profiles/%s.yaml" $profile -}}
{{- $profileValues := .root.Files.Get $profileFile | fromYaml -}}
{{- $items := dict -}}
{{- if and $profileValues ($profileValues.components | default dict) -}}
  {{- $items = index ($profileValues.components | default dict) .name | default dict -}}
{{- end -}}
{{- if and (not $items) $profileValues ($profileValues.services | default dict) -}}
  {{- $items = index ($profileValues.services | default dict) .name | default dict -}}
{{- end -}}
{{- toYaml $items -}}
{{- end }}

{{/*
=============================================================================
Resolve effective managementState considering profile defaults.
If managementState is explicitly set (non-null), use it.
Otherwise, use the profile default for the given component/service name.
=============================================================================
Arguments (passed as dict):
  - state: the managementState value from values.yaml (may be null)
  - root: root context ($)
  - name: the component or service name
*/}}
{{- define "rhoai-dependencies.effectiveManagementState" -}}
{{- if .state -}}
{{- .state -}}
{{- else -}}
{{- $profileDefaults := include "rhoai-dependencies.profileComponentDefaults" (dict "root" .root "name" .name) | fromYaml -}}
{{- $dsc := $profileDefaults.dsc | default (dict "managementState" "Removed") -}}
{{- $dsci := $profileDefaults.dsci | default dict -}}
{{- if $dsci.managementState -}}
{{- $dsci.managementState -}}
{{- else -}}
{{- $dsc.managementState | default "Removed" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
=============================================================================
Check if a component is active (needs its dependencies)
A component is active if managementState is Managed or Unmanaged
=============================================================================
*/}}
{{- define "rhoai-dependencies.isComponentActive" -}}
{{- $state := . -}}
{{- if or (eq $state "Managed") (eq $state "Unmanaged") -}}
true
{{- end -}}
{{- end }}

{{/*
=============================================================================
Common helper: Check if a dependency is required by any active item.
An item is active if managementState is Managed or Unmanaged.
Supports profile dependency overrides for null dependency values.
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
  - items: the collection to iterate (components or services)
  - stateKey: the key containing managementState ("dsc" or "dsci")
*/}}
{{- define "rhoai-dependencies.isRequiredByItems" -}}
{{- $dependencyName := .dependencyName -}}
{{- $root := .root -}}
{{- $items := .items -}}
{{- $stateKey := .stateKey -}}
{{- $required := false -}}
{{- range $name, $item := $items -}}
  {{- $stateObj := index $item $stateKey -}}
  {{- if and $item $stateObj -}}
    {{- $effectiveState := include "rhoai-dependencies.effectiveManagementState" (dict "state" $stateObj.managementState "root" $root "name" $name) -}}
    {{- if include "rhoai-dependencies.isComponentActive" $effectiveState -}}
      {{- $itemDeps := $item.dependencies | default dict -}}
      {{- $depEnabled := index $itemDeps $dependencyName -}}
      {{- /* Resolve null dependency values from profile defaults */ -}}
      {{- /* kindIs "invalid" checks for nil: key exists but value is null (e.g. jobSet: in values.yaml) */ -}}
      {{- if and (hasKey $itemDeps $dependencyName) (kindIs "invalid" $depEnabled) -}}
        {{- $profileDefaults := include "rhoai-dependencies.profileComponentDefaults" (dict "root" $root "name" $name) | fromYaml -}}
        {{- $profileDeps := $profileDefaults.dependencies | default dict -}}
        {{- if hasKey $profileDeps $dependencyName -}}
          {{- $depEnabled = index $profileDeps $dependencyName -}}
        {{- else -}}
          {{- $depEnabled = true -}}
        {{- end -}}
      {{- end -}}
      {{- if eq ($depEnabled | toString) "true" -}}
        {{- $required = true -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $required -}}
{{- end }}

{{/*
=============================================================================
Check if a dependency is required by any active component
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.isRequiredByComponent" -}}
{{- include "rhoai-dependencies.isRequiredByItems" (dict "dependencyName" .dependencyName "root" .root "items" .root.Values.components "stateKey" "dsc") -}}
{{- end }}

{{/*
=============================================================================
Check if a dependency is required by any active service
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.isRequiredByService" -}}
{{- include "rhoai-dependencies.isRequiredByItems" (dict "dependencyName" .dependencyName "root" .root "items" .root.Values.services "stateKey" "dsci") -}}
{{- end }}

{{/*
=============================================================================
Check if a dependency is required by another dependency that will be installed
(Transitive dependency resolution)
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.isRequiredByDependency" -}}
{{- $dependencyName := .dependencyName -}}
{{- $root := .root -}}
{{- $required := false -}}
{{- range $depName, $dep := $root.Values.dependencies -}}
  {{- $depDeps := $dep.dependencies | default dict -}}
  {{- $needsThis := index $depDeps $dependencyName -}}
  {{- if eq ($needsThis | toString) "true" -}}
    {{- $parentEnabled := $dep.enabled | toString -}}
    {{- if eq $parentEnabled "true" -}}
      {{- $required = true -}}
    {{- else if ne $parentEnabled "false" -}}
      {{- if eq (include "rhoai-dependencies.isRequiredByComponent" (dict "dependencyName" $depName "root" $root)) "true" -}}
        {{- $required = true -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $required -}}
{{- end }}

{{/*
=============================================================================
Determine if a dependency should be installed
Tri-state logic:
  - enabled: true  → always install
  - enabled: false → never install
  - enabled: auto  → install if required by any enabled component OR
                     required by another dependency that will be installed OR
                     required by any enabled service
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency
  - dependency: the dependency configuration object
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.shouldInstall" -}}
{{- $dependencyName := .dependencyName -}}
{{- $dependency := .dependency -}}
{{- $root := .root -}}
{{- $enabled := $dependency.enabled | toString -}}
{{- if eq $enabled "true" -}}
true
{{- else if eq $enabled "false" -}}
false
{{- else -}}
{{- $requiredByComponent := include "rhoai-dependencies.isRequiredByComponent" (dict "dependencyName" $dependencyName "root" $root) -}}
{{- $requiredByDependency := include "rhoai-dependencies.isRequiredByDependency" (dict "dependencyName" $dependencyName "root" $root) -}}
{{- $requiredByService := include "rhoai-dependencies.isRequiredByService" (dict "dependencyName" $dependencyName "root" $root) -}}
{{- if or (eq $requiredByComponent "true") (eq $requiredByDependency "true") (eq $requiredByService "true") -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
=============================================================================
Check if CRD exists (for CR templates)
Returns "true" if CRD exists or skipCrdCheck is enabled, empty string otherwise
=============================================================================
Arguments (passed as dict):
  - crdName: full name of the CRD (e.g., "kueues.kueue.openshift.io")
  - root: root context ($) to access .Values
*/}}
{{- define "rhoai-dependencies.crdExists" -}}
{{- $crdName := .crdName -}}
{{- $root := .root -}}
{{- if $root.Values.skipCrdCheck -}}
true
{{- else -}}
{{- $crd := lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" $crdName -}}
{{- if and $crd $crd.metadata -}}
true
{{- end -}}
{{- end -}}
{{- end }}

{{/*
=============================================================================
Merge component dsc config with operator-type defaults and profile defaults.
Priority: user values > operator-type defaults > profile defaults.
Resolves null managementState at top level and in sub-components.
=============================================================================
Arguments (passed as dict):
  - componentName: the component name (for profile resolution)
  - component: the component configuration from .Values.components
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.componentDSCConfig" -}}
{{- $operatorType := .root.Values.operator.type -}}
{{- $componentName := .componentName -}}
{{- $root := .root -}}
{{- $dsc := .component.dsc | default dict | deepCopy -}}
{{- $operatorDefaults := dict -}}
{{- if and .component.defaults (index .component.defaults $operatorType) -}}
  {{- $operatorDefaults = index .component.defaults $operatorType -}}
{{- end -}}
{{- $profileDefaults := include "rhoai-dependencies.profileComponentDefaults" (dict "root" $root "name" $componentName) | fromYaml -}}
{{- $profileDsc := $profileDefaults.dsc | default dict -}}
{{- /* Merge: user dsc > operator defaults > profile defaults */ -}}
{{- $merged := merge $dsc $operatorDefaults -}}
{{- /* Resolve top-level managementState */ -}}
{{- $effectiveState := include "rhoai-dependencies.effectiveManagementState" (dict "state" $merged.managementState "root" $root "name" $componentName) -}}
{{- $_ := set $merged "managementState" $effectiveState -}}
{{- /* Resolve sub-component managementStates (one level deep) */ -}}
{{- range $key, $val := $merged -}}
  {{- if kindIs "map" $val -}}
    {{- if hasKey $val "managementState" -}}
      {{- if not $val.managementState -}}
        {{- $profileSub := index $profileDsc $key | default dict -}}
        {{- $subState := $profileSub.managementState | default "Removed" -}}
        {{- $_ := set $val "managementState" $subState -}}
      {{- end -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- toYaml $merged -}}
{{- end }}

{{/*
=============================================================================
Check if OLM installation mode is enabled
Returns "true" if tags.install-with-helm-dependencies is false (default), empty string otherwise
=============================================================================
*/}}
{{- define "rhoai-dependencies.isOlmMode" -}}
{{- if not (index .Values.tags "install-with-helm-dependencies") -}}
true
{{- end -}}
{{- end }}

