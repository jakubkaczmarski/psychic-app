import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var daily: TarotCard?
    @State private var showSettings = false

    private var greetLine: String? {
        let name = app.userName.trimmingCharacters(in: .whitespaces)
        switch (name.isEmpty, app.sign) {
        case (false, let sign?): return "Hi \(name) · \(sign)"
        case (false, nil): return "Hi \(name)"
        case (true, let sign?): return "Tonight for \(sign)"
        default: return nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    if let greetLine {
                        Text(greetLine)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                    }
                    Text("Ask anything.\nThe cards are listening.")
                        .font(Theme.display(40, .medium))
                        .foregroundStyle(Theme.textBright)
                    Text("Pick a psychic for a playful reading on love, work, or whatever is on your mind tonight.")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                }

                dailyCard
                modeBanner

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        EyebrowText("Psychics online")
                        Spacer()
                        HStack(spacing: 6) {
                            OnlineDot()
                            Text("\(Catalog.psychics.count) available")
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.online)
                    }
                    ForEach(Catalog.psychics) { p in
                        NavigationLink(value: Route.profile(p.id)) {
                            PsychicRow(psychic: p)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Text("For entertainment only. Moonlit psychics are AI characters, not real advisors.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task { await app.checkServer() }
    }

    private var header: some View {
        HStack {
            Wordmark()
            Spacer()
            Button { app.path.append(.readings) } label: {
                Image(systemName: "book.closed")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        if !app.readings.isEmpty {
                            Text("\(app.readings.count)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.onGold)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Theme.gold, in: Capsule())
                                .offset(x: 3, y: -3)
                        }
                    }
            }
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Your readings")

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Theme.borderStrong, lineWidth: 1))
            }
            .foregroundStyle(Theme.text)
            .accessibilityLabel("Settings")
        }
        .padding(.top, 8)
    }

    private var dailyCard: some View {
        Button {
            withAnimation(.spring(duration: 0.4)) { daily = Catalog.deck.randomElement() }
        } label: {
            HStack(spacing: 16) {
                MiniTarotCard(numeral: daily?.numeral)
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowText("Card of the day")
                    if let daily {
                        Text(daily.name).font(Theme.display(22)).foregroundStyle(Theme.gold)
                        Text(daily.meaning).font(.system(size: 14)).foregroundStyle(Theme.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Tap to reveal your card").font(Theme.display(22)).foregroundStyle(Theme.textBright)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(strong: true)
        }
        .buttonStyle(.plain)
    }

    private var banner: (icon: String, color: Color, text: String) {
        if !app.isLive { return ("wand.and.stars", Theme.gold, "Demo mode · connect a reading server in Settings") }
        if app.serverOnline == false { return ("wifi.exclamationmark", Theme.gold, "Can't reach the reading server · tap to check") }
        return ("sparkles", Theme.online, "Live readings by Claude are on")
    }

    @ViewBuilder private var modeBanner: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 10) {
                Image(systemName: banner.icon)
                    .foregroundStyle(banner.color)
                Text(banner.text)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSoft)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(Theme.faint)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct PsychicRow: View {
    let psychic: Psychic

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(psychic: psychic, size: 62)
            VStack(alignment: .leading, spacing: 3) {
                Text(psychic.name).font(Theme.display(21)).foregroundStyle(Theme.textBright)
                Text(psychic.specialty).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.gold)
                Text(psychic.tagline).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
        }
        .padding(14)
        .cardSurface()
        .contentShape(Rectangle())
    }
}
