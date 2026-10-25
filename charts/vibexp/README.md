# VibeXP Helm chart

![Version: 0.1.1](https://img.shields.io/badge/Version-0.1.1-informational?style=flat-square) ![Type: application](https://img.shields.io/badge/Type-application-informational?style=flat-square) ![AppVersion: 0.18.0](https://img.shields.io/badge/AppVersion-0.18.0-informational?style=flat-square)

VibeXP — the shared brain of your organization for AI. Deploys the VibeXP server (API + web app in one container) with optional in-cluster text embeddings (Hugging Face TEI) and an optional bundled PostgreSQL + pgvector.

[VibeXP](https://vibexp.io) serves its web app and API from one container. This
chart runs it on Kubernetes together with the pieces it needs, each optional:

| Component | Default | What it is |
|---|---|---|
| VibeXP server | always | One pod (see [Scaling](#scaling)) |
| PostgreSQL + pgvector | off (`postgresql.enabled`) | A single-pod database for evaluation and small installs, or bring your own (`externalDatabase`) |
| Text embeddings (TEI) | off (`embeddings.enabled`) | [Hugging Face text-embeddings-inference](https://github.com/huggingface/text-embeddings-inference) for semantic search, or point at one you run elsewhere (`embeddings.externalName`) |
| Attachments volume | on (`persistence`) | A PVC (or `hostPath`) for uploads; or use S3/GCS (`storage.backend`) |
| Ingress / HTTPRoute | off | Standard `networking.k8s.io/v1` Ingress, or a Gateway API HTTPRoute |

## Install

The chart is published as an OCI artifact:

```sh
helm install vibexp oci://ghcr.io/vibexp/charts/vibexp \
  --namespace vibexp --create-namespace \
  --set postgresql.enabled=true
```

That is an **evaluation** install: no public URL, so the base URL is
`http://localhost:8080` — VibeXP's local mode, where the dev login is on and the
SSRF guard is off (so `config.outboundAllowedCidrs` has no effect). Never expose
it. Reach it with:

```sh
kubectl -n vibexp port-forward svc/vibexp 8080:80
```

### A production install

```yaml
# values.yaml
baseUrl: https://vibexp.example.com

ingress:
  enabled: true
  className: nginx
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    nginx.ingress.kubernetes.io/proxy-body-size: 10m
  hosts:
    - host: vibexp.example.com
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: vibexp-tls
      hosts: [vibexp.example.com]

config:
  # The network your ingress controller connects from, so VibeXP sees real
  # client IPs (rate limits and audit logs depend on it).
  trustedProxies: [10.42.0.0/16]
  instanceAdmins: [you@example.com]

# Keys you manage (and back up) yourself.
secrets:
  existingSecret: vibexp-secrets   # ENCRYPTION_KEY, SESSION_ENCRYPTION_KEY

externalDatabase:
  host: postgres.example.internal
  database: vibexp
  username: vibexp
  existingSecret: vibexp-db        # key DB_PASSWORD
  sslmode: require

embeddings:
  enabled: true
  service:
    # A free address in your Service CIDR. The chart allowlists it for the
    # app's SSRF guard, which otherwise refuses to call private addresses.
    clusterIP: 10.43.200.10
```

```sh
kubectl -n vibexp create secret generic vibexp-secrets \
  --from-literal=ENCRYPTION_KEY="$(openssl rand -base64 24)" \
  --from-literal=SESSION_ENCRYPTION_KEY="$(openssl rand -hex 32)"
helm install vibexp oci://ghcr.io/vibexp/charts/vibexp -n vibexp -f values.yaml
```

A new instance starts in **setup mode** and logs a one-time setup URL
(`kubectl -n vibexp logs deploy/vibexp | grep -i setup`). Sign-in providers,
the access allowlist, mail and site branding are configured there and in
Admin → Settings — they are stored in the database, not in the chart.

## Configuration model

By default the image's built-in configuration is used and the chart feeds it
environment variables (`baseUrl`, `config.*`, the database, storage). Anything
else can be set with `extraEnv` — see the image's
[`config.docker.yaml`](https://github.com/vibexp/vibexp/blob/main/backend/config.docker.yaml)
for every variable it reads.

For full control, set `config.file` to a complete `config.yaml` (start from
[`config.example.yaml`](https://github.com/vibexp/vibexp/blob/main/backend/config.example.yaml)).
It replaces the built-in file; `${VAR}` references inside it are resolved from
the environment, so keep secrets in the Secret and reference them. The pod
restarts when the file's content changes.

## Secrets

Without `secrets.existingSecret` the chart creates a Secret and generates
`ENCRYPTION_KEY` and `SESSION_ENCRYPTION_KEY` on first install, re-using them on
upgrades. The encryption key protects the credentials VibeXP stores in its
database — **back it up**; losing it makes them unreadable. The Secret is kept
when the release is uninstalled.

Generated values rely on Helm's `lookup`, which renders nothing in
`helm template` and in GitOps tools that render offline (Argo CD). There, set
the keys explicitly or use `existingSecret`, or each render produces new ones.

## Semantic search and the SSRF guard

The embedding provider is configured **per team in the app** (Settings →
Embedding Providers); the chart only runs the server. Use
`http://<fullname>-embeddings:80` as its URL (`vibexp-embeddings` for a release named `vibexp`; the install notes print it),
and a model that produces **1024-dimensional** vectors — the default
`mixedbread-ai/mxbai-embed-large-v1` does.

Outside local mode (a non-localhost base URL), VibeXP refuses outbound calls to
private addresses unless they are allowlisted,
and it checks the IP it dials — the TEI Service's ClusterIP. Either pin
`embeddings.service.clusterIP` (the chart then allowlists it), or add your
Service CIDR to `config.outboundAllowedCidrs`. Otherwise embedding fails with
`connection to disallowed address range blocked`.

## Scaling

VibeXP runs exactly **one replica** with the `Recreate` strategy: it migrates
its database at boot, and two versions must never run against it at once. An
upgrade therefore has a short downtime. Migrations are not reversible — take a
database backup before upgrading, and roll back by restoring it.

## Upgrading

Chart versions follow SemVer; breaking changes bump the major version (minor
before 1.0) and are described in the release notes.

## Requirements

Kubernetes: `>=1.25.0-0`

## Values

| Key | Type | Default | Description |
|-----|------|---------|-------------|
| affinity | object | `{}` | Affinity. |
| baseUrl | string | `""` | The public URL of this instance — the single origin that serves the web app and the API (e.g. `https://vibexp.example.com`). Used for OAuth callbacks, the MCP endpoint and links in mail. When empty it is derived from the first ingress/HTTPRoute host, and failing that it is `http://localhost:8080`: an evaluation setup where the DEV LOGIN IS ON and the SSRF guard is OFF (private destinations are all reachable). Never expose an instance whose base URL points at localhost. |
| commonAnnotations | object | `{}` | Annotations added to every resource the chart renders. |
| commonLabels | object | `{}` | Labels added to every resource the chart renders. |
| config.existingConfigMap | string | `""` | Use an existing ConfigMap (key `config.yaml`) instead of `config.file`. |
| config.file | string | `""` | A complete VibeXP `config.yaml`, rendered with `tpl` (so it may use `{{ .Values.* }}`). Replaces the image's built-in config. Start from https://github.com/vibexp/vibexp/blob/main/backend/config.example.yaml. `${VAR}` placeholders are resolved by the app from the environment, so keep secrets in a Secret and reference them. |
| config.instanceAdmins | list | `[]` | Root instance administrators (emails). They cannot be revoked in the UI, and the first sign-in by one of them ends the setup mode of a new instance. |
| config.logFormat | string | `"json"` | Log format: json or text. |
| config.logLevel | string | `"info"` | Log level: debug, info, warn, error. |
| config.outboundAllowedCidrs | list | `[]` | Private CIDRs VibeXP may call out to. The SSRF guard refuses every loopback/private destination by default — including an in-cluster embeddings or LLM service. The embeddings Service IP is added automatically when `embeddings.service.clusterIP` is set. Link-local and multicast can never be allowlisted; overlapping entries abort startup. |
| config.trustedProxies | list | `[]` | CIDRs of the proxies allowed to set X-Forwarded-For (your ingress controller's pod or node range, e.g. `10.42.0.0/16` on k3s). Empty means the header is ignored and every client is rate-limited as the proxy's address — set this whenever VibeXP sits behind an ingress. |
| embeddings.affinity | object | `{}` | Affinity. |
| embeddings.enabled | bool | `false` | Run TEI in the cluster (or point a Service at an external one, below). |
| embeddings.externalName | string | `""` | Instead of deploying TEI, create an ExternalName Service pointing at this DNS name (an embeddings server running elsewhere). |
| embeddings.extraArgs | list | `["--auto-truncate","--max-client-batch-size","64"]` | Extra TEI arguments. |
| embeddings.extraEnv | list | `[]` | Extra environment variables. |
| embeddings.huggingfaceToken | object | `{"existingSecret":"","key":"HF_TOKEN"}` | Secret with a Hugging Face token for gated/private models. |
| embeddings.image.digest | string | `""` | TEI image digest. |
| embeddings.image.pullPolicy | string | `"IfNotPresent"` | Pull policy. |
| embeddings.image.registry | string | `"ghcr.io"` | TEI image registry. |
| embeddings.image.repository | string | `"huggingface/text-embeddings-inference"` | TEI image repository. |
| embeddings.image.tag | string | `"cpu-1.9"` | TEI image tag (`cpu-*`, or a GPU variant such as `1.9` / `89-1.9`). |
| embeddings.livenessProbe | object | `{"httpGet":{"path":"/health","port":"http"},"periodSeconds":30,"timeoutSeconds":5}` | Liveness probe. |
| embeddings.model | string | `"mixedbread-ai/mxbai-embed-large-v1"` | Model to serve. Must produce 1024-dimensional embeddings. |
| embeddings.nameOverride | string | `""` | Service name. Defaults to `<fullname>-embeddings`. The provider URL entered in the app names it, so keep it stable. |
| embeddings.nodeSelector | object | `{}` | Node selector. |
| embeddings.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. |
| embeddings.persistence.annotations | object | `{}` | PVC annotations. |
| embeddings.persistence.enabled | bool | `true` | Persist the model cache. |
| embeddings.persistence.existingClaim | string | `""` | Existing PVC. |
| embeddings.persistence.size | string | `"5Gi"` | Size. |
| embeddings.persistence.storageClass | string | `""` | Storage class. |
| embeddings.podAnnotations | object | `{}` | Pod annotations. |
| embeddings.podLabels | object | `{}` | Pod labels. |
| embeddings.podSecurityContext | object | `{"fsGroup":1000,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":1000,"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context. |
| embeddings.priorityClassName | string | `""` | Priority class. |
| embeddings.readinessProbe | object | `{"httpGet":{"path":"/health","port":"http"},"periodSeconds":10,"timeoutSeconds":5}` | Readiness probe. |
| embeddings.resources | object | `{"limits":{"memory":"4Gi"},"requests":{"cpu":"250m","memory":"2Gi"}}` | Resources. The default model needs ~2.5 GiB of memory on CPU. |
| embeddings.revision | string | `""` | Model revision (empty for the default branch). |
| embeddings.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container security context. |
| embeddings.service.annotations | object | `{}` | Service annotations. |
| embeddings.service.clusterIP | string | `""` | Fixed ClusterIP. Set it to a free address in your Service CIDR and the chart adds `<ip>/32` to `config.outboundAllowedCidrs`, which the app's SSRF guard needs in order to reach TEI. Otherwise allowlist the Service CIDR yourself. |
| embeddings.service.port | int | `80` | Service port. |
| embeddings.startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/health","port":"http"},"periodSeconds":10}` | Startup probe (allows ~10 minutes to download and load the model). |
| embeddings.tolerations | list | `[]` | Tolerations. |
| externalDatabase.database | string | `"vibexp"` | Database name. Leave empty to supply `DB_NAME` from `secrets.existingSecret`. |
| externalDatabase.existingSecret | string | `""` | Existing Secret with the password. When neither this nor `password` is set, `DB_PASSWORD` must be in `secrets.existingSecret`. |
| externalDatabase.host | string | `""` | Host. |
| externalDatabase.password | string | `""` | Password (stored in the chart's Secret). Prefer `existingSecret`. |
| externalDatabase.port | int | `5432` | Port. |
| externalDatabase.secretKey | string | `"DB_PASSWORD"` | Key of the password in `existingSecret`. |
| externalDatabase.sslmode | string | `"require"` | `sslmode` (disable, require, verify-ca, verify-full). |
| externalDatabase.username | string | `"vibexp"` | User. Leave empty to supply `DB_USER` from `secrets.existingSecret`. |
| extraEnv | list | `[]` | Extra environment variables (list of EnvVar). They take precedence over the variables the chart sets. |
| extraEnvFrom | list | `[]` | Extra `envFrom` sources (Secrets/ConfigMaps). |
| extraObjects | list | `[]` | Extra manifests deployed with the release (list of objects or strings, rendered with `tpl`). |
| extraVolumeMounts | list | `[]` | Extra volume mounts for the VibeXP container. |
| extraVolumes | list | `[]` | Extra volumes for the VibeXP pod. |
| fullnameOverride | string | `""` | Override the full resource name prefix (default `<release>-vibexp`, or `<release>` when the release name already contains `vibexp`). |
| global.imagePullSecrets | list | `[]` | Pull secrets added to every pod of the chart. |
| global.imageRegistry | string | `""` | Registry prepended to every image of the chart (overrides each `image.registry`). For mirrors and air-gapped clusters. |
| httpRoute.annotations | object | `{}` | Annotations. |
| httpRoute.enabled | bool | `false` | Create an HTTPRoute (needs the Gateway API CRDs). |
| httpRoute.hostnames | list | `[]` | Hostnames. The first also derives `baseUrl` when that and the ingress are unset; it is assumed to be served over https. |
| httpRoute.matches | list | `[{"path":{"type":"PathPrefix","value":"/"}}]` | Path matches. |
| httpRoute.parentRefs | list | `[]` | Gateways to attach to. |
| image.digest | string | `""` | Image digest (`sha256:...`). When set it is used instead of the tag. |
| image.pullPolicy | string | `"IfNotPresent"` | Image pull policy. |
| image.registry | string | `"ghcr.io"` | Image registry. |
| image.repository | string | `"vibexp/vibexp"` | Image repository. |
| image.tag | string | `""` | Image tag. Defaults to the chart's `appVersion`. |
| imagePullSecrets | list | `[]` | Pull secrets for the VibeXP pod (in addition to `global.imagePullSecrets`). |
| ingress.annotations | object | `{}` | Ingress annotations (e.g. cert-manager, proxy body size — uploads can be 10 MiB). |
| ingress.className | string | `""` | Ingress class. |
| ingress.enabled | bool | `false` | Create an Ingress. |
| ingress.hosts | list | `[{"host":"vibexp.local","paths":[{"path":"/","pathType":"Prefix"}]}]` | Hosts. The first host also derives `baseUrl` when that is empty. |
| ingress.tls | list | `[]` | TLS (`[{secretName, hosts}]`). |
| initContainers | list | `[]` | Init containers (rendered with `tpl`). |
| livenessProbe | object | `{"failureThreshold":4,"httpGet":{"path":"/healthz","port":"http"},"periodSeconds":30,"timeoutSeconds":5}` | Liveness probe. |
| nameOverride | string | `""` | Override the chart name in resource names. |
| networkPolicy.enabled | bool | `false` | Create a NetworkPolicy for the VibeXP pod (ingress only; egress stays open — the app calls LLM, mail and identity providers on the internet). |
| networkPolicy.ingressFrom | list | `[]` | Peers allowed to reach the HTTP port (empty = any). |
| nodeSelector | object | `{}` | Node selector. |
| persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. |
| persistence.annotations | object | `{}` | Extra annotations on the PVC. |
| persistence.enabled | bool | `true` | Mount a volume for attachments (used when `storage.backend` is `filesystem`). |
| persistence.existingClaim | string | `""` | Use an existing PVC. |
| persistence.hostPath | string | `""` | Use a directory on the node instead of a PVC (single-node clusters). It must exist and be writable by uid 100 / gid 101. |
| persistence.keep | bool | `true` | Keep the PVC when the release is uninstalled. |
| persistence.mountPath | string | `"/var/lib/vibexp/attachments"` | Where the volume is mounted in the container. |
| persistence.size | string | `"10Gi"` | Size. |
| persistence.storageClass | string | `""` | Storage class (`-` for none, empty for the cluster default). |
| podAnnotations | object | `{}` | Annotations added to the VibeXP pod. |
| podLabels | object | `{}` | Labels added to the VibeXP pod. |
| podSecurityContext | object | `{"fsGroup":101,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":101,"runAsNonRoot":true,"runAsUser":100,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod-level security context. The image's `vibexp` user is uid 100 / gid 101. |
| postgresql.affinity | object | `{}` | Affinity. |
| postgresql.auth.database | string | `"vibexp"` | Database name. |
| postgresql.auth.existingSecret | string | `""` | Existing Secret with the password. |
| postgresql.auth.password | string | `""` | Password. Generated when empty. |
| postgresql.auth.secretKey | string | `"password"` | Key of the password in `existingSecret`. |
| postgresql.auth.username | string | `"vibexp"` | Database user (a superuser of the bundled server). |
| postgresql.enabled | bool | `false` | Run a bundled PostgreSQL + pgvector. |
| postgresql.image.digest | string | `""` | Image digest. |
| postgresql.image.pullPolicy | string | `"IfNotPresent"` | Pull policy. |
| postgresql.image.registry | string | `"docker.io"` | Image registry. |
| postgresql.image.repository | string | `"pgvector/pgvector"` | Image repository. |
| postgresql.image.tag | string | `"0.8.1-pg17"` | Image tag. |
| postgresql.nodeSelector | object | `{}` | Node selector. |
| postgresql.persistence.accessModes | list | `["ReadWriteOnce"]` | Access modes. |
| postgresql.persistence.annotations | object | `{}` | PVC annotations. |
| postgresql.persistence.enabled | bool | `true` | Persist the data directory. |
| postgresql.persistence.existingClaim | string | `""` | Existing PVC. |
| postgresql.persistence.size | string | `"8Gi"` | Size. |
| postgresql.persistence.storageClass | string | `""` | Storage class. |
| postgresql.podAnnotations | object | `{}` | Pod annotations. |
| postgresql.podLabels | object | `{}` | Pod labels. |
| postgresql.podSecurityContext | object | `{"fsGroup":999,"fsGroupChangePolicy":"OnRootMismatch","runAsGroup":999,"runAsNonRoot":true,"runAsUser":999,"seccompProfile":{"type":"RuntimeDefault"}}` | Pod security context (the image's `postgres` user is 999). |
| postgresql.resources | object | `{"limits":{"memory":"1Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resources. |
| postgresql.securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]}}` | Container security context. |
| postgresql.tolerations | list | `[]` | Tolerations. |
| priorityClassName | string | `""` | Priority class. |
| readinessProbe | object | `{"failureThreshold":3,"httpGet":{"path":"/readyz","port":"http"},"periodSeconds":10,"timeoutSeconds":5}` | Readiness probe. |
| resources | object | `{"limits":{"memory":"2Gi"},"requests":{"cpu":"100m","memory":"256Mi"}}` | Resource requests and limits for the VibeXP container. |
| revisionHistoryLimit | int | `3` | Number of old ReplicaSets to keep for rollback. |
| secrets.apiKeyCommon | string | `""` | Optional shared API key (`API_KEY_COMMON`). |
| secrets.backofficeAdminApiKey | string | `""` | Optional back-office admin API key (`BACKOFFICE_ADMIN_API_KEY`). |
| secrets.encryptionKey | string | `""` | AES-256 key, EXACTLY 32 bytes. Encrypts credentials stored in the database: changing or losing it makes them unreadable. Generated when empty. |
| secrets.existingSecret | string | `""` | Name of an existing Secret holding at least `ENCRYPTION_KEY` and `SESSION_ENCRYPTION_KEY`. |
| secrets.keep | bool | `true` | Keep the generated Secret when the release is uninstalled (`helm.sh/resource-policy: keep`), so a reinstall can still read the data. |
| secrets.sessionEncryptionKey | string | `""` | Session encryption key, 64 hex characters. Generated when empty. |
| securityContext | object | `{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},"readOnlyRootFilesystem":true}` | Container-level security context. |
| service.annotations | object | `{}` | Service annotations. |
| service.clusterIP | string | `""` | Fixed ClusterIP (empty to let Kubernetes choose). |
| service.labels | object | `{}` | Extra Service labels. |
| service.nodePort | string | `""` | Node port when `type` is NodePort/LoadBalancer. |
| service.port | int | `80` | Service port. |
| service.type | string | `"ClusterIP"` | Service type. |
| serviceAccount.annotations | object | `{}` | Annotations (e.g. for workload identity). |
| serviceAccount.automountServiceAccountToken | bool | `false` | Mount the API token. VibeXP never calls the Kubernetes API. |
| serviceAccount.create | bool | `true` | Create a ServiceAccount. |
| serviceAccount.name | string | `""` | Its name (generated from the fullname when empty). |
| sidecars | list | `[]` | Additional containers in the VibeXP pod (rendered with `tpl`). |
| startupProbe | object | `{"failureThreshold":60,"httpGet":{"path":"/healthz","port":"http"},"periodSeconds":5}` | Startup probe. Generous, because migrations run before the server listens. |
| storage.backend | string | `"filesystem"` | `filesystem`, `s3`, `gcs`, or empty (attachments disabled). |
| storage.bucket | string | `""` | Bucket for the `s3` and `gcs` backends. |
| storage.s3.accessKeyKey | string | `"S3_ACCESS_KEY"` | Key of the access key in `existingSecret`. |
| storage.s3.endpoint | string | `""` | S3 endpoint (empty for AWS). |
| storage.s3.existingSecret | string | `""` | Secret with the S3 credentials. |
| storage.s3.pathStyle | bool | `false` | Path-style addressing (MinIO and most self-hosted stores). |
| storage.s3.region | string | `""` | S3 region. |
| storage.s3.secretKeyKey | string | `"S3_SECRET_KEY"` | Key of the secret key in `existingSecret`. |
| terminationGracePeriodSeconds | int | `30` | Seconds to wait for a graceful shutdown. |
| tests.image | object | `{"digest":"","registry":"docker.io","repository":"busybox","tag":"1.37"}` | Image of the `helm test` pod. |
| tolerations | list | `[]` | Tolerations. |
| topologySpreadConstraints | list | `[]` | Topology spread constraints. |
| updateStrategy | object | `{"type":"Recreate"}` | Deployment strategy. VibeXP runs ONE replica: it applies database migrations at boot and two versions must never share a database, so the old pod is stopped before the new one starts. Changing this to RollingUpdate is not supported. |
| waitForDatabase.enabled | bool | `true` | Wait for the database port before starting VibeXP. |
| waitForDatabase.image.digest | string | `""` |  |
| waitForDatabase.image.pullPolicy | string | `"IfNotPresent"` |  |
| waitForDatabase.image.registry | string | `"docker.io"` |  |
| waitForDatabase.image.repository | string | `"busybox"` |  |
| waitForDatabase.image.tag | string | `"1.37"` |  |
| waitForDatabase.timeoutSeconds | int | `300` | Give up (and let the pod restart) after this many seconds. |
