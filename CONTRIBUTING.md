# Contributing

1. Change the chart under `charts/<name>/`.
2. **Bump `version` in its `Chart.yaml`** (SemVer — CI rejects a change without
   one). Bump `appVersion` too when moving to a new VibeXP release.
3. Regenerate the chart README: `helm-docs` (or
   `docker run --rm -v "$PWD:/helm-docs" -u "$(id -u)" jnorwood/helm-docs:v1.14.2`).
4. Run the checks locally:

   ```sh
   helm lint charts/vibexp -f charts/vibexp/ci/default-values.yaml
   ct lint --config ct.yaml
   ct install --config ct.yaml   # needs a cluster, e.g. `kind create cluster`
   ```

5. Open a pull request. CI lints, validates the manifests against the
   Kubernetes schemas and installs every `ci/*-values.yaml` case into kind.

Merging to `main` publishes every chart whose version is not yet released: the
package is pushed to `oci://ghcr.io/vibexp/charts`, signed with cosign, and a
GitHub release `<chart>-<version>` is created.

Values are documented with `# --` comments, which helm-docs turns into the
README's values table. Keep `values.schema.json` in step with `values.yaml`.
