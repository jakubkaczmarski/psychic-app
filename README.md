# As Fate Would Have It

The app was called Moonlit; the server, its Railway address and the `x-moonlit-key` header keep that name.

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

2. Open `AsFate.xcodeproj` in Xcode 26 and run the **AsFate** scheme on an iPhone simulator (iOS 17+). The simulator reaches your Mac's `localhost`, so live readings work right away.

If the server isn't running, the app shows a "Can't reach the reading server" banner. Clear the server address in Settings to use demo mode with pre-written replies.

## Features

### Onboarding
A questionnaire-style first run (`AsFate/Views/Onboarding/`):

1. Welcome screen with a sample reading
2. Goal: "What's on your mind lately?"
3. What's making it hard (multi-select)
4. First name and star sign
5. A short "Reading your stars…" moment
6. **Try it:** tap 3 face-down tarot cards for past, present and future
7. The spread, a matched psychic (picked from the goal) and a shareable image. The psychic's reading of the spread starts loading as soon as the cards are drawn (`AppState.startTeaser`): without Fate+ the first message is readable and the rest is shown blurred, and the button reads "Read Selene's full reading". If the reading fails, the card meanings are shown instead
8. A paywall personalised for each user (closable), with real StoreKit 2 purchases

Finishing opens the matched psychic's chat with that same reading (it isn't fetched twice). Without Fate+ the blurred part stays locked there, under **Unlock {psychic}'s reply**; Fate+ reveals it in place. Settings has **Replay onboarding**.

### Personalised paywall
The paywall at the end of onboarding is built from the user's own answers instead of a generic feature list:

- Their matched psychic's photo, with a line in that psychic's voice about their goal ("Darling, I've barely begun with your love life. Stay a while.").
- A headline with their name: "Alex, keep Selene on call".
- The three cards they just drew, with "Up next: Selene reads all three for you."
- Benefits that name their psychic, their topic and that psychic's ritual, then the other four psychics.
- The price under the button ("Free for 3 days, then $29.99/year. Cancel anytime."), taken from the App Store in the user's currency. The trial is only offered to people who can still get it.

The second-person topic for each goal is `yourTopic` in `OnboardingCatalog.goals`; the voice lines and ritual benefits are in `PaywallView.swift`. The made-up review was removed: Apple rejects apps that show invented reviews.

### Free messages and locked replies
Without Fate+ you get **3 free messages a day** (`AppState.freeMessagesPerDay`). The onboarding reading and the first question about the card of the day don't count. Rituals and suggested questions do.

- When 1 or 0 free messages are left, a line above the input says so ("No free messages left today · your next reply will be locked · **Go unlimited**").
- A message sent after that is **not sent to the server**: the psychic reads it and types as usual, but what arrives is a **blurred** stand-in bubble with a lock, and an **Unlock {psychic}'s reply** button opens the paywall. The real reply is fetched and typed out once Fate+ is unlocked, so a locked reply costs nothing.
- Once the locked reply has arrived, the input is replaced by "You've used today's 3 free messages. More tomorrow, or unlock unlimited readings now." So at most one reply a day is locked. The limit resets the next day.
- If the reply fails, the free message is given back and nothing is locked.
- The paywall opened from a locked reply says "Read Selene's reply", with a line in the psychic's voice ("Your answer is waiting under the moonlight, darling.").
- Settings shows the free messages left, **Restore purchases** and, with Fate+, **Manage subscription**. Debug builds add **Debug: reset Fate+ and free messages**.
- The limit is kept on the phone, so reinstalling resets it. Enforce it on the server (per device and per subscription) once purchases are real.

### Fate+ subscriptions (StoreKit 2)
`AsFate/Store.swift` loads the products, buys and restores them, and listens for renewals, refunds and Ask to Buy approvals. `AppState.isPlus` follows the App Store's verified entitlements, checked at launch and on every change; when a subscription ends, Fate+ turns off again.

| Product ID | Plan |
| --- | --- |
| `com.jakubkaczmarski.asfate.plus.yearly` | $29.99/year with a 3-day free trial |
| `com.jakubkaczmarski.asfate.plus.weekly` | $4.99/week |

- **Mock purchases (on for now):** while `Store.mockPurchases` is `true`, nothing goes through StoreKit. In every build, TestFlight included, the paywall button turns Fate+ on for free, and Settings shows **Turn off Fate+ (test build)** instead of Manage subscription. Purchase events are still tracked, with `mock=true`. Set it to `false` once the products exist in App Store Connect.

- **Test purchases:** run the **AsFate** scheme from Xcode. The shared scheme uses `AsFate.storekit`, so purchases, trials, renewals and refunds work locally without App Store Connect and nothing is charged. Use **Debug → StoreKit → Manage Transactions** in Xcode to refund or expire them.
- **Launched outside Xcode** (for example with `simctl`), StoreKit has no products. The paywall then shows the default prices, and debug builds unlock Fate+ locally when you tap the button (`debugPlus`; cleared by the debug reset). Release builds never do this: they say the purchase isn't available.
- **Before release:** create a subscription group "Fate+" with both products in App Store Connect, using the same IDs, prices and trial. Then test once with a Sandbox account on a real device.

### Analytics
Funnel events go to [TelemetryDeck](https://telemetrydeck.com) (`AsFate/Analytics.swift`), which collects no personal data, so no consent banner is needed. **Setup:** create an app in TelemetryDeck and paste its App ID into `Analytics.appID`. Until then nothing is sent, and debug builds print each event to the Xcode console (`[analytics] Paywall.shown …`). Debug builds send in test mode, so they don't mix with real users.

| Event | When | Parameters |
| --- | --- | --- |
| `Onboarding.stepViewed` | Each onboarding screen | `step` (`0_welcome` … `7_paywall`), `goal` |
| `Onboarding.completed` | Leaving onboarding | `goal`, `psychic`, `painCount` |
| `Onboarding.teaserShown` | The first reading appeared on the result screen | `psychic`, `parts`, `locked` (bubble counts) |
| `Paywall.shown` / `planSelected` / `ctaTapped` / `restoreTapped` | Paywall actions | `source`, `psychic`, `goal`, `plan`, `trialEligible` |
| `Paywall.dismissed` | Close or "Not now" | the above, plus `how` and `seconds` |
| | `source` is `onboarding`, `lockedReply`, `limitBar`, `freeHint` or `settings` | |
| `Paywall.productsUnavailable` | The App Store returned no products | as `Paywall.shown` |
| `Purchase.trialStarted` / `Purchase.completed` | A verified yearly trial / any other purchase | paywall parameters, `productID`, `seconds` |
| `Purchase.cancelled` / `Purchase.pending` / `Purchase.failed` | The purchase sheet was closed, waits for approval, or failed | paywall parameters, `seconds`; `reason` on failures |
| `Purchase.restored` | Restore finished | `source`, `found`; `reason` on failures |
| `Purchase.subscriptionEnded` | Fate+ was on and the entitlement is gone (expired, refunded) | |
| `Chat.firstMessageSent` | The first message ever | as `Chat.messageSent` |
| `Chat.messageSent` | Every message | `psychic`, `messageInVisit`, `ritual`, `live`, `daysSinceInstall` |
| `Chat.visitStarted` | New thread or a welcome back after 6 h | `psychic`, `returning` |
| `Chat.replyLocked` | A locked stand-in was shown after the free messages ran out | `psychic` |
| `App.activeDay` | Once per calendar day the app is opened | `daysSinceInstall`, `week` |
| `Daily.cardRevealed` | Turning the card of the day | `streak` |
| `Daily.morningMessagesAnswered` | The notification permission answer | `granted` |

**Every event** also carries the user's onboarding answers and a few counters (`Analytics.context`): `goal`, `pains` (sorted IDs, such as `overthink,signals`), `painCount`, `sign`, `psychic`, `onboardingVersion`, `isPlus` and `paywallViews`. So any event can be split by them. For example, filter `Purchase.trialStarted` by `pains` to see which answers convert best, or break `Paywall.shown → Purchase.trialStarted` down by `source` to see which paywall sells. Bump `Analytics.onboardingVersion` whenever you change the onboarding or paywall, so you can compare conversion before and after. Successful purchases also send TelemetryDeck's built-in purchase signal, which fills its revenue and trial dashboards.

Day 1 and day 7 retention are the share of installs that send `App.activeDay` with `daysSinceInstall` 1 and 7. Messages per visit come from the highest `messageInVisit`. Never add names, questions or chat text as parameters.

### Five distinct psychics
Each psychic has a character bible as markdown files in `server/psychics/<id>/`: backstory, voice, reply length, catchphrases, things they never say, quirks, opinions of the other four, and example replies, plus any extra documents you add (lore, beliefs, memories). Change a personality there and restart the server; the app doesn't need an update. The format is in [server/psychics/README.md](server/psychics/README.md).

| Psychic | Voice | Ritual (button in the chat) |
| --- | --- | --- |
| Madame Selene | Slow, lyrical, romantic | **Read tonight's moon**: the real moon phase, calculated on the phone |
| Oracle Kaz | Clipped startup-speak, ends with an "Action item" | **Run my forecast**: love, money and energy scores out of 5 |
| Grandma Ivy | Chatty, homely, practical | **Swirl the cup**: a tea-leaf symbol and how soon it applies |
| Zephyr | Chaotic, absurd, encouraging | **Shake the crystal ball** (or shake the phone): a vision of three random things |
| Mirela | Warm, frank, family-minded | **Cut the deck**: a card from a real 52-card deck, read by suit and rank |

Rituals live in `AsFate/Rituals.swift`. The result is shown as a card in the chat and sent to Claude as a note so the psychic interprets it. Typing "tarot", "draw" or "card" also triggers the ritual. Each psychic shows their own suggested questions.

### Memory
Each psychic remembers your earlier visits with them.

- A gap of 6 hours or more starts a new visit, and the psychic greets you again in their own voice ("Jakub. Back for the next quarter.").
- Only the current visit is sent as conversation. Earlier visits are sent as short notes (`memory`), up to 8: the date, what you asked, and any ritual result. The psychic may ask how things turned out.
- Everything is stored on the phone (UserDefaults). The server keeps nothing between requests.
- Debug builds have **Settings → Debug: pretend a day has passed** for testing.

### Daily: card of the day, moods and morning messages
Everything daily is worked out on the phone from the date (`AsFate/Daily.swift`), so it needs no server and stays the same all day.

- **Your psychic**: picked in onboarding from your goal, and changeable in **Settings → Daily**. They read your card of the day and send your morning messages.
- **Card of the day**: one card per day per install, shown on the home screen. Tap to turn it over and your psychic reads it in their voice. **Ask … about it** opens their chat with the card as context. Turning it over on consecutive days builds a streak; missing a day resets it.
- **Moods**: each psychic has a mood that changes daily ("Mercury retrograde. Calendar is chaos"). It's shown under their name on the home screen and sent to the server, so it colours that day's replies.
- **Morning messages**: a home-screen card leads to a screen that explains the messages and previews tomorrow's real one, before iOS asks for notification permission. Once you allow it, the next 7 days of messages are scheduled locally at 9:00 (`AsFate/MorningMessages.swift`); the queue is topped up whenever the app opens. Tapping a message opens your psychic's chat about that day's card. No push server or certificates are needed.
- Debug builds have **Settings → Debug: send a morning message in 5 seconds**.

### Cosmic view
A 3D view of the solar system for any date (`AsFate/Cosmos/`), opened from the **Cosmic view** card on the home screen. The card teases today's sky ("Mercury and Venus are retrograde").

- **Real positions**: `Ephemeris.swift` works out where every planet is from NASA JPL's approximate orbital elements (valid 1800–2050, well under a degree off), and the Moon from a short series. It gives each body's sign, degree, and whether it's retrograde. Checked against published charts for 1 Jan 2000 and the 8 Apr 2024 eclipse (Sun and Moon both at 19° Aries).
- **The scene** (`CosmosScene.swift`, SceneKit): the Sun, eight planets on their orbits, the Moon beside Earth, a slowly drifting, twinkling starfield and a zodiac dial around everything. Distances are logarithmic so the inner planets get room; directions are real.
- **Looks**: photographic surface maps for the Sun, Moon and every planet, Earth with a separate drifting cloud layer, Saturn's real ring texture, and the Milky Way as the sky (`AsFate/Resources/Planets/`, about 56 MB: 2K maps for the solar system scene, plus one 8K map per body, or 4K where the source has nothing larger, for the close-up in the detail sheet). They come from [Solar System Scope](https://www.solarsystemscope.com/textures/), based on NASA imagery and licensed CC BY 4.0; the credit is in the Settings footer and must stay there. Planets are matte-shaded with a thin atmosphere rim; the Sun is brightened towards the centre and is the only thing that blooms.
- **Sheet**: a black bottom sheet with the date, a status pill and the time ruler. Folded, it shows one card per body; pulled up by its handle, a list with each body's sign, degree and whether it is retrograde. Selecting a body shows a turning close-up (`PlanetHero`), the sign it is in and the one it enters next with both dates and a progress bar, and tiles for its speed, distance from Earth and retrograde dates.
- **Moving around**: drag to orbit, pinch to zoom. It opens with a fly-in from deep space.
- **Picking a planet** (tap it or its chip): the dial turns so that planet's sign is at the top, the sign lights up gold, and a gold beam runs from Earth through the planet to the exact degree. If it's retrograde (or will be soon) the card shows the dates, e.g. "Retrograde 24 Oct – 13 Nov" (worked out from the planet's apparent motion, checked against published 2026–27 dates), and a coral arc on the dial marks the stretch of sky it walks back over. Crossing into a new sign while scrubbing gives a small haptic tap. A card explains it ("Mercury rules how you think and talk. In Scorpio it's intense and private.") and **Ask {psychic} what it means** opens your psychic's chat with the whole sky as context.
- **Time travel**: drag the ruler to scrub day by day (with a flick), or press play: time glides forward at 1 day a second, and the speed button switches to 1 week or 1 month a second. The ↩ button glides back to today.
- Labels are a 2D overlay pinned to each planet every frame, so they stay the same size at any zoom; a label that would overlap a more important one hides.

### Texting like a person
Replies are written and delivered like real texts, not one polished answer.

- **Writing**: each psychic has a `## Texting` section in `server/psychics/<id>/persona.md`. Kaz sends two-word bursts, Zephyr writes all lowercase and now and then fixes a typo with "*", Ivy adds "Oh, and…" afterthoughts and sometimes signs off "love, Ivy x", and Mirela often asks something back first. Shared rules ask for short messages (under about 20 words), no restating the question, no tidy summaries, and varied openings.
- **Bubbles**: the server separates messages with blank lines; the app (`AppState.respond`) splits them into separate chat bubbles, at most 5.
- **Rhythm**: the user's message is marked **Seen** after a short "reading" pause, then a typing bubble appears and each message arrives after a delay based on its length and the psychic's typing speed (`typingSpeed` and `readDelay` in `AsFate/Rituals.swift`). Ivy types slowly; Kaz and Zephyr are quick. The reply is fetched while the psychic "reads", so the wait isn't longer than before.

### How the app talks about AI
Screens say "For entertainment only" without labelling the psychics as AI, for a smoother experience. The full disclosure stays in the Settings footer. The server tells each psychic never to raise it unprompted, but to answer honestly if a user sincerely asks whether they're a real person, and to step out of character if someone seems to be in crisis.

## The server (`server/`)

| Endpoint | What it does |
| --- | --- |
| `GET /health` | Returns `{ ok: true, model, personas }`, where `personas` says whether they came from the files or Psychic Studio |
| `POST /v1/reading` | Takes `{ psychicId, userName, sign, messages, memory?, mood? }` and streams newline-delimited JSON: `{"type":"text","text":…}` pieces, then `{"type":"done"}` or `{"type":"error","code","message"}` |

- The psychics' instructions are built from `server/psychics/` by `server/src/psychics.ts`. The persona part is prompt-cached, so a long character bible costs little after the first reading. The app sends only the chat, so it can't be used as a free general-purpose Claude proxy.
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
| `PERSONA_STUDIO_URL` | (empty) | Optional. Fetch personas from Psychic Studio instead of `server/psychics/`, refreshed every minute. The files stay the fallback. |
| `PERSONA_STUDIO_TOKEN` | (empty) | The studio's `STUDIO_READ_TOKEN` |
| `MOONLIT_APP_KEY` | (empty) | Optional shared key the app must send in `x-moonlit-key`. Set the same value in `ReadingClient.appKey`. It deters casual misuse but isn't real security. |

Rate limits are kept in memory, so they reset when the server restarts and only work with a single instance. Move them to Redis or a database before scaling out.

## Psychic Studio (`studio/`)

A separate service with a web interface for writing each psychic's persona, example replies and background documents. The iOS app never talks to it: the reading server fetches finished personas from it, so an edit reaches readings within a minute without a deploy. Setup and details are in [studio/README.md](studio/README.md).

```
iOS app ──► reading server (server/) ──► Claude
                  │ GET /v1/personas every minute
                  ▼
           Psychic Studio (studio/) ◄── editors, in the browser
```

## Deploying

The server runs on any Node 22.18+ host with `npm start`; Railway, Render and Fly.io all work. Set `ANTHROPIC_API_KEY` in the host's dashboard, then put the public URL in `ReadingClient.defaultServerURL` (or in the app's Settings while testing).

To use Psychic Studio, deploy `studio/` as a second service with a persistent volume for its database (see [studio/README.md](studio/README.md)), then set `PERSONA_STUDIO_URL` and `PERSONA_STUDIO_TOKEN` on the reading server.

## App layout

| File | What it does |
| --- | --- |
| `AsFate/Models.swift` | The five psychics (bio, greeting, demo lines), star signs and the tarot deck |
| `AsFate/AppState.swift` | Navigation, saved readings (UserDefaults), visits and memory notes, and turning the chat into turns for the server |
| `AsFate/Cosmos/` | Cosmic view: planet positions (`Ephemeris`), the 3D scene and the screen with the time scrubber |
| `AsFate/Analytics.swift` | Funnel events sent to TelemetryDeck, with the onboarding answers on every event |
| `AsFate/Store.swift` | Fate+ subscriptions with StoreKit 2: products, purchase, restore and entitlements |
| `AsFate.storekit` | Local StoreKit test products, used when running the **AsFate** scheme from Xcode |
| `AsFate/Daily.swift` | Card of the day, daily moods and morning-message text |
| `AsFate/MorningMessages.swift` | Schedules local morning notifications and handles taps on them |
| `AsFate/Views/DailyViews.swift` | Card-of-the-day tile and the morning-message explainer |
| `AsFate/Rituals.swift` | Each psychic's ritual (moon phase, forecast, tea leaves, crystal ball, playing card) and welcome-back line |
| `AsFate/Views/Onboarding/` | Onboarding flow, three-card draw, share image and personalised paywall |
| `AsFate/ReadingClient.swift` | Calls the server and reads the streamed reply |
| `AsFate/Views/` | Welcome, Home, Profile, Chat, Readings and Settings screens |
| `AsFate/Resources/` | Psychic portraits, and planet textures in `Planets/` (CC BY 4.0, Solar System Scope) |

## Before a public release

- Create the Fate+ products in App Store Connect and paste a TelemetryDeck App ID into `Analytics.appID`.
- Add links to your Terms of Use (EULA) and Privacy Policy on the paywall and in the App Store description: Apple requires them for subscriptions.

- Deploy the server over HTTPS and point the app at it.
- Add real user accounts or App Attest if you need stronger protection than per-device limits.
- Replace the 200 px portraits with full-resolution exports, add an app icon, and set your own bundle identifier and team.

## Card artwork

The tarot card faces are Pamela Colman Smith's illustrations for the Rider-Waite-Smith deck (1910), which are in the public domain. All 78 scans come from Wikimedia Commons (`RWS Tarot 00 Fool.jpg` and the other major arcana, `Cups01.jpg` to `Cups14.jpg`, and the same for `Wands`, `Swords` and `Pents`), resized to 480 pixels wide in `AsFate/Assets.xcassets/tarot_*.imageset`. A card without a scan falls back to the art drawn in `TarotArt.swift`.
