import http from "node:http";
import Anthropic from "@anthropic-ai/sdk";
import { PSYCHICS, STAR_SIGNS, systemPrompt } from "./psychics.ts";

// ---- Config (environment variables) ----
const PORT = Number(process.env.PORT ?? 8787);
const MODEL = process.env.MOONLIT_MODEL ?? "claude-opus-5-5";
// Readings each device may request per rolling 24 hours.
const DEVICE_DAILY_LIMIT = Number(process.env.DEVICE_DAILY_LIMIT ?? 40);
// Readings each IP address may request per rolling 24 hours.
const IP_DAILY_LIMIT = Number(process.env.IP_DAILY_LIMIT ?? 200);
// Optional shared token the app sends in `x-moonlit-key`. It deters casual misuse
// but is not real authentication: anyone can extract it from the app.
const APP_KEY = process.env.MOONLIT_APP_KEY ?? "";

const MAX_TURNS = 40;
const MAX_CHARS = 2000;
const DAY_MS = 24 * 60 * 60 * 1000;

if (!process.env.ANTHROPIC_API_KEY) {
  console.warn("ANTHROPIC_API_KEY is not set: readings will fail until it is.");
}
const client = new Anthropic();

// ---- In-memory rate limiting (resets on restart; fine for a single instance) ----
const hits = new Map<string, number[]>();

function allow(key: string, limit: number): boolean {
  const now = Date.now();
  const recent = (hits.get(key) ?? []).filter((t) => now - t < DAY_MS);
  if (recent.length >= limit) {
    hits.set(key, recent);
    return false;
  }
  recent.push(now);
  hits.set(key, recent);
  return true;
}

setInterval(() => {
  const now = Date.now();
  for (const [key, times] of hits) {
    const recent = times.filter((t) => now - t < DAY_MS);
    if (recent.length) hits.set(key, recent);
    else hits.delete(key);
  }
}, 60 * 60 * 1000).unref();

// ---- Request validation ----
interface Turn {
  role: "user" | "assistant";
  content: string;
}

interface ReadingRequest {
  psychicId: string;
  userName: string;
  sign: string | null;
  messages: Turn[];
  /** Short notes about earlier readings with this psychic, written by the app. */
  memory: string[];
  /** Today's mood for this psychic, chosen by the app. */
  mood: string | null;
}

const MAX_MEMORY = 10;
const MAX_MEMORY_CHARS = 200;

function parseReading(body: unknown): ReadingRequest | string {
  if (!body || typeof body !== "object") return "Body must be a JSON object.";
  const b = body as Record<string, unknown>;

  if (typeof b.psychicId !== "string" || !(b.psychicId in PSYCHICS)) return "Unknown psychic.";

  const userName = typeof b.userName === "string" ? b.userName.trim().slice(0, 40) : "";
  const sign = typeof b.sign === "string" && STAR_SIGNS.has(b.sign) ? b.sign : null;

  if (!Array.isArray(b.messages) || b.messages.length === 0) return "messages must be a non-empty array.";
  const messages: Turn[] = [];
  for (const m of b.messages.slice(-MAX_TURNS)) {
    if (!m || typeof m !== "object") return "Each message must be an object.";
    const { role, content } = m as Record<string, unknown>;
    if (role !== "user" && role !== "assistant") return "Message role must be user or assistant.";
    if (typeof content !== "string" || !content.trim()) return "Message content must be text.";
    if (content.length > MAX_CHARS) return `Messages are limited to ${MAX_CHARS} characters.`;
    // Merge consecutive turns from the same side.
    const last = messages.at(-1);
    if (last && last.role === role) last.content += "\n\n" + content;
    else messages.push({ role, content });
  }
  if (messages[0].role !== "user") messages.unshift({ role: "user", content: "(The user opens a reading with you.)" });
  if (messages.at(-1)!.role !== "user") return "The last message must come from the user.";

  const memory = Array.isArray(b.memory)
    ? b.memory
        .filter((m): m is string => typeof m === "string" && m.trim().length > 0)
        .slice(-MAX_MEMORY)
        .map((m) => m.replace(/\s+/g, " ").trim().slice(0, MAX_MEMORY_CHARS))
    : [];

  const mood = typeof b.mood === "string" && b.mood.trim() ? b.mood.replace(/\s+/g, " ").trim().slice(0, 80) : null;

  return { psychicId: b.psychicId, userName, sign, messages, memory, mood };
}

async function readJSON(req: http.IncomingMessage): Promise<unknown> {
  let size = 0;
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > 200_000) throw new Error("too_large");
    chunks.push(chunk as Buffer);
  }
  return JSON.parse(Buffer.concat(chunks).toString("utf8"));
}

function sendJSON(res: http.ServerResponse, status: number, body: object) {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

function clientIP(req: http.IncomingMessage): string {
  const forwarded = req.headers["x-forwarded-for"];
  const first = (Array.isArray(forwarded) ? forwarded[0] : forwarded)?.split(",")[0]?.trim();
  return first || req.socket.remoteAddress || "unknown";
}

// ---- The reading endpoint: streams newline-delimited JSON events ----
//   {"type":"text","text":"..."}  a piece of the reply
//   {"type":"done"}               the reply finished
//   {"type":"error","code":"...","message":"..."}
async function handleReading(req: http.IncomingMessage, res: http.ServerResponse) {
  if (APP_KEY && req.headers["x-moonlit-key"] !== APP_KEY) {
    return sendJSON(res, 401, { code: "unauthorized", message: "Missing or wrong app key." });
  }

  const deviceID = String(req.headers["x-device-id"] ?? "").slice(0, 64);
  if (!deviceID) return sendJSON(res, 400, { code: "bad_request", message: "Missing x-device-id header." });

  let parsed: ReadingRequest | string;
  try {
    parsed = parseReading(await readJSON(req));
  } catch {
    return sendJSON(res, 400, { code: "bad_request", message: "Body must be valid JSON under 200 KB." });
  }
  if (typeof parsed === "string") return sendJSON(res, 400, { code: "bad_request", message: parsed });

  if (!allow(`ip:${clientIP(req)}`, IP_DAILY_LIMIT) || !allow(`device:${deviceID}`, DEVICE_DAILY_LIMIT)) {
    return sendJSON(res, 429, {
      code: "daily_limit",
      message: "The spirits need rest. You've used today's readings; come back tomorrow.",
    });
  }

  if (!process.env.ANTHROPIC_API_KEY) {
    console.error("Reading refused: ANTHROPIC_API_KEY is not set on the server.");
    return sendJSON(res, 503, { code: "server_config", message: "Readings are unavailable right now." });
  }

  const persona = PSYCHICS[parsed.psychicId];
  res.writeHead(200, {
    "content-type": "application/x-ndjson; charset=utf-8",
    "cache-control": "no-cache",
    "x-accel-buffering": "no",
  });
  const emit = (event: object) => res.write(JSON.stringify(event) + "\n");

  const stream = client.beta.messages.stream({
    model: MODEL,
    max_tokens: 2000,
    system: systemPrompt(persona, parsed.userName, parsed.sign, parsed.memory, parsed.mood),
    messages: parsed.messages,
    output_config: { effort: "low" },
    // If Claude declines, the API re-runs the request on a fallback model automatically.
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
  });

  // Stop paying for tokens if the user leaves mid-reading.
  res.on("close", () => {
    if (!res.writableFinished) stream.abort();
  });

  stream.on("text", (delta) => emit({ type: "text", text: delta }));

  try {
    const final = await stream.finalMessage();
    if (final.stop_reason === "refusal") {
      emit({ type: "error", code: "refused", message: "This question can't be answered here. Try asking something else." });
    } else {
      emit({ type: "done" });
    }
  } catch (err) {
    if (res.destroyed) return;
    let code = "upstream_error";
    let message = "The reading was interrupted. Please try again.";
    if (err instanceof Anthropic.RateLimitError) {
      code = "busy";
      message = "Too many readings right now. Try again in a minute.";
    } else if (err instanceof Anthropic.AuthenticationError || err instanceof Anthropic.PermissionDeniedError) {
      console.error("Anthropic rejected the server's API key:", err.message);
      code = "server_config";
      message = "Readings are unavailable right now.";
    } else if (err instanceof Anthropic.APIError && err.status === 529) {
      code = "busy";
      message = "The spirits are busy right now. Try again in a minute.";
    } else if (err instanceof Anthropic.APIError) {
      console.error(`Anthropic API error ${err.status}:`, err.message);
    } else {
      console.error("Reading failed:", err);
    }
    emit({ type: "error", code, message });
  }
  res.end();
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url ?? "/", "http://localhost");
  try {
    if (req.method === "GET" && url.pathname === "/health") {
      return sendJSON(res, 200, { ok: true, model: MODEL });
    }
    if (req.method === "POST" && url.pathname === "/v1/reading") {
      return await handleReading(req, res);
    }
    sendJSON(res, 404, { code: "not_found", message: "Not found." });
  } catch (err) {
    console.error("Unhandled error:", err);
    if (!res.headersSent) sendJSON(res, 500, { code: "server_error", message: "Something went wrong." });
    else res.end();
  }
});

server.listen(PORT, () => console.log(`Moonlit server listening on :${PORT} (model ${MODEL})`));
