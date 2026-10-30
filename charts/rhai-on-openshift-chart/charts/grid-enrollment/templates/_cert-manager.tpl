{{/* Shared trust survives release removal; site membership never owns the CA. */}}
{{- define "grid-enrollment.certManager.retain" -}}
helm.sh/resource-policy: keep
argocd.argoproj.io/sync-options: Prune=false,Delete=false
{{- end }}

{{- define "grid-enrollment.external.validate" -}}
{{- $ext := .Values.external -}}
{{- $cm := .Values.external.certManager -}}
{{- if .Values.managedClusters.enabled -}}
{{- if ne .Values.mode "external" -}}
{{- fail "managedClusters.enabled requires mode=external" -}}
{{- end -}}
{{- if ne .Values.grid.membership.source "Local" -}}
{{- fail "managedClusters.enabled requires grid.membership.source=Local" -}}
{{- end -}}
{{- $_ := required "external.delivery.namespace is required for managed-cluster enrollment" $ext.delivery.namespace -}}
{{- if $ext.delivery.enabled -}}
{{- fail "managedClusters.enabled supplies identity delivery; leave external.delivery.enabled=false" -}}
{{- end -}}
{{- if gt (len (printf "%s.%s-identities" .Release.Namespace (include "grid-enrollment.membership.name" .))) 63 -}}
{{- fail "managed-cluster policy names including the release namespace must fit within 63 characters; set fullnameOverride" -}}
{{- end -}}
{{- if or (hasPrefix .Values.managedClusters.identitySecretPrefix $cm.ca.secretName) (hasPrefix .Values.managedClusters.identitySecretPrefix $ext.trustBundleSecretRef) -}}
{{- fail "managedClusters.identitySecretPrefix must not overlap shared CA or trust bundle names" -}}
{{- end -}}
{{- if $ext.sites -}}
{{- fail "managedClusters.enabled discovers sites from cluster inventory; leave external.sites empty" -}}
{{- end -}}
{{- end -}}
{{- if .Values.invites -}}
{{- fail "mode=external uses external.sites, not invites" -}}
{{- end -}}
{{- if or .Values.hubSite.name .Values.invitePolicy.enabled -}}
{{- fail "mode=external requires hubSite.name empty and invitePolicy.enabled=false; use external.sites and external.delivery" -}}
{{- end -}}
{{- if $cm.enabled -}}
{{- if and $cm.issuer.create (or (ne $cm.issuer.kind "Issuer") (ne $cm.issuer.group "cert-manager.io")) -}}
{{- fail "external.certManager.issuer.create supports only a namespaced cert-manager.io Issuer" -}}
{{- end -}}
{{- if eq $cm.ca.mode "Generate" -}}
{{- if not $cm.issuer.create -}}
{{- fail "external.certManager.ca.mode=Generate requires external.certManager.issuer.create=true" -}}
{{- end -}}
{{- if ge (int $cm.ca.renewBeforeHours) (int $cm.ca.durationHours) -}}
{{- fail "external.certManager.ca.renewBeforeHours must be less than external.certManager.ca.durationHours" -}}
{{- end -}}
{{- if eq $cm.issuer.name $cm.ca.bootstrapIssuerName -}}
{{- fail "external.certManager.issuer.name and external.certManager.ca.bootstrapIssuerName must differ" -}}
{{- end -}}
{{- if and (or $ext.sites .Values.managedClusters.enabled) (gt (int $cm.certificate.durationHours) (int $cm.ca.durationHours)) -}}
{{- fail "site certificate duration must not exceed the generated CA duration" -}}
{{- end -}}
{{- end -}}
{{- if ge (int $cm.certificate.renewBeforeHours) (int $cm.certificate.durationHours) -}}
{{- fail "external.certManager.certificate.renewBeforeHours must be less than external.certManager.certificate.durationHours" -}}
{{- end -}}
{{- end -}}
{{- if or $ext.delivery.enabled .Values.managedClusters.enabled -}}
{{- $_ := required "external.delivery.namespace is required" $ext.delivery.namespace -}}
{{- include "grid-enrollment.refuseDeliveryNamespace" (dict "key" "external.delivery.namespace" "ns" $ext.delivery.namespace "hint" (include "grid-enrollment.operatorNamespaceHint" .)) -}}
{{- if eq $ext.delivery.identitySecretName $ext.delivery.caSecretName -}}
{{- fail "external.delivery.identitySecretName and caSecretName must differ" -}}
{{- end -}}
{{- if not (and $cm.enabled $cm.issuer.create) -}}
{{- $_ := required "external issuer delivery requires external.trustBundleSecretRef" $ext.trustBundleSecretRef -}}
{{- end -}}
{{- end -}}
{{- $secrets := dict -}}
{{- $clusters := dict -}}
{{- range $name, $site := $ext.sites -}}
{{- $secret := $site.secretName | default (printf "grid-site-%s" $name) -}}
{{- if or (hasKey $secrets $secret) (eq $secret $cm.ca.secretName) (eq $secret $ext.trustBundleSecretRef) (and (eq $cm.ca.mode "Generate") (eq $secret $cm.ca.certificateName)) -}}
{{- fail "site secret names must be unique and must not overlap shared CA resources" -}}
{{- end -}}
{{- $_ := set $secrets $secret true -}}
{{- if and $ext.delivery.enabled $site.cluster -}}
{{- if gt (len (printf "%s.grid-identity-%s" $.Release.Namespace $name)) 63 -}}
{{- fail "Policy propagation requires namespace.grid-identity-site to fit within 63 characters" -}}
{{- end -}}
{{- if hasKey $clusters $site.cluster -}}
{{- fail "external.delivery supports one site identity per managed cluster" -}}
{{- end -}}
{{- $_ := set $clusters $site.cluster true -}}
{{- end -}}
{{- end -}}
{{- end }}
