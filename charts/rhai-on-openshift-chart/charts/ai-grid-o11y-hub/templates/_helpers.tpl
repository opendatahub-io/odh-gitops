{{/*
Chart name, overridable only through the release, since this chart renders a fixed set of
cluster-scoped names that the ingest contract depends on.
*/}}
{{- define "ai-grid-o11y-hub.name" -}}
{{- .Chart.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "ai-grid-o11y-hub.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels. part-of marks the whole aggregation path, hub and spoke alike, so the two
charts' objects can be listed together.
*/}}
{{- define "ai-grid-o11y-hub.labels" -}}
helm.sh/chart: {{ include "ai-grid-o11y-hub.chart" . }}
app.kubernetes.io/name: {{ include "ai-grid-o11y-hub.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/part-of: ai-grid-usage-logs
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
The LokiStack tenant, deliberately not a value.

In `openshift-logging` tenant mode the gateway's OPA sidecar injects a namespace matcher
built from the *hub's* RBAC for the `application` tenant, so a record carrying a namespace
that exists only on a spoke is accepted with 204 and then matches no query, for any user
including cluster-admin. `infrastructure` is in the gateway's --opa.skip-tenants list and
receives no matcher. Making this configurable would let a one-word override turn every
spoke's data silently unreadable.
*/}}
{{- define "ai-grid-o11y-hub.tenant" -}}
infrastructure
{{- end }}

{{- define "ai-grid-o11y-hub.lokiStackName" -}}
{{- .Values.lokiStack.name | required "lokiStack.name is required" }}
{{- end }}

{{- define "ai-grid-o11y-hub.writerName" -}}
{{- .Values.ingest.writer.serviceAccountName | default (printf "%s-writer" (include "ai-grid-o11y-hub.lokiStackName" .)) }}
{{- end }}

{{- define "ai-grid-o11y-hub.readerName" -}}
{{- .Values.ingest.reader.serviceAccountName | default (printf "%s-reader" (include "ai-grid-o11y-hub.lokiStackName" .)) }}
{{- end }}

{{- define "ai-grid-o11y-hub.obcName" -}}
{{- .Values.objectStorage.obc.name | default (printf "%s-bucket" (include "ai-grid-o11y-hub.lokiStackName" .)) }}
{{- end }}

{{/*
Name of the Secret the LokiStack reads. Rendered by this chart when
objectStorage.secret.create, supplied by the user otherwise.
*/}}
{{- define "ai-grid-o11y-hub.storageSecretName" -}}
{{- if .Values.objectStorage.secret.create -}}
{{- .Values.objectStorage.secretName | default (printf "%s-object-storage" (include "ai-grid-o11y-hub.lokiStackName" .)) }}
{{- else -}}
{{- .Values.objectStorage.secretName | required "objectStorage.secretName is required unless objectStorage.secret.create is true" }}
{{- end -}}
{{- end }}

{{/*
The ingest endpoint distributed to spokes, validated rather than passed through.

The collector's otlphttp exporter appends /v1/logs itself, so an endpoint that already ends
in it produces a 404 on every record with no other signal. The tenant segment is equally
load bearing: a record written to the application tenant is accepted with 204 and then
matches no query. Both mistakes look like success, so they are caught at render time.

Not derived from lokiStack.name even when this chart renders the store: the host comes from
the Route the Loki operator creates, whose domain is the cluster's and may carry an
infrastructure-specific prefix. Computing it would be wrong on exactly the clusters where it
matters, so it is read once and supplied.
*/}}
{{- define "ai-grid-o11y-hub.spokeEndpoint" -}}
{{- $e := .Values.spokePolicy.endpoint | required "spokePolicy.endpoint is required: the LokiStack Route host plus /api/logs/v1/infrastructure/otlp" -}}
{{- if hasSuffix "/v1/logs" $e -}}
{{- fail (printf "spokePolicy.endpoint must not end in /v1/logs; the otlphttp exporter appends it (got %q)" $e) -}}
{{- end -}}
{{- if not (hasPrefix "https://" $e) -}}
{{- fail (printf "spokePolicy.endpoint must start with https://: the policy ships this to every selected spoke, and each one sends the fleet writer token and its usage records to it (got %q)" $e) -}}
{{- end -}}
{{- if not (contains (printf "/api/logs/v1/%s/" (include "ai-grid-o11y-hub.tenant" .)) $e) -}}
{{- fail (printf "spokePolicy.endpoint must address the %s tenant: records sent to another tenant are accepted and then unreadable (got %q)" (include "ai-grid-o11y-hub.tenant" .) $e) -}}
{{- end -}}
{{- $url := urlParse $e -}}
{{- if not $url.hostname -}}
{{- fail "spokePolicy.endpoint must include a hostname" -}}
{{- end -}}
{{- $path := printf "/api/logs/v1/%s/otlp" (include "ai-grid-o11y-hub.tenant" .) -}}
{{- if or (ne $url.path $path) $url.query $url.fragment (hasSuffix "?" $e) (hasSuffix "#" $e) -}}
{{- fail (printf "spokePolicy.endpoint must use the exact ingest base path %s without a query or fragment (got %q)" $path $e) -}}
{{- end -}}
{{- $e -}}
{{- end }}

{{/*
Whether a CRD is present, so a CR is skipped until its operator has installed it. The parent
chart gates every dependency CR this way and tells the installer to re-run `helm upgrade` once
the CRDs exist; the store does the same, because the release that creates the LokiStack is also
the release that installs the Loki operator, and `helm install` rejects the whole manifest for an
unknown kind rather than retrying.

The parent's `rhoai-dependencies.crdExists` reads `.Values.skipCrdCheck` at the parent root,
which a subchart cannot see, so this reads `global.skipCrdCheck` — Helm passes `global` down —
and falls back to a live lookup.
*/}}
{{- define "ai-grid-o11y-hub.crdExists" -}}
{{- if (.root.Values.global | default dict).skipCrdCheck -}}
true
{{- else -}}
{{- $crd := lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" .crdName -}}
{{- if and $crd $crd.metadata -}}
true
{{- end -}}
{{- end -}}
{{- end }}
