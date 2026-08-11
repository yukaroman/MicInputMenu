# Contributing

Issues and pull requests are welcome.

## Requirements

- macOS 13 or later
- Swift 6 toolchain
- Xcode Command Line Tools

## Build and verify

```sh
swift build
swift run MicInputMenu --self-test
MIC_INPUT_NATIVE_ONLY=1 Scripts/package_app.sh dist
dist/MicInputMenu.app/Contents/MacOS/MicInputMenu --diagnose
```

Please keep the app lightweight, preserve the no-recording privacy model, and
add a self-test for changes to pure application logic.
