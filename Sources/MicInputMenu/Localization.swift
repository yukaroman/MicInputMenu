import Foundation

enum L10n {
    private static let usesChinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true

    static func text(zh: String, en: String) -> String {
        usesChinese ? zh : en
    }

    static let appName = text(zh: "麦克风输入", en: "Mic Input")
    static let currentInput = text(zh: "当前输入", en: "Current Input")
    static let noInput = text(zh: "未找到输入设备", en: "No input device found")
    static let inputVolume = text(zh: "输入音量", en: "Input Volume")
    static let muteInput = text(zh: "静音输入", en: "Mute Input")
    static let muted = text(zh: "已静音", en: "Muted")
    static let fallbackInput = text(zh: "设备断开时切换到", en: "Switch When Disconnected")
    static let fallbackAutomatic = text(zh: "自动（优先内置麦克风）", en: "Automatic (Prefer Built-in)")
    static let fallbackDisabled = text(zh: "不自动切换", en: "Do Not Switch Automatically")
    static let unavailable = text(zh: "不可用", en: "Unavailable")
    static let preferences = text(zh: "偏好设置", en: "Preferences")
    static let showDeviceName = text(zh: "在菜单栏显示设备名称", en: "Show Device Name in Menu Bar")
    static let switchNotifications = text(zh: "设备切换通知", en: "Device Switch Notifications")
    static let notificationDenied = text(zh: "通知权限未开启", en: "Notification Access Is Off")
    static let globalShortcut = text(zh: "全局快捷键", en: "Global Shortcut")
    static let launchAtLogin = text(zh: "登录时自动启动", en: "Launch at Login")
    static let launchApproval = text(zh: "登录时自动启动（等待批准）", en: "Launch at Login (Approval Required)")
    static let refresh = text(zh: "刷新", en: "Refresh")
    static let soundSettings = text(zh: "打开声音设置…", en: "Open Sound Settings…")
    static let quit = text(zh: "退出麦克风输入", en: "Quit Mic Input")
    static let switchFailed = text(zh: "无法切换麦克风", en: "Could Not Switch Microphone")
    static let volumeFailed = text(zh: "无法调整输入音量", en: "Could Not Change Input Volume")
    static let muteFailed = text(zh: "无法更改静音状态", en: "Could Not Change Mute State")
    static let featureFailed = text(zh: "无法更改设置", en: "Could Not Change Setting")
    static let readFailed = text(zh: "无法读取输入设备", en: "Could Not Read Input Devices")
    static let dismiss = text(zh: "好", en: "OK")

    static func switchNotification(_ deviceName: String) -> String {
        text(
            zh: "输入设备已切换到“\(deviceName)”",
            en: "Input switched to “\(deviceName)”"
        )
    }

    static func automaticSwitchNotification(_ deviceName: String) -> String {
        text(
            zh: "原设备已断开，输入已自动切换到“\(deviceName)”",
            en: "The previous device disconnected. Input switched to “\(deviceName)”."
        )
    }
}
