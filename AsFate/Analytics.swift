import Foundation
import StoreKit
import TelemetryDeck

/// Funnel analytics, sent to TelemetryDeck (privacy-friendly: no personal data, no consent banner needed).
///
/// Setup: create an app at telemetrydeck.com and paste its App ID into `appID`.
/// While `appID` is empty nothing is sent; debug builds print each event to the console instead.
/// Debug builds send in TelemetryDeck's test mode, so they don't mix with real users.
///
/// Never put names, questions or chat text in parameters, only categories and counts.
///
/// Every event also carries the user's onboarding answers (see `context`), so any event, most
/// importantly `Purchase.trialStarted`, can be split by goal, pains, star sign, matched psychic and
/// onboarding version to see which paths convert best.
enum Analytics {
    static let appID = ""

    /// Bump this whenever the onboarding or paywall changes, to compare conversion before and after.
    static let onboardingVersion = "1"

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
        /// The App Store had no products to show, so nothing could be bought.
        case productsUnavailable = "Paywall.productsUnavailable"
        // Purchases (StoreKit verified)
        case trialStarted = "Purchase.trialStarted"
        case purchased = "Purchase.completed"
        case purchaseCancelled = "Purchase.cancelled"
        /// Waiting for approval, for example Ask to Buy.
        case purchasePending = "Purchase.pending"
        case purchaseFailed = "Purchase.failed"
        /// Restore finished; `found` says whether a subscription came back.
        case restored = "Purchase.restored"
        /// Fate+ was on and no longer is: expired, refunded or cancelled.
        case subscriptionEnded = "Purchase.subscriptionEnded"
        // Chat
        case firstMessageSent = "Chat.firstMessageSent"
        case messageSent = "Chat.messageSent"
        case visitStarted = "Chat.visitStarted"
        /// A reply arrived after the free messages ran out and is shown blurred.
        case replyLocked = "Chat.replyLocked"
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
        let all = context.merging(parameters) { _, new in new }
        #if DEBUG
        let params = all.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        print("[analytics] \(event.rawValue) \(params)")
        #endif
        guard started else { return }
        TelemetryDeck.signal(event.rawValue, parameters: all)
    }

    /// Also sends TelemetryDeck's built-in purchase signal, which powers its revenue and trial dashboards.
    static func trackPurchase(_ transaction: StoreKit.Transaction, _ parameters: [String: String]) {
        guard started else { return }
        TelemetryDeck.purchaseCompleted(transaction: transaction, parameters: context.merging(parameters) { _, new in new })
    }

    // MARK: Conversion context

    private static let contextKey = "analyticsContext"

    private static var storedContext: [String: String] {
        (defaults.dictionary(forKey: contextKey) ?? [:]).mapValues { "\($0)" }
    }

    /// Sent with every event: the onboarding answers (categories only, never the name),
    /// the onboarding version, whether Fate+ is on and how many paywalls were seen.
    static var context: [String: String] {
        var c = storedContext
        c["onboardingVersion"] = onboardingVersion
        c["isPlus"] = String(defaults.bool(forKey: "isPlus"))
        c["paywallViews"] = String(defaults.integer(forKey: "paywallViews"))
        return c
    }

    /// Remembers an onboarding answer (`goal`, `pains`, `sign`, `psychic`) for all later events.
    static func setContext(_ key: String, _ value: String?) {
        var c = storedContext
        c[key] = value ?? "none"
        defaults.set(c, forKey: contextKey)
    }

    /// Counts paywall views, so purchases show whether people buy on the first paywall or a later one.
    static func paywallViewed() {
        defaults.set(defaults.integer(forKey: "paywallViews") + 1, forKey: "paywallViews")
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
