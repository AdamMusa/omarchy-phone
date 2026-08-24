# Omarchy UI runtime provenance

The bundled `omarchy-ui-runtime` is byte-for-byte the artifact published by the
attested Omarchy UI runtime release below. It was not copied from the vendored
runtime stored in the Omarchy UI source checkout; that file is not a build input
for this plugin.

- Release: [`runtime-v0.1.0`](https://github.com/AdamMusa/omarchy-ui/releases/tag/runtime-v0.1.0)
- Release asset: [`omarchy-ui-runtime`](https://github.com/AdamMusa/omarchy-ui/releases/download/runtime-v0.1.0/omarchy-ui-runtime)
- Omarchy UI source revision: [`9e102e14cdc90e1b077ec37a0646d43f104eb9e3`](https://github.com/AdamMusa/omarchy-ui/tree/9e102e14cdc90e1b077ec37a0646d43f104eb9e3)
- Remote build: [GitHub Actions run `32762173432`](https://github.com/AdamMusa/omarchy-ui/actions/runs/32762173432)
- Signed provenance: [GitHub artifact attestation `42660584`](https://github.com/AdamMusa/omarchy-ui/attestations/42660584)
- SHA-256: `c5a5aec0078465a14af991e7de90a13fe4294d120032a2519e1979ec8b1d6d8f`
- Size: `1,859,816` bytes
- Target: x86-64 Linux

The release workflow performs two clean builds in separate cache directories
and requires byte-identical output before signing or publishing the artifact.
Its complete build inputs are committed in
[`runtime/inputs.env`](https://github.com/AdamMusa/omarchy-ui/blob/9e102e14cdc90e1b077ec37a0646d43f104eb9e3/runtime/inputs.env):

- Zui: `514bd4a84b5785d5909c2d28664849b1d77c804f`
- mruby: `831da26b9021de0369d17b71b5667e2941a1a32d`
- mruby-json: `f99d9428025469f2400f93c53b185f65f963e507`
- mruby-regexp-pcre: `71bd16ba59239f04aefb73bb6d46d5b581f27b1b`
- mruby-env: `056ae324451ef16a50c7887e117f0ea30921b71b`
- mruby-process: `95da206a5764f4e80146979b8e35bd7a9afd6850`

Reviewers can independently verify the committed executable:

```bash
sha256sum --check omarchy-ui-runtime.sha256
gh attestation verify omarchy-ui-runtime --repo AdamMusa/omarchy-ui

tmpdir=$(mktemp -d)
gh release download runtime-v0.1.0 \
  --repo AdamMusa/omarchy-ui \
  --pattern omarchy-ui-runtime \
  --dir "$tmpdir"
cmp omarchy-ui-runtime "$tmpdir/omarchy-ui-runtime"
```

The same checks run remotely on every phone-plugin push and pull request in
[`verify-runtime.yml`](.github/workflows/verify-runtime.yml).
