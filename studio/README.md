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
After that, the database is the source of truth. The one exception: the first start after decks were added
fills in each psychic's "How I read" and deck from those files, if the psychic has neither yet.

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
  opinions of the others, how they read their ritual, and (optional) how they read cards.
- **Deck**: tarot or playing cards, and the psychic's own meaning for any card (upright, reversed, and a memory
  tied to it). Blank cards use the traditional meaning, which the reading server holds.
- **Examples**: short exchanges that show how the psychic texts. Blank lines in a reply become separate bubbles.
- **Documents**: background notes such as history, beliefs, people in their life or how they read particular cards.
  Write them, upload `.md` / `.txt` files, or drop files onto the page. Each one can be switched off without deleting it.
- **Photo**: click the round photo next to the name, or drop an image onto it. Photos are cropped to a square
  and shrunk to at most 800 px. On first start, psychics get the photo bundled with the iOS app
  (`AsFate/Resources/psychic_<id>.png`, set by `STUDIO_PHOTO_DIR`). Photo changes are part of the history.
- **Write with Claude**: the button at the top right. Claude reads everything written about the psychic so far
  (fields, every document, examples, card meanings, the rest of the cast) and writes what you tick: the empty persona
  fields or all of them, more example replies, their own meanings for cards it picks, or a background document on a
  topic you give. Add notes to steer it ("drier and funnier", "she grew up in Naples"). Each card in the Deck tab also
  has its own button. Whatever Claude writes is saved as one version, with an Undo right after and in History.
  The quickest way to make a new psychic: create it, add a document or two about who they are, then tick everything.
  Needs `ANTHROPIC_API_KEY` in the studio's settings (and `STUDIO_MODEL` to change the model from `claude-opus-5-5`);
  without it the buttons are switched off.
- **History**: every version of the psychic, newest first, with what changed in each. Edits made within
  10 minutes of each other are grouped into one version, and the last 150 versions are kept. "Go back to this"
  restores an earlier version; the restore is itself a new version, so it can be undone. Deleting a psychic
  deletes its history too.
- **New psychic**: a guided setup, step by step: the idea, background documents, deck and tone, Claude writes
  them, review (with a preview of how they look in the app), photo, then "Show in the app". Readings can use a
  psychic once the persona and at least one example are filled in; a psychic that isn't finished shows
  "Continue guided setup" at the top.
- **In the app**: what the iOS app shows: tagline, bio, tags, greeting, suggested questions, daily moods, ritual
  button, colour, typing speed, morning messages, with a phone preview. A new psychic appears in the app once it's
  live, has a tagline, bio, greeting and at least one suggested question, and "Show in the app" is on: the app
  picks it up from the reading server the next time it checks in, with no app update. Their ritual button draws a
  card from their deck. For the five psychics built into the app, anything filled in here replaces the app's own
  text, field by field.

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
| `GET /v1/photos/<id>` | Same token. A psychic's photo, for when the app starts loading photos through the reading server. |
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
