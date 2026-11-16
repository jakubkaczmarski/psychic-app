import UIKit
import UserNotifications

/// Local morning notifications from your psychic, written a week ahead.
/// No server or push certificate is needed: the message for each day is known in advance.
enum MorningMessages {
    static let hour = 9
    private static let idPrefix = "morning-"
    private static let daysAhead = 7

    static func isAuthorized() async -> Bool {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        return s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
    }

    /// Asks iOS for permission. Returns whether it was granted.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces the scheduled messages with the next week's, from the given psychic.
    static func schedule(psychic: Psychic, name: String, seed: String) async {
        cancelAll()
        guard await isAuthorized() else { return }
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.current
        let now = Date()
        for offset in 0..<daysAhead {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            var when = calendar.dateComponents([.year, .month, .day], from: day)
            when.hour = hour
            guard let fireDate = calendar.date(from: when), fireDate > now else { continue }

            let card = Daily.card(on: day, seed: seed)
            let content = UNMutableNotificationContent()
            content.title = psychic.name
            content.body = Daily.morningMessage(psychicID: psychic.id, name: name, card: card, on: day)
            content.sound = .default
            content.userInfo = ["action": "daily"]
            let request = UNNotificationRequest(identifier: idPrefix + Daily.dayKey(day), content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    static func cancelAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    #if DEBUG
    /// Testing aid: today's message, 5 seconds from now.
    static func sendTest(psychic: Psychic, name: String, seed: String) async {
        let content = UNMutableNotificationContent()
        content.title = psychic.name
        content.body = Daily.morningMessage(psychicID: psychic.id, name: name, card: Daily.card(seed: seed))
        content.sound = .default
        content.userInfo = ["action": "daily"]
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "test-\(UUID())", content: content,
                                  trigger: UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)))
    }
    #endif
}

extension Notification.Name {
    /// Posted when the user taps a morning message.
    static let openDailyCard = Notification.Name("openDailyCard")
}

/// Shows notifications while the app is open and handles taps on them.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.notification.request.content.userInfo["action"] as? String == "daily" {
            await MainActor.run { NotificationCenter.default.post(name: .openDailyCard, object: nil) }
        }
    }
}
