# VibeXP Helm charts

Helm charts for running [VibeXP](https://vibexp.io) on Kubernetes.

| Chart | Description |
|---|---|
| [`vibexp`](charts/vibexp) | The VibeXP server, with optional text embeddings (TEI), bundled PostgreSQL + pgvector, Ingress or Gateway API |

Charts are published as OCI artifacts to GitHub Container Registry and signed
with [cosign](https://github.com/sigstore/cosign) (keyless):

```sh
helm install vibexp oci://ghcr.io/vibexp/charts/vibexp \
  --namespace vibexp --create-namespace \
  --set postgresql.enabled=true
```

Verify a chart's signature:

```sh
cosign verify ghcr.io/vibexp/charts/vibexp:<version> \
  --certificate-identity-regexp '^https://github.com/vibexp/helm-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

See the [chart's README](charts/vibexp/README.md) for configuration.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues with VibeXP itself belong in
[vibexp/vibexp](https://github.com/vibexp/vibexp/issues).

## License

[MIT](LICENSE)
