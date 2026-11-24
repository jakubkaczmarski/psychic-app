// Psychic Studio: a separate service for writing each psychic's persona and documents.
// The web interface is for editors; the reading server fetches finished personas from /v1/personas.

import fs from "node:fs";
import http from "node:http";
import path from "node:path";
import { checkConfig, hasReadToken, isSignedIn, signIn, signOut, tooManyAttempts } from "./auth.ts";
import { DECKS, isDeck } from "./cards.ts";
import { type DraftRequest, DraftError, claudeAvailable, draft } from "./claude.ts";
import * as db from "./db.ts";
import { fillReadingStylesFrom, seedFrom } from "./seed.ts";

const PORT = Number(process.env.PORT ?? 8790);
const PUBLIC_DIR = path.join(import.meta.dirname, "..", "public");

const problems = checkConfig();
if (problems.length) {
  for (const p of problems) console.error(p);
  console.error("Copy studio/.env.example to studio/.env and fill it in.");
  process.exit(1);
}

const seedDir = path.resolve(process.env.STUDIO_SEED_DIR ?? path.join(import.meta.dirname, "..", "..", "server", "psychics"));
if (db.isEmpty()) {
  const n = seedFrom(seedDir);
  if (n) console.log(`Imported ${n} psychics from ${seedDir}.`);
} else if (db.addedDecks) {
  // First start since decks were added: bring in each psychic's "How I read" and deck from the files.
  const filled = fillReadingStylesFrom(seedDir);
  if (filled.length) console.log(`Added how ${filled.join(", ")} read cards, from ${seedDir}.`);
}
db.ensureHistory();
importAppPhotos();

/** Gives psychics that never had a photo the one bundled with the iOS app (AsFate/Resources/psychic_<id>.png). */
function importAppPhotos() {
  const dir = path.resolve(process.env.STUDIO_PHOTO_DIR ?? path.join(import.meta.dirname, "..", "..", "AsFate", "Resources"));
  for (const id of db.psychicsNeverPhotographed()) {
    const file = path.join(dir, `psychic_${id}.png`);
    if (fs.existsSync(file)) {
      db.setPhoto(id, "image/png", fs.readFileSync(file));
      console.log(`Added the app's photo for ${id}.`);
    }
  }
}

const MAX_PHOTO_BYTES = 3_000_000;

/** Works out the image type from its first bytes, so only real images are stored. */
function imageType(bytes: Uint8Array): string | null {
  const starts = (...sig: number[]) => sig.every((b, i) => bytes[i] === b);
  if (starts(0x89, 0x50, 0x4e, 0x47)) return "image/png";
  if (starts(0xff, 0xd8, 0xff)) return "image/jpeg";
  if (starts(0x52, 0x49, 0x46, 0x46) && bytes[8] === 0x57 && bytes[9] === 0x45 && bytes[10] === 0x42 && bytes[11] === 0x50) return "image/webp";
  return null;
}

function sendPhoto(res: http.ServerResponse, photoId: number) {
  const photo = db.getPhoto(photoId);
  if (!photo) return fail(res, 404, "No such photo.");
  res.writeHead(200, {
    "content-type": photo.mime,
    "content-length": photo.data.byteLength,
    // A photo id never changes its image, so browsers can keep it.
    "cache-control": "private, max-age=31536000, immutable",
    "x-content-type-options": "nosniff",
  });
  res.end(photo.data);
}

// ---- Limits ----
const MAX_FIELD = 10_000;
const MAX_LIST_ITEMS = 30;
const MAX_LIST_ITEM = 300;
const MAX_EXAMPLES = 60;
const MAX_DOC = 100_000;
const MAX_TITLE = 120;
const MAX_MEANING = 1000;
const ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,31}$/;

class BadRequest extends Error {}

function text(value: unknown, field: string, max = MAX_FIELD): string {
  if (typeof value !== "string") throw new BadRequest(`${field} must be text.`);
  const v = value.replace(/\r\n/g, "\n").trim();
  if (v.length > max) throw new BadRequest(`${field} is limited to ${max.toLocaleString("en")} characters.`);
  return v;
}

function list(value: unknown, field: string): string[] {
  if (!Array.isArray(value)) throw new BadRequest(`${field} must be a list.`);
  const items = value.map((v) => text(v, field, MAX_LIST_ITEM)).filter(Boolean);
  if (items.length > MAX_LIST_ITEMS) throw new BadRequest(`${field} is limited to ${MAX_LIST_ITEMS} items.`);
  return items;
}

function parsePersona(body: Record<string, unknown>): db.Persona {
  const p = {} as db.Persona;
  for (const f of db.PERSONA_FIELDS) p[f] = text(body[f] ?? "", f);
  for (const f of db.LIST_FIELDS) p[f] = list(body[f] ?? [], f);
  p.howIRead = text(body.howIRead ?? "", "How they read");
  if (!p.name) throw new BadRequest("A psychic needs a name.");
  return p;
}

function parseApp(value: unknown): db.AppProfile {
  const o = (value && typeof value === "object" ? value : {}) as Record<string, unknown>;
  const app = db.emptyApp();
  for (const f of db.APP_TEXT_FIELDS) app[f] = text(o[f] ?? "", f, 2000);
  for (const f of db.APP_LIST_FIELDS) app[f] = list(o[f] ?? [], f);
  if (app.color && !/^#[0-9a-fA-F]{6}$/.test(app.color)) throw new BadRequest("The colour must look like #6A58B4.");
  if (app.typing && !["slow", "medium", "fast"].includes(app.typing)) throw new BadRequest("Typing speed is slow, medium or fast.");
  return app;
}

function parseDraftRequest(body: Record<string, unknown>): DraftRequest {
  const r: DraftRequest = {};
  if (body.app === "empty" || body.app === "all") r.app = body.app;
  if (body.persona === "empty" || body.persona === "all") r.persona = body.persona;
  if (typeof body.examples === "number" && body.examples > 0) r.examples = Math.min(Math.floor(body.examples), 12);
  if (body.cards && typeof body.cards === "object") {
    const c = body.cards as Record<string, unknown>;
    r.cards = {
      names: Array.isArray(c.names) ? c.names.filter((n): n is string => typeof n === "string").slice(0, 20) : undefined,
      count: typeof c.count === "number" ? Math.min(Math.max(Math.floor(c.count), 1), 20) : undefined,
    };
  }
  if (typeof body.document === "string" && body.document.trim()) r.document = text(body.document, "Document topic", 300);
  if (typeof body.notes === "string") r.notes = text(body.notes, "Notes", 2000);
  if (!r.persona && !r.app && !r.examples && !r.cards && !r.document) throw new BadRequest("Pick at least one thing for Claude to write.");
  return r;
}

function parseDeck(body: Record<string, unknown>): db.Deck {
  if (!isDeck(body.deck)) throw new BadRequest('deck must be "tarot" or "playing".');
  if (!Array.isArray(body.cardMeanings)) throw new BadRequest("cardMeanings must be a list.");
  if (body.cardMeanings.length > 78) throw new BadRequest("There are at most 78 cards.");
  const cardMeanings = body.cardMeanings.map((m) => {
    const o = (m ?? {}) as Record<string, unknown>;
    return {
      card: text(o.card ?? "", "Card", 60),
      upright: text(o.upright ?? "", "Upright meaning", MAX_MEANING),
      reversed: text(o.reversed ?? "", "Reversed meaning", MAX_MEANING),
      memory: text(o.memory ?? "", "Memory", MAX_MEANING),
    };
  });
  return { deck: body.deck, cardMeanings };
}

function parseExamples(value: unknown): db.Example[] {
  if (!Array.isArray(value)) throw new BadRequest("examples must be a list.");
  if (value.length > MAX_EXAMPLES) throw new BadRequest(`Examples are limited to ${MAX_EXAMPLES}.`);
  return value
    .map((e) => {
      const o = (e ?? {}) as Record<string, unknown>;
      return { user: text(o.user ?? "", "Example message", 2000).replace(/\n+/g, " "), reply: text(o.reply ?? "", "Example reply", 4000) };
    })
    // Half-written examples are kept so autosave doesn't lose them; only complete ones are published.
    .filter((e) => e.user || e.reply);
}

// ---- HTTP helpers ----
async function readJSON(req: http.IncomingMessage): Promise<Record<string, unknown>> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > 6_000_000) throw new BadRequest("Request is too large.");
    chunks.push(chunk as Buffer);
  }
  if (!chunks.length) return {};
  try {
    const parsed = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
    return parsed;
  } catch {
    throw new BadRequest("Body must be a JSON object.");
  }
}

function send(res: http.ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}

const fail = (res: http.ServerResponse, status: number, message: string) => send(res, status, { message });

function clientIP(req: http.IncomingMessage): string {
  const forwarded = String(req.headers["x-forwarded-for"] ?? "").split(",")[0].trim();
  return forwarded || req.socket.remoteAddress || "unknown";
}

const STATIC: Record<string, string> = {
  "/": "index.html",
  "/app.js": "app.js",
  "/styles.css": "styles.css",
};
const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
};

function serveStatic(res: http.ServerResponse, file: string) {
  res.writeHead(200, {
    "content-type": TYPES[path.extname(file)],
    "cache-control": "no-cache",
    "content-security-policy": "default-src 'self'; frame-ancestors 'none'",
    "x-content-type-options": "nosniff",
  });
  res.end(fs.readFileSync(path.join(PUBLIC_DIR, file)));
}

// ---- Routes ----
async function api(req: http.IncomingMessage, res: http.ServerResponse, url: URL) {
  const method = req.method ?? "GET";
  const parts = url.pathname.split("/").filter(Boolean).slice(1); // drop "api"

  if (method !== "GET" && !String(req.headers["content-type"] ?? "").startsWith("application/json")) {
    return fail(res, 415, "Send JSON.");
  }

  if (parts[0] === "login" && method === "POST") {
    const ip = clientIP(req);
    if (tooManyAttempts(ip)) return fail(res, 429, "Too many attempts. Try again in 15 minutes.");
    const { password } = await readJSON(req);
    if (typeof password !== "string" || !signIn(ip, password, res)) return fail(res, 401, "Wrong password.");
    return send(res, 200, { ok: true });
  }
  if (parts[0] === "logout" && method === "POST") {
    signOut(res);
    return send(res, 200, { ok: true });
  }
  if (!isSignedIn(req)) return fail(res, 401, "Sign in first.");
  if (parts[0] === "me") return send(res, 200, { ok: true, claude: claudeAvailable() });
  if (parts[0] === "decks" && method === "GET") return send(res, 200, { decks: DECKS });

  // /api/psychics
  if (parts[0] === "psychics" && parts.length === 1) {
    if (method === "GET") return send(res, 200, { psychics: db.listPsychics() });
    if (method === "POST") {
      const body = await readJSON(req);
      const id = text(body.id ?? "", "id", 32).toLowerCase();
      const name = text(body.name ?? "", "Name", 200);
      if (!ID_PATTERN.test(id)) throw new BadRequest("The id must be lowercase letters, numbers and dashes, like \"luna\".");
      if (!name) throw new BadRequest("A psychic needs a name.");
      if (db.getPsychic(id)) throw new BadRequest(`There is already a psychic with the id "${id}".`);
      db.createPsychic(id, name);
      return send(res, 201, { psychic: db.getPsychic(id) });
    }
  }

  // /api/psychics/:id[/examples|/documents]
  if (parts[0] === "psychics" && parts[1]) {
    const id = parts[1];
    const psychic = db.getPsychic(id);
    if (!psychic) return fail(res, 404, "No such psychic.");
    const withStatus = (p: db.Psychic) => ({
      ...p, missing: db.missingParts(p), appMissing: db.missingForApp(p), builtIn: db.BUILT_IN.has(p.id), published: db.publish(p),
    });

    if (parts.length === 2) {
      if (method === "GET") return send(res, 200, { psychic: withStatus(psychic) });
      if (method === "PUT") {
        db.updatePersona(id, parsePersona(await readJSON(req)));
        return send(res, 200, { psychic: withStatus(db.getPsychic(id)!) });
      }
      if (method === "DELETE") {
        db.deletePsychic(id);
        return send(res, 200, { ok: true });
      }
    }
    if (parts[2] === "claude" && method === "POST") {
      const request = parseDraftRequest(await readJSON(req));
      const cast = db.listPsychics().map((c) => ({ id: c.id, name: c.name, specialty: c.specialty }));
      const result = await draft(psychic, cast, request);
      const undoVersionId = db.latestVersionId(id);
      const wrote = [
        result.persona && Object.keys(result.persona).length && "the persona",
        result.app && Object.keys(result.app).length && "the app profile",
        result.examples?.length && `${result.examples.length} example${result.examples.length === 1 ? "" : "s"}`,
        result.cardMeanings?.length && `${result.cardMeanings.length} card meaning${result.cardMeanings.length === 1 ? "" : "s"}`,
        result.document && `“${result.document.title || "a document"}”`,
      ].filter(Boolean) as string[];
      if (!wrote.length) throw new BadRequest("There was nothing to write: every field you asked for is already filled in.");
      const summary = wrote.length === 1 ? wrote[0] : `${wrote.slice(0, -1).join(", ")} and ${wrote.at(-1)}`;
      db.applyDraft(id, result, `Claude wrote ${summary}`);
      return send(res, 200, { psychic: withStatus(db.getPsychic(id)!), summary, undoVersionId });
    }
    if (parts[2] === "app" && method === "PUT") {
      const body = await readJSON(req);
      db.updateApp(id, parseApp(body.app), typeof body.inApp === "boolean" ? body.inApp : psychic.inApp);
      return send(res, 200, { psychic: withStatus(db.getPsychic(id)!) });
    }
    if (parts[2] === "deck" && method === "PUT") {
      db.updateDeck(id, parseDeck(await readJSON(req)));
      return send(res, 200, { psychic: withStatus(db.getPsychic(id)!) });
    }
    if (parts[2] === "examples" && method === "PUT") {
      db.replaceExamples(id, parseExamples((await readJSON(req)).examples));
      return send(res, 200, { psychic: withStatus(db.getPsychic(id)!) });
    }
    if (parts[2] === "photo" && method === "PUT") {
      const { data } = await readJSON(req);
      if (typeof data !== "string" || !data) throw new BadRequest("Send the photo as base64 in \"data\".");
      const bytes = Buffer.from(data, "base64");
      if (bytes.byteLength > MAX_PHOTO_BYTES) throw new BadRequest("Photos are limited to 3 MB.");
      const mime = imageType(bytes);
      if (!mime) throw new BadRequest("That file isn't a PNG, JPEG or WebP image.");
      db.setPhoto(id, mime, bytes);
      return send(res, 200, { psychic: withStatus(db.getPsychic(id)!) });
    }
    if (parts[2] === "photo" && method === "DELETE") {
      db.removePhoto(id);
      return send(res, 200, { psychic: withStatus(db.getPsychic(id)!) });
    }
    if (parts[2] === "history" && method === "GET") {
      return send(res, 200, { history: db.history(id) });
    }
    if (parts[2] === "documents" && method === "POST") {
      const body = await readJSON(req);
      const title = text(body.title ?? "", "Title", MAX_TITLE);
      const docId = db.createDocument(id, title, text(body.body ?? "", "Document", MAX_DOC));
      return send(res, 201, { document: db.getDocument(docId) });
    }
  }

  // /api/photos/:photoId
  if (parts[0] === "photos" && parts[1] && method === "GET") return sendPhoto(res, Number(parts[1]));

  // /api/versions/:id/restore
  if (parts[0] === "versions" && parts[2] === "restore" && method === "POST") {
    const id = db.restore(Number(parts[1]));
    if (!id) return fail(res, 404, "No such version.");
    const psychic = db.getPsychic(id)!;
    return send(res, 200, { psychic: { ...psychic, missing: db.missingParts(psychic), published: db.publish(psychic) } });
  }

  // /api/documents/:docId
  if (parts[0] === "documents" && parts[1]) {
    const doc = db.getDocument(Number(parts[1]));
    if (!doc) return fail(res, 404, "No such document.");
    if (method === "PUT") {
      const body = await readJSON(req);
      db.updateDocument(
        doc.id,
        text(body.title ?? doc.title, "Title", MAX_TITLE),
        text(body.body ?? doc.body, "Document", MAX_DOC),
        typeof body.enabled === "boolean" ? body.enabled : doc.enabled,
      );
      return send(res, 200, { document: db.getDocument(doc.id) });
    }
    if (method === "DELETE") {
      db.deleteDocument(doc.id);
      return send(res, 200, { ok: true });
    }
  }

  fail(res, 404, "Not found.");
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  try {
    if (req.method === "GET" && url.pathname === "/health") return send(res, 200, { ok: true });

    // For the reading server (and, later, the app through it).
    const photoMatch = url.pathname.match(/^\/v1\/photos\/(\d+)$/);
    if (req.method === "GET" && photoMatch) {
      if (!hasReadToken(req)) return fail(res, 401, "Missing or wrong token.");
      return sendPhoto(res, Number(photoMatch[1]));
    }
    if (req.method === "GET" && url.pathname === "/v1/personas") {
      if (!hasReadToken(req)) return fail(res, 401, "Missing or wrong token.");
      return send(res, 200, { psychics: db.publishedPersonas() });
    }

    if (url.pathname.startsWith("/api/")) return await api(req, res, url);

    if (req.method === "GET" && STATIC[url.pathname]) return serveStatic(res, STATIC[url.pathname]);
    fail(res, 404, "Not found.");
  } catch (err) {
    if (err instanceof BadRequest) return fail(res, 400, err.message);
    if (err instanceof DraftError) return fail(res, 502, err.message);
    console.error("Unhandled error:", err);
    if (!res.headersSent) fail(res, 500, "Something went wrong.");
    else res.end();
  }
});

server.listen(PORT, () => console.log(`Psychic Studio on http://localhost:${PORT}`));
