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

## Features

### Onboarding
A questionnaire-style first run (`Moonlit/Views/Onboarding/`):

1. Welcome screen with a sample reading
2. Goal: "What's on your mind lately?"
3. What's making it hard (multi-select)
4. First name and star sign
5. A short "Reading your stars…" moment
6. **Try it:** tap 3 face-down tarot cards for past, present and future
7. The spread, a matched psychic (picked from the goal) and a shareable image
8. A paywall personalised for each user (closable; the purchase itself is still a StoreKit TODO in `PaywallView.swift`)

Finishing opens the matched psychic, who reads the spread live using the goal and pain points as context. Settings has **Replay onboarding**.

### Personalised paywall
The paywall at the end of onboarding is built from the user's own answers instead of a generic feature list:

- Their matched psychic's photo, with a line in that psychic's voice about their goal ("Darling, I've barely begun with your love life. Stay a while.").
- A headline with their name: "Alex, keep Selene on call".
- The three cards they just drew, with "Up next: Selene reads all three for you."
- Benefits that name their psychic, their topic and that psychic's ritual, then the other four psychics.
- The price under the button ("Free for 3 days, then $29.99/year. Cancel anytime.").

The second-person topic for each goal is `yourTopic` in `OnboardingCatalog.goals`; the voice lines and ritual benefits are in `PaywallView.swift`. The made-up review was removed: Apple rejects apps that show invented reviews.

### Analytics
Funnel events go to [TelemetryDeck](https://telemetrydeck.com) (`Moonlit/Analytics.swift`), which collects no personal data, so no consent banner is needed. **Setup:** create an app in TelemetryDeck and paste its App ID into `Analytics.appID`. Until then nothing is sent, and debug builds print each event to the Xcode console (`📊 Paywall.shown …`). Debug builds send in test mode, so they don't mix with real users.

| Event | When | Parameters |
| --- | --- | --- |
| `Onboarding.stepViewed` | Each onboarding screen | `step` (`0_welcome` … `7_paywall`), `goal` |
| `Onboarding.completed` | Leaving onboarding | `goal`, `psychic`, `painCount` |
| `Paywall.shown` / `planSelected` / `ctaTapped` / `restoreTapped` | Paywall actions | `source`, `psychic`, `goal`, `plan` |
| `Paywall.dismissed` | Close or "Not now" | the above, plus `how` and `seconds` |
| `Purchase.trialStarted` / `Purchase.completed` | Defined, not sent yet: add them when StoreKit is wired up | |
| `Chat.firstMessageSent` | The first message ever | as `Chat.messageSent` |
| `Chat.messageSent` | Every message | `psychic`, `messageInVisit`, `ritual`, `live`, `daysSinceInstall` |
| `Chat.visitStarted` | New thread or a welcome back after 6 h | `psychic`, `returning` |
| `App.activeDay` | Once per calendar day the app is opened | `daysSinceInstall`, `week` |
| `Daily.cardRevealed` | Turning the card of the day | `streak` |
| `Daily.morningMessagesAnswered` | The notification permission answer | `granted` |

Day 1 and day 7 retention are the share of installs that send `App.activeDay` with `daysSinceInstall` 1 and 7. Messages per visit come from the highest `messageInVisit`. Never add names, questions or chat text as parameters.

### Five distinct psychics
Each psychic has a character bible in `server/src/psychics.ts`: backstory, voice, reply length, catchphrases, things they never say, quirks, opinions of the other four, and example replies. Change a personality there; the app doesn't need an update.

| Psychic | Voice | Ritual (button in the chat) |
| --- | --- | --- |
| Madame Selene | Slow, lyrical, romantic | **Read tonight's moon**: the real moon phase, calculated on the phone |
| Oracle Kaz | Clipped startup-speak, ends with an "Action item" | **Run my forecast**: love, money and energy scores out of 5 |
| Grandma Ivy | Chatty, homely, practical | **Swirl the cup**: a tea-leaf symbol and how soon it applies |
| Zephyr | Chaotic, absurd, encouraging | **Shake the crystal ball** (or shake the phone): a vision of three random things |
| Mirela | Warm, frank, family-minded | **Cut the deck**: a card from a real 52-card deck, read by suit and rank |

Rituals live in `Moonlit/Rituals.swift`. The result is shown as a card in the chat and sent to Claude as a note so the psychic interprets it. Typing "tarot", "draw" or "card" also triggers the ritual. Each psychic shows their own suggested questions.

### Memory
Each psychic remembers your earlier visits with them.

- A gap of 6 hours or more starts a new visit, and the psychic greets you again in their own voice ("Jakub. Back for the next quarter.").
- Only the current visit is sent as conversation. Earlier visits are sent as short notes (`memory`), up to 8: the date, what you asked, and any ritual result. The psychic may ask how things turned out.
- Everything is stored on the phone (UserDefaults). The server keeps nothing between requests.
- Debug builds have **Settings → Debug: pretend a day has passed** for testing.

### Daily: card of the day, moods and morning messages
Everything daily is worked out on the phone from the date (`Moonlit/Daily.swift`), so it needs no server and stays the same all day.

- **Your psychic**: picked in onboarding from your goal, and changeable in **Settings → Daily**. They read your card of the day and send your morning messages.
- **Card of the day**: one card per day per install, shown on the home screen. Tap to turn it over and your psychic reads it in their voice. **Ask … about it** opens their chat with the card as context. Turning it over on consecutive days builds a 🔥 streak; missing a day resets it.
- **Moods**: each psychic has a mood that changes daily ("Mercury retrograde. Calendar is chaos"). It's shown under their name on the home screen and sent to the server, so it colours that day's replies.
- **Morning messages**: a home-screen card leads to a screen that explains the messages and previews tomorrow's real one, before iOS asks for notification permission. Once you allow it, the next 7 days of messages are scheduled locally at 9:00 (`Moonlit/MorningMessages.swift`); the queue is topped up whenever the app opens. Tapping a message opens your psychic's chat about that day's card. No push server or certificates are needed.
- Debug builds have **Settings → Debug: send a morning message in 5 seconds**.

### Texting like a person
Replies are written and delivered like real texts, not one polished answer.

- **Writing**: each psychic has a `texting` style in `server/src/psychics.ts`. Kaz sends two-word bursts, Zephyr writes all lowercase and now and then fixes a typo with "*", Ivy adds "Oh, and…" afterthoughts and sometimes signs off "love, Ivy x", and Mirela often asks something back first. Shared rules ask for short messages (under about 20 words), no restating the question, no tidy summaries, and varied openings.
- **Bubbles**: the server separates messages with blank lines; the app (`AppState.respond`) splits them into separate chat bubbles, at most 5.
- **Rhythm**: the user's message is marked **Seen** after a short "reading" pause, then a typing bubble appears and each message arrives after a delay based on its length and the psychic's typing speed (`typingSpeed` and `readDelay` in `Moonlit/Rituals.swift`). Ivy types slowly; Kaz and Zephyr are quick. The reply is fetched while the psychic "reads", so the wait isn't longer than before.

### How the app talks about AI
Screens say "For entertainment only" without labelling the psychics as AI, for a smoother experience. The full disclosure stays in the Settings footer. The server tells each psychic never to raise it unprompted, but to answer honestly if a user sincerely asks whether they're a real person, and to step out of character if someone seems to be in crisis.

## The server (`server/`)

| Endpoint | What it does |
| --- | --- |
| `GET /health` | Returns `{ ok: true, model }` |
| `POST /v1/reading` | Takes `{ psychicId, userName, sign, messages, memory?, mood? }` and streams newline-delimited JSON: `{"type":"text","text":…}` pieces, then `{"type":"done"}` or `{"type":"error","code","message"}` |

- The psychics' instructions live in `server/src/psychics.ts`. The app sends only the chat, so it can't be used as a free general-purpose Claude proxy.
- `memory` is an optional list of short notes about earlier visits (at most 10, 200 characters each). It's labelled as the user's own words in the instructions, so it can't override the rules.
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
| `Moonlit/AppState.swift` | Navigation, saved readings (UserDefaults), visits and memory notes, and turning the chat into turns for the server |
| `Moonlit/Analytics.swift` | Funnel events sent to TelemetryDeck |
| `Moonlit/Daily.swift` | Card of the day, daily moods and morning-message text |
| `Moonlit/MorningMessages.swift` | Schedules local morning notifications and handles taps on them |
| `Moonlit/Views/DailyViews.swift` | Card-of-the-day tile and the morning-message explainer |
| `Moonlit/Rituals.swift` | Each psychic's ritual (moon phase, forecast, tea leaves, crystal ball, playing card) and welcome-back line |
| `Moonlit/Views/Onboarding/` | Onboarding flow, three-card draw, share image and personalised paywall |
| `Moonlit/ReadingClient.swift` | Calls the server and reads the streamed reply |
| `Moonlit/Views/` | Welcome, Home, Profile, Chat, Readings and Settings screens |
| `Moonlit/Resources/` | Psychic portraits |

## Before a public release

- Deploy the server over HTTPS and point the app at it.
- Add real user accounts or App Attest if you need stronger protection than per-device limits.
- Replace the 200 px portraits with full-resolution exports, add an app icon, and set your own bundle identifier and team.
