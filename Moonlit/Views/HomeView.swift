import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    @State private var showSettings = false
    @State private var showMorningPrimer = false
    @State private var showCosmos = false
    /// A question asked from the cosmic view, sent once it has closed.
    @State private var pendingAsk: (question: String, note: String)?

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

                DailyCardTile()
                CosmosTile { showCosmos = true }
                if !app.morningMessagesOn && !app.morningPromptDismissed {
                    morningPrompt
                }
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

                Text("For entertainment only.")
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
        // A tapped morning message opens the chat, so close anything covering it.
        .onReceive(NotificationCenter.default.publisher(for: .openDailyCard)) { _ in
            showSettings = false
            showMorningPrimer = false
        }
        .fullScreenCover(isPresented: $showCosmos, onDismiss: {
            if let ask = pendingAsk {
                pendingAsk = nil
                app.openChat(app.matchedPsychic, asking: ask.question, note: ask.note)
            }
        }) {
            CosmosView(onAsk: { pendingAsk = ($0, $1) })
        }
        .sheet(isPresented: $showMorningPrimer) {
            MorningMessagesPrimer()
                .presentationDetents([.large])
        }
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

    private var morningPrompt: some View {
        let p = app.matchedPsychic
        return Button { showMorningPrimer = true } label: {
            HStack(spacing: 12) {
                AvatarView(psychic: p, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get a morning message from \(p.short)")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textBright)
                    Text("Your card of the day, every morning at \(MorningMessages.hour):00")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "bell.badge").foregroundStyle(Theme.gold)
            }
            .padding(14)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.gold.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var banner: (icon: String, color: Color, text: String) {
        if !app.isLive { return ("wand.and.stars", Theme.gold, "Demo mode · connect a reading server in Settings") }
        if app.serverOnline == false { return ("wifi.exclamationmark", Theme.gold, "Can't reach the reading server · tap to check") }
        return ("sparkles", Theme.online, "Live readings are on")
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
                HStack(spacing: 5) {
                    Image(systemName: "sparkle").font(.system(size: 10))
                    Text(Daily.mood(for: psychic.id))
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.lilac)
                .padding(.top, 2)
                .accessibilityLabel("Mood today: \(Daily.mood(for: psychic.id))")
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
        }
        .padding(14)
        .cardSurface()
        .contentShape(Rectangle())
    }
}

/// Home-screen entry to the cosmic view, with a one-line teaser about today's sky.
struct CosmosTile: View {
    let open: () -> Void
    @State private var twinkle = false

    private var teaser: String {
        let today = Ephemeris.placements(on: Date())
        let retro = today.filter(\.retrograde).map(\.body.name)
        let moon = today.first { $0.body == .moon }?.sign.name ?? ""
        // Lead with the planets people talk about: Mercury, then Venus, then Mars.
        let personal = retro.filter { ["Mercury", "Venus", "Mars"].contains($0) }
        switch (personal.count, retro.count) {
        case (_, 0): return "No planets retrograde · Moon in \(moon)"
        case (0, _): return "Moon in \(moon) · \(retro.count) slow planets retrograde"
        case (1, 1): return "\(personal[0]) is retrograde · Moon in \(moon)"
        case (1, _): return "\(personal[0]) is retrograde, plus \(retro.count - 1) more"
        default: return "\(personal[0]) and \(personal[1]) are retrograde"
        }
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(RadialGradient(colors: [Color(hex: 0xFFD27A), Color(hex: 0xE89A4A).opacity(0)],
                                                 center: .center, startRadius: 2, endRadius: 22))
                        .frame(width: 44, height: 44)
                        .scaleEffect(twinkle ? 1.12 : 0.95)
                    ForEach(0..<3) { i in
                        Circle()
                            .stroke(Theme.lilac.opacity(0.25), lineWidth: 1)
                            .frame(width: CGFloat(30 + i * 16), height: CGFloat(30 + i * 16))
                    }
                    Circle().fill(Color(hex: 0x5FA8E8)).frame(width: 6, height: 6)
                        .offset(x: 23).rotationEffect(.degrees(twinkle ? 40 : -20))
                    Circle().fill(Color(hex: 0xE0704A)).frame(width: 5, height: 5)
                        .offset(x: -31).rotationEffect(.degrees(twinkle ? -25 : 10))
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    EyebrowText("Cosmic view")
                    Text("See where the planets are")
                        .font(Theme.display(19))
                        .foregroundStyle(Theme.textBright)
                    Text(teaser)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Theme.faint)
            }
            .padding(16)
            .cardSurface(strong: true)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { twinkle = true }
        }
    }
}
