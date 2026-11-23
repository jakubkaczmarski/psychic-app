# Psychic documents

Each folder here is one psychic. The folder name is the id the app sends (`selene`, `kaz`, `ivy`, `zephyr`, `mirela`).
The server reads these files when it starts and builds the psychic's instructions from them. `npm run dev`
restarts when a file changes; in production, restart the server.

Folders starting with `_` or `.` are ignored, so `_drafts/` is a safe place for work in progress.

## `persona.md` (required)

A `# Name` title, then these `##` sections, all required:

| Section | What goes in it |
| --- | --- |
| Specialty | One line, e.g. "Love & relationships" |
| Backstory | Who they are and where they come from |
| Voice | How they sound: rhythm, vocabulary, attitude, what they call people |
| Texting | How they text: number of messages, length, punctuation, typos |
| Catchphrases | A `- ` list, used sparingly |
| Never | A `- ` list of things they never do |
| Quirks | Habits that show up in readings |
| Others | What they think of the other psychics |
| Ritual | How they read the result of their ritual button in the app |

## `examples.md` (required)

Each `## ` heading is something a user says; the text under it is the psychic's reply. Blank lines in a
reply become separate chat bubbles. More examples is the best way to sharpen a voice, but vary them:
the psychic is told to match the voice, never copy the lines.

## Any other `.md` file (optional)

Every other markdown file becomes a background note: lore, beliefs, places, people in their life, how they
read particular cards or signs. The `# Title` names the note (or the file name, if there's no title).
Notes are added in file-name order, so prefix them (`01-family.md`) if order matters.

The psychic is told to draw on notes naturally and never recite them. Write them as facts about the
character, not as instructions: "Her grandmother Lela read cards at every wedding" works better than
"Always mention Lela".

## Size and cost

Everything in a folder is sent with every reading, so it's prompt-cached: after the first reading, the
cached part costs a twentieth of the normal input price, as long as that psychic gets a reading at least
every 5 minutes. Tens of pages per psychic is fine. If a psychic ever needs a whole book, it should be
searched rather than sent every time.
