# Privacy

Mic Input Menu uses Core Audio metadata to list input devices, read the current
default input, and change device, volume, or mute settings at the user's
request. For Bluetooth inputs, it reads the paired device's local Bluetooth
class and name solely to choose an appropriate icon.

The app:

- does not record or capture audio;
- does not request microphone permission;
- does not send analytics or telemetry;
- does not include advertising or tracking SDKs;
- stores preferences locally with `UserDefaults`.

Optional switch notifications use macOS User Notifications. Launch-at-login
uses `SMAppService` when available, with a per-user LaunchAgent fallback for
locally signed builds.

macOS may request Bluetooth permission when a Bluetooth input device is
available. The permission is used only to read that paired device's local name
and device class; the app does not scan for devices, initiate connections, or
transmit Bluetooth data.
