import SwiftUI

struct ChatView: View {
    @EnvironmentObject var app: AppState
    let psychic: Psychic
    @State private var draft = ""
    @FocusState private var inputFocused: Bool
    /// The open paywall; its id says where it was opened from, for analytics.
    @State private var paywall: SheetSource?

    private var messages: [ChatMessage] { app.threads[psychic.id] ?? [] }
    private var busy: Bool { app.answeringFor != nil }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    Text("Reading started · for fun only")
                        .font(.system(size: 11, weight: .medium))
                        .tracking(1)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.faint)
                        .padding(.vertical, 6)
                    ForEach(Array(messages.enumerated()), id: \.element.id) { i, m in
                        row(i, m)
                    }
                    if app.typingFor == psychic.id {
                        TypingRow(psychic: psychic)
                            .id("typing")
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                app.ensureThread(psychic)
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: messages) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: app.typingFor) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .animation(.easeOut(duration: 0.2), value: app.typingFor)
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            if app.isLimitReached { limitBar } else { composer }
        }
        .sheet(item: $paywall) { item in paywallSheet(item.id) }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            // Shaking the phone shakes Zephyr's crystal ball.
            if psychic.id == "zephyr", !busy { app.performRitual(with: psychic) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button { app.path.append(.profile(psychic.id)) } label: {
                    HStack(spacing: 10) {
                        AvatarView(psychic: psychic, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(psychic.name).font(Theme.display(17)).foregroundStyle(Theme.textBright)
                            HStack(spacing: 5) {
                                OnlineDot(size: 6)
                                Text(app.isLive ? "Live reading" : "Demo mode")
                            }
                            .font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(psychic.name), view profile")
            }
        }
    }

    private func paywallSheet(_ source: String) -> some View {
        PaywallView(psychic: psychic, goal: app.onboardingGoal, lockedReply: source == "lockedReply",
                    name: app.userName.trimmingCharacters(in: .whitespaces), source: source) { paywall = nil }
    }

    @ViewBuilder private func row(_ i: Int, _ m: ChatMessage) -> some View {
        // Like a messaging app: the avatar sits only on the last bubble of a run.
        // The typing bubble carries the avatar while they're still typing.
        let next: ChatMessage? = i + 1 < messages.count ? messages[i + 1] : nil
        let typing = app.typingFor == psychic.id
        let showAvatar: Bool = next.map { $0.role == .user } ?? !typing
        let lastUserID = messages.last(where: { $0.role == .user })?.id
        MessageRow(message: m, psychic: psychic, showAvatar: showAvatar,
                   showSeen: m.id == lastUserID && m.seen == true)
            .id(m.id)
        // Under the last bubble of a locked reply.
        if m.locked == true, next?.locked != true, !typing {
            UnlockReplyRow(psychic: psychic) { paywall = SheetSource(id: "lockedReply") }
                .id("unlock-\(m.id)")
        }
    }

    /// Replaces the composer once today's free messages are used up.
    private var limitBar: some View {
        VStack(spacing: 10) {
            Text("You've used today's \(AppState.freeMessagesPerDay) free messages. More tomorrow, or unlock unlimited readings now.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Unlock unlimited readings") { paywall = SheetSource(id: "limitBar") }
                .buttonStyle(GoldButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
        .background(Theme.bg)
    }

    /// "1 free message left today", shown when it's about to run out.
    @ViewBuilder private var freeHint: some View {
        if !app.isPlus, app.freeMessagesLeft <= 1 {
            Button { paywall = SheetSource(id: "freeHint") } label: {
                Text(app.freeMessagesLeft == 1
                     ? "1 free message left today · **Go unlimited**"
                     : "No free messages left today · your next reply will be locked · **Go unlimited**")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
    }

    private var composer: some View {
        VStack(spacing: 8) {
            freeHint
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    let style = Rituals.style(for: psychic.id)
                    Button { app.performRitual(with: psychic) } label: {
                        Label(style.button, systemImage: style.buttonSymbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.onGold)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .background(Theme.gold, in: Capsule())
                    }
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)

                    ForEach(psychic.asks, id: \.self) { chip in
                        Button(chip) { app.send(chip, to: psychic) }
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 40)
                            .background(Theme.surface, in: Capsule())
                            .overlay(Capsule().stroke(Theme.borderStrong, lineWidth: 1))
                            .disabled(busy)
                            .opacity(busy ? 0.5 : 1)
                    }
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 10) {
                TextField("", text: $draft, prompt: Text("Ask the spirits anything…").foregroundColor(Theme.faint), axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .submitLabel(.send)
                    .onSubmit(sendDraft)
                    .padding(.horizontal, 18).padding(.vertical, 13)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.borderStrong, lineWidth: 1))
                    .foregroundStyle(Theme.textBright)
                    .accessibilityLabel("Ask your question")

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.onGold)
                        .frame(width: 48, height: 48)
                        .background(Theme.gold, in: Circle())
                }
                .disabled(!canSend)
                .opacity(canSend ? 1 : 0.45)
                .accessibilityLabel("Send question")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
        .padding(.top, 8)
        .background(Theme.bg)
    }

    private var canSend: Bool {
        !busy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendDraft() {
        guard canSend else { return }
        app.send(draft, to: psychic)
        draft = ""
    }
}

/// Lets `.sheet(item:)` take a plain string.
private struct SheetSource: Identifiable { let id: String }

/// Shown under a locked reply.
struct UnlockReplyRow: View {
    let psychic: Psychic
    let unlock: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 30, height: 1)
            Button(action: unlock) {
                Label("Unlock \(psychic.short)'s reply", systemImage: "lock.open.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(Theme.gold, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .transition(.opacity)
    }
}

/// "Selene is typing" bubble.
struct TypingRow: View {
    let psychic: Psychic
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            AvatarView(psychic: psychic, size: 30)
            TypingDots()
                .padding(.horizontal, 16).padding(.vertical, 15)
                .background(Theme.surfaceRaised, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18).stroke(Theme.border, lineWidth: 1))
            Spacer(minLength: 40)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(psychic.short) is typing")
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let psychic: Psychic
    var showAvatar = true
    var showSeen = false

    var body: some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 3) {
                HStack {
                    Spacer(minLength: 60)
                    Text(message.text)
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.onGold)
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .background(Theme.gold, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18))
                }
                if showSeen {
                    Text("Seen")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.faint)
                        .padding(.trailing, 4)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: showSeen)
        case .psychic:
            HStack(alignment: .bottom, spacing: 8) {
                if showAvatar {
                    AvatarView(psychic: psychic, size: 30)
                } else {
                    Color.clear.frame(width: 30, height: 30)
                }
                Group {
                    if message.text.isEmpty {
                        HStack(spacing: 10) {
                            TypingDots()
                            Text("\(psychic.short) is reading the signs…")
                                .font(.system(size: 13).italic())
                                .foregroundStyle(Theme.faint)
                        }
                        .accessibilityElement(children: .combine)
                    } else if message.locked == true {
                        // The real reply, blurred until Moonlit+ is unlocked.
                        Text(message.text)
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.text)
                            .lineSpacing(2)
                            .blur(radius: 6)
                            .overlay(Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(Theme.gold))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Locked reply from \(psychic.short)")
                    } else {
                        Text(message.text)
                            .font(.system(size: 16))
                            .foregroundStyle(message.isError ? Theme.muted : Theme.text)
                            .italic(message.isError)
                            .lineSpacing(2)
                            .textSelection(.enabled)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Theme.surfaceRaised, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 4, bottomTrailingRadius: 18, topTrailingRadius: 18).stroke(Theme.border, lineWidth: 1))
                Spacer(minLength: 40)
            }
        case .card:
            if let card = message.card {
                HStack(alignment: .bottom, spacing: 8) {
                    AvatarView(psychic: psychic, size: 30)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 14) {
                            MiniTarotCard(numeral: card.numeral, width: 52)
                            VStack(alignment: .leading, spacing: 4) {
                                EyebrowText("You drew")
                                Text(card.name).font(Theme.display(24)).foregroundStyle(Theme.gold)
                            }
                        }
                        Text(card.meaning).font(.system(size: 15)).foregroundStyle(Theme.text)
                    }
                    .padding(14)
                    .frame(width: 260, alignment: .leading)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold, lineWidth: 1))
                    Spacer(minLength: 0)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        case .ritual:
            if let ritual = message.ritual {
                HStack(alignment: .bottom, spacing: 8) {
                    AvatarView(psychic: psychic, size: 30)
                    RitualCardView(ritual: ritual, accent: Color(hex: psychic.ringHex))
                    Spacer(minLength: 0)
                }
                .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
    }
}

/// The result of a psychic's ritual: the moon, a forecast, tea leaves, a vision or a playing card.
struct RitualCardView: View {
    let ritual: Ritual
    let accent: Color
    @State private var shown = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: ritual.symbol)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 56, height: 56)
                    .background(accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.6), lineWidth: 1))
                    .scaleEffect(shown ? 1 : 0.6)
                    .rotationEffect(.degrees(shown ? 0 : -20))
                VStack(alignment: .leading, spacing: 4) {
                    EyebrowText(ritual.eyebrow)
                    Text(ritual.title)
                        .font(Theme.display(22))
                        .foregroundStyle(Theme.gold)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Text(ritual.detail)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 270, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .onAppear { withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) { shown = true } }
    }
}

extension Notification.Name {
    static let deviceDidShake = Notification.Name("deviceDidShake")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { NotificationCenter.default.post(name: .deviceDidShake, object: nil) }
        super.motionEnded(motion, with: event)
    }
}
