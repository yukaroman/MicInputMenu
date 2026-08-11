import Carbon
import Foundation

private let micInputHotKeySignature: OSType = 0x4D49434D // MICM
private let micInputHotKeyID: UInt32 = 1

private func micInputHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData else { return OSStatus(eventNotHandledErr) }
    let controller = Unmanaged<GlobalHotKeyController>
        .fromOpaque(userData)
        .takeUnretainedValue()
    controller.performAction()
    return noErr
}

enum GlobalHotKeyError: LocalizedError {
    case eventHandler(OSStatus)
    case registration(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .eventHandler(status):
            return "Unable to install the keyboard event handler (\(status))."
        case let .registration(status):
            return "The shortcut may already be used by another app (\(status))."
        }
    }
}

final class GlobalHotKeyController {
    static let displayShortcut = "⌃⌥M"

    private var eventHandlerReference: EventHandlerRef?
    private var hotKeyReference: EventHotKeyRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) throws {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            micInputHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard status == noErr else {
            throw GlobalHotKeyError.eventHandler(status)
        }
    }

    deinit {
        setDisabled()
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
        }
    }

    var isEnabled: Bool {
        hotKeyReference != nil
    }

    func setEnabled() throws {
        guard hotKeyReference == nil else { return }

        let identifier = EventHotKeyID(
            signature: micInputHotKeySignature,
            id: micInputHotKeyID
        )
        let modifiers = UInt32(controlKey | optionKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard status == noErr else {
            hotKeyReference = nil
            throw GlobalHotKeyError.registration(status)
        }
    }

    func setDisabled() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
    }

    fileprivate func performAction() {
        action()
    }
}
