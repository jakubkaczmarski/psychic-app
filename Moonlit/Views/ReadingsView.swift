import SwiftUI

struct ReadingsView: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your readings").font(Theme.display(38, .medium)).foregroundStyle(Theme.textBright)
                    Text("Every conversation with the circle, saved on this phone.")
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                }

                if app.readings.isEmpty {
                    VStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .foregroundStyle(Color(hex: 0x5C4C9E))
                            .frame(width: 72, height: 108)
                            .overlay(Image(systemName: "sparkle").font(.system(size: 26)).foregroundStyle(Theme.faint))
                        Text("No readings yet").font(Theme.display(24)).foregroundStyle(Theme.textBright)
                        Text("Ask a psychic your first question and the reading will be kept here.")
                            .font(.system(size: 15)).foregroundStyle(Theme.muted)
                            .multilineTextAlignment(.center)
                        Button("Find a psychic") { app.path.removeAll() }
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 24).frame(minHeight: 48)
                            .overlay(Capsule().stroke(Theme.gold, lineWidth: 1))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                } else {
                    ForEach(app.readings, id: \.psychic.id) { entry in
                        NavigationLink(value: Route.chat(entry.psychic.id)) {
                            ReadingRow(psychic: entry.psychic, messages: entry.messages)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(Theme.bg)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.bg, for: .navigationBar)
    }
}

private struct ReadingRow: View {
    let psychic: Psychic
    let messages: [ChatMessage]

    private var questions: Int { messages.filter { $0.role == .user }.count }
    private var preview: String {
        guard let last = messages.last(where: { !$0.text.isEmpty }) else { return "" }
        if last.role == .card, let card = last.card { return "Drew \(card.name)" }
        return last.text
    }

    var body: some View {
        HStack(spacing: 14) {
            AvatarView(psychic: psychic, size: 54)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(psychic.name).font(Theme.display(19)).foregroundStyle(Theme.textBright)
                    Spacer()
                    Text("\(questions) \(questions == 1 ? "question" : "questions")")
                        .font(.system(size: 12)).foregroundStyle(Theme.faint)
                }
                Text(preview).font(.system(size: 14)).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }
        .padding(14)
        .cardSurface()
    }
}
