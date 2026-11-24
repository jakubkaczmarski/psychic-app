import Foundation

struct TarotCard: Codable, Hashable {
    /// Roman numeral of a major arcana card; empty for the minor cards.
    let numeral: String
    let name: String
    let meaning: String

    /// The name with its numeral, when it has one: "The Sun (XIX)", "Ace of Cups".
    var label: String { numeral.isEmpty ? name : "\(name) (\(numeral))" }
}

/// A card the server drew and has turned face up.
struct DrawnCard: Codable, Hashable {
    /// Where it sits in the spread, e.g. "What's in the way".
    let position: String
    let name: String
    /// Roman numeral of a major arcana card; empty otherwise.
    let numeral: String
    /// Cups, Wands, Swords, Pentacles or "Major"; Hearts, Diamonds, Clubs or Spades.
    let suit: String
    let rank: String
    let reversed: Bool
    /// Traditional meaning, the reversed one when it's reversed.
    let meaning: String

    var tarotCard: TarotCard { TarotCard(numeral: numeral, name: name, meaning: meaning) }
}

/// The spreads the server can lay out.
enum SpreadKind: String, Codable, CaseIterable, Identifiable {
    case single, three, cross
    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: "One card"
        case .three: "Three cards"
        case .cross: "The cross · 5 cards"
        }
    }
    /// What the user "says" when they pick it.
    var request: String {
        switch self {
        case .single: "Draw one card for me."
        case .three: "Lay out three cards for me."
        case .cross: "Lay out the cross for me."
        }
    }
    var count: Int { self == .single ? 1 : self == .three ? 3 : 5 }
    /// Only with Fate+.
    var needsPlus: Bool { self == .cross }
}

/// A spread on the table, as of one turn: the cards turned so far, and the token to turn the next one.
/// The server keeps the face-down cards inside the token; the app can't see them.
struct CardSpread: Codable, Hashable {
    let token: String
    /// "tarot" or "playing".
    let deck: String
    let kind: String
    let name: String
    let positions: [String]
    let cards: [DrawnCard]

    var isComplete: Bool { cards.count >= positions.count }
    var isPlaying: Bool { deck == "playing" }
}

/// What to ask the server to draw with a question: a new spread, or the next card of one on the table.
struct DrawRequest: Codable, Hashable {
    var spread: String? = nil
    var token: String? = nil
    var turn: Int? = nil
}

struct ChatMessage: Identifiable, Codable, Equatable {
    enum Role: String, Codable { case user, psychic, card, ritual, spread }

    var id = UUID()
    var role: Role
    var text: String
    var card: TarotCard? = nil
    /// Extra context sent to Claude with a user turn but not shown in the bubble.
    var apiNote: String? = nil
    var isError = false
    /// Result of a psychic's ritual (role `.ritual`).
    var ritual: Ritual? = nil
    /// Cards on the table after this turn (role `.spread`).
    var spread: CardSpread? = nil
    /// Cards to draw with this question (user messages). Kept so a locked reply can draw them once unlocked.
    var draw: DrawRequest? = nil
    /// When the message was added. Missing on messages saved by older versions.
    var date: Date? = Date()
    /// Marks the first message of a new visit; earlier visits are sent as memory.
    var startsVisit: Bool? = nil
    /// The psychic has "read" this user message.
    var seen: Bool? = nil
    /// A reply sent after the free messages ran out: shown blurred until Fate+ is unlocked.
    var locked: Bool? = nil
    /// A locked bubble that stands in for a reply not fetched yet: it's fetched once Fate+ is unlocked.
    var awaitingReply: Bool? = nil
}

struct Psychic: Identifiable, Hashable {
    let id: String
    var name: String
    var short: String
    let imageName: String
    var ringHex: UInt32
    var specialty: String
    var tagline: String
    var bio: String
    let persona: String
    var styles: [String]
    var asks: [String]
    var defaultName: String
    var greeting: String
    var signLine: String
    var cardIntro: String
    // Demo-mode replies, used only when no API key is set.
    let love: [String]
    let work: [String]
    let general: [String]

    // Set in Psychic Studio (see `PsychicDirectory`); nil or empty means the app's own default.
    /// Quote on the profile page ("A taste of a reading").
    var sample: String? = nil
    var moods: [String] = []
    var morningOpenings: [String] = []
    var ritualButton: String? = nil
    var ritualIntro: String? = nil
    var spreadIntro: String? = nil
    var welcomeBack: String? = nil
    /// "slow", "medium" or "fast".
    var typing: String? = nil
    /// Built into the app, with its own ritual. Psychics added in Psychic Studio draw cards instead.
    var isBuiltIn = true

    /// The quote on the profile page.
    var sampleReading: String { sample ?? general.first ?? tagline }
}

struct StarSign: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let dates: String
}

enum Catalog {
    static let chips = ["Will I find love soon?", "Should I change jobs?", "What is my energy this week?", "Draw a tarot card"]

    static let signs: [StarSign] = [
        .init(name: "Aries", dates: "Mar 21–Apr 19"), .init(name: "Taurus", dates: "Apr 20–May 20"),
        .init(name: "Gemini", dates: "May 21–Jun 20"), .init(name: "Cancer", dates: "Jun 21–Jul 22"),
        .init(name: "Leo", dates: "Jul 23–Aug 22"), .init(name: "Virgo", dates: "Aug 23–Sep 22"),
        .init(name: "Libra", dates: "Sep 23–Oct 22"), .init(name: "Scorpio", dates: "Oct 23–Nov 21"),
        .init(name: "Sagittarius", dates: "Nov 22–Dec 21"), .init(name: "Capricorn", dates: "Dec 22–Jan 19"),
        .init(name: "Aquarius", dates: "Jan 20–Feb 18"), .init(name: "Pisces", dates: "Feb 19–Mar 20"),
    ]

    /// The full 78-card deck: the 22 major arcana, then cups, wands, swords and pentacles.
    /// Minor cards have no numeral.
    static let deck: [TarotCard] = [
        .init(numeral: "0", name: "The Fool", meaning: "A leap is calling. Say yes before you have it all figured out."),
        .init(numeral: "I", name: "The Magician", meaning: "You already hold every tool you need. Start before you feel ready."),
        .init(numeral: "II", name: "The High Priestess", meaning: "Your intuition is louder than the noise. Trust the quiet voice."),
        .init(numeral: "III", name: "The Empress", meaning: "Abundance and care. Something you have nurtured is ready to bloom."),
        .init(numeral: "IV", name: "The Emperor", meaning: "Structure is your friend right now. Set the rule, then keep it."),
        .init(numeral: "V", name: "The Hierophant", meaning: "Someone has walked this road before you. Ask for the map."),
        .init(numeral: "VI", name: "The Lovers", meaning: "A choice of the heart. Pick the option that feels like home."),
        .init(numeral: "VII", name: "The Chariot", meaning: "Two forces pull in different directions. Hold the reins and keep moving."),
        .init(numeral: "VIII", name: "Strength", meaning: "Gentle courage wins. Patience is your superpower right now."),
        .init(numeral: "IX", name: "The Hermit", meaning: "Step back from the crowd for a while. The answer needs quiet to reach you."),
        .init(numeral: "X", name: "Wheel of Fortune", meaning: "Luck is turning your way. Be ready when it lands."),
        .init(numeral: "XI", name: "Justice", meaning: "What is fair will show itself. Be honest about your own part in it."),
        .init(numeral: "XII", name: "The Hanged Man", meaning: "Stop pushing. Seen from a different angle, the problem changes shape."),
        .init(numeral: "XIII", name: "Death", meaning: "An ending that makes room. Let the finished thing be finished."),
        .init(numeral: "XIV", name: "Temperance", meaning: "Balance and pacing. Mix a little of both options."),
        .init(numeral: "XV", name: "The Devil", meaning: "Notice what has a hold on you. The chain is looser than it looks."),
        .init(numeral: "XVI", name: "The Tower", meaning: "Something shaky is coming down. What is left standing is what was true."),
        .init(numeral: "XVII", name: "The Star", meaning: "Hope, healing and a quiet glow-up on the way."),
        .init(numeral: "XVIII", name: "The Moon", meaning: "Not everything is clear yet. Let things reveal themselves."),
        .init(numeral: "XIX", name: "The Sun", meaning: "Warmth, wins and a very good day ahead."),
        .init(numeral: "XX", name: "Judgement", meaning: "A wake-up call. Answer it, and forgive the earlier you."),
        .init(numeral: "XXI", name: "The World", meaning: "A chapter closes beautifully. Celebrate how far you came."),
        // Cups
        .init(numeral: "", name: "Ace of Cups", meaning: "A new feeling is pouring in. Let your heart be open to it."),
        .init(numeral: "", name: "Two of Cups", meaning: "Two people meeting as equals. A bond worth tending."),
        .init(numeral: "", name: "Three of Cups", meaning: "Good company and something to toast. Say yes to the invitation."),
        .init(numeral: "", name: "Four of Cups", meaning: "You are bored with what is on offer. Look up: there is a fourth cup."),
        .init(numeral: "", name: "Five of Cups", meaning: "Grieve what spilled, then turn around. Two cups are still standing."),
        .init(numeral: "", name: "Six of Cups", meaning: "A sweet memory returns. Take the kindness from it and leave the rest."),
        .init(numeral: "", name: "Seven of Cups", meaning: "So many shiny options. Choose one real thing over seven daydreams."),
        .init(numeral: "", name: "Eight of Cups", meaning: "You are walking away from something that no longer fills you. Keep going."),
        .init(numeral: "", name: "Nine of Cups", meaning: "A wish granted. Let yourself enjoy it without apology."),
        .init(numeral: "", name: "Ten of Cups", meaning: "Home, peace and people who love you. This is the good part."),
        .init(numeral: "", name: "Page of Cups", meaning: "A tender message or a surprise from the heart. Stay curious."),
        .init(numeral: "", name: "Knight of Cups", meaning: "Someone arrives with an offer and a lot of feeling. See if the actions match."),
        .init(numeral: "", name: "Queen of Cups", meaning: "Deep kindness and good instincts. Trust how you read the room."),
        .init(numeral: "", name: "King of Cups", meaning: "Calm in the middle of other people's waves. Lead with a steady heart."),
        // Wands
        .init(numeral: "", name: "Ace of Wands", meaning: "A spark of something new. Act on it while it is hot."),
        .init(numeral: "", name: "Two of Wands", meaning: "You have a plan and a view. Decide how far you want to go."),
        .init(numeral: "", name: "Three of Wands", meaning: "Your ships are on their way. Keep watching the horizon."),
        .init(numeral: "", name: "Four of Wands", meaning: "A reason to celebrate at home. Mark the milestone."),
        .init(numeral: "", name: "Five of Wands", meaning: "A noisy scuffle, more sport than war. Do not take it personally."),
        .init(numeral: "", name: "Six of Wands", meaning: "Recognition is coming. Accept the applause."),
        .init(numeral: "", name: "Seven of Wands", meaning: "You are holding your ground. You have the higher position, so stand firm."),
        .init(numeral: "", name: "Eight of Wands", meaning: "News is moving fast. Be ready to move with it."),
        .init(numeral: "", name: "Nine of Wands", meaning: "Tired, but still standing. One more push and you are through."),
        .init(numeral: "", name: "Ten of Wands", meaning: "You are carrying too much. Put down what is not yours."),
        .init(numeral: "", name: "Page of Wands", meaning: "An eager idea wants to be tried. Let yourself be a beginner."),
        .init(numeral: "", name: "Knight of Wands", meaning: "A burst of energy and a fast exit. Aim before you charge."),
        .init(numeral: "", name: "Queen of Wands", meaning: "Warmth and confidence that fill a room. Take up your space."),
        .init(numeral: "", name: "King of Wands", meaning: "A natural leader with a long view. Back your own vision."),
        // Swords
        .init(numeral: "", name: "Ace of Swords", meaning: "A clear thought cuts through the fog. Say the true thing."),
        .init(numeral: "", name: "Two of Swords", meaning: "You are avoiding a choice. Take off the blindfold and look."),
        .init(numeral: "", name: "Three of Swords", meaning: "A heartache named out loud starts to heal. Be gentle with yourself."),
        .init(numeral: "", name: "Four of Swords", meaning: "Rest is not giving up. Lie down for a while before the next round."),
        .init(numeral: "", name: "Five of Swords", meaning: "A win that costs too much. Ask whether this fight is worth it."),
        .init(numeral: "", name: "Six of Swords", meaning: "Calmer water is ahead. Let yourself be carried away from the storm."),
        .init(numeral: "", name: "Seven of Swords", meaning: "Someone is being less than straight, maybe you. Choose the honest route."),
        .init(numeral: "", name: "Eight of Swords", meaning: "You feel stuck, but the ropes are loose. Take one small step."),
        .init(numeral: "", name: "Nine of Swords", meaning: "The worry is louder at night than the facts are. Morning will shrink it."),
        .init(numeral: "", name: "Ten of Swords", meaning: "The worst has already happened. From here, the only way is up."),
        .init(numeral: "", name: "Page of Swords", meaning: "A sharp, curious mind is on the case. Ask the question nobody is asking."),
        .init(numeral: "", name: "Knight of Swords", meaning: "Someone charges in with strong opinions. Check the facts before you follow."),
        .init(numeral: "", name: "Queen of Swords", meaning: "Clear eyes and firm boundaries. Say what you mean, kindly."),
        .init(numeral: "", name: "King of Swords", meaning: "A fair mind and a steady hand. Decide with your head this time."),
        // Pentacles
        .init(numeral: "", name: "Ace of Pentacles", meaning: "A seed of something solid: work, money or health. Plant it."),
        .init(numeral: "", name: "Two of Pentacles", meaning: "You are juggling two things and keeping your balance. Stay light on your feet."),
        .init(numeral: "", name: "Three of Pentacles", meaning: "Good work gets noticed. Build it with other people."),
        .init(numeral: "", name: "Four of Pentacles", meaning: "You are holding on tight. Ask what would happen if you loosened your grip."),
        .init(numeral: "", name: "Five of Pentacles", meaning: "A lean season. Help is nearer than you think, so look up and ask."),
        .init(numeral: "", name: "Six of Pentacles", meaning: "Giving and receiving in fair measure. Let yourself do both."),
        .init(numeral: "", name: "Seven of Pentacles", meaning: "You have done the planting. Now check the crop and be patient."),
        .init(numeral: "", name: "Eight of Pentacles", meaning: "Practice, patience and steady hands. Your skill is growing with every try."),
        .init(numeral: "", name: "Nine of Pentacles", meaning: "You built this comfort yourself. Enjoy the garden."),
        .init(numeral: "", name: "Ten of Pentacles", meaning: "Something lasting for the people you love. Think in generations."),
        .init(numeral: "", name: "Page of Pentacles", meaning: "A keen student with a new opportunity. Take the lesson seriously."),
        .init(numeral: "", name: "Knight of Pentacles", meaning: "Slow, steady and reliable. Keep showing up."),
        .init(numeral: "", name: "Queen of Pentacles", meaning: "Practical care and a warm home. Look after yourself as well as you look after others."),
        .init(numeral: "", name: "King of Pentacles", meaning: "Security earned and shared. Be generous with what you have built."),
    ]

    /// Every psychic to show: the built-in ones (with any text changed in Psychic Studio), then the ones
    /// added in Psychic Studio. See `PsychicDirectory`.
    static var psychics: [Psychic] { PsychicDirectory.psychics(builtIn: builtIn) }

    static let builtIn: [Psychic] = [
        Psychic(
            id: "selene", name: "Madame Selene", short: "Selene", imageName: "psychic_selene", ringHex: 0x6A58B4,
            specialty: "Love & relationships", tagline: "Reads the moon, and your texts.",
            bio: "A third-generation moon reader from a seaside town that may or may not exist. She speaks softly, reads slowly, and believes every heart has a tide.",
            persona: "a soft-spoken, poetic third-generation moon reader who uses tarot and moon phases. Gentle, romantic, a touch dramatic. Calls people 'dear one' or 'darling'.",
            styles: ["Tarot", "Moon phases", "Gentle"],
            asks: ["Does my crush like me back?", "Should I text my ex?", "When will I meet the one?"],
            defaultName: "dear one",
            greeting: "Welcome, {name}. The moon is bright tonight, and so, I sense, is your curiosity. What weighs on your heart?",
            signLine: "Ah, a {sign}. I felt it before you said a word.",
            cardIntro: "Let me turn one card for you…",
            love: ["I see two paths crossing under a waxing moon. Someone thinks of you more than they admit. Let them catch up to you; do not chase.", "The cards whisper patience. What is meant for you will not need convincing."],
            work: ["The moon cares little for spreadsheets, but I sense restlessness. A small change, not a dramatic one, would light you up.", "Ask for what you are worth, darling. The universe rewards a clear request."],
            general: ["The energy around you is tender but strong, like a new tide. Rest first, decide second.", "I sense you already know the answer. You only wanted someone to say it aloud."]
        ),
        Psychic(
            id: "kaz", name: "Oracle Kaz", short: "Kaz", imageName: "psychic_kaz", ringHex: 0x8C6634,
            specialty: "Career & ambition", tagline: "Blunt star charts. No sugarcoating.",
            bio: "A former startup founder turned astrologer. Reads your chart like a quarterly report and tells you exactly what it says, whether you like it or not.",
            persona: "a blunt former startup founder turned astrologer who reads charts like quarterly reports. Direct, punchy short sentences, mildly sarcastic but firmly on the user's side.",
            styles: ["Astrology", "Career", "Direct"],
            asks: ["Should I ask for a raise?", "Is it time to quit my job?", "Will my side project take off?"],
            defaultName: "there",
            greeting: "Kaz here. Hey {name}. Stars are aligned, schedule is tight. Ask and I will give you the straight read.",
            signLine: "{sign}, huh. Explains a lot. We can work with it.",
            cardIntro: "Pulling one card. Do not argue with it.",
            love: ["Mercury says stop overthinking the double text. Say what you mean, then go do something for yourself.", "Strong loyalty, weak patience. Give it one more honest conversation before you decide."],
            work: ["Big shift coming. Not a sign to quit tomorrow. A sign to update your CV tonight.", "The stars back the bold move. Pitch the idea."],
            general: ["Your energy is scattered across too many tabs. Close three. Pick one. Win that.", "Saturn is watching your follow-through. Finish the thing you started last month."]
        ),
        Psychic(
            id: "ivy", name: "Grandma Ivy", short: "Ivy", imageName: "psychic_ivy", ringHex: 0x4A7A5E,
            specialty: "Tea leaves & life choices", tagline: "Sit down, love. The kettle is on.",
            bio: "Has read tea leaves at the same kitchen table for fifty years. Gives advice with a biscuit on the side, whether you asked for one or not.",
            persona: "a cozy grandmother who has read tea leaves at her kitchen table for fifty years. Warm, a little fussy, gives practical life advice with a biscuit on the side. Calls people 'love' and 'sweetheart'.",
            styles: ["Tea leaves", "Life advice", "Cozy"],
            asks: ["Am I on the right path?", "Should I move to a new city?", "How do I stop worrying so much?"],
            defaultName: "sweetheart",
            greeting: "Oh, hello {name}. Sit, sit. Swirl your cup three times and tell me what is troubling you.",
            signLine: "A {sign}! My late husband was one. Lovely people.",
            cardIntro: "I do not usually do cards, but here, I will pick one for you…",
            love: ["The leaves show a little heart near the rim. That means soon, not someday. Wear the nice coat.", "I see a bird in your cup. Good news is flying in about someone you care for."],
            work: ["There is a ladder at the bottom of your cup. Slow climbing, but steady. Grandma approves.", "You are doing the work of two people. Have a biscuit and ask for help, love."],
            general: ["A clear cup means a clear road. Whatever you are dreading is smaller than it looks.", "I see an anchor. Stay put a little longer; something good is settling around you."]
        ),
        Psychic(
            id: "zephyr", name: "Zephyr", short: "Zephyr", imageName: "psychic_zephyr", ringHex: 0x2F5F7C,
            specialty: "Crystal ball & cosmic chaos", tagline: "Sees everything. Explains nothing.",
            bio: "Found a crystal ball at a flea market and has been seeing things ever since. Mostly the future. Occasionally pigeons.",
            persona: "a chaotic, playful young mystic with a flea-market crystal ball. Absurd humour, cosmic metaphors and random tangents (pigeons, snacks, weird lamps), but always encouraging underneath.",
            styles: ["Crystal ball", "Chaos", "Playful"],
            asks: ["What does the universe want from me?", "Will this week be weird?", "What is my spirit snack?"],
            defaultName: "friend",
            greeting: "Whoa, {name}. Your aura walked in before you did. It is very purple. Ask me something; the crystal ball is buffering.",
            signLine: "{sign} energy detected. The ball just went sparkly.",
            cardIntro: "Shuffling the cosmos… okay, this one literally jumped out.",
            love: ["The ball shows a coffee shop, a mixed-up order and a laugh. Go get the oat latte. Trust me.", "Cosmic forecast: 70% chance of butterflies, 30% chance of awkward-but-cute."],
            work: ["I see you in a meeting saying the smartest thing in the room. Then a pigeon. The pigeon is not important. You are.", "The universe is rebooting your career. Please do not unplug during the update."],
            general: ["The crystal says: drink water, text your friend back, and absolutely buy the weird lamp.", "Big main-character energy this week. Act accordingly, with snacks."]
        ),
        Psychic(
            id: "mirela", name: "Mirela", short: "Mirela", imageName: "psychic_mirela", ringHex: 0x9A3B4A,
            specialty: "Card reading & family matters", tagline: "Ordinary playing cards, extraordinary honesty.",
            bio: "Learned to read an ordinary deck of playing cards from her grandmother, in a Romani family where the cards came out at every celebration. Warm, funny, and impossible to fool.",
            persona: "a warm, funny and sharp Romani card reader in her fifties who learned to read an ordinary deck of playing cards from her grandmother. Frank, affectionate, family-minded and impossible to fool. Speaks with dignity and real warmth; never a stereotype or caricature, no fake accent.",
            styles: ["Playing cards", "Family", "Warm & honest"],
            asks: ["What is coming for my family?", "Can I trust my new friend?", "Is good luck on its way?"],
            defaultName: "my dear",
            greeting: "Come in, {name}, sit with me. Cut the deck with your left hand and tell me what brought you here.",
            signLine: "A {sign}? Then you are stubborn and lucky. Good combination.",
            cardIntro: "Let me lay one card down for you…",
            love: ["The queen of hearts sits right beside you. Someone has warm eyes for you, but they are shy. Make it easy for them.", "Someone talks sweet but acts slow. Watch what they do, not what they say."],
            work: ["Diamonds all over this spread. Money is moving toward you, slowly. Do not spend it before it arrives.", "The ten of clubs: hard work, but it pays. Ask an older person you trust for advice this week."],
            general: ["There's a message you've been meaning to send. Send it today. That conversation will untangle something.", "Luck is on its way, but luck likes a tidy house. Finish one small thing today and make room for it."]
        ),
    ]

    /// The psychic with this id. One hidden in Psychic Studio since is still found, so old chats keep working.
    static func psychic(_ id: String) -> Psychic {
        psychics.first { $0.id == id } ?? PsychicDirectory.anyPsychic(id) ?? builtIn[0]
    }
}
