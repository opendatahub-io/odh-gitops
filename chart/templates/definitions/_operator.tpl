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
*/}}
{{- define "rhoai-dependencies.operator.namespace" -}}
apiVersion: v1
kind: Namespace
metadata:
  name: {{ .namespace }}
  labels:
    {{- include "rhoai-dependencies.labels" .root | nindent 4 }}
{{- end }}

{{/*
Generate OperatorGroup for an operator (single namespace mode)
Arguments (passed as dict):
  - namespace: namespace name
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.operator.operatorgroup" -}}
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: {{ .namespace }}
  namespace: {{ .namespace }}
  labels:
    {{- include "rhoai-dependencies.labels" .root | nindent 4 }}
spec:
  upgradeStrategy: Default
{{- end }}

{{/*
Generate Subscription for an operator
Arguments (passed as dict):
  - name: subscription/operator name
  - namespace: namespace name
  - channel: subscription channel
  - source: catalog source (optional, uses global default)
  - sourceNamespace: catalog source namespace (optional, uses global default)
  - installPlanApproval: install plan approval (optional, uses global default)
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.operator.subscription" -}}
{{- $source := default .root.Values.global.olm.source .source -}}
{{- $sourceNamespace := default .root.Values.global.olm.sourceNamespace .sourceNamespace -}}
{{- $installPlanApproval := default .root.Values.global.olm.installPlanApproval .installPlanApproval -}}
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: {{ .name }}
  namespace: {{ .namespace }}
  labels:
    {{- include "rhoai-dependencies.labels" .root | nindent 4 }}
spec:
  channel: {{ .channel }}
  installPlanApproval: {{ $installPlanApproval }}
  name: {{ .name }}
  source: {{ $source }}
  sourceNamespace: {{ $sourceNamespace }}
{{- end }}

{{/*
Generate complete OLM operator installation (Namespace + OperatorGroup + Subscription)
Arguments (passed as dict):
  - name: operator name
  - namespace: namespace name
  - channel: subscription channel
  - source: catalog source (optional)
  - sourceNamespace: catalog source namespace (optional)
  - installPlanApproval: install plan approval (optional)
  - root: root context ($)
*/}}
{{- define "rhoai-dependencies.operator.olm" -}}
{{ include "rhoai-dependencies.operator.namespace" . }}
---
{{ include "rhoai-dependencies.operator.operatorgroup" . }}
---
{{ include "rhoai-dependencies.operator.subscription" . }}
{{- end }}

