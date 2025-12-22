{{/*
=============================================================================
COMPONENT → DEPENDENCY MAP
Defines which dependencies are required by each component.
When a component's managementState is Managed or Unmanaged, its dependencies
are automatically enabled (unless explicitly disabled).
=============================================================================
*/}}
{{- define "rhoai-dependencies.componentDeps" -}}
kserve:
  - certManager
  - leaderWorkerSet
  - jobSet
  - rhcl
  - customMetricsAutoscaler
kueue:
  - certManager
  - kueue
aipipelines: []
feastoperator: []
{{- end }}

{{/*
=============================================================================
DEPENDENCY → DEPENDENCY MAP (Transitive Dependencies)
Defines which dependencies require other dependencies.
When a dependency is installed, its transitive dependencies are also
automatically enabled (unless explicitly disabled).
=============================================================================
*/}}
{{- define "rhoai-dependencies.dependencyDeps" -}}
kueue:
  - certManager
leaderWorkerSet:
  - certManager
jobSet:
  - certManager
rhcl:
  - certManager
  - leaderWorkerSet
certManager: []
customMetricsAutoscaler: []
clusterObservability: []
opentelemetry: []
tempo: []
{{- end }}

