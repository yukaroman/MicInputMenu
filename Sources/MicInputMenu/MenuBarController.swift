import AppKit
import CoreAudio

private enum InputSwitchReason {
    case manual
    case shortcut
    case fallback
    case external
}

final class MenuBarController: NSObject, NSMenuDelegate {
    private static let transientErrorItemIdentifier = NSUserInterfaceItemIdentifier(
        "MicInputMenu.TransientError"
    )

    private let audioService: CoreAudioInputService
    private let preferences: AppPreferences
    private let notificationController: NotificationController
    private let launchAtLoginController: LaunchAtLoginController
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    private var hotKeyController: GlobalHotKeyController?
    private var hotKeyError: Error?
    private var refreshWorkItem: DispatchWorkItem?
    private var errorClearWorkItem: DispatchWorkItem?
    private var isMenuOpen = false
    private var refreshAfterMenuCloses = false
    private var transientErrorMessage: String?
    private var currentDevices: [AudioInputDevice] = []
    private var currentDefaultID: AudioDeviceID?
    private var lastKnownDefaultUID: String?
    private var statusDeviceName = L10n.noInput
    private var statusDeviceKind: AudioInputDeviceKind?
    private var statusIsMuted: Bool?
    private var statusReadError: String?
    private var hasInitialSnapshot = false
    private var pendingSwitchReason: InputSwitchReason?

    init(
        audioService: CoreAudioInputService = CoreAudioInputService(),
        preferences: AppPreferences = AppPreferences(),
        notificationController: NotificationController = NotificationController(),
        launchAtLoginController: LaunchAtLoginController = LaunchAtLoginController()
    ) {
        self.audioService = audioService
        self.preferences = preferences
        self.notificationController = notificationController
        self.launchAtLoginController = launchAtLoginController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        configureStatusItem()
        menu.delegate = self
        statusItem.menu = menu
        configureGlobalHotKey()
        refreshStateAndMenu()

        audioService.startObservingChanges { [weak self] in
            self?.scheduleRefresh()
        }
    }

    deinit {
        refreshWorkItem?.cancel()
        errorClearWorkItem?.cancel()
        audioService.stopObserving()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        refreshStateAndMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        guard refreshAfterMenuCloses else { return }
        refreshAfterMenuCloses = false
        scheduleRefresh()
    }

    func enableLaunchAtLoginForAutomation() -> String {
        do {
            if launchAtLoginController.state == .disabled {
                try launchAtLoginController.toggle()
            }
            if launchAtLoginController.state == .requiresApproval {
                try launchAtLoginController.toggle()
            }
            refreshStateAndMenu()

            switch launchAtLoginController.state {
            case .enabled: return "enabled"
            case .requiresApproval: return "requiresApproval"
            case .disabled: return "disabled"
            case .unavailable: return "unavailable"
            }
        } catch {
            return "error|\(error.localizedDescription)"
        }
    }

    @objc private func selectInputDevice(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }

        do {
            pendingSwitchReason = .manual
            try audioService.setDefaultInputDevice(AudioDeviceID(number.uint32Value))
            refreshStateAndMenu()
        } catch {
            pendingSwitchReason = nil
            presentError(title: L10n.switchFailed, error: error)
        }
    }

    @objc private func toggleMute(_ sender: NSMenuItem) {
        guard let number = sender.representedObject as? NSNumber else { return }
        let deviceID = AudioDeviceID(number.uint32Value)
        let state = audioService.inputControlState(deviceID: deviceID)
        guard let isMuted = state.isMuted else { return }

        do {
            try audioService.setInputMuted(!isMuted, deviceID: deviceID)
            refreshStateAndMenu()
        } catch {
            presentError(title: L10n.muteFailed, error: error)
        }
    }

    @objc private func useAutomaticFallback(_ sender: NSMenuItem) {
        preferences.useAutomaticFallback()
        refreshStateAndMenu()
    }

    @objc private func disableFallback(_ sender: NSMenuItem) {
        preferences.disableFallback()
        refreshStateAndMenu()
    }

    @objc private func selectFallbackDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String,
              let device = currentDevices.first(where: { $0.uid == uid }) else {
            return
        }
        preferences.useFallbackDevice(device)
        refreshStateAndMenu()
    }

    @objc private func toggleDeviceName(_ sender: NSMenuItem) {
        preferences.showsDeviceName.toggle()
        refreshStateAndMenu()
    }

    @objc private func toggleNotifications(_ sender: NSMenuItem) {
        if preferences.notificationsEnabled {
            preferences.notificationsEnabled = false
            refreshStateAndMenu()
            return
        }

        notificationController.requestAuthorization { [weak self] granted, error in
            guard let self else { return }
            if granted {
                preferences.notificationsEnabled = true
            } else {
                let permissionError = error ?? NSError(
                    domain: "MicInputMenu.Notifications",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.notificationDenied]
                )
                presentError(title: L10n.notificationDenied, error: permissionError)
            }
            refreshStateAndMenu()
        }
    }

    @objc private func toggleGlobalHotKey(_ sender: NSMenuItem) {
        do {
            if hotKeyController == nil {
                hotKeyController = try makeHotKeyController()
            }
            guard let hotKeyController else { return }

            if hotKeyController.isEnabled {
                hotKeyController.setDisabled()
                preferences.globalHotKeyEnabled = false
            } else {
                try hotKeyController.setEnabled()
                preferences.globalHotKeyEnabled = true
            }
            hotKeyError = nil
            refreshStateAndMenu()
        } catch {
            hotKeyError = error
            preferences.globalHotKeyEnabled = false
            presentError(title: L10n.featureFailed, error: error)
        }
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            try launchAtLoginController.toggle()
            refreshStateAndMenu()
        } catch {
            presentError(title: L10n.featureFailed, error: error)
        }
    }

    @objc private func refresh(_ sender: Any?) {
        refreshStateAndMenu()
    }

    @objc private func openSoundSettings(_ sender: Any?) {
        let modernURL = URL(
            string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input"
        )!
        if !NSWorkspace.shared.open(modernURL),
           let fallbackURL = URL(
               string: "x-apple.systempreferences:com.apple.preference.sound?input"
           ) {
            NSWorkspace.shared.open(fallbackURL)
        }
    }

    @objc private func quit(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        button.image = statusImage(symbol: "mic.fill", accessibilityDescription: L10n.appName)
        button.imagePosition = .imageOnly
        button.toolTip = L10n.appName
        statusItem.isVisible = true
    }

    private func configureGlobalHotKey() {
        do {
            let controller = try makeHotKeyController()
            hotKeyController = controller
            if preferences.globalHotKeyEnabled {
                try controller.setEnabled()
            }
        } catch {
            hotKeyError = error
            preferences.globalHotKeyEnabled = false
        }
    }

    private func makeHotKeyController() throws -> GlobalHotKeyController {
        try GlobalHotKeyController { [weak self] in
            self?.cycleInputDevice()
        }
    }

    private func cycleInputDevice() {
        do {
            let devices = try audioService.inputDevices()
            guard !devices.isEmpty else { return }
            let defaultID = try audioService.defaultInputDeviceID()
            let nextDevice: AudioInputDevice

            if let currentIndex = devices.firstIndex(where: { $0.id == defaultID }) {
                nextDevice = devices[(currentIndex + 1) % devices.count]
            } else {
                nextDevice = devices[0]
            }

            pendingSwitchReason = .shortcut
            try audioService.setDefaultInputDevice(nextDevice.id)
            refreshStateAndMenu()
        } catch {
            pendingSwitchReason = nil
            presentError(title: L10n.switchFailed, error: error)
        }
    }

    private func scheduleRefresh() {
        if isMenuOpen {
            refreshAfterMenuCloses = true
            return
        }
        guard refreshWorkItem == nil else { return }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            refreshWorkItem = nil
            if isMenuOpen {
                refreshAfterMenuCloses = true
            } else {
                refreshStateAndMenu()
            }
        }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: workItem)
    }

    private func refreshStateAndMenu() {
        do {
            let devices = try audioService.inputDevices()
            var defaultID = try audioService.defaultInputDeviceID()
            var switchReason = pendingSwitchReason

            if hasInitialSnapshot,
               let previousUID = lastKnownDefaultUID,
               !devices.contains(where: { $0.uid == previousUID }),
               let fallback = FallbackResolver.resolve(
                   mode: preferences.fallbackMode,
                   preferredUID: preferences.fallbackDeviceUID,
                   from: devices
               ) {
                if fallback.id != defaultID {
                    try audioService.setDefaultInputDevice(fallback.id)
                    defaultID = fallback.id
                }
                switchReason = .fallback
            }

            let currentDevice = devices.first(where: { $0.id == defaultID })
            if hasInitialSnapshot,
               currentDevice?.uid != lastKnownDefaultUID,
               let currentDevice,
               preferences.notificationsEnabled {
                notificationController.postDeviceSwitch(
                    to: currentDevice.name,
                    automatic: switchReason == .fallback
                )
            }

            currentDevices = devices
            currentDefaultID = defaultID
            lastKnownDefaultUID = currentDevice?.uid
            hasInitialSnapshot = true
            pendingSwitchReason = nil
            rebuildMenu(devices: devices, defaultID: defaultID)
        } catch {
            pendingSwitchReason = nil
            rebuildErrorMenu(error: error)
        }
    }

    private func rebuildMenu(
        devices: [AudioInputDevice],
        defaultID: AudioDeviceID?
    ) {
        menu.removeAllItems()

        let currentDevice = devices.first(where: { $0.id == defaultID })
        let controlState = currentDevice.map {
            audioService.inputControlState(deviceID: $0.id)
        }
        let currentName = currentDevice?.name ?? L10n.noInput
        let currentItem = NSMenuItem(
            title: "\(L10n.currentInput): \(currentName)",
            action: nil,
            keyEquivalent: ""
        )
        currentItem.isEnabled = false
        currentItem.image = menuImage(symbol: "mic.fill")
        menu.addItem(currentItem)
        addTransientErrorItemIfNeeded()
        menu.addItem(.separator())

        if devices.isEmpty {
            let emptyItem = NSMenuItem(title: L10n.noInput, action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for device in devices {
                let item = NSMenuItem(
                    title: device.name,
                    action: #selector(selectInputDevice(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = NSNumber(value: device.id)
                item.state = device.id == defaultID ? .on : .off
                item.image = menuImage(symbol: device.kind.symbolName)
                menu.addItem(item)
            }
        }

        if let currentDevice, let controlState {
            addInputControls(for: currentDevice, controlState: controlState)
        }

        menu.addItem(.separator())
        addFallbackMenu(devices: devices)
        addPreferencesMenu()
        addUtilityItems()
        statusDeviceName = currentName
        statusDeviceKind = currentDevice?.kind
        statusIsMuted = controlState?.isMuted
        statusReadError = nil
        updateStatusItemFromSnapshot()
    }

    private func addInputControls(
        for device: AudioInputDevice,
        controlState: AudioInputControlState
    ) {
        var addedControl = false

        if let volume = controlState.volume, controlState.canSetVolume {
            menu.addItem(.separator())
            let volumeItem = NSMenuItem(title: L10n.inputVolume, action: nil, keyEquivalent: "")
            volumeItem.view = InputVolumeMenuView(volume: volume) { [weak self] value in
                guard let self else { return false }
                do {
                    try audioService.setInputVolume(value, deviceID: device.id)
                    return true
                } catch {
                    presentError(title: L10n.volumeFailed, error: error)
                    return false
                }
            }
            menu.addItem(volumeItem)
            addedControl = true
        }

        if let isMuted = controlState.isMuted, controlState.canSetMute {
            if !addedControl {
                menu.addItem(.separator())
            }
            let muteItem = NSMenuItem(
                title: L10n.muteInput,
                action: #selector(toggleMute(_:)),
                keyEquivalent: ""
            )
            muteItem.target = self
            muteItem.representedObject = NSNumber(value: device.id)
            muteItem.state = isMuted ? .on : .off
            muteItem.image = menuImage(symbol: "mic.slash")
            menu.addItem(muteItem)
        }
    }

    private func addFallbackMenu(devices: [AudioInputDevice]) {
        let parentItem = NSMenuItem(
            title: L10n.fallbackInput,
            action: nil,
            keyEquivalent: ""
        )
        parentItem.image = menuImage(symbol: "arrow.triangle.branch")
        let submenu = NSMenu(title: L10n.fallbackInput)

        let automaticItem = NSMenuItem(
            title: L10n.fallbackAutomatic,
            action: #selector(useAutomaticFallback(_:)),
            keyEquivalent: ""
        )
        automaticItem.target = self
        automaticItem.state = preferences.fallbackMode == .automatic ? .on : .off
        submenu.addItem(automaticItem)
        submenu.addItem(.separator())

        for device in devices {
            let item = NSMenuItem(
                title: device.name,
                action: #selector(selectFallbackDevice(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = device.uid
            item.image = menuImage(symbol: device.kind.symbolName)
            item.state = preferences.fallbackMode == .specific
                && preferences.fallbackDeviceUID == device.uid ? .on : .off
            submenu.addItem(item)
        }

        if preferences.fallbackMode == .specific,
           let selectedUID = preferences.fallbackDeviceUID,
           !devices.contains(where: { $0.uid == selectedUID }) {
            let selectedName = preferences.fallbackDeviceName ?? selectedUID
            let unavailableItem = NSMenuItem(
                title: "\(selectedName) (\(L10n.unavailable))",
                action: nil,
                keyEquivalent: ""
            )
            unavailableItem.isEnabled = false
            unavailableItem.state = .on
            submenu.addItem(unavailableItem)
        }

        submenu.addItem(.separator())
        let disabledItem = NSMenuItem(
            title: L10n.fallbackDisabled,
            action: #selector(disableFallback(_:)),
            keyEquivalent: ""
        )
        disabledItem.target = self
        disabledItem.state = preferences.fallbackMode == .disabled ? .on : .off
        submenu.addItem(disabledItem)

        parentItem.submenu = submenu
        menu.addItem(parentItem)
    }

    private func addPreferencesMenu() {
        let parentItem = NSMenuItem(
            title: L10n.preferences,
            action: nil,
            keyEquivalent: ""
        )
        parentItem.image = menuImage(symbol: "gearshape")
        let submenu = NSMenu(title: L10n.preferences)

        let nameItem = NSMenuItem(
            title: L10n.showDeviceName,
            action: #selector(toggleDeviceName(_:)),
            keyEquivalent: ""
        )
        nameItem.target = self
        nameItem.state = preferences.showsDeviceName ? .on : .off
        submenu.addItem(nameItem)

        let notificationItem = NSMenuItem(
            title: L10n.switchNotifications,
            action: #selector(toggleNotifications(_:)),
            keyEquivalent: ""
        )
        notificationItem.target = self
        notificationItem.state = preferences.notificationsEnabled ? .on : .off
        submenu.addItem(notificationItem)

        let shortcutItem = NSMenuItem(
            title: "\(L10n.globalShortcut): \(GlobalHotKeyController.displayShortcut)",
            action: #selector(toggleGlobalHotKey(_:)),
            keyEquivalent: ""
        )
        shortcutItem.target = self
        shortcutItem.state = hotKeyController?.isEnabled == true ? .on : .off
        shortcutItem.toolTip = hotKeyError?.localizedDescription
        submenu.addItem(shortcutItem)

        submenu.addItem(.separator())

        let launchState = launchAtLoginController.state
        let launchItem = NSMenuItem(
            title: launchState == .requiresApproval ? L10n.launchApproval : L10n.launchAtLogin,
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: ""
        )
        launchItem.target = self
        switch launchState {
        case .enabled:
            launchItem.state = .on
        case .requiresApproval:
            launchItem.state = .mixed
        case .disabled:
            launchItem.state = .off
        case .unavailable:
            launchItem.isEnabled = false
            launchItem.toolTip = L10n.unavailable
        }
        submenu.addItem(launchItem)

        parentItem.submenu = submenu
        menu.addItem(parentItem)
    }

    private func addUtilityItems() {
        menu.addItem(.separator())

        let refreshItem = NSMenuItem(
            title: L10n.refresh,
            action: #selector(refresh(_:)),
            keyEquivalent: "r"
        )
        refreshItem.target = self
        refreshItem.image = menuImage(symbol: "arrow.clockwise")
        menu.addItem(refreshItem)

        let settingsItem = NSMenuItem(
            title: L10n.soundSettings,
            action: #selector(openSoundSettings(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.image = menuImage(symbol: "slider.horizontal.3")
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: L10n.quit,
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func rebuildErrorMenu(error: Error) {
        menu.removeAllItems()

        let errorItem = NSMenuItem(title: L10n.readFailed, action: nil, keyEquivalent: "")
        errorItem.isEnabled = false
        errorItem.toolTip = error.localizedDescription
        errorItem.image = menuImage(symbol: "exclamationmark.triangle")
        menu.addItem(errorItem)

        menu.addItem(.separator())
        addFallbackMenu(devices: currentDevices)
        addPreferencesMenu()
        addUtilityItems()
        statusDeviceName = L10n.noInput
        statusDeviceKind = nil
        statusIsMuted = nil
        statusReadError = error.localizedDescription
        updateStatusItemFromSnapshot()
    }

    private func updateStatusItemFromSnapshot() {
        guard let button = statusItem.button else { return }

        let errorMessage = transientErrorMessage ?? statusReadError
        let isMuted = statusIsMuted == true
        let symbol: String
        let accessibilityDescription: String

        if let errorMessage {
            symbol = "exclamationmark.triangle.fill"
            accessibilityDescription = errorMessage
        } else if let statusDeviceKind {
            symbol = statusDeviceKind.statusSymbolName(isMuted: isMuted)
            accessibilityDescription = isMuted
                ? "\(L10n.currentInput): \(statusDeviceName), \(L10n.muted)"
                : "\(L10n.currentInput): \(statusDeviceName)"
        } else {
            symbol = "mic.slash"
            accessibilityDescription = L10n.noInput
        }

        button.image = statusImage(
            symbol: symbol,
            accessibilityDescription: accessibilityDescription
        )
        if preferences.showsDeviceName {
            statusItem.length = NSStatusItem.variableLength
            button.imagePosition = .imageLeading
            button.title = Self.shortenedStatusName(statusDeviceName)
        } else {
            statusItem.length = NSStatusItem.squareLength
            button.imagePosition = .imageOnly
            button.title = ""
        }
        button.toolTip = errorMessage ?? accessibilityDescription
    }

    static func shortenedStatusName(_ name: String, limit: Int = 24) -> String {
        guard name.count > limit, limit > 1 else { return name }
        return String(name.prefix(limit - 1)) + "…"
    }

    private func menuImage(symbol: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func statusImage(symbol: String, accessibilityDescription: String) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        let image = (
            NSImage(systemSymbolName: symbol, accessibilityDescription: accessibilityDescription)
                ?? NSImage(systemSymbolName: "mic.fill", accessibilityDescription: accessibilityDescription)
        )?.withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func presentError(title: String, error: Error) {
        let message = "\(title): \(error.localizedDescription)"
        guard transientErrorMessage != message else { return }

        transientErrorMessage = message
        installTransientErrorItem()
        updateStatusItemFromSnapshot()

        errorClearWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, transientErrorMessage == message else { return }
            transientErrorMessage = nil
            errorClearWorkItem = nil
            removeTransientErrorItem()
            updateStatusItemFromSnapshot()
        }
        errorClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func addTransientErrorItemIfNeeded() {
        guard let item = transientErrorMenuItem() else { return }
        menu.addItem(item)
    }

    private func installTransientErrorItem() {
        removeTransientErrorItem()
        guard let item = transientErrorMenuItem() else { return }
        menu.insertItem(item, at: min(1, menu.items.count))
    }

    private func removeTransientErrorItem() {
        guard let item = menu.items.first(where: {
            $0.identifier == Self.transientErrorItemIdentifier
        }) else { return }
        menu.removeItem(item)
    }

    private func transientErrorMenuItem() -> NSMenuItem? {
        guard let transientErrorMessage else { return nil }
        let item = NSMenuItem(
            title: Self.shortenedStatusName(transientErrorMessage, limit: 72),
            action: nil,
            keyEquivalent: ""
        )
        item.identifier = Self.transientErrorItemIdentifier
        item.image = menuImage(symbol: "exclamationmark.triangle.fill")
        item.toolTip = transientErrorMessage
        item.isEnabled = false
        return item
    }
}
