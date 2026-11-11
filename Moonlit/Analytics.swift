import Foundation
import TelemetryDeck

/// Funnel analytics, sent to TelemetryDeck (privacy-friendly: no personal data, no consent banner needed).
///
/// Setup: create an app at telemetrydeck.com and paste its App ID into `appID`.
/// While `appID` is empty nothing is sent; debug builds print each event to the console instead.
/// Debug builds send in TelemetryDeck's test mode, so they don't mix with real users.
///
/// Never put names, questions or chat text in parameters, only categories and counts.
enum Analytics {
    static let appID = ""

    enum Event: String {
        // Onboarding
        case onboardingStep = "Onboarding.stepViewed"
        case onboardingCompleted = "Onboarding.completed"
        // Paywall
        case paywallShown = "Paywall.shown"
        case paywallPlanSelected = "Paywall.planSelected"
        case paywallCTATapped = "Paywall.ctaTapped"
        case paywallRestoreTapped = "Paywall.restoreTapped"
        case paywallDismissed = "Paywall.dismissed"
        /// TODO: Send these from `PaywallView` once StoreKit purchases are wired up.
        case trialStarted = "Purchase.trialStarted"
        case purchased = "Purchase.completed"
        // Chat
        case firstMessageSent = "Chat.firstMessageSent"
        case messageSent = "Chat.messageSent"
        case visitStarted = "Chat.visitStarted"
        // Daily habits and retention
        case activeDay = "App.activeDay"
        case dailyCardRevealed = "Daily.cardRevealed"
        case morningMessagesAnswered = "Daily.morningMessagesAnswered"
    }

    private static var started = false
    private static let defaults = UserDefaults.standard

    static func start() {
        if defaults.object(forKey: "installDate") == nil { defaults.set(Date(), forKey: "installDate") }
        guard !appID.isEmpty, !started else { return }
        started = true
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
    }

    static func track(_ event: Event, _ parameters: [String: String] = [:]) {
        #if DEBUG
        let params = parameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("📊 \(event.rawValue) \(params)")
        #endif
        guard started else { return }
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
    }

    /// Days since the app was first opened: 0 on install day, 1 the next day, and so on.
    static var daysSinceInstall: Int {
        let install = defaults.object(forKey: "installDate") as? Date ?? Date()
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: install), to: cal.startOfDay(for: Date())).day ?? 0
    }

    /// Sends `App.activeDay` once per calendar day. Day 1 and day 7 retention are the share of
    /// installs that send it with `daysSinceInstall` 1 and 7.
    static func appBecameActive() {
        let today = Daily.dayKey()
        guard defaults.string(forKey: "lastActiveDay") != today else { return }
        defaults.set(today, forKey: "lastActiveDay")
        let days = daysSinceInstall
        track(.activeDay, ["daysSinceInstall": String(days), "week": String(days / 7)])
    }
}
