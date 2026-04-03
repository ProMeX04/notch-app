import Foundation
import UserNotifications
import AppKit

struct AppNotificationManager {
    private static let categoryID = "NOTCH_TIMER_ALERT"
    private static let dismissActionID = "DISMISS"

    /// Call once at app launch (before requesting authorization)
    static func setup() {
        let dismissAction = UNNotificationAction(
            identifier: dismissActionID,
            title: "Dismiss",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: categoryID,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    static func sendNotification(title: String, body: String, identifier: String = UUID().uuidString) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized else {
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    deliver(title: title, body: body, identifier: identifier)
                }
                return
            }
            deliver(title: title, body: body, identifier: identifier)
        }
    }

    private static func deliver(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .defaultCritical    // louder, like Clock app alarm
        content.categoryIdentifier = categoryID
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                NotchLog.notification.error("Notification error: \(String(describing: error))")
            }
        }
    }
}
