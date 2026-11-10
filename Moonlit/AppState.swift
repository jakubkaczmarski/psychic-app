import SwiftUI

enum Route: Hashable {
    case profile(String)
    case chat(String)
    case readings
}

@MainActor
final class AppState: ObservableObject {
    @Published var userName: String { didSet { defaults.set(userName, forKey: "userName"); nameChanged() } }

    /// Morning messages include the name; rewrite them once typing has paused.
    private var nameDebounce: Task<Void, Never>?
    private func nameChanged() {
        guard morningMessagesOn else { return }
        nameDebounce?.cancel()
        nameDebounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.refreshMorningMessages()
        }
    }
    @Published var sign: String? { didSet { defaults.set(sign, forKey: "sign") } }
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }
    @Published var threads: [String: [ChatMessage]] { didSet { saveThreads() } }
    @Published var answeringFor: String?
    @Published var path: [Route] = []
    /// Where readings come from. Empty means demo mode (pre-written replies).
    @Published var serverURL: String { didSet { defaults.set(serverURL, forKey: "serverURL"); serverOnline = nil } }
    /// nil = not checked yet.
    @Published var serverOnline: Bool?

    /// Your psychic: reads your card of the day and sends morning messages.
    @Published var matchedPsychicID: String {
        didSet { defaults.set(matchedPsychicID, forKey: "matchedPsychic"); refreshMorningMessages() }
    }
    /// Day (see `Daily.dayKey`) the card of the day was last revealed, and the streak up to that day.
    @Published private(set) var dailyRevealDay: String? { didSet { defaults.set(dailyRevealDay, forKey: "dailyRevealDay") } }
    @Published private(set) var dailyStreakCount: Int { didSet { defaults.set(dailyStreakCount, forKey: "dailyStreak") } }
    /// The user turned on morning messages (iOS permission is checked separately).
    @Published var morningMessagesOn: Bool {
        didSet { defaults.set(morningMessagesOn, forKey: "morningMessagesOn"); refreshMorningMessages() }
    }
    /// The user said "Not now" to the morning-message prompt on the home screen.
    @Published var morningPromptDismissed: Bool { didSet { defaults.set(morningPromptDismissed, forKey: "morningPromptDismissed") } }

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
        let goal = defaults.string(forKey: "onboardingGoal")
        matchedPsychicID = defaults.string(forKey: "matchedPsychic")
            ?? OnboardingCatalog.goals.first { $0.id == goal }?.psychicID
            ?? "selene"
        dailyRevealDay = defaults.string(forKey: "dailyRevealDay")
        dailyStreakCount = defaults.integer(forKey: "dailyStreak")
        morningMessagesOn = defaults.bool(forKey: "morningMessagesOn")
        morningPromptDismissed = defaults.bool(forKey: "morningPromptDismissed")
    }

    // MARK: Daily: card of the day, streak, morning messages

    var matchedPsychic: Psychic { Catalog.psychic(matchedPsychicID) }

    var todaysCard: TarotCard { Daily.card(seed: deviceID) }

    /// Makes the daily card differ between installs.
    var dailySeed: String { deviceID }

    var revealedToday: Bool { dailyRevealDay == Daily.dayKey() }

    /// Days in a row the card was revealed; 0 once a day is missed.
    var dailyStreak: Int {
        guard let day = dailyRevealDay else { return 0 }
        return day == Daily.dayKey() || day == Daily.dayKey(daysFrom: Date(), -1) ? dailyStreakCount : 0
    }

    func revealDailyCard() {
        guard !revealedToday else { return }
        dailyStreakCount = dailyRevealDay == Daily.dayKey(daysFrom: Date(), -1) ? dailyStreakCount + 1 : 1
        dailyRevealDay = Daily.dayKey()
    }

    /// Opens your psychic's chat and asks about today's card.
    func askAboutDailyCard() {
        revealDailyCard()
        guard onboarded else { return }
        let card = todaysCard
        path = []
        openChat(matchedPsychic, asking: "My card of the day is \(card.name). What does it mean for me today?",
                 note: Daily.cardNote(card))
    }

    /// Asks iOS for permission and, if granted, schedules the next week of messages.
    func enableMorningMessages() async -> Bool {
        let granted = await MorningMessages.requestPermission()
        morningPromptDismissed = true
        morningMessagesOn = granted
        return granted
    }

    /// Rewrites the scheduled messages, e.g. after a name or psychic change. Safe to call often.
    func refreshMorningMessages() {
        guard morningMessagesOn else { MorningMessages.cancelAll(); return }
        let psychic = matchedPsychic
        let name = userName.trimmingCharacters(in: .whitespaces)
        let seed = deviceID
        Task { await MorningMessages.schedule(psychic: psychic, name: name, seed: seed) }
    }

    #if DEBUG
    func sendTestMorningMessage() {
        let psychic = matchedPsychic, name = userName.trimmingCharacters(in: .whitespaces), seed = deviceID
        Task {
            if !(await MorningMessages.isAuthorized()) { _ = await MorningMessages.requestPermission() }
            await MorningMessages.sendTest(psychic: psychic, name: name, seed: seed)
        }
    }
    #endif

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
        ensureThread(p)
        if path.last != .chat(p.id) { path.append(.chat(p.id)) }
        if let question { send(question, to: p, note: note) }
    }

    // MARK: Onboarding

    /// Saves the onboarding answers, enters the app and, if given, opens the first reading.
    func completeOnboarding(goal: String?, pains: [String], match: Psychic, question: String?, note: String?) {
        defaults.set(goal, forKey: "onboardingGoal")
        defaults.set(pains, forKey: "onboardingPains")
        matchedPsychicID = match.id
        path = []
        onboarded = true
        if let question { openChat(match, asking: question, note: note) }
    }

    func replayOnboarding() {
        path = []
        onboarded = false
    }

    /// A gap this long between messages starts a new visit.
    static let visitGap: TimeInterval = 6 * 60 * 60

    /// Starts a thread with a greeting, or greets the user again when they come back after a while.
    func ensureThread(_ p: Psychic) {
        guard let thread = threads[p.id], !thread.isEmpty else {
            threads[p.id] = [ChatMessage(role: .psychic, text: greeting(for: p))]
            return
        }
        // Messages saved before dates existed count as old.
        let last = thread.last?.date ?? .distantPast
        if Date().timeIntervalSince(last) > Self.visitGap {
            let name = userName.trimmingCharacters(in: .whitespaces)
            let text = Rituals.style(for: p.id).welcomeBack
                .replacingOccurrences(of: "{name}", with: name.isEmpty ? p.defaultName.capitalized : name)
            threads[p.id, default: []].append(ChatMessage(role: .psychic, text: text, startsVisit: true))
        }
    }

    /// Sends a question. `note` is extra context for Claude that isn't shown in the bubble.
    /// With `ritual` (or a question asking for a card), the psychic performs their ritual first.
    func send(_ raw: String, to p: Psychic, note: String? = nil, ritual: Bool = false) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, answeringFor == nil else { return }

        var user = ChatMessage(role: .user, text: text, apiNote: note)
        var performed: Ritual?
        if note == nil, ritual || Self.wantsCard(text) {
            let result = Rituals.perform(for: p.id, sign: sign)
            performed = result.ritual
            user.apiNote = result.note
        }
        threads[p.id, default: []].append(user)
        if let performed {
            threads[p.id, default: []].append(ChatMessage(role: .psychic, text: Rituals.style(for: p.id).intro))
            threads[p.id, default: []].append(ChatMessage(role: .ritual, text: performed.detail, ritual: performed))
        }
        respond(as: p, to: text, ritual: performed)
    }

    func performRitual(with p: Psychic) {
        send(Rituals.style(for: p.id).button, to: p, ritual: true)
    }

    private func respond(as p: Psychic, to question: String, ritual: Ritual?) {
        let reply = ChatMessage(role: .psychic, text: "")
        let replyID = reply.id
        let history = apiTurns(for: p)
        let memory = memoryNotes(for: p)
        threads[p.id, default: []].append(reply)
        answeringFor = p.id

        let name = userName.trimmingCharacters(in: .whitespaces)
        let sign = sign

        Task {
            defer { answeringFor = nil }
            guard let client else {
                try? await Task.sleep(nanoseconds: 1_300_000_000)
                update(p.id, replyID) { $0.text = self.demoReply(p, question, ritual: ritual != nil) }
                return
            }
            do {
                try await client.stream(psychicID: p.id, userName: name, sign: sign, turns: history, memory: memory,
                                        mood: Daily.mood(for: p.id)) { [weak self] delta in
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

    /// Index where the current visit starts; everything before it is an earlier visit.
    private func visitStart(in thread: [ChatMessage]) -> Int {
        thread.lastIndex(where: { $0.startsVisit == true }) ?? 0
    }

    /// Short notes about earlier visits, so the psychic can remember them. Most recent last.
    private func memoryNotes(for p: Psychic) -> [String] {
        let thread = threads[p.id] ?? []
        let earlier = thread[..<visitStart(in: thread)]
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        var notes: [String] = []
        for (i, m) in earlier.enumerated() where m.role == .user && !m.isError {
            var note = ""
            if let date = m.date { note += formatter.string(from: date) + ": " }
            note += "asked \"\(m.text.prefix(140))\""
            // Include the ritual result that answered this question, if there was one.
            if let ritual = earlier[(i + 1)...].prefix(while: { $0.role != .user }).first(where: { $0.role == .ritual })?.ritual {
                note += " (ritual result: \(ritual.title))"
            }
            notes.append(note)
        }
        return Array(notes.suffix(8))
    }

    /// Converts the current visit into alternating user/assistant turns that start and end on a user turn.
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
        let all = threads[p.id] ?? []
        let thread = Array(all[visitStart(in: all)...].suffix(30))
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
            case .card, .ritual: break
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

    #if DEBUG
    /// Testing aid: pretends every saved message is a day older, so the next visit triggers memory.
    func ageReadingsByOneDay() {
        threads = threads.mapValues { $0.map { m in
            var m = m
            m.date = (m.date ?? Date()).addingTimeInterval(-86_400)
            return m
        } }
    }
    #endif

    private func demoReply(_ p: Psychic, _ text: String, ritual: Bool) -> String {
        let t = text.lowercased()
        if ritual { return "This card is speaking straight to you. Sit with it tonight. (Demo reply: set a server address in Settings for live readings.)" }
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
