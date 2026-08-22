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

## Android quick start

Android 11 or newer and the Omarchy computer must be on the same Wi-Fi network.

1. On Android, enable **Settings → System → Developer options → Wireless debugging**.
2. Tap **Pair device with pairing code**. Keep this popup open.
3. In Omarchy Phone under **Pair Android**, enter the popup's complete pairing address
   (`IP:port`) and its six-digit code, then click **Pair** before the code expires.
4. Omarchy Phone discovers Android's connection service and connects in the background.
5. When the phone appears, click **Open Phone** to start scrcpy.

Generate a new pairing popup if pairing reports that the code expired. Pairing establishes trust
once; Omarchy Phone handles the separate connection port automatically.

## iPhone quick start

For AirPlay mirroring, connect the iPhone and Omarchy computer to the same trusted network:

1. Click **Start AirPlay** in Omarchy Phone.
2. Note the four-digit PIN displayed in the panel and desktop notification.
3. On iPhone, open Control Center, tap **Screen Mirroring**, and select **Omarchy**.
4. Enter the PIN on the iPhone when prompted.
5. Click **Stop AirPlay** when finished.

For USB discovery, connect and unlock the iPhone, accept **Trust This Computer**, and use the
**Trust** action in Omarchy Phone if it appears. iOS permits mirroring but not remote touch or
keyboard control.

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

Application behavior lives in `main.rb` and `lib/phone_backend.rb`. QML bridge files and
`omarchy-ui-runtime` are generated distribution artifacts owned by Omarchy UI; do not edit them
inside this project.

Build and validate the complete plugin before publishing:

```bash
omarchy_ui bundle
omarchy plugin validate dist/omarchy-phone-plugin
```

## License

MIT.
