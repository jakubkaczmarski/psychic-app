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
  if (!id) {
    if (state.list.length) return go(state.list[0].id);
    return renderEmpty();
  }
  state.tab = ["persona", "examples", "documents", "history"].includes(tab) ? tab : "persona";
  if (!state.psychic || state.psychic.id !== id) {
    try {
      state.psychic = (await api("GET", `/api/psychics/${encodeURIComponent(id)}`)).psychic;
    } catch (err) {
      if (err.status === 404 && state.list.length) return go(state.list[0].id);
      throw err;
    }
    state.openDocId = null;
  }
  state.examples = state.psychic.examples.map((e) => ({ ...e }));
  if (!state.examples.length) state.examples.push({ user: "", reply: "" });
  renderSidebar();
  renderEditor();
  if (focus) document.getElementById(decodeURIComponent(focus))?.focus();
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
          h("span", { className: p.missing.length ? "dot draft" : "dot", title: p.missing.length ? "Not live yet" : "Live in readings" }),
          h("span", { className: "name" }, p.name || p.id),
          h("span", { className: "meta" }, p.missing.length ? "Not live yet" : p.specialty),
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
      h("button", { className: "primary", onclick: openNewDialog }, "New psychic"),
    ),
  );
}

function approxTokens(p) {
  const chars = JSON.stringify(p.published).length;
  return Math.round(chars / 4 / 50) * 50 || 50;
}

function renderEditor() {
  $("editor").replaceChildren(
    h("div", { className: "editor-inner" },
      h("header", { id: "character", className: "character" }),
      h("div", { className: "tabbar" },
        h("nav", { id: "tabs", className: "tabs", "aria-label": "Sections" }),
        h("span", { id: "save-state", className: "save-state", role: "status", "data-kind": "saved" }, "All changes saved"),
      ),
      h("div", { id: "tab-body" },
        state.tab === "examples" ? examplesView()
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
  el.replaceChildren(...[
    h("h1", {}, p.name || p.id),
    h("div", { className: "specialty" }, p.specialty || "No specialty yet"),
    p.catchphrases[0] ? h("blockquote", {}, `“${p.catchphrases[0]}”`) : null,
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
    tab("examples", "Examples", complete),
    tab("documents", "Documents", p.documents.filter((d) => d.enabled).length),
    tab("history", "History"),
  );
}

// ---------- Persona ----------
function personaView() {
  const p = state.psychic;
  const form = h("form", { className: "fields", onsubmit: (e) => e.preventDefault() });

  for (const f of FIELDS) {
    const id = `f-${f.key}`;
    const value = f.list ? p[f.key].join("\n") : p[f.key];
    const field = h("div", { className: "field" }, h("label", { for: id }, f.label));
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

// ---------- New psychic ----------
function slugify(name) {
  return name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/^(madame|grandma|oracle|auntie|the)\s+/, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32);
}

let idEdited = false;
async function openNewDialog() {
  if (!(await canLeave())) return;
  $("new-form").reset();
  $("new-error").textContent = "";
  $("new-id-preview").textContent = "";
  $("new-id-field").hidden = true;
  idEdited = false;
  $("new-dialog").showModal();
}
$("new-psychic").addEventListener("click", openNewDialog);
$("new-cancel").addEventListener("click", () => $("new-dialog").close());
$("new-name").addEventListener("input", () => {
  if (!idEdited) $("new-id").value = slugify($("new-name").value);
  $("new-id-preview").textContent = $("new-id").value ? `Id: ${$("new-id").value}` : "";
});
$("new-id-edit").addEventListener("click", () => {
  $("new-id-field").hidden = false;
  $("new-id").focus();
});
$("new-id").addEventListener("input", () => {
  idEdited = true;
  $("new-id-preview").textContent = $("new-id").value ? `Id: ${$("new-id").value}` : "";
});
$("new-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const { psychic } = await api("POST", "/api/psychics", { id: $("new-id").value.trim(), name: $("new-name").value.trim() });
    $("new-dialog").close();
    forgetUnsaved();
    await refreshList();
    go(psychic.id, "persona");
    toast(`${psychic.name} created. Fill in the list at the top to make them live.`);
  } catch (err) {
    $("new-error").textContent = err.message;
    if (/id/i.test(err.message)) $("new-id-field").hidden = false;
  }
});

// ---------- Start ----------
async function start() {
  $("login").hidden = true;
  $("app").hidden = false;
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
