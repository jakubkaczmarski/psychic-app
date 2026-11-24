// Real card draws: the decks, the spreads, and the notes that tell the psychic what came up.
// Cards are drawn here on the server, never in the app, so a reading can't be handed a made-up draw.
// A drawn spread travels back to the app as an encrypted token: the app shows the cards turned so far and
// sends the token back to turn the next one, without being able to read or change the cards still face down.

import crypto from "node:crypto";

export type DeckId = "tarot" | "playing";
export type SpreadId = "single" | "three" | "cross";

export interface Card {
  name: string;
  /** Roman numeral of a major arcana card; empty otherwise. */
  numeral: string;
  /** Cups, Wands, Swords or Pentacles; Hearts, Diamonds, Clubs or Spades; "Major" for the major arcana. */
  suit: string;
  /** Ace, Two, … King, or the major arcana card's name. */
  rank: string;
  upright: string;
  /** Empty for decks that aren't read reversed. */
  reversed: string;
}

/** A psychic's own reading of one card. Any part may be empty; the traditional meaning fills the gaps. */
export interface CardMeaning {
  card: string;
  upright: string;
  reversed: string;
  memory: string;
}

// ---- Tarot: 78 cards, read upright or reversed ----
// Upright meanings match the app's deck (AsFate/Models.swift), so the card of the day reads the same way.
const MAJORS: [string, string, string, string][] = [
  ["The Fool", "0", "A leap is calling. Say yes before you have it all figured out.", "Hesitating at the edge, or leaping without looking. Check the ground, then go."],
  ["The Magician", "I", "You already hold every tool you need. Start before you feel ready.", "Talent left on the table, or a little too much showmanship. Use what you have, honestly."],
  ["The High Priestess", "II", "Your intuition is louder than the noise. Trust the quiet voice.", "You've stopped listening to your gut. Get quiet enough to hear it again."],
  ["The Empress", "III", "Abundance and care. Something you have nurtured is ready to bloom.", "Giving everyone care except yourself. Water your own garden first."],
  ["The Emperor", "IV", "Structure is your friend right now. Set the rule, then keep it.", "Too rigid, or no structure at all. Find the rule that actually helps."],
  ["The Hierophant", "V", "Someone has walked this road before you. Ask for the map.", "The usual way doesn't fit you. It's all right to write your own rules."],
  ["The Lovers", "VI", "A choice of the heart. Pick the option that feels like home.", "Heart and head pulling apart. Be honest about what you really value."],
  ["The Chariot", "VII", "Two forces pull in different directions. Hold the reins and keep moving.", "Spinning your wheels. Pick one direction before you push harder."],
  ["Strength", "VIII", "Gentle courage wins. Patience is your superpower right now.", "Running low on patience, mostly with yourself. Be gentler there first."],
  ["The Hermit", "IX", "Step back from the crowd for a while. The answer needs quiet to reach you.", "Alone a bit too long. Time to come back to the people who miss you."],
  ["Wheel of Fortune", "X", "Luck is turning your way. Be ready when it lands.", "A run of bad luck that is already turning. Hold steady through the bump."],
  ["Justice", "XI", "What is fair will show itself. Be honest about your own part in it.", "Something feels unfair. Own your part, and let the rest go."],
  ["The Hanged Man", "XII", "Stop pushing. Seen from a different angle, the problem changes shape.", "Waiting for a sign that has already come. It's time to move."],
  ["Death", "XIII", "An ending that makes room. Let the finished thing be finished.", "Holding on to something that is already over. Letting go will feel lighter than you think."],
  ["Temperance", "XIV", "Balance and pacing. Mix a little of both options.", "Too much of one thing. Bring the balance back slowly."],
  ["The Devil", "XV", "Notice what has a hold on you. The chain is looser than it looks.", "The chain is coming off. You're ready to walk away from an old habit."],
  ["The Tower", "XVI", "Something shaky is coming down. What is left standing is what was true.", "Propping up something that wants to change. A small shake now saves a big one later."],
  ["The Star", "XVII", "Hope, healing and a quiet glow-up on the way.", "Hope has dimmed a little. It hasn't gone out; tend it."],
  ["The Moon", "XVIII", "Not everything is clear yet. Let things reveal themselves.", "The fog is lifting. What confused you is about to make sense."],
  ["The Sun", "XIX", "Warmth, wins and a very good day ahead.", "The good news is there, a little behind the clouds. Let yourself enjoy it."],
  ["Judgement", "XX", "A wake-up call. Answer it, and forgive the earlier you.", "Being too hard on yourself. The call is to grow, not to punish."],
  ["The World", "XXI", "A chapter closes beautifully. Celebrate how far you came.", "Nearly there. Finish the last little piece before you start something new."],
];

const MINORS: Record<string, [string, string][]> = {
  Cups: [
    ["A new feeling is pouring in. Let your heart be open to it.", "A feeling held back. Let yourself feel it before you decide anything."],
    ["Two people meeting as equals. A bond worth tending.", "A bond out of balance. Talk before it drifts."],
    ["Good company and something to toast. Say yes to the invitation.", "Too much going out, or feeling left out. Find your real people."],
    ["You are bored with what is on offer. Look up: there is a fourth cup.", "Coming out of a slump. You're ready to say yes again."],
    ["Grieve what spilled, then turn around. Two cups are still standing.", "Turning around at last. Forgiveness is close."],
    ["A sweet memory returns. Take the kindness from it and leave the rest.", "Living in the past a little. The good days are not all behind you."],
    ["So many shiny options. Choose one real thing over seven daydreams.", "The fog of options is clearing. You know which one is real."],
    ["You are walking away from something that no longer fills you. Keep going.", "Afraid to leave, or leaving too soon. Be sure what you're walking toward."],
    ["A wish granted. Let yourself enjoy it without apology.", "The wish isn't quite what you thought. Ask what you really want."],
    ["Home, peace and people who love you. This is the good part.", "A little friction at home. Small kindness fixes more than big talks."],
    ["A tender message or a surprise from the heart. Stay curious.", "Feelings hurt over something small. Say it gently."],
    ["Someone arrives with an offer and a lot of feeling. See if the actions match.", "Charm without follow-through. Watch what they do."],
    ["Deep kindness and good instincts. Trust how you read the room.", "Taking on everyone's feelings. Give some of them back."],
    ["Calm in the middle of other people's waves. Lead with a steady heart.", "Keeping the calm on the outside only. Let someone see the waves."],
  ],
  Wands: [
    ["A spark of something new. Act on it while it is hot.", "A spark that keeps fizzling. Wait for the right moment, it's coming."],
    ["You have a plan and a view. Decide how far you want to go.", "Playing it too safe. The plan needs a first step."],
    ["Your ships are on their way. Keep watching the horizon.", "Delays at sea. It's late, not lost."],
    ["A reason to celebrate at home. Mark the milestone.", "The party's on hold. Celebrate the small win anyway."],
    ["A noisy scuffle, more sport than war. Do not take it personally.", "The arguing is winding down. Agree to disagree."],
    ["Recognition is coming. Accept the applause.", "Waiting for applause that's slow to come. Know your own worth."],
    ["You are holding your ground. You have the higher position, so stand firm.", "Tired of defending. Pick the one hill that matters."],
    ["News is moving fast. Be ready to move with it.", "Things are slowing down. Use the pause."],
    ["Tired, but still standing. One more push and you are through.", "Running on empty. Rest is part of the plan."],
    ["You are carrying too much. Put down what is not yours.", "You're starting to put some of it down. Keep going."],
    ["An eager idea wants to be tried. Let yourself be a beginner.", "Lots of ideas, no start. Pick one and play."],
    ["A burst of energy and a fast exit. Aim before you charge.", "Rushing, then stalling. Steady beats fast this time."],
    ["Warmth and confidence that fill a room. Take up your space.", "Dimming yourself for someone. Don't."],
    ["A natural leader with a long view. Back your own vision.", "Big plans, short patience. Bring people with you."],
  ],
  Swords: [
    ["A clear thought cuts through the fog. Say the true thing.", "Thoughts in a tangle. Sleep on it before you speak."],
    ["You are avoiding a choice. Take off the blindfold and look.", "The choice is making itself. Better to make it yourself."],
    ["A heartache named out loud starts to heal. Be gentle with yourself.", "The hurt is healing. Stop pressing on the bruise."],
    ["Rest is not giving up. Lie down for a while before the next round.", "Ready to get up again. Ease back in."],
    ["A win that costs too much. Ask whether this fight is worth it.", "Ready to make peace. Someone has to go first."],
    ["Calmer water is ahead. Let yourself be carried away from the storm.", "Not quite ready to leave the storm. That's all right, the boat will wait."],
    ["Someone is being less than straight, maybe you. Choose the honest route.", "The truth is coming out. Let it, it's lighter that way."],
    ["You feel stuck, but the ropes are loose. Take one small step.", "The ropes are off. Walk."],
    ["The worry is louder at night than the facts are. Morning will shrink it.", "The worst of the worry is passing. Tell someone what kept you up."],
    ["The worst has already happened. From here, the only way is up.", "Getting back up, slowly. Good."],
    ["A sharp, curious mind is on the case. Ask the question nobody is asking.", "All talk, or gossip in the air. Check before you repeat it."],
    ["Someone charges in with strong opinions. Check the facts before you follow.", "Words that cut too fast. Slow down before you reply."],
    ["Clear eyes and firm boundaries. Say what you mean, kindly.", "Sharp words covering a soft heart. Say it kindly."],
    ["A fair mind and a steady hand. Decide with your head this time.", "Logic without heart. Ask how it will feel, too."],
  ],
  Pentacles: [
    ["A seed of something solid: work, money or health. Plant it.", "A chance you're not quite ready for. Prepare the soil."],
    ["You are juggling two things and keeping your balance. Stay light on your feet.", "One ball too many. Put one down on purpose."],
    ["Good work gets noticed. Build it with other people.", "Working alone, or the team isn't pulling together. Ask for help."],
    ["You are holding on tight. Ask what would happen if you loosened your grip.", "Spending to feel better, or holding too tight. Find the middle."],
    ["A lean season. Help is nearer than you think, so look up and ask.", "The lean season is ending. Let help in."],
    ["Giving and receiving in fair measure. Let yourself do both.", "Giving more than you get back. Even it out."],
    ["You have done the planting. Now check the crop and be patient.", "Impatient with slow growth. It's growing."],
    ["Practice, patience and steady hands. Your skill is growing with every try.", "Going through the motions. Find the part you love again."],
    ["You built this comfort yourself. Enjoy the garden.", "Leaning on others for comfort. You can build your own."],
    ["Something lasting for the people you love. Think in generations.", "Family and money tangled together. Talk about it plainly."],
    ["A keen student with a new opportunity. Take the lesson seriously.", "A lesson skipped. Go back and learn it."],
    ["Slow, steady and reliable. Keep showing up.", "Steady has turned into stuck. Change one small thing."],
    ["Practical care and a warm home. Look after yourself as well as you look after others.", "Caring for everyone but yourself. Your turn."],
    ["Security earned and shared. Be generous with what you have built.", "Worrying about security too much. You have enough."],
  ],
};

const RANKS = ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Page", "Knight", "Queen", "King"];

const TAROT: Card[] = [
  ...MAJORS.map(([name, numeral, upright, reversed]) => ({ name, numeral, suit: "Major", rank: name, upright, reversed })),
  ...Object.entries(MINORS).flatMap(([suit, cards]) =>
    cards.map(([upright, reversed], i) => ({ name: `${RANKS[i]} of ${suit}`, numeral: "", suit, rank: RANKS[i], upright, reversed })),
  ),
];

// ---- Playing cards: 52 cards, read the cartomancy way (never reversed) ----
const PLAYING_SUITS: [string, string][] = [
  ["Hearts", "love, family and the home"],
  ["Diamonds", "money, news and practical matters"],
  ["Clubs", "work, effort and ambition"],
  ["Spades", "obstacles, hard truths and endings that clear the way"],
];
const PLAYING_RANKS: [string, string][] = [
  ["Ace", "a beginning"], ["Two", "a choice or a pair"], ["Three", "growth, or a third person"], ["Four", "stability"],
  ["Five", "change and a little turbulence"], ["Six", "harmony and things settling"], ["Seven", "a test of patience"],
  ["Eight", "movement and news on the way"], ["Nine", "a wish"], ["Ten", "completion"],
  ["Jack", "a young person or a message"], ["Queen", "a woman of strength and care"], ["King", "a man of authority"],
];

const PLAYING: Card[] = PLAYING_SUITS.flatMap(([suit, theme]) =>
  PLAYING_RANKS.map(([rank, meaning]) => ({
    name: `${rank} of ${suit}`, numeral: "", suit, rank,
    upright: `${meaning[0].toUpperCase()}${meaning.slice(1)}, in matters of ${theme}.`,
    reversed: "",
  })),
);

export const DECKS: Record<DeckId, { name: string; cards: Card[]; reversals: boolean }> = {
  tarot: { name: "tarot deck", cards: TAROT, reversals: true },
  playing: { name: "deck of playing cards", cards: PLAYING, reversals: false },
};

/** Chance a tarot card lands reversed. Real decks get turned around as they're shuffled. */
const REVERSED_CHANCE = 0.3;

export const SPREADS: Record<SpreadId, { name: string; positions: string[] }> = {
  single: { name: "one-card draw", positions: ["The card"] },
  three: { name: "three-card spread", positions: ["The situation", "What's in the way", "The advice"] },
  cross: { name: "five-card cross", positions: ["The heart of it", "What crosses you", "What's behind you", "What's coming", "Where it leads"] },
};

export const isDeck = (v: unknown): v is DeckId => v === "tarot" || v === "playing";
export const isSpread = (v: unknown): v is SpreadId => typeof v === "string" && Object.hasOwn(SPREADS, v);

/** Finds a card by name, ignoring case and extra spaces. */
export function findCard(deck: DeckId, name: string): Card | undefined {
  const want = name.toLowerCase().replace(/\s+/g, " ").trim();
  return DECKS[deck].cards.find((c) => c.name.toLowerCase() === want);
}

// ---- Drawing ----
export interface DrawnCard {
  card: Card;
  reversed: boolean;
}

/** Shuffles the whole deck with a cryptographic random source and deals from the top. No card twice. */
export function deal(deck: DeckId, count: number): DrawnCard[] {
  const { cards, reversals } = DECKS[deck];
  const order = cards.map((_, i) => i);
  for (let i = order.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [order[i], order[j]] = [order[j], order[i]];
  }
  return order.slice(0, count).map((i) => ({
    card: cards[i],
    reversed: reversals && crypto.randomInt(1000) < REVERSED_CHANCE * 1000,
  }));
}

// ---- The spread token ----
// AES-256-GCM: the app can carry it but can't read the face-down cards or change any of them.
interface SpreadPayload {
  v: 1;
  /** Psychic the spread was drawn for. */
  p: string;
  d: DeckId;
  s: SpreadId;
  /** Cards as [index in deck, reversed]. */
  c: [number, 0 | 1][];
  /** When it was drawn (ms). */
  t: number;
}

const TOKEN_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1000;

const secret = process.env.DRAW_SECRET ?? "";
if (!secret) {
  console.warn("DRAW_SECRET is not set: spreads in progress can't be continued after a restart.");
}
const KEY = crypto.createHash("sha256").update(secret || crypto.randomBytes(32)).digest();

export interface Spread {
  psychicId: string;
  deck: DeckId;
  spread: SpreadId;
  cards: DrawnCard[];
  token: string;
}

export function drawSpread(psychicId: string, deck: DeckId, spread: SpreadId): Spread {
  const cards = deal(deck, SPREADS[spread].positions.length);
  const all = DECKS[deck].cards;
  const payload: SpreadPayload = {
    v: 1, p: psychicId, d: deck, s: spread, t: Date.now(),
    c: cards.map((c) => [all.indexOf(c.card), c.reversed ? 1 : 0]),
  };
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", KEY, iv);
  const body = Buffer.concat([cipher.update(JSON.stringify(payload), "utf8"), cipher.final()]);
  const token = Buffer.concat([iv, cipher.getAuthTag(), body]).toString("base64url");
  return { psychicId, deck, spread, cards, token };
}

/** Opens a spread token. Returns null if it was tampered with, is too old, or isn't ours. */
export function openSpread(token: string): Spread | null {
  try {
    const raw = Buffer.from(token, "base64url");
    if (raw.length < 29 || raw.length > 2000) return null;
    const decipher = crypto.createDecipheriv("aes-256-gcm", KEY, raw.subarray(0, 12));
    decipher.setAuthTag(raw.subarray(12, 28));
    const json = Buffer.concat([decipher.update(raw.subarray(28)), decipher.final()]).toString("utf8");
    const p = JSON.parse(json) as SpreadPayload;
    if (p.v !== 1 || !isDeck(p.d) || !isSpread(p.s) || Date.now() - p.t > TOKEN_MAX_AGE_MS) return null;
    const all = DECKS[p.d].cards;
    const cards = p.c.map(([i, r]) => ({ card: all[i], reversed: r === 1 }));
    if (cards.length !== SPREADS[p.s].positions.length || cards.some((c) => !c.card)) return null;
    return { psychicId: p.p, deck: p.d, spread: p.s, cards, token };
  } catch {
    return null;
  }
}

// ---- What a reader notices across a spread ----
const TAROT_SUIT_THEMES: Record<string, string> = {
  Cups: "feelings and relationships",
  Wands: "energy, drive and ambition",
  Swords: "thoughts, words and conflict",
  Pentacles: "money, work and the body",
};
const PLAYING_SUIT_THEMES = Object.fromEntries(PLAYING_SUITS);
const COURT = new Set(["Page", "Knight", "Queen", "King", "Jack"]);
const NUMBER_WORDS = ["", "", "two", "three", "four", "five"];
const plural = (rank: string) => (rank === "Six" ? "Sixes" : `${rank}s`);

/** Plain-language patterns in a set of cards, the way a reader would point them out. */
export function patterns(deck: DeckId, drawn: DrawnCard[]): string[] {
  if (drawn.length < 2) return [];
  const out: string[] = [];
  const n = drawn.length;

  const bySuit = new Map<string, number>();
  for (const d of drawn) bySuit.set(d.card.suit, (bySuit.get(d.card.suit) ?? 0) + 1);
  const themes = deck === "tarot" ? TAROT_SUIT_THEMES : PLAYING_SUIT_THEMES;
  for (const [suit, count] of bySuit) {
    if (suit === "Major" || count < 2) continue;
    const share = count === n ? `all ${suit}` : `${NUMBER_WORDS[count]} ${suit}`;
    out.push(`${share}: this reading is mostly about ${themes[suit]}`);
  }
  const missing = Object.keys(themes).filter((s) => !bySuit.has(s));
  if (n >= 5 && missing.length === 1) out.push(`no ${missing[0]} at all: the answer doesn't lie in ${themes[missing[0]]}`);

  if (deck === "tarot") {
    const majors = bySuit.get("Major") ?? 0;
    if (majors >= 2 && majors >= n / 2) out.push(`${majors} of the ${n} cards are major arcana: something bigger than day-to-day life is moving here`);
    if (majors === 0 && n >= 3) out.push("no major arcana: this is in the user's own hands, everyday choices rather than fate");
    const reversed = drawn.filter((d) => d.reversed).length;
    if (reversed >= 2 && reversed >= n / 2) out.push(`${reversed} cards reversed: energy that's blocked, delayed or turned inward`);
  } else {
    const red = drawn.filter((d) => d.card.suit === "Hearts" || d.card.suit === "Diamonds").length;
    if (red === n) out.push("all red cards: a warm, favourable reading");
    else if (red === 0) out.push("all black cards: effort and obstacles, but nothing that can't be worked through");
  }

  const byRank = new Map<string, number>();
  for (const d of drawn) if (d.card.suit !== "Major") byRank.set(d.card.rank, (byRank.get(d.card.rank) ?? 0) + 1);
  for (const [rank, count] of byRank) {
    if (count < 2) continue;
    const what = rank === "Queen" ? "two women in this story, allies or rivals"
      : rank === "King" ? "two strong men or two authorities pulling on this"
      : rank === "Jack" || rank === "Page" ? "news or messages coming from more than one direction"
      : rank === "Knight" ? "a lot of comings and goings"
      : rank === "Ace" ? "more than one new beginning at once"
      : `the ${rank.toLowerCase()} is repeated, so its meaning is doubled`;
    out.push(`${NUMBER_WORDS[count]} ${plural(rank)}: ${what}`);
  }

  const court = drawn.filter((d) => COURT.has(d.card.rank)).length;
  if (court >= 2 && court >= n / 2) out.push("lots of picture cards: this is about people more than events");

  for (let i = 1; i < n; i++) {
    const a = drawn[i - 1], b = drawn[i];
    if (a.card.suit === b.card.suit && a.card.suit !== "Major" && a.reversed !== b.reversed) {
      out.push(`the ${b.card.name} lands ${b.reversed ? "reversed" : "upright"} right after the ${a.card.name} ${a.reversed ? "reversed" : "upright"}: the same suit flipping, so that energy is turning around`);
      break;
    }
  }
  return out;
}

// ---- The note sent to the psychic ----
const label = (d: DrawnCard) => `${d.card.name}${d.card.numeral ? ` (${d.card.numeral})` : ""}${d.reversed ? ", reversed" : ""}`;

/** Describes the cards turned so far and tells the psychic which one to read now. */
export function spreadNote(s: Spread, turned: number, meanings: CardMeaning[] = []): string {
  const { name, positions } = SPREADS[s.spread];
  const deckName = DECKS[s.deck].name;
  const own = new Map(meanings.map((m) => [m.card.toLowerCase(), m]));
  const total = positions.length;
  const shown = s.cards.slice(0, turned);

  const lines = shown.map((d, i) => {
    const mine = own.get(d.card.name.toLowerCase());
    const traditional = d.reversed ? d.card.reversed || d.card.upright : d.card.upright;
    const personal = d.reversed ? mine?.reversed : mine?.upright;
    let line = `${i + 1}. ${positions[i]}: ${label(d)}. Traditional meaning${d.reversed ? " reversed" : ""}: ${traditional}`;
    if (personal) line += ` Your own reading of it: ${personal}`;
    if (mine?.memory) line += ` A memory you have with this card: ${mine.memory}`;
    return line;
  });

  const parts = [
    `[The app just ${turned === 1 ? `laid out a ${name} from your ${deckName}` : `turned card ${turned} of your ${name}`} for this question. The draw is real and random: read these cards, never invent others.`,
    `Cards turned so far:\n${lines.join("\n")}`,
  ];

  if (total === 1) {
    parts.push("Read this card for their question, in your own way.");
  } else if (turned < total) {
    const down = positions.slice(turned);
    if (turned > 1) parts.push("Before the card, react briefly to what the user just said if it needs it.");
    parts.push(
      `Read only card ${turned} (${positions[turned - 1]})${turned > 1 ? ", in light of the cards before it" : ""}. ` +
      `${down.length} card${down.length === 1 ? " is" : "s are"} still face down (${down.join(", ")}): never name or guess them. ` +
      "Then check in with the user in your own way, for example whether it rings true or what it brings up, and let them know you'll turn the next card when they're ready.",
    );
  } else {
    if (turned > 1) parts.push("Before the card, react briefly to what the user just said if it needs it.");
    const seen = patterns(s.deck, s.cards);
    parts.push(
      `This is the last card. Read it, then read the spread as a whole: how the cards talk to each other, what changes from one to the next, and what it all adds up to for their question.` +
      (seen.length ? ` Things a reader would notice: ${seen.join("; ")}. Bring in one or two of these naturally, not as a list.` : ""),
    );
  }
  parts.push("Hard cards are never doom: stay kind and give them something they can do.]");
  return parts.join("\n");
}

/** What the app shows for a turned card. */
export function publicCard(d: DrawnCard, position: string) {
  return {
    position,
    name: d.card.name,
    numeral: d.card.numeral,
    suit: d.card.suit,
    rank: d.card.rank,
    reversed: d.reversed,
    meaning: d.reversed ? d.card.reversed || d.card.upright : d.card.upright,
  };
}
