// Password sign-in for the web interface (signed cookie) and a bearer token for the reading server.

import crypto from "node:crypto";
import type http from "node:http";

const PASSWORD = process.env.STUDIO_PASSWORD ?? "";
const READ_TOKEN = process.env.STUDIO_READ_TOKEN ?? "";
const SECRET = process.env.STUDIO_SESSION_SECRET || crypto.randomBytes(32).toString("hex");
const COOKIE_SECURE = process.env.COOKIE_SECURE === "1";
const COOKIE = "studio_session";
const SESSION_MS = 7 * 24 * 60 * 60 * 1000;

export function checkConfig(): string[] {
  const problems: string[] = [];
  if (PASSWORD.length < 8) problems.push("STUDIO_PASSWORD must be set (at least 8 characters).");
  if (READ_TOKEN.length < 16) problems.push("STUDIO_READ_TOKEN must be set (at least 16 characters).");
  if (!process.env.STUDIO_SESSION_SECRET) {
    console.warn("STUDIO_SESSION_SECRET is not set: everyone is signed out when the studio restarts.");
  }
  return problems;
}

function safeEqual(a: string, b: string): boolean {
  const ha = crypto.createHash("sha256").update(a).digest();
  const hb = crypto.createHash("sha256").update(b).digest();
  return crypto.timingSafeEqual(ha, hb);
}

const sign = (value: string) => crypto.createHmac("sha256", SECRET).update(value).digest("base64url");

function cookies(req: http.IncomingMessage): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (req.headers.cookie ?? "").split(";")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

export function isSignedIn(req: http.IncomingMessage): boolean {
  const [expires, signature] = (cookies(req)[COOKIE] ?? "").split(".");
  if (!expires || !signature || !safeEqual(signature, sign(expires))) return false;
  return Number(expires) > Date.now();
}

// Slows down password guessing: 10 failed attempts per IP per 15 minutes.
const failures = new Map<string, number[]>();
const WINDOW_MS = 15 * 60 * 1000;

export function tooManyAttempts(ip: string): boolean {
  const recent = (failures.get(ip) ?? []).filter((t) => Date.now() - t < WINDOW_MS);
  failures.set(ip, recent);
  return recent.length >= 10;
}

export function signIn(ip: string, password: string, res: http.ServerResponse): boolean {
  if (!safeEqual(password, PASSWORD)) {
    failures.set(ip, [...(failures.get(ip) ?? []), Date.now()]);
    return false;
  }
  failures.delete(ip);
  const expires = String(Date.now() + SESSION_MS);
  setCookie(res, `${expires}.${sign(expires)}`, SESSION_MS / 1000);
  return true;
}

export function signOut(res: http.ServerResponse) {
  setCookie(res, "", 0);
}

function setCookie(res: http.ServerResponse, value: string, maxAge: number) {
  res.setHeader(
    "set-cookie",
    `${COOKIE}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=${maxAge}${COOKIE_SECURE ? "; Secure" : ""}`,
  );
}

export function hasReadToken(req: http.IncomingMessage): boolean {
  const header = String(req.headers.authorization ?? "");
  return header.startsWith("Bearer ") && safeEqual(header.slice(7), READ_TOKEN);
}
