# Moonlit

A SwiftUI iOS app where people chat with five AI psychic characters for fun. Readings come from a small Node server that holds the Claude API key and streams replies from Claude (`claude-opus-5-5`) back to the app.

```
iPhone app ──► Moonlit server (holds the key, limits use) ──► Claude
```

## Run it locally

1. Start the server:

   ```bash
   cd server
   npm install
   ANTHROPIC_API_KEY=sk-ant-... npm run dev
   ```

   It listens on `http://localhost:8787`. Check it with `curl localhost:8787/health`.

2. Open `Moonlit.xcodeproj` in Xcode 26 and run the **Moonlit** scheme on an iPhone simulator (iOS 17+). The simulator reaches your Mac's `localhost`, so live readings work right away.

If the server isn't running, the app shows a "Can't reach the reading server" banner. Clear the server address in Settings to use demo mode with pre-written replies.

## The server (`server/`)

| Endpoint | What it does |
| --- | --- |
| `GET /health` | Returns `{ ok: true, model }` |
| `POST /v1/reading` | Takes `{ psychicId, userName, sign, messages }` and streams newline-delimited JSON: `{"type":"text","text":…}` pieces, then `{"type":"done"}` or `{"type":"error","code","message"}` |

- The psychics' instructions live in `server/src/psychics.ts`. The app sends only the chat, so it can't be used as a free general-purpose Claude proxy.
- Each request must carry an `x-device-id` header (the app generates one per install). Limits are per device and per IP address over a rolling 24 hours.
- The server stops the Claude request if the user leaves mid-reading, so you don't pay for unread tokens.
- If Claude declines a question, a fallback model answers automatically (`fallbacks: "default"`).

Environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `ANTHROPIC_API_KEY` | (required) | Your Claude API key |
| `PORT` | `8787` | Port to listen on |
| `MOONLIT_MODEL` | `claude-opus-5-5` | Model used for readings |
| `DEVICE_DAILY_LIMIT` | `40` | Readings per device per 24 h |
| `IP_DAILY_LIMIT` | `200` | Readings per IP address per 24 h |
| `MOONLIT_APP_KEY` | (empty) | Optional shared key the app must send in `x-moonlit-key`. Set the same value in `ReadingClient.appKey`. It deters casual misuse but isn't real security. |

Rate limits are kept in memory, so they reset when the server restarts and only work with a single instance. Move them to Redis or a database before scaling out.

## Deploying

The server runs on any Node 22.18+ host with `npm start`; Railway, Render and Fly.io all work. Set `ANTHROPIC_API_KEY` in the host's dashboard, then put the public URL in `ReadingClient.defaultServerURL` (or in the app's Settings while testing).

## App layout

| File | What it does |
| --- | --- |
| `Moonlit/Models.swift` | The five psychics (bio, greeting, demo lines), star signs and the tarot deck |
| `Moonlit/AppState.swift` | Navigation, saved readings (UserDefaults), and turning the chat into turns for the server |
| `Moonlit/ReadingClient.swift` | Calls the server and reads the streamed reply |
| `Moonlit/Views/` | Welcome, Home, Profile, Chat, Readings and Settings screens |
| `Moonlit/Resources/` | Psychic portraits |

## Before a public release

- Deploy the server over HTTPS and point the app at it.
- Add real user accounts or App Attest if you need stronger protection than per-device limits.
- Replace the 200 px portraits with full-resolution exports, add an app icon, and set your own bundle identifier and team.
