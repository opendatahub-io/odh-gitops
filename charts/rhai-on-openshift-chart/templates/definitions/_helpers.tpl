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
{{- $dsci := $profileDefaults.dsci | default dict -}}
{{- if $dsci.managementState -}}
{{- $dsci.managementState -}}
{{- else -}}
Removed
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
    {{- /* Structural components (DSC v3): no component-level managementState;
           active when any child's effective state is Managed/Unmanaged */ -}}
    {{- $effectiveState := "" -}}
    {{- if and (eq $stateKey "dsc") (include "rhoai-dependencies.isStructuralComponent" (dict "name" $name)) -}}
      {{- $effectiveState = include "rhoai-dependencies.structuralComponentEffectiveState" (dict "dsc" $stateObj "root" $root "name" $name) -}}
    {{- else -}}
      {{- $effectiveState = include $stateHelper (dict "state" $stateObj.managementState "root" $root "name" $name) -}}
    {{- end -}}
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
Uses the normalized components dict (deprecated DSC v2 keys translated),
so a component enabled through a legacy key still activates dependencies.
=============================================================================
Arguments (passed as dict):
  - dependencyName: name of the dependency to check
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.isRequiredByComponent" -}}
{{- $components := include "rhoai-dependencies.components" .root | fromYaml -}}
{{- include "rhoai-dependencies._isRequiredByItems" (dict
  "dependencyName" .dependencyName
  "root" .root
  "items" $components
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
 Check whether a deprecated DSC v2 values key is meaningfully set (any
 translatable field non-nil, non-empty). Used by validation, normalization
 notices and NOTES.txt. Returns "true" when set, empty string otherwise.
 Only user-set values can appear under these keys: the chart no longer
 ships defaults for them (T2 removed them from values.yaml).
 =============================================================================
Arguments (passed as dict):
  - root: root context ($)
  - key: one of "modelregistry", "feastoperator", "dashboard.dsc.managementState",
         "trainingoperator", "kserve.dsc.wva"
*/}}
{{- define "rhoai-dependencies.legacyKeyInUse" -}}
{{- $c := .root.Values.components | default dict -}}
{{- $result := false -}}
{{- if eq .key "modelregistry" -}}
{{-   $old := index $c "modelregistry" | default dict -}}
{{-   $oldDsc := $old.dsc | default dict -}}
{{-   if or (index $oldDsc "managementState") (index $oldDsc "registriesNamespace") $old.dependencies $old.defaults -}}
{{-     $result = true -}}
{{-   end -}}
{{- else if eq .key "feastoperator" -}}
{{-   $old := index $c "feastoperator" | default dict -}}
{{-   if or (index ($old.dsc | default dict) "managementState") $old.dependencies $old.defaults -}}
{{-     $result = true -}}
{{-   end -}}
{{- else if eq .key "dashboard.dsc.managementState" -}}
{{-   $dash := index $c "dashboard" | default dict -}}
{{-   if index ($dash.dsc | default dict) "managementState" -}}
{{-     $result = true -}}
{{-   end -}}
{{- else if eq .key "trainingoperator" -}}
{{-   $old := index $c "trainingoperator" | default dict -}}
{{-   if or (index ($old.dsc | default dict) "managementState") $old.dependencies $old.defaults -}}
{{-     $result = true -}}
{{-   end -}}
{{- else if eq .key "kserve.dsc.wva" -}}
{{-   $kserve := index $c "kserve" | default dict -}}
{{-   $wva := index ($kserve.dsc | default dict) "wva" | default dict -}}
{{-   if index $wva "managementState" -}}
{{-     $result = true -}}
{{-   end -}}
{{- end -}}
{{- if $result -}}true{{- end -}}
{{- end }}

{{/*
 =============================================================================
 Chart-shipped default instance namespaces for aiHub, per operator type.
 MUST stay in sync with components.aiHub.defaults in values.yaml (they are
 intentionally identical to the old modelregistry chart defaults, so an
 upgrade across the DSC v2 -> v3 migration does not flip the value and
 trip the operator's CEL immutability check while Managed).
 Used to distinguish "user customized aiHub.defaults" (conflicts with a
 translated modelregistry.defaults) from the untouched chart default.
 =============================================================================
*/}}
{{- define "rhoai-dependencies.aiHubChartDefaultInstancesNamespaces" -}}
{{- dict "odh" "odh-model-registry" "rhoai" "rhoai-model-registries" | toYaml -}}
{{- end }}

{{/*
 =============================================================================
 Validate deprecated DSC v2 values keys against their DSC v3 replacements.
 Fails the render with an actionable message when:
  - a legacy key and its replacement are both meaningfully set (ambiguous)
  - a key with no DSC v3 equivalent is set (trainingoperator, kserve.dsc.wva)
 Called at the top of the DataScienceCluster template, before normalization.
 Chart-owned defaults blocks are never consulted here: they are plumbing,
 not user intent.
 =============================================================================
Arguments: root context ($)
*/}}
{{- define "rhoai-dependencies.validateMigration" -}}
{{- $c := .Values.components | default dict -}}

{{- /* modelregistry XOR aiHub */ -}}
{{- $newAIHub := index $c "aiHub" | default dict -}}
{{- $newAIHubDsc := $newAIHub.dsc | default dict -}}
{{- if and (include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "modelregistry"))
            (or (index $newAIHubDsc "managementState") (index $newAIHubDsc "instancesNamespace") $newAIHub.dependencies) -}}
{{-   fail "components.modelregistry and components.aiHub are mutually exclusive: modelregistry is the deprecated DSC v2 name for aiHub, and both are set (any of managementState, namespaces or dependencies).\nMigrate your values:\n  components.modelregistry.dsc.managementState      -> components.aiHub.dsc.managementState\n  components.modelregistry.dsc.registriesNamespace  -> components.aiHub.dsc.instancesNamespace\nThen remove the components.modelregistry block." -}}
{{- end -}}

{{- /* modelregistry defaults XOR customized aiHub defaults: the new side always
       carries the chart default, so only a user-customized value (different
       from the chart default) counts as the new side being set */ -}}
{{- $chartDefaultNs := include "rhoai-dependencies.aiHubChartDefaultInstancesNamespaces" . | fromYaml -}}
{{- $oldMR := index $c "modelregistry" | default dict -}}
{{- if $oldMR.defaults -}}
{{-   $newAIHubDefaults := $newAIHub.defaults | default dict -}}
{{-   range $opType, $opDefaults := $oldMR.defaults -}}
{{-     $oldNs := index $opDefaults "registriesNamespace" -}}
{{-     $newNs := index (index $newAIHubDefaults $opType | default dict) "instancesNamespace" -}}
{{-     if and $oldNs $newNs (ne $newNs (index $chartDefaultNs $opType)) -}}
{{-       fail (printf "components.modelregistry.defaults.%s.registriesNamespace and components.aiHub.defaults.%s.instancesNamespace are both customized: modelregistry is the deprecated DSC v2 name for aiHub, and both operator-type defaults are set.\nKeep only one: remove the components.modelregistry block, or reset components.aiHub.defaults.%s.instancesNamespace to the chart default (%s)." $opType $opType $opType (index $chartDefaultNs $opType)) -}}
{{-     end -}}
{{-   end -}}
{{- end -}}

{{- /* feastoperator XOR data */ -}}
{{- $newData := index $c "data" | default dict -}}
{{- $newDataDsc := $newData.dsc | default dict -}}
{{- $newFS := index $newDataDsc "featureStore" | default dict -}}
{{- $newDR := index $newDataDsc "dataRegistry" | default dict -}}
{{- if and (include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "feastoperator"))
            (or (index $newFS "managementState") (index $newDR "managementState") $newData.dependencies $newData.defaults) -}}
{{-   fail "components.feastoperator and components.data are mutually exclusive: feastoperator is the deprecated DSC v2 name for data.featureStore, and both are set (any of featureStore/dataRegistry states, dependencies or defaults).\nMigrate your values:\n  components.feastoperator.dsc.managementState -> components.data.dsc.featureStore.managementState\nThen remove the components.feastoperator block." -}}
{{- end -}}

{{- /* dashboard flat managementState XOR structural children */ -}}
{{- $dash := index $c "dashboard" | default dict -}}
{{- $dashDsc := $dash.dsc | default dict -}}
{{- $std := index $dashDsc "standard" | default dict -}}
{{- $portal := index $dashDsc "maasPortal" | default dict -}}
{{- if and (include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "dashboard.dsc.managementState"))
            (or (index $std "managementState") (index $portal "managementState")) -}}
{{-   fail "components.dashboard.dsc.managementState and its DSC v3 structural children are mutually exclusive: the Dashboard became a structural component in DSC v3 (no component-level managementState).\nMigrate your values:\n  components.dashboard.dsc.managementState -> components.dashboard.dsc.standard.managementState\nThen remove the flat managementState key." -}}
{{- end -}}

{{- /* trainingoperator: removed in DSC v3, no translation */ -}}
{{- if include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "trainingoperator") -}}
{{-   fail "components.trainingoperator was removed in DSC v3. Use components.trainer (the successor component) instead, then remove the components.trainingoperator block." -}}
{{- end -}}

{{- /* kserve.dsc.wva: removed in DSC v3, no translation */ -}}
{{- if include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "kserve.dsc.wva") -}}
{{-   fail "components.kserve.dsc.wva was removed in DSC v3: the operator now treats the llm-d Workload Variant Autoscaler as always Removed. Remove the wva block from your values." -}}
{{- end -}}
{{- end }}

{{/*
 =============================================================================
 Return the normalized components dict (toYaml) with deprecated DSC v2 keys
 translated to their DSC v3 equivalents and pruned. Rules:
  - modelregistry    -> aiHub (dsc.managementState, dsc.registriesNamespace
                        -> dsc.instancesNamespace; dependencies merged with
                        the new side winning; operator-type defaults
                        translated with the old value winning, for upgrade
                        continuity)
  - feastoperator    -> data.dsc.featureStore
  - dashboard flat   -> dashboard.dsc.standard (in place)
 Legacy keys are always pruned, even when set to null, so they can never
 leak into the rendered DataScienceCluster v3 (structural components must
 not carry a component-level managementState, and removed components must
 not appear at all). Moves only happen when the target field is unset
 (kindIs "invalid"), which the XOR validation above guarantees is
 unambiguous. Idempotent: translating already-normalized values is a no-op.
 The result is a deep copy; .Values is never mutated.
 =============================================================================
Arguments: root context ($)
*/}}
{{- define "rhoai-dependencies.components" -}}
{{- $c := deepCopy (.Values.components | default dict) -}}

{{- /* ---- modelregistry -> aiHub ---- */ -}}
{{- if hasKey $c "modelregistry" -}}
{{-   $old := index $c "modelregistry" | default dict -}}
{{-   $oldDsc := $old.dsc | default dict -}}
{{-   $new := index $c "aiHub" | default dict -}}
{{-   $newDsc := $new.dsc | default dict -}}
{{-   if and (index $oldDsc "managementState") (kindIs "invalid" (index $newDsc "managementState")) -}}
{{-     $_ := set $newDsc "managementState" (index $oldDsc "managementState") -}}
{{-   end -}}
{{-   if and (index $oldDsc "registriesNamespace") (kindIs "invalid" (index $newDsc "instancesNamespace")) -}}
{{-     $_ := set $newDsc "instancesNamespace" (index $oldDsc "registriesNamespace") -}}
{{-   end -}}
{{-   $_ := set $new "dsc" $newDsc -}}
{{-   if $old.dependencies -}}
{{- /* Defense-in-depth (unreachable while validation stands: both sides
           set fails the render). New side wins on conflicting keys; old
           side fills gaps. sprig merge: dst wins. */ -}}
{{-     $mergedDeps := merge (deepCopy ($new.dependencies | default dict)) (deepCopy $old.dependencies) -}}
{{-     $_ := set $new "dependencies" $mergedDeps -}}
{{-   end -}}
{{-   if $old.defaults -}}
{{- /* Old-wins by design for upgrade continuity: the new side only reaches
           here when its value equals the untouched chart default (see
           validateMigration), so the translated old value is what the user
           had before the migration */ -}}
{{-     $newDefaults := deepCopy ($new.defaults | default dict) -}}
{{-     range $opType, $opDefaults := $old.defaults -}}
{{-       if index $opDefaults "registriesNamespace" -}}
{{-         $target := deepCopy (index $newDefaults $opType | default dict) -}}
{{-         $_ := set $target "instancesNamespace" (index $opDefaults "registriesNamespace") -}}
{{-         $_ := set $newDefaults $opType $target -}}
{{-       end -}}
{{-     end -}}
{{-     $_ := set $new "defaults" $newDefaults -}}
{{-   end -}}
{{-   $_ := set $c "aiHub" $new -}}
{{-   $_ := unset $c "modelregistry" -}}
{{- end -}}

{{- /* ---- feastoperator -> data.featureStore ---- */ -}}
{{- if hasKey $c "feastoperator" -}}
{{-   $old := index $c "feastoperator" | default dict -}}
{{-   $new := index $c "data" | default dict -}}
{{-   $newDsc := $new.dsc | default dict -}}
{{-   $fs := index $newDsc "featureStore" | default dict -}}
{{-   if and (index ($old.dsc | default dict) "managementState") (kindIs "invalid" (index $fs "managementState")) -}}
{{-     $_ := set $fs "managementState" (index ($old.dsc | default dict) "managementState") -}}
{{-   end -}}
{{-   $_ := set $newDsc "featureStore" $fs -}}
{{-   $_ := set $new "dsc" $newDsc -}}
{{-   if $old.dependencies -}}
{{- /* Defense-in-depth (unreachable while validation stands: both sides
           set fails the render). New side wins on conflicting keys; old
           side fills gaps. sprig merge: dst wins. */ -}}
{{-     $mergedDeps := merge (deepCopy ($new.dependencies | default dict)) (deepCopy $old.dependencies) -}}
{{-     $_ := set $new "dependencies" $mergedDeps -}}
{{-   end -}}
{{- /* Operator-type defaults move verbatim: feastoperator shipped no chart
         defaults, so any user content has no automatic conflict with the
         data side (validation fails when both sides set defaults) */ -}}
{{-   if $old.defaults -}}
{{-     $_ := set $new "defaults" (deepCopy $old.defaults) -}}
{{-   end -}}
{{-   $_ := set $c "data" $new -}}
{{-   $_ := unset $c "feastoperator" -}}
{{- end -}}

{{- /* ---- dashboard: flat managementState -> standard (in place) ---- */ -}}
{{- if hasKey $c "dashboard" -}}
{{-   $dash := index $c "dashboard" | default dict -}}
{{-   $dashDsc := $dash.dsc | default dict -}}
{{-   if hasKey $dashDsc "managementState" -}}
{{-     if index $dashDsc "managementState" -}}
{{-       $std := index $dashDsc "standard" | default dict -}}
{{-       if kindIs "invalid" (index $std "managementState") -}}
{{-         $_ := set $std "managementState" (index $dashDsc "managementState") -}}
{{-         $_ := set $dashDsc "standard" $std -}}
{{-       end -}}
{{-     end -}}
{{- /* Always prune the flat key: a null value would render as an invalid component-level managementState on a structural DSC v3 component */ -}}
{{- $_ := unset $dashDsc "managementState" -}}
{{- /* Explicit reattach (defensive: do not rely on map aliasing through default dict) */ -}}
{{- $_ := set $dash "dsc" $dashDsc -}}
{{- $_ := set $c "dashboard" $dash -}}
{{-   end -}}
{{- end -}}

{{- /* trainingoperator / kserve.dsc.wva: removed in DSC v3. Validation above already failed for meaningfully-set values; prune defensively so null-only remnants cannot leak into the render */ -}}
{{- if hasKey $c "trainingoperator" -}}
{{-   $_ := unset $c "trainingoperator" -}}
{{- end -}}
{{- if hasKey $c "kserve" -}}
{{-   $kserve := index $c "kserve" | default dict -}}
{{-   if hasKey ($kserve.dsc | default dict) "wva" -}}
{{-     $kserveDsc := $kserve.dsc | default dict -}}
{{-     $_ := unset $kserveDsc "wva" -}}
{{-     $_ := set $kserve "dsc" $kserveDsc -}}
{{-     $_ := set $c "kserve" $kserve -}}
{{-   end -}}
{{- end -}}

{{- toYaml $c -}}
{{- end }}

{{/*
 =============================================================================
 Map of component names that were produced by a deprecated DSC v2 key
 translation, to the legacy key that triggered it (toYaml dict).
 Drives the deprecation comments in the rendered DataScienceCluster and
 the Deprecation Notices section in NOTES.txt. Empty when no legacy key
 is meaningfully set.
 =============================================================================
Arguments: root context ($)
*/}}
{{- define "rhoai-dependencies.translatedComponents" -}}
{{- $t := dict -}}
{{- if include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "modelregistry") -}}
{{-   $_ := set $t "aiHub" "modelregistry" -}}
{{- end -}}
{{- if include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "feastoperator") -}}
{{-   $_ := set $t "data" "feastoperator" -}}
{{- end -}}
{{- if include "rhoai-dependencies.legacyKeyInUse" (dict "root" . "key" "dashboard.dsc.managementState") -}}
{{-   $_ := set $t "dashboard" "dashboard.dsc.managementState" -}}
{{- end -}}
{{- toYaml $t -}}
{{- end }}


{{/*
 =============================================================================
 Check if a component is structural in DSC v3 (children carry independent
 managementState values; there is no component-level managementState).
 Returns "true" for structural components, empty string otherwise.
 =============================================================================
Arguments (passed as dict):
  - name: the component name
*/}}
{{- define "rhoai-dependencies.isStructuralComponent" -}}
{{- if has .name (list "dashboard" "data") -}}
true
{{- end -}}
{{- end }}

{{/*
 =============================================================================
 Resolve the effective managementState of a structural component child
 (e.g. dashboard.standard, data.featureStore).
 If the child state is explicitly set (non-null), use it.
 Otherwise, fall back to the profile default for that child, then Removed.
 =============================================================================
Arguments (passed as dict):
  - state: the child managementState value from values.yaml (may be null)
  - root: root context ($)
  - name: the component name
  - child: the child key name (e.g. "standard", "featureStore")
*/}}
{{- define "rhoai-dependencies.structuralChildEffectiveState" -}}
{{- if .state -}}
{{- .state -}}
{{- else -}}
{{- $profileDefaults := include "rhoai-dependencies.profileComponentDefaults" (dict "root" .root "name" .name) | fromYaml -}}
{{- $profileDsc := $profileDefaults.dsc | default dict -}}
{{- index ($profileDsc | dig .child (dict) | default dict) "managementState" | default "Removed" -}}
{{- end -}}
{{- end }}

{{/*
 =============================================================================
 Compute the aggregate effective state of a structural component (DSC v3).
 Uses the same child resolution as the rendered DSC (profile fallback via
 resolveNestedManagementState), so dependency activation can never diverge
 from what is rendered. Returns Managed if any child's effective state is
 Managed or Unmanaged, otherwise Removed.
 =============================================================================
Arguments (passed as dict):
  - dsc: the component's dsc config from values.yaml
  - root: root context ($)
  - name: the component name
*/}}
{{- define "rhoai-dependencies.structuralComponentEffectiveState" -}}
{{- $dsc := deepCopy (.dsc | default dict) -}}
{{- $profileDefaults := include "rhoai-dependencies.profileComponentDefaults" (dict "root" .root "name" .name) | fromYaml -}}
{{- $profileDsc := $profileDefaults.dsc | default dict -}}
{{- /* Resolve child managementStates with profile fallback (same logic as render) */ -}}
{{- $_ := include "rhoai-dependencies.resolveNestedManagementState" (dict "merged" $dsc "profileDsc" $profileDsc) -}}
{{- $state := "Removed" -}}
{{- range $key, $val := $dsc -}}
  {{- if kindIs "map" $val -}}
    {{- if include "rhoai-dependencies.isComponentActive" (index $val "managementState") -}}
      {{- $state = "Managed" -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- $state -}}
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
{{- $subComponentKeys := list "modelsAsAService" "batchGateway" "nim" "standard" "maasPortal" "featureStore" "dataRegistry" "workbenchesV2" -}}
{{- range $key, $val := $merged -}}
  {{- if and (kindIs "map" $val) (has $key $subComponentKeys) -}}
    {{- if not (index $val "managementState") -}}
      {{- $profileSub := index $profileDsc $key | default dict -}}
      {{- $subState := $profileSub.managementState | default "Removed" -}}
      {{- $_ := set $val "managementState" $subState -}}
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
{{- /* Resolve top-level managementState (flat components only; structural
       components in DSC v3 have no component-level managementState — their
       children are resolved individually by resolveNestedManagementState) */ -}}
{{- if not (include "rhoai-dependencies.isStructuralComponent" (dict "name" $componentName)) -}}
{{-   $effectiveState := include "rhoai-dependencies.effectiveComponentManagementState" (dict "state" $merged.managementState "root" $root "name" $componentName) -}}
{{-   $_ := set $merged "managementState" $effectiveState -}}
{{- end -}}
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
