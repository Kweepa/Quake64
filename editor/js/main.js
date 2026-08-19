import {
  KINDS,
  PALETTE_ORDER,
  ENEMY_TYPES,
  ENEMY_FACINGS,
  JOINT_NAMES,
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
  dummyFrameFor,
  isFigureObject,
  objectLabel,
  objectTree,
  roomUnderObject,
  usesLinkTag,
  emptyMdlRig,
  DEFAULT_MDL_SCALE,
  clampMdlScale,
  WEAPON_KEYS,
  WEAPON_LABELS,
  clampWeaponScale,
  DEFAULT_WEAPON_SCALE,
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
  pickSharewareDirectory,
  tryRestoreSharewareDir,
  getStoredSharewareHandle,
  allowStoredSharewareDir,
  sharewareFolderName,
  loadSharewarePakBuffers,
  ensureWeaponsPngDirectory,
  writePngFile,
} from "./io.js";
import { parsePakBuffers } from "./pak.js";
import {
  loadEnemyMdls,
  loadWeaponMdls,
  mdlEditorVerts,
  averageJointPositions,
  filterMdlClips,
  mdlFrameIndexAt,
  buildStickFramesFromMdl,
  resolveWeaponFrames,
  rasterWeaponFrame,
  WEAPON_MDL_PATHS,
  WEAPON_SPRITE_W,
  WEAPON_SPRITE_H,
  mdlQuakeVerts,
  inspectTriNormal,
  inspectQuadPair,
  mdlEnsureQuads,
  QUAD_COPLANAR_DOT,
  QUAD_PLANE_REL,
} from "./mdl.js";
import { LayoutView } from "./layoutView.js";
import { OverheadView } from "./overheadView.js";
import { AnimView } from "./animView.js";
import { WeaponView } from "./weaponView.js";

const statusEl = document.getElementById("status");
const titleEl = document.querySelector(".toolbar h1");
const btnUndo = document.getElementById("btn-undo");
const btnRedo = document.getElementById("btn-redo");
const UNDO_LIMIT = 40;
const AUTOSAVE_MS = 8000;
/** Match Quake monster default: one MDL frame per 0.1s think. */
const ANIM_PLAY_MS = 100;

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
let animLoop = false;
let sharewareModels = {};
let sharewareMissing = [];
let sharewareWeapons = {};
let sharewareWeaponMissing = [];
let overlayOn = true;
let bindJoint = -1;
let clipIndex = 0;
let frameLocal = 0;
let mdlScale = DEFAULT_MDL_SCALE;
let weaponKey = "axe";
let weaponFrame = 0;
let weaponClipWarn = false;
let weaponSelectedVerts = [];
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
  getFrame: () => {
    const e = doc.enemies[enemyIndex];
    if (!e?.clips?.length) return 0;
    return frameIndex;
  },
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
  getMeshOverlay: () => {
    if (!overlayOn) return null;
    const e = doc.enemies[enemyIndex];
    if (!e) return null;
    const mdl = sharewareModels[e.name];
    if (!mdl) return null;
    const timeline = getTimeline(e);
    const clip = timeline[clipIndex] || timeline[0];
    if (!clip) return null;
    const local = Math.max(0, Math.min(frameLocal, clip.len - 1));
    const frameName = clip.frameNames?.[local] || `${clip.name}${local}`;
    const mdlFi = e.clips?.length
      ? mdlFrameIndexAt(mdl, e.clips[clipIndex].start + local)
      : clip.mdlFrames[local]?.index ?? 0;
    const verts = mdlEditorVerts(mdl, mdlFi, mdlScale);
    const rig = e.mdlRig || emptyMdlRig();
    return {
      verts,
      edges: mdl.edges,
      bindJoint,
      jointVerts: rig.jointVerts,
      ghost: averageJointPositions(verts, rig.jointVerts),
      lines: e.lines,
      frameName,
    };
  },
  onSelectMeshVert: (i, additive) => {
    assignMeshVerts([i], additive);
  },
  onSelectMeshVerts: (indices, additive) => {
    assignMeshVerts(indices, additive);
  },
});

const weaponView = new WeaponView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  previewCanvas: document.getElementById("weapon-preview-canvas"),
  getMdl: () => sharewareWeapons[weaponKey] || null,
  getScale: () => doc.weapons.scale,
  getPan: () => {
    const item = doc.weapons.items[weaponKey];
    return item?.pan || { x: 0, y: 0 };
  },
  getPreviewFrame: () => weaponFrame,
  getOnionFrames: () => selectedWeaponFrames(),
  getSelectedVerts: () => weaponSelectedVerts,
  onSelectVerts: (indices, additive) => {
    if (!indices.length) {
      if (!additive) weaponSelectedVerts = [];
    } else if (additive) {
      const set = new Set(weaponSelectedVerts);
      for (const i of indices) set.add(i);
      weaponSelectedVerts = [...set].sort((a, b) => a - b);
    } else weaponSelectedVerts = [...indices].sort((a, b) => a - b);
    refreshPanels();
    if (editorMode === "weapons") weaponView.draw();
  },
  setScale: (v) => {
    doc.weapons.scale = clampWeaponScale(v);
    syncWeaponScaleInputs();
  },
  setPan: (x, y) => {
    const item = ensureWeaponItem(weaponKey);
    item.pan = { x, y };
  },
  beginUndo,
  endUndo,
  onChange: () => {
    markDirty();
  },
  onPanEnd: () => {
    refreshWeaponClipStatus();
  },
  onClipWarn: (clipped) => {
    weaponClipWarn = !!clipped;
    if (editorMode === "weapons") refreshWeaponClipStatus();
  },
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
    mdlScale,
    weapon: weaponKey,
    weaponFrame,
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
  clampFrameIndex(activeEnemy());
  syncClipFromFrameIndex(activeEnemy());
  const have = new Set(activeMap(d).objects.map((o) => o.id));
  selectedIds = ed.selectedIds.filter((id) => have.has(id));
  selectedVerts = [...ed.selectedVerts];
  setMdlScale(ed.mdlScale, false);
  weaponKey = WEAPON_KEYS.includes(ed.weapon) ? ed.weapon : "axe";
  weaponFrame = Math.max(0, ed.weaponFrame | 0);
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
    weapons: doc.weapons,
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
  clampFrameIndex(activeEnemy());
  syncClipFromFrameIndex(activeEnemy());
  clampWeaponPreviewFrame();
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

function getTimeline(e) {
  if (e.clips?.length) {
    const mdl = sharewareModels[e.name];
    const kept = mdl ? filterMdlClips(mdl.clips) : [];
    let ki = 0;
    return e.clips.map((c) => {
      const mdlClip = kept[ki];
      const frameNames = [];
      const mdlFrames = [];
      if (mdlClip && mdlClip.name === c.name) {
        for (const fr of mdlClip.frames) {
          frameNames.push(fr.name);
          mdlFrames.push(fr);
        }
        ki++;
      }
      return { name: c.name, len: c.len, start: c.start, frameNames, mdlFrames };
    });
  }
  const mdl = sharewareModels[e.name];
  if (!mdl) return [];
  return filterMdlClips(mdl.clips).map((c) => ({
    name: c.name,
    len: c.frames.length,
    start: 0,
    frameNames: c.frames.map((fr) => fr.name),
    mdlFrames: c.frames,
  }));
}

function clampFrameIndex(e) {
  if (!e?.frames?.length) {
    frameIndex = 0;
    return;
  }
  if (e.clips?.length) {
    frameIndex = Math.max(0, Math.min(frameIndex, e.frames.length - 1));
  }
}

function syncClipFromFrameIndex(e) {
  const timeline = getTimeline(e);
  if (!timeline.length) {
    clipIndex = 0;
    frameLocal = 0;
    return;
  }
  if (e.clips?.length) {
    const clip = clipForFrame(e.clips, frameIndex);
    if (clip) {
      clipIndex = Math.max(0, e.clips.indexOf(clip));
      frameLocal = frameIndex - clip.start;
      return;
    }
  }
  if (clipIndex >= timeline.length) clipIndex = 0;
  const clip = timeline[clipIndex];
  frameLocal = Math.max(0, Math.min(frameLocal, clip.len - 1));
}

function frameLabel(e, fi) {
  if (!e?.clips?.length) return "rest";
  const clip = clipForFrame(e.clips, fi);
  if (!clip) return `frame ${fi}`;
  return `${clip.name} ${fi - clip.start}`;
}

function activeTimelineClip() {
  const timeline = getTimeline(activeEnemy());
  if (!timeline.length) return null;
  if (clipIndex >= timeline.length) clipIndex = 0;
  return timeline[clipIndex];
}

function setMode(mode) {
  editorMode = mode;
  document.getElementById("btn-mode-layout").classList.toggle("active", mode === "layout");
  document.getElementById("btn-mode-anim").classList.toggle("active", mode === "anim");
  document.getElementById("btn-mode-weapons").classList.toggle("active", mode === "weapons");
  document.getElementById("layout-left").hidden = mode !== "layout";
  document.getElementById("anim-left").hidden = mode !== "anim";
  document.getElementById("weapons-left").hidden = mode !== "weapons";
  document.getElementById("draw-mode-group").hidden = mode !== "layout";
  document.getElementById("overhead-panel").hidden = mode !== "layout";
  document.getElementById("weapon-preview-panel").hidden = mode !== "weapons";
  const map = activeMap(doc);
  document.getElementById("center-title").textContent =
    mode === "layout"
      ? map.name
        ? `Map ${doc.activeLevel} — ${map.name}`
        : `Map ${doc.activeLevel}`
      : mode === "weapons"
        ? WEAPON_LABELS[weaponKey] || "Weapons"
        : "Enemy";
  document.getElementById("hint").textContent =
    mode === "layout"
      ? "Drag palette to place · LMB line/box-select · Shift add · WASD/wheel fly · Q/E up · RMB look · Alt+RMB zoom · MMB orbit · F focus · G drop · gizmo moves selection · Del"
      : mode === "weapons"
        ? "LMB vertex to inspect · Shift add · click empty clears · drag empty pans · wheel scale"
        : bindJoint >= 0
          ? `Box-select mesh verts for ${JOINT_NAMES[bindJoint]} · Shift add · Esc stops bind · RMB orbit`
          : "LMB box-select verts · click-drag unselected on camera plane · gizmo moves selection · X/Y/Z nudge · [ ] frames · RMB orbit · Alt+RMB zoom";
  layoutView.enabled = mode === "layout";
  animView.enabled = mode === "anim";
  weaponView.enabled = mode === "weapons";
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
      const prevClip = activeTimelineClip()?.name;
      enemyIndex = i;
      selectedVerts = [];
      bindJoint = -1;
      clampFrameIndex(activeEnemy());
      const timeline = getTimeline(activeEnemy());
      if (prevClip) {
        const idx = timeline.findIndex((c) => c.name === prevClip);
        clipIndex = idx >= 0 ? idx : 0;
      } else clipIndex = 0;
      frameLocal = 0;
      syncClipFromFrameIndex(activeEnemy());
      markDirty();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  });
}

function ensureWeaponItem(key) {
  if (!doc.weapons) doc.weapons = { scale: DEFAULT_WEAPON_SCALE, items: {} };
  if (!doc.weapons.items[key]) {
    doc.weapons.items[key] = { pan: { x: 0, y: 0 }, frames: null };
  }
  return doc.weapons.items[key];
}

function selectedWeaponFrames() {
  const mdl = sharewareWeapons[weaponKey];
  const item = ensureWeaponItem(weaponKey);
  return resolveWeaponFrames(item, mdl, weaponKey);
}

function clampWeaponPreviewFrame() {
  const mdl = sharewareWeapons[weaponKey];
  const selected = selectedWeaponFrames();
  if (mdl?.frames?.length) {
    weaponFrame = Math.max(0, Math.min(weaponFrame, mdl.frames.length - 1));
  }
  if (selected.length && !selected.includes(weaponFrame)) {
    weaponFrame = selected[0];
  }
}

function syncWeaponScaleInputs() {
  const range = document.getElementById("weapon-scale");
  const num = document.getElementById("weapon-scale-num");
  const shown = String(doc.weapons.scale);
  if (range && range.value !== shown) range.value = shown;
  if (num && document.activeElement !== num && num.value !== shown) num.value = shown;
}

function syncWeaponGlobalButtons() {
  const folder = sharewareFolderName();
  const openBtn = document.getElementById("btn-weapon-folder");
  if (openBtn) openBtn.textContent = folder ? "Change folder…" : "Open shareware folder";
  const exportBtn = document.getElementById("btn-weapon-export");
  if (exportBtn) exportBtn.disabled = !Object.keys(sharewareWeapons).length;
}

function refreshWeaponClipStatus() {
  if (editorMode !== "weapons") return;
  if (!sharewareWeapons[weaponKey]) return;
  if (weaponClipWarn) {
    setStatus("Current frame leaves the 48×42 window — pan this weapon to fit", true);
  } else {
    const n = selectedWeaponFrames().length;
    setStatus(`${WEAPON_LABELS[weaponKey]} · ${n} export frame${n === 1 ? "" : "s"}`);
  }
}

function pixelsToPngBlob(pixels) {
  const canvas = document.createElement("canvas");
  canvas.width = WEAPON_SPRITE_W;
  canvas.height = WEAPON_SPRITE_H;
  const ctx = canvas.getContext("2d");
  const img = ctx.createImageData(WEAPON_SPRITE_W, WEAPON_SPRITE_H);
  for (let i = 0; i < pixels.length; i++) {
    const on = pixels[i] ? 1 : 0;
    const o = i * 4;
    img.data[o] = on ? 232 : 0;
    img.data[o + 1] = on ? 228 : 0;
    img.data[o + 2] = on ? 216 : 0;
    img.data[o + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error("PNG encode failed"));
    }, "image/png");
  });
}

async function exportWeaponPngs() {
  if (!Object.keys(sharewareWeapons).length) {
    setStatus("Load shareware to export", true);
    return;
  }
  const dir = await ensureWeaponsPngDirectory();
  if (!dir) return;
  let n = 0;
  for (const key of WEAPON_KEYS) {
    const mdl = sharewareWeapons[key];
    if (!mdl) continue;
    const item = ensureWeaponItem(key);
    const frames = resolveWeaponFrames(item, mdl, key);
    const pan = item.pan || { x: 0, y: 0 };
    for (const fi of frames) {
      const { pixels } = rasterWeaponFrame(mdl, fi, doc.weapons.scale, pan);
      const blob = await pixelsToPngBlob(pixels);
      await writePngFile(dir, `${key}_${fi}.png`, blob);
      n++;
    }
  }
  setStatus(`Exported ${n} PNG${n === 1 ? "" : "s"} (copy to *_edit.png to clean)`);
}

function renderWeaponList() {
  const ul = document.getElementById("weapon-list");
  if (!ul) return;
  ul.innerHTML = "";
  for (const key of WEAPON_KEYS) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = WEAPON_LABELS[key];
    if (key === weaponKey) btn.className = "active";
    btn.addEventListener("click", () => {
      weaponKey = key;
      weaponSelectedVerts = [];
      clampWeaponPreviewFrame();
      markDirty();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  }
}

function renderWeaponInspector(root) {
  const h = document.createElement("h2");
  h.textContent = WEAPON_LABELS[weaponKey] || weaponKey;
  root.appendChild(h);

  const mdl = sharewareWeapons[weaponKey];
  const item = ensureWeaponItem(weaponKey);
  const folder = sharewareFolderName();

  const status = document.createElement("p");
  status.className = "muted";
  if (mdl) {
    status.textContent = folder
      ? `${folder} · ${mdl.numVerts} verts · ${mdl.frames.length} frames`
      : `${mdl.numVerts} verts · ${mdl.frames.length} frames`;
  } else if (sharewareWeaponMissing.includes(weaponKey)) {
    status.textContent = folder
      ? `${WEAPON_MDL_PATHS[weaponKey]} is not in ${folder}`
      : "View-model not in the opened PAK";
  } else {
    status.textContent = folder
      ? `Opened ${folder}. Open again if models did not load.`
      : "Open a folder that contains pak0.pak or id1/pak0.pak";
  }
  root.appendChild(status);

  root.appendChild(
    vec3Field("Pan XY", [
      {
        value: Math.round(item.pan.x * 100) / 100,
        onChange: (v) => {
          pushUndo();
          item.pan.x = Number.isFinite(v) ? v : 0;
          markDirty();
          refreshAll();
        },
      },
      {
        value: Math.round(item.pan.y * 100) / 100,
        onChange: (v) => {
          pushUndo();
          item.pan.y = Number.isFinite(v) ? v : 0;
          markDirty();
          refreshAll();
        },
      },
    ])
  );

  if (mdl && weaponSelectedVerts.length) {
    const vh = document.createElement("h2");
    vh.textContent = "Vertex";
    root.appendChild(vh);
    const verts = mdlQuakeVerts(mdl, weaponFrame);
    const packed = mdl.frames[weaponFrame]?.verts;
    const fmt = (n) => (Number.isFinite(n) ? n.toFixed(4) : "—");
    const dist3 = (a, b) => Math.hypot(a.x - b.x, a.y - b.y, a.z - b.z);
    for (const i of weaponSelectedVerts) {
      const v = verts[i];
      const box = document.createElement("div");
      box.className = "weapon-vert-info";
      const title = document.createElement("p");
      title.textContent = `Index ${i}`;
      box.appendChild(title);
      if (v) {
        const xyz = document.createElement("p");
        xyz.className = "muted";
        xyz.textContent = `Quake XYZ  ${fmt(v.x)}  ${fmt(v.y)}  ${fmt(v.z)}`;
        box.appendChild(xyz);
      }
      if (packed && i * 3 + 2 < packed.length) {
        const pk = document.createElement("p");
        pk.className = "muted";
        pk.textContent = `Packed  ${packed[i * 3]}  ${packed[i * 3 + 1]}  ${packed[i * 3 + 2]}`;
        box.appendChild(pk);
      }
      const twins = [];
      if (v) {
        for (let j = 0; j < verts.length; j++) {
          if (j === i) continue;
          if (dist3(v, verts[j]) <= 1e-4) twins.push(j);
        }
      }
      const tw = document.createElement("p");
      tw.className = "muted";
      tw.textContent = twins.length ? `Same position as  ${twins.join(", ")}` : "No coincident verts";
      box.appendChild(tw);
      root.appendChild(box);
    }
    if (weaponSelectedVerts.length === 2) {
      const a = verts[weaponSelectedVerts[0]];
      const b = verts[weaponSelectedVerts[1]];
      if (a && b) {
        const d = document.createElement("p");
        d.className = "muted";
        d.textContent = `Distance  ${fmt(dist3(a, b))}`;
        root.appendChild(d);
      }
    }
    if (weaponSelectedVerts.length === 3) {
      const pts = weaponSelectedVerts.map((i) => verts[i]);
      if (pts.every(Boolean)) {
        const n = inspectTriNormal(pts[0], pts[1], pts[2]);
        const box = document.createElement("p");
        box.className = "muted";
        box.textContent = n
          ? `Normal  ${fmt(n.x)}  ${fmt(n.y)}  ${fmt(n.z)}  (pair if n·n ≥ ${QUAD_COPLANAR_DOT})`
          : "Normal  degenerate triangle";
        root.appendChild(box);
        const asTri = (mdl.tris || []).some((t) => {
          const s = new Set(t);
          return weaponSelectedVerts.every((i) => s.has(i));
        });
        const note = document.createElement("p");
        note.className = "muted";
        note.textContent = asTri ? "These indices are an MDL triangle" : "Not an MDL triangle (by index)";
        root.appendChild(note);
      }
    }
    if (weaponSelectedVerts.length === 4) {
      const pts = weaponSelectedVerts.map((i) => verts[i]);
      if (pts.every(Boolean)) {
        const rest = weaponFrame === 0 ? verts : mdlQuakeVerts(mdl, 0);
        const q = inspectQuadPair(mdl.tris, weaponSelectedVerts, rest, mdlEnsureQuads(mdl));
        const box = document.createElement("div");
        box.className = "weapon-vert-info";
        if (!q || q.noModelPair) {
          const p = document.createElement("p");
          p.className = "muted";
          p.textContent = "Not two MDL triangles sharing an edge";
          box.appendChild(p);
        } else {
          const lines = [
            `Shared edge  ${q.shared[0]}–${q.shared[1]}`,
            `Normal score  n·n  ${fmt(q.coplanarDot)}  (need ≥ ${QUAD_COPLANAR_DOT})`,
            `Plane error  ${fmt(q.planeRel)}  (need < ${QUAD_PLANE_REL})`,
            `Parallel / trap  ${fmt(q.parallelMax)}  (score only)`,
            `Convex  ${q.convex ? "yes" : "no"}`,
            `Diagonal split  ${q.diagonal ? "yes" : "no"}`,
            q.paired ? "Paired in mesh" : q.pass ? "Gates pass, not paired" : "Would not pair",
          ];
          for (const line of lines) {
            const p = document.createElement("p");
            p.className = "muted";
            p.textContent = line;
            box.appendChild(p);
          }
        }
        root.appendChild(box);
      }
    }
  }

  const fh = document.createElement("h2");
  fh.textContent = "Export frames";
  root.appendChild(fh);
  if (!mdl) {
    const p = document.createElement("p");
    p.className = "muted";
    p.textContent = "Load shareware to pick frames.";
    root.appendChild(p);
    return;
  }

  const selected = new Set(selectedWeaponFrames());
  const ul = document.createElement("ul");
  ul.className = "weapon-frame-list";
  for (const clip of mdl.clips || []) {
    const head = document.createElement("li");
    head.className = "clip-head";
    head.textContent = clip.name;
    ul.appendChild(head);
    for (const fr of clip.frames) {
      const li = document.createElement("li");
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = selected.has(fr.index);
      chk.addEventListener("change", () => {
        pushUndo();
        const next = new Set(selectedWeaponFrames());
        if (chk.checked) next.add(fr.index);
        else next.delete(fr.index);
        item.frames = [...next].sort((a, b) => a - b);
        clampWeaponPreviewFrame();
        markDirty();
        refreshAll();
      });
      const nameBtn = document.createElement("button");
      nameBtn.type = "button";
      nameBtn.className = "frame-name" + (weaponFrame === fr.index ? " current" : "");
      nameBtn.textContent = fr.name || `frame ${fr.index}`;
      nameBtn.addEventListener("click", () => {
        weaponFrame = fr.index;
        markDirty();
        refreshAll();
      });
      li.append(chk, nameBtn);
      ul.appendChild(li);
    }
  }
  root.appendChild(ul);
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
  if (editorMode === "weapons") {
    renderWeaponInspector(root);
    return;
  }
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
    if (obj.kind === "platform") {
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = obj.collide !== false;
      chk.addEventListener("change", () => apply(() => (obj.collide = chk.checked)));
      root.appendChild(field("Collide", chk));
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
    if (obj.kind === "platform") {
      root.appendChild(
        vec3Field("Size", [
          { value: obj.sx, onChange: (v) => apply(() => (obj.sx = v)), min: 1, max: 256 },
          { value: obj.sz, onChange: (v) => apply(() => (obj.sz = v)), min: 1, max: 256 },
        ])
      );
    } else if (!KINDS[obj.kind].fixed) {
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

  const timeline = getTimeline(e);
  if (timeline.length) {
    const clip = activeTimelineClip() || timeline[0];
    if (clipIndex >= timeline.length) clipIndex = 0;
    frameLocal = Math.max(0, Math.min(frameLocal, clip.len - 1));

    const clipSel = document.createElement("select");
    timeline.forEach((c, i) => {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = `${c.name} (${c.len})`;
      if (i === clipIndex) opt.selected = true;
      clipSel.appendChild(opt);
    });
    clipSel.addEventListener("change", () => {
      clipIndex = Number(clipSel.value) | 0;
      frameLocal = 0;
      if (e.clips?.length) {
        frameIndex = e.clips[clipIndex].start;
      }
      markDirty();
      refreshAll();
    });
    root.appendChild(field("Clip", clipSel));

    const frameName = clip.frameNames?.[frameLocal] || `${clip.name}${frameLocal}`;
    const sliderRow = document.createElement("label");
    sliderRow.className = "field block";
    const sliderLbl = document.createElement("span");
    sliderLbl.id = "anim-frame-label";
    sliderLbl.textContent = frameName;
    const slider = document.createElement("input");
    slider.id = "anim-frame-slider";
    slider.type = "range";
    slider.min = "0";
    slider.max = String(Math.max(0, clip.len - 1));
    slider.value = String(frameLocal);
    slider.addEventListener("input", () => {
      frameLocal = Number(slider.value) | 0;
      sliderLbl.textContent = clip.frameNames?.[frameLocal] || `${clip.name}${frameLocal}`;
      if (e.clips?.length) {
        frameIndex = e.clips[clipIndex].start + frameLocal;
      }
      animView.draw();
    });
    sliderRow.append(sliderLbl, slider);
    root.appendChild(sliderRow);

    const playRow = document.createElement("div");
    playRow.className = "btn-row";
    const playBtn = document.createElement("button");
    playBtn.id = "btn-anim-play";
    playBtn.type = "button";
    playBtn.textContent = animPlaying ? "Pause" : "Play";
    if (animPlaying) playBtn.className = "active";
    playBtn.addEventListener("click", toggleAnimPlay);
    const loopLbl = document.createElement("label");
    loopLbl.className = "check-inline";
    const loopChk = document.createElement("input");
    loopChk.id = "anim-loop";
    loopChk.type = "checkbox";
    loopChk.checked = animLoop;
    loopChk.addEventListener("change", () => {
      animLoop = loopChk.checked;
    });
    loopLbl.append(loopChk, document.createTextNode(" Loop"));
    playRow.append(playBtn, loopLbl);
    root.appendChild(playRow);
  }

  const counts = document.createElement("p");
  counts.className = "muted";
  const clip = e.clips?.length ? clipForFrame(e.clips, frameIndex) : activeTimelineClip();
  const stickFrame = e.clips?.length ? frameIndex : 0;
  const height = frameHeight(e.frames[stickFrame] || e.frames[0]);
  const frameTotal = e.clips?.length ? e.frames.length : timeline.length ? "MDL preview" : 1;
  counts.textContent = `13 verts · 13 lines · ${clip?.name || "rest"} · height ${height} · ${frameTotal} frames`;
  root.appendChild(counts);

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
  editRow.append(copyBtn, pasteBtn);
  root.appendChild(editRow);

  if (selectedVerts.length === 1) {
    const vi = selectedVerts[0];
    const stickFi = e.clips?.length ? frameIndex : 0;
    const v = e.frames[stickFi][vi];
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

  renderQuakeSource(root, e);
}

function ensureEnemyRig(e) {
  if (!e.mdlRig || !Array.isArray(e.mdlRig.jointVerts) || e.mdlRig.jointVerts.length !== 13) {
    e.mdlRig = emptyMdlRig();
  }
  return e.mdlRig;
}

function activeMdl() {
  return sharewareModels[activeEnemy()?.name] || null;
}

function updateAnimHint() {
  if (editorMode !== "anim") return;
  const hint = document.getElementById("hint");
  if (!hint) return;
  hint.textContent =
    bindJoint >= 0
      ? `Box-select mesh verts for ${JOINT_NAMES[bindJoint]} · Shift add · Esc stops bind · RMB orbit`
      : "LMB box-select verts · click-drag unselected on camera plane · gizmo moves selection · X/Y/Z nudge · [ ] frames · RMB orbit · Alt+RMB zoom";
}

function assignMeshVerts(indices, additive) {
  if (bindJoint < 0) return;
  const e = activeEnemy();
  if (!e) return;
  const rig = ensureEnemyRig(e);
  const mdl = activeMdl();
  const max = mdl ? mdl.numVerts : Infinity;
  pushUndo();
  const set = new Set(additive ? rig.jointVerts[bindJoint] : []);
  for (const i of indices) {
    const n = i | 0;
    if (n >= 0 && n < max) set.add(n);
  }
  rig.jointVerts[bindJoint] = [...set].sort((a, b) => a - b);
  markDirty();
  refreshPanels();
  animView.draw();
}

async function loadSharewareFromHandle(handle) {
  try {
    const buffers = await loadSharewarePakBuffers(handle);
    if (!buffers.length) {
      sharewareModels = {};
      sharewareMissing = ENEMY_TYPES.map((t) => t.name);
      sharewareWeapons = {};
      sharewareWeaponMissing = [...WEAPON_KEYS];
      setStatus("No pak0.pak / pak1.pak in that folder", true);
      refreshPanels();
      return;
    }
    const lumps = parsePakBuffers(buffers);
    const { models, missing } = loadEnemyMdls(lumps);
    sharewareModels = models;
    sharewareMissing = missing;
    const weapons = loadWeaponMdls(lumps);
    sharewareWeapons = weapons.models;
    sharewareWeaponMissing = weapons.missing;
    clampWeaponPreviewFrame();
    markDirty();
    const n = Object.keys(models).length;
    const wn = Object.keys(sharewareWeapons).length;
    const miss = missing.length ? ` · missing ${missing.join(", ")}` : "";
    const wmiss = weapons.missing.length ? ` · weapons missing ${weapons.missing.join(", ")}` : "";
    setStatus(
      `Loaded ${n} enemy / ${wn} weapon model${wn === 1 ? "" : "s"} from ${sharewareFolderName()}${miss}${wmiss}`
    );
  } catch (err) {
    sharewareModels = {};
    sharewareMissing = ENEMY_TYPES.map((t) => t.name);
    sharewareWeapons = {};
    sharewareWeaponMissing = [...WEAPON_KEYS];
    setStatus(String(err.message || err), true);
  }
  refreshPanels();
  if (editorMode === "anim") animView.draw();
  if (editorMode === "weapons") weaponView.draw();
}

async function openSharewareFolder() {
  try {
    const stored = await getStoredSharewareHandle();
    if (stored) {
      const allowed = await allowStoredSharewareDir(stored);
      if (allowed) {
        await loadSharewareFromHandle(allowed);
        return;
      }
    }
    const handle = await pickSharewareDirectory();
    if (!handle) {
      setStatus("Open cancelled", true);
      return;
    }
    await loadSharewareFromHandle(handle);
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
}

function copyAllMdlFrames() {
  const e = activeEnemy();
  const mdl = activeMdl();
  if (!e || !mdl) {
    setStatus("Load shareware first", true);
    return;
  }
  const rig = ensureEnemyRig(e);
  const bound = rig.jointVerts.some((list) => list.length);
  if (!bound) {
    setStatus("Assign mesh verts to at least one joint first", true);
    return;
  }
  const rest = e.frames[0] || dummyFrameFor(e.name);
  const { frames, clips } = buildStickFramesFromMdl(mdl, rig, mdlScale, rest, clampVert);
  if (!frames.length) {
    setStatus("No Quake frames to copy", true);
    return;
  }
  pushUndo();
  e.frames = frames;
  e.clips = clips;
  frameIndex = 0;
  clipIndex = 0;
  frameLocal = 0;
  markDirty();
  refreshAll();
  setStatus(`Copied ${frames.length} frames from Quake MDL`);
}

function renderQuakeSource(root, e) {
  const wrap = document.createElement("section");
  wrap.className = "quake-source";
  const h = document.createElement("h2");
  h.textContent = "Quake source";
  wrap.appendChild(h);

  const status = document.createElement("p");
  status.className = "muted";
  const mdl = sharewareModels[e.name];
  const folder = sharewareFolderName();
  const kept = mdl ? filterMdlClips(mdl.clips) : [];
  const keptCount = kept.reduce((n, c) => n + c.frames.length, 0);
  if (mdl) {
    status.textContent = folder
      ? `${folder} · ${mdl.numVerts} mesh verts · ${keptCount} kept frames`
      : `${mdl.numVerts} mesh verts · ${keptCount} kept frames`;
  } else if (sharewareMissing.includes(e.name)) {
    status.textContent = folder
      ? `${e.name} is not in ${folder}`
      : `${e.name} model not in the opened PAK`;
  } else {
    status.textContent = folder
      ? `Opened ${folder}. Open again if models did not load.`
      : "Open a folder that contains pak0.pak or id1/pak0.pak";
  }
  wrap.appendChild(status);

  const openRow = document.createElement("div");
  openRow.className = "btn-row";
  const openBtn = document.createElement("button");
  openBtn.type = "button";
  openBtn.textContent = folder ? "Change folder…" : "Open shareware folder";
  openBtn.addEventListener("click", () => void openSharewareFolder());
  openRow.appendChild(openBtn);
  wrap.appendChild(openRow);

  if (mdl && kept.length) {
    const copyAllBtn = document.createElement("button");
    copyAllBtn.type = "button";
    copyAllBtn.textContent = "Copy all frames";
    copyAllBtn.title = "Write all kept Quake poses onto stick frames using current joint bindings";
    copyAllBtn.addEventListener("click", copyAllMdlFrames);
    const copyRow = document.createElement("div");
    copyRow.className = "btn-row";
    copyRow.appendChild(copyAllBtn);
    wrap.appendChild(copyRow);
  }

  const jointList = document.createElement("ul");
  jointList.className = "joint-list";
  const rig = ensureEnemyRig(e);
  JOINT_NAMES.forEach((name, i) => {
    const li = document.createElement("li");
    li.className = "joint-row" + (bindJoint === i ? " active" : "");
    const label = document.createElement("span");
    label.className = "joint-name";
    const n = rig.jointVerts[i].length;
    label.textContent = n ? `${name} · ${n}` : name;
    const bindBtn = document.createElement("button");
    bindBtn.type = "button";
    bindBtn.textContent = bindJoint === i ? "Done" : "Bind";
    if (bindJoint === i) bindBtn.className = "active";
    bindBtn.addEventListener("click", () => {
      bindJoint = bindJoint === i ? -1 : i;
      if (bindJoint >= 0) setOverlayOn(true);
      updateAnimHint();
      refreshPanels();
      animView.draw();
    });
    const clearBtn = document.createElement("button");
    clearBtn.type = "button";
    clearBtn.textContent = "Clear";
    clearBtn.disabled = !rig.jointVerts[i].length;
    clearBtn.addEventListener("click", () => {
      pushUndo();
      rig.jointVerts[i] = [];
      if (bindJoint === i) bindJoint = -1;
      markDirty();
      updateAnimHint();
      refreshPanels();
      animView.draw();
    });
    li.append(label, bindBtn, clearBtn);
    jointList.appendChild(li);
  });
  wrap.appendChild(jointList);
  root.appendChild(wrap);
}

function frameHeight(verts) {
  let maxY = -Infinity;
  for (const v of verts) {
    if (v.y > maxY) maxY = v.y;
  }
  return Number.isFinite(maxY) ? maxY : 0;
}

function applyFrameLocal() {
  const e = activeEnemy();
  if (e?.clips?.length) {
    const clip = e.clips[clipIndex];
    if (clip) frameIndex = clip.start + frameLocal;
  }
}

function advanceFrame(d) {
  const timeline = getTimeline(activeEnemy());
  if (!timeline.length) return false;
  const clip = timeline[clipIndex] || timeline[0];
  const len = Math.max(1, clip.len);
  frameLocal = (frameLocal + d + len) % len;
  applyFrameLocal();
  return true;
}

function syncPlayUi() {
  const clip = activeTimelineClip();
  const slider = document.getElementById("anim-frame-slider");
  const lbl = document.getElementById("anim-frame-label");
  if (clip && slider) {
    slider.value = String(frameLocal);
    if (lbl) lbl.textContent = clip.frameNames?.[frameLocal] || `${clip.name}${frameLocal}`;
  }
  if (editorMode === "anim") animView.draw();
}

function stepFrame(d) {
  if (!advanceFrame(d)) return;
  markDirty();
  refreshAll();
}

function stepWeaponFrame(d) {
  const frames = selectedWeaponFrames();
  if (!frames.length) return;
  let i = frames.indexOf(weaponFrame);
  if (i < 0) i = 0;
  weaponFrame = frames[(i + d + frames.length) % frames.length];
  markDirty();
  refreshAll();
}

function copyFrame() {
  const e = activeEnemy();
  if (!e.clips?.length) {
    setStatus("Copy frames from Quake MDL first", true);
    return;
  }
  const fr = e.frames[frameIndex];
  frameClipboard = fr.map((v) => ({ x: v.x, y: v.y, z: v.z }));
  setStatus(`Copied ${frameLabel(e, frameIndex)}`);
  refreshPanels();
}

function pasteFrame() {
  if (!frameClipboard) {
    setStatus("Copy a frame first", true);
    return;
  }
  const e = activeEnemy();
  if (!e.clips?.length) {
    setStatus("Copy frames from Quake MDL first", true);
    return;
  }
  const fr = e.frames[frameIndex];
  pushUndo();
  for (let i = 0; i < fr.length; i++) {
    const src = frameClipboard[i] || fr[i];
    fr[i].x = clampVert(src.x);
    fr[i].y = clampVert(src.y);
    fr[i].z = clampVert(src.z);
  }
  markDirty();
  refreshAll();
  setStatus(`Pasted onto ${frameLabel(e, frameIndex)}`);
}

function stopAnimPlay() {
  animPlaying = false;
  if (animPlayTimer) {
    clearInterval(animPlayTimer);
    animPlayTimer = null;
  }
}

function updatePlayButton() {
  const playBtn = document.getElementById("btn-anim-play");
  if (!playBtn) return;
  playBtn.textContent = animPlaying ? "Pause" : "Play";
  playBtn.classList.toggle("active", animPlaying);
}

function toggleAnimPlay() {
  if (animPlaying) {
    stopAnimPlay();
    updatePlayButton();
    setStatus("Paused");
    return;
  }
  const clip = activeTimelineClip();
  if (!clip) {
    setStatus("No clip to play", true);
    return;
  }
  frameLocal = 0;
  applyFrameLocal();
  syncPlayUi();
  animPlaying = true;
  animPlayTimer = setInterval(tickAnimPlay, ANIM_PLAY_MS);
  updatePlayButton();
  setStatus(`Playing ${clip.name}`);
}

function tickAnimPlay() {
  if (editorMode !== "anim") {
    stopAnimPlay();
    updatePlayButton();
    return;
  }
  const clip = activeTimelineClip();
  if (!clip) {
    stopAnimPlay();
    updatePlayButton();
    return;
  }
  if (frameLocal >= clip.len - 1) {
    if (!animLoop) {
      stopAnimPlay();
      updatePlayButton();
      setStatus("Paused");
      return;
    }
    frameLocal = 0;
  } else {
    frameLocal++;
  }
  applyFrameLocal();
  syncPlayUi();
}

function setOverlayOn(on) {
  overlayOn = !!on;
  document.getElementById("btn-mdl-overlay")?.classList.toggle("active", overlayOn);
  if (editorMode === "anim") animView.draw();
}

function setMdlScale(value, dirty = true) {
  mdlScale = clampMdlScale(value);
  const range = document.getElementById("mdl-scale");
  const numInp = document.getElementById("mdl-scale-num");
  const shown = String(mdlScale);
  if (range && range.value !== shown) range.value = shown;
  if (numInp && numInp.value !== shown) numInp.value = shown;
  if (dirty) {
    markDirty();
    if (editorMode === "anim") animView.draw();
  }
}

function nudgeVert(axis, delta) {
  const e = activeEnemy();
  if (!e.clips?.length) {
    setStatus("Copy frames from Quake MDL first", true);
    return;
  }
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
  renderWeaponList();
  renderInspector();
  syncWeaponScaleInputs();
  syncWeaponGlobalButtons();
  overheadView.draw();
  if (editorMode === "anim") animView.draw();
  if (editorMode === "weapons") weaponView.draw();
}

function refreshAll() {
  refreshPanels();
  if (editorMode === "layout") layoutView.draw();
  else if (editorMode === "weapons") weaponView.draw();
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
document.getElementById("btn-mode-weapons").addEventListener("click", () => {
  setMode("weapons");
  markDirty();
});
document.getElementById("mdl-scale").addEventListener("input", (e) => {
  setMdlScale(e.target.value);
});
document.getElementById("mdl-scale-num").addEventListener("change", (e) => {
  setMdlScale(e.target.value);
});
document.getElementById("btn-mdl-overlay").addEventListener("click", () => {
  setOverlayOn(!overlayOn);
});
document.getElementById("weapon-scale").addEventListener("input", (e) => {
  doc.weapons.scale = clampWeaponScale(e.target.value);
  syncWeaponScaleInputs();
  if (editorMode === "weapons") weaponView.draw();
});
document.getElementById("weapon-scale").addEventListener("change", (e) => {
  pushUndo();
  doc.weapons.scale = clampWeaponScale(e.target.value);
  syncWeaponScaleInputs();
  markDirty();
  refreshAll();
});
document.getElementById("weapon-scale-num").addEventListener("change", (e) => {
  pushUndo();
  doc.weapons.scale = clampWeaponScale(e.target.value);
  syncWeaponScaleInputs();
  markDirty();
  refreshAll();
});
document.getElementById("btn-weapon-folder")?.addEventListener("click", () => void openSharewareFolder());
document.getElementById("btn-weapon-export")?.addEventListener("click", () => {
  exportWeaponPngs().catch((err) => setStatus(String(err.message || err), true));
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
    if (e.key === "Escape") {
      if (bindJoint >= 0) {
        e.preventDefault();
        bindJoint = -1;
        updateAnimHint();
        refreshPanels();
        animView.draw();
        return;
      }
    }
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
  if (editorMode === "weapons") {
    if (e.key === "Escape") {
      if (weaponSelectedVerts.length) {
        e.preventDefault();
        weaponSelectedVerts = [];
        refreshAll();
        return;
      }
    }
    if (e.key === "[" || e.key === "," || e.key === "ArrowLeft") {
      e.preventDefault();
      stepWeaponFrame(-1);
      return;
    }
    if (e.key === "]" || e.key === "." || e.key === "ArrowRight") {
      e.preventDefault();
      stepWeaponFrame(1);
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

async function restoreSharewareQuietly() {
  try {
    const dir = await tryRestoreSharewareDir();
    if (dir) await loadSharewareFromHandle(dir);
  } catch {
    /* folder optional */
  }
}

async function boot() {
  updateDirtyIndicator();
  refreshAll();
  try {
    const loaded = await tryRestoreDocFile();
    if (loaded) {
      applyLoadedDoc(loaded);
      await restoreSharewareQuietly();
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
    await restoreSharewareQuietly();
  } catch (err) {
    setStatus(String(err.message || err), true);
  }
}

void boot();

setInterval(() => {
  if (editorMode === "layout") overheadView.draw();
}, 80);
