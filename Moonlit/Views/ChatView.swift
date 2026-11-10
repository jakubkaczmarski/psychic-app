import SwiftUI

struct ChatView: View {
    @EnvironmentObject var app: AppState
    let psychic: Psychic
    @State private var draft = ""
    @FocusState private var inputFocused: Bool

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
                    ForEach(messages) { m in
                        MessageRow(message: m, psychic: psychic).id(m.id)
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
        }
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) { composer }
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

    private var composer: some View {
        VStack(spacing: 8) {
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

struct MessageRow: View {
    let message: ChatMessage
    let psychic: Psychic

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(message.text)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.onGold)
                    .padding(.horizontal, 14).padding(.vertical, 11)
                    .background(Theme.gold, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 18, bottomTrailingRadius: 4, topTrailingRadius: 18))
            }
        case .psychic:
            HStack(alignment: .bottom, spacing: 8) {
                AvatarView(psychic: psychic, size: 30)
                Group {
                    if message.text.isEmpty {
                        HStack(spacing: 10) {
                            TypingDots()
                            Text("\(psychic.short) is reading the signs…")
                                .font(.system(size: 13).italic())
                                .foregroundStyle(Theme.faint)
                        }
                        .accessibilityElement(children: .combine)
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
