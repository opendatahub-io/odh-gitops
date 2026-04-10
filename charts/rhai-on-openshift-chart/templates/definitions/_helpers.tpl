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
Get profile defaults for a component.
Returns YAML with dsc managementState and optional sub-component
states and dependency overrides.
=============================================================================
Arguments (passed as dict):
  - root: root context ($)
  - name: the component name
*/}}
{{- define "rhoai-dependencies.profileComponentDefaults" -}}
{{- $profile := .root.Values.profile | default "default" -}}
{{- $profileFile := printf "profiles/%s.yaml" $profile -}}
{{- $profileValues := .root.Files.Get $profileFile | fromYaml -}}
{{- $items := dict -}}
{{- if $profileValues -}}
  {{- $items = index ($profileValues.components | default dict) .name | default dict -}}
{{- end -}}
{{- toYaml $items -}}
{{- end }}

{{/*
=============================================================================
Get profile defaults for a service.
Returns YAML with dsci managementState and optional dependency overrides.
=============================================================================
Arguments (passed as dict):
  - root: root context ($)
  - name: the service name
*/}}
{{- define "rhoai-dependencies.profileServiceDefaults" -}}
{{- $profile := .root.Values.profile | default "default" -}}
{{- $profileFile := printf "profiles/%s.yaml" $profile -}}
{{- $profileValues := .root.Files.Get $profileFile | fromYaml -}}
{{- $items := dict -}}
{{- if $profileValues -}}
  {{- $items = index ($profileValues.services | default dict) .name | default dict -}}
{{- end -}}
{{- toYaml $items -}}
{{- end }}

{{/*
=============================================================================
Resolve effective managementState for a component considering profile defaults.
If managementState is explicitly set (non-null), use it.
Otherwise, use the profile default for the given component name.
=============================================================================
Arguments (passed as dict):
  - state: the managementState value from values.yaml (may be null)
  - root: root context ($)
  - name: the component name
*/}}
{{- define "rhoai-dependencies.effectiveComponentManagementState" -}}
{{- if .state -}}
{{- .state -}}
{{- else -}}
{{- $profileDefaults := include "rhoai-dependencies.profileComponentDefaults" (dict "root" .root "name" .name) | fromYaml -}}
{{- $dsc := $profileDefaults.dsc | default (dict "managementState" "Removed") -}}
{{- $dsc.managementState | default "Removed" -}}
{{- end -}}
{{- end }}

{{/*
=============================================================================
Resolve effective managementState for a service considering profile defaults.
If managementState is explicitly set (non-null), use it.
Otherwise, use the profile default for the given service name.
=============================================================================
Arguments (passed as dict):
  - state: the managementState value from values.yaml (may be null)
  - root: root context ($)
  - name: the service name
*/}}
{{- define "rhoai-dependencies.effectiveServiceManagementState" -}}
{{- if .state -}}
{{- .state -}}
{{- else -}}
{{- $profileDefaults := include "rhoai-dependencies.profileServiceDefaults" (dict "root" .root "name" .name) | fromYaml -}}
{{- $dsci := $profileDefaults.dsci | default (dict "managementState" "Removed") -}}
{{- $dsci.managementState | default "Removed" -}}
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
INTERNAL: Generic helper to check if a dependency is required by active items.
An item is active if managementState is Managed or Unmanaged.
Supports profile dependency overrides for null dependency values.
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
  - items: the collection to iterate
  - stateKey: the key containing managementState ("dsc" or "dsci")
  - profileHelper: name of profile helper ("rhoai-dependencies.profileComponentDefaults" or "rhoai-dependencies.profileServiceDefaults")
  - stateHelper: name of state helper ("rhoai-dependencies.effectiveComponentManagementState" or "rhoai-dependencies.effectiveServiceManagementState")
*/}}
{{- define "rhoai-dependencies._isRequiredByItems" -}}
{{- $dependencyName := .dependencyName -}}
{{- $root := .root -}}
{{- $items := .items -}}
{{- $stateKey := .stateKey -}}
{{- $profileHelper := .profileHelper -}}
{{- $stateHelper := .stateHelper -}}
{{- $required := false -}}
{{- range $name, $item := $items -}}
  {{- $stateObj := index $item $stateKey -}}
  {{- if and $item (hasKey $item $stateKey) -}}
    {{- $effectiveState := include $stateHelper (dict "state" $stateObj.managementState "root" $root "name" $name) -}}
    {{- if include "rhoai-dependencies.isComponentActive" $effectiveState -}}
      {{- $itemDeps := $item.dependencies | default dict -}}
      {{- $depEnabled := index $itemDeps $dependencyName -}}
      {{- /* Resolve null dependency values from profile defaults */ -}}
      {{- /* kindIs "invalid" checks for nil: key exists but value is null (e.g. jobSet: in values.yaml) */ -}}
      {{- if and (hasKey $itemDeps $dependencyName) (kindIs "invalid" $depEnabled) -}}
        {{- $profileDefaults := include $profileHelper (dict "root" $root "name" $name) | fromYaml -}}
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
Check if a dependency is required by any active component.
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.isRequiredByComponent" -}}
{{- include "rhoai-dependencies._isRequiredByItems" (dict
  "dependencyName" .dependencyName
  "root" .root
  "items" .root.Values.components
  "stateKey" "dsc"
  "profileHelper" "rhoai-dependencies.profileComponentDefaults"
  "stateHelper" "rhoai-dependencies.effectiveComponentManagementState"
) -}}
{{- end }}

{{/*
=============================================================================
Check if a dependency is required by any active service.
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.isRequiredByService" -}}
{{- include "rhoai-dependencies._isRequiredByItems" (dict
  "dependencyName" .dependencyName
  "root" .root
  "items" .root.Values.services
  "stateKey" "dsci"
  "profileHelper" "rhoai-dependencies.profileServiceDefaults"
  "stateHelper" "rhoai-dependencies.effectiveServiceManagementState"
) -}}
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
      {{- if eq (include "rhoai-dependencies.shouldInstall" (dict "dependencyName" $depName "dependency" $dep "root" $root)) "true" -}}
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
Resolve nested (one level deep) managementState values.
For each map-valued key in the merged config, if it has a managementState
field that is null/empty, fall back to the corresponding value from profileDsc.
This helper mutates the merged dict in place (via set) and returns empty output.
=============================================================================
Arguments (passed as dict):
  - merged: the merged DSC config (user > operator > profile)
  - profileDsc: the profile DSC defaults (for fallback)
*/}}
{{- define "rhoai-dependencies.resolveNestedManagementState" -}}
{{- $merged := .merged -}}
{{- $profileDsc := .profileDsc -}}
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
{{- $profileDsc := $profileDefaults.dsc | default dict | deepCopy -}}
{{- /* Merge: user dsc > operator defaults > profile defaults */ -}}
{{- $merged := merge $dsc (deepCopy $operatorDefaults) $profileDsc -}}
{{- /* Resolve top-level managementState */ -}}
{{- $effectiveState := include "rhoai-dependencies.effectiveComponentManagementState" (dict "state" $merged.managementState "root" $root "name" $componentName) -}}
{{- $_ := set $merged "managementState" $effectiveState -}}
{{- /* Resolve sub-component managementStates (one level deep) */ -}}
{{- $_ := include "rhoai-dependencies.resolveNestedManagementState" (dict "merged" $merged "profileDsc" $profileDsc) -}}
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

