import Foundation

enum FallbackMode: String {
    case disabled
    case automatic
    case specific
}

final class AppPreferences {
    private enum Key {
        static let showsDeviceName = "showsDeviceName"
        static let notificationsEnabled = "notificationsEnabled"
        static let globalHotKeyEnabled = "globalHotKeyEnabled"
        static let fallbackMode = "fallbackMode"
        static let fallbackDeviceUID = "fallbackDeviceUID"
        static let fallbackDeviceName = "fallbackDeviceName"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.showsDeviceName: false,
            Key.notificationsEnabled: false,
            Key.globalHotKeyEnabled: true,
            Key.fallbackMode: FallbackMode.automatic.rawValue
        ])
    }

    var showsDeviceName: Bool {
        get { defaults.bool(forKey: Key.showsDeviceName) }
        set { defaults.set(newValue, forKey: Key.showsDeviceName) }
    }

    var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    var globalHotKeyEnabled: Bool {
        get { defaults.bool(forKey: Key.globalHotKeyEnabled) }
        set { defaults.set(newValue, forKey: Key.globalHotKeyEnabled) }
    }

    var fallbackMode: FallbackMode {
        get {
            guard let rawValue = defaults.string(forKey: Key.fallbackMode),
                  let mode = FallbackMode(rawValue: rawValue) else {
                return .automatic
            }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.fallbackMode) }
    }

    var fallbackDeviceUID: String? {
        get { defaults.string(forKey: Key.fallbackDeviceUID) }
        set { defaults.set(newValue, forKey: Key.fallbackDeviceUID) }
    }

    var fallbackDeviceName: String? {
        get { defaults.string(forKey: Key.fallbackDeviceName) }
        set { defaults.set(newValue, forKey: Key.fallbackDeviceName) }
    }

    func useAutomaticFallback() {
        fallbackMode = .automatic
        fallbackDeviceUID = nil
        fallbackDeviceName = nil
    }

    func disableFallback() {
        fallbackMode = .disabled
        fallbackDeviceUID = nil
        fallbackDeviceName = nil
    }

    func useFallbackDevice(_ device: AudioInputDevice) {
        fallbackMode = .specific
        fallbackDeviceUID = device.uid
        fallbackDeviceName = device.name
    }
}

enum FallbackResolver {
    static func resolve(
        mode: FallbackMode,
        preferredUID: String?,
        from devices: [AudioInputDevice]
    ) -> AudioInputDevice? {
        guard mode != .disabled, !devices.isEmpty else { return nil }

        if mode == .specific,
           let preferredUID,
           let preferred = devices.first(where: { $0.uid == preferredUID }) {
            return preferred
        }

        return devices.min { first, second in
            let firstPriority = priority(for: first.kind)
            let secondPriority = priority(for: second.kind)
            if firstPriority == secondPriority {
                return first.name.localizedStandardCompare(second.name) == .orderedAscending
            }
            return firstPriority < secondPriority
        }
    }

    private static func priority(for kind: AudioInputDeviceKind) -> Int {
        switch kind {
        case .builtIn: return 0
        case .usb: return 1
        case .bluetooth: return 2
        case .phone: return 3
        case .wireless: return 4
        case .aggregate: return 5
        case .virtual: return 6
        case .other: return 7
        }
    }
}
