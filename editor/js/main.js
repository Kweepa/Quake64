import {
  KINDS,
  PALETTE_ORDER,
  FRAME_NAMES,
  clampObject,
  clampVert,
  createObject,
  createDefaultDocument,
  currentRoom,
  cycleFace,
  normalizeDocument,
  uid,
  LEVEL_NAMES,
  activeMap,
} from "./model.js";
import { downloadJSON, loadFromStorage, readJSONFile, saveToStorage } from "./io.js";
import { LayoutView } from "./layoutView.js";
import { OverheadView } from "./overheadView.js";
import { AnimView } from "./animView.js";

const statusEl = document.getElementById("status");
const titleEl = document.querySelector(".toolbar h1");
const btnUndo = document.getElementById("btn-undo");
const btnRedo = document.getElementById("btn-redo");
const UNDO_LIMIT = 40;
const AUTOSAVE_MS = 8000;

let doc = normalizeDocument(loadFromStorage()) || createDefaultDocument();
let editorMode = "layout";
let localDraw = false;
let selectedId = null;
let enemyIndex = 0;
let frameIndex = 0;
let selectedVerts = [];
let dirty = false;
let autosaveTimer = null;
let undoStack = [];
let redoStack = [];
let undoGesture = false;

const layoutView = new LayoutView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getDoc: () => doc,
  getSelectedId: () => selectedId,
  getLocalMode: () => localDraw && editorMode === "layout",
  onSelect: (id) => {
    selectedId = id;
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onStatus: setStatus,
  beginUndo,
  endUndo,
});

const overheadView = new OverheadView(document.getElementById("overhead-canvas"), {
  getDoc: () => doc,
  getCamera: () => layoutView.camera,
  getSelectedId: () => selectedId,
  getLocalMode: () => localDraw,
});

const animView = new AnimView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getEnemy: () => doc.enemies[enemyIndex],
  getFrame: () => frameIndex,
  getSelectedVerts: () => selectedVerts,
  onSelectVert: (i, additive) => {
    if (i < 0) selectedVerts = [];
    else if (additive) {
      if (!selectedVerts.includes(i)) selectedVerts.push(i);
    } else selectedVerts = [i];
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  beginUndo,
  endUndo,
});

function setStatus(msg, isError = false) {
  statusEl.textContent = msg || "";
  statusEl.classList.toggle("error", isError);
}

function markDirty() {
  dirty = true;
  titleEl.textContent = "Quake64*";
  document.title = "Quake64 *";
  clearTimeout(autosaveTimer);
  autosaveTimer = setTimeout(() => {
    saveToStorage(doc);
    dirty = false;
    titleEl.textContent = "Quake64";
    document.title = "Quake64 Editor";
  }, AUTOSAVE_MS);
}

function snapshot() {
  return JSON.stringify(doc);
}

function beginUndo() {
  if (undoGesture) return;
  undoStack.push(snapshot());
  if (undoStack.length > UNDO_LIMIT) undoStack.shift();
  redoStack.length = 0;
  undoGesture = true;
  updateUndoButtons();
}

function endUndo() {
  undoGesture = false;
}

function pushUndo() {
  beginUndo();
  endUndo();
}

function restore(json) {
  doc = normalizeDocument(JSON.parse(json));
  selectedId = null;
  selectedVerts = [];
  if (enemyIndex >= doc.enemies.length) enemyIndex = 0;
  markDirty();
  refreshAll();
}

function undo() {
  if (!undoStack.length) return;
  endUndo();
  redoStack.push(snapshot());
  restore(undoStack.pop());
  updateUndoButtons();
}

function redo() {
  if (!redoStack.length) return;
  undoStack.push(snapshot());
  restore(redoStack.pop());
  updateUndoButtons();
}

function updateUndoButtons() {
  btnUndo.disabled = undoStack.length === 0;
  btnRedo.disabled = redoStack.length === 0;
}

function activeEnemy() {
  return doc.enemies[enemyIndex];
}

function setMode(mode) {
  editorMode = mode;
  document.getElementById("btn-mode-layout").classList.toggle("active", mode === "layout");
  document.getElementById("btn-mode-anim").classList.toggle("active", mode === "anim");
  document.getElementById("layout-left").hidden = mode !== "layout";
  document.getElementById("anim-left").hidden = mode !== "anim";
  document.getElementById("draw-mode-group").hidden = mode !== "layout";
  document.getElementById("overhead-panel").hidden = mode !== "layout";
  document.getElementById("center-title").textContent =
    mode === "layout" ? `Map ${doc.activeLevel}` : "Enemy";
  document.getElementById("hint").textContent =
    mode === "layout"
      ? "Click canvas · WASD fly along look · Q/E camera up · RMB look · LMB move · R face · Del delete"
      : "Click vert to select · drag axis to move · X/Y/Z nudge (Shift = −) · [ ] or ← → frames · RMB orbit";
  layoutView.enabled = mode === "layout";
  animView.enabled = mode === "anim";
  refreshAll();
}

function setDrawMode(local) {
  localDraw = local;
  document.getElementById("btn-draw-all").classList.toggle("active", !local);
  document.getElementById("btn-draw-local").classList.toggle("active", local);
  const cam = layoutView.camera;
  const room = currentRoom(doc, cam);
  if (local && !room) setStatus("Local: camera is not inside a room", true);
  else setStatus(local ? "Local draw" : "All rooms");
  refreshAll();
}

function buildPalette() {
  const root = document.getElementById("item-palette");
  root.innerHTML = "";
  for (const kind of PALETTE_ORDER) {
    const el = document.createElement("button");
    el.type = "button";
    el.className = "palette-item";
    el.textContent = KINDS[kind].label;
    el.style.borderColor = KINDS[kind].color;
    el.addEventListener("click", () => placeKind(kind));
    root.appendChild(el);
  }
}

function placeKind(kind) {
  pushUndo();
  const p = layoutView.placeInFront(kind);
  const obj = createObject(kind, p.x, p.y, p.z);
  obj.y = Math.max(0, obj.y);
  clampObject(obj);
  activeMap(doc).objects.push(obj);
  selectedId = obj.id;
  markDirty();
  refreshAll();
}

function selectedObject() {
  return activeMap(doc).objects.find((o) => o.id === selectedId) || null;
}

function deleteSelected() {
  if (editorMode === "layout") {
    if (!selectedId) return;
    pushUndo();
    activeMap(doc).objects = activeMap(doc).objects.filter((o) => o.id !== selectedId);
    selectedId = null;
    markDirty();
    refreshAll();
    return;
  }
  const e = activeEnemy();
  if (selectedVerts.length === 1) {
    /* keep verts; topology stays */
  }
}

function duplicateSelected() {
  const obj = selectedObject();
  if (!obj) return;
  pushUndo();
  const copy = clampObject({ ...obj, id: uid(), x: obj.x + 2, z: obj.z + 2 });
  activeMap(doc).objects.push(copy);
  selectedId = copy.id;
  markDirty();
  refreshAll();
}

function switchLevel(name) {
  if (!LEVEL_NAMES.includes(name) || name === doc.activeLevel) return;
  doc.activeLevel = name;
  selectedId = null;
  markDirty();
  if (editorMode === "layout") {
    document.getElementById("center-title").textContent = `Map ${doc.activeLevel}`;
  }
  refreshAll();
  setStatus(name);
}

function renderLevelList() {
  const root = document.getElementById("level-list");
  if (!root) return;
  root.classList.add("level-list");
  root.innerHTML = "";
  const title = document.createElement("h2");
  title.textContent = "Levels";
  root.appendChild(title);
  const ul = document.createElement("ul");
  for (const name of LEVEL_NAMES) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = name;
    if (name === doc.activeLevel) btn.className = "active";
    btn.addEventListener("click", () => switchLevel(name));
    li.appendChild(btn);
    ul.appendChild(li);
  }
  root.appendChild(ul);
}

function renderObjectList() {
  const ul = document.getElementById("object-list");
  ul.innerHTML = "";
  for (const obj of activeMap(doc).objects) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = `${KINDS[obj.kind].label}  ${obj.x},${obj.y},${obj.z}`;
    if (obj.id === selectedId) btn.className = "active";
    btn.addEventListener("click", () => {
      selectedId = obj.id;
      refreshPanels();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  }
}

function renderEnemyList() {
  const ul = document.getElementById("enemy-list");
  ul.innerHTML = "";
  doc.enemies.forEach((e, i) => {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = e.name;
    if (i === enemyIndex) btn.className = "active";
    btn.addEventListener("click", () => {
      enemyIndex = i;
      selectedVerts = [];
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  });
}

function field(label, input) {
  const row = document.createElement("label");
  row.className = "field";
  const span = document.createElement("span");
  span.textContent = label;
  row.append(span, input);
  return row;
}

function vec3Field(label, specs) {
  const row = document.createElement("label");
  row.className = "field vec3";
  const span = document.createElement("span");
  span.textContent = label;
  const wrap = document.createElement("div");
  wrap.className = "vec3-inputs";
  for (const s of specs) {
    wrap.appendChild(numInput(s.value, s.onChange, s.min, s.max));
  }
  row.append(span, wrap);
  return row;
}

function numInput(value, onChange, min, max) {
  const inp = document.createElement("input");
  inp.type = "number";
  inp.value = String(value);
  if (min != null) inp.min = String(min);
  if (max != null) inp.max = String(max);
  inp.addEventListener("change", () => onChange(Number(inp.value)));
  return inp;
}

function renderInspector() {
  const root = document.getElementById("right-editors");
  root.innerHTML = "";
  if (editorMode === "layout") {
    const obj = selectedObject();
    const h = document.createElement("h2");
    h.textContent = obj ? KINDS[obj.kind].label : "Inspector";
    root.appendChild(h);
    if (!obj) {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = "Select an object or place one from the palette.";
      root.appendChild(p);
      return;
    }
    const apply = (fn) => {
      pushUndo();
      fn();
      clampObject(obj);
      markDirty();
      refreshAll();
    };
    root.appendChild(
      vec3Field("XYZ", [
        { value: obj.x, onChange: (v) => apply(() => (obj.x = v)), min: 0, max: 255 },
        { value: obj.y, onChange: (v) => apply(() => (obj.y = v)), min: 0, max: 255 },
        { value: obj.z, onChange: (v) => apply(() => (obj.z = v)), min: 0, max: 255 },
      ])
    );
    if (!KINDS[obj.kind].fixed) {
      root.appendChild(
        vec3Field("Size", [
          { value: obj.sx, onChange: (v) => apply(() => (obj.sx = v)), min: 1, max: 256 },
          { value: obj.sy, onChange: (v) => apply(() => (obj.sy = v)), min: 1, max: 256 },
          { value: obj.sz, onChange: (v) => apply(() => (obj.sz = v)), min: 1, max: 256 },
        ])
      );
    } else {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = `Fixed size ${obj.sx}×${obj.sy}×${obj.sz}`;
      root.appendChild(p);
    }
    if (obj.kind === "doorway" || obj.kind === "switch" || obj.kind === "crate") {
      const sel = document.createElement("select");
      for (const f of ["+z", "-z", "+x", "-x"]) {
        const opt = document.createElement("option");
        opt.value = f;
        opt.textContent = f;
        if (obj.face === f) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () => apply(() => (obj.face = sel.value)));
      root.appendChild(field("Face", sel));
    }
    if (obj.kind === "slope") {
      const axis = document.createElement("select");
      for (const a of ["x", "z"]) {
        const opt = document.createElement("option");
        opt.value = a;
        opt.textContent = a.toUpperCase();
        if (obj.axis === a) opt.selected = true;
        axis.appendChild(opt);
      }
      axis.addEventListener("change", () => apply(() => (obj.axis = axis.value)));
      root.appendChild(field("Axis", axis));
      const dir = document.createElement("select");
      for (const d of [1, -1]) {
        const opt = document.createElement("option");
        opt.value = String(d);
        opt.textContent = d === 1 ? "+ run" : "− run";
        if (obj.dir === d) opt.selected = true;
        dir.appendChild(opt);
      }
      dir.addEventListener("change", () => apply(() => (obj.dir = Number(dir.value))));
      root.appendChild(field("Dir", dir));
    }
    const row = document.createElement("div");
    row.className = "btn-row";
    const dup = document.createElement("button");
    dup.type = "button";
    dup.textContent = "Duplicate";
    dup.addEventListener("click", duplicateSelected);
    const del = document.createElement("button");
    del.type = "button";
    del.className = "danger";
    del.textContent = "Delete";
    del.addEventListener("click", deleteSelected);
    row.append(dup, del);
    root.appendChild(row);
    return;
  }

  const e = activeEnemy();
  const h = document.createElement("h2");
  h.textContent = e.name;
  root.appendChild(h);
  const name = document.createElement("input");
  name.type = "text";
  name.value = e.name;
  name.addEventListener("change", () => {
    pushUndo();
    e.name = name.value.slice(0, 24) || "Enemy";
    markDirty();
    refreshAll();
  });
  root.appendChild(field("Name", name));

  const strip = document.createElement("div");
  strip.className = "frame-strip";
  FRAME_NAMES.forEach((n, i) => {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = n;
    if (i === frameIndex) b.className = "active";
    b.addEventListener("click", () => {
      frameIndex = i;
      refreshAll();
    });
    strip.appendChild(b);
  });
  root.appendChild(strip);

  const counts = document.createElement("p");
  counts.className = "muted";
  counts.textContent = `12 verts · 12 lines · 24 frames`;
  root.appendChild(counts);

  if (selectedVerts.length === 1) {
    const vi = selectedVerts[0];
    const v = e.frames[frameIndex][vi];
    const setC = (k, val) => {
      pushUndo();
      v[k] = clampVert(val);
      markDirty();
      refreshAll();
    };
    root.appendChild(
      vec3Field("XYZ", [
        { value: v.x, onChange: (n) => setC("x", n), min: -64, max: 63 },
        { value: v.y, onChange: (n) => setC("y", n), min: -64, max: 63 },
        { value: v.z, onChange: (n) => setC("z", n), min: -64, max: 63 },
      ])
    );
  }

  const row = document.createElement("div");
  row.className = "btn-row";
  const prev = document.createElement("button");
  prev.type = "button";
  prev.textContent = "Prev frame";
  prev.addEventListener("click", () => stepFrame(-1));
  const next = document.createElement("button");
  next.type = "button";
  next.textContent = "Next frame";
  next.addEventListener("click", () => stepFrame(1));
  row.append(prev, next);
  root.appendChild(row);
}

function stepFrame(d) {
  frameIndex = (frameIndex + d + FRAME_NAMES.length) % FRAME_NAMES.length;
  refreshAll();
}

function nudgeVert(axis, delta) {
  const e = activeEnemy();
  const idxs = selectedVerts.length ? selectedVerts : [];
  if (!idxs.length) {
    setStatus("Select a vertex first", true);
    return;
  }
  pushUndo();
  for (const i of idxs) {
    const v = e.frames[frameIndex][i];
    v[axis] = clampVert(v[axis] + delta);
  }
  markDirty();
  refreshAll();
}

function refreshPanels() {
  renderLevelList();
  renderObjectList();
  renderEnemyList();
  renderInspector();
  overheadView.draw();
  if (editorMode === "anim") animView.draw();
}

function refreshAll() {
  refreshPanels();
  if (editorMode === "layout") layoutView.draw();
  else animView.draw();
}

document.getElementById("btn-mode-layout").addEventListener("click", () => setMode("layout"));
document.getElementById("btn-mode-anim").addEventListener("click", () => setMode("anim"));
document.getElementById("btn-draw-all").addEventListener("click", () => setDrawMode(false));
document.getElementById("btn-draw-local").addEventListener("click", () => setDrawMode(true));
document.getElementById("btn-undo").addEventListener("click", undo);
document.getElementById("btn-redo").addEventListener("click", redo);
document.getElementById("btn-save").addEventListener("click", () => {
  saveToStorage(doc);
  downloadJSON(doc);
  dirty = false;
  titleEl.textContent = "Quake64";
  setStatus("Saved");
});
document.getElementById("btn-load").addEventListener("click", () => {
  document.getElementById("file-input").click();
});
document.getElementById("file-input").addEventListener("change", async (e) => {
  const file = e.target.files?.[0];
  e.target.value = "";
  if (!file) return;
  try {
    pushUndo();
    doc = normalizeDocument(await readJSONFile(file));
    selectedId = null;
    enemyIndex = 0;
    markDirty();
    refreshAll();
    setStatus(`Loaded ${file.name}`);
  } catch (err) {
    setStatus(String(err), true);
  }
});

window.addEventListener("keydown", (e) => {
  if (e.target.matches("input, select, textarea")) return;
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "z") {
    e.preventDefault();
    if (e.shiftKey) redo();
    else undo();
    return;
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "y") {
    e.preventDefault();
    redo();
    return;
  }
  if (e.key === "Delete" || e.key === "Backspace") {
    if (editorMode === "layout") {
      e.preventDefault();
      deleteSelected();
    }
  }
  if (e.key.toLowerCase() === "r" && editorMode === "layout") {
    const obj = selectedObject();
    if (obj && (obj.kind === "doorway" || obj.kind === "switch" || obj.kind === "crate")) {
      e.preventDefault();
      pushUndo();
      obj.face = cycleFace(obj.face, 1);
      clampObject(obj);
      markDirty();
      refreshAll();
    }
    if (obj && obj.kind === "slope") {
      e.preventDefault();
      pushUndo();
      if (obj.axis === "z" && obj.dir === 1) obj.dir = -1;
      else if (obj.axis === "z") {
        obj.axis = "x";
        obj.dir = 1;
      } else if (obj.dir === 1) obj.dir = -1;
      else {
        obj.axis = "z";
        obj.dir = 1;
      }
      clampObject(obj);
      markDirty();
      refreshAll();
    }
  }
  if (editorMode === "anim") {
    if (e.key === "[" || e.key === "," || e.key === "ArrowLeft") {
      e.preventDefault();
      stepFrame(-1);
      return;
    }
    if (e.key === "]" || e.key === "." || e.key === "ArrowRight") {
      e.preventDefault();
      stepFrame(1);
      return;
    }
    const k = e.key.toLowerCase();
    if (k === "x" || k === "y" || k === "z") {
      e.preventDefault();
      nudgeVert(k, e.shiftKey ? -1 : 1);
      return;
    }
  }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "d" && editorMode === "layout") {
    e.preventDefault();
    duplicateSelected();
  }
});

buildPalette();
setMode("layout");
updateUndoButtons();
setStatus("Ready");

// Keep overhead in sync while flying
setInterval(() => {
  if (editorMode === "layout") overheadView.draw();
}, 80);
