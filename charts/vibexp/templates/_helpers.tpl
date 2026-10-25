{{/* ---------- Names ---------- */}}

{{- define "vibexp.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Fully qualified app name, truncated to leave room for the longest suffix the
chart appends (`-embeddings`, 11 characters) within a 63-character DNS label.
*/}}
{{- define "vibexp.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 52 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 52 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 52 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "vibexp.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vibexp.embeddings.fullname" -}}
{{- default (printf "%s-embeddings" (include "vibexp.fullname" .)) .Values.embeddings.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "vibexp.postgresql.fullname" -}}
{{- printf "%s-postgresql" (include "vibexp.fullname" .) }}
{{- end }}

{{- define "vibexp.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "vibexp.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* ---------- Labels and annotations ---------- */}}

{{/* Usage: include "vibexp.labels" (dict "ctx" $ "component" "server") */}}
{{- define "vibexp.labels" -}}
helm.sh/chart: {{ include "vibexp.chart" .ctx }}
{{ include "vibexp.selectorLabels" . }}
app.kubernetes.io/version: {{ include "vibexp.appVersion" .ctx | quote }}
app.kubernetes.io/managed-by: {{ .ctx.Release.Service }}
app.kubernetes.io/part-of: vibexp
{{- with .ctx.Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/* Usage: include "vibexp.selectorLabels" (dict "ctx" $ "component" "server") */}}
{{- define "vibexp.selectorLabels" -}}
app.kubernetes.io/name: {{ include "vibexp.name" .ctx }}
app.kubernetes.io/instance: {{ .ctx.Release.Name }}
app.kubernetes.io/component: {{ .component }}
{{- end }}

{{/*
Common annotations merged with a resource's own.
Usage: include "vibexp.annotations" (dict "ctx" $ "annotations" .Values.service.annotations)
Renders nothing when both are empty.
*/}}
{{- define "vibexp.annotations" -}}
{{- $all := merge (deepCopy (default dict .annotations)) (default dict .ctx.Values.commonAnnotations) }}
{{- with $all }}
annotations:
  {{- tpl (toYaml .) $.ctx | nindent 2 }}
{{- end }}
{{- end }}

{{/* ---------- Images ---------- */}}

{{- define "vibexp.appVersion" -}}
{{- default .Chart.AppVersion .Values.image.tag }}
{{- end }}

{{/*
Usage: include "vibexp.image" (dict "image" .Values.image "global" .Values.global "defaultTag" .Chart.AppVersion)
*/}}
{{- define "vibexp.image" -}}
{{- $registry := default .image.registry (.global | default dict).imageRegistry }}
{{- $ref := .image.repository }}
{{- if $registry }}{{ $ref = printf "%s/%s" $registry $ref }}{{ end }}
{{- if .image.digest }}
{{- printf "%s@%s" $ref .image.digest }}
{{- else }}
{{- printf "%s:%s" $ref (toString (default .defaultTag .image.tag)) }}
{{- end }}
{{- end }}

{{/* Pull secrets: global ones plus the given list. */}}
{{- define "vibexp.imagePullSecrets" -}}
{{- $secrets := concat (default list .ctx.Values.global.imagePullSecrets) (default list .secrets) | uniq }}
{{- with $secrets }}
imagePullSecrets:
  {{- range . }}
  {{- if kindIs "string" . }}
  - name: {{ . }}
  {{- else }}
  - {{ toYaml . | nindent 4 | trim }}
  {{- end }}
  {{- end }}
{{- end }}
{{- end }}

{{/* ---------- Derived settings ---------- */}}

{{/*
The public URL: baseUrl, else the first ingress host (https when it has TLS),
else the first HTTPRoute hostname (https), else localhost (dev login on).
*/}}
{{- define "vibexp.baseUrl" -}}
{{- if .Values.baseUrl }}
{{- .Values.baseUrl | trimSuffix "/" }}
{{- else if and .Values.ingress.enabled .Values.ingress.hosts }}
{{- $host := (first .Values.ingress.hosts).host }}
{{- $tls := false }}
{{- range .Values.ingress.tls }}{{ if has $host (default list .hosts) }}{{ $tls = true }}{{ end }}{{ end }}
{{- printf "%s://%s" (ternary "https" "http" $tls) $host }}
{{- else if and .Values.httpRoute.enabled .Values.httpRoute.hostnames }}
{{- printf "https://%s" (first .Values.httpRoute.hostnames) }}
{{- else }}
{{- print "http://localhost:8080" }}
{{- end }}
{{- end }}

{{- define "vibexp.isLocalBaseUrl" -}}
{{- $u := urlParse (include "vibexp.baseUrl" .) }}
{{- if or (eq $u.hostname "localhost") (eq $u.hostname "127.0.0.1") }}true{{ end }}
{{- end }}

{{/* Whether a Service named for the embeddings server is rendered. */}}
{{- define "vibexp.embeddings.active" -}}
{{- if or .Values.embeddings.enabled .Values.embeddings.externalName }}true{{ end }}
{{- end }}

{{- define "vibexp.outboundAllowedCidrs" -}}
{{- $cidrs := default list .Values.config.outboundAllowedCidrs }}
{{- if and (include "vibexp.embeddings.active" .) .Values.embeddings.service.clusterIP (not .Values.embeddings.externalName) }}
{{- $cidrs = append $cidrs (printf "%s/32" .Values.embeddings.service.clusterIP) }}
{{- end }}
{{- $cidrs | uniq | join "," }}
{{- end }}

{{- define "vibexp.secretName" -}}
{{- default (include "vibexp.fullname" .) .Values.secrets.existingSecret }}
{{- end }}

{{- define "vibexp.configMapName" -}}
{{- default (printf "%s-config" (include "vibexp.fullname" .)) .Values.config.existingConfigMap }}
{{- end }}

{{- define "vibexp.configFileEnabled" -}}
{{- if or .Values.config.file .Values.config.existingConfigMap }}true{{ end }}
{{- end }}

{{- define "vibexp.postgresql.secretName" -}}
{{- default (include "vibexp.postgresql.fullname" .) .Values.postgresql.auth.existingSecret }}
{{- end }}

{{/*
Database connection: host, port, name, user, and where DB_PASSWORD comes from.
Returns YAML: {host, port, name, user, sslmode, passwordSecret, passwordKey}.
An empty passwordSecret means DB_PASSWORD is expected in the envFrom Secret.
*/}}
{{- define "vibexp.database" -}}
{{- if .Values.postgresql.enabled }}
host: {{ include "vibexp.postgresql.fullname" . }}
port: "5432"
name: {{ .Values.postgresql.auth.database | quote }}
user: {{ .Values.postgresql.auth.username | quote }}
sslmode: disable
passwordSecret: {{ include "vibexp.postgresql.secretName" . }}
passwordKey: {{ .Values.postgresql.auth.secretKey | quote }}
{{- else }}
host: {{ .Values.externalDatabase.host | quote }}
port: {{ .Values.externalDatabase.port | toString | quote }}
name: {{ .Values.externalDatabase.database | quote }}
user: {{ .Values.externalDatabase.username | quote }}
sslmode: {{ .Values.externalDatabase.sslmode | quote }}
{{- if .Values.externalDatabase.existingSecret }}
passwordSecret: {{ .Values.externalDatabase.existingSecret }}
passwordKey: {{ .Values.externalDatabase.secretKey | quote }}
{{- else }}
passwordSecret: ""
passwordKey: ""
{{- end }}
{{- end }}
{{- end }}

{{/*
A value for a chart-generated Secret that must survive upgrades: the given
value, else the one already stored in the live Secret, else a new one.
Usage: include "vibexp.secretValue" (dict "ctx" $ "secret" "<name>" "key" "K" "value" "<given>" "generate" "<fresh>")
Returns the plain (not base64) value.

`lookup` sees nothing under `helm template` or GitOps tools that render
offline (Argo CD): set the values explicitly there, or every render
generates new keys.
*/}}
{{- define "vibexp.secretValue" -}}
{{- if .value }}
{{- .value }}
{{- else }}
{{- $existing := lookup "v1" "Secret" .ctx.Release.Namespace .secret }}
{{- if and $existing (hasKey (default dict $existing.data) .key) }}
{{- index $existing.data .key | b64dec }}
{{- else }}
{{- .generate }}
{{- end }}
{{- end }}
{{- end }}

{{/* storageClassName for a PVC: "" = cluster default (omitted), "-" = none. */}}
{{- define "vibexp.storageClass" -}}
{{- if eq . "-" }}
storageClassName: ""
{{- else if . }}
storageClassName: {{ . | quote }}
{{- end }}
{{- end }}
