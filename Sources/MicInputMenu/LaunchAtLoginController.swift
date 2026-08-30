import Foundation
import ServiceManagement

enum LaunchAtLoginState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LaunchAtLoginError: LocalizedError {
    case launchctlFailed(String)

    var errorDescription: String? {
        switch self {
        case let .launchctlFailed(message):
            return message.isEmpty ? "Unable to update the login item." : message
        }
    }
}

final class LaunchAtLoginController {
    private let fileManager = FileManager.default
    private let fallbackLabel = "io.github.yukaroman.MicInputMenu.login"
    private let legacyFallbackLabel = "local.codex.MicInputMenu.login"

    init() {
        try? migrateLegacyFallbackIfNeeded()
    }

    var state: LaunchAtLoginState {
        if fallbackItemExists || legacyFallbackItemExists {
            return .enabled
        }

        switch SMAppService.mainApp.status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return canUseFallback ? .disabled : .unavailable
        @unknown default:
            return .unavailable
        }
    }

    func toggle() throws {
        if fallbackItemExists || legacyFallbackItemExists {
            try disableFallback()
            return
        }

        switch SMAppService.mainApp.status {
        case .notRegistered:
            try SMAppService.mainApp.register()
        case .enabled:
            try SMAppService.mainApp.unregister()
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
        case .notFound:
            try enableFallback()
        @unknown default:
            throw CocoaError(.featureUnsupported)
        }
    }

    private var launchAgentsDirectory: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }

    private var fallbackPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(fallbackLabel).plist")
    }

    private var legacyFallbackPlistURL: URL {
        launchAgentsDirectory.appendingPathComponent("\(legacyFallbackLabel).plist")
    }

    private var fallbackItemExists: Bool {
        fileManager.fileExists(atPath: fallbackPlistURL.path)
    }

    private var legacyFallbackItemExists: Bool {
        fileManager.fileExists(atPath: legacyFallbackPlistURL.path)
    }

    private var canUseFallback: Bool {
        let appURL = Bundle.main.bundleURL
        return appURL.pathExtension == "app"
            && fileManager.isExecutableFile(
                atPath: appURL.appendingPathComponent("Contents/MacOS/MicInputMenu").path
            )
    }

    private func enableFallback() throws {
        guard canUseFallback else { throw CocoaError(.featureUnsupported) }

        try fileManager.createDirectory(
            at: launchAgentsDirectory,
            withIntermediateDirectories: true
        )

        let propertyList: [String: Any] = [
            "Label": fallbackLabel,
            "AssociatedBundleIdentifiers": [
                Bundle.main.bundleIdentifier ?? "io.github.yukaroman.MicInputMenu"
            ],
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                Bundle.main.bundleURL.path
            ],
            "RunAtLoad": true,
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: propertyList,
            format: .xml,
            options: 0
        )
        try data.write(to: fallbackPlistURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o644],
            ofItemAtPath: fallbackPlistURL.path
        )

        if !fallbackItemIsLoaded {
            do {
                try runLaunchctl([
                    "bootstrap",
                    launchDomain,
                    fallbackPlistURL.path
                ])
            } catch {
                try? fileManager.removeItem(at: fallbackPlistURL)
                throw error
            }
        }
    }

    private func disableFallback() throws {
        var firstError: Error?
        for item in [
            (fallbackLabel, fallbackPlistURL),
            (legacyFallbackLabel, legacyFallbackPlistURL)
        ] {
            do {
                try disableFallbackItem(label: item.0, plistURL: item.1)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    private func migrateLegacyFallbackIfNeeded() throws {
        guard legacyFallbackItemExists, !fallbackItemExists, canUseFallback else {
            return
        }

        try enableFallback()
        try disableFallbackItem(
            label: legacyFallbackLabel,
            plistURL: legacyFallbackPlistURL
        )
    }

    private func disableFallbackItem(label: String, plistURL: URL) throws {
        if fallbackItemIsLoaded(label: label) {
            try runLaunchctl([
                "bootout",
                launchDomain,
                plistURL.path
            ])
        }
        if fileManager.fileExists(atPath: plistURL.path) {
            try fileManager.removeItem(at: plistURL)
        }
    }

    private var launchDomain: String {
        "gui/\(getuid())"
    }

    private var fallbackItemIsLoaded: Bool {
        fallbackItemIsLoaded(label: fallbackLabel)
    }

    private func fallbackItemIsLoaded(label: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["print", "\(launchDomain)/\(label)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func runLaunchctl(_ arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw LaunchAtLoginError.launchctlFailed(message)
        }
    }
}
