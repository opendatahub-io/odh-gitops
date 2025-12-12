{{/*
=============================================================================
DEPENDENCY MAP
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
  - kueue
aipipelines: []
{{- end }}

