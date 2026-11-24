import Foundation

/// Psychics as Psychic Studio describes them, from the reading server (`GET /v1/psychics`).
///
/// The built-in psychics stay in the app; any text set in the studio replaces theirs, field by field.
/// Psychics added in the studio appear once they're switched on there ("Show in the app") and have what the
/// app needs. The list is saved on the phone, so they're there offline and at the next launch.
enum PsychicDirectory {
    struct Entry: Codable {
        let id: String
        let name: String?
        let specialty: String?
        let app: App?
    }

    struct App: Codable {
        var short, tagline, bio, greeting, signLine, welcomeBack, defaultName, sample: String?
        var cardIntro, spreadIntro, ritualButton, ritualIntro, color, typing: String?
        var tags, asks, moods, morningOpenings: [String]?
        var show: Bool?
    }

    private static let file: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("psychics.json")
    }()

    /// Read on the main actor only (views and AppState).
    nonisolated(unsafe) private static var entries: [Entry] = {
        (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }()

    /// Saves the server's list. Returns whether anything changed.
    @discardableResult
    static func update(_ new: [Entry]) -> Bool {
        let safe = new.filter { isSafeID($0.id) }
        guard let data = try? JSONEncoder().encode(safe) else { return false }
        if let old = try? JSONEncoder().encode(entries), old == data { return false }
        entries = safe
        try? data.write(to: file, options: .atomic)
        return true
    }

    static func psychics(builtIn: [Psychic]) -> [Psychic] {
        let builtInIDs = Set(builtIn.map(\.id))
        let byID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let mine = builtIn.map { p in byID[p.id].map { p.applying($0) } ?? p }
        let added = entries.filter { !builtInIDs.contains($0.id) && $0.app?.show == true }.compactMap(Psychic.init(entry:))
        return mine + added
    }

    /// A studio psychic even if it's hidden now, for chats that already exist.
    static func anyPsychic(_ id: String) -> Psychic? {
        entries.first { $0.id == id }.flatMap(Psychic.init(entry:))
    }

    /// Ids name photo files, so only allow what the server itself allows.
    static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 32 && id.allSatisfy { ($0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "-" }
    }
}

private func nonEmpty(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

private func nonEmpty(_ a: [String]?) -> [String]? {
    let list = (a ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    return list.isEmpty ? nil : list
}

private func hexColor(_ s: String?) -> UInt32? {
    guard let s = nonEmpty(s), s.hasPrefix("#"), s.count == 7 else { return nil }
    return UInt32(s.dropFirst(), radix: 16)
}

extension Psychic {
    /// A psychic added in Psychic Studio. Nil until it has what the app needs.
    init?(entry: PsychicDirectory.Entry) {
        guard let app = entry.app, let name = nonEmpty(entry.name),
              let tagline = nonEmpty(app.tagline), let bio = nonEmpty(app.bio),
              let greeting = nonEmpty(app.greeting), let asks = nonEmpty(app.asks) else { return nil }
        let short = nonEmpty(app.short)
            ?? name.replacingOccurrences(of: #"^(Madame|Grandma|Oracle|Auntie|The)\s+"#, with: "", options: .regularExpression)
        self.init(
            id: entry.id, name: name, short: short, imageName: "psychic_\(entry.id)",
            ringHex: hexColor(app.color) ?? 0x8A6F4A,
            specialty: nonEmpty(entry.specialty) ?? "", tagline: tagline, bio: bio, persona: "",
            styles: nonEmpty(app.tags) ?? [], asks: asks,
            defaultName: nonEmpty(app.defaultName) ?? "friend", greeting: greeting,
            signLine: nonEmpty(app.signLine) ?? "A {sign}. I had a feeling.",
            cardIntro: nonEmpty(app.cardIntro) ?? "Let me turn one card for you…",
            love: [], work: [], general: []
        )
        isBuiltIn = false
        apply(app)
    }

    /// This built-in psychic with whatever text Psychic Studio sets.
    func applying(_ entry: PsychicDirectory.Entry) -> Psychic {
        var p = self
        if let name = nonEmpty(entry.name) { p.name = name }
        if let specialty = nonEmpty(entry.specialty) { p.specialty = specialty }
        if let app = entry.app {
            if let v = nonEmpty(app.short) { p.short = v }
            if let v = nonEmpty(app.tagline) { p.tagline = v }
            if let v = nonEmpty(app.bio) { p.bio = v }
            if let v = nonEmpty(app.greeting) { p.greeting = v }
            if let v = nonEmpty(app.signLine) { p.signLine = v }
            if let v = nonEmpty(app.defaultName) { p.defaultName = v }
            if let v = nonEmpty(app.cardIntro) { p.cardIntro = v }
            if let v = nonEmpty(app.asks) { p.asks = v }
            if let v = nonEmpty(app.tags) { p.styles = v }
            if let v = hexColor(app.color) { p.ringHex = v }
            p.apply(app)
        }
        return p
    }

    private mutating func apply(_ app: PsychicDirectory.App) {
        if let v = nonEmpty(app.sample) { sample = v }
        if let v = nonEmpty(app.moods) { moods = v }
        if let v = nonEmpty(app.morningOpenings) { morningOpenings = v }
        if let v = nonEmpty(app.ritualButton) { ritualButton = v }
        if let v = nonEmpty(app.ritualIntro) { ritualIntro = v }
        if let v = nonEmpty(app.spreadIntro) { spreadIntro = v }
        if let v = nonEmpty(app.welcomeBack) { welcomeBack = v }
        if let v = nonEmpty(app.typing) { typing = v }
    }
}
