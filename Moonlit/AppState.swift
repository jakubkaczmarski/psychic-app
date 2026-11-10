import SwiftUI

enum Route: Hashable {
    case profile(String)
    case chat(String)
    case readings
}

@MainActor
final class AppState: ObservableObject {
    @Published var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    @Published var sign: String? { didSet { defaults.set(sign, forKey: "sign") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    @Published var threads: [String: [ChatMessage]] { didSet { saveThreads() } }
    @Published var answeringFor: String?
    @Published var path: [Route] = []
    /// Where readings come from. Empty means demo mode (pre-written replies).
    @Published var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL"); serverOnline = nil } }
    /// nil = not checked yet.
    @Published var serverOnline: Bool?

    private let defaults = UserDefaults.standard
    private let deviceID: String
    private var demoTurn: [String: Int] = [:]

    var isLive: Bool { client != nil }

    private var client: ReadingClient? {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.scheme != nil else { return nil }
        return ReadingClient(baseURL: url, deviceID: deviceID)
    }

    init() {
        userName = defaults.string(forKey: "userName") ?? ""
        sign = defaults.string(forKey: "sign")
        onboarded = defaults.bool(forKey: "onboarded")
        if let data = defaults.data(forKey: "threads"),
           let saved = try? JSONDecoder().decode([String: [ChatMessage]].self, from: data) {
            threads = saved
        } else {
            threads = [:]
        }
        serverURL = defaults.string(forKey: "serverURL") ?? ReadingClient.defaultServerURL
        if let saved = defaults.string(forKey: "deviceID") {
            deviceID = saved
        } else {
            deviceID = UUID().uuidString
            defaults.set(deviceID, forKey: "deviceID")
        }
    }

    // MARK: Server

    func checkServer() async {
        guard let client else { serverOnline = nil; return }
        serverOnline = await client.health()
    }

    // MARK: Readings

    var readings: [(psychic: Psychic, messages: [ChatMessage])] {
        Catalog.psychics.compactMap { p in
            let thread = threads[p.id] ?? []
            return thread.contains { $0.role == .user } ? (p, thread) : nil
        }
    }

    func clearReadings() {
        threads = [:]
    }

    func greeting(for p: Psychic) -> String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        var text = p.greeting.replacingOccurrences(of: "{name}", with: name.isEmpty ? p.defaultName : name)
        if let sign { text += " " + p.signLine.replacingOccurrences(of: "{sign}", with: sign) }
        return text
    }

    func openChat(_ p: Psychic, asking question: String? = nil, note: String? = nil) {
        if threads[p.id]?.isEmpty ?? true {
            threads[p.id] = [ChatMessage(role: .psychic, text: greeting(for: p))]
        }
        if path.last != .chat(p.id) { path.append(.chat(p.id)) }
        if let question { send(question, to: p, note: note) }
    }

    // MARK: Onboarding

    /// Saves the onboarding answers, enters the app and, if given, opens the first reading.
    func completeOnboarding(goal: String?, pains: [String], match: Psychic, question: String?, note: String?) {
        defaults.set(goal, forKey: "onboardingGoal")
        defaults.set(pains, forKey: "onboardingPains")
        path = []
        onboarded = true
        if let question { openChat(match, asking: question, note: note) }
    }

    func replayOnboarding() {
        path = []
        onboarded = false
    }

    func ensureThread(_ p: Psychic) {
        if threads[p.id]?.isEmpty ?? true {
            threads[p.id] = [ChatMessage(role: .psychic, text: greeting(for: p))]
        }
    }

    /// `note` is extra context for Claude that isn't shown in the bubble; when set, no card is drawn.
    func send(_ raw: String, to p: Psychic, note: String? = nil) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, answeringFor == nil else { return }

        var drawn: TarotCard?
        var user = ChatMessage(role: .user, text: text, apiNote: note)
        if note == nil, Self.wantsCard(text) {
            let card = Catalog.deck.randomElement()!
            drawn = card
            user.apiNote = "[The app just drew a tarot card for this question: \(card.name) (\(card.numeral)). Traditional meaning: \(card.meaning) Interpret this card for the user in your own voice.]"
        }
        threads[p.id, default: []].append(user)
        if let drawn {
            threads[p.id, default: []].append(ChatMessage(role: .psychic, text: p.cardIntro))
            threads[p.id, default: []].append(ChatMessage(role: .card, text: drawn.meaning, card: drawn))
        }
        respond(as: p, to: text)
    }

    private func respond(as p: Psychic, to question: String) {
        let reply = ChatMessage(role: .psychic, text: "")
        let replyID = reply.id
        let history = apiTurns(for: p)
        threads[p.id, default: []].append(reply)
        answeringFor = p.id

        let name = userName.trimmingCharacters(in: .whitespaces)
        let sign = sign

        Task {
            defer { answeringFor = nil }
            guard let client else {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                update(p.id, replyID) { $0.text = self.demoReply(p, question) }
                return
            }
            do {
                try await client.stream(psychicID: p.id, userName: name, sign: sign, turns: history) { [weak self] delta in
                    self?.update(p.id, replyID) { $0.text += delta }
                }
                serverOnline = true
                update(p.id, replyID) { msg in
                    msg.text = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if msg.text.isEmpty { msg.text = "…the vision faded. Ask me again?"; msg.isError = true }
                }
            } catch {
                update(p.id, replyID) { msg in
                    let partial = msg.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    let note = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    msg.text = partial.isEmpty ? note : partial + "\n\n(" + note + ")"
                    msg.isError = true
                }
            }
        }
    }

    private func update(_ psychicID: String, _ messageID: UUID, _ change: (inout ChatMessage) -> Void) {
        guard var thread = threads[psychicID], let i = thread.firstIndex(where: { $0.id == messageID }) else { return }
        change(&thread[i])
        threads[psychicID] = thread
    }

    // MARK: Conversation sent to the server
    // The psychic's instructions live on the server; the app sends only the chat.

    /// Converts the visible thread into alternating user/assistant turns that start and end on a user turn.
    private func apiTurns(for p: Psychic) -> [ReadingClient.Turn] {
        var turns: [ReadingClient.Turn] = []
        func push(_ role: String, _ text: String) {
            guard !text.isEmpty else { return }
            if let last = turns.last, last.role == role {
                turns[turns.count - 1] = .init(role: role, content: last.content + "\n\n" + text)
            } else {
                turns.append(.init(role: role, content: text))
            }
        }
        let thread = Array((threads[p.id] ?? []).suffix(30))
        for (i, m) in thread.enumerated() where !m.isError {
            // Drop a question whose reply failed, so it isn't answered again later.
            if m.role == .user,
               let reply = thread[(i + 1)...].first(where: { $0.role == .psychic && !$0.text.isEmpty }),
               reply.isError,
               !thread[(i + 1)...].prefix(while: { $0.id != reply.id }).contains(where: { $0.role == .user }) {
                continue
            }
            switch m.role {
            case .user: push("user", m.apiNote.map { m.text + "\n\n" + $0 } ?? m.text)
            case .psychic: push("assistant", m.text)
            case .card: break
            }
        }
        // Lines shown after the question (like "Pulling one card…") aren't part of what Claude answers.
        while turns.last?.role == "assistant" { turns.removeLast() }
        if turns.first?.role == "assistant" {
            turns.insert(.init(role: "user", content: "(The user opens a reading with you.)"), at: 0)
        }
        return turns
    }

    // MARK: Demo mode

    static func wantsCard(_ text: String) -> Bool {
        let t = text.lowercased()
        return t.contains("tarot") || t.contains("draw") || t.contains(" card")
    }

    private func demoReply(_ p: Psychic, _ text: String) -> String {
        let t = text.lowercased()
        if Self.wantsCard(text) { return "This card is speaking straight to you. Sit with it tonight. (Demo reply: set a server address in Settings for live readings.)" }
        let pool: [String]
        let topic: String
        if ["love", "crush", "date", "partner", "relationship", "heart", " ex", "the one", "marr"].contains(where: t.contains) {
            pool = p.love; topic = "love"
        } else if ["job", "work", "career", "boss", "money", "raise", "quit", "project", "business"].contains(where: t.contains) {
            pool = p.work; topic = "work"
        } else {
            pool = p.general; topic = "general"
        }
        let key = p.id + topic
        let n = demoTurn[key, default: 0]
        demoTurn[key] = n + 1
        return pool[n % pool.count]
    }

    // MARK: Persistence

    private func saveThreads() {
        // Keep the store small: never persist an in-progress (empty) reply.
        let clean = threads.mapValues { $0.filter { !($0.role == .psychic && $0.text.isEmpty) } }
        if let data = try? JSONEncoder().encode(clean) { defaults.set(data, forKey: "threads") }
    }
}
