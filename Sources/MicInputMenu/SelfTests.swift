import CoreAudio
import Foundation

enum SelfTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .failed(message): return message
        }
    }
}

enum SelfTests {
    static func run() throws {
        try testSpecificFallback()
        try testMissingFallbackUsesAutomaticPriority()
        try testDisabledFallback()
        try testPreferencePersistence()
        try testStatusNameLength()
        try testTransportClassification()
        try testStatusSymbols()
    }

    private static func testSpecificFallback() throws {
        let devices = [
            makeDevice(id: 1, uid: "built-in", name: "Built-in", kind: .builtIn),
            makeDevice(id: 2, uid: "usb", name: "USB Mic", kind: .usb)
        ]
        let result = FallbackResolver.resolve(
            mode: .specific,
            preferredUID: "usb",
            from: devices
        )
        try expect(result?.uid == "usb", "Specific fallback selection failed")
    }

    private static func testMissingFallbackUsesAutomaticPriority() throws {
        let devices = [
            makeDevice(id: 1, uid: "bluetooth", name: "Headset", kind: .bluetooth),
            makeDevice(id: 2, uid: "built-in", name: "Built-in", kind: .builtIn)
        ]
        let result = FallbackResolver.resolve(
            mode: .specific,
            preferredUID: "missing",
            from: devices
        )
        try expect(result?.uid == "built-in", "Automatic fallback priority failed")
    }

    private static func testDisabledFallback() throws {
        let result = FallbackResolver.resolve(
            mode: .disabled,
            preferredUID: nil,
            from: [makeDevice(id: 1, uid: "built-in", name: "Built-in", kind: .builtIn)]
        )
        try expect(result == nil, "Disabled fallback returned a device")
    }

    private static func testPreferencePersistence() throws {
        let suiteName = "MicInputMenuSelfTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw SelfTestError.failed("Unable to create isolated preferences")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AppPreferences(defaults: defaults)
        let device = makeDevice(id: 1, uid: "usb", name: "Desk Mic", kind: .usb)
        preferences.useFallbackDevice(device)

        try expect(preferences.fallbackMode == .specific, "Fallback mode was not persisted")
        try expect(preferences.fallbackDeviceUID == "usb", "Fallback UID was not persisted")
        try expect(preferences.fallbackDeviceName == "Desk Mic", "Fallback name was not persisted")
    }

    private static func testStatusNameLength() throws {
        let result = MenuBarController.shortenedStatusName(
            "A very long microphone device name",
            limit: 12
        )
        try expect(result.count == 12, "Status name length is not bounded")
        try expect(result.hasSuffix("…"), "Truncated status name has no ellipsis")
    }

    private static func testTransportClassification() throws {
        try expect(
            AudioInputDeviceKind.classify(
                transportType: kAudioDeviceTransportTypeBuiltIn
            ) == .builtIn,
            "Built-in transport classification failed"
        )
        try expect(
            AudioInputDeviceKind.classify(
                transportType: kAudioDeviceTransportTypeBluetooth
            ) == .bluetooth,
            "Bluetooth transport classification failed"
        )
        try expect(
            AudioInputDeviceKind.classify(
                transportType: kAudioDeviceTransportTypeUSB
            ) == .usb,
            "USB transport classification failed"
        )
    }

    private static func testStatusSymbols() throws {
        try expect(
            AudioInputDeviceKind.builtIn.statusSymbolName(isMuted: false) == "mic.fill",
            "Built-in status symbol is incorrect"
        )
        try expect(
            AudioInputDeviceKind.usb.statusSymbolName(isMuted: false) == "cable.connector",
            "USB status symbol is incorrect"
        )
        try expect(
            AudioInputDeviceKind.phone.statusSymbolName(isMuted: false) == "iphone",
            "Phone status symbol is incorrect"
        )
        try expect(
            AudioInputDeviceKind.bluetooth.statusSymbolName(isMuted: true) == "mic.slash.fill",
            "Muted status symbol is incorrect"
        )
    }

    private static func makeDevice(
        id: AudioDeviceID,
        uid: String,
        name: String,
        kind: AudioInputDeviceKind
    ) -> AudioInputDevice {
        AudioInputDevice(
            id: id,
            uid: uid,
            name: name,
            transportType: kAudioDeviceTransportTypeUnknown,
            kind: kind
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw SelfTestError.failed(message) }
    }
}
