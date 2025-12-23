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
{{- with .Values.global.labels }}
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
Merge dependency OLM config with global OLM defaults
=============================================================================
*/}}
{{- define "rhoai-dependencies.olmConfig" -}}
{{- $global := .global.olm | default dict -}}
{{- $dependency := .dependency.olm | default dict -}}
{{- $merged := merge $dependency $global -}}
{{- toYaml $merged -}}
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
Check if a dependency is required by any active component
A component is active if managementState is Managed or Unmanaged
Reads from components.<name>.dependencies.<depName> in values.yaml
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - components: the components configuration object
*/}}
{{- define "rhoai-dependencies.isRequiredByComponent" -}}
{{- $dependencyName := .dependencyName -}}
{{- $components := .components -}}
{{- $required := false -}}
{{- range $compName, $comp := $components -}}
  {{- if and $comp $comp.dsc $comp.dsc.managementState -}}
    {{- if include "rhoai-dependencies.isComponentActive" $comp.dsc.managementState -}}
      {{- $compDeps := $comp.dependencies | default dict -}}
      {{- $depEnabled := index $compDeps $dependencyName -}}
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
Check if a dependency is required by another dependency that will be installed
(Transitive dependency resolution)
Reads from dependencies.<name>.dependencies.<depName> in values.yaml
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - dependencies: the dependencies configuration object
  - components: the components configuration object
*/}}
{{- define "rhoai-dependencies.isRequiredByDependency" -}}
{{- $dependencyName := .dependencyName -}}
{{- $dependencies := .dependencies -}}
{{- $components := .components -}}
{{- $required := false -}}
{{- range $depName, $dep := $dependencies -}}
  {{- $depDeps := $dep.dependencies | default dict -}}
  {{- $needsThis := index $depDeps $dependencyName -}}
  {{- if eq ($needsThis | toString) "true" -}}
    {{- /* Check if the parent dependency will be installed */ -}}
    {{- $parentEnabled := $dep.enabled | toString -}}
    {{- if eq $parentEnabled "true" -}}
      {{- $required = true -}}
    {{- else if ne $parentEnabled "false" -}}
      {{- /* Parent is auto - check if it's required by a component */ -}}
      {{- if eq (include "rhoai-dependencies.isRequiredByComponent" (dict "dependencyName" $depName "components" $components)) "true" -}}
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
                     required by another dependency that will be installed
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency
  - dependency: the dependency configuration object
  - dependencies: all dependencies configuration object
  - components: the components configuration object
*/}}
{{- define "rhoai-dependencies.shouldInstall" -}}
{{- $dependencyName := .dependencyName -}}
{{- $dependency := .dependency -}}
{{- $dependencies := .dependencies -}}
{{- $components := .components -}}
{{- $enabled := $dependency.enabled | toString -}}
{{- if eq $enabled "true" -}}
true
{{- else if eq $enabled "false" -}}
false
{{- else -}}
{{- /* auto mode: check if required by component or by another dependency */ -}}
{{- $requiredByComponent := include "rhoai-dependencies.isRequiredByComponent" (dict "dependencyName" $dependencyName "components" $components) -}}
{{- $requiredByDependency := include "rhoai-dependencies.isRequiredByDependency" (dict "dependencyName" $dependencyName "dependencies" $dependencies "components" $components) -}}
{{- if or (eq $requiredByComponent "true") (eq $requiredByDependency "true") -}}
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
{{- if $root.Values.global.skipCrdCheck -}}
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
Merge component dsc config with operator-type defaults
Component dsc values override defaults from component.defaults.<operatorType>.
=============================================================================
Arguments (passed as dict):
  - component: the component configuration from .Values.components
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.componentDSCConfig" -}}
{{- $operatorType := .root.Values.operator.type -}}
{{- $dsc := .component.dsc | default dict -}}
{{- $defaults := dict -}}
{{- if and .component.defaults (index .component.defaults $operatorType) -}}
  {{- $defaults = index .component.defaults $operatorType -}}
{{- end -}}
{{- merge $dsc $defaults | toYaml -}}
{{- end }}

