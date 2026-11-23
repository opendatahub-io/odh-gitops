{{/*
=============================================================================
OLM Operator Templates
Reusable templates for installing operators via OLM (Subscription, OperatorGroup)
=============================================================================
*/}}

{{/*
Generate Namespace for an operator
Arguments (passed as dict):
  - namespace: namespace name
  - root: root context ($)
  - namespaceLabels: additional Namespace labels (optional)
  - namespaceAnnotations: additional Namespace annotations (optional)
  - syncWave: Argo CD sync wave (optional)
*/}}
{{- define "rhoai-dependencies.operator.namespace" -}}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .namespace }}
  annotations:
    helm.sh/resource-policy: keep
    {{- with .syncWave }}
    argocd.argoproj.io/sync-wave: {{ . | quote }}
    {{- end }}
    {{- with .namespaceAnnotations }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
  labels:
    {{- include "rhoai-dependencies.labels" .root | nindent 4 }}
    {{- with .namespaceLabels }}
    {{- toYaml . | nindent 4 }}
    {{- end }}
{{- end }}

{{/*
Generate OperatorGroup for an operator
Arguments (passed as dict):
  - name: operator name
  - operatorGroupName: custom OperatorGroup name (optional, defaults to name)
  - namespace: namespace name
  - targetNamespaces: list of target namespaces (optional, omit for AllNamespaces mode)
  - syncWave: Argo CD sync wave (optional)
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.operator.operatorgroup" -}}
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: {{ .operatorGroupName | default .name }}
  namespace: {{ .namespace }}
  {{- with .syncWave }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ . | quote }}
  {{- end }}
  labels:
    {{- include "rhoai-dependencies.labels" .root | nindent 4 }}
spec:
  upgradeStrategy: Default
  {{- with .targetNamespaces }}
  targetNamespaces:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}

{{/*
Generate Subscription for an operator
Arguments (passed as dict):
  - name: subscription/operator name
  - namespace: namespace name
  - channel: subscription channel
  - source: catalog source (optional, uses global default)
  - sourceNamespace: catalog source namespace (optional, uses global default)
  - version: operator version (optional, for version pinning) input: v$version (e.g., "v1.0.5") to form startingCSV: $name.$version
  - installPlanApproval: install plan approval (optional)
      Logic: 1) if only installPlanApproval set: use it
             2) if only version set: auto-set installPlanApproval to "Manual" to prevent upgrade
             3) if both version and installPlanApproval set: use both, this is for a minimum version case
             4) if neither set: explicitly set to "Automatic"
  - config: configuration for the subscription (optional)
  - syncWave: Argo CD sync wave (optional)
  - subscriptionSyncWave: override the Subscription's sync wave (optional)
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.operator.subscription" -}}
{{- $source := default .root.Values.olm.source .source -}}
{{- $sourceNamespace := default .root.Values.olm.sourceNamespace .sourceNamespace -}}
{{- $installPlanApproval := "Automatic" -}}
{{- if .installPlanApproval -}}
{{- $installPlanApproval = .installPlanApproval -}}
{{- else if .version -}}
{{- $installPlanApproval = "Manual" -}}
{{- end -}}
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
  {{- with (default .syncWave .subscriptionSyncWave) }}
  annotations:
    argocd.argoproj.io/sync-wave: {{ . | quote }}
  {{- end }}
  labels:
    {{- include "rhoai-dependencies.labels" .root | nindent 4 }}
spec:
  channel: {{ .channel }}
  installPlanApproval: {{ $installPlanApproval }}
  name: {{ .name }}
  source: {{ $source }}
  sourceNamespace: {{ $sourceNamespace }}
  {{- with .version }}
  startingCSV: {{ $.name }}.{{ . }}
  {{- end }}
  {{- with .config }}
  config:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}

{{/*
Generate complete OLM operator installation (Namespace, OperatorGroup, Subscription)
Arguments (passed as dict):
  - name: operator name
  - operatorGroupName: custom OperatorGroup name (optional, defaults to name)
  - namespace: namespace name
  - createNamespace: whether to generate Namespace (optional, defaults to true)
  - createOperatorGroup: whether to generate OperatorGroup (optional, defaults to true)
  - channel: subscription channel
  - source: catalog source (optional)
  - sourceNamespace: catalog source namespace (optional)
  - version: operator version (optional, for version pinning) input: v$version (e.g., "v1.0.5") to form startingCSV: $name.$version
  - installPlanApproval: install plan approval (optional)
      Logic: 1) if only installPlanApproval set: use it
             2) if only version set: auto-set installPlanApproval to "Manual" to prevent upgrade
             3) if both version and installPlanApproval set: use both, this is for a minimum version case
             4) if neither set: explicitly set to "Automatic"
  - targetNamespaces: list of target namespaces for OperatorGroup (optional)
  - syncWave: Argo CD sync wave for all generated resources (optional)
  - subscriptionSyncWave: override the Subscription's sync wave (optional)
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.operator.olm" -}}
{{- $createNamespace := true -}}
{{- if hasKey . "createNamespace" -}}
{{- $createNamespace = .createNamespace -}}
{{- end -}}
{{- if $createNamespace }}
{{ include "rhoai-dependencies.operator.namespace" . }}
---
{{- end }}
{{- $createOperatorGroup := true -}}
{{- if hasKey . "createOperatorGroup" -}}
{{- $createOperatorGroup = .createOperatorGroup -}}
{{- end -}}
{{- if $createOperatorGroup }}
{{ include "rhoai-dependencies.operator.operatorgroup" . }}
---
{{- end }}
{{ include "rhoai-dependencies.operator.subscription" . }}
{{- end }}
