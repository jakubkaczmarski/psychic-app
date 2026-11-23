// SQLite storage for psychics, their example replies and their documents.

import fs from "node:fs";
import path from "node:path";
import { DatabaseSync } from "node:sqlite";

export const PERSONA_FIELDS = [
  "name", "specialty", "backstory", "voice", "texting", "quirks", "others", "ritual",
] as const;
export const LIST_FIELDS = ["catchphrases", "never"] as const;

type TextField = (typeof PERSONA_FIELDS)[number];
type ListField = (typeof LIST_FIELDS)[number];

export type Persona = Record<TextField, string> & Record<ListField, string[]>;

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

export interface Psychic extends Persona {
  id: string;
  updatedAt: string;
  examples: Example[];
  documents: Doc[];
}

/** The shape the reading server expects (matches PsychicPersona in server/src/psychics.ts). */
export interface PublishedPersona extends Persona {
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
      updatedAt: String(row.updated_at),
      exampleCount: Number(row.example_count),
      documentCount: Number(row.document_count),
      missing: missingParts(psychic),
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
  return { id, updatedAt: String(row.updated_at), ...toPersona(row), examples, documents };
}

export function createPsychic(id: string, name: string) {
  db.prepare("INSERT INTO psychics (id, name) VALUES (?, ?)").run(id, name);
}

export function updatePersona(id: string, persona: Persona) {
  db.prepare(`
    UPDATE psychics SET name = ?, specialty = ?, backstory = ?, voice = ?, texting = ?,
      catchphrases = ?, never = ?, quirks = ?, others = ?, ritual = ?, updated_at = datetime('now')
    WHERE id = ?`).run(
    persona.name, persona.specialty, persona.backstory, persona.voice, persona.texting,
    JSON.stringify(persona.catchphrases), JSON.stringify(persona.never),
    persona.quirks, persona.others, persona.ritual, id,
  );
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
    return Number(result.lastInsertRowid);
  });
}

export function updateDocument(docId: number, title: string, body: string, enabled: boolean) {
  tx(() => {
    db.prepare("UPDATE documents SET title = ?, body = ?, enabled = ?, updated_at = datetime('now') WHERE id = ?")
      .run(title, body, enabled ? 1 : 0, docId);
    touch(getDocument(docId)!.psychicId);
  });
}

export function deleteDocument(docId: number) {
  const doc = getDocument(docId);
  if (!doc) return;
  tx(() => {
    db.prepare("DELETE FROM documents WHERE id = ?").run(docId);
    touch(doc.psychicId);
  });
}

/** Required parts that are still empty. A psychic is only published once this is empty. */
export function missingParts(p: Psychic): string[] {
  const missing: string[] = [];
  for (const f of PERSONA_FIELDS) if (!p[f].trim()) missing.push(f);
  for (const f of LIST_FIELDS) if (!p[f].length) missing.push(f);
  if (!p.examples.length) missing.push("examples");
  return missing;
}

export function publish(p: Psychic): PublishedPersona {
  const persona = {} as Persona;
  for (const f of PERSONA_FIELDS) persona[f] = p[f];
  for (const f of LIST_FIELDS) persona[f] = p[f];
  return {
    ...persona,
    examples: p.examples,
    notes: p.documents.filter((d) => d.enabled && d.body.trim()).map((d) => ({ title: d.title, body: d.body })),
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

export function importPsychic(id: string, persona: Persona, examples: Example[], docs: { title: string; body: string }[]) {
  tx(() => {
    createPsychic(id, persona.name);
    updatePersona(id, persona);
    replaceExamples(id, examples);
    for (const d of docs) createDocument(id, d.title, d.body);
  });
}
