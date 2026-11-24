// SQLite storage for psychics, their example replies and their documents.

import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";
import { type DeckId, cardName, isDeck } from "./cards.ts";

export const PERSONA_FIELDS = [
  "name", "specialty", "backstory", "voice", "texting", "quirks", "others", "ritual",
] as const;
export const LIST_FIELDS = ["catchphrases", "never"] as const;

type TextField = (typeof PERSONA_FIELDS)[number];
type ListField = (typeof LIST_FIELDS)[number];

/** Required fields, plus "How I read", which is optional so older psychics stay live without it. */
export type Persona = Record<TextField, string> & Record<ListField, string[]> & { howIRead: string };

/** A psychic's own reading of one card. Blank parts fall back to the traditional meaning. */
export interface CardMeaning {
  card: string;
  upright: string;
  reversed: string;
  memory: string;
}

/** What the iOS app shows for a psychic: the home screen card, profile page, chat greeting and so on. */
export const APP_TEXT_FIELDS = [
  "short", "tagline", "bio", "greeting", "signLine", "welcomeBack", "defaultName", "sample",
  "cardIntro", "spreadIntro", "ritualButton", "ritualIntro", "color", "typing",
] as const;
export const APP_LIST_FIELDS = ["tags", "asks", "moods", "morningOpenings"] as const;
export type AppProfile = Record<(typeof APP_TEXT_FIELDS)[number], string> & Record<(typeof APP_LIST_FIELDS)[number], string[]>;

/** Psychics built into the iOS app. Their app profile only overrides the built-in text, field by field. */
export const BUILT_IN = new Set(["selene", "kaz", "ivy", "zephyr", "mirela"]);

export function emptyApp(): AppProfile {
  const a = {} as AppProfile;
  for (const f of APP_TEXT_FIELDS) a[f] = "";
  for (const f of APP_LIST_FIELDS) a[f] = [];
  return a;
}

function toApp(json: unknown): AppProfile {
  const a = emptyApp();
  let raw: Record<string, unknown> = {};
  try { raw = typeof json === "string" ? JSON.parse(json) : {}; } catch { /* empty */ }
  for (const f of APP_TEXT_FIELDS) if (typeof raw[f] === "string") a[f] = raw[f] as string;
  for (const f of APP_LIST_FIELDS) if (Array.isArray(raw[f])) a[f] = (raw[f] as unknown[]).filter((x): x is string => typeof x === "string");
  return a;
}

/** App fields a new psychic needs before the app can show them. Built-in psychics need none. */
export function missingForApp(p: { id: string; app: AppProfile }): string[] {
  if (BUILT_IN.has(p.id)) return [];
  const missing: string[] = [];
  for (const f of ["tagline", "bio", "greeting"] as const) if (!p.app[f].trim()) missing.push(f);
  if (!p.app.asks.length) missing.push("asks");
  return missing;
}

export interface Deck {
  deck: DeckId;
  cardMeanings: CardMeaning[];
}

export interface Example {
  user: string;
  reply: string;
}

export interface Doc {
  id: number;
  title: string;
  body: string;
  enabled: boolean;
  updatedAt: string;
}

export interface Psychic extends Persona, Deck {
  id: string;
  app: AppProfile;
  /** The editor switched on "Show in the app". */
  inApp: boolean;
  updatedAt: string;
  /** Changes whenever the photo does; null when there's no photo. */
  photoId: number | null;
  examples: Example[];
  documents: Doc[];
}

/** The shape the reading server expects (matches PsychicPersona in server/src/psychics.ts). */
export interface PublishedPersona extends Persona, Deck {
  /** For the iOS app; `show` says whether a psychic that isn't built in should appear. */
  app: AppProfile & { show: boolean };
  /** Id of the current photo (fetch it from /v1/photos/<id>); null when there's none. Changes when the photo does. */
  photoId: number | null;
  examples: Example[];
  notes: { title: string; body: string }[];
}

const dataDir = path.resolve(process.env.STUDIO_DATA_DIR ?? "./data");
fs.mkdirSync(dataDir, { recursive: true });
const db = new DatabaseSync(path.join(dataDir, "studio.db"));

db.exec(`
  PRAGMA journal_mode = WAL;
  PRAGMA foreign_keys = ON;
  CREATE TABLE IF NOT EXISTS psychics (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL DEFAULT '',
    specialty TEXT NOT NULL DEFAULT '',
    backstory TEXT NOT NULL DEFAULT '',
    voice TEXT NOT NULL DEFAULT '',
    texting TEXT NOT NULL DEFAULT '',
    catchphrases TEXT NOT NULL DEFAULT '[]',
    never TEXT NOT NULL DEFAULT '[]',
    quirks TEXT NOT NULL DEFAULT '',
    others TEXT NOT NULL DEFAULT '',
    ritual TEXT NOT NULL DEFAULT '',
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS examples (
    id INTEGER PRIMARY KEY,
    psychic_id TEXT NOT NULL REFERENCES psychics(id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    user TEXT NOT NULL,
    reply TEXT NOT NULL
  );
  CREATE TABLE IF NOT EXISTS documents (
    id INTEGER PRIMARY KEY,
    psychic_id TEXT NOT NULL REFERENCES psychics(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE TABLE IF NOT EXISTS revisions (
    id INTEGER PRIMARY KEY,
    psychic_id TEXT NOT NULL REFERENCES psychics(id) ON DELETE CASCADE,
    kind TEXT NOT NULL,
    label TEXT NOT NULL,
    snapshot TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
  CREATE INDEX IF NOT EXISTS revisions_psychic ON revisions (psychic_id, id);
  CREATE TABLE IF NOT EXISTS photos (
    id INTEGER PRIMARY KEY,
    psychic_id TEXT NOT NULL REFERENCES psychics(id) ON DELETE CASCADE,
    mime TEXT NOT NULL,
    data BLOB NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
  );
`);

// Older databases: add newer columns to psychics.
const columns = () => (db.prepare("PRAGMA table_info(psychics)").all() as { name: string }[]).map((c) => c.name);
if (!columns().includes("photo_id")) db.exec("ALTER TABLE psychics ADD COLUMN photo_id INTEGER");
/** True when this start added "How I read" and decks: psychics created before then can be filled from the files. */
export const addedDecks = !columns().includes("deck");
if (addedDecks) {
  db.exec(`
    ALTER TABLE psychics ADD COLUMN how_i_read TEXT NOT NULL DEFAULT '';
    ALTER TABLE psychics ADD COLUMN deck TEXT NOT NULL DEFAULT 'tarot';
  `);
}
if (!columns().includes("app")) {
  db.exec(`
    ALTER TABLE psychics ADD COLUMN app TEXT NOT NULL DEFAULT '{}';
    ALTER TABLE psychics ADD COLUMN in_app INTEGER NOT NULL DEFAULT 0;
  `);
}
db.exec(`
  CREATE TABLE IF NOT EXISTS card_meanings (
    psychic_id TEXT NOT NULL REFERENCES psychics(id) ON DELETE CASCADE,
    card TEXT NOT NULL,
    upright TEXT NOT NULL DEFAULT '',
    reversed TEXT NOT NULL DEFAULT '',
    memory TEXT NOT NULL DEFAULT '',
    PRIMARY KEY (psychic_id, card)
  );
`);

let txDepth = 0;

/** Runs fn in a transaction. Nested calls join the outer transaction. */
function tx<T>(fn: () => T): T {
  if (txDepth > 0) return fn();
  db.exec("BEGIN");
  txDepth++;
  try {
    const result = fn();
    db.exec("COMMIT");
    return result;
  } catch (err) {
    db.exec("ROLLBACK");
    throw err;
  } finally {
    txDepth--;
  }
}

type Row = Record<string, unknown>;

function toPersona(row: Row): Persona {
  const p = {} as Persona;
  for (const f of PERSONA_FIELDS) p[f] = String(row[f] ?? "");
  for (const f of LIST_FIELDS) p[f] = JSON.parse(String(row[f] ?? "[]"));
  p.howIRead = String(row.how_i_read ?? "");
  return p;
}

function toDoc(row: Row): Doc {
  return {
    id: Number(row.id),
    title: String(row.title),
    body: String(row.body),
    enabled: Boolean(row.enabled),
    updatedAt: String(row.updated_at),
  };
}

const touch = (id: string) =>
  db.prepare("UPDATE psychics SET updated_at = datetime('now') WHERE id = ?").run(id);

export function isEmpty(): boolean {
  return (db.prepare("SELECT COUNT(*) AS n FROM psychics").get() as Row).n === 0;
}

export function listPsychics() {
  const rows = db
    .prepare(`
      SELECT p.*,
        (SELECT COUNT(*) FROM examples e WHERE e.psychic_id = p.id) AS example_count,
        (SELECT COUNT(*) FROM documents d WHERE d.psychic_id = p.id) AS document_count
      FROM psychics p ORDER BY p.name COLLATE NOCASE, p.id`)
    .all() as Row[];
  return rows.map((row) => {
    const psychic = getPsychic(String(row.id))!;
    return {
      id: String(row.id),
      name: String(row.name),
      specialty: String(row.specialty),
      photoId: psychic.photoId,
      updatedAt: String(row.updated_at),
      exampleCount: Number(row.example_count),
      documentCount: Number(row.document_count),
      missing: missingParts(psychic),
      appMissing: missingForApp(psychic),
      inApp: psychic.inApp,
      builtIn: BUILT_IN.has(psychic.id),
      promptChars: promptChars(psychic),
    };
  });
}

export function getPsychic(id: string): Psychic | null {
  const row = db.prepare("SELECT * FROM psychics WHERE id = ?").get(id) as Row | undefined;
  if (!row) return null;
  const examples = (
    db.prepare("SELECT user, reply FROM examples WHERE psychic_id = ? ORDER BY position").all(id) as Row[]
  ).map((e) => ({ user: String(e.user), reply: String(e.reply) }));
  const documents = (
    db.prepare("SELECT * FROM documents WHERE psychic_id = ? ORDER BY title COLLATE NOCASE, id").all(id) as Row[]
  ).map(toDoc);
  const photoId = row.photo_id === null || row.photo_id === undefined ? null : Number(row.photo_id);
  const deck: DeckId = isDeck(row.deck) ? row.deck : "tarot";
  const cardMeanings = (
    db.prepare("SELECT card, upright, reversed, memory FROM card_meanings WHERE psychic_id = ? ORDER BY rowid").all(id) as Row[]
  ).map((m) => ({ card: String(m.card), upright: String(m.upright), reversed: String(m.reversed), memory: String(m.memory) }));
  return {
    id, updatedAt: String(row.updated_at), photoId, ...toPersona(row), deck, cardMeanings,
    app: toApp(row.app), inApp: Boolean(row.in_app), examples, documents,
  };
}

export function createPsychic(id: string, name: string) {
  tx(() => {
    db.prepare("INSERT INTO psychics (id, name) VALUES (?, ?)").run(id, name);
    record(id, "created", "Created");
  });
}

export function updatePersona(id: string, persona: Persona) {
  db.prepare(`
    UPDATE psychics SET name = ?, specialty = ?, backstory = ?, voice = ?, texting = ?,
      catchphrases = ?, never = ?, quirks = ?, others = ?, ritual = ?, how_i_read = ?, updated_at = datetime('now')
    WHERE id = ?`).run(
    persona.name, persona.specialty, persona.backstory, persona.voice, persona.texting,
    JSON.stringify(persona.catchphrases), JSON.stringify(persona.never),
    persona.quirks, persona.others, persona.ritual, persona.howIRead ?? "", id,
  );
  record(id, "persona", "Edited the persona", true);
}

/** Saves what the app shows for this psychic, and whether a new psychic appears in the app. */
export function updateApp(id: string, app: AppProfile, inApp: boolean) {
  const before = getPsychic(id);
  db.prepare("UPDATE psychics SET app = ?, in_app = ?, updated_at = datetime('now') WHERE id = ?")
    .run(JSON.stringify(app), inApp ? 1 : 0, id);
  if (before && before.inApp !== inApp) record(id, "app-show", inApp ? "Shown in the app" : "Hidden from the app");
  else record(id, "app", "Edited the app profile", true);
}

/** Sets the deck and replaces the psychic's own card meanings. Meanings for cards not in the deck are dropped. */
export function updateDeck(id: string, deck: Deck) {
  tx(() => {
    db.prepare("UPDATE psychics SET deck = ?, updated_at = datetime('now') WHERE id = ?").run(deck.deck, id);
    db.prepare("DELETE FROM card_meanings WHERE psychic_id = ?").run(id);
    const insert = db.prepare(
      "INSERT OR REPLACE INTO card_meanings (psychic_id, card, upright, reversed, memory) VALUES (?, ?, ?, ?, ?)",
    );
    for (const m of deck.cardMeanings) {
      const card = cardName(deck.deck, m.card);
      if (card && (m.upright || m.reversed || m.memory)) insert.run(id, card, m.upright, m.reversed, m.memory);
    }
    record(id, "deck", "Edited the deck", true);
  });
}

export function deletePsychic(id: string) {
  db.prepare("DELETE FROM psychics WHERE id = ?").run(id);
}

export function replaceExamples(id: string, examples: Example[]) {
  tx(() => {
    db.prepare("DELETE FROM examples WHERE psychic_id = ?").run(id);
    const insert = db.prepare("INSERT INTO examples (psychic_id, position, user, reply) VALUES (?, ?, ?, ?)");
    examples.forEach((e, i) => insert.run(id, i, e.user, e.reply));
    touch(id);
    record(id, "examples", "Edited the examples", true);
  });
}

export function getDocument(docId: number): (Doc & { psychicId: string }) | null {
  const row = db.prepare("SELECT * FROM documents WHERE id = ?").get(docId) as Row | undefined;
  return row ? { ...toDoc(row), psychicId: String(row.psychic_id) } : null;
}

export function createDocument(psychicId: string, title: string, body: string): number {
  return tx(() => {
    const result = db
      .prepare("INSERT INTO documents (psychic_id, title, body) VALUES (?, ?, ?)")
      .run(psychicId, title, body);
    touch(psychicId);
    record(psychicId, "doc-add", title ? `Added “${title}”` : "Added a document");
    return Number(result.lastInsertRowid);
  });
}

export function updateDocument(docId: number, title: string, body: string, enabled: boolean) {
  const before = getDocument(docId);
  if (!before) return;
  tx(() => {
    db.prepare("UPDATE documents SET title = ?, body = ?, enabled = ?, updated_at = datetime('now') WHERE id = ?")
      .run(title, body, enabled ? 1 : 0, docId);
    touch(before.psychicId);
    const name = title || "Untitled";
    if (before.enabled !== enabled) {
      record(before.psychicId, "doc-toggle", enabled ? `Switched “${name}” on` : `Switched “${name}” off`);
    } else {
      record(before.psychicId, `doc:${docId}`, `Edited “${name}”`, true);
    }
  });
}

export function deleteDocument(docId: number) {
  const doc = getDocument(docId);
  if (!doc) return;
  tx(() => {
    db.prepare("DELETE FROM documents WHERE id = ?").run(docId);
    touch(doc.psychicId);
    record(doc.psychicId, "doc-delete", `Deleted “${doc.title || "Untitled"}”`);
  });
}

const isComplete = (e: Example) => Boolean(e.user.trim() && e.reply.trim());

/** Required parts that are still empty. A psychic is only published once this is empty. */
export function missingParts(p: Psychic): string[] {
  const missing: string[] = [];
  for (const f of PERSONA_FIELDS) if (!p[f].trim()) missing.push(f);
  for (const f of LIST_FIELDS) if (!p[f].length) missing.push(f);
  if (!p.examples.some(isComplete)) missing.push("examples");
  return missing;
}

export function publish(p: Psychic): PublishedPersona {
  const persona = {} as Persona;
  for (const f of PERSONA_FIELDS) persona[f] = p[f];
  for (const f of LIST_FIELDS) persona[f] = p[f];
  return {
    ...persona,
    howIRead: p.howIRead,
    deck: p.deck,
    cardMeanings: p.cardMeanings,
    app: { ...p.app, show: p.inApp && !missingForApp(p).length },
    photoId: p.photoId,
    examples: p.examples.filter(isComplete),
    notes: p.documents.filter((d) => d.enabled && d.body.trim()).map((d) => ({ title: d.title || "Background", body: d.body })),
  };
}

/** Rough size of what this psychic adds to every reading's prompt. */
function promptChars(p: Psychic): number {
  const pub = publish(p);
  return JSON.stringify(pub).length;
}

/** Every complete psychic, in the format the reading server reads. */
export function publishedPersonas(): Record<string, PublishedPersona> {
  const out: Record<string, PublishedPersona> = {};
  const ids = (db.prepare("SELECT id FROM psychics ORDER BY id").all() as Row[]).map((r) => String(r.id));
  for (const id of ids) {
    const p = getPsychic(id)!;
    if (!missingParts(p).length) out[id] = publish(p);
  }
  return out;
}

export function importPsychic(
  id: string, persona: Persona, examples: Example[], docs: { title: string; body: string }[], deck: Deck,
) {
  tx(() => {
    quietly(() => {
      createPsychic(id, persona.name);
      updatePersona(id, persona);
      updateDeck(id, deck);
      replaceExamples(id, examples);
      for (const d of docs) createDocument(id, d.title, d.body);
    });
    record(id, "imported", "Imported from the markdown files");
  });
}

/**
 * Fills in "How I read" and the deck for a psychic that has neither yet, from the markdown files.
 * Used once, when a database from before decks existed is upgraded.
 */
export function fillReadingStyle(id: string, howIRead: string, deck: Deck): boolean {
  const p = getPsychic(id);
  if (!p || p.howIRead || p.cardMeanings.length || (!howIRead && !deck.cardMeanings.length && deck.deck === "tarot")) return false;
  tx(() => {
    quietly(() => {
      db.prepare("UPDATE psychics SET how_i_read = ? WHERE id = ?").run(howIRead, id);
      updateDeck(id, deck);
    });
    record(id, "imported", "Added how they read cards, from the markdown files");
  });
  return true;
}

// ---- Drafts from Claude ----

/** The newest version of a psychic: going back to it undoes whatever happens next. */
export function latestVersionId(psychicId: string): number | null {
  const row = db.prepare("SELECT id FROM revisions WHERE psychic_id = ? ORDER BY id DESC LIMIT 1").get(psychicId) as Row | undefined;
  return row ? Number(row.id) : null;
}

/**
 * Saves what Claude wrote as one new version: persona fields replace the current ones, examples are added
 * after the existing ones, card meanings replace those for the same cards, and a document is added.
 */
export function applyDraft(
  id: string,
  draft: {
    persona?: Partial<Persona>;
    examples?: Example[];
    cardMeanings?: CardMeaning[];
    document?: { title: string; body: string };
    app?: Partial<AppProfile>;
  },
  label: string,
) {
  tx(() => {
    quietly(() => {
      const p = getPsychic(id)!;
      if (draft.persona && Object.keys(draft.persona).length) {
        const next = { ...p } as Persona;
        for (const [k, v] of Object.entries(draft.persona)) {
          if (Array.isArray(v)) (next as Record<string, unknown>)[k] = v.map((x) => String(x).trim()).filter(Boolean);
          else if (typeof v === "string") (next as Record<string, unknown>)[k] = v.trim();
        }
        updatePersona(id, next);
      }
      if (draft.examples?.length) replaceExamples(id, [...p.examples, ...draft.examples].slice(0, 60));
      if (draft.cardMeanings?.length) {
        const byCard = new Map(p.cardMeanings.map((m) => [m.card, m]));
        for (const m of draft.cardMeanings) byCard.set(m.card, m);
        updateDeck(id, { deck: p.deck, cardMeanings: [...byCard.values()] });
      }
      if (draft.document?.body.trim()) createDocument(id, draft.document.title.trim(), draft.document.body.trim());
      if (draft.app && Object.keys(draft.app).length) {
        const now = getPsychic(id)!;
        const app = { ...now.app };
        for (const [k, v] of Object.entries(draft.app)) {
          if (Array.isArray(v)) (app as Record<string, unknown>)[k] = v.map((x) => String(x).trim()).filter(Boolean);
          else if (typeof v === "string") (app as Record<string, unknown>)[k] = v.trim();
        }
        updateApp(id, app, now.inApp);
      }
    });
    record(id, "claude", label);
  });
}

// ---- History ----
// Every change saves a snapshot of the whole psychic. Autosaves to the same part within
// GROUP_MINUTES of each other update one version instead of making a new one each time.
const GROUP_MINUTES = 10;
const KEEP_VERSIONS = 150;

interface Snapshot extends Persona {
  /** Missing in versions saved before the app profile existed. */
  app?: AppProfile;
  inApp?: boolean;
  /** Missing in versions saved before decks existed. */
  deck?: DeckId;
  cardMeanings?: CardMeaning[];
  photoId?: number | null;
  examples: Example[];
  documents: { id: number; title: string; body: string; enabled: boolean }[];
}

let quietDepth = 0;
function quietly(fn: () => void) {
  quietDepth++;
  try {
    fn();
  } finally {
    quietDepth--;
  }
}

function snapshotOf(id: string): Snapshot | null {
  const p = getPsychic(id);
  if (!p) return null;
  const persona = {} as Persona;
  for (const f of PERSONA_FIELDS) persona[f] = p[f];
  for (const f of LIST_FIELDS) persona[f] = p[f];
  return {
    ...persona,
    howIRead: p.howIRead,
    deck: p.deck,
    cardMeanings: p.cardMeanings,
    app: p.app,
    inApp: p.inApp,
    photoId: p.photoId,
    examples: p.examples,
    documents: p.documents.map((d) => ({ id: d.id, title: d.title, body: d.body, enabled: d.enabled })),
  };
}

function record(psychicId: string, kind: string, label: string, group = false) {
  if (quietDepth > 0) return;
  const snapshot = snapshotOf(psychicId);
  if (!snapshot) return;
  const json = JSON.stringify(snapshot);
  const last = db
    .prepare(`SELECT id, kind, snapshot, (julianday('now') - julianday(updated_at)) * 1440 AS age
              FROM revisions WHERE psychic_id = ? ORDER BY id DESC LIMIT 1`)
    .get(psychicId) as Row | undefined;
  if (last && String(last.snapshot) === json) return; // nothing actually changed
  if (group && last && last.kind === kind && Number(last.age) < GROUP_MINUTES) {
    db.prepare("UPDATE revisions SET snapshot = ?, updated_at = datetime('now') WHERE id = ?").run(json, Number(last.id));
    return;
  }
  db.prepare("INSERT INTO revisions (psychic_id, kind, label, snapshot) VALUES (?, ?, ?, ?)").run(psychicId, kind, label, json);
  db.prepare(`DELETE FROM revisions WHERE psychic_id = ? AND id NOT IN
              (SELECT id FROM revisions WHERE psychic_id = ? ORDER BY id DESC LIMIT ?)`).run(psychicId, psychicId, KEEP_VERSIONS);
  // Old photos stay while a kept version still uses them, so going back brings the photo back too.
  db.prepare(`DELETE FROM photos WHERE psychic_id = ?
              AND id IS NOT (SELECT photo_id FROM psychics WHERE id = ?)
              AND id NOT IN (SELECT json_extract(snapshot, '$.photoId') FROM revisions
                             WHERE psychic_id = ? AND json_extract(snapshot, '$.photoId') IS NOT NULL)`)
    .run(psychicId, psychicId, psychicId);
}

// ---- Photos ----
export function getPhoto(photoId: number): { mime: string; data: Uint8Array; psychicId: string } | null {
  const row = db.prepare("SELECT psychic_id, mime, data FROM photos WHERE id = ?").get(photoId) as Row | undefined;
  return row ? { mime: String(row.mime), data: row.data as Uint8Array, psychicId: String(row.psychic_id) } : null;
}

function setPhotoPointer(psychicId: string, photoId: number | null) {
  db.prepare("UPDATE psychics SET photo_id = ?, updated_at = datetime('now') WHERE id = ?").run(photoId, psychicId);
}

/** Replaces a psychic's photo. The previous one is kept while history still refers to it. */
export function setPhoto(psychicId: string, mime: string, data: Uint8Array) {
  tx(() => {
    const had = getPsychic(psychicId)?.photoId != null;
    const result = db.prepare("INSERT INTO photos (psychic_id, mime, data) VALUES (?, ?, ?)").run(psychicId, mime, data);
    setPhotoPointer(psychicId, Number(result.lastInsertRowid));
    record(psychicId, "photo", had ? "Changed the photo" : "Added a photo");
  });
}

/** Psychics with no photo now and none ever (removing a photo on purpose keeps it removed). */
export function psychicsNeverPhotographed(): string[] {
  return (db.prepare(`SELECT id FROM psychics WHERE photo_id IS NULL
    AND NOT EXISTS (SELECT 1 FROM photos WHERE photos.psychic_id = psychics.id)
    AND NOT EXISTS (SELECT 1 FROM revisions r WHERE r.psychic_id = psychics.id AND r.kind = 'photo')`).all() as Row[])
    .map((r) => String(r.id));
}

export function removePhoto(psychicId: string) {
  tx(() => {
    setPhotoPointer(psychicId, null);
    record(psychicId, "photo", "Removed the photo");
  });
}

/** Gives psychics that predate history a starting version, so their first edit can be undone. */
export function ensureHistory() {
  const ids = db
    .prepare("SELECT id FROM psychics WHERE id NOT IN (SELECT DISTINCT psychic_id FROM revisions)")
    .all() as Row[];
  for (const row of ids) record(String(row.id), "start", "Starting point");
}

const FIELD_LABELS: Record<string, string> = {
  name: "name", specialty: "specialty", backstory: "backstory", voice: "voice", texting: "texting style",
  catchphrases: "catchphrases", never: "never list", quirks: "quirks", others: "the other psychics", ritual: "ritual",
  howIRead: "how they read",
};

/** Plain-language list of what differs between two versions. */
function describeChanges(before: Snapshot | null, after: Snapshot): string[] {
  if (!before) return [];
  const changes: string[] = [];
  const fields = [...PERSONA_FIELDS, ...LIST_FIELDS, "howIRead" as const].filter(
    (f) => JSON.stringify(before[f] ?? "") !== JSON.stringify(after[f] ?? ""),
  );
  if (fields.length) changes.push(`Changed ${fields.map((f) => FIELD_LABELS[f]).join(", ")}`);
  if (after.app && JSON.stringify(before.app ?? emptyApp()) !== JSON.stringify(after.app)) changes.push("Changed the app profile");
  if ((before.inApp ?? false) !== (after.inApp ?? false)) changes.push(after.inApp ? "Shown in the app" : "Hidden from the app");
  if ((before.deck ?? "tarot") !== (after.deck ?? "tarot")) {
    changes.push(`Switched to ${after.deck === "playing" ? "playing cards" : "tarot"}`);
  }
  const meanings = (s: Snapshot) => new Map((s.cardMeanings ?? []).map((m) => [m.card, JSON.stringify(m)]));
  const mBefore = meanings(before), mAfter = meanings(after);
  const cardsChanged = [...new Set([...mBefore.keys(), ...mAfter.keys()])].filter((c) => mBefore.get(c) !== mAfter.get(c));
  if (cardsChanged.length) {
    changes.push(cardsChanged.length <= 3
      ? `Changed the meaning of ${cardsChanged.join(", ")}`
      : `Changed ${cardsChanged.length} card meanings`);
  }
  const exBefore = before.examples.length, exAfter = after.examples.length;
  if (JSON.stringify(before.examples) !== JSON.stringify(after.examples)) {
    changes.push(exAfter > exBefore ? `Added ${exAfter - exBefore} example${exAfter - exBefore === 1 ? "" : "s"}`
      : exAfter < exBefore ? `Removed ${exBefore - exAfter} example${exBefore - exAfter === 1 ? "" : "s"}`
      : "Changed examples");
  }
  if ((before.photoId ?? null) !== (after.photoId ?? null)) {
    changes.push(after.photoId == null ? "Removed the photo" : before.photoId == null ? "Added a photo" : "Changed the photo");
  }
  const docName = (d: { title: string }) => `“${d.title || "Untitled"}”`;
  const oldDocs = new Map(before.documents.map((d) => [d.id, d]));
  const newDocs = new Map(after.documents.map((d) => [d.id, d]));
  for (const d of after.documents) {
    const old = oldDocs.get(d.id);
    if (!old) changes.push(`Added ${docName(d)}`);
    else {
      if (old.title !== d.title || old.body !== d.body) changes.push(`Changed ${docName(d)}`);
      if (old.enabled !== d.enabled) changes.push(`Switched ${docName(d)} ${d.enabled ? "on" : "off"}`);
    }
  }
  for (const d of before.documents) if (!newDocs.has(d.id)) changes.push(`Removed ${docName(d)}`);
  return changes;
}

export function history(psychicId: string) {
  const rows = db
    .prepare("SELECT id, kind, label, snapshot, created_at, updated_at FROM revisions WHERE psychic_id = ? ORDER BY id")
    .all(psychicId) as Row[];
  let previous: Snapshot | null = null;
  const out = rows.map((row, i) => {
    const snap = JSON.parse(String(row.snapshot)) as Snapshot;
    const entry = {
      id: Number(row.id),
      label: String(row.label),
      startedAt: String(row.created_at),
      savedAt: String(row.updated_at),
      changes: describeChanges(previous, snap),
      current: i === rows.length - 1,
    };
    previous = snap;
    return entry;
  });
  return out.reverse();
}

/** Puts a psychic back the way it was in an earlier version. The restore is itself a new version. */
export function restore(revisionId: number): string | null {
  const row = db.prepare("SELECT psychic_id, snapshot FROM revisions WHERE id = ?").get(revisionId) as Row | undefined;
  if (!row) return null;
  const id = String(row.psychic_id);
  const snap = JSON.parse(String(row.snapshot)) as Snapshot;
  tx(() => {
    quietly(() => {
      // Versions from before decks existed don't have them: keep the current ones.
      const now = getPsychic(id)!;
      updatePersona(id, { ...snap, howIRead: snap.howIRead ?? now.howIRead });
      if (snap.deck !== undefined) updateDeck(id, { deck: snap.deck, cardMeanings: snap.cardMeanings ?? [] });
      if (snap.app !== undefined) updateApp(id, toApp(JSON.stringify(snap.app)), snap.inApp ?? false);
      if (snap.photoId !== undefined) setPhotoPointer(id, snap.photoId);
      replaceExamples(id, snap.examples);
      db.prepare("DELETE FROM documents WHERE psychic_id = ?").run(id);
      // Keep each document's id when it's free, so history can tell a restored document from a new one.
      const taken = db.prepare("SELECT 1 FROM documents WHERE id = ?");
      const insert = db.prepare("INSERT INTO documents (id, psychic_id, title, body, enabled) VALUES (?, ?, ?, ?, ?)");
      for (const d of snap.documents) {
        insert.run(taken.get(d.id) ? null : d.id, id, d.title, d.body, d.enabled ? 1 : 0);
      }
    });
    record(id, "restore", "Went back to an earlier version");
  });
  return id;
}
