# Omarchy UI runtime provenance

The bundled executable is byte-for-byte the artifact published by the independently
attested `runtime-v0.1.4` release.

- Omarchy UI release: https://github.com/AdamMusa/omarchy-ui/releases/tag/runtime-v0.1.4
- Omarchy UI revision: `acc8938cda6298e946a2f63aaf00c67b1d402787`
- Zui revision: `74b48f047d5811b53667e5cc0fb7f0bb63548764` (`0.0.10`)
- mruby revision: `831da26b9021de0369d17b71b5667e2941a1a32d` (`4.0.0`)
- Remote build: https://github.com/AdamMusa/omarchy-ui/actions/runs/33296176108
- Signed attestation: https://github.com/AdamMusa/omarchy-ui/attestations/43928397
- Target: x86-64 Linux
- Size: `1,880,680` bytes
- SHA-256: `721e023e7868a0f2a85c9b63250042a97d981943d9e60b8d98cf7c781a87de6e`

The workflow checks out every external input at a full commit digest, performs two clean
builds, requires byte-identical executables, and signs the resulting SHA through GitHub's
artifact attestation service. Machine-readable provenance is included in
`runtime-provenance.json`; independent verification instructions are in
the [runtime build documentation](https://github.com/AdamMusa/omarchy-ui/blob/main/docs/runtime-build.md).
