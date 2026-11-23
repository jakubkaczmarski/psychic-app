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
  /** Changes whenever the photo does; null when there's no photo. */
  photoId: number | null;
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

// Older databases: add the photo pointer to psychics.
if (!(db.prepare("PRAGMA table_info(psychics)").all() as { name: string }[]).some((c) => c.name === "photo_id")) {
  db.exec("ALTER TABLE psychics ADD COLUMN photo_id INTEGER");
}

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
      photoId: psychic.photoId,
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
  const photoId = row.photo_id === null || row.photo_id === undefined ? null : Number(row.photo_id);
  return { id, updatedAt: String(row.updated_at), photoId, ...toPersona(row), examples, documents };
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
      catchphrases = ?, never = ?, quirks = ?, others = ?, ritual = ?, updated_at = datetime('now')
    WHERE id = ?`).run(
    persona.name, persona.specialty, persona.backstory, persona.voice, persona.texting,
    JSON.stringify(persona.catchphrases), JSON.stringify(persona.never),
    persona.quirks, persona.others, persona.ritual, id,
  );
  record(id, "persona", "Edited the persona", true);
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

export function importPsychic(id: string, persona: Persona, examples: Example[], docs: { title: string; body: string }[]) {
  tx(() => {
    quietly(() => {
      createPsychic(id, persona.name);
      updatePersona(id, persona);
      replaceExamples(id, examples);
      for (const d of docs) createDocument(id, d.title, d.body);
    });
    record(id, "imported", "Imported from the markdown files");
  });
}

// ---- History ----
// Every change saves a snapshot of the whole psychic. Autosaves to the same part within
// GROUP_MINUTES of each other update one version instead of making a new one each time.
const GROUP_MINUTES = 10;
const KEEP_VERSIONS = 150;

interface Snapshot extends Persona {
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
};

/** Plain-language list of what differs between two versions. */
function describeChanges(before: Snapshot | null, after: Snapshot): string[] {
  if (!before) return [];
  const changes: string[] = [];
  const fields = [...PERSONA_FIELDS, ...LIST_FIELDS].filter(
    (f) => JSON.stringify(before[f]) !== JSON.stringify(after[f]),
  );
  if (fields.length) changes.push(`Changed ${fields.map((f) => FIELD_LABELS[f]).join(", ")}`);
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
      updatePersona(id, snap);
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
