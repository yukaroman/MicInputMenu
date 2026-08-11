# Privacy

Mic Input Menu uses Core Audio metadata to list input devices, read the current
default input, and change device, volume, or mute settings at the user's
request.

The app:

- does not record or capture audio;
- does not request microphone permission;
- does not send analytics or telemetry;
- does not include advertising or tracking SDKs;
- stores preferences locally with `UserDefaults`.

Optional switch notifications use macOS User Notifications. Launch-at-login
uses `SMAppService` when available, with a per-user LaunchAgent fallback for
locally signed builds.
