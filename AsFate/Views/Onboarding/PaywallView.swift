import StoreKit
import SwiftUI

/// Paywall shown at the end of onboarding, personalised with the user's psychic, goal and spread.
/// Prices and purchases come from StoreKit (see `Store`); every outcome is sent to analytics
/// with the paywall's source, plan and the user's onboarding answers.
struct PaywallView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var store: Store
    let psychic: Psychic
    var goal: OnboardingGoal? = nil
    /// The three cards drawn in onboarding, shown as "your reading so far".
    var spread: [TarotCard] = []
    /// Opened from a locked reply: the header talks about that reply.
    var lockedReply = false
    var name: String = ""
    /// Where the paywall was opened from, for analytics.
    var source: String = "onboarding"
    let onFinish: () -> Void

    enum Plan: String { case yearly, weekly }
    @State private var plan: Plan = .yearly
    @State private var shownAt = Date()
    @State private var busy = false
    @State private var message: String?

    private var yearly: Product? { store.products[Store.yearlyID] }
    private var weekly: Product? { store.products[Store.weeklyID] }
    private var selectedProduct: Product? { plan == .yearly ? yearly : weekly }

    /// "3 days free" when the yearly plan has a trial this user can still get.
    private var trial: String? {
        guard store.trialEligible else { return nil }
        guard let yearly else { return "3 days free" }  // until StoreKit answers
        return yearly.freeTrialText
    }
    // Shown until StoreKit answers (and if it never does); the App Store prices replace them.
    private var yearlyPrice: String { yearly?.displayPrice ?? "$29.99" }
    private var weeklyPrice: String { weekly?.displayPrice ?? "$4.99" }
    private var isTrial: Bool { plan == .yearly && trial != nil }

    /// The user's goal when it belongs to this psychic, otherwise what the psychic is known for.
    private var topic: String {
        if let goal, goal.psychicID == psychic.id { return goal.yourTopic }
        let fallback = ["selene": "your love life", "kaz": "your career", "ivy": "your life choices",
                        "zephyr": "your week ahead", "mirela": "your family"]
        return fallback[psychic.id] ?? "you"
    }
    private var others: [Psychic] { Catalog.psychics.filter { $0.id != psychic.id } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button { dismiss("close") } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    if spread.count == 3 { spreadRecap }
                    VStack(alignment: .leading, spacing: 12) {
                        benefit("Ask \(psychic.short) about \(topic), any time, day or night")
                        benefit(Self.ritualBenefit[psychic.id] ?? "Unlimited rituals and tarot pulls")
                        benefit("Your card of the day and morning messages from \(psychic.short)")
                        othersRow
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        planRow(.yearly, title: "Yearly",
                                detail: trial.map { "\($0), then \(yearlyPrice)/year" } ?? "\(yearlyPrice)/year",
                                badge: "Best value")
                        planRow(.weekly, title: "Weekly", detail: "\(weeklyPrice)/week", badge: nil)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            OnboardingFooter {
                Button { Task { await buy() } } label: {
                    if busy {
                        ProgressView().tint(Theme.onGold)
                    } else {
                        Text(isTrial ? "Start my free trial" : "Continue")
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(busy)
                HStack(spacing: 18) {
                    Button("Restore purchases") { Task { await restore() } }
                    Button("Not now") { dismiss("notNow") }
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 40)
                .disabled(busy)
                Text(finePrint)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            shownAt = Date()
            Analytics.paywallViewed()
            Analytics.track(.paywallShown, analyticsParams)
        }
        .task {
            if store.products.isEmpty { await store.loadProducts() }
            if store.unavailable, !Store.mockPurchases { Analytics.track(.productsUnavailable, analyticsParams) }
        }
        .alert("Fate+", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private var finePrint: String {
        switch plan {
        case .yearly:
            if let trial { return "\(trial.prefix(1).uppercased() + trial.dropFirst()), then \(yearlyPrice)/year. Cancel anytime." }
            return "\(yearlyPrice)/year. Cancel anytime."
        case .weekly:
            return "\(weeklyPrice)/week. Cancel anytime. For entertainment only."
        }
    }

    // MARK: Personalised content

    /// The matched psychic, a line in their voice about the user's goal, and the headline.
    private var header: some View {
        VStack(spacing: 16) {
            AvatarView(psychic: psychic, size: 92)
            VStack(alignment: .leading, spacing: 6) {
                Text(psychic.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: psychic.ringHex).opacity(0.9))
                Text(pitch)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))

            Text(headline)
                .font(Theme.display(30, .medium))
                .foregroundStyle(Theme.textBright)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The first reading arrived during onboarding and part of it is locked.
    private var teaserWaiting: Bool {
        if case .ready(let parts) = app.teaser { return parts.indices.contains { app.teaserLocked($0) } }
        return false
    }

    private var headline: String {
        if lockedReply { return "Read \(psychic.short)'s reply" }
        if teaserWaiting { return name.isEmpty ? "Read all of \(psychic.short)'s reading" : "\(name), read all of \(psychic.short)'s reading" }
        return name.isEmpty ? "Keep \(psychic.short) on call" : "\(name), keep \(psychic.short) on call"
    }

    /// What the psychic says on the paywall, in their own texting voice.
    private var pitch: String {
        if lockedReply {
            let lines: [String: String] = [
                "selene": "Your answer is waiting under the moonlight, darling.",
                "kaz": "Your answer's behind the paywall. Your call.",
                "ivy": "I've a proper answer for you, love. It's just there, under the tea towel.",
                "zephyr": "the ball has your answer!! it's right there",
                "mirela": "I have your answer, my dear. Come, read it.",
            ]
            return lines[psychic.id] ?? lines["selene"]!
        }
        let lines: [String: String] = [
            "selene": "Darling, I've barely begun with {topic}. Stay a while.",
            "kaz": "That was the warm-up. The real read on {topic} starts now.",
            "ivy": "Oh, love, that was only the first cup. There's plenty more to say about {topic}.",
            "zephyr": "ok the ball is NOT done with {topic}. it's still glowing. stay",
            "mirela": "One spread tells me a little, my dear. Come back often and I'll tell you the rest about {topic}.",
        ]
        return (lines[psychic.id] ?? lines["selene"]!).replacingOccurrences(of: "{topic}", with: topic)
    }

    private static let ritualBenefit: [String: String] = [
        "selene": "Moon readings whenever your heart needs one",
        "kaz": "Fresh love, money and energy forecasts on demand",
        "ivy": "Tea-leaf readings, with the kettle always on",
        "zephyr": "Unlimited crystal ball visions (pigeons not guaranteed)",
        "mirela": "A new card from Mirela's deck every time you ask",
    ]

    /// The three cards the user just drew, so the paywall is about their reading.
    private var spreadRecap: some View {
        VStack(alignment: .leading, spacing: 12) {
            EyebrowText("Your spread")
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(zip(OnboardingCatalog.positions, spread)), id: \.0) { position, card in
                    VStack(spacing: 6) {
                        TarotTile(card: card, revealed: true, compact: true)
                            .frame(width: 52)
                        Text(position).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        Text(card.name)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text(teaserWaiting ? "\(psychic.short)'s full reading is waiting for you."
                               : "Up next: \(psychic.short) reads all three for you.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var othersRow: some View {
        HStack(spacing: 12) {
            HStack(spacing: -10) {
                ForEach(others) { p in
                    AvatarView(psychic: p, size: 30).overlay(Circle().stroke(Theme.bg, lineWidth: 2))
                }
            }
            Text("Plus \(others.map(\.short).dropLast().joined(separator: ", ")) and \(others.last?.short ?? "")")
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
        }
    }

    private func benefit(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold)
            Text(text).font(.system(size: 16)).foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Analytics

    private var analyticsParams: [String: String] {
        ["source": source, "psychic": psychic.id, "goal": goal?.id ?? "none", "plan": plan.rawValue,
         "trialEligible": String(store.trialEligible)]
    }

    private func dismiss(_ how: String) {
        var params = analyticsParams
        params["how"] = how
        params["seconds"] = String(Int(Date().timeIntervalSince(shownAt)))
        Analytics.track(.paywallDismissed, params)
        onFinish()
    }

    private func planRow(_ p: Plan, title: String, detail: String, badge: String?) -> some View {
        let selected = plan == p
        return Button {
            plan = p
            Analytics.track(.paywallPlanSelected, analyticsParams)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.gold : Theme.borderStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textBright)
                    Text(detail).font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.onGold)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Theme.gold, in: Theme.chip)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 66)
            .background(selected ? Theme.surfaceSelected : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .stroke(selected ? Theme.gold : Theme.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var secondsOnPaywall: String { String(Int(Date().timeIntervalSince(shownAt))) }

    private func buy() async {
        Analytics.track(.paywallCTATapped, analyticsParams)
        var params = analyticsParams
        params["seconds"] = secondsOnPaywall

        if Store.mockPurchases {
            // Testing (TestFlight): no StoreKit, no charge. Tracked like a real purchase, marked as a mock.
            params["mock"] = "true"
            Analytics.track(isTrial ? .trialStarted : .purchased, params)
            app.unlockPlusForTesting()
            onFinish()
            return
        }

        guard let product = selectedProduct else {
            #if DEBUG
            // No StoreKit products here (launched outside Xcode, or not in App Store Connect yet).
            print("[store] StoreKit products unavailable: unlocking Fate+ locally (debug builds only).")
            app.unlockPlusForTesting()
            onFinish()
            #else
            Analytics.track(.purchaseFailed, params.merging(["reason": "productsUnavailable"]) { $1 })
            message = "Fate+ can't be bought right now. Check your connection and try again."
            #endif
            return
        }

        busy = true
        defer { busy = false }
        switch await store.purchase(product) {
        case .purchased(let transaction):
            let trialStarted = isTrial
            params["productID"] = product.id
            Analytics.track(trialStarted ? .trialStarted : .purchased, params)
            Analytics.trackPurchase(transaction, params)
            onFinish()
        case .cancelled:
            Analytics.track(.purchaseCancelled, params)
        case .pending:
            Analytics.track(.purchasePending, params)
            message = "Your purchase is waiting for approval. Fate+ turns on as soon as it's approved."
        case .failed(let reason):
            params["reason"] = reason
            Analytics.track(.purchaseFailed, params)
            message = "The purchase didn't go through. Nothing was charged. Please try again."
        }
    }

    private func restore() async {
        Analytics.track(.paywallRestoreTapped, analyticsParams)
        if Store.mockPurchases {
            message = "This is a test build: purchases are free and nothing is charged. Tap the button above to turn on Fate+."
            return
        }
        busy = true
        defer { busy = false }
        switch await store.restore() {
        case .restored:
            Analytics.track(.restored, analyticsParams.merging(["found": "true"]) { $1 })
            onFinish()
        case .nothingFound:
            Analytics.track(.restored, analyticsParams.merging(["found": "false"]) { $1 })
            message = "No Fate+ subscription was found for this Apple Account."
        case .cancelled:
            break
        case .failed(let reason):
            Analytics.track(.restored, analyticsParams.merging(["found": "false", "reason": reason]) { $1 })
            message = "Purchases couldn't be restored. Check your connection and try again."
        }
    }
}
