// Psychic Studio web interface. Plain modules, no build step.
// Everything saves automatically a moment after you stop typing.

const $ = (id) => document.getElementById(id);

/** Creates an element. attrs: properties, "on*" handlers, or aria-/data- attributes. */
function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === undefined || value === null || value === false) continue;
    if (key.startsWith("on")) el.addEventListener(key.slice(2), value);
    else if (key.startsWith("aria-") || key.startsWith("data-") || key === "for" || key === "role") el.setAttribute(key, value);
    else el[key] = value;
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    el.append(child instanceof Node ? child : document.createTextNode(String(child)));
  }
  return el;
}

class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function api(method, path, body) {
  const res = await fetch(path, {
    method,
    headers: method !== "GET" ? { "content-type": "application/json" } : {},
    body: method !== "GET" ? JSON.stringify(body ?? {}) : undefined,
  });
  const data = await res.json().catch(() => ({}));
  if (res.status === 401 && path !== "/api/login") {
    showLogin();
    throw new ApiError(401, "Signed out.");
  }
  if (!res.ok) throw new ApiError(res.status, data.message || `Request failed (${res.status}).`);
  return data;
}

let toastTimer;
function toast(message) {
  const el = $("toast");
  el.textContent = message;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 2600);
}

/** Text boxes grow with their content, so there's no scrolling inside them. */
function autoGrow(el) {
  el.style.height = "auto";
  el.style.height = `${el.scrollHeight + 2}px`;
}
document.addEventListener("input", (e) => {
  if (e.target instanceof HTMLTextAreaElement) autoGrow(e.target);
});
const growAll = () => document.querySelectorAll("#editor textarea").forEach(autoGrow);
window.addEventListener("resize", growAll);

// ---------- State ----------
const state = {
  list: [],
  psychic: null,
  tab: "persona",
  examples: [],
  openDocId: null,
  /** Cards in each deck, from the server: { tarot: { name, reversals, groups: [{ name, cards }] }, playing: … } */
  decks: null,
  /** Card whose meaning is open in the Deck tab. */
  openCard: null,
  /** Deck tab shows only cards with their own meaning. */
  onlyOwn: false,
  /** The studio can write with Claude (it has an API key). */
  claude: false,
};

const FIELDS = [
  { key: "name", label: "Name", input: true, placeholder: "e.g. Madame Selene" },
  { key: "specialty", label: "Specialty", input: true, hint: "One line, shown in the app.", placeholder: "e.g. Love & relationships" },
  { key: "backstory", label: "Backstory", hint: "Who they are and where they come from.", placeholder: "e.g. A third-generation moon reader from a seaside town she will not name…" },
  { key: "voice", label: "Voice", hint: "How they sound: rhythm, vocabulary, attitude, what they call people.", placeholder: "e.g. Slow, lyrical and romantic. Calls people 'dear one'." },
  { key: "texting", label: "Texting style", hint: "How many messages, how long, punctuation, capitals, typos.", placeholder: "e.g. Usually 2 messages, each one or two flowing sentences." },
  { key: "catchphrases", label: "Catchphrases", list: true, hint: "One per line. Used now and then, never twice in a row.", placeholder: "e.g. The tide always turns, dear one." },
  { key: "never", label: "Never", list: true, hint: "One per line: things this character never says or does.", placeholder: "e.g. slang\nharsh verdicts" },
  { key: "quirks", label: "Quirks", hint: "Habits that show up in readings.", placeholder: "e.g. Mentions the moon whenever she can." },
  { key: "others", label: "The other psychics", hint: "What they think of the rest of the cast.", placeholder: "e.g. Finds Kaz terribly loud but annoyingly right." },
  { key: "ritual", label: "Ritual", hint: "How they read the result of their ritual button in the app.", placeholder: "e.g. Names tonight's moon phase and lets it set the mood." },
  { key: "howIRead", label: "How I read cards", optional: true,
    hint: "Optional. Their method with a spread: do they ask a question before drawing, how much they hedge, do they name the card or hint at it first, how they handle a hard card like the Tower while staying kind.",
    placeholder: "e.g. Hints at the picture before naming the card. Asks how it feels before turning the next one. The Tower is weather, never fate." },
];

// Where each missing part gets filled in, for the to-do list.
const PART = Object.fromEntries(FIELDS.map((f) => [f.key, { label: f.label, tab: "persona", focus: `f-${f.key}` }]));
PART.examples = { label: "An example reply", tab: "examples", focus: "ex-u-0" };
const ORDER = [...FIELDS.map((f) => f.key), "examples"];

// ---------- Autosave ----------
const saver = { timer: null, fn: null, pending: false, running: null, error: null };

function showSaveState(kind, message) {
  const el = $("save-state");
  if (!el) return;
  el.dataset.kind = kind;
  el.textContent =
    kind === "saving" ? "Saving…" : kind === "error" ? `Not saved: ${message}` : kind === "waiting" ? "Editing…" : "All changes saved";
}

/** Queues fn to run shortly after the last edit. */
function scheduleSave(fn, delay = 700) {
  saver.fn = fn;
  saver.pending = true;
  showSaveState("waiting");
  clearTimeout(saver.timer);
  saver.timer = setTimeout(flushSave, delay);
}

/** Runs any queued save now. Resolves to false if it failed. */
async function flushSave() {
  clearTimeout(saver.timer);
  if (saver.running) await saver.running;
  if (!saver.pending) return !saver.error;
  const fn = saver.fn;
  saver.pending = false;
  showSaveState("saving");
  saver.running = (async () => {
    try {
      await fn();
      saver.error = null;
      if (!saver.pending) showSaveState("saved");
    } catch (err) {
      saver.error = err.message;
      saver.pending = true;
      saver.fn = fn;
      showSaveState("error", err.message);
    }
  })();
  await saver.running;
  saver.running = null;
  return !saver.error;
}

async function canLeave() {
  if (await flushSave()) return true;
  return confirm(`Your last change wasn't saved (${saver.error}). Leave anyway and lose it?`);
}

function forgetUnsaved() {
  clearTimeout(saver.timer);
  Object.assign(saver, { pending: false, fn: null, error: null });
}

window.addEventListener("beforeunload", (e) => {
  if (saver.pending || saver.running) {
    flushSave();
    e.preventDefault();
  }
});

/** Takes the saved psychic from the server and refreshes everything except the open form. */
async function applySaved(psychic) {
  if (state.psychic?.id !== psychic.id) return;
  state.psychic = psychic;
  renderHeader();
  renderTabs();
  await refreshList();
}

// ---------- Sign in ----------
function showLogin() {
  $("app").hidden = true;
  $("login").hidden = false;
  $("password").value = "";
  $("password").focus();
}

$("login-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  $("login-error").textContent = "";
  try {
    await api("POST", "/api/login", { password: $("password").value });
    await start();
  } catch (err) {
    $("login-error").textContent = err.message;
  }
});

$("sign-out").addEventListener("click", async () => {
  if (!(await canLeave())) return;
  forgetUnsaved();
  await api("POST", "/api/logout");
  showLogin();
});

// ---------- Routing: #/<id>/<tab> ----------
function go(id, tab = "persona") {
  location.hash = `#/${id}/${tab}`;
}

let currentHash = location.hash;
window.addEventListener("hashchange", async () => {
  if (location.hash === currentHash) return;
  const target = location.hash;
  if (!(await canLeave())) {
    history.replaceState(null, "", currentHash);
    return;
  }
  forgetUnsaved();
  currentHash = target;
  route();
});

async function route() {
  currentHash = location.hash;
  const [, id, tab, focus] = location.hash.split("/");
  if (id === "new") {
    // The first step of the guided setup, before the psychic exists.
    state.psychic = null;
    state.tab = "create";
    state.wizardStep = "idea";
    renderSidebar();
    return renderWizard();
  }
  if (!id) {
    if (state.list.length) return go(state.list[0].id);
    return renderEmpty();
  }
  state.tab = ["persona", "app", "examples", "deck", "documents", "history", "create"].includes(tab) ? tab : "persona";
  if (state.tab === "create") state.wizardStep = WIZARD.some((w) => w.key === focus) ? focus : "sources";
  if (!state.psychic || state.psychic.id !== id) {
    try {
      state.psychic = (await api("GET", `/api/psychics/${encodeURIComponent(id)}`)).psychic;
    } catch (err) {
      if (err.status === 404 && state.list.length) return go(state.list[0].id);
      throw err;
    }
    state.openDocId = null;
    state.openCard = null;
  }
  state.examples = state.psychic.examples.map((e) => ({ ...e }));
  if (!state.examples.length) state.examples.push({ user: "", reply: "" });
  renderSidebar();
  renderEditor();
  if (focus && state.tab !== "create") document.getElementById(decodeURIComponent(focus))?.focus();
}

// ---------- Sidebar ----------
async function refreshList() {
  state.list = (await api("GET", "/api/psychics")).psychics;
  renderSidebar();
}

function renderSidebar() {
  const current = state.psychic?.id;
  $("psychic-list").replaceChildren(
    ...state.list.map((p) =>
      h("li", {},
        h("a", { href: `#/${p.id}/persona`, "aria-current": p.id === current ? "page" : null },
          h("span", { className: "avatar-wrap" },
            avatar(p, "small"),
            h("span", { className: p.missing.length ? "dot draft" : "dot", title: p.missing.length ? "Not live yet" : "Live in readings" })),
          h("span", { className: "name" }, p.name || p.id),
          h("span", { className: "meta" },
            p.missing.length ? "Not live yet" : !p.builtIn && !p.inApp ? "Live, not in the app yet" : p.specialty),
        ),
      ),
    ),
  );
  // On phones the list is a swipeable row: keep the current psychic in view.
  $("psychic-list").querySelector('[aria-current="page"]')?.scrollIntoView({ block: "nearest", inline: "nearest" });
}

// ---------- Editor ----------
function renderEmpty() {
  $("editor").replaceChildren(
    h("div", { className: "editor-inner" },
      h("div", { className: "character" }, h("h1", {}, "No psychics yet")),
      h("p", { className: "empty" }, "Create the first psychic to start writing their character."),
      h("button", { className: "primary", onclick: () => (location.hash = "#/new") }, "Make your first psychic"),
    ),
  );
}

function approxTokens(p) {
  const chars = JSON.stringify(p.published).length;
  return Math.round(chars / 4 / 50) * 50 || 50;
}

function renderEditor() {
  if (state.tab === "create") return renderWizard();
  $("editor").replaceChildren(
    h("div", { className: "editor-inner" },
      h("header", { id: "character", className: "character" }),
      h("div", { className: "tabbar" },
        h("nav", { id: "tabs", className: "tabs", "aria-label": "Sections" }),
        h("span", { id: "save-state", className: "save-state", role: "status", "data-kind": "saved" }, "All changes saved"),
      ),
      h("div", { id: "tab-body" },
        state.tab === "examples" ? examplesView()
          : state.tab === "app" ? appView()
          : state.tab === "deck" ? deckView()
          : state.tab === "documents" ? documentsView()
          : state.tab === "history" ? historyView()
          : personaView()),
    ),
  );
  renderHeader();
  renderTabs();
  growAll();
}

function renderHeader() {
  const p = state.psychic;
  const el = $("character");
  if (!el) return;
  const live = !p.missing.length;
  const unfinished = p.missing.length || (!p.builtIn && !p.inApp);
  el.replaceChildren(...[
    claudeButton(),
    unfinished ? h("a", { className: "setup-link", href: `#/${p.id}/create/${p.missing.length ? "sources" : "live"}` }, "Continue guided setup →") : null,
    h("div", { className: "identity" },
      photoPicker(p),
      h("div", {},
        h("h1", {}, p.name || p.id),
        h("div", { className: "specialty" }, p.specialty || "No specialty yet"),
        p.catchphrases[0] ? h("blockquote", {}, `“${p.catchphrases[0]}”`) : null,
      ),
    ),
    live
      ? h("div", { className: "status" },
          h("span", { className: "dot" }),
          h("span", {}, `Live in readings. Changes reach readings within a minute. About ${approxTokens(p).toLocaleString("en")} tokens of character per reading.`))
      : h("div", { className: "todo" },
          h("div", { className: "status" },
            h("span", { className: "dot draft" }),
            h("span", {}, `Not live yet. Fill in ${p.missing.length === 1 ? "this" : `these ${p.missing.length}`} and ${p.name || "this psychic"} goes live:`)),
          h("ul", {},
            [...p.missing].sort((a, b) => ORDER.indexOf(a) - ORDER.indexOf(b)).map((m) => {
              const part = PART[m] ?? { label: m, tab: "persona" };
              return h("li", {}, h("a", { href: `#/${p.id}/${part.tab}/${part.focus ?? ""}`, onclick: (e) => jumpTo(e, part) }, part.label));
            })),
        ),
  ].filter(Boolean));
}

async function jumpTo(e, part) {
  e.preventDefault();
  if (state.tab !== part.tab) {
    if (!(await canLeave())) return;
    forgetUnsaved();
    state.tab = part.tab;
    history.replaceState(null, "", `#/${state.psychic.id}/${part.tab}`);
    currentHash = location.hash;
    renderEditor();
  }
  const target = document.getElementById(part.focus);
  target?.scrollIntoView({ block: "center", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  target?.focus({ preventScroll: true });
}

function renderTabs() {
  const p = state.psychic;
  const el = $("tabs");
  if (!el) return;
  const complete = p.examples.filter((e) => e.user && e.reply).length;
  const tab = (key, label, count) =>
    h("a", { href: `#/${p.id}/${key}`, "aria-current": state.tab === key ? "page" : null },
      label, count !== undefined ? h("span", { className: "count" }, count) : null);
  el.replaceChildren(
    tab("persona", "Persona"),
    tab("app", "In the app"),
    tab("examples", "Examples", complete),
    tab("deck", "Deck", p.cardMeanings.length),
    tab("documents", "Documents", p.documents.filter((d) => d.enabled).length),
    tab("history", "History"),
  );
}

// ---------- Photos ----------
const initials = (name) => (name || "?").replace(/^(madame|grandma|grandpa|oracle|auntie|aunt|uncle|the)\s+/i, "").trim().slice(0, 1).toUpperCase();

function avatar(p, size) {
  return p.photoId
    ? h("img", { className: `avatar ${size}`, src: `/api/photos/${p.photoId}`, alt: "" })
    : h("span", { className: `avatar ${size} empty`, "aria-hidden": "true" }, initials(p.name || p.id));
}

/** Crops to a square from the centre and shrinks to at most 800 px, so photos stay small. */
async function preparePhoto(file) {
  const bitmap = await createImageBitmap(file);
  const side = Math.min(bitmap.width, bitmap.height);
  const out = Math.min(800, side);
  const canvas = document.createElement("canvas");
  canvas.width = canvas.height = out;
  canvas.getContext("2d").drawImage(bitmap, (bitmap.width - side) / 2, (bitmap.height - side) / 2, side, side, 0, 0, out, out);
  const type = file.type === "image/png" ? "image/png" : "image/jpeg";
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, type, 0.9));
  const bytes = new Uint8Array(await blob.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(binary);
}

async function uploadPhoto(file) {
  if (!file) return;
  if (!/^image\/(png|jpeg|webp|heic|heif|gif)$/.test(file.type)) return toast("Choose a PNG, JPEG or WebP image.");
  const p = state.psychic;
  try {
    toast("Uploading photo…");
    const data = await preparePhoto(file);
    const { psychic } = await api("PUT", `/api/psychics/${p.id}/photo`, { data });
    await applySaved(psychic);
    toast("Photo saved");
  } catch (err) {
    toast(err.message || "That image couldn't be read. Try a PNG or JPEG.");
  }
}

function photoPicker(p) {
  const input = h("input", {
    type: "file", accept: "image/png,image/jpeg,image/webp", hidden: true,
    onchange: (e) => { const f = e.target.files[0]; e.target.value = ""; uploadPhoto(f); },
  });
  const frame = h("button", {
    className: "photo", type: "button",
    title: p.photoId ? "Change photo" : "Add a photo",
    "aria-label": p.photoId ? `Change ${p.name}'s photo` : `Add a photo of ${p.name}`,
    onclick: () => input.click(),
    ondragover: (e) => { e.preventDefault(); frame.classList.add("over"); },
    ondragleave: () => frame.classList.remove("over"),
    ondrop: (e) => { e.preventDefault(); frame.classList.remove("over"); uploadPhoto(e.dataTransfer.files[0]); },
  },
    avatar(p, "large"),
    h("span", { className: "photo-label" }, p.photoId ? "Change" : "Add photo"),
  );
  const remove = p.photoId
    ? h("button", {
        className: "link small remove-photo", type: "button",
        onclick: async () => {
          try {
            const { psychic } = await api("DELETE", `/api/psychics/${p.id}/photo`);
            await applySaved(psychic);
            undoToast("Photo removed", async () => {
              const history = (await api("GET", `/api/psychics/${p.id}/history`)).history;
              const before = history[1];
              if (!before) return;
              const { psychic: back } = await api("POST", `/api/versions/${before.id}/restore`);
              await applySaved(back);
              toast("Photo back");
            });
          } catch (err) {
            toast(err.message);
          }
        },
      }, "Remove photo")
    : null;
  return h("div", { className: "photo-col" }, frame, input, remove);
}

// ---------- Persona ----------
function personaView() {
  const p = state.psychic;
  const form = h("form", { className: "fields", onsubmit: (e) => e.preventDefault() });

  for (const f of FIELDS) {
    const id = `f-${f.key}`;
    const value = f.list ? p[f.key].join("\n") : p[f.key];
    const field = h("div", { className: "field" }, h("label", { for: id }, f.label, f.optional ? h("span", { className: "optional" }, " optional") : null));
    if (f.hint) field.append(h("p", { className: "hint" }, f.hint));
    field.append(
      f.input
        ? h("input", { id, name: f.key, value, maxLength: 10000, placeholder: f.placeholder })
        : h("textarea", { id, name: f.key, value, rows: 2, placeholder: f.placeholder }),
    );
    form.append(field);
  }

  const save = async () => {
    const data = new FormData(form);
    const body = {};
    for (const f of FIELDS) {
      const v = String(data.get(f.key) ?? "");
      body[f.key] = f.list ? v.split("\n").map((s) => s.trim()).filter(Boolean) : v;
    }
    const { psychic } = await api("PUT", `/api/psychics/${p.id}`, body);
    await applySaved(psychic);
  };
  form.addEventListener("input", () => scheduleSave(save));

  const dangerZone = h("section", { className: "danger-zone" },
    h("h3", {}, "Delete psychic"),
    h("p", {}, `Removes ${p.name || p.id} with their examples and documents. Readings with this psychic stop working within a minute.`),
    h("button", {
      className: "danger", type: "button",
      onclick: async () => {
        const typed = prompt(`To delete ${p.name || p.id} for good, type their id: ${p.id}`);
        if (typed?.trim() !== p.id) return;
        forgetUnsaved();
        await api("DELETE", `/api/psychics/${p.id}`);
        state.psychic = null;
        await refreshList();
        toast("Psychic deleted");
        location.hash = "";
      },
    }, "Delete psychic"),
  );

  return h("div", {}, form, dangerZone);
}

// ---------- Examples ----------
function examplesView() {
  const p = state.psychic;
  const list = h("div", { className: "examples" });

  const save = async () => {
    const { psychic } = await api("PUT", `/api/psychics/${p.id}/examples`, { examples: state.examples });
    await applySaved(psychic);
  };

  const draw = (focusId) => {
    list.replaceChildren(
      ...state.examples.map((ex, i) => {
        const warn = h("p", { className: "hint warn" }, "Not used until both parts are filled in.");
        const check = () => (warn.hidden = (ex.user.trim() === "") === (ex.reply.trim() === ""));
        check();
        return h("div", { className: "example" },
          h("label", { for: `ex-u-${i}` }, "Someone asks"),
          h("input", {
            id: `ex-u-${i}`, value: ex.user, placeholder: "Should I text my ex?",
            oninput: (e) => { ex.user = e.target.value; check(); scheduleSave(save); },
          }),
          h("label", { for: `ex-r-${i}` }, `${p.name || "The psychic"} replies`),
          h("textarea", {
            id: `ex-r-${i}`, value: ex.reply, rows: 3,
            placeholder: "Oh, darling.\n\nThe moon is waning tonight…",
            oninput: (e) => { ex.reply = e.target.value; check(); scheduleSave(save); },
          }),
          warn,
          h("div", { className: "row" },
            h("button", { className: "ghost small", type: "button", disabled: i === 0, "aria-label": `Move example ${i + 1} up`, onclick: () => move(i, -1) }, "↑ Up"),
            h("button", { className: "ghost small", type: "button", disabled: i === state.examples.length - 1, "aria-label": `Move example ${i + 1} down`, onclick: () => move(i, 1) }, "↓ Down"),
            h("span", { className: "spacer" }),
            h("button", {
              className: "danger small", type: "button",
              onclick: () => {
                const [removed] = state.examples.splice(i, 1);
                if (!state.examples.length) state.examples.push({ user: "", reply: "" });
                draw();
                scheduleSave(save, 0);
                if (removed.user || removed.reply) undoToast("Example removed", () => {
                  state.examples.splice(i, 0, removed);
                  draw();
                  scheduleSave(save, 0);
                });
              },
            }, "Remove"),
          ),
        );
      }),
    );
    list.querySelectorAll("textarea").forEach(autoGrow);
    if (focusId) document.getElementById(focusId)?.focus();
  };
  const move = (i, by) => {
    const [ex] = state.examples.splice(i, 1);
    state.examples.splice(i + by, 0, ex);
    draw();
    scheduleSave(save, 0);
  };
  draw();

  return h("div", {},
    h("p", { className: "hint intro" },
      "Short exchanges that show how this psychic texts. A blank line in a reply splits it into separate chat bubbles. The psychic copies the voice, never the exact words, so vary them."),
    list,
    h("button", {
      className: "ghost add", type: "button",
      onclick: () => {
        state.examples.push({ user: "", reply: "" });
        draw(`ex-u-${state.examples.length - 1}`);
      },
    }, "+ Add another example"),
  );
}

// ---------- Deck ----------
async function loadDecks() {
  if (!state.decks) state.decks = (await api("GET", "/api/decks")).decks;
  return state.decks;
}

function deckView() {
  const p = state.psychic;
  const wrap = h("div", {}, h("p", { className: "empty" }, "Loading…"));
  loadDecks().then(() => drawDeck(wrap)).catch((err) => wrap.replaceChildren(h("p", { className: "empty" }, err.message)));
  return wrap;
}

function drawDeck(wrap) {
  const p = state.psychic;
  const deck = state.decks[p.deck] ?? state.decks.tarot;
  // Edits go into this copy, keyed by card name, and are saved as a whole.
  const meanings = new Map(p.cardMeanings.map((m) => [m.card, { ...m }]));
  const hasOwn = (m) => m && (m.upright.trim() || m.reversed.trim() || m.memory.trim());

  const save = async () => {
    const cardMeanings = [...meanings.values()].filter(hasOwn);
    const { psychic } = await api("PUT", `/api/psychics/${p.id}/deck`, { deck: p.deck, cardMeanings });
    // Keep the open editor; only refresh counts and the header.
    state.psychic = { ...psychic };
    renderHeader();
    renderTabs();
    await refreshList();
  };

  const chooseDeck = async (id) => {
    if (id === p.deck) return;
    const own = [...meanings.values()].filter(hasOwn).length;
    if (own && !confirm(`Switch ${p.name || "this psychic"} to ${state.decks[id].name.toLowerCase()}? Their ${own} card meaning${own === 1 ? "" : "s"} for ${deck.name.toLowerCase()} will be removed (you can get them back from History).`)) {
      return drawDeck(wrap);
    }
    if (!(await flushSave())) return;
    try {
      const { psychic } = await api("PUT", `/api/psychics/${p.id}/deck`, { deck: id, cardMeanings: [] });
      state.psychic = psychic;
      state.openCard = null;
      await refreshList();
      renderHeader();
      renderTabs();
      drawDeck(wrap);
    } catch (err) {
      toast(err.message);
    }
  };

  const picker = h("fieldset", { className: "deck-picker" },
    h("legend", {}, "Reads with"),
    ...Object.entries(state.decks).map(([id, d]) =>
      h("label", { className: "radio" },
        h("input", { type: "radio", name: "deck", value: id, checked: p.deck === id, onchange: () => chooseDeck(id) }),
        h("span", {}, d.name, h("span", { className: "hint inline" }, d.reversals ? " · cards can land reversed" : " · read upright only"))),
    ),
  );

  const summary = (m) => {
    if (!hasOwn(m)) return "Traditional meaning";
    return [m.upright && "upright", deck.reversals && m.reversed && "reversed", m.memory && "memory"].filter(Boolean).join(" · ");
  };

  const cardRow = (name) => {
    const m = meanings.get(name) ?? { card: name, upright: "", reversed: "", memory: "" };
    const open = state.openCard === name;
    const slug = name.toLowerCase().replace(/[^a-z0-9]+/g, "-");
    const note = h("span", { className: hasOwn(m) ? "size own" : "size" }, summary(m));
    const toggle = async () => {
      // Redrawing rebuilds the meanings from the saved psychic, so save first.
      if (!(await flushSave())) return;
      state.openCard = open ? null : name;
      drawDeck(wrap);
      if (!open) document.getElementById(`card-${slug}-upright`)?.focus();
    };
    const field = (key, label, hint, placeholder) => [
      h("label", { for: `card-${slug}-${key}` }, label),
      hint ? h("p", { className: "hint" }, hint) : null,
      h("textarea", {
        id: `card-${slug}-${key}`, value: m[key], rows: 2, placeholder,
        oninput: (e) => {
          m[key] = e.target.value;
          meanings.set(name, m);
          note.textContent = summary(m);
          note.className = hasOwn(m) ? "size own" : "size";
          scheduleSave(save);
        },
      }),
    ];
    return h("li", { className: open ? "open" : null },
      h("div", { className: "doc-row" },
        h("button", { className: "title", type: "button", "aria-expanded": String(open), onclick: toggle }, name),
        note),
      open
        ? h("div", { className: "doc-edit" },
            ...field("upright", deck.reversals ? "Upright" : "Their meaning", "Leave a box empty to use the traditional meaning.", "What this card means when they read it"),
            ...(deck.reversals ? field("reversed", "Reversed", null, "What it means when it lands upside down") : []),
            ...field("memory", "A memory", "Optional. Something in their life this card is tied to. They bring it up now and then, not every time.", "e.g. It turned up the week my cousin eloped."),
            h("div", { className: "row" },
              h("button", { className: "ghost", type: "button", onclick: toggle }, "Done"),
              h("span", { className: "spacer" }),
              state.claude
                ? h("button", {
                    className: "ghost claude", type: "button",
                    onclick: (e) => draftCard(name, e.currentTarget),
                  }, hasOwn(m) ? "✦ Rewrite with Claude" : "✦ Write with Claude")
                : null,
            ),
          )
        : null,
    );
  };

  const filter = h("label", { className: "switch" },
    h("input", { type: "checkbox", role: "switch", checked: state.onlyOwn, onchange: async (e) => { state.onlyOwn = e.target.checked; await flushSave(); drawDeck(wrap); } }),
    h("span", {}, "Only cards with their own meaning"));

  const groups = deck.groups
    .map((g) => ({ ...g, cards: state.onlyOwn ? g.cards.filter((c) => hasOwn(meanings.get(c))) : g.cards }))
    .filter((g) => g.cards.length);

  wrap.replaceChildren(
    h("p", { className: "hint intro" },
      "The app draws real cards and tells the psychic what came up, with each card's traditional meaning. Give a card their own meaning and they read it their way instead: that's where a reader's personality shows. A handful of favourite or feared cards goes a long way."),
    picker,
    h("div", { className: "row deck-tools" }, filter),
    ...(groups.length
      ? groups.map((g) => h("section", { className: "card-group" }, h("h3", {}, g.name), h("ul", { className: "docs" }, g.cards.map(cardRow))))
      : [h("p", { className: "empty" }, `${p.name || "This psychic"} reads every card the traditional way so far. Switch the filter off and open a card to give it their own meaning.`)]),
  );
  wrap.querySelectorAll("textarea").forEach(autoGrow);
}

// ---------- Writing with Claude ----------
// Claude reads everything written about the psychic (fields, documents, examples, card meanings) and writes
// what's asked for. The result is saved as one version, so it can be undone here or from History.

function claudeButton() {
  return h("button", {
    className: "ghost claude header-claude", type: "button",
    disabled: !state.claude,
    title: state.claude ? "Claude reads everything written so far and drafts more" : "Add ANTHROPIC_API_KEY to the studio's settings to write with Claude",
    onclick: () => openClaudeDialog(),
  }, "✦ Write with Claude");
}

/** What the dialog offers first, from the tab you're on and what's still missing. */
function claudePreset() {
  const p = state.psychic;
  const missing = new Set(p.missing);
  const personaEmpty = [...FIELDS.map((f) => f.key)].some((k) => (Array.isArray(p[k]) ? !p[k].length : !String(p[k] ?? "").trim()));
  const appEmpty = !p.builtIn && p.appMissing.length ? "empty" : "";
  if (missing.size) {
    return { persona: personaEmpty ? "empty" : "", app: appEmpty, examples: missing.has("examples") ? 6 : 0, cards: p.cardMeanings.length ? 0 : 8, document: "" };
  }
  const none = { persona: "", app: "", examples: 0, cards: 0, document: "" };
  switch (state.tab) {
    case "app": return { ...none, app: appEmpty || "all" };
    case "examples": return { ...none, examples: 6 };
    case "deck": return { ...none, cards: 8 };
    case "documents": return { ...none, document: "Their family and the people in their life" };
    default: return { ...none, persona: personaEmpty ? "empty" : "all", app: appEmpty };
  }
}

async function runClaude(body) {
  const p = state.psychic;
  if (!(await flushSave())) throw new Error("Your last change isn't saved yet. Fix that first.");
  return api("POST", `/api/psychics/${p.id}/claude`, body);
}

async function showClaudeResult({ psychic, summary, undoVersionId }) {
  state.psychic = psychic;
  state.examples = psychic.examples.map((e) => ({ ...e }));
  if (!state.examples.length) state.examples.push({ user: "", reply: "" });
  await refreshList();
  renderEditor();
  const undo = undoVersionId
    ? async () => {
        const { psychic: back } = await api("POST", `/api/versions/${undoVersionId}/restore`);
        state.psychic = back;
        state.examples = back.examples.map((e) => ({ ...e }));
        await refreshList();
        renderEditor();
        toast("Undone");
      }
    : null;
  if (undo) undoToast(`Claude wrote ${summary}`, undo);
  else toast(`Claude wrote ${summary}`);
}

async function draftCard(name, button) {
  button.disabled = true;
  button.textContent = "Writing…";
  try {
    const result = await runClaude({ cards: { names: [name] } });
    state.openCard = name;
    await showClaudeResult(result);
  } catch (err) {
    toast(err.message);
    button.disabled = false;
    button.textContent = "✦ Write with Claude";
  }
}

function openClaudeDialog() {
  const p = state.psychic;
  const preset = claudePreset();
  const deckName = p.deck === "playing" ? "playing cards" : "tarot cards";
  const dialog = h("dialog", { className: "claude-dialog", "aria-labelledby": "claude-title" });
  const status = h("p", { className: "hint claude-status", role: "status" });
  const error = h("p", { className: "error", role: "alert" });

  const option = (id, checked, label, extra) =>
    h("div", { className: "claude-option" },
      h("label", { className: "check" }, h("input", { type: "checkbox", id, checked }), h("span", {}, label)),
      extra);
  const select = (id, values, selected) =>
    h("select", { id }, values.map(([v, t]) => h("option", { value: v, selected: String(v) === String(selected) }, t)));

  const form = h("form", { method: "dialog" },
    h("h2", { id: "claude-title" }, `Write with Claude`),
    h("p", { className: "hint" },
      `Claude reads everything written about ${p.name || "this psychic"} so far, ${p.documents.length === 0 ? "(add documents first for the best results)" : p.documents.length === 1 ? "including its document" : `including all ${p.documents.length} documents`}, and writes in the same voice. What it writes is saved as one version: undo it right after, or from History.`),
    option("cl-persona", Boolean(preset.persona), "Persona fields",
      select("cl-persona-mode", [["empty", "Fill the empty ones"], ["all", "Rewrite all of them"]], preset.persona || "empty")),
    option("cl-app", Boolean(preset.app), "What the app shows",
      select("cl-app-mode", [["empty", "Fill the empty fields"], ["all", "Rewrite all of it"]], preset.app || "empty")),
    option("cl-examples", Boolean(preset.examples), "Example replies",
      select("cl-examples-count", [[3, "3 more"], [6, "6 more"], [10, "10 more"]], preset.examples || 6)),
    option("cl-cards", Boolean(preset.cards), `Their own meaning for ${deckName}`,
      select("cl-cards-count", [[4, "4 cards"], [8, "8 cards"], [12, "12 cards"]], preset.cards || 8)),
    option("cl-doc", Boolean(preset.document), "A background document about",
      h("input", { id: "cl-doc-topic", value: preset.document, placeholder: "e.g. Her shop, her rivals, her first reading", maxLength: 300 })),
    h("label", { for: "cl-notes" }, "Notes for Claude ", h("span", { className: "optional" }, "optional")),
    h("textarea", { id: "cl-notes", rows: 3, placeholder: "e.g. Make her drier and funnier. She grew up in Naples and still runs her mother's bakery." }),
    status,
    error,
    h("div", { className: "row end" },
      h("button", { type: "button", className: "ghost", id: "cl-cancel", onclick: () => dialog.close() }, "Cancel"),
      h("button", { type: "submit", className: "primary", id: "cl-go" }, "Write it"),
    ),
  );
  dialog.append(form);
  document.body.append(dialog);
  dialog.addEventListener("close", () => dialog.remove());
  // Typing a topic ticks its box.
  form.querySelector("#cl-doc-topic").addEventListener("input", (e) => (form.querySelector("#cl-doc").checked = Boolean(e.target.value.trim())));

  let busy = false;
  dialog.addEventListener("cancel", (e) => { if (busy) e.preventDefault(); });
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const val = (id) => form.querySelector(`#${id}`);
    const body = {
      persona: val("cl-persona").checked ? val("cl-persona-mode").value : undefined,
      app: val("cl-app").checked ? val("cl-app-mode").value : undefined,
      examples: val("cl-examples").checked ? Number(val("cl-examples-count").value) : undefined,
      cards: val("cl-cards").checked ? { count: Number(val("cl-cards-count").value) } : undefined,
      document: val("cl-doc").checked ? val("cl-doc-topic").value.trim() : undefined,
      notes: val("cl-notes").value,
    };
    if (body.document === "") return (error.textContent = "Say what the document should be about.");
    if (!body.persona && !body.app && !body.examples && !body.cards && !body.document) return (error.textContent = "Tick at least one thing to write.");
    error.textContent = "";
    busy = true;
    form.querySelectorAll("input, select, textarea, button").forEach((el) => (el.disabled = true));
    const started = Date.now();
    const tick = () => (status.textContent = `Claude is writing… ${Math.round((Date.now() - started) / 1000)}s. This usually takes under a minute.`);
    tick();
    const timer = setInterval(tick, 1000);
    try {
      const result = await runClaude(body);
      busy = false;
      dialog.close();
      await showClaudeResult(result);
    } catch (err) {
      busy = false;
      error.textContent = err.message;
      status.textContent = "";
      form.querySelectorAll("input, select, textarea, button").forEach((el) => (el.disabled = false));
    } finally {
      clearInterval(timer);
    }
  });
  dialog.showModal();
}

// A short toast with an Undo button, for removals.
function undoToast(message, undo) {
  const el = $("toast");
  el.replaceChildren(message, " ", h("button", { className: "toast-action", type: "button", onclick: () => { el.hidden = true; undo(); } }, "Undo"));
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => (el.hidden = true), 6000);
}

// ---------- Documents ----------
function formatSize(chars) {
  const words = Math.max(0, Math.round(chars / 6));
  return words === 0 ? "Empty" : `${words.toLocaleString("en")} words`;
}

const titleFrom = (text, fallback) => text.match(/^# (.+)$/m)?.[1].trim() || fallback;

async function reloadPsychic() {
  const { psychic } = await api("GET", `/api/psychics/${state.psychic.id}`);
  state.psychic = psychic;
  await refreshList();
}

async function addFiles(files) {
  const usable = [...files].filter((f) => /\.(md|markdown|txt)$/i.test(f.name) || f.type.startsWith("text/"));
  if (!usable.length) return toast("Only .md and .txt files can be added.");
  try {
    let lastId = null;
    for (const file of usable) {
      const text = await file.text();
      const { document: doc } = await api("POST", `/api/psychics/${state.psychic.id}/documents`, {
        title: titleFrom(text, file.name.replace(/\.(md|markdown|txt)$/i, "")),
        body: text.replace(/^# .+$/m, "").trim(),
      });
      lastId = doc.id;
    }
    await reloadPsychic();
    if (usable.length === 1) state.openDocId = lastId;
    renderEditor();
    toast(usable.length === 1 ? "Document added" : `${usable.length} documents added`);
  } catch (err) {
    toast(err.message);
  }
}

function documentsView() {
  const p = state.psychic;

  const toggleOpen = async (doc) => {
    if (!(await canLeave())) return;
    forgetUnsaved();
    state.openDocId = state.openDocId === doc.id ? null : doc.id;
    if (state.openDocId === null) await reloadPsychic();
    renderEditor();
    if (state.openDocId) document.getElementById("doc-body")?.focus();
  };

  const rows = p.documents.map((doc) => {
    const open = state.openDocId === doc.id;
    const draft = { title: doc.title, body: doc.body };
    const titleBtn = h("button", { className: "title", type: "button", "aria-expanded": String(open), onclick: () => toggleOpen(doc) }, doc.title || "Untitled");
    const size = h("span", { className: "size" }, formatSize(doc.body.length));

    const save = async () => {
      await api("PUT", `/api/documents/${doc.id}`, draft);
      doc.title = draft.title;
      doc.body = draft.body;
      renderHeader();
    };
    const edit = () => {
      titleBtn.textContent = draft.title || "Untitled";
      size.textContent = formatSize(draft.body.length);
      scheduleSave(save);
    };

    const row = h("div", { className: doc.enabled ? "doc-row" : "doc-row off" },
      titleBtn,
      size,
      h("label", { className: "switch", title: "When on, this document goes into every reading" },
        h("input", {
          type: "checkbox", checked: doc.enabled, role: "switch",
          onchange: async (e) => {
            try {
              await api("PUT", `/api/documents/${doc.id}`, { enabled: e.target.checked });
              doc.enabled = e.target.checked;
              row.classList.toggle("off", !doc.enabled);
              await reloadPsychic();
              renderHeader();
              renderTabs();
            } catch (err) {
              e.target.checked = !e.target.checked;
              toast(err.message);
            }
          },
        }),
        h("span", {}, "In readings"),
      ),
    );

    const editor = open
      ? h("div", { className: "doc-edit" },
          h("label", { for: "doc-title" }, "Title"),
          h("input", { id: "doc-title", value: draft.title, maxLength: 120, placeholder: "Family", oninput: (e) => { draft.title = e.target.value; edit(); } }),
          h("label", { for: "doc-body" }, "Text"),
          h("textarea", {
            id: "doc-body", value: draft.body, rows: 8,
            placeholder: "Her grandmother Lela read cards at every wedding and christening…",
            oninput: (e) => { draft.body = e.target.value; edit(); },
          }),
          h("div", { className: "row" },
            h("button", { className: "ghost", type: "button", onclick: () => toggleOpen(doc) }, "Done"),
            h("span", { className: "spacer" }),
            h("button", {
              className: "danger", type: "button",
              onclick: async () => {
                if (!confirm(`Delete "${draft.title || "Untitled"}"? This can't be undone.`)) return;
                forgetUnsaved();
                await api("DELETE", `/api/documents/${doc.id}`);
                state.openDocId = null;
                await reloadPsychic();
                renderEditor();
                toast("Document deleted");
              },
            }, "Delete document"),
          ),
        )
      : null;
    return h("li", { className: open ? "open" : null }, row, editor);
  });

  const upload = h("input", {
    type: "file", accept: ".md,.markdown,.txt,text/plain,text/markdown", multiple: true, hidden: true,
    onchange: (e) => {
      const files = [...e.target.files];
      e.target.value = "";
      addFiles(files);
    },
  });

  const newDoc = async () => {
    if (!(await canLeave())) return;
    forgetUnsaved();
    try {
      const { document: doc } = await api("POST", `/api/psychics/${p.id}/documents`, { title: "", body: "" });
      await reloadPsychic();
      state.openDocId = doc.id;
      renderEditor();
      $("doc-title")?.focus();
    } catch (err) {
      toast(err.message);
    }
  };

  const drop = h("div", {
    className: "dropzone",
    ondragover: (e) => { e.preventDefault(); drop.classList.add("over"); },
    ondragleave: () => drop.classList.remove("over"),
    ondrop: (e) => { e.preventDefault(); drop.classList.remove("over"); addFiles(e.dataTransfer.files); },
  },
    h("div", { className: "row" },
      h("button", { className: "primary", type: "button", onclick: newDoc }, "Write a document"),
      h("button", { className: "ghost", type: "button", onclick: () => upload.click() }, "Upload files"),
      upload,
    ),
    h("p", { className: "hint" }, "Or drop .md or .txt files here."),
  );

  return h("div", {},
    h("p", { className: "hint intro" },
      "Background for this character: their history, beliefs, the people in their life, how they read particular cards. Documents switched on go into every reading, and the psychic draws on them without reciting them. Write facts about the character, not instructions."),
    drop,
    p.documents.length
      ? h("ul", { className: "docs" }, rows)
      : h("p", { className: "empty" }, `${p.name || "This psychic"} has no documents yet.`),
  );
}

// ---------- History ----------
const parseTime = (t) => new Date(t.replace(" ", "T") + "Z");

function when(t) {
  const d = parseTime(t);
  const mins = Math.round((Date.now() - d) / 60000);
  if (mins < 1) return "Just now";
  if (mins < 60) return `${mins} min ago`;
  const time = d.toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
  const today = new Date();
  const yesterday = new Date(Date.now() - 86400000);
  if (d.toDateString() === today.toDateString()) return `Today at ${time}`;
  if (d.toDateString() === yesterday.toDateString()) return `Yesterday at ${time}`;
  return d.toLocaleDateString(undefined, { day: "numeric", month: "short", year: d.getFullYear() === today.getFullYear() ? undefined : "numeric" }) + ` at ${time}`;
}

function historyView() {
  const p = state.psychic;
  const list = h("ol", { className: "history" }, h("li", { className: "empty" }, "Loading…"));

  const goBack = async (version, currentId) => {
    if (!(await canLeave())) return;
    forgetUnsaved();
    try {
      const { psychic } = await api("POST", `/api/versions/${version.id}/restore`);
      state.psychic = psychic;
      state.examples = psychic.examples.map((e) => ({ ...e }));
      await refreshList();
      renderEditor();
      undoToast(`Went back to the version from ${when(version.savedAt).toLowerCase()}`, async () => {
        const { psychic: undone } = await api("POST", `/api/versions/${currentId}/restore`);
        state.psychic = undone;
        state.examples = undone.examples.map((e) => ({ ...e }));
        await refreshList();
        renderEditor();
        toast("Undone");
      });
    } catch (err) {
      toast(err.message);
    }
  };

  api("GET", `/api/psychics/${p.id}/history`).then(({ history }) => {
    const currentId = history.find((v) => v.current)?.id;
    list.replaceChildren(
      ...history.map((v) =>
        h("li", { className: v.current ? "version current" : "version" },
          h("div", { className: "when" }, when(v.savedAt)),
          h("div", { className: "what" },
            v.changes.length ? v.changes.map((c) => h("div", {}, c)) : h("div", {}, v.label)),
          v.current
            ? h("span", { className: "tag" }, "Current version")
            : h("button", { className: "ghost small", type: "button", onclick: () => goBack(v, currentId) }, "Go back to this"),
        ),
      ),
    );
  }).catch((err) => list.replaceChildren(h("li", { className: "empty" }, err.message)));

  return h("div", {},
    h("p", { className: "hint intro" },
      "Every change is kept here, newest first. Edits made within 10 minutes of each other are grouped into one version. Going back to an earlier version doesn't erase anything: it's added here too, so you can always undo it."),
    list,
  );
}

// ---------- In the app ----------
// What the iOS app shows: the home screen card, profile page, chat greeting and buttons.

const APP_SECTIONS = [
  { title: "Home screen", fields: [
    { key: "short", label: "Short name", input: true, hint: "Used in buttons and sentences, like “Start a reading with Selene”.", placeholder: "e.g. Selene" },
    { key: "tagline", label: "Tagline", input: true, required: true, hint: "One line under their name.", placeholder: "e.g. Reads the moon, and your texts." },
    { key: "moods", label: "Daily moods", list: true, hint: "One per line. The app shows one each day.", placeholder: "e.g. Baking for the whole street" },
    { key: "color", label: "Accent colour", color: true, hint: "The ring around their photo." },
  ] },
  { title: "Profile page", fields: [
    { key: "bio", label: "Bio", required: true, hint: "Two or three sentences about them, in the third person.", placeholder: "e.g. A third-generation moon reader from a seaside town that may or may not exist…" },
    { key: "tags", label: "Tags", list: true, hint: "Three short tags, one per line.", placeholder: "Tarot\nMoon phases\nGentle" },
    { key: "sample", label: "A taste of a reading", hint: "A sentence or two in their voice.", placeholder: "e.g. There's a message you've been meaning to send. Send it today." },
  ] },
  { title: "Chat", fields: [
    { key: "greeting", label: "Greeting", required: true, hint: "Their first message. {name} is replaced with the user's name.", placeholder: "e.g. Welcome, {name}. What weighs on your heart?" },
    { key: "asks", label: "Suggested questions", list: true, required: true, hint: "Tappable questions under the chat, one per line.", placeholder: "Does my crush like me back?\nShould I text my ex?" },
    { key: "signLine", label: "When they hear your star sign", hint: "{sign} is replaced.", placeholder: "e.g. Ah, a {sign}. I felt it before you said a word." },
    { key: "welcomeBack", label: "Welcome back", hint: "When someone returns after a while. {name} is replaced.", placeholder: "e.g. There you are, {name}." },
    { key: "defaultName", label: "What they call you without a name", input: true, placeholder: "e.g. love" },
    { key: "typing", label: "Typing speed", select: [["", "Medium (default)"], ["slow", "Slow"], ["medium", "Medium"], ["fast", "Fast"]] },
  ] },
  { title: "Cards and ritual", fields: [
    { key: "ritualButton", label: "Ritual button", input: true, hint: "Their main button in the chat. For new psychics it draws a card from their deck.", placeholder: "e.g. Cut the deck" },
    { key: "ritualIntro", label: "What they say during the ritual", placeholder: "e.g. Cut with your left hand, my dear. Now, let me turn one over…" },
    { key: "cardIntro", label: "Drawing one card", placeholder: "e.g. Let me turn one card for you…" },
    { key: "spreadIntro", label: "Laying out a spread", hint: "{n} is the number of cards, as a word.", placeholder: "e.g. {n} cards, face down. We turn them one by one." },
  ] },
  { title: "Morning messages", fields: [
    { key: "morningOpenings", label: "Openings", list: true, hint: "One per line. The morning notification starts with one of these.", placeholder: "Morning, love.\nKettle's on." },
  ] },
];
const APP_KEYS = APP_SECTIONS.flatMap((s) => s.fields.map((f) => f.key));
const APP_LABEL = Object.fromEntries(APP_SECTIONS.flatMap((s) => s.fields.map((f) => [f.key, f.label])));

const fill = (text, name = "Alex") => (text || "").replaceAll("{name}", name).replaceAll("{sign}", "Leo").replaceAll("{n}", "three");

/** A phone-shaped preview of the home card, profile and chat greeting. */
function phonePreview(p, app = p.app) {
  const color = app.color || "#8a6f4a";
  const short = app.short || (p.name || "").replace(/^(madame|grandma|grandpa|oracle|auntie|aunt|uncle|the)\s+/i, "") || "They";
  const mood = app.moods[0];
  const greeting = app.greeting ? fill(app.greeting) : "";
  return h("div", { className: "phone", "aria-label": "Preview of the app" },
    h("div", { className: "phone-card" },
      h("span", { className: "phone-avatar", style: `--ring:${color}` }, p.photoId ? h("img", { src: `/api/photos/${p.photoId}`, alt: "" }) : initials(p.name || p.id)),
      h("div", {},
        h("div", { className: "phone-name" }, p.name || p.id),
        h("div", { className: "phone-specialty" }, p.specialty || "Specialty"),
        h("div", { className: "phone-tagline" }, app.tagline || h("em", {}, "Tagline")),
        mood ? h("div", { className: "phone-mood" }, `✦ ${mood}`) : null)),
    h("div", { className: "phone-chat" },
      greeting ? h("div", { className: "bubble" }, greeting) : h("div", { className: "bubble empty" }, "Greeting"),
      ...(p.examples || []).filter((e) => e.user && e.reply).slice(0, 1).flatMap((e) => [
        h("div", { className: "bubble user" }, e.user),
        ...e.reply.split(/\n\s*\n/).slice(0, 3).map((b) => h("div", { className: "bubble" }, b.trim())),
      ])),
    h("div", { className: "phone-chips" },
      h("span", { className: "chip gold" }, app.ritualButton || "Draw a card"),
      ...(app.asks.length ? app.asks : ["Suggested question"]).slice(0, 2).map((q) => h("span", { className: "chip" }, q))),
  );
}

function appView() {
  const p = state.psychic;
  const app = { ...p.app, tags: [...p.app.tags], asks: [...p.app.asks], moods: [...p.app.moods], morningOpenings: [...p.app.morningOpenings] };
  const previewSlot = h("div", { className: "preview-slot" }, phonePreview(p, app));
  const redraw = () => previewSlot.replaceChildren(phonePreview(p, app));

  const save = async () => {
    const { psychic } = await api("PUT", `/api/psychics/${p.id}/app`, { app, inApp: p.inApp });
    state.psychic = psychic;
    renderHeader();
    renderTabs();
    await refreshList();
    showSwitch();
  };

  const switchSlot = h("div", {});
  const showSwitch = () => {
    const q = state.psychic;
    if (q.builtIn) {
      switchSlot.replaceChildren(h("p", { className: "hint intro" },
        `${q.name} is built into the app. Anything written here replaces the app's own text, field by field; leave a field empty to keep what the app has.`));
      return;
    }
    const blocked = q.missing.length ? "Finish the persona first: the app can only show a psychic who is live in readings."
      : q.appMissing.length ? `Fill in ${q.appMissing.map((k) => APP_LABEL[k]?.toLowerCase() ?? k).join(", ")} to show ${q.name} in the app.` : "";
    switchSlot.replaceChildren(h("div", { className: "show-in-app" },
      h("label", { className: "switch" },
        h("input", {
          type: "checkbox", role: "switch", checked: q.inApp, disabled: Boolean(blocked) && !q.inApp,
          onchange: async (e) => {
            try {
              await flushSave();
              const { psychic } = await api("PUT", `/api/psychics/${q.id}/app`, { app, inApp: e.target.checked });
              state.psychic = psychic;
              await refreshList();
              renderHeader();
              showSwitch();
              toast(psychic.inApp ? `${psychic.name} will appear in the app within a minute` : `${psychic.name} is hidden from the app`);
            } catch (err) {
              e.target.checked = !e.target.checked;
              toast(err.message);
            }
          },
        }),
        h("span", {}, "Show in the app")),
      h("p", { className: "hint" }, blocked || (q.inApp
        ? "Users see them in the app next time it checks in. Turn this off to hide them again."
        : "Ready. Turn this on when you're happy with them."))));
  };
  showSwitch();

  const sections = APP_SECTIONS.map((sec) => h("fieldset", { className: "app-section" },
    h("legend", {}, sec.title),
    ...sec.fields.map((f) => {
      const id = `a-${f.key}`;
      const onInput = (v) => { app[f.key] = v; redraw(); scheduleSave(save); };
      let control;
      if (f.list) control = h("textarea", { id, rows: 2, value: app[f.key].join("\n"), placeholder: f.placeholder, oninput: (e) => onInput(e.target.value.split("\n").map((x) => x.trim()).filter(Boolean)) });
      else if (f.select) control = h("select", { id, onchange: (e) => onInput(e.target.value) }, f.select.map(([v, t]) => h("option", { value: v, selected: app[f.key] === v }, t)));
      else if (f.color) control = h("div", { className: "row" },
        h("input", { id, type: "color", value: app.color || "#8a6f4a", oninput: (e) => onInput(e.target.value) }),
        h("button", { type: "button", className: "link small", onclick: (e) => { onInput(""); e.target.previousSibling.value = "#8a6f4a"; } }, "Use the default"));
      else if (f.input) control = h("input", { id, value: app[f.key], placeholder: f.placeholder, oninput: (e) => onInput(e.target.value) });
      else control = h("textarea", { id, rows: 2, value: app[f.key], placeholder: f.placeholder, oninput: (e) => onInput(e.target.value) });
      return h("div", { className: "field" },
        h("label", { for: id }, f.label, f.required && !p.builtIn ? null : h("span", { className: "optional" }, " optional")),
        f.hint ? h("p", { className: "hint" }, f.hint) : null,
        control);
    })));

  return h("div", { className: "app-layout" },
    h("div", {}, switchSlot, ...sections),
    h("aside", { className: "app-preview" }, h("div", { className: "sticky" }, h("p", { className: "hint" }, "Preview"), previewSlot)));
}

// ---------- Guided setup ----------
// Step by step: who they are, what to read, Claude writes them, review, photo, then into the app.

const WIZARD = [
  { key: "idea", title: "The idea" },
  { key: "sources", title: "Background" },
  { key: "deck", title: "Cards & tone" },
  { key: "write", title: "Write them" },
  { key: "review", title: "Review" },
  { key: "photo", title: "Photo" },
  { key: "live", title: "Go live" },
];

function wizardGo(step) {
  forgetUnsaved();
  location.hash = `#/${state.psychic.id}/create/${step}`;
}

function renderWizard() {
  const p = state.psychic;
  const index = WIZARD.findIndex((w) => w.key === state.wizardStep);
  const step = WIZARD[index];
  const steps = h("ol", { className: "steps" },
    WIZARD.map((w, i) => h("li", { className: i < index ? "done" : i === index ? "current" : "" },
      p && i !== index
        ? h("a", { href: `#/${p.id}/create/${w.key}` }, h("span", { className: "n" }, i + 1), w.title)
        : h("span", {}, h("span", { className: "n" }, i + 1), w.title))));
  const body = {
    idea: wizIdea, sources: wizSources, deck: wizDeck, write: wizWrite, review: wizReview, photo: wizPhoto, live: wizLive,
  }[step.key]();
  $("editor").replaceChildren(
    h("div", { className: "editor-inner wizard" },
      h("div", { className: "wizard-top" },
        h("div", { className: "eyebrow" }, p ? `Setting up ${p.name}` : "New psychic"),
        p ? h("a", { className: "link small", href: `#/${p.id}/persona` }, "Leave guided setup") : null),
      steps,
      h("section", { className: "wizard-body", "aria-live": "polite" }, body)),
  );
  $("editor").querySelector("[autofocus]")?.focus();
  growAll();
}

const wizNav = (back, next, nextLabel = "Next", extra = null) =>
  h("div", { className: "wizard-nav" },
    back ? h("button", { type: "button", className: "ghost", onclick: back }, "← Back") : h("span", {}),
    h("span", { className: "spacer" }),
    extra,
    next ? h("button", { type: "button", className: "primary", onclick: next }, nextLabel) : null);

function wizIdea() {
  const err = h("p", { className: "error", role: "alert" });
  const name = h("input", { id: "wz-name", maxLength: 200, placeholder: "e.g. Auntie Luna", autocomplete: "off", autofocus: true });
  const idPreview = h("span", { className: "hint" });
  let edited = false;
  const id = h("input", { id: "wz-id", maxLength: 32, placeholder: "luna", autocomplete: "off", oninput: () => { edited = true; showId(); } });
  const idField = h("div", { hidden: true }, h("label", { for: "wz-id" }, "Id"), id,
    h("p", { className: "hint" }, "Lowercase letters, numbers and dashes. It can't be changed later."));
  const showId = () => (idPreview.textContent = id.value ? `Id: ${id.value}` : "");
  name.addEventListener("input", () => { if (!edited) id.value = slugify(name.value); showId(); });
  const idea = h("textarea", { id: "wz-idea", rows: 4, placeholder: "e.g. A 70-year-old launderette owner in Leeds who reads tarot between spin cycles. Dry, nosy, kind underneath." });
  const specialty = h("input", { id: "wz-specialty", maxLength: 200, placeholder: "e.g. Money & second chances (optional, Claude can pick)" });

  const next = async () => {
    err.textContent = "";
    if (!name.value.trim()) return (err.textContent = "Give them a name.");
    try {
      const { psychic } = await api("POST", "/api/psychics", { id: id.value.trim(), name: name.value.trim() });
      if (specialty.value.trim()) await api("PUT", `/api/psychics/${psychic.id}`, { ...psychic, specialty: specialty.value.trim() });
      if (idea.value.trim()) await api("POST", `/api/psychics/${psychic.id}/documents`, { title: "The idea", body: idea.value.trim() });
      state.psychic = (await api("GET", `/api/psychics/${psychic.id}`)).psychic;
      await refreshList();
      wizardGo("sources");
    } catch (e) {
      err.textContent = e.message;
      if (/id/i.test(e.message)) idField.hidden = false;
    }
  };

  return h("div", {},
    h("h2", {}, "Who are they?"),
    h("p", { className: "lead" }, "Start with a name and a sentence or two. You'll add more background next, and Claude can write the rest."),
    h("label", { for: "wz-name" }, "Name"), name,
    h("p", { className: "hint row" }, idPreview, h("button", { type: "button", className: "link small", onclick: () => { idField.hidden = false; id.focus(); } }, "Change id")),
    idField,
    h("label", { for: "wz-idea" }, "The idea"), idea,
    h("label", { for: "wz-specialty" }, "What they read about ", h("span", { className: "optional" }, "optional")), specialty,
    err,
    wizNav(null, next, "Create and continue →"));
}

function wizSources() {
  const p = state.psychic;
  const title = h("input", { id: "wz-doc-title", maxLength: 120, placeholder: "e.g. Family" });
  const text = h("textarea", { id: "wz-doc-body", rows: 6, placeholder: "Paste or write anything about them: where they grew up, the people in their life, how they talk, what they believe, lines they'd say…" });
  const add = async () => {
    if (!text.value.trim()) return toast("Write or paste something first.");
    try {
      await api("POST", `/api/psychics/${p.id}/documents`, { title: title.value.trim() || titleFrom(text.value, "Background"), body: text.value.replace(/^# .+$/m, "").trim() });
      await reloadPsychic();
      renderWizard();
      toast("Added");
    } catch (e) { toast(e.message); }
  };
  const upload = h("input", { type: "file", accept: ".md,.markdown,.txt,text/plain,text/markdown", multiple: true, hidden: true,
    onchange: (e) => { const f = [...e.target.files]; e.target.value = ""; addFiles(f); } });
  const drop = h("div", { className: "dropzone",
    ondragover: (e) => { e.preventDefault(); drop.classList.add("over"); },
    ondragleave: () => drop.classList.remove("over"),
    ondrop: (e) => { e.preventDefault(); drop.classList.remove("over"); addFiles(e.dataTransfer.files); } },
    h("div", { className: "row" }, h("button", { type: "button", className: "ghost", onclick: () => upload.click() }, "Upload .md or .txt files"), upload),
    h("p", { className: "hint" }, "Or drop files here."));

  return h("div", {},
    h("h2", {}, `What should Claude know about ${p.name}?`),
    h("p", { className: "lead" }, "The more you give, the more specific they get. Notes, a character sketch, family, places, sayings: rough is fine. Each piece becomes a background document the psychic draws on in readings."),
    p.documents.length
      ? h("ul", { className: "source-list" }, p.documents.map((d) => h("li", {},
          h("span", { className: "title" }, d.title || "Untitled"),
          h("span", { className: "hint" }, formatSize(d.body.length)),
          h("button", { type: "button", className: "link small", onclick: async () => {
            if (!confirm(`Remove "${d.title || "Untitled"}"?`)) return;
            await api("DELETE", `/api/documents/${d.id}`);
            await reloadPsychic();
            renderWizard();
          } }, "Remove"))))
      : h("p", { className: "empty" }, "Nothing yet."),
    h("div", { className: "source-add" },
      h("label", { for: "wz-doc-title" }, "Title ", h("span", { className: "optional" }, "optional")), title,
      h("label", { for: "wz-doc-body" }, "Text"), text,
      h("div", { className: "row" }, h("button", { type: "button", className: "ghost", onclick: add }, "+ Add this"))),
    drop,
    wizNav(null, () => wizardGo("deck"), p.documents.length ? "Next →" : "Skip for now →"));
}

/** Tone notes from the guided setup, kept in this browser per psychic so a reload doesn't lose them. */
function wizardNotes(id) {
  try { return localStorage.getItem(`wizard-notes:${id}`) ?? ""; } catch { return ""; }
}
function setWizardNotes(id, text) {
  try { localStorage.setItem(`wizard-notes:${id}`, text); } catch { /* private mode: notes last until reload */ }
  state.wizardNotes = text;
}

function wizDeck() {
  const p = state.psychic;
  const notes = h("textarea", { id: "wz-notes", rows: 3, value: state.wizardNotes || wizardNotes(p.id), placeholder: "e.g. Deadpan but soft underneath. Never mean. Loves bingo metaphors.",
    oninput: (e) => setWizardNotes(p.id, e.target.value) });
  const choose = async (deck) => {
    try {
      const { psychic } = await api("PUT", `/api/psychics/${p.id}/deck`, { deck, cardMeanings: deck === p.deck ? p.cardMeanings : [] });
      state.psychic = psychic;
    } catch (e) { toast(e.message); }
  };
  const card = (deck, title, text) => h("label", { className: "choice" },
    h("input", { type: "radio", name: "wz-deck", checked: p.deck === deck, onchange: () => choose(deck) }),
    h("span", {}, h("strong", {}, title), h("span", { className: "hint" }, text)));
  return h("div", {},
    h("h2", {}, "Cards and tone"),
    h("p", { className: "lead" }, "Every psychic can lay out real cards in a reading. Pick their deck, and tell Claude anything about the tone you're after."),
    h("div", { className: "choices" },
      card("tarot", "Tarot", "78 cards with pictures, and cards can land reversed. Most psychics read tarot."),
      card("playing", "Playing cards", "An ordinary 52-card deck read the old way: hearts for love, spades for hard truths.")),
    h("label", { for: "wz-notes" }, "Notes for Claude ", h("span", { className: "optional" }, "optional")),
    notes,
    wizNav(() => wizardGo("sources"), () => wizardGo("write"), "Next →"));
}

function wizWrite() {
  const p = state.psychic;
  if (!state.claude) {
    return h("div", {},
      h("h2", {}, `Write ${p.name}`),
      h("p", { className: "lead" }, "Claude isn't set up in this studio (it needs ANTHROPIC_API_KEY in the studio's settings), so this part is by hand: fill in the Persona and In the app tabs and add a few example replies. Then come back for the photo."),
      wizNav(() => wizardGo("deck"), () => go(p.id, "persona"), "Open the persona tab"));
  }
  const parts = [
    ["persona", "Their character: backstory, voice, texting style, quirks and how they read"],
    ["app", "What the app shows: tagline, bio, greeting, suggested questions, moods"],
    ["examples", "6 example replies in their voice"],
    ["cards", `Their own meaning for 8 ${p.deck === "playing" ? "playing cards" : "tarot cards"}`],
  ];
  const checks = Object.fromEntries(parts.map(([k]) => [k, h("input", { type: "checkbox", checked: true })]));
  const status = h("div", { className: "writing", hidden: true });
  const err = h("p", { className: "error", role: "alert" });
  const goBtn = h("button", { type: "button", className: "primary big" }, `✦ Write ${p.name} with Claude`);
  goBtn.addEventListener("click", async () => {
    const body = {
      // Fill what's empty: keeps anything already written, like a specialty typed in the first step.
      persona: checks.persona.checked ? "empty" : undefined,
      app: checks.app.checked ? "empty" : undefined,
      examples: checks.examples.checked ? 6 : undefined,
      cards: checks.cards.checked ? { count: 8 } : undefined,
      notes: state.wizardNotes || wizardNotes(p.id),
    };
    if (!body.persona && !body.app && !body.examples && !body.cards) return (err.textContent = "Tick at least one thing.");
    err.textContent = "";
    goBtn.disabled = true;
    Object.values(checks).forEach((c) => (c.disabled = true));
    status.hidden = false;
    const started = Date.now();
    const lines = ["Reading the background…", "Finding their voice…", "Writing the greeting…", "Shuffling the deck…", "Trying out replies…", "Nearly there…"];
    const tick = () => {
      const t = Math.round((Date.now() - started) / 1000);
      status.replaceChildren(h("span", { className: "orb", "aria-hidden": "true" }), h("span", {}, `${lines[Math.min(Math.floor(t / 9), lines.length - 1)]} ${t}s`));
    };
    tick();
    const timer = setInterval(tick, 1000);
    try {
      const result = await runClaude(body);
      state.psychic = result.psychic;
      await refreshList();
      wizardGo("review");
      toast(`Claude wrote ${result.summary}`);
    } catch (e) {
      err.textContent = e.message;
      goBtn.disabled = false;
      Object.values(checks).forEach((c) => (c.disabled = false));
      status.hidden = true;
    } finally {
      clearInterval(timer);
    }
  });
  return h("div", {},
    h("h2", {}, `Write ${p.name}`),
    h("p", { className: "lead" }, `Claude reads the idea${p.documents.length > 1 ? ` and all ${p.documents.length} documents` : p.documents.length ? " and the background" : ""} and writes the rest in one go. It takes about a minute. Everything is saved as one version you can undo, and you'll review it next.`),
    h("ul", { className: "write-list" }, parts.map(([k, label]) => h("li", {}, h("label", { className: "check" }, checks[k], h("span", {}, label))))),
    status,
    err,
    h("div", { className: "row center" }, goBtn),
    wizNav(() => wizardGo("deck"), null, "", h("button", { type: "button", className: "link", onclick: () => wizardGo("review") }, "Skip, I'll write it myself")));
}

function wizReview() {
  const p = state.psychic;
  const section = (title, tab, ...content) => h("section", { className: "review-card" },
    h("div", { className: "row" }, h("h3", {}, title), h("span", { className: "spacer" }), h("a", { className: "link small", href: `#/${p.id}/${tab}` }, "Edit")),
    ...content);
  const quote = (t) => (t ? h("p", { className: "review-text" }, t) : h("p", { className: "hint" }, "Not written yet."));
  const rewriteNotes = h("textarea", { rows: 2, placeholder: "What should change? e.g. Funnier, shorter messages, less about cats." });
  const rewrite = h("button", { type: "button", className: "ghost claude" }, "✦ Rewrite with these notes");
  rewrite.addEventListener("click", async () => {
    if (!rewriteNotes.value.trim()) return toast("Say what should change first.");
    rewrite.disabled = true;
    rewrite.textContent = "Rewriting…";
    try {
      const result = await runClaude({ persona: "all", app: "all", notes: `${state.wizardNotes || wizardNotes(p.id)}\n${rewriteNotes.value}`.trim() });
      state.psychic = result.psychic;
      await refreshList();
      renderWizard();
      if (result.undoVersionId) undoToast(`Claude rewrote ${p.name}`, async () => {
        state.psychic = (await api("POST", `/api/versions/${result.undoVersionId}/restore`)).psychic;
        renderWizard();
      });
    } catch (e) {
      toast(e.message);
      rewrite.disabled = false;
      rewrite.textContent = "✦ Rewrite with these notes";
    }
  });
  return h("div", {},
    h("h2", {}, `Meet ${p.name}`),
    h("p", { className: "lead" }, "Read it through. Edit anything directly, or tell Claude what to change."),
    h("div", { className: "review-layout" },
      h("div", {},
        section("Who they are", "persona",
          h("p", { className: "review-label" }, p.specialty || "No specialty yet"),
          quote(p.backstory),
          p.catchphrases.length ? h("p", { className: "hint" }, p.catchphrases.map((c) => `“${c}”`).join("  ·  ")) : null),
        section("How they sound", "persona", quote(p.voice), quote(p.texting)),
        section("How they read cards", "deck",
          quote(p.howIRead),
          p.cardMeanings.length ? h("p", { className: "hint" }, `Their own meaning for ${p.cardMeanings.map((m) => m.card).join(", ")}.`) : null),
        section("Example replies", "examples",
          p.examples.length ? h("p", { className: "hint" }, `${p.examples.length} written. The preview shows the first.`) : quote("")),
        state.claude ? h("section", { className: "review-card" }, h("h3", {}, "Not quite right?"), rewriteNotes, h("div", { className: "row" }, rewrite)) : null),
      h("aside", { className: "app-preview" }, h("div", { className: "sticky" }, h("p", { className: "hint" }, "In the app"), phonePreview(p)))),
    wizNav(() => wizardGo("write"), () => wizardGo("photo"), "Looks good →"));
}

function wizPhoto() {
  const p = state.psychic;
  return h("div", {},
    h("h2", {}, `A photo of ${p.name}`),
    h("p", { className: "lead" }, "A square portrait works best. It's cropped to a circle and shrunk to 800 px. You can skip this and add one later."),
    h("div", { className: "photo-step" }, photoPicker(p)),
    wizNav(() => wizardGo("review"), () => wizardGo("live"), p.photoId ? "Next →" : "Skip for now →"));
}

function wizLive() {
  const p = state.psychic;
  const row = (ok, title, detail, link) => h("li", { className: ok ? "ok" : "pending" },
    h("span", { className: "mark", "aria-hidden": "true" }, ok ? "✓" : "○"),
    h("div", {}, h("strong", {}, title), h("div", { className: "hint" }, detail)),
    !ok && link ? h("a", { className: "link small", href: link }, "Fill in") : null);
  const live = !p.missing.length;
  const appReady = !p.appMissing.length;
  const canShow = live && appReady;
  const toggle = h("input", { type: "checkbox", role: "switch", checked: p.inApp, disabled: !canShow && !p.inApp });
  toggle.addEventListener("change", async () => {
    try {
      const { psychic } = await api("PUT", `/api/psychics/${p.id}/app`, { app: p.app, inApp: toggle.checked });
      state.psychic = psychic;
      await refreshList();
      renderWizard();
    } catch (e) { toggle.checked = !toggle.checked; toast(e.message); }
  });
  return h("div", {},
    h("h2", {}, p.inApp ? `${p.name} is in the app ✦` : `Put ${p.name} in the app`),
    h("p", { className: "lead" }, p.builtIn
      ? `${p.name} is built into the app, so they're always there. Changes reach readings within a minute.`
      : "Once they're live in readings and the app has what it needs, switch them on. Users see them the next time the app checks in, no app update needed."),
    h("ul", { className: "checklist" },
      row(live, "Live in readings", live ? "Their character is complete." : `Still missing: ${p.missing.map((m) => PART[m]?.label ?? m).join(", ")}.`, `#/${p.id}/persona`),
      row(appReady, "Ready for the app", appReady ? "Tagline, bio, greeting and suggested questions are in." : `Still missing: ${p.appMissing.map((m) => APP_LABEL[m] ?? m).join(", ")}.`, `#/${p.id}/app`),
      row(Boolean(p.photoId), "Photo", p.photoId ? "Looking good." : "Optional. Without one, the app shows their initial.", `#/${p.id}/create/photo`)),
    p.builtIn ? null : h("div", { className: "show-in-app big" },
      h("label", { className: "switch" }, toggle, h("span", {}, "Show in the app"))),
    wizNav(() => wizardGo("photo"), () => go(p.id, "persona"), "Finish"));
}

// ---------- New psychic ----------
function slugify(name) {
  return name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/^(madame|grandma|grandpa|oracle|auntie|aunt|uncle|the)\s+/, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32);
}

$("new-psychic").addEventListener("click", async () => {
  if (!(await canLeave())) return;
  forgetUnsaved();
  location.hash = "#/new";
});

// ---------- Start ----------
async function start() {
  $("login").hidden = true;
  $("app").hidden = false;
  state.claude = Boolean((await api("GET", "/api/me")).claude);
  await refreshList();
  await route();
}

(async () => {
  try {
    await api("GET", "/api/me");
    await start();
  } catch (err) {
    if (err.status !== 401) {
      document.body.textContent = `Psychic Studio couldn't load: ${err.message}`;
    }
  }
})();
