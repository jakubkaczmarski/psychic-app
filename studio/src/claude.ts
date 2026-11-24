// Drafting with Claude: reads everything written about a psychic (fields, documents, examples, card meanings)
// and writes the parts an editor asks for. Drafts are applied by the caller and land in History, so they
// can be undone like any other edit.

import Anthropic from "@anthropic-ai/sdk";
import { DECKS } from "./cards.ts";
import {
  APP_LIST_FIELDS, APP_TEXT_FIELDS, BUILT_IN, LIST_FIELDS, PERSONA_FIELDS,
  type AppProfile, type CardMeaning, type Example, type Persona, type Psychic,
} from "./db.ts";

const MODEL = process.env.STUDIO_MODEL ?? "claude-opus-5-5";
// Medium keeps drafts cheap (it's Claude Opus 5.5's default); set STUDIO_EFFORT=high for more careful drafts.
const EFFORT = (["low", "medium", "high"] as const).find((e) => e === process.env.STUDIO_EFFORT) ?? "medium";

/** True when the studio has credentials for the Claude API. */
export const claudeAvailable = () => Boolean(process.env.ANTHROPIC_API_KEY || process.env.ANTHROPIC_AUTH_TOKEN);

let client: Anthropic | null = null;
const api = () => (client ??= new Anthropic());

export interface DraftRequest {
  /** Persona fields to write: only the empty ones, or all of them. */
  persona?: "empty" | "all";
  /** App profile fields to write: only the empty ones, or all of them. */
  app?: "empty" | "all";
  /** How many new example replies to write. */
  examples?: number;
  /** Card meanings: these cards, or `count` cards Claude picks as right for this character. */
  cards?: { names?: string[]; count?: number };
  /** Topic of a new background document. */
  document?: string;
  /** Free-text direction from the editor. */
  notes?: string;
}

export interface Draft {
  persona?: Partial<Persona>;
  app?: Partial<AppProfile>;
  examples?: Example[];
  cardMeanings?: CardMeaning[];
  document?: { title: string; body: string };
}

export class DraftError extends Error {}

// ---- What Claude is told ----
const FIELD_GUIDE: Record<keyof Persona, string> = {
  name: "Display name, e.g. 'Madame Selene' or 'Grandma Ivy'.",
  specialty: "One short line shown in the app, e.g. 'Love & relationships'.",
  backstory: "Who they are and where they come from, 2 to 5 sentences.",
  voice: "How they sound: rhythm, vocabulary, attitude, what they call people.",
  texting: "How they text: number of messages per reply (1 to 4), message length, punctuation, capitals, typos.",
  catchphrases: "2 to 4 signature phrases, each one short. Used sparingly in readings.",
  never: "4 to 6 things this character never says or does (short items, e.g. 'curses or bad omens').",
  quirks: "Habits that show up in readings, 2 to 4 sentences.",
  others: "What they think of the other psychics in the app, 1 to 3 sentences.",
  ritual: "How they interpret the result of their ritual button in the app. <ritual_result> says exactly what the app gives them; describe how they read that result, and never invent a different ritual.",
  howIRead: "Their method with cards: whether they ask a question before drawing, how much they hedge, whether they name a card or hint at it first, how they handle a hard card like the Tower while staying kind, how they pace a spread turned one card at a time.",
};

const RULES = `About the app: "As Fate Would Have It" is an entertainment iOS app where people text AI psychic characters for fun. Each psychic has their own voice, specialty and ritual. Readings are playful and kind and leave people feeling better about the future: specific-sounding but harmless guidance, small actions, gentle nudges.

What you write becomes the character bible the psychic is played from. Rules for everything you write:
- Make the character vivid, specific and consistent with everything already written. Build on the documents and fields; never contradict them.
- Keep the voice distinct from the rest of the cast.
- Characters are warm underneath, never cruel. No curses, doom, frightening predictions, death or illness.
- Treat cultures and backgrounds with dignity: no fake accents, broken English, stereotypes or caricature.
- No medical, legal or financial instructions.
- Plain text only inside each field: no markdown, headings or emoji. Use contractions. No em dashes.`;

const RITUALS: Record<string, string> = {
  selene: "The app gives the real phase of tonight's moon.",
  kaz: "The app gives ratings out of 5 for love, money and energy this week.",
  ivy: "The app gives a tea-leaf symbol and where it sits in the cup (rim = soon, middle = weeks, bottom = further off).",
  zephyr: "The app gives three random things seen in the crystal ball.",
  mirela: "The app draws one real playing card.",
};

function describe(p: Psychic, cast: { id: string; name: string; specialty: string }[]): string {
  const field = (k: keyof Persona) => {
    const v = p[k];
    const text = Array.isArray(v) ? v.map((x) => `- ${x}`).join("\n") : v;
    return `<field name="${k}">\n${text || "(empty)"}\n</field>`;
  };
  const docs = p.documents.filter((d) => d.body.trim());
  const deck = DECKS[p.deck];
  return [
    `<psychic id="${p.id}">`,
    ...[...PERSONA_FIELDS, ...LIST_FIELDS, "howIRead" as const].map(field),
    `<app_profile>\n${[...APP_TEXT_FIELDS, ...APP_LIST_FIELDS].map((k) => {
      const v = p.app[k];
      return `${k}: ${Array.isArray(v) ? (v.length ? v.join(" | ") : "(empty)") : v || "(empty)"}`;
    }).join("\n")}\n</app_profile>`,
    `<deck>${deck.name}${deck.reversals ? " (cards can land reversed)" : " (read upright only)"}</deck>`,
    // Psychics added in the studio draw one real card from their deck as their ritual.
    `<ritual_result>${RITUALS[p.id] ?? `The app draws one real card from their ${DECKS[p.deck].name.toLowerCase()} deck.`}</ritual_result>`,
    docs.length
      ? `<documents>\n${docs.map((d) => `<document title="${d.title || "Untitled"}"${d.enabled ? "" : ' used_in_readings="no"'}>\n${d.body}\n</document>`).join("\n")}\n</documents>`
      : "<documents>(none yet)</documents>",
    p.examples.length
      ? `<examples>\n${p.examples.map((e) => `<example>\nUser: ${e.user}\n${p.name || "Psychic"}:\n${e.reply}\n</example>`).join("\n")}\n</examples>`
      : "<examples>(none yet)</examples>",
    p.cardMeanings.length
      ? `<card_meanings>\n${p.cardMeanings.map((m) => `- ${m.card}: upright: ${m.upright || "-"} / reversed: ${m.reversed || "-"} / memory: ${m.memory || "-"}`).join("\n")}\n</card_meanings>`
      : "<card_meanings>(none yet)</card_meanings>",
    "</psychic>",
    `<cast>\n${cast.filter((c) => c.id !== p.id).map((c) => `- ${c.name || c.id}: ${c.specialty || "no specialty yet"}`).join("\n")}\n</cast>`,
  ].filter(Boolean).join("\n");
}

const str = { type: "string" } as const;
const object = (properties: Record<string, unknown>) => ({
  type: "object", properties, required: Object.keys(properties), additionalProperties: false,
});

async function ask<T>(context: string, task: string, notes: string | undefined, schema: Record<string, unknown>): Promise<T> {
  const content = `${context}\n\n${notes?.trim() ? `<editor_notes>\n${notes.trim()}\n</editor_notes>\n\n` : ""}${task}`;
  let response: Anthropic.Beta.BetaMessage;
  try {
    response = await api().beta.messages.create({
      model: MODEL,
      max_tokens: 16000,
      system: RULES,
      messages: [{ role: "user", content }],
      output_config: { effort: EFFORT, format: { type: "json_schema", schema } },
      // If Claude declines, the API re-runs the request on a fallback model automatically.
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
    });
  } catch (err) {
    if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
      throw new DraftError("The Claude API key was rejected. Check ANTHROPIC_API_KEY in the studio's settings.");
    }
    if (err instanceof Anthropic.RateLimitError || (err instanceof Anthropic.APIError && err.status === 529)) {
      throw new DraftError("Claude is busy right now. Try again in a minute.");
    }
    if (err instanceof Anthropic.APIError) {
      console.error(`Claude API error ${err.status}:`, err.message);
      throw new DraftError("Claude couldn't write this right now. Try again.");
    }
    if (err instanceof Anthropic.APIConnectionError) throw new DraftError("Couldn't reach Claude. Check the connection.");
    throw err;
  }
  const u = response.usage;
  console.log(`Claude draft (${response.model}, ${EFFORT}): ${u.input_tokens} tokens in, ${u.output_tokens} out.`);
  if (response.stop_reason === "refusal") throw new DraftError("Claude declined to write this. Try different notes.");
  if (response.stop_reason === "max_tokens") throw new DraftError("Claude ran out of room. Ask for fewer things at once.");
  const text = response.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  try {
    return JSON.parse(text) as T;
  } catch {
    throw new DraftError("Claude's answer couldn't be read. Try again.");
  }
}

const APP_GUIDE: Record<keyof AppProfile, string> = {
  short: "Short name used in buttons and sentences, e.g. 'Selene' for 'Madame Selene'.",
  tagline: "One punchy line under their name on the home screen, under 45 characters, e.g. 'Reads the moon, and your texts.'",
  bio: "2 or 3 sentences for their profile page, written about them in the third person, warm and intriguing.",
  tags: "Exactly 3 short tags for their profile, e.g. 'Tarot', 'Moon phases', 'Gentle'.",
  greeting: "First chat message, in their texting voice, under 35 words. Must contain {name} where the user's name goes. Ends by inviting a question.",
  signLine: "One line said when they learn the user's star sign. Must contain {sign}.",
  welcomeBack: "Message when the user comes back after a while, in their voice. Must contain {name}.",
  defaultName: "What they call the user when there's no name, e.g. 'love', 'dear one', 'friend'.",
  sample: "A short sample of a reading for their profile page, 1 or 2 sentences in their voice.",
  asks: "3 example questions users might tap to ask them, matching their specialty, each under 40 characters.",
  cardIntro: "What they say while drawing one card, under 15 words.",
  spreadIntro: "What they say while laying out several cards face down. Must contain {n} for the number of cards (written as a word). Under 20 words.",
  ritualButton: "Label of their main ritual button in the chat, 2 to 4 words. Their ritual is drawing a card from their deck, phrased their way, e.g. 'Cut the deck'.",
  ritualIntro: "What they say as they perform that ritual, under 20 words.",
  moods: "6 short daily moods shown on their card in the app, under 45 characters each, specific and in character, e.g. 'Baking for the whole street'.",
  morningOpenings: "3 short openings for a morning notification, in their voice, e.g. 'Morning, love.'",
  color: "Their accent colour as a hex code like #6A58B4: a rich, mid-dark colour that suits them and reads on parchment.",
  typing: "How fast they text: 'slow', 'medium' or 'fast'.",
};

async function draftApp(context: string, p: Psychic, mode: "empty" | "all", notes?: string) {
  const all = [...APP_TEXT_FIELDS, ...APP_LIST_FIELDS];
  const keys = all.filter((k) => mode === "all" || (Array.isArray(p.app[k]) ? !p.app[k].length : !String(p.app[k]).trim()));
  if (!keys.length) return {};
  const properties = Object.fromEntries(keys.map((k) => [k,
    (APP_LIST_FIELDS as readonly string[]).includes(k) ? { type: "array", items: str }
      : k === "typing" ? { type: "string", enum: ["slow", "medium", "fast"] } : str]));
  const builtIn = BUILT_IN.has(p.id);
  const task = `Write what the iOS app shows for ${p.name || "this psychic"}: the home screen card, profile page, chat greeting and buttons. Everything in their voice where it's something they say.${builtIn ? " They're already in the app; this text replaces the built-in text." : ""}${mode === "all" ? " Rewrite where it can be better." : " Only these fields are empty; the rest stay."}
${keys.map((k) => `- ${k}: ${APP_GUIDE[k]}`).join("\n")}`;
  return ask<Partial<AppProfile>>(context, task, notes, object(properties));
}

// ---- The parts ----
async function draftPersona(context: string, p: Psychic, mode: "empty" | "all", notes?: string) {
  // The name is the editor's to choose; Claude writes everything else.
  const keys = [...PERSONA_FIELDS, ...LIST_FIELDS, "howIRead" as const]
    .filter((k) => k !== "name")
    .filter((k) => mode === "all" || (Array.isArray(p[k]) ? !p[k].length : !String(p[k]).trim()));
  if (!keys.length) return {};
  const properties = Object.fromEntries(keys.map((k) => [k, (LIST_FIELDS as readonly string[]).includes(k) ? { type: "array", items: str } : str]));
  const task = `Write these fields of ${p.name || "this psychic"}'s character bible${mode === "all" ? ", rewriting the current text where it can be better (keep what already works and everything the documents establish)" : " (they're empty now; the others stay as they are)"}:
${keys.map((k) => `- ${k}: ${FIELD_GUIDE[k]}`).join("\n")}`;
  return ask<Partial<Persona>>(context, task, notes, object(properties));
}

async function draftExamples(context: string, p: Psychic, count: number, notes?: string) {
  const task = `Write ${count} new example exchanges that show how ${p.name || "this psychic"} texts in a reading. Each is something a user says, then the psychic's reply.
- Vary the questions: love, work, family, friends, money worries, small daily dilemmas, a card or ritual result, someone just saying hi. Don't repeat the existing examples.
- Replies follow their texting style exactly. Separate chat bubbles with a blank line. Each bubble under 25 words, at most 4 bubbles, under 80 words in all.
- Sound like a person texting: contractions, varied openings, no tidy three-part structure, no recap.
- Never mention drawing, pulling or turning a card or naming one that came up: in the app, cards are drawn for real and the psychic is told what came up, so an example that invents a card would teach them to make cards up. Their advice comes from their wisdom, not a card.`;
  const out = await ask<{ examples: Example[] }>(context, task, notes,
    object({ examples: { type: "array", items: object({ user: str, reply: str }) } }));
  return out.examples.filter((e) => e.user?.trim() && e.reply?.trim()).slice(0, count);
}

async function draftCards(context: string, p: Psychic, req: { names?: string[]; count?: number }, notes?: string) {
  const deck = DECKS[p.deck];
  const all = deck.groups.flatMap((g) => g.cards);
  const names = req.names?.filter((n) => all.includes(n)) ?? [];
  const count = names.length || Math.min(Math.max(req.count ?? 8, 1), 20);
  const have = new Set(p.cardMeanings.map((m) => m.card));
  const task = `${names.length
    ? `Write ${p.name || "this psychic"}'s own reading of ${names.length === 1 ? "this card" : "these cards"}: ${names.join(", ")}.`
    : `Pick the ${count} cards from the ${deck.name.toLowerCase()} deck that ${p.name || "this psychic"} would have the strongest personal feelings about (favourites, feared ones, ones tied to their life), skipping cards they already have a meaning for${have.size ? ` (${[...have].join(", ")})` : ""}, and write their own reading of each.`}
For each card:
- upright: their personal take, in a sentence or two, as a fact about how they read it (e.g. "Her wish card. Whatever they asked, the heart's wish has a real chance.").${deck.reversals ? "\n- reversed: their take when it lands upside down." : "\n- reversed: always an empty string (this deck isn't read reversed)."}
- memory: optional. A small moment from their life tied to this card, or an empty string. Give a memory to roughly one card in three.
Hard cards are never doom in their reading: give them a kind, practical turn.`;
  const out = await ask<{ cards: CardMeaning[] }>(context, task, notes,
    object({ cards: { type: "array", items: object({ card: { type: "string", enum: names.length ? names : all }, upright: str, reversed: str, memory: str }) } }));
  return out.cards
    .filter((m) => all.includes(m.card))
    .map((m) => ({ ...m, reversed: deck.reversals ? m.reversed : "" }));
}

async function draftDocument(context: string, p: Psychic, topic: string, notes?: string) {
  const task = `Write a background document for ${p.name || "this psychic"} about: ${topic}
It's reference material the psychic draws on in readings without reciting it. Write it as facts about the character, not instructions ("Her grandmother Lela read cards at every wedding", not "Always mention Lela"). Specific names, places, habits and small stories. 150 to 400 words. Plain paragraphs, no markdown.
The title is a few words, like "Family" or "The shop on Via Roma".`;
  return ask<{ title: string; body: string }>(context, task, notes, object({ title: str, body: str }));
}

/** Writes the requested parts, in parallel. Nothing is saved here. */
export async function draft(p: Psychic, cast: { id: string; name: string; specialty: string }[], req: DraftRequest): Promise<Draft> {
  if (!claudeAvailable()) throw new DraftError("Add ANTHROPIC_API_KEY to the studio's settings to write with Claude.");
  const context = describe(p, cast);
  const [persona, app, examples, cardMeanings, document] = await Promise.all([
    req.persona ? draftPersona(context, p, req.persona, req.notes) : undefined,
    req.app ? draftApp(context, p, req.app, req.notes) : undefined,
    req.examples ? draftExamples(context, p, req.examples, req.notes) : undefined,
    req.cards ? draftCards(context, p, req.cards, req.notes) : undefined,
    req.document?.trim() ? draftDocument(context, p, req.document.trim(), req.notes) : undefined,
  ]);
  return { persona, app, examples, cardMeanings, document };
}
