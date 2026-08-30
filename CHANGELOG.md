# Changelog

## 2.1.1

- Distinguish Bluetooth speakers, headphones, headsets, microphones, car
  audio, AirPods, and unknown devices using the Bluetooth device class.
- Show a speaker icon for Bluetooth loudspeakers such as Marshall WILLEN
  instead of treating every Bluetooth input as AirPods.
- Add the required macOS Bluetooth usage description and document that the
  permission is used only for local icon classification.

## 2.1.0

- Add device-aware and mute-aware menu bar icons.
- Observe volume, mute, name, availability, and input-channel changes live.
- Coalesce rapid Core Audio events and defer menu rebuilding during interaction.
- Replace blocking alerts with temporary in-menu error messages.
- Keep device switching, fallback selection, notifications, global shortcut,
  launch at login, and Chinese/English UI support.
