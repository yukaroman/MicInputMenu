import Foundation
import UserNotifications

final class NotificationController: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization(completion: @escaping (Bool, Error?) -> Void) {
        center.requestAuthorization(options: [.alert]) { granted, error in
            DispatchQueue.main.async {
                completion(granted, error)
            }
        }
    }

    func postDeviceSwitch(to deviceName: String, automatic: Bool) {
        let content = UNMutableNotificationContent()
        content.title = L10n.appName
        content.body = automatic
            ? L10n.automaticSwitchNotification(deviceName)
            : L10n.switchNotification(deviceName)

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner])
    }
}
