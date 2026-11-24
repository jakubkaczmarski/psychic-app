import SwiftUI

// MARK: 1. Welcome

struct WelcomeStep: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: -14) {
                        ForEach(Catalog.psychics.prefix(6)) { p in
                            AvatarView(psychic: p, size: 58)
                                .overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                        }
                    }
                    .padding(.top, 28)

                    VStack(alignment: .leading, spacing: 12) {
                        Wordmark(size: 22)
                        Text("Answers for the questions that keep you up at night.")
                            .font(Theme.display(38, .medium))
                            .foregroundStyle(Theme.textBright)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Five psychics, one for every kind of question. Your first reading takes a minute.")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.muted)
                            .lineSpacing(3)
                    }

                    chatPreview
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            OnboardingFooter {
                Button("Get my first reading", action: onStart)
                    .buttonStyle(GoldButtonStyle())
                Text("For entertainment only.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.faint)
                    .frame(minHeight: 30)
            }
        }
    }

    /// A glimpse of a real reading, so people see the end state first.
    private var chatPreview: some View {
        let selene = Catalog.psychic("selene")
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 60)
                Text("Should I text him first?")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            }
            HStack(alignment: .bottom, spacing: 10) {
                AvatarView(psychic: selene, size: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(selene.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.lilac)
                    Text("The moon says yes, darling. But send it tomorrow morning, not at 2am.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.text)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                Spacer(minLength: 30)
            }
        }
        .padding(16)
        .cardSurface()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Example reading. You ask: Should I text him first? Madame Selene answers: The moon says yes, darling. But send it tomorrow morning, not at 2am.")
    }
}

// MARK: 2. Goal

struct GoalStep: View {
    @Binding var selection: String?
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingHeader(title: "What's on your mind lately?",
                                     subtitle: "We'll match you with the psychic who knows it best.")
                    VStack(spacing: 10) {
                        ForEach(OnboardingCatalog.goals) { g in
                            OptionRow(symbol: g.symbol, label: g.label, selected: selection == g.id) {
                                withAnimation(.easeOut(duration: 0.2)) { selection = g.id }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            if selection != nil {
                OnboardingFooter {
                    Button("Continue", action: onNext).buttonStyle(GoldButtonStyle())
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}

// MARK: 3. What makes it hard

struct PainsStep: View {
    @Binding var selection: Set<String>
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingHeader(title: "What's making it hard right now?",
                                     subtitle: "Pick all that fit. Your psychic will keep it in mind.")
                    VStack(spacing: 10) {
                        ForEach(OnboardingCatalog.pains) { p in
                            OptionRow(symbol: p.symbol, label: p.label, selected: selection.contains(p.id), multi: true) {
                                if selection.contains(p.id) { selection.remove(p.id) } else { selection.insert(p.id) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            OnboardingFooter {
                Button(selection.isEmpty ? "Skip" : "Continue", action: onNext).buttonStyle(GoldButtonStyle())
            }
        }
    }
}

// MARK: 4. Name and star sign

struct YouStep: View {
    @EnvironmentObject var app: AppState
    @FocusState private var nameFocused: Bool
    let onNext: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingHeader(title: "Now, a little about you.",
                                     subtitle: "So your readings feel like they're actually about you.")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What should they call you?")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSoft)
                        TextField("", text: $app.userName, prompt: Text("Your first name").foregroundColor(Theme.faint))
                            .textContentType(.givenName)
                            .submitLabel(.done)
                            .focused($nameFocused)
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.borderStrong, lineWidth: 1))
                            .foregroundStyle(Theme.textBright)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your star sign")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textSoft)
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(Catalog.signs) { s in
                                let selected = app.sign == s.name
                                Button {
                                    app.sign = selected ? nil : s.name
                                } label: {
                                    VStack(spacing: 2) {
                                        Text(s.name).font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Theme.textBright)
                                            .lineLimit(1).minimumScaleFactor(0.8)
                                        Text(s.dates).font(.system(size: 11))
                                            .foregroundStyle(Theme.muted)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 58)
                                    .background(selected ? Theme.surfaceSelected : Theme.surface,
                                                in: RoundedRectangle(cornerRadius: Theme.radius))
                                    .overlay(RoundedRectangle(cornerRadius: Theme.radius)
                                        .stroke(selected ? Theme.gold : Theme.border, lineWidth: selected ? 1.5 : 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            OnboardingFooter {
                Button("Shuffle my cards") {
                    nameFocused = false
                    onNext()
                }
                .buttonStyle(GoldButtonStyle())
            }
        }
    }
}

// MARK: 5. Processing

struct ProcessingStep: View {
    let name: String
    let onDone: () -> Void
    @State private var line = 0
    @State private var spin = false

    private var lines: [String] {
        [name.isEmpty ? "Reading your stars…" : "Reading your stars, \(name)…",
         "Shuffling the deck…",
         "Finding your psychic…"]
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle().stroke(Theme.gold.opacity(0.2), lineWidth: 1).frame(width: 160, height: 160)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Theme.gold, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(Theme.gold)
                    .symbolEffect(.pulse)
            }
            Text(lines[line])
                .font(Theme.display(24, .medium))
                .foregroundStyle(Theme.textBright)
                .multilineTextAlignment(.center)
                .id(line)
                .transition(.opacity)
                .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { spin = true }
        }
        .task {
            for i in 1..<lines.count {
                try? await Task.sleep(for: .milliseconds(950))
                if Task.isCancelled { return }
                withAnimation(.easeInOut(duration: 0.3)) { line = i }
            }
            try? await Task.sleep(for: .milliseconds(950))
            if !Task.isCancelled { onDone() }
        }
    }
}

// MARK: 6. Try it: draw three cards

struct DrawStep: View {
    let onDone: ([TarotCard]) -> Void
    @State private var deck = Array(Catalog.deck.shuffled().prefix(6))
    @State private var picked: [Int] = []

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
    private var remaining: Int { 3 - picked.count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    OnboardingHeader(eyebrow: "Your first reading",
                                     title: "Pick three cards.",
                                     subtitle: "Go with your gut. They'll show your past, present and future.")
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(deck.indices, id: \.self) { i in
                            let order = picked.firstIndex(of: i)
                            Button { pick(i) } label: {
                                VStack(spacing: 8) {
                                    TarotTile(card: deck[i], revealed: order != nil)
                                    Text(order.map { OnboardingCatalog.positions[$0] } ?? " ")
                                        .font(Theme.eyebrow)
                                        .tracking(1.2)
                                        .foregroundStyle(Theme.gold)
                                }
                                .opacity(remaining == 0 && order == nil ? 0.35 : 1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(order.map { "\(OnboardingCatalog.positions[$0]): \(deck[i].name)" } ?? "Face-down card")
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            OnboardingFooter {
                Button(remaining == 0 ? "See what they mean" : "Pick \(remaining) more") {
                    onDone(picked.map { deck[$0] })
                }
                .buttonStyle(GoldButtonStyle())
                .disabled(remaining > 0)
                .opacity(remaining > 0 ? 0.45 : 1)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: picked.count)
    }

    private func pick(_ i: Int) {
        guard remaining > 0, !picked.contains(i) else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { picked.append(i) }
    }
}

/// A tarot card that flips from its back to its face.
struct TarotTile: View {
    let card: TarotCard
    let revealed: Bool
    /// Small tiles drop the name, which is shown next to them instead.
    var compact = false

    var body: some View {
        ZStack {
            back.opacity(revealed ? 0 : 1)
            face.opacity(revealed ? 1 : 0)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
        }
        .aspectRatio(TarotArt.aspect, contentMode: .fit)
        .rotation3DEffect(.degrees(revealed ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
    }

    private var back: some View { TarotBack() }

    private var face: some View { TarotArt(card: card, compact: compact) }
}

// MARK: 7. Result: the spread and the psychic match

struct ResultStep: View {
    @EnvironmentObject var app: AppState
    let spread: [TarotCard]
    let goal: OnboardingGoal?
    let match: Psychic
    let name: String
    let sign: String?
    let onNext: () -> Void

    @State private var shareImage: Image?
    @State private var trackedTeaser = false

    /// The psychic's first reading, fetched since the cards were drawn (see `AppState.startTeaser`).
    private var parts: [String]? {
        if case .ready(let parts) = app.teaser { return parts }
        return nil
    }
    private var lockedCount: Int {
        (parts ?? []).indices.filter { app.teaserLocked($0) }.count
    }
    /// No early reading (it failed, or demo data is missing): show the card meanings instead.
    private var showsMeanings: Bool { app.teaser == nil || app.teaser == .failed }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    OnboardingHeader(eyebrow: name.isEmpty ? "Your reading" : "\(name)'s reading",
                                     title: "Your cards are in.")
                    if showsMeanings {
                        meaningsList
                    } else {
                        spreadRow
                        readingPanel
                    }
                    matchCard
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            OnboardingFooter {
                Button(ctaTitle, action: onNext)
                    .buttonStyle(GoldButtonStyle())
                if let shareImage {
                    ShareLink(item: shareImage,
                              preview: SharePreview("My As Fate Would Have It reading", image: shareImage)) {
                        Label("Share my reading", systemImage: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .task { renderShareImage() }
        .onAppear(perform: trackTeaser)
        .onChange(of: app.teaser) { _, _ in trackTeaser() }
    }

    private var ctaTitle: String {
        if showsMeanings || (parts != nil && lockedCount == 0) { return "Ask \(match.short) about my cards" }
        return "Read \(match.short)'s full reading"
    }

    private func trackTeaser() {
        guard !trackedTeaser, let parts else { return }
        trackedTeaser = true
        Analytics.track(.teaserShown, ["psychic": match.id, "parts": String(parts.count), "locked": String(lockedCount)])
    }

    /// The three cards side by side, named; what they mean comes from the psychic.
    private var spreadRow: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(zip(OnboardingCatalog.positions, spread)), id: \.0) { position, card in
                VStack(spacing: 6) {
                    TarotTile(card: card, revealed: true, compact: true).frame(width: 74)
                    EyebrowText(position)
                    Text(card.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textBright)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    /// The psychic reading the spread: the first message readable, the rest blurred until Fate+.
    private var readingPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                AvatarView(psychic: match, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(match.short)'s reading").font(Theme.display(20)).foregroundStyle(Theme.textBright)
                    Text(parts == nil ? "Reading your cards now" : "Your past, present and future")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
            }
            if let parts {
                ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                    bubble(part, locked: app.teaserLocked(i))
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                if lockedCount > 0 {
                    Label("\(match.short) has \(lockedCount) more \(lockedCount == 1 ? "message" : "messages") about your cards",
                          systemImage: "lock.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.gold)
                }
            } else {
                HStack(spacing: 10) {
                    TypingDots()
                    Text("\(match.short) is reading the signs…")
                        .font(.system(size: 13).italic())
                        .foregroundStyle(Theme.faint)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityElement(children: .combine)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
        .animation(.easeOut(duration: 0.4), value: app.teaser)
    }

    private func bubble(_ text: String, locked: Bool) -> some View {
        Text(text)
            .font(.system(size: 16))
            .foregroundStyle(Theme.text)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .blur(radius: locked ? 6 : 0)
            .overlay {
                if locked { Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(Theme.gold) }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceRaised, in: UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 2, bottomTrailingRadius: 10, topTrailingRadius: 10))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 2, bottomTrailingRadius: 10, topTrailingRadius: 10).stroke(Theme.border, lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(locked ? "Locked message from \(match.short)" : text)
    }

    /// Each card with its traditional meaning, used when the psychic's reading isn't available.
    private var meaningsList: some View {
        VStack(spacing: 10) {
            ForEach(Array(zip(OnboardingCatalog.positions, spread)), id: \.0) { position, card in
                HStack(alignment: .top, spacing: 14) {
                    TarotTile(card: card, revealed: true, compact: true).frame(width: 54)
                    VStack(alignment: .leading, spacing: 4) {
                        EyebrowText(position)
                        Text(card.name).font(Theme.display(19)).foregroundStyle(Theme.textBright)
                        Text(card.meaning)
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .cardSurface()
            }
        }
    }

    private var matchCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            EyebrowText("Your psychic match")
            HStack(spacing: 14) {
                AvatarView(psychic: match, size: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(match.name).font(Theme.display(21)).foregroundStyle(Theme.textBright)
                    Text(match.specialty).font(.system(size: 14)).foregroundStyle(Theme.lilac)
                }
            }
            Text(goal?.matchReason ?? match.tagline)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.gold.opacity(0.5), lineWidth: 1))
    }

    @MainActor private func renderShareImage() {
        let renderer = ImageRenderer(content: ShareCard(spread: spread, match: match, name: name, sign: sign))
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }
}

/// The image people share: their three cards on a story-sized card.
struct ShareCard: View {
    let spread: [TarotCard]
    let match: Psychic
    let name: String
    let sign: String?

    var body: some View {
        VStack(spacing: 22) {
            Wordmark(size: 22)
            VStack(spacing: 6) {
                Text(name.isEmpty ? "My reading" : "\(name)'s reading")
                    .font(Theme.display(30, .medium))
                    .foregroundStyle(Theme.textBright)
                if let sign {
                    Text(sign.uppercased()).font(Theme.eyebrow).tracking(1.6).foregroundStyle(Theme.muted)
                }
            }
            HStack(spacing: 12) {
                ForEach(Array(zip(OnboardingCatalog.positions, spread)), id: \.0) { position, card in
                    VStack(spacing: 8) {
                        TarotTile(card: card, revealed: true).frame(width: 92)
                        Text(position.uppercased()).font(Theme.eyebrow).tracking(1.2).foregroundStyle(Theme.gold)
                    }
                }
            }
            if let future = spread.last {
                Text("“\(future.meaning)”")
                    .font(Theme.display(17))
                    .italic()
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }
            HStack(spacing: 10) {
                AvatarView(psychic: match, size: 34)
                Text("Read by \(match.name)").font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.textSoft)
            }
        }
        .padding(28)
        .frame(width: 360)
        .background(
            LinearGradient(colors: [Theme.surfaceRaised, Theme.bg], startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .light)
    }
}
