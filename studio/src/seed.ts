// Imports personas from a folder of markdown files (the format in server/psychics/README.md).

import fs from "node:fs";
import path from "node:path";
import { type DeckId, cardName } from "./cards.ts";
import { type Deck, fillReadingStyle, getPsychic, importPsychic, LIST_FIELDS, PERSONA_FIELDS, type Persona } from "./db.ts";

function sections(md: string): [string, string][] {
  const parts = md.split(/^## (.+)$/m);
  const out: [string, string][] = [];
  for (let i = 1; i < parts.length; i += 2) out.push([parts[i].trim(), parts[i + 1].trim()]);
  return out;
}

const title = (md: string) => md.match(/^# (.+)$/m)?.[1].trim() ?? null;

const bullets = (text: string) =>
  text.split("\n").map((l) => l.trim()).filter((l) => l.startsWith("- ")).map((l) => l.slice(2).trim());

function readFolder(dir: string) {
  const personaMd = fs.readFileSync(path.join(dir, "persona.md"), "utf8");
  const byHeading = new Map(sections(personaMd).map(([h, b]) => [h.toLowerCase(), b]));
  const persona = {} as Persona;
  for (const f of PERSONA_FIELDS) persona[f] = f === "name" ? (title(personaMd) ?? "") : (byHeading.get(f) ?? "");
  for (const f of LIST_FIELDS) persona[f] = bullets(byHeading.get(f) ?? "");
  persona.howIRead = byHeading.get("how i read") ?? "";

  const examplesPath = path.join(dir, "examples.md");
  const examples = fs.existsSync(examplesPath)
    ? sections(fs.readFileSync(examplesPath, "utf8")).map(([user, reply]) => ({ user, reply }))
    : [];

  const docs = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".md") && f !== "persona.md" && f !== "examples.md" && f !== "deck.md")
    .sort()
    .map((file) => {
      const md = fs.readFileSync(path.join(dir, file), "utf8");
      return { title: title(md) ?? path.basename(file, ".md"), body: md.replace(/^# .+$/m, "").trim() };
    });

  const deckPath = path.join(dir, "deck.md");
  const deck = fs.existsSync(deckPath) ? readDeck(fs.readFileSync(deckPath, "utf8")) : { deck: "tarot" as const, cardMeanings: [] };

  return { persona, examples, docs, deck };
}

/** Reads deck.md (see server/psychics/README.md). Cards that aren't in the deck are skipped. */
function readDeck(md: string): Deck {
  const declared = md.match(/^deck:\s*(.+)$/im)?.[1].trim().toLowerCase() ?? "tarot";
  const deck: DeckId = declared.startsWith("playing") ? "playing" : "tarot";
  const cardMeanings = sections(md).flatMap(([heading, body]) => {
    const card = cardName(deck, heading);
    if (!card) return [];
    const field = (name: string) => body.match(new RegExp(`^${name}:\\s*(.+)$`, "im"))?.[1].trim() ?? "";
    const tagged = /^(upright|reversed|memory):/im.test(body);
    return [{ card, upright: tagged ? field("Upright") : body.trim(), reversed: field("Reversed"), memory: field("Memory") }];
  });
  return { deck, cardMeanings };
}

function folders(root: string): { id: string; dir: string }[] {
  if (!fs.existsSync(root)) return [];
  return fs.readdirSync(root, { withFileTypes: true })
    .filter((e) => e.isDirectory() && !/^[._]/.test(e.name) && fs.existsSync(path.join(root, e.name, "persona.md")))
    .map((e) => ({ id: e.name, dir: path.join(root, e.name) }));
}

/** For a database upgraded to decks: fills each psychic's "How I read" and deck from its files, if it has neither. */
export function fillReadingStylesFrom(root: string): string[] {
  const filled: string[] = [];
  for (const { id, dir } of folders(root)) {
    if (!getPsychic(id)) continue;
    const { persona, deck } = readFolder(dir);
    if (fillReadingStyle(id, persona.howIRead, deck)) filled.push(id);
  }
  return filled;
}

export function seedFrom(root: string): number {
  if (!fs.existsSync(root)) {
    console.warn(`Seed folder ${root} not found; starting with no psychics.`);
    return 0;
  }
  let count = 0;
  for (const { id, dir } of folders(root)) {
    const { persona, examples, docs, deck } = readFolder(dir);
    importPsychic(id, persona, examples, docs, deck);
    count++;
  }
  return count;
}
