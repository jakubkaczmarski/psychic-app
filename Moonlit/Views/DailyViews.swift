import SwiftUI

/// Home screen tile: today's card, read by your psychic, with a streak.
struct DailyCardTile: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        let p = app.matchedPsychic
        let card = app.todaysCard
        let revealed = app.revealedToday

        VStack(alignment: .leading, spacing: 14) {
            HStack {
                EyebrowText("Card of the day")
                Spacer()
                if app.dailyStreak > 0 {
                    Text("🔥 \(app.dailyStreak) day\(app.dailyStreak == 1 ? "" : "s")")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.gold.opacity(0.12), in: Capsule())
                        .accessibilityLabel("\(app.dailyStreak) day streak")
                }
            }

            Button {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { app.revealDailyCard() }
            } label: {
                HStack(alignment: .top, spacing: 16) {
                    TarotTile(card: card, revealed: revealed, compact: true)
                        .frame(width: 64)
                    VStack(alignment: .leading, spacing: 6) {
                        if revealed {
                            Text(card.name).font(Theme.display(22)).foregroundStyle(Theme.gold)
                            HStack(alignment: .top, spacing: 8) {
                                AvatarView(psychic: p, size: 24)
                                Text(Daily.morningMessage(psychicID: p.id, name: firstName, card: card))
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.textSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            Text("Tap to turn your card").font(Theme.display(22)).foregroundStyle(Theme.textBright)
                            Text("\(p.short) will read it for you.")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Not `.disabled`, which would dim the revealed reading; tapping again does nothing.
            .allowsHitTesting(!revealed)
            .accessibilityHint(revealed ? "" : "Reveals today's card")

            if revealed {
                Button { app.askAboutDailyCard() } label: {
                    Label("Ask \(p.short) about it", systemImage: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.onGold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.gold, in: Capsule())
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(strong: true)
    }

    private var firstName: String { app.userName.trimmingCharacters(in: .whitespaces) }
}

/// Explains morning messages before iOS asks for notification permission.
struct MorningMessagesPrimer: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var asking = false

    var body: some View {
        let p = app.matchedPsychic
        let name = app.userName.trimmingCharacters(in: .whitespaces)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()

        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 24) {
                    AvatarView(psychic: p, size: 96)
                        .padding(.top, 36)
                    VStack(spacing: 10) {
                        Text("Start each day with \(p.short).")
                            .font(Theme.display(30, .medium))
                            .foregroundStyle(Theme.textBright)
                            .multilineTextAlignment(.center)
                        Text("Every morning \(p.short) turns a card for you and sends a short message about your day.")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                    }

                    // A preview of tomorrow's actual message.
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(psychic: p, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(p.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textBright)
                                Spacer()
                                Text("\(MorningMessages.hour):00").font(.system(size: 12)).foregroundStyle(Theme.faint)
                            }
                            Text(Daily.morningMessage(psychicID: p.id, name: name,
                                                      card: Daily.card(on: tomorrow, seed: app.dailySeed), on: tomorrow))
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Example message from \(p.name)")

                    VStack(alignment: .leading, spacing: 12) {
                        point("sun.horizon", "One message a day, at \(MorningMessages.hour):00")
                        point("flame", "Keeps your daily streak going")
                        point("hand.raised", "Turn it off any time in Settings")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)
            }

            OnboardingFooter {
                Button {
                    asking = true
                    Task {
                        _ = await app.enableMorningMessages()
                        asking = false
                        dismiss()
                    }
                } label: {
                    HStack {
                        Text("Send me morning messages")
                        if asking { ProgressView().tint(Theme.onGold) }
                    }
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(asking)
                Button("Not now") {
                    app.morningPromptDismissed = true
                    dismiss()
                }
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.gold).frame(width: 24)
            Text(text).font(.system(size: 16)).foregroundStyle(Theme.text)
        }
    }
}
