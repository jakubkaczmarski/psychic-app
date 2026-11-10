import Foundation

/// Everything that changes once a day: the card of the day, each psychic's mood,
/// and the morning message in your psychic's voice.
/// All of it is worked out from the date (and the install's ID), so it is the same
/// all day, needs no server, and can be written ahead for notifications.
enum Daily {
    /// "2026-11-10" in the user's time zone.
    static func dayKey(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func dayKey(daysFrom date: Date, _ offset: Int) -> String {
        dayKey(Calendar.current.date(byAdding: .day, value: offset, to: date) ?? date)
    }

    /// Stable hash (FNV-1a); Swift's own hashValue changes between launches.
    static func stableHash(_ s: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }

    private static func pick<T>(_ items: [T], _ key: String) -> T {
        items[Int(stableHash(key) % UInt64(items.count))]
    }

    // MARK: Card of the day

    /// The same card all day for this install; different installs get different cards.
    static func card(on date: Date = Date(), seed: String) -> TarotCard {
        pick(Catalog.deck, "card|\(seed)|\(dayKey(date))")
    }

    /// Note sent to Claude when the user asks about their card of the day.
    static func cardNote(_ card: TarotCard) -> String {
        "[This is the user's card of the day in the app: \(card.name) (\(card.numeral)). Traditional meaning: \(card.meaning) Read what it means for their day in your own voice.]"
    }

    // MARK: Moods

    private static let moods: [String: [String]] = [
        "selene": ["Dreamy: the moon kept her up", "Sentimental, rereading old letters", "Glowing after a long bath",
                   "Feeling the tide turn", "Wistful, a candle per question", "Romantic weather, all day"],
        "kaz": ["Mercury retrograde. Calendar is chaos", "Bullish. Third espresso", "In back-to-back meetings with Saturn",
                "Rebranding his whiteboard", "Q4 energy, no small talk", "Mildly smug: a forecast came true"],
        "ivy": ["Baking for the whole street", "Biscuit is on her lap, so she's staying put", "Knitting through the readings",
                "Gardening, mud on her slippers", "Chatty: the neighbours had news", "Cosy, second pot of tea"],
        "zephyr": ["The crystal ball is buffering", "Saw a pigeon wearing a hat. Shaken", "Running on oat lattes",
                   "Cosmic static, very sparkly", "Rearranging the laundromat portal", "In their main-character era"],
        "mirela": ["Busy: a niece is getting engaged", "Shuffling a brand-new deck", "Cooking for twelve, reading for you",
                   "Sharp today. No one fools her", "Missing her grandmother Lela", "Celebrating, the cards were kind"],
    ]

    static func mood(for psychicID: String, on date: Date = Date()) -> String {
        pick(moods[psychicID] ?? moods["selene"]!, "mood|\(psychicID)|\(dayKey(date))")
    }

    // MARK: Morning message

    private static let openings: [String: [String]] = [
        "selene": ["Good morning, dear one.", "The moon is still in the sky this morning, darling.", "Wake gently, dear one."],
        "kaz": ["Market open.", "Morning briefing.", "Kaz here. Quick one."],
        "ivy": ["Morning, love.", "Kettle's on, sweetheart.", "Rise and shine, pet."],
        "zephyr": ["gm. the ball woke up before me.", "okay so the cosmos sent a memo.", "morning!! big sparkly energy today."],
        "mirela": ["Good morning, my dear.", "Up already? Good.", "Come, sit a minute."],
    ]

    /// A short message in the psychic's voice about the day's card.
    static func morningMessage(psychicID: String, name: String, card: TarotCard, on date: Date = Date()) -> String {
        let opening = pick(openings[psychicID] ?? openings["selene"]!, "open|\(psychicID)|\(dayKey(date))")
        let you = name.isEmpty ? "" : ", \(name)"
        switch psychicID {
        case "kaz":
            return "\(opening) Today's card\(you): \(card.name). \(card.meaning)"
        case "ivy":
            return "\(opening) The leaves pulled \(card.name) for you today\(you). \(card.meaning)"
        case "zephyr":
            return "\(opening) today's card\(you) is \(card.name). \(card.meaning)"
        case "mirela":
            return "\(opening) I turned \(card.name) for you today\(you). \(card.meaning)"
        default:
            return "\(opening) Your card today is \(card.name)\(you). \(card.meaning)"
        }
    }
}
