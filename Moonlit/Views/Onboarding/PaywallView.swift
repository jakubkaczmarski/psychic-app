import SwiftUI

/// Placeholder paywall shown at the end of onboarding.
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
    let onFinish: () -> Void

    enum Plan: String { case yearly, weekly }
    @State private var plan: Plan = .yearly

    // TODO: Replace with real products and prices from StoreKit.
    private static let yearlyProductID = "com.example.moonlit.plus.yearly"
    private static let weeklyProductID = "com.example.moonlit.plus.weekly"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: onFinish) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        HStack(spacing: -12) {
                            ForEach(Catalog.psychics) { p in
                                AvatarView(psychic: p, size: p.id == psychic.id ? 64 : 48)
                                    .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                                    .zIndex(p.id == psychic.id ? 1 : 0)
                            }
                        }
                        Text("Your psychic circle, whenever you need it.")
                            .font(Theme.display(30, .medium))
                            .foregroundStyle(Theme.textBright)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        benefit("Unlimited questions with all five psychics")
                        benefit("Tarot pulls whenever you ask for one")
                        benefit("Every reading saved, so you can look back")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    review

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
                    Button("Not now", action: onFinish)
                }
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 40)
                Text("Cancel anytime. For entertainment only.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    private func benefit(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.gold)
            Text(text).font(.system(size: 16)).foregroundStyle(Theme.text)
        }
    }

    // TODO: Placeholder review. Replace with a real App Store review once you have one.
    private var review: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { _ in Image(systemName: "star.fill") }
            }
            .font(.system(size: 13))
            .foregroundStyle(Theme.gold)
            .accessibilityLabel("5 stars")
            Text("“Grandma Ivy told me to stop waiting for a sign. Weirdly, that was the sign.”")
                .font(Theme.display(16))
                .italic()
                .foregroundStyle(Theme.text)
            Text("Maya, Libra").font(.system(size: 13)).foregroundStyle(Theme.muted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func planRow(_ p: Plan, title: String, detail: String, badge: String?) -> some View {
        let selected = plan == p
        return Button { plan = p } label: {
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
        // TODO: Purchase `plan == .yearly ? Self.yearlyProductID : Self.weeklyProductID` with StoreKit 2.
        onFinish()
    }

    private func restore() {
        // TODO: `try await AppStore.sync()`, then re-check entitlements.
        onFinish()
    }
}
