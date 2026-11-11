import SwiftUI

/// Paywall shown at the end of onboarding, personalised with the user's psychic, goal and spread.
/// The purchase itself is still a placeholder.
///
/// TODO: Connect StoreKit 2 before release:
///   1. Create the products in App Store Connect (IDs below are placeholders).
///   2. Load them with `Product.products(for:)` and show `displayPrice` instead of the hard-coded prices.
///   3. Call `product.purchase()` in `startTrial()`, verify the transaction and finish it.
///   4. Check `Transaction.currentEntitlements` at launch and implement `restore()` with `AppStore.sync()`.
///   5. Decide what Moonlit+ unlocks (for example, raise the server's daily limit for subscribers).
/// Until then every button simply continues into the app; nothing is charged.
struct PaywallView: View {
    let psychic: Psychic
    var goal: OnboardingGoal? = nil
    /// The three cards drawn in onboarding, shown as "your reading so far".
    var spread: [TarotCard] = []
    var name: String = ""
    /// Where the paywall was opened from, for analytics.
    var source: String = "onboarding"
    let onFinish: () -> Void

    enum Plan: String { case yearly, weekly }
    @State private var plan: Plan = .yearly
    @State private var shownAt = Date()

    // TODO: Replace with real products and prices from StoreKit.
    private static let yearlyProductID = "com.example.moonlit.plus.yearly"
    private static let weeklyProductID = "com.example.moonlit.plus.weekly"

    private var topic: String { goal?.yourTopic ?? "you" }
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
                        planRow(.yearly, title: "Yearly", detail: "3 days free, then $29.99/year", badge: "Best value")
                        planRow(.weekly, title: "Weekly", detail: "$4.99/week", badge: nil)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }

            OnboardingFooter {
                Button(plan == .yearly ? "Start my free trial" : "Continue", action: startTrial)
                    .buttonStyle(GoldButtonStyle())
                HStack(spacing: 18) {
                    Button("Restore purchases", action: restore)
                    Button("Not now") { dismiss("notNow") }
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 40)
                Text(plan == .yearly ? "Free for 3 days, then $29.99/year. Cancel anytime." : "Cancel anytime. For entertainment only.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .onAppear {
            shownAt = Date()
            Analytics.track(.paywallShown, analyticsParams)
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
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text(name.isEmpty ? "Keep \(psychic.short) on call" : "\(name), keep \(psychic.short) on call")
                .font(Theme.display(30, .medium))
                .foregroundStyle(Theme.textBright)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What the psychic says on the paywall, in their own texting voice.
    private var pitch: String {
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
            Text("Up next: \(psychic.short) reads all three for you.")
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
        ["source": source, "psychic": psychic.id, "goal": goal?.id ?? "none", "plan": plan.rawValue]
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
                        .background(Theme.gold, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 66)
            .background(selected ? Color(hex: 0x2A2350) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Theme.gold : Theme.border, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func startTrial() {
        Analytics.track(.paywallCTATapped, analyticsParams)
        // TODO: Purchase `plan == .yearly ? Self.yearlyProductID : Self.weeklyProductID` with StoreKit 2,
        // then send `.trialStarted` (yearly) or `.purchased` (weekly) with `analyticsParams`.
        onFinish()
    }

    private func restore() {
        Analytics.track(.paywallRestoreTapped, analyticsParams)
        // TODO: `try await AppStore.sync()`, then re-check entitlements.
        onFinish()
    }
}
