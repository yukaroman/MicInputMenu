# Mic Input Menu

[![CI](https://github.com/yukaroman/MicInputMenu/actions/workflows/ci.yml/badge.svg)](https://github.com/yukaroman/MicInputMenu/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/yukaroman/MicInputMenu)](https://github.com/yukaroman/MicInputMenu/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A lightweight macOS menu bar utility for viewing and changing the system's
default audio input device. The interface supports English and Chinese.

一个轻量的 macOS 菜单栏工具，用来查看、切换和控制系统麦克风输入来源。

## Features

- Persistent, device-aware menu bar icon with an optional device name
- Muted-state icon that updates when another app or macOS changes input mute
- One-click switching between built-in, USB, Bluetooth, iPhone, wireless,
  aggregate, and virtual input devices
- Input volume and mute controls when supported by the selected device
- Live Core Audio updates for volume, mute, device name, availability, data
  source, and input-channel changes
- Configurable fallback when the current input disconnects
- Optional device-switch notifications
- Global Control-Option-M shortcut for cycling input devices
- Launch at login with `SMAppService` and a per-user LaunchAgent fallback
- Non-blocking error messages inside the menu

## Privacy

Mic Input Menu reads and controls Core Audio properties only. It does not
record audio, request microphone access, collect analytics, or make network
requests. See [PRIVACY.md](PRIVACY.md) for details.

## Install

Download the latest ZIP from [GitHub Releases](https://github.com/yukaroman/MicInputMenu/releases),
extract it, and move `MicInputMenu.app` to `/Applications`.

Release assets are universal binaries for Apple Silicon and Intel Macs. When a
release is built without the optional Apple Developer secrets, its filename
contains `unsigned`. macOS may require Control-clicking the app and choosing
**Open** the first time. A Developer ID-signed and notarized release opens
normally.

## Requirements

- macOS 13 Ventura or later
- Apple Silicon or Intel Mac

## Build and test

```sh
swift build
swift run MicInputMenu --self-test
```

Create a universal application and ZIP archive:

```sh
chmod +x Scripts/package_app.sh
Scripts/package_app.sh dist
```

Use `MIC_INPUT_NATIVE_ONLY=1` to build only for the current architecture.

## Automated releases

GitHub Actions runs the self-tests and produces an application artifact for
every push. Pushing a tag such as `v2.1.0` builds a universal app and publishes
it to GitHub Releases with a SHA-256 checksum.

The release workflow supports optional Developer ID signing and Apple
notarization through repository secrets. See
[Signing and notarization](#signing-and-notarization).

## Signing and notarization

Local builds use an ad-hoc signature by default. For a local Developer ID build:

```sh
MIC_INPUT_SIGNING_IDENTITY="Developer ID Application: Example (TEAMID)" \
MIC_INPUT_NOTARY_PROFILE="notary-profile" \
Scripts/package_app.sh dist
```

For notarized GitHub releases, configure these repository secrets:

- `MACOS_CERTIFICATE_P12_BASE64`
- `MACOS_CERTIFICATE_PASSWORD`
- `MACOS_SIGNING_IDENTITY`
- `APPLE_API_KEY_P8_BASE64`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

The certificate and API key values must be base64 encoded. Without these
secrets the workflow still publishes an ad-hoc signed build and clearly labels
the asset as unsigned.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Issues and pull requests are welcome.

## License

Mic Input Menu is available under the [MIT License](LICENSE).
