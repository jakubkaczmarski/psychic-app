// Imports personas from a folder of markdown files (the format in server/psychics/README.md).

import fs from "node:fs";
import path from "node:path";
import { importPsychic, LIST_FIELDS, PERSONA_FIELDS, type Persona } from "./db.ts";

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

  const examplesPath = path.join(dir, "examples.md");
  const examples = fs.existsSync(examplesPath)
    ? sections(fs.readFileSync(examplesPath, "utf8")).map(([user, reply]) => ({ user, reply }))
    : [];

  const docs = fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".md") && f !== "persona.md" && f !== "examples.md")
    .sort()
    .map((file) => {
      const md = fs.readFileSync(path.join(dir, file), "utf8");
      return { title: title(md) ?? path.basename(file, ".md"), body: md.replace(/^# .+$/m, "").trim() };
    });

  return { persona, examples, docs };
}

export function seedFrom(root: string): number {
  if (!fs.existsSync(root)) {
    console.warn(`Seed folder ${root} not found; starting with no psychics.`);
    return 0;
  }
  let count = 0;
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    if (!entry.isDirectory() || /^[._]/.test(entry.name)) continue;
    const dir = path.join(root, entry.name);
    if (!fs.existsSync(path.join(dir, "persona.md"))) continue;
    const { persona, examples, docs } = readFolder(dir);
    importPsychic(entry.name, persona, examples, docs);
    count++;
  }
  return count;
}
