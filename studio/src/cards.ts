// The cards in each deck, by name, for the Deck tab. Names match the reading server's decks
// (server/src/cards.ts), which also holds the traditional meanings used when a psychic has none of their own.

export type DeckId = "tarot" | "playing";

export const isDeck = (v: unknown): v is DeckId => v === "tarot" || v === "playing";

const MAJORS = [
  "The Fool", "The Magician", "The High Priestess", "The Empress", "The Emperor", "The Hierophant", "The Lovers",
  "The Chariot", "Strength", "The Hermit", "Wheel of Fortune", "Justice", "The Hanged Man", "Death", "Temperance",
  "The Devil", "The Tower", "The Star", "The Moon", "The Sun", "Judgement", "The World",
];
const TAROT_RANKS = ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Page", "Knight", "Queen", "King"];
const PLAYING_RANKS = ["Ace", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten", "Jack", "Queen", "King"];

export const DECKS: Record<DeckId, { name: string; reversals: boolean; groups: { name: string; cards: string[] }[] }> = {
  tarot: {
    name: "Tarot",
    reversals: true,
    groups: [
      { name: "Major arcana", cards: MAJORS },
      ...["Cups", "Wands", "Swords", "Pentacles"].map((suit) => ({ name: suit, cards: TAROT_RANKS.map((r) => `${r} of ${suit}`) })),
    ],
  },
  playing: {
    name: "Playing cards",
    reversals: false,
    groups: ["Hearts", "Diamonds", "Clubs", "Spades"].map((suit) => ({ name: suit, cards: PLAYING_RANKS.map((r) => `${r} of ${suit}`) })),
  },
};

/** The card's proper name in this deck, or null if it isn't in it. Ignores case and extra spaces. */
export function cardName(deck: DeckId, name: string): string | null {
  const want = name.toLowerCase().replace(/\s+/g, " ").trim();
  for (const g of DECKS[deck].groups) for (const c of g.cards) if (c.toLowerCase() === want) return c;
  return null;
}
