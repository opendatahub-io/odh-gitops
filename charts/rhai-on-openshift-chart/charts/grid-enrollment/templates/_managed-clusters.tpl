{{- define "grid-enrollment.membership.name" -}}
{{- printf "%s-membership" (include "grid-enrollment.fullname" . | trunc 48 | trimSuffix "-") -}}
{{- end -}}

{{- define "grid-enrollment.membership.clusterRoleName" -}}
{{- $name := printf "%s-%s" .Release.Namespace (include "grid-enrollment.membership.name" .) -}}
{{- printf "%s-%s" ($name | trunc 54 | trimSuffix "-") ($name | sha256sum | trunc 8) -}}
{{- end -}}

{{- define "grid-enrollment.membership.lookupRules" -}}
- apiGroups: [cluster.open-cluster-management.io]
  resources: [managedclusters]
  verbs: [get, list, watch]
- apiGroups: [work.open-cluster-management.io]
  resources: [manifestworks]
  resourceNames: [{{ .Values.managedClusters.workName | quote }}]
  verbs: [get, list, watch]
{{- if .Values.gridIdentity.enabled }}
- apiGroups: [""]
  resources: [configmaps]
  resourceNames: [{{ .Values.gridIdentity.configMapName | quote }}]
  verbs: [get, list, watch]
{{- end }}
{{- end -}}
