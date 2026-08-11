import AppKit
import Darwin

final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var automationObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        automationObserver = DistributedNotificationCenter.default().addObserver(
            forName: AutomationBridge.enableLaunchAtLoginRequest,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let requestID = notification.userInfo?["requestID"] as? String else { return }
            let result = self?.menuBarController?.enableLaunchAtLoginForAutomation()
                ?? "error|Menu bar controller is unavailable"
            DistributedNotificationCenter.default().postNotificationName(
                AutomationBridge.enableLaunchAtLoginResponse,
                object: nil,
                userInfo: ["requestID": requestID, "result": result],
                deliverImmediately: true
            )
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let automationObserver {
            DistributedNotificationCenter.default().removeObserver(automationObserver)
        }
    }
}

private enum AutomationBridge {
    static let enableLaunchAtLoginRequest = Notification.Name(
        "io.github.yukaroman.MicInputMenu.enableLaunchAtLogin.request"
    )
    static let enableLaunchAtLoginResponse = Notification.Name(
        "io.github.yukaroman.MicInputMenu.enableLaunchAtLogin.response"
    )
}

private func runDiagnostics() -> Int32 {
    let service = CoreAudioInputService()

    do {
        let devices = try service.inputDevices()
        let defaultID = try service.defaultInputDeviceID()
        let defaultName = devices.first(where: { $0.id == defaultID })?.name ?? "none"

        print("Default input: \(defaultName)")
        print("Input devices: \(devices.count)")
        for device in devices {
            let marker = device.id == defaultID ? "*" : "-"
            let controls = service.inputControlState(deviceID: device.id)
            let volume = controls.volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "n/a"
            let mute = controls.isMuted.map { $0 ? "on" : "off" } ?? "n/a"
            print(
                "\(marker) \(device.name) "
                    + "[kind=\(device.kind.rawValue), volume=\(volume), mute=\(mute), uid=\(device.uid)]"
            )
        }
        return 0
    } catch {
        fputs("Diagnostics failed: \(error.localizedDescription)\n", stderr)
        return 1
    }
}

private func requestLaunchAtLogin() -> Int32 {
    let center = DistributedNotificationCenter.default()
    let requestID = UUID().uuidString
    var result: String?
    let observer = center.addObserver(
        forName: AutomationBridge.enableLaunchAtLoginResponse,
        object: nil,
        queue: .main
    ) { notification in
        guard notification.userInfo?["requestID"] as? String == requestID else { return }
        result = notification.userInfo?["result"] as? String
    }
    defer { center.removeObserver(observer) }

    center.postNotificationName(
        AutomationBridge.enableLaunchAtLoginRequest,
        object: nil,
        userInfo: ["requestID": requestID],
        deliverImmediately: true
    )

    let deadline = Date().addingTimeInterval(5)
    while result == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    switch result {
    case "enabled":
        print("Launch at login: enabled")
        return 0
    case "requiresApproval":
        print("Launch at login: requires approval in System Settings")
        return 2
    case "disabled":
        fputs("Launch at login remained disabled\n", stderr)
        return 1
    case "unavailable":
        fputs("Launch at login is unavailable\n", stderr)
        return 1
    case let value? where value.hasPrefix("error|"):
        fputs("Unable to enable launch at login: \(value.dropFirst(6))\n", stderr)
        return 1
    default:
        fputs("The running app did not respond to the launch-at-login request\n", stderr)
        return 1
    }
}

if CommandLine.arguments.contains("--diagnose") {
    exit(runDiagnostics())
}

if CommandLine.arguments.contains("--self-test") {
    do {
        try SelfTests.run()
        print("Self-tests passed")
        exit(0)
    } catch {
        fputs("Self-tests failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--enable-launch-at-login") {
    exit(requestLaunchAtLogin())
}

let application = NSApplication.shared
let applicationDelegate = ApplicationDelegate()
application.delegate = applicationDelegate
application.setActivationPolicy(.accessory)
application.run()
