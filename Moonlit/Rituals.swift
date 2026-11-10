import Foundation

/// The result of a psychic's ritual, shown as a card in the chat.
struct Ritual: Codable, Hashable {
    /// Small caps label above the title, e.g. "Tonight's moon".
    let eyebrow: String
    let title: String
    /// SF Symbol shown on the card.
    let symbol: String
    /// One or two lines explaining the result.
    let detail: String
}

/// How each psychic's ritual is presented in the chat.
struct RitualStyle {
    /// Label of the ritual button in the chat.
    let button: String
    let buttonSymbol: String
    /// What the psychic says while performing it.
    let intro: String
    /// Greeting when the user comes back after a while. `{name}` is replaced.
    let welcomeBack: String
}

enum Rituals {
    static func style(for psychicID: String) -> RitualStyle {
        styles[psychicID] ?? styles["selene"]!
    }

    private static let styles: [String: RitualStyle] = [
        "selene": .init(button: "Read tonight's moon", buttonSymbol: "moon.stars",
                        intro: "Let me draw back the curtain and look at the moon for you…",
                        welcomeBack: "There you are, {name}. The moon has changed since we last spoke, and I wondered about you."),
        "kaz": .init(button: "Run my forecast", buttonSymbol: "chart.line.uptrend.xyaxis",
                     intro: "Running your numbers. Give me a second.",
                     welcomeBack: "{name}. Back for the next quarter. Good. Let's review."),
        "ivy": .init(button: "Swirl the cup", buttonSymbol: "cup.and.saucer",
                     intro: "Swirl it three times, love, then turn it over on the saucer. Let's see…",
                     welcomeBack: "Oh, {name}, you came back! Sit down, love, I'll put the kettle on."),
        "zephyr": .init(button: "Shake the crystal ball", buttonSymbol: "sparkles",
                        intro: "okay hold on, shaking the ball… it's going cloudy… ooh.",
                        welcomeBack: "{name}!! the ball literally glowed when you walked in. welcome back to the chaos."),
        "mirela": .init(button: "Cut the deck", buttonSymbol: "suit.heart",
                        intro: "Cut the deck with your left hand, my dear. Now, let me turn one over…",
                        welcomeBack: "{name}, you're back. Sit, sit. I had a feeling you'd come today."),
    ]

    /// Performs the psychic's ritual. Returns the card to show and a note for Claude.
    static func perform(for psychicID: String, sign: String?, now: Date = Date()) -> (ritual: Ritual, note: String) {
        let ritual: Ritual
        switch psychicID {
        case "kaz": ritual = forecast(sign: sign)
        case "ivy": ritual = teaLeaves()
        case "zephyr": ritual = crystalBall()
        case "mirela": ritual = playingCard()
        default: ritual = moon(now)
        }
        let note = "[The app just performed your ritual for this question. \(ritual.eyebrow): \(ritual.title). \(ritual.detail) Interpret this result for the user in your own voice.]"
        return (ritual, note)
    }

    // MARK: Selene: the real moon phase

    static func moon(_ date: Date) -> Ritual {
        let synodicMonth = 29.530588853
        // A known new moon: 6 January 2000, 18:14 UTC.
        let reference = Date(timeIntervalSince1970: 947_182_440)
        var age = date.timeIntervalSince(reference) / 86_400
        age = age.truncatingRemainder(dividingBy: synodicMonth)
        if age < 0 { age += synodicMonth }
        let index = Int((age / synodicMonth) * 8 + 0.5) % 8
        let illumination = Int(((1 - cos(2 * .pi * age / synodicMonth)) / 2 * 100).rounded())
        let phases: [(String, String, String)] = [
            ("New Moon", "moonphase.new.moon", "A dark sky for new beginnings. Plant a wish and tell no one."),
            ("Waxing Crescent", "moonphase.waxing.crescent", "A sliver of light that is growing. Small first steps are favoured."),
            ("First Quarter", "moonphase.first.quarter", "Half lit and pushing forward. A time to decide and act."),
            ("Waxing Gibbous", "moonphase.waxing.gibbous", "Almost full. Feelings run louder than facts; refine, don't rush."),
            ("Full Moon", "moonphase.full.moon", "Everything revealed. Truths and feelings come to the surface."),
            ("Waning Gibbous", "moonphase.waning.gibbous", "Light pouring back out. A time for gratitude and sharing."),
            ("Last Quarter", "moonphase.last.quarter", "Half dark. A time to forgive, release and clear space."),
            ("Waning Crescent", "moonphase.waning.crescent", "The last sliver before dark. Rest, reflect and let go."),
        ]
        let (name, symbol, meaning) = phases[index]
        return Ritual(eyebrow: "Tonight's moon", title: name, symbol: symbol,
                      detail: "\(illumination)% lit. \(meaning)")
    }

    // MARK: Kaz: the forecast

    static func forecast(sign: String?) -> Ritual {
        let love = Int.random(in: 1...5), money = Int.random(in: 1...5), energy = Int.random(in: 1...5)
        let who = sign.map { "\($0) forecast" } ?? "Your forecast"
        return Ritual(eyebrow: "This week", title: who, symbol: "chart.line.uptrend.xyaxis",
                      detail: "Love \(love)/5 · Money \(money)/5 · Energy \(energy)/5")
    }

    // MARK: Ivy: tea leaves

    private static let leaves: [(String, String, String)] = [
        ("A key", "key", "A door is about to open."),
        ("A bird", "bird", "News is on its way."),
        ("A heart", "heart", "Someone is fond of you."),
        ("An anchor", "sailboat", "Stay put; things are settling."),
        ("A ladder", "stairs", "Slow, steady progress upward."),
        ("A ring", "circle", "A promise or a commitment."),
        ("A tree", "tree", "Growth and good health."),
        ("A little boat", "ferry", "A trip or a change of scene."),
        ("A crescent moon", "moon", "A change of mood, for the better."),
        ("A star", "star", "A wish has a good chance."),
        ("A teacup", "cup.and.saucer", "Good company is coming."),
        ("An umbrella", "umbrella", "You are protected; the worry will pass."),
    ]

    static func teaLeaves() -> Ritual {
        let (shape, symbol, meaning) = leaves.randomElement()!
        let place = [("near the rim", "soon"), ("in the middle", "in a few weeks"), ("at the bottom", "further off")].randomElement()!
        return Ritual(eyebrow: "In your cup", title: shape, symbol: symbol,
                      detail: "\(place.0.capitalizedFirst), so \(place.1). \(meaning)")
    }

    // MARK: Zephyr: the crystal ball

    private static let visions = [
        "a pigeon in a tiny hat", "a humming vending machine", "a lamp shaped like a duck", "an empty car park at midnight",
        "a slice of lemon cake", "one lost glove", "a disco ball", "a cat walking across a keyboard", "a bus that is early",
        "a rubber plant", "a neon sign that says OPEN", "a single spoon", "a traffic cone wearing sunglasses", "a very calm goose",
    ]

    static func crystalBall() -> Ritual {
        let seen = Array(visions.shuffled().prefix(3))
        return Ritual(eyebrow: "The ball shows", title: "A vision", symbol: "circle.hexagongrid.fill",
                      detail: "\(seen[0].capitalizedFirst), \(seen[1]) and \(seen[2]).")
    }

    // MARK: Mirela: a real 52-card deck

    static func playingCard() -> Ritual {
        let suits: [(String, String, String)] = [
            ("Hearts", "suit.heart.fill", "love and family"),
            ("Diamonds", "suit.diamond.fill", "money and news"),
            ("Clubs", "suit.club.fill", "work and effort"),
            ("Spades", "suit.spade.fill", "obstacles and hard truths"),
        ]
        let ranks: [(String, String)] = [
            ("Ace", "a beginning"), ("Two", "a choice or a pair"), ("Three", "growth"), ("Four", "stability"),
            ("Five", "change"), ("Six", "harmony at home"), ("Seven", "a test of patience"), ("Eight", "movement"),
            ("Nine", "a wish"), ("Ten", "completion"), ("Jack", "a young person or a message"),
            ("Queen", "a caring, strong woman"), ("King", "a man of authority"),
        ]
        let (suit, symbol, suitMeaning) = suits.randomElement()!
        let (rank, rankMeaning) = ranks.randomElement()!
        return Ritual(eyebrow: "Your card", title: "\(rank) of \(suit)", symbol: symbol,
                      detail: "\(suit) speak of \(suitMeaning). The \(rank.lowercased()) means \(rankMeaning).")
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
