import SwiftUI

// MARK: - Content

struct OnboardingGoal: Identifiable, Hashable {
    let id: String
    let emoji: String
    let label: String
    /// Used in sentences: "What do they say about {topic}?"
    let topic: String
    /// The psychic best suited to this goal.
    let psychicID: String
    /// Why that psychic was picked, shown on the result screen.
    let matchReason: String
}

struct OnboardingPain: Identifiable, Hashable {
    let id: String
    let emoji: String
    let label: String
}

enum OnboardingCatalog {
    static let goals: [OnboardingGoal] = [
        .init(id: "love", emoji: "💘", label: "Love & relationships", topic: "my love life", psychicID: "selene",
              matchReason: "Matters of the heart are Selene's whole world. She reads the moon, and your texts."),
        .init(id: "work", emoji: "💼", label: "Work & money", topic: "my work life", psychicID: "kaz",
              matchReason: "Kaz reads careers like a quarterly report. Blunt, fast, and weirdly useful."),
        .init(id: "decision", emoji: "🔀", label: "A big decision", topic: "the decision I'm facing", psychicID: "ivy",
              matchReason: "Grandma Ivy has talked half her town through big choices, one cup of tea at a time."),
        .init(id: "family", emoji: "🏡", label: "Family & friends", topic: "the people close to me", psychicID: "mirela",
              matchReason: "Mirela reads family the way she reads cards: with love and total honesty."),
        .init(id: "self", emoji: "🌱", label: "Figuring out what I want", topic: "where I'm headed", psychicID: "selene",
              matchReason: "Selene believes every heart has a tide. She'll help you find which way yours is pulling."),
        .init(id: "fun", emoji: "✨", label: "Just curious, for fun", topic: "the week ahead", psychicID: "zephyr",
              matchReason: "Zephyr sees everything and explains nothing. The most fun you'll have with a crystal ball."),
    ]

    static let pains: [OnboardingPain] = [
        .init(id: "overthink", emoji: "🌀", label: "I overthink everything"),
        .init(id: "signals", emoji: "📱", label: "Someone's sending mixed signals"),
        .init(id: "noone", emoji: "🤐", label: "No one I can really ask"),
        .init(id: "wrong", emoji: "😬", label: "Scared of choosing wrong"),
        .init(id: "unsure", emoji: "💭", label: "I don't know what I want"),
        .init(id: "repeat", emoji: "🔁", label: "The same thing keeps happening"),
    ]

    static let positions = ["Past", "Present", "Future"]
}

// MARK: - Flow

private enum OnboardingStep: Int {
    case welcome, goal, pains, you, processing, draw, result, paywall

    /// Steps that show the progress bar, in order.
    static let progressSteps: [OnboardingStep] = [.goal, .pains, .you, .processing, .draw, .result]
}

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var step: OnboardingStep = .welcome
    @State private var forward = true
    @State private var goalID: String?
    @State private var pains: Set<String> = []
    @State private var spread: [TarotCard] = []

    private var goal: OnboardingGoal? { OnboardingCatalog.goals.first { $0.id == goalID } }
    private var match: Psychic { Catalog.psychic(goal?.psychicID ?? "zephyr") }
    private var firstName: String { app.userName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(spacing: 0) {
            if let index = OnboardingStep.progressSteps.firstIndex(of: step) {
                topBar(progress: Double(index + 1) / Double(OnboardingStep.progressSteps.count))
            }
            ZStack {
                screen
                    .id(step)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .background(Theme.bg.ignoresSafeArea())
    }

    @ViewBuilder private var screen: some View {
        switch step {
        case .welcome:
            WelcomeStep { go(.goal) }
        case .goal:
            GoalStep(selection: $goalID) { go(.pains) }
        case .pains:
            PainsStep(selection: $pains) { go(.you) }
        case .you:
            YouStep { go(.processing) }
        case .processing:
            ProcessingStep(name: firstName) { go(.draw) }
        case .draw:
            DrawStep { cards in
                spread = cards
                go(.result)
            }
        case .result:
            ResultStep(spread: spread, goal: goal, match: match, name: firstName, sign: app.sign) { go(.paywall) }
        case .paywall:
            PaywallView(psychic: match) { finish() }
        }
    }

    private func topBar(progress: Double) -> some View {
        HStack(spacing: 14) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .frame(width: 44, height: 44)
            }
            .disabled(!canGoBack)
            .opacity(canGoBack ? 1 : 0)
            .accessibilityLabel("Back")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surfaceRaised)
                    Capsule().fill(Theme.gold).frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 6)
            .accessibilityElement()
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(progress * 100)) percent")

            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .animation(.easeInOut(duration: 0.35), value: progress)
    }

    private var canGoBack: Bool {
        [.goal, .pains, .you, .draw].contains(step)
    }

    private func back() {
        switch step {
        case .goal: go(.welcome)
        case .pains: go(.goal)
        case .you: go(.pains)
        case .draw: go(.you)
        default: break
        }
    }

    private func go(_ next: OnboardingStep) {
        forward = next.rawValue > step.rawValue
        withAnimation(.easeInOut(duration: 0.35)) { step = next }
    }

    /// Leaves onboarding and opens a reading of the spread with the matched psychic.
    private func finish() {
        let painLabels = OnboardingCatalog.pains.filter { pains.contains($0.id) }.map(\.label)
        var question: String?
        var note: String?
        if spread.count == 3 {
            let names = spread.map(\.name)
            question = "I just pulled \(names[0]), \(names[1]) and \(names[2]) for my past, present and future. What do they say about \(goal?.topic ?? "the week ahead")?"
            var lines = ["[During onboarding the user pulled a three-card spread in the app:"]
            for (position, card) in zip(OnboardingCatalog.positions, spread) {
                lines.append("\(position): \(card.name) (\(card.numeral)). Traditional meaning: \(card.meaning)")
            }
            if let goal { lines.append("What's on their mind: \(goal.label).") }
            if !painLabels.isEmpty { lines.append("What's making it hard: \(painLabels.joined(separator: "; ")).") }
            lines.append("Read the spread for them in your own voice, one card at a time, then tie it together.]")
            note = lines.joined(separator: "\n")
        }
        app.completeOnboarding(goal: goalID, pains: Array(pains), match: match, question: question, note: note)
    }
}

// MARK: - Shared pieces

struct OnboardingHeader: View {
    var eyebrow: String?
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let eyebrow { EyebrowText(eyebrow) }
            Text(title)
                .font(Theme.display(32, .medium))
                .foregroundStyle(Theme.textBright)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OptionRow: View {
    let emoji: String
    let label: String
    let selected: Bool
    var multi = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(emoji).font(.system(size: 24))
                Text(label)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.textBright)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if multi {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 22))
                        .foregroundStyle(selected ? Theme.gold : Theme.borderStrong)
                } else if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.gold)
                }
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(selected ? Color(hex: 0x2A2350) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(selected ? Theme.gold : Theme.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: selected)
    }
}

/// Bottom bar holding a step's main button.
struct OnboardingFooter<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(spacing: 4) { content }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(Theme.bg)
    }
}
