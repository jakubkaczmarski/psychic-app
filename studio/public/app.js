// Psychic Studio web interface. Plain modules, no build step.

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
    headers: body !== undefined || method !== "GET" ? { "content-type": "application/json" } : {},
    body: body !== undefined ? JSON.stringify(body) : method !== "GET" ? "{}" : undefined,
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

// ---------- State ----------
const state = {
  list: [],
  psychic: null,
  tab: "persona",
  dirty: false,
  examples: [],
  openDoc: null, // { id, title, body }
};

const FIELDS = [
  { key: "name", label: "Name", input: true },
  { key: "specialty", label: "Specialty", input: true, hint: "One line, shown in the app, e.g. \"Love & relationships\"." },
  { key: "backstory", label: "Backstory", hint: "Who they are and where they come from." },
  { key: "voice", label: "Voice", hint: "How they sound: rhythm, vocabulary, attitude, what they call people." },
  { key: "texting", label: "Texting style", hint: "How many messages, how long, punctuation, capitals, typos." },
  { key: "catchphrases", label: "Catchphrases", list: true, hint: "One per line. Used sparingly, never twice in a row." },
  { key: "never", label: "Never", list: true, hint: "One per line: words, habits or topics this character never uses." },
  { key: "quirks", label: "Quirks", hint: "Habits that show up in readings." },
  { key: "others", label: "The other psychics", hint: "What they think of the rest of the cast." },
  { key: "ritual", label: "Ritual", hint: "How they read the result of their ritual button in the app." },
];

const LABELS = Object.fromEntries(FIELDS.map((f) => [f.key, f.label.toLowerCase()]));
LABELS.examples = "examples";

function setDirty(value) {
  state.dirty = value;
  const el = document.querySelector(".savebar .state");
  if (el) {
    el.textContent = value ? "Unsaved changes" : "All changes saved";
    el.classList.toggle("dirty", value);
  }
}

function confirmLeave() {
  return !state.dirty || confirm("You have unsaved changes. Leave without saving?");
}

window.addEventListener("beforeunload", (e) => {
  if (state.dirty) e.preventDefault();
});

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
  if (!confirmLeave()) return;
  state.dirty = false;
  await api("POST", "/api/logout");
  showLogin();
});

// ---------- Routing: #/<id>/<tab> ----------
function go(id, tab = "persona") {
  location.hash = `#/${id}/${tab}`;
}

let currentHash = location.hash;
window.addEventListener("hashchange", () => {
  if (location.hash === currentHash) return;
  if (!confirmLeave()) {
    history.replaceState(null, "", currentHash);
    return;
  }
  currentHash = location.hash;
  setDirty(false);
  route();
});

async function route() {
  const [, id, tab] = location.hash.split("/");
  if (!id) {
    if (state.list.length) return go(state.list[0].id);
    return renderEmpty();
  }
  state.tab = ["persona", "examples", "documents"].includes(tab) ? tab : "persona";
  if (!state.psychic || state.psychic.id !== id) {
    try {
      state.psychic = (await api("GET", `/api/psychics/${encodeURIComponent(id)}`)).psychic;
    } catch (err) {
      if (err.status === 404 && state.list.length) return go(state.list[0].id);
      throw err;
    }
    state.openDoc = null;
  }
  state.examples = state.psychic.examples.map((e) => ({ ...e }));
  renderSidebar();
  renderEditor();
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
          h("span", { className: "meta" }, p.specialty || "No specialty yet"),
        ),
      ),
    ),
  );
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
  const p = state.psychic;
  const live = !p.missing.length;
  const enabledDocs = p.documents.filter((d) => d.enabled).length;

  const header = h("header", { className: "character" },
    h("h1", {}, p.name || p.id),
    h("div", { className: "specialty" }, p.specialty || "No specialty yet"),
    p.catchphrases[0] ? h("blockquote", {}, `“${p.catchphrases[0]}”`) : null,
    h("div", { className: "status" },
      h("span", { className: live ? "dot" : "dot draft" }),
      live
        ? h("span", {}, `Live in readings. Sends about ${approxTokens(p).toLocaleString("en")} tokens of character with every reading.`)
        : h("span", {}, `Not live yet. Still needed: ${p.missing.map((m) => LABELS[m] ?? m).join(", ")}.`),
    ),
  );

  const tab = (key, label, count) =>
    h("a", { href: `#/${p.id}/${key}`, "aria-current": state.tab === key ? "page" : null },
      label, count !== undefined ? h("span", { className: "count" }, count) : null);

  const tabs = h("nav", { className: "tabs", "aria-label": "Sections" },
    tab("persona", "Persona"),
    tab("examples", "Examples", p.examples.length),
    tab("documents", "Documents", `${enabledDocs}`),
  );

  const body =
    state.tab === "examples" ? examplesView() : state.tab === "documents" ? documentsView() : personaView();

  $("editor").replaceChildren(h("div", { className: "editor-inner" }, header, tabs, body));
}

function savebar(label, onSave) {
  return h("div", { className: "savebar" },
    h("button", { className: "primary", type: "submit", onclick: onSave }, label),
    h("span", { className: state.dirty ? "state dirty" : "state" }, state.dirty ? "Unsaved changes" : "All changes saved"),
  );
}

let currentSave = null;
document.addEventListener("keydown", (e) => {
  if ((e.metaKey || e.ctrlKey) && e.key === "s" && currentSave) {
    e.preventDefault();
    currentSave();
  }
});

async function afterSave(psychic, message) {
  state.psychic = psychic;
  setDirty(false);
  await refreshList();
  renderEditor();
  toast(message);
}

// Persona
function personaView() {
  const p = state.psychic;
  const form = h("form", { oninput: () => setDirty(true), onsubmit: (e) => e.preventDefault() });

  for (const f of FIELDS) {
    const id = `f-${f.key}`;
    const value = f.list ? p[f.key].join("\n") : p[f.key];
    form.append(h("label", { for: id }, f.label));
    if (f.hint) form.append(h("p", { className: "hint" }, f.hint));
    form.append(
      f.input
        ? h("input", { id, name: f.key, value, maxLength: 10000 })
        : h("textarea", { id, name: f.key, value, rows: f.list ? 4 : 5 }),
    );
  }

  const save = async () => {
    const data = new FormData(form);
    const body = {};
    for (const f of FIELDS) {
      const v = String(data.get(f.key) ?? "");
      body[f.key] = f.list ? v.split("\n").map((s) => s.trim()).filter(Boolean) : v;
    }
    try {
      const { psychic } = await api("PUT", `/api/psychics/${p.id}`, body);
      await afterSave(psychic, "Persona saved");
    } catch (err) {
      toast(err.message);
    }
  };
  currentSave = save;
  form.append(savebar("Save persona", save));

  const dangerZone = h("section", { className: "danger-zone" },
    h("h3", {}, "Delete psychic"),
    h("p", {}, `Removes ${p.name || p.id}, their examples and documents. Readings with this psychic stop working within a minute.`),
    h("button", {
      className: "danger", type: "button",
      onclick: async () => {
        const typed = prompt(`Type "${p.id}" to delete this psychic for good.`);
        if (typed !== p.id) return;
        await api("DELETE", `/api/psychics/${p.id}`);
        state.psychic = null;
        setDirty(false);
        await refreshList();
        toast("Psychic deleted");
        location.hash = "";
      },
    }, "Delete psychic"),
  );

  return h("div", {}, form, dangerZone);
}

// Examples
function examplesView() {
  const p = state.psychic;
  const list = h("div", {});

  const draw = () => {
    list.replaceChildren(
      ...state.examples.map((ex, i) =>
        h("div", { className: "example" },
          h("label", { for: `ex-u-${i}` }, "They say"),
          h("input", { id: `ex-u-${i}`, value: ex.user, oninput: (e) => { ex.user = e.target.value; setDirty(true); } }),
          h("label", { for: `ex-r-${i}` }, `${p.name || "The psychic"} replies`),
          h("textarea", { id: `ex-r-${i}`, value: ex.reply, rows: Math.min(14, Math.max(4, ex.reply.split("\n").length + 1)), oninput: (e) => { ex.reply = e.target.value; setDirty(true); } }),
          h("div", { className: "row" },
            h("button", { className: "ghost small", type: "button", disabled: i === 0, onclick: () => move(i, -1) }, "Move up"),
            h("button", { className: "ghost small", type: "button", disabled: i === state.examples.length - 1, onclick: () => move(i, 1) }, "Move down"),
            h("span", { className: "spacer" }),
            h("button", { className: "danger small", type: "button", onclick: () => { state.examples.splice(i, 1); setDirty(true); draw(); } }, "Remove"),
          ),
        ),
      ),
    );
  };
  const move = (i, by) => {
    const [ex] = state.examples.splice(i, 1);
    state.examples.splice(i + by, 0, ex);
    setDirty(true);
    draw();
  };
  draw();

  const save = async () => {
    try {
      const { psychic } = await api("PUT", `/api/psychics/${p.id}/examples`, { examples: state.examples });
      state.examples = psychic.examples.map((e) => ({ ...e }));
      await afterSave(psychic, "Examples saved");
    } catch (err) {
      toast(err.message);
    }
  };
  currentSave = save;

  return h("div", {},
    h("p", { className: "hint" },
      "Short exchanges that show how this psychic texts. Leave a blank line in a reply to split it into separate chat bubbles. The psychic matches the voice but never copies these lines, so vary them."),
    list,
    h("div", { className: "row", style: "margin-top:16px" },
      h("button", {
        className: "ghost", type: "button",
        onclick: () => {
          state.examples.push({ user: "", reply: "" });
          setDirty(true);
          draw();
          document.getElementById(`ex-u-${state.examples.length - 1}`)?.focus();
        },
      }, "Add example"),
    ),
    savebar("Save examples", save),
  );
}

// Documents
function formatSize(chars) {
  const words = Math.max(1, Math.round(chars / 6));
  return `${words.toLocaleString("en")} words`;
}

function titleFrom(text, fallback) {
  return text.match(/^# (.+)$/m)?.[1].trim() || fallback;
}

function documentsView() {
  const p = state.psychic;
  currentSave = null;

  const openEditor = (doc) => {
    if (!confirmLeave()) return;
    setDirty(false);
    state.openDoc = state.openDoc?.id === doc.id ? null : { id: doc.id, title: doc.title, body: doc.body };
    renderEditor();
  };

  const saveDoc = async () => {
    const d = state.openDoc;
    try {
      await api("PUT", `/api/documents/${d.id}`, { title: d.title, body: d.body });
      const { psychic } = await api("GET", `/api/psychics/${p.id}`);
      await afterSave(psychic, "Document saved");
    } catch (err) {
      toast(err.message);
    }
  };

  const rows = p.documents.map((doc) => {
    const open = state.openDoc?.id === doc.id;
    const row = h("div", { className: doc.enabled ? "doc-row" : "doc-row off" },
      h("button", { className: "title", type: "button", "aria-expanded": String(open), onclick: () => openEditor(doc) }, doc.title),
      h("span", { className: "size" }, formatSize(doc.body.length)),
      h("label", { className: "toggle" },
        h("input", {
          type: "checkbox", checked: doc.enabled,
          onchange: async (e) => {
            try {
              await api("PUT", `/api/documents/${doc.id}`, { enabled: e.target.checked });
              const { psychic } = await api("GET", `/api/psychics/${p.id}`);
              state.psychic = psychic;
              await refreshList();
              renderEditor();
              toast(e.target.checked ? "Document is used in readings" : "Document is no longer used in readings");
            } catch (err) {
              toast(err.message);
            }
          },
        }),
        "Used in readings",
      ),
    );

    let editor = null;
    if (open) {
      currentSave = saveDoc;
      const d = state.openDoc;
      editor = h("div", { className: "doc-edit" },
        h("label", { for: "doc-title" }, "Title"),
        h("input", { id: "doc-title", value: d.title, maxLength: 120, oninput: (e) => { d.title = e.target.value; setDirty(true); } }),
        h("label", { for: "doc-body" }, "Text"),
        h("textarea", { id: "doc-body", className: "tall", value: d.body, oninput: (e) => { d.body = e.target.value; setDirty(true); } }),
        h("div", { className: "savebar" },
          h("button", { className: "primary", type: "button", onclick: saveDoc }, "Save document"),
          h("span", { className: state.dirty ? "state dirty" : "state" }, state.dirty ? "Unsaved changes" : "All changes saved"),
          h("span", { className: "spacer" }),
          h("button", {
            className: "danger", type: "button",
            onclick: async () => {
              if (!confirm(`Delete "${doc.title}"? This can't be undone.`)) return;
              await api("DELETE", `/api/documents/${doc.id}`);
              state.openDoc = null;
              const { psychic } = await api("GET", `/api/psychics/${p.id}`);
              await afterSave(psychic, "Document deleted");
            },
          }, "Delete document"),
        ),
      );
    }
    return h("li", {}, row, editor);
  });

  const addDocument = async (title, body) => {
    const { document } = await api("POST", `/api/psychics/${p.id}/documents`, { title, body });
    return document;
  };

  const upload = h("input", {
    type: "file", accept: ".md,.txt,text/plain,text/markdown", multiple: true, hidden: true,
    onchange: async (e) => {
      const files = [...e.target.files];
      e.target.value = "";
      try {
        for (const file of files) {
          const text = await file.text();
          await addDocument(titleFrom(text, file.name.replace(/\.(md|txt)$/i, "")), text.replace(/^# .+$/m, "").trim());
        }
        const { psychic } = await api("GET", `/api/psychics/${p.id}`);
        await afterSave(psychic, files.length === 1 ? "Document added" : `${files.length} documents added`);
      } catch (err) {
        toast(err.message);
      }
    },
  });

  return h("div", {},
    h("p", { className: "hint" },
      "Background for this character: their history, beliefs, people in their life, how they read particular cards or signs. Every document marked \"Used in readings\" goes into every reading, and the psychic draws on it without reciting it. Write facts about the character rather than instructions."),
    h("div", { className: "row", style: "margin-top:12px" },
      h("button", {
        className: "primary", type: "button",
        onclick: async () => {
          if (!confirmLeave()) return;
          try {
            const doc = await addDocument("Untitled", "");
            const { psychic } = await api("GET", `/api/psychics/${p.id}`);
            state.openDoc = { id: doc.id, title: doc.title, body: doc.body };
            await afterSave(psychic, "Document added");
            document.getElementById("doc-title")?.select();
          } catch (err) {
            toast(err.message);
          }
        },
      }, "New document"),
      h("button", { className: "ghost", type: "button", onclick: () => upload.click() }, "Upload .md or .txt"),
      upload,
    ),
    p.documents.length
      ? h("ul", { className: "docs" }, rows)
      : h("p", { className: "empty" }, `${p.name || "This psychic"} has no documents yet. Add one to give them more history to draw on.`),
  );
}

// ---------- New psychic ----------
function slugify(name) {
  return name.toLowerCase().normalize("NFKD").replace(/[̀-ͯ]/g, "")
    .replace(/^(madame|grandma|oracle|auntie|the)\s+/, "")
    .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 32);
}

let idEdited = false;
function openNewDialog() {
  if (!confirmLeave()) return;
  $("new-form").reset();
  $("new-error").textContent = "";
  idEdited = false;
  $("new-dialog").showModal();
}
$("new-psychic").addEventListener("click", openNewDialog);
$("new-cancel").addEventListener("click", () => $("new-dialog").close());
$("new-name").addEventListener("input", () => {
  if (!idEdited) $("new-id").value = slugify($("new-name").value);
});
$("new-id").addEventListener("input", () => (idEdited = true));
$("new-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const { psychic } = await api("POST", "/api/psychics", { id: $("new-id").value.trim(), name: $("new-name").value.trim() });
    $("new-dialog").close();
    setDirty(false);
    await refreshList();
    go(psychic.id);
  } catch (err) {
    $("new-error").textContent = err.message;
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
