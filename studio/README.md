# Psychic Studio

A separate service for writing the psychics: each one's persona, example replies and background documents,
edited in the browser. The reading server (`server/`) fetches finished personas from it every minute, so an
edit reaches readings within a minute without a deploy. The iOS app never talks to the studio.

## Run it locally

Needs Node 24 or later. No dependencies beyond TypeScript for type checking.

```bash
cd studio
cp .env.example .env    # set STUDIO_PASSWORD and STUDIO_READ_TOKEN
npm install
npm run dev             # http://localhost:8790
```

On first start, with an empty database, it imports the psychics from `server/psychics/` (`STUDIO_SEED_DIR`).
After that, the database is the source of truth.

Then point the reading server at it, in `server/.env`:

```bash
PERSONA_STUDIO_URL=http://localhost:8790
PERSONA_STUDIO_TOKEN=<the studio's STUDIO_READ_TOKEN>
```

`GET /health` on the reading server shows where its personas came from (`"source": "studio"`).

## What editors can do

Everything saves automatically a moment after you stop typing. The indicator next to the tabs shows
"Saving…", "All changes saved", or what went wrong. Until a psychic is complete, a to-do list at the top shows
what's still missing, and each item jumps to its field.

- **Persona**: name, specialty, backstory, voice, texting style, catchphrases, things they never do, quirks,
  opinions of the others, and how they read their ritual.
- **Examples**: short exchanges that show how the psychic texts. Blank lines in a reply become separate bubbles.
- **Documents**: background notes such as history, beliefs, people in their life or how they read particular cards.
  Write them, upload `.md` / `.txt` files, or drop files onto the page. Each one can be switched off without deleting it.
- **History**: every version of the psychic, newest first, with what changed in each. Edits made within
  10 minutes of each other are grouped into one version, and the last 150 versions are kept. "Go back to this"
  restores an earlier version; the restore is itself a new version, so it can be undone. Deleting a psychic
  deletes its history too.
- **New psychic**: readings can use it once the persona and at least one example are filled in. The iOS
  app also needs an update before users can pick it, because the app's list of psychics is built in.

A psychic with an empty required field shows as "Not live yet" and isn't sent to the reading server.
Everything marked "Used in readings" goes into every reading with that psychic. The persona part of the prompt
is cached, so tens of pages per psychic stays cheap.

## How it fits together

| Piece | Where |
| --- | --- |
| HTTP server, routes and validation | `src/index.ts` |
| SQLite storage (`node:sqlite`, file in `STUDIO_DATA_DIR`) | `src/db.ts` |
| Password sign-in (signed cookie) and the read token | `src/auth.ts` |
| Import from markdown folders | `src/seed.ts` |
| Web interface, no build step | `public/` |

| Endpoint | Who uses it |
| --- | --- |
| `GET /v1/personas` | The reading server, with `Authorization: Bearer <STUDIO_READ_TOKEN>`. Returns every live psychic. |
| `/api/...` | The web interface, after signing in |
| `GET /health` | Uptime checks |

If the studio is down or returns an error, the reading server keeps the personas it last fetched. If it never
reached the studio, it uses the files in `server/psychics/`.

## Deploying

Run it as its own service with `npm start`, separate from the reading server. Set `STUDIO_PASSWORD`,
`STUDIO_READ_TOKEN`, `STUDIO_SESSION_SECRET` and `COOKIE_SECURE=1`, and put `STUDIO_DATA_DIR` on a
persistent volume: the database is the only copy of your edits, so back it up. Serve it over HTTPS; it
holds the psychics' instructions, so don't leave it open without the password.

## Not built yet

- Several editor accounts. There is one shared password.
- Trying a reading from the studio before an edit goes live.
- PDF and Word uploads (only `.md` and `.txt` for now).
