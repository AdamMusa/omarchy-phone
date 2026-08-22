# Omarchy Phone

The first application built with [Omarchy UI](https://github.com/AdamMusa/omarchy-ui).
It provides Android discovery, wireless pairing, scrcpy control, iPhone discovery, and AirPlay
mirroring from an Omarchy bar widget and panel.

## Install

```bash
omarchy plugin add https://github.com/AdamMusa/omarchy-phone.git --enable
```

Review third-party plugin code before enabling it. Omarchy plugins run with your user account.

The repository is self-contained: it includes the QML bridge and prebuilt x86-64 mruby runtime,
so Ruby, mruby, and the `omarchy-ui` gem are not required on the destination computer.

## Optional system tools

- `adb` for Android discovery, pairing, and network connections.
- `scrcpy` for Android screen mirroring and keyboard/mouse control.
- `libimobiledevice` for trusted USB iPhone discovery and pairing.
- `uxplay` for iPhone AirPlay screen/audio mirroring.

Android supports remote control through scrcpy. AirPlay mirrors an iPhone but cannot send touch
or keyboard input back to iOS.

## AirPlay and firewall

UxPlay uses TCP and UDP ports `7100-7102`; mDNS discovery uses UDP `5353`. If UFW is enabled,
allow those ports from the local network. Starting AirPlay displays a four-digit PIN in the
panel and desktop notification. Active AirPlay sessions appear automatically in the device list.

## Update or remove

```bash
omarchy plugin update izeesoft.omarchy-phone
omarchy plugin remove izeesoft.omarchy-phone
```

## Development

Application behavior lives in `main.rb` and `lib/phone_backend.rb`. The remaining QML files and
`omarchy-ui-runtime` are generated distribution artifacts from Omarchy UI.

Validate before publishing:

```bash
omarchy plugin validate .
```

## License

MIT.
