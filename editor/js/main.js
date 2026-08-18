import {
  KINDS,
  PALETTE_ORDER,
  FRAME_NAMES,
  ENEMY_TYPES,
  ENEMY_FACINGS,
  clampEnemyRot,
  clampObject,
  clampTriggerText,
  clampName,
  clampTag,
  clampElevType,
  clampVert,
  C64_HEX,
  C64_NAMES,
  ROOM_SKY_DEFAULT,
  ROOM_FLOOR_DEFAULT,
  ROOM_LINE_DEFAULT,
  MAX_TRIGGER_TEXT,
  MAX_NAME_LEN,
  MAX_TAG_LEN,
  ELEV_TYPES,
  createObject,
  createDefaultDocument,
  currentRoom,
  cycleFace,
  normalizeDocument,
  uid,
  LEVEL_NAMES,
  activeMap,
  clipForFrame,
  flipFrameX,
  isFigureObject,
  objectLabel,
  objectTree,
  roomUnderObject,
  usesLinkTag,
} from "./model.js";
import {
  autosaveDocJSON,
  DEFAULT_DOC_PATH,
  docFileName,
  getStoredDocHandle,
  hasDocFileHandle,
  loadDocJSON,
  saveDocJSON,
  tryRestoreDocFile,
  allowStoredDocFile,
} from "./io.js";
import { LayoutView } from "./layoutView.js";
import { OverheadView } from "./overheadView.js";
import { AnimView } from "./animView.js";

const statusEl = document.getElementById("status");
const titleEl = document.querySelector(".toolbar h1");
const btnUndo = document.getElementById("btn-undo");
const btnRedo = document.getElementById("btn-redo");
const UNDO_LIMIT = 40;
const AUTOSAVE_MS = 8000;

let doc = createDefaultDocument();
let editorMode = "layout";
let localDraw = false;
let selectedIds = [];
let pendingPlace = null;
let enemyIndex = 0;
let frameIndex = 0;
let selectedVerts = [];
let dirty = false;
let saving = false;
let autosaveTimer = null;
let undoStack = [];
let redoStack = [];
let undoGesture = false;
let frameClipboard = null;
let animPlaying = false;
let animPlayTimer = null;
/** Collapsed room ids in the Objects tree. */
const collapsedRooms = new Set();

const layoutView = new LayoutView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getDoc: () => doc,
  getSelectedIds: () => selectedIds,
  getLocalMode: () => localDraw && editorMode === "layout",
  onSelectIds: (ids, additive) => {
    if (additive) {
      for (const id of ids) {
        if (!selectedIds.includes(id)) selectedIds.push(id);
      }
    } else selectedIds = [...ids];
    markDirty();
    refreshPanels();
  },
  onToggleSelect: (id) => {
    const i = selectedIds.indexOf(id);
    if (i >= 0) selectedIds.splice(i, 1);
    else selectedIds.push(id);
    markDirty();
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onViewChanged: () => {
    syncEditorToDoc();
    markDirty();
  },
  onStatus: setStatus,
  beginUndo,
  endUndo,
});

const overheadView = new OverheadView(document.getElementById("overhead-canvas"), {
  getDoc: () => doc,
  getCamera: () => layoutView.camera,
  getSelectedId: () => (selectedIds.length ? selectedIds[selectedIds.length - 1] : null),
  getSelectedIds: () => selectedIds,
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
    markDirty();
    refreshPanels();
  },
  onSelectVerts: (indices, additive) => {
    if (additive) {
      for (const i of indices) {
        if (!selectedVerts.includes(i)) selectedVerts.push(i);
      }
    } else selectedVerts = [...indices];
    markDirty();
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onViewChanged: () => {
    syncEditorToDoc();
    markDirty();
  },
  beginUndo,
  endUndo,
});

function setStatus(msg, isError = false) {
  statusEl.textContent = msg || "";
  statusEl.classList.toggle("error", isError);
}

function updateDirtyIndicator() {
  const star = dirty ? "*" : "";
  if (titleEl) titleEl.textContent = `Quake64${star}`;
  document.title = dirty ? "Quake64 *" : "Quake64 Editor";
}

function markDirty() {
  if (!dirty) {
    dirty = true;
    updateDirtyIndicator();
  }
  scheduleAutosave();
}

function markClean() {
  dirty = false;
  updateDirtyIndicator();
  clearAutosaveTimer();
}

function clearAutosaveTimer() {
  if (autosaveTimer) {
    clearTimeout(autosaveTimer);
    autosaveTimer = null;
  }
}

function isEditingField(el = document.activeElement) {
  return (
    el instanceof HTMLInputElement ||
    el instanceof HTMLTextAreaElement ||
    el instanceof HTMLSelectElement ||
    !!el?.isContentEditable
  );
}

function scheduleAutosave() {
  clearAutosaveTimer();
  if (!dirty || isEditingField()) return;
  autosaveTimer = setTimeout(() => {
    autosaveTimer = null;
    void runAutosave();
  }, AUTOSAVE_MS);
}

async function runAutosave() {
  if (!dirty || saving || !hasDocFileHandle()) return;
  if (isEditingField()) {
    scheduleAutosave();
    return;
  }
  await saveNow("Autosaved");
}

document.addEventListener("focusin", (e) => {
  if (isEditingField(e.target)) clearAutosaveTimer();
});
document.addEventListener("focusout", () => {
  requestAnimationFrame(() => {
    if (dirty && !isEditingField()) scheduleAutosave();
  });
});

function syncEditorToDoc() {
  const cam = layoutView.camera;
  const orb = animView.orbit;
  const enemy = doc.enemies[enemyIndex];
  doc.editor = {
    mode: editorMode,
    localDraw,
    selectedIds: [...selectedIds],
    enemy: enemy?.name || "Grunt",
    frameIndex,
    selectedVerts: [...selectedVerts],
    layoutCamera: {
      x: cam.x,
      y: cam.y,
      z: cam.z,
      yaw: cam.yaw,
      pitch: cam.pitch,
      speed: cam.speed,
    },
    animOrbit: { yaw: orb.yaw, pitch: orb.pitch, dist: orb.dist },
  };
}

function applyEditorState(d) {
  const ed = d.editor;
  const cam = layoutView.camera;
  const lc = ed.layoutCamera;
  cam.x = lc.x;
  cam.y = lc.y;
  cam.z = lc.z;
  cam.yaw = lc.yaw;
  cam.pitch = lc.pitch;
  cam.speed = lc.speed;
  const orb = animView.orbit;
  orb.yaw = ed.animOrbit.yaw;
  orb.pitch = ed.animOrbit.pitch;
  orb.dist = ed.animOrbit.dist;
  const ei = d.enemies.findIndex((e) => e.name === ed.enemy);
  enemyIndex = ei >= 0 ? ei : 0;
  frameIndex = ed.frameIndex;
  const have = new Set(activeMap(d).objects.map((o) => o.id));
  selectedIds = ed.selectedIds.filter((id) => have.has(id));
  selectedVerts = [...ed.selectedVerts];
  setDrawMode(ed.localDraw);
  setMode(ed.mode);
}

async function saveNow(okMsg = "Saved") {
  if (saving) return;
  saving = true;
  try {
    syncEditorToDoc();
    const how = hasDocFileHandle()
      ? await autosaveDocJSON(doc)
      : await saveDocJSON(doc, DEFAULT_DOC_PATH);
    if (!how) {
      setStatus("Save cancelled", true);
      return;
    }
    markClean();
    setStatus(`${okMsg} ${docFileName()}`);
  } catch (err) {
    setStatus(String(err.message || err), true);
    scheduleAutosave();
  } finally {
    saving = false;
  }
}

function snapshot() {
  return JSON.stringify({
    version: doc.version,
    activeLevel: doc.activeLevel,
    maps: doc.maps,
    enemies: doc.enemies,
  });
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
  const have = new Set(activeMap(doc).objects.map((o) => o.id));
  selectedIds = selectedIds.filter((id) => have.has(id));
  selectedVerts = selectedVerts.filter((i) => i >= 0 && i < 13);
  if (enemyIndex >= doc.enemies.length) enemyIndex = 0;
  syncEditorToDoc();
  markDirty();
  refreshAll();
}

function clearUndoHistory() {
  undoStack.length = 0;
  redoStack.length = 0;
  undoGesture = false;
  updateUndoButtons();
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
    mode === "layout"
      ? (() => {
          const map = activeMap(doc);
          return map.name ? `Map ${doc.activeLevel} — ${map.name}` : `Map ${doc.activeLevel}`;
        })()
      : "Enemy";
  document.getElementById("hint").textContent =
    mode === "layout"
      ? "Drag palette to place · LMB line/box-select · Shift add · WASD/wheel fly · Q/E up · RMB look · MMB orbit · F focus · G drop · gizmo moves selection · Del"
      : "LMB box-select verts · click-drag unselected on camera plane · gizmo moves selection · X/Y/Z nudge · [ ] frames · RMB orbit";
  layoutView.enabled = mode === "layout";
  animView.enabled = mode === "anim";
  if (mode !== "anim") stopAnimPlay();
  refreshAll();
}

function setOrthoMode(mode) {
  overheadView.setMode(mode);
  document.getElementById("btn-ortho-top").classList.toggle("active", mode === "top");
  document.getElementById("btn-ortho-left").classList.toggle("active", mode === "left");
  document.getElementById("btn-ortho-forward").classList.toggle("active", mode === "forward");
  const hint = document.getElementById("ortho-hint");
  if (hint) hint.textContent = overheadView.hint();
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
    root.appendChild(paletteButton(KINDS[kind].label, KINDS[kind].color, { kind }));
  }
  const sep = document.createElement("div");
  sep.className = "palette-sep";
  sep.textContent = "Enemies";
  root.appendChild(sep);
  for (const t of ENEMY_TYPES) {
    root.appendChild(paletteButton(t.name, KINDS.enemy.color, { kind: "enemy", enemy: t.name }));
  }
}

function paletteButton(label, color, payload) {
  const el = document.createElement("button");
  el.type = "button";
  el.className = "palette-item";
  el.textContent = label;
  el.style.borderColor = color;
  el.title = "Drag onto the map to place";
  el.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    e.preventDefault();
    pendingPlace = { ...payload, pointerId: e.pointerId };
    el.setPointerCapture(e.pointerId);
    setStatus(`Drop ${label} on the map…`);
  });
  el.addEventListener("pointerup", (e) => {
    if (!pendingPlace || pendingPlace.pointerId !== e.pointerId) return;
    finishPaletteDrop(e);
  });
  el.addEventListener("pointercancel", () => {
    pendingPlace = null;
  });
  return el;
}

function finishPaletteDrop(e) {
  const place = pendingPlace;
  pendingPlace = null;
  if (!place || editorMode !== "layout") return;
  const canvas = document.getElementById("view-canvas");
  const rect = canvas.getBoundingClientRect();
  if (
    e.clientX < rect.left ||
    e.clientX > rect.right ||
    e.clientY < rect.top ||
    e.clientY > rect.bottom
  ) {
    setStatus("Place cancelled", true);
    return;
  }
  const mx = ((e.clientX - rect.left) / rect.width) * layoutView.cssW;
  const my = ((e.clientY - rect.top) / rect.height) * layoutView.cssH;
  const kind = place.kind;
  const p = layoutView.placeAtScreen(mx, my, kind);
  pushUndo();
  const obj = createObject(kind, p.x, p.y, p.z, place.enemy ? { enemy: place.enemy } : {});
  clampObject(obj);
  activeMap(doc).objects.push(obj);
  selectedIds = [obj.id];
  markDirty();
  refreshAll();
  setStatus(
    place.enemy ? `Placed ${place.enemy}` : `Placed ${KINDS[kind].label}`
  );
}

function selectedObject() {
  if (selectedIds.length !== 1) return null;
  return activeMap(doc).objects.find((o) => o.id === selectedIds[0]) || null;
}

function deleteSelected() {
  if (editorMode === "layout") {
    if (!selectedIds.length) return;
    pushUndo();
    const drop = new Set(selectedIds);
    activeMap(doc).objects = activeMap(doc).objects.filter((o) => !drop.has(o.id));
    selectedIds = [];
    markDirty();
    refreshAll();
    return;
  }
}

function duplicateSelected() {
  if (!selectedIds.length) return;
  pushUndo();
  const created = [];
  for (const id of selectedIds) {
    const obj = activeMap(doc).objects.find((o) => o.id === id);
    if (!obj) continue;
    const copy = clampObject({
      ...obj,
      id: uid(),
      x: obj.x + 2,
      z: obj.z + 2,
    });
    activeMap(doc).objects.push(copy);
    created.push(copy.id);
  }
  selectedIds = created;
  markDirty();
  refreshAll();
}

function dropSelectedToFloor() {
  if (!selectedIds.length || editorMode !== "layout") return;
  pushUndo();
  let n = 0;
  for (const id of selectedIds) {
    const obj = activeMap(doc).objects.find((o) => o.id === id);
    if (!obj || obj.kind === "room") continue;
    const room = roomUnderObject(doc, obj);
    obj.y = room ? room.y : 0;
    clampObject(obj);
    n++;
  }
  if (!n) {
    endUndo();
    undoStack.pop();
    updateUndoButtons();
    setStatus("Nothing to drop", true);
    return;
  }
  markDirty();
  refreshAll();
  setStatus(`Dropped ${n} to floor`);
}

function switchLevel(name) {
  if (!LEVEL_NAMES.includes(name) || name === doc.activeLevel) return;
  doc.activeLevel = name;
  selectedIds = [];
  collapsedRooms.clear();
  markDirty();
  if (editorMode === "layout") {
    const map = activeMap(doc);
    document.getElementById("center-title").textContent = map.name
      ? `Map ${doc.activeLevel} — ${map.name}`
      : `Map ${doc.activeLevel}`;
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
    const map = doc.maps[name];
    const display = clampName(map?.name);
    btn.textContent = display ? `${name}` : name;
    btn.title = display ? `${name} — ${display}` : name;
    if (display) {
      const sub = document.createElement("span");
      sub.className = "level-sub";
      sub.textContent = display;
      btn.appendChild(document.createElement("br"));
      btn.appendChild(sub);
    }
    if (name === doc.activeLevel) btn.className = "active";
    btn.addEventListener("click", () => switchLevel(name));
    li.appendChild(btn);
    ul.appendChild(li);
  }
  root.appendChild(ul);
}

function selectObjectIds(ids, additive) {
  if (additive) {
    for (const id of ids) {
      const i = selectedIds.indexOf(id);
      if (i >= 0) selectedIds.splice(i, 1);
      else selectedIds.push(id);
    }
  } else selectedIds = [...ids];
  markDirty();
  refreshPanels();
}

function makeObjectListButton(obj) {
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = objectLabel(obj);
  btn.classList.add(obj.kind === "room" ? "tree-label-wrap" : "tree-label-elide");
  if (selectedIds.includes(obj.id)) btn.classList.add("active");
  btn.addEventListener("click", (e) => {
    selectObjectIds([obj.id], e.shiftKey);
  });
  return btn;
}

function renderObjectList() {
  const ul = document.getElementById("object-list");
  ul.innerHTML = "";
  ul.classList.add("object-tree");
  const { nodes, orphans } = objectTree(doc);

  for (const { room, children } of nodes) {
    const li = document.createElement("li");
    li.className = "tree-room";
    const row = document.createElement("div");
    row.className = "tree-row";
    const twist = document.createElement("button");
    twist.type = "button";
    twist.className = "tree-twist";
    const collapsed = collapsedRooms.has(room.id);
    twist.textContent = collapsed ? "▸" : "▾";
    twist.title = collapsed ? "Expand" : "Collapse";
    twist.addEventListener("click", (e) => {
      e.stopPropagation();
      if (collapsedRooms.has(room.id)) collapsedRooms.delete(room.id);
      else collapsedRooms.add(room.id);
      renderObjectList();
    });
    const roomBtn = makeObjectListButton(room);
    roomBtn.classList.add("tree-room-btn");
    row.append(twist, roomBtn);
    li.appendChild(row);
    if (!collapsed) {
      const childUl = document.createElement("ul");
      childUl.className = "tree-children";
      if (!children.length) {
        const empty = document.createElement("li");
        empty.className = "tree-empty";
        empty.textContent = "(empty)";
        childUl.appendChild(empty);
      } else {
        for (const obj of children) {
          const cli = document.createElement("li");
          cli.appendChild(makeObjectListButton(obj));
          childUl.appendChild(cli);
        }
      }
      li.appendChild(childUl);
    }
    ul.appendChild(li);
  }

  if (orphans.length) {
    const li = document.createElement("li");
    li.className = "tree-orphans";
    const label = document.createElement("div");
    label.className = "tree-orphan-label";
    label.textContent = "Outside rooms";
    li.appendChild(label);
    const childUl = document.createElement("ul");
    childUl.className = "tree-children";
    for (const obj of orphans) {
      const cli = document.createElement("li");
      cli.appendChild(makeObjectListButton(obj));
      childUl.appendChild(cli);
    }
    li.appendChild(childUl);
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
      markDirty();
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

function colorPicker(label, value, onPick) {
  const wrap = document.createElement("div");
  wrap.className = "field color-field";
  const span = document.createElement("span");
  span.textContent = label;
  const row = document.createElement("div");
  row.className = "color-swatches";
  for (let i = 0; i < 16; i++) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "swatch" + (i === value ? " selected" : "");
    btn.title = `${i}: ${C64_NAMES[i]}`;
    btn.dataset.color = String(i);
    btn.style.background = C64_HEX[i];
    btn.addEventListener("click", () => onPick(i));
    row.appendChild(btn);
  }
  wrap.append(span, row);
  return wrap;
}

function renderInspector() {
  const root = document.getElementById("right-editors");
  root.innerHTML = "";
  if (editorMode === "layout") {
    const obj = selectedObject();
    const h = document.createElement("h2");
    h.textContent = obj
      ? obj.kind === "enemy"
        ? obj.enemy || "Enemy"
        : KINDS[obj.kind].label
      : "Inspector";
    root.appendChild(h);
    if (selectedIds.length > 1) {
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = `${selectedIds.length} selected`;
      root.appendChild(p);
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
    if (!obj) {
      const map = activeMap(doc);
      const p = document.createElement("p");
      p.className = "muted";
      p.textContent = `Map ${doc.activeLevel}. Select an object or drag one from the palette.`;
      root.appendChild(p);
      const nameInp = document.createElement("input");
      nameInp.type = "text";
      nameInp.maxLength = MAX_NAME_LEN;
      nameInp.value = map.name || "";
      nameInp.placeholder = "Display name";
      nameInp.addEventListener("change", () => {
        pushUndo();
        map.name = clampName(nameInp.value);
        markDirty();
        refreshAll();
      });
      root.appendChild(field("Name", nameInp));
      return;
    }
    const apply = (fn) => {
      pushUndo();
      fn();
      clampObject(obj);
      markDirty();
      refreshAll();
    };
    if (obj.kind === "room") {
      const nameInp = document.createElement("input");
      nameInp.type = "text";
      nameInp.maxLength = MAX_NAME_LEN;
      nameInp.value = obj.name || "";
      nameInp.placeholder = "Display name";
      nameInp.addEventListener("change", () => apply(() => (obj.name = clampName(nameInp.value))));
      root.appendChild(field("Name", nameInp));
      root.appendChild(
        colorPicker("Sky", obj.skyColor ?? ROOM_SKY_DEFAULT, (v) =>
          apply(() => {
            obj.skyColor = v;
          })
        )
      );
      root.appendChild(
        colorPicker("Floor", obj.floorColor ?? ROOM_FLOOR_DEFAULT, (v) =>
          apply(() => {
            obj.floorColor = v;
          })
        )
      );
      root.appendChild(
        colorPicker("Lines", obj.lineColor ?? ROOM_LINE_DEFAULT, (v) =>
          apply(() => {
            obj.lineColor = v;
          })
        )
      );
    }
    if (obj.kind === "enemy") {
      const sel = document.createElement("select");
      for (const t of ENEMY_TYPES) {
        const opt = document.createElement("option");
        opt.value = t.name;
        opt.textContent = t.name;
        if (obj.enemy === t.name) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () => apply(() => (obj.enemy = sel.value)));
      root.appendChild(field("Type", sel));
    }
    if (isFigureObject(obj) || obj.kind === "teleporter_dest") {
      const rotWrap = document.createElement("div");
      rotWrap.className = "vec3-inputs";
      const rotInp = numInput(obj.rot ?? 0, (v) => apply(() => (obj.rot = v)), 0, 7);
      const rotLbl = document.createElement("span");
      rotLbl.className = "rot-label";
      rotLbl.textContent = ENEMY_FACINGS[clampEnemyRot(obj.rot ?? 0)];
      rotWrap.append(rotInp, rotLbl);
      root.appendChild(field("Rot", rotWrap));
    }
    root.appendChild(
      vec3Field("XYZ", [
        { value: obj.x, onChange: (v) => apply(() => (obj.x = v)), min: 0, max: 255 },
        { value: obj.y, onChange: (v) => apply(() => (obj.y = v)), min: 0, max: 255 },
        { value: obj.z, onChange: (v) => apply(() => (obj.z = v)), min: 0, max: 255 },
      ])
    );
    if (obj.kind === "trigger") {
      const ta = document.createElement("textarea");
      ta.rows = 3;
      ta.maxLength = MAX_TRIGGER_TEXT;
      ta.value = obj.text || "";
      ta.placeholder = "Shown while inside";
      ta.addEventListener("change", () => apply(() => (obj.text = clampTriggerText(ta.value))));
      const row = field("Text", ta);
      row.classList.add("block");
      root.appendChild(row);
    }
    if (usesLinkTag(obj.kind)) {
      const tagInp = document.createElement("input");
      tagInp.type = "text";
      tagInp.maxLength = MAX_TAG_LEN;
      tagInp.value = obj.tag || "";
      tagInp.placeholder =
        obj.kind === "switch" || obj.kind === "elevator"
          ? "elevator link"
          : obj.kind === "key"
            ? "key id"
            : "teleporter link";
      tagInp.addEventListener("change", () => apply(() => (obj.tag = clampTag(tagInp.value))));
      root.appendChild(field("Tag", tagInp));
    }
    if (obj.kind === "elevator") {
      const sel = document.createElement("select");
      for (const t of ELEV_TYPES) {
        const opt = document.createElement("option");
        opt.value = t;
        opt.textContent = t;
        if (clampElevType(obj.elevType) === t) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () => apply(() => (obj.elevType = sel.value)));
      root.appendChild(field("Type", sel));
    }
    if (obj.kind === "doorway") {
      const lock = document.createElement("input");
      lock.type = "checkbox";
      lock.checked = !!obj.locked;
      lock.addEventListener("change", () => apply(() => (obj.locked = lock.checked)));
      root.appendChild(field("Locked", lock));
      const keyInp = document.createElement("input");
      keyInp.type = "text";
      keyInp.maxLength = MAX_TAG_LEN;
      keyInp.value = obj.keyTag || "";
      keyInp.placeholder = "key tag";
      keyInp.disabled = !obj.locked;
      keyInp.addEventListener("change", () => apply(() => (obj.keyTag = clampTag(keyInp.value))));
      root.appendChild(field("Key", keyInp));
    }
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
      markDirty();
      refreshAll();
    });
    strip.appendChild(b);
  });
  root.appendChild(strip);

  const counts = document.createElement("p");
  counts.className = "muted";
  const clip = clipForFrame(frameIndex);
  const height = frameHeight(e.frames[frameIndex]);
  counts.textContent = `13 verts · 13 lines · ${clip.name} · height ${height} · 24 frames`;
  root.appendChild(counts);

  const scaleRow = document.createElement("label");
  scaleRow.className = "field";
  const scaleLbl = document.createElement("span");
  scaleLbl.textContent = "Scale";
  const scaleInp = document.createElement("input");
  scaleInp.type = "number";
  scaleInp.step = "0.1";
  scaleInp.placeholder = "1.0";
  scaleInp.title = "Scale this frame, then clears";
  scaleInp.addEventListener("change", () => {
    scaleCurrentFrame(Number(scaleInp.value));
    scaleInp.value = "";
  });
  scaleRow.append(scaleLbl, scaleInp);
  root.appendChild(scaleRow);

  const editRow = document.createElement("div");
  editRow.className = "btn-row";
  const copyBtn = document.createElement("button");
  copyBtn.type = "button";
  copyBtn.textContent = "Copy frame";
  copyBtn.addEventListener("click", copyFrame);
  const pasteBtn = document.createElement("button");
  pasteBtn.type = "button";
  pasteBtn.textContent = "Paste frame";
  pasteBtn.disabled = !frameClipboard;
  pasteBtn.addEventListener("click", pasteFrame);
  const flipBtn = document.createElement("button");
  flipBtn.type = "button";
  flipBtn.textContent = "Flip";
  flipBtn.title = "Mirror this frame on X; weapon stays on the right wrist";
  flipBtn.addEventListener("click", flipCurrentFrame);
  editRow.append(copyBtn, pasteBtn, flipBtn);
  root.appendChild(editRow);

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
  const playBtn = document.createElement("button");
  playBtn.type = "button";
  playBtn.textContent = animPlaying ? "Pause" : "Play";
  if (animPlaying) playBtn.className = "active";
  playBtn.addEventListener("click", toggleAnimPlay);
  const prev = document.createElement("button");
  prev.type = "button";
  prev.textContent = "Prev frame";
  prev.addEventListener("click", () => stepFrame(-1));
  const next = document.createElement("button");
  next.type = "button";
  next.textContent = "Next frame";
  next.addEventListener("click", () => stepFrame(1));
  row.append(playBtn, prev, next);
  root.appendChild(row);
}

function frameHeight(verts) {
  let maxY = -Infinity;
  for (const v of verts) {
    if (v.y > maxY) maxY = v.y;
  }
  return Number.isFinite(maxY) ? maxY : 0;
}

function stepFrame(d) {
  frameIndex = (frameIndex + d + FRAME_NAMES.length) % FRAME_NAMES.length;
  markDirty();
  refreshAll();
}

function scaleCurrentFrame(factor) {
  if (!Number.isFinite(factor) || factor === 0) {
    setStatus("Enter a non-zero scale", true);
    return;
  }
  const e = activeEnemy();
  const fr = e.frames[frameIndex];
  pushUndo();
  for (const v of fr) {
    v.x = clampVert(Math.round(v.x * factor));
    v.y = clampVert(Math.round(v.y * factor));
    v.z = clampVert(Math.round(v.z * factor));
  }
  markDirty();
  refreshAll();
  setStatus(`Scaled ${FRAME_NAMES[frameIndex]} × ${factor}`);
}

function copyFrame() {
  const fr = activeEnemy().frames[frameIndex];
  frameClipboard = fr.map((v) => ({ x: v.x, y: v.y, z: v.z }));
  setStatus(`Copied ${FRAME_NAMES[frameIndex]}`);
  refreshPanels();
}

function pasteFrame() {
  if (!frameClipboard) {
    setStatus("Copy a frame first", true);
    return;
  }
  const fr = activeEnemy().frames[frameIndex];
  pushUndo();
  for (let i = 0; i < fr.length; i++) {
    const src = frameClipboard[i] || fr[i];
    fr[i].x = clampVert(src.x);
    fr[i].y = clampVert(src.y);
    fr[i].z = clampVert(src.z);
  }
  markDirty();
  refreshAll();
  setStatus(`Pasted onto ${FRAME_NAMES[frameIndex]}`);
}

function flipCurrentFrame() {
  const e = activeEnemy();
  pushUndo();
  flipFrameX(e.frames[frameIndex]);
  markDirty();
  refreshAll();
  setStatus(`Flipped ${FRAME_NAMES[frameIndex]} on X`);
}

function stopAnimPlay() {
  animPlaying = false;
  if (animPlayTimer) {
    clearInterval(animPlayTimer);
    animPlayTimer = null;
  }
}

function toggleAnimPlay() {
  if (animPlaying) {
    stopAnimPlay();
    refreshPanels();
    setStatus("Paused");
    return;
  }
  animPlaying = true;
  animPlayTimer = setInterval(tickAnimPlay, 500);
  refreshPanels();
  setStatus(`Playing ${clipForFrame(frameIndex).name}`);
}

function tickAnimPlay() {
  if (editorMode !== "anim") {
    stopAnimPlay();
    return;
  }
  const clip = clipForFrame(frameIndex);
  const local = frameIndex - clip.start;
  frameIndex = clip.start + ((local + 1) % clip.len);
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

document.getElementById("btn-mode-layout").addEventListener("click", () => {
  setMode("layout");
  markDirty();
});
document.getElementById("btn-mode-anim").addEventListener("click", () => {
  setMode("anim");
  markDirty();
});
document.getElementById("btn-draw-all").addEventListener("click", () => {
  setDrawMode(false);
  markDirty();
});
document.getElementById("btn-draw-local").addEventListener("click", () => {
  setDrawMode(true);
  markDirty();
});
document.getElementById("btn-ortho-top").addEventListener("click", () => setOrthoMode("top"));
document.getElementById("btn-ortho-left").addEventListener("click", () => setOrthoMode("left"));
document.getElementById("btn-ortho-forward").addEventListener("click", () => setOrthoMode("forward"));
document.getElementById("btn-undo").addEventListener("click", undo);
document.getElementById("btn-redo").addEventListener("click", redo);
document.getElementById("btn-save").addEventListener("click", async () => {
  await saveNow("Saved");
});

function applyLoadedDoc(loaded) {
  doc = normalizeDocument(loaded);
  applyEditorState(doc);
  clearUndoHistory();
  markClean();
  refreshAll();
  setStatus(`Loaded ${docFileName()}`);
}

function showFileAccessGate(storedHandle) {
  const overlay = document.createElement("div");
  overlay.className = "file-gate";
  overlay.innerHTML = `
    <div class="file-gate-card" role="dialog" aria-modal="true" aria-labelledby="file-gate-title">
      <h2 id="file-gate-title">Open map file</h2>
      <p class="muted">
        ${
          storedHandle
            ? `Browser needs permission to read/write <strong>${storedHandle.name}</strong>.`
            : `Choose project file <strong>${DEFAULT_DOC_PATH}</strong> (usually in the editor folder).`
        }
      </p>
      <div class="btn-row">
        <button type="button" class="file-gate-primary" id="file-gate-ok">
          ${storedHandle ? `Allow ${storedHandle.name}` : `Open ${DEFAULT_DOC_PATH}…`}
        </button>
        ${storedHandle ? `<button type="button" id="file-gate-other">Choose different file…</button>` : ""}
      </div>
    </div>
  `;
  document.body.appendChild(overlay);
  const ok = overlay.querySelector("#file-gate-ok");
  const other = overlay.querySelector("#file-gate-other");
  ok.focus();

  const finish = async (loader) => {
    ok.disabled = true;
    if (other) other.disabled = true;
    try {
      const loaded = await loader();
      if (!loaded) {
        ok.disabled = false;
        if (other) other.disabled = false;
        setStatus("Open cancelled", true);
        return;
      }
      overlay.remove();
      applyLoadedDoc(loaded);
    } catch (err) {
      ok.disabled = false;
      if (other) other.disabled = false;
      setStatus(String(err.message || err), true);
    }
  };

  ok.addEventListener("click", () => {
    void finish(() =>
      storedHandle ? allowStoredDocFile(storedHandle) : loadDocJSON()
    );
  });
  other?.addEventListener("click", () => {
    void finish(() => loadDocJSON());
  });
}

document.getElementById("btn-load").addEventListener("click", async () => {
  try {
    const loaded = await loadDocJSON();
    if (!loaded) return;
    applyLoadedDoc(loaded);
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
});

window.addEventListener("keydown", (e) => {
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
    e.preventDefault();
    void saveNow("Saved");
    return;
  }
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
  if (e.key.toLowerCase() === "g" && editorMode === "layout" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    if (selectedIds.length) {
      e.preventDefault();
      dropSelectedToFloor();
      return;
    }
  }
  if (e.key.toLowerCase() === "f" && editorMode === "layout") {
    if (!e.ctrlKey && !e.metaKey && !e.altKey && selectedIds.length) {
      e.preventDefault();
      if (layoutView.focusSelection()) setStatus("Focused selection");
    }
    return;
  }
  if (e.key.toLowerCase() === "r" && editorMode === "layout") {
    const obj = selectedObject();
    if (obj && isFigureObject(obj)) {
      e.preventDefault();
      pushUndo();
      obj.rot = clampEnemyRot((obj.rot ?? 0) + 1);
      markDirty();
      refreshAll();
    }
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

async function boot() {
  updateDirtyIndicator();
  refreshAll();
  try {
    const loaded = await tryRestoreDocFile();
    if (loaded) {
      applyLoadedDoc(loaded);
      return;
    }
    const stored = await getStoredDocHandle();
    showFileAccessGate(stored);
    setStatus(
      stored
        ? `Click Allow to open ${stored.name}`
        : `Open ${DEFAULT_DOC_PATH} to edit the project map`,
      false
    );
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
}

void boot();

setInterval(() => {
  if (editorMode === "layout") overheadView.draw();
}, 80);
