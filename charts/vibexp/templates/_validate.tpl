{{/*
Fails the render on settings that would otherwise only show up as a crash-looping
pod or a silently broken feature. Included from deployment.yaml.
*/}}
{{- define "vibexp.validate" -}}
{{- $v := .Values }}

{{- if ne $v.updateStrategy.type "Recreate" }}
{{- fail "updateStrategy.type must be Recreate: VibeXP migrates its database at boot, and two versions must never run against it at once" }}
{{- end }}

{{- with $v.secrets.encryptionKey }}
{{- if ne (len .) 32 }}{{ fail "secrets.encryptionKey must be exactly 32 bytes (AES-256), e.g. `openssl rand -base64 24`" }}{{ end }}
{{- end }}
{{- with $v.secrets.sessionEncryptionKey }}
{{- if not (regexMatch "^[0-9a-fA-F]{64}$" .) }}{{ fail "secrets.sessionEncryptionKey must be 64 hex characters, e.g. `openssl rand -hex 32`" }}{{ end }}
{{- end }}

{{- if not (has $v.storage.backend (list "" "filesystem" "s3" "gcs")) }}
{{- fail "storage.backend must be one of: filesystem, s3, gcs, or empty" }}
{{- end }}
{{- if and (eq $v.storage.backend "filesystem") (not $v.persistence.enabled) }}
{{- fail "storage.backend=filesystem needs persistence.enabled=true (the container filesystem is read-only); use s3/gcs or an empty backend instead" }}
{{- end }}
{{- if and (has $v.storage.backend (list "s3" "gcs")) (not $v.storage.bucket) }}
{{- fail (printf "storage.backend=%s needs storage.bucket" $v.storage.backend) }}
{{- end }}
{{- if and $v.persistence.hostPath $v.persistence.existingClaim }}
{{- fail "persistence.hostPath and persistence.existingClaim are mutually exclusive" }}
{{- end }}

{{- if and (not $v.postgresql.enabled) (not $v.externalDatabase.host) }}
{{- fail "a database is required: set externalDatabase.host, or postgresql.enabled=true for a bundled one" }}
{{- end }}
{{- if and $v.postgresql.enabled $v.externalDatabase.existingSecret }}
{{- fail "postgresql.enabled and externalDatabase.existingSecret are mutually exclusive" }}
{{- end }}
{{- if and (not $v.postgresql.enabled) (not $v.externalDatabase.existingSecret) (not $v.externalDatabase.password) (not $v.secrets.existingSecret) }}
{{- fail "no database password: set externalDatabase.existingSecret, externalDatabase.password, or provide DB_PASSWORD in secrets.existingSecret" }}
{{- end }}

{{- if and $v.embeddings.enabled $v.embeddings.externalName }}
{{- fail "embeddings.enabled (run TEI here) and embeddings.externalName (use one elsewhere) are mutually exclusive" }}
{{- end }}

{{- if and $v.config.file $v.config.existingConfigMap }}
{{- fail "config.file and config.existingConfigMap are mutually exclusive" }}
{{- end }}
{{- with $v.config.file }}
{{- $cfg := fromYaml (tpl . $) }}
{{- if hasKey $cfg "Error" }}{{ fail (printf "config.file is not valid YAML: %s" $cfg.Error) }}{{ end }}
{{- /* Removed upstream: `github:` makes 0.9.0+ refuse to boot, `fcm:` is rejected by the schema. */}}
{{- range $gone := list "github" "fcm" }}
{{- if hasKey $cfg $gone }}{{ fail (printf "config.file must not declare `%s:` (removed from VibeXP in 0.9.0)" $gone) }}{{ end }}
{{- end }}
{{- end }}

{{- if and (eq $v.service.type "ClusterIP") $v.service.nodePort }}
{{- fail "service.nodePort needs service.type NodePort or LoadBalancer" }}
{{- end }}
{{- end }}
