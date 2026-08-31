# Compiled QML provenance

Omarchy UI generated this package's native Qt module from the tree-shaken Zui and
Omarchy host QML graph. Generated QML source contents were discarded after AOT compilation.

- Format: `qt-aot-qml-module` version 1
- Qt: `6.11.2`
- Module: `OmarchyUI.Bundles.B68231fff638e32d55470`
- Source fingerprint: `68231fff638e32d5547000c555087afecd2d68a8f6e0d3b7b0ecec4eefdcad9e`

## Artifacts

- `OmarchyUI/Bundles/B68231fff638e32d55470/libomarchy_ui_bundle_b68231fff638e32d55470.so` — `e298c4bc0821243485e140e1c74c7c279c728833623dd4fc42870c19dc0132a1`
- `OmarchyUI/Bundles/B68231fff638e32d55470/libomarchy_ui_bundle_b68231fff638e32d55470plugin.so` — `c2aece9feb3e89d53b2ba20b7298c372a6d968c0d2c6c35dcf10e1a7c65ae922`

Verify the packaged libraries from the plugin directory:

```bash
sha256sum --check omarchy-ui-qml-bundle.sha256
```

`App.qml`, `Service.qml`, `Panel.qml`, and `BarWidget.qml` are the minimal loader shims
required by Omarchy's file-based entry-point contract. Application UI lives in the compiled
module recorded by `omarchy-ui-qml-bundle.json`.
