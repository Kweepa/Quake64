import {
  KINDS,
  PALETTE_ORDER,
  ENEMY_TYPES,
  ENEMY_FACINGS,
  JOINT_NAMES,
  clampEnemyRot,
  cycleEnemyRot,
  cycleSlopeOrient,
  clampObject,
  clampTriggerText,
  clampName,
  clampTag,
  elevHeightsAuto,
  clampElevHeights,
  elevStopBottoms,
  clampTriggerPurpose,
  TRIGGER_PURPOSES,
  TRIGGER_PURPOSE_LABELS,
  clampVert,
  C64_HEX,
  C64_NAMES,
  ROOM_BG_DEFAULT,
  ROOM_LINE_DEFAULT,
  ROOM_FX_DEFAULT,
  ROOM_WPN_DEFAULT,
  MAX_TRIGGER_TEXT,
  MAX_NAME_LEN,
  MAX_TAG_LEN,
  PICKUP_TYPES,
  ALL_MESH_KEYS,
  ITEM_MESH_KEYS,
  DOOR_MESH_KEYS,
  DOOR_TYPES,
  DOOR_LOCKS,
  DOOR_LOCK_LABELS,
  clampPickupType,
  clampDoorLock,
  clampDoorType,
  isDoorMeshKey,
  ITEM_MAX_UNIQUE,
  itemMeshStats,
  createObject,
  createDefaultDocument,
  localFocusRoom,
  normalizeDocument,
  uid,
  LEVEL_NAMES,
  activeMap,
  mapStats,
  formatMapStats,
  formatMapLoadTitle,
  packedPoseBytes,
  ENEMY_POSE_MAX,
  ROOM_MAX_TYPES,
  canAddEnemyType,
  clipForFrame,
  dummyFrameFor,
  isFigureObject,
  objectLabel,
  objectTree,
  roomUnderObject,
  roomById,
  roomsOf,
  assignDoorRooms,
  snapDoorBetweenRooms,
  snapSwitchToRoom,
  usesLinkTag,
  triggerUsesTag,
  emptyMdlRig,
  DEFAULT_MDL_SCALE,
  clampMdlScale,
  clampEnemyLodZ,
  defaultEnemyLodZ,
  WEAPON_KEYS,
  WEAPON_LABELS,
  clampWeaponScale,
  DEFAULT_WEAPON_SCALE,
  ROOM_SHAPES,
  applyRoomShape,
  rotateRoom,
  rotateRoomY,
  rotateRoomsBlockY,
  roomFloorY,
  clampRoomShape,
  parseEditorState,
  gameDocument,
} from "./model.js";
import {
  autosaveDocJSON,
  DEFAULT_DOC_PATH,
  docFileName,
  getStoredDocHandle,
  hasDocFileHandle,
  loadDocJSON,
  saveDocJSON,
  loadEditorSettings,
  saveEditorSettings,
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
  buildStickFramesFromMdl,
  resolveWeaponFrames,
  rasterWeaponFrame,
  WEAPON_MDL_PATHS,
  WEAPON_SPRITE_W,
  WEAPON_SPRITE_H,
} from "./mdl.js";
import { LayoutView } from "./layoutView.js";
import { OverheadView } from "./overheadView.js";
import { AnimView } from "./animView.js";
import { WeaponView } from "./weaponView.js";
import { ItemView } from "./itemView.js";

const statusEl = document.getElementById("status");
const titleEl = document.querySelector(".toolbar h1");
const btnUndo = document.getElementById("btn-undo");
const btnRedo = document.getElementById("btn-redo");
const UNDO_LIMIT = 40;
const AUTOSAVE_MS = 8000;
const MDL_RIG_BACKUP_KEY = "quake64-mdl-rigs";
/** Match Quake monster default: one MDL frame per 0.1s think. */
const ANIM_PLAY_MS = 100;

let doc = createDefaultDocument();
let editorMode = "layout";
let localDraw = false;
let neighbourDraw = false;
let selectedIds = [];
let pendingPlace = null;
let enemyIndex = 0;
let frameIndex = 0;
let selectedVerts = [];
let dirty = false;
let saving = false;
let autosaveTimer = null;
let editorSaveRaf = 0;
let editorSettingsReady = false;
let applyingEditor = false;
let undoStack = [];
let redoStack = [];
let undoGesture = false;
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
let itemMeshKey = "backpack";
/** Collapsed room ids in the Objects tree. */
const collapsedRooms = new Set();
/** Last room used for placement / parenting. */
let lastRoomId = null;

const layoutView = new LayoutView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getDoc: () => doc,
  getSelectedIds: () => selectedIds,
  getLocalMode: () => localDraw && editorMode === "layout",
  getNeighbourMode: () => neighbourDraw,
  getFocusRoom: () => localFocusRoom(doc, selectedIds, lastRoomId),
  onSelectIds: (ids, additive) => {
    if (additive) {
      for (const id of ids) {
        if (!selectedIds.includes(id)) selectedIds.push(id);
      }
    } else selectedIds = [...ids];
    rememberSelectedRoom();
    markUi();
    refreshPanels();
  },
  onToggleSelect: (id) => {
    const i = selectedIds.indexOf(id);
    if (i >= 0) selectedIds.splice(i, 1);
    else selectedIds.push(id);
    rememberSelectedRoom();
    markUi();
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onViewChanged: () => {
    markUi();
  },
  onStatus: setStatus,
  beginUndo,
  endUndo,
  getPlaceRoom: () => placementRoom(),
});

const overheadView = new OverheadView(document.getElementById("overhead-canvas"), {
  getDoc: () => doc,
  getCamera: () => layoutView.camera,
  getSelectedId: () => (selectedIds.length ? selectedIds[selectedIds.length - 1] : null),
  getSelectedIds: () => selectedIds,
  getLocalMode: () => localDraw,
  getNeighbourMode: () => neighbourDraw,
  getFocusRoom: () => localFocusRoom(doc, selectedIds, lastRoomId),
});

const animView = new AnimView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getEnemy: () => doc.enemies[enemyIndex],
  getFrame: () => {
    const e = doc.enemies[enemyIndex];
    const stick = stickClipFor(e, activeTimelineClip());
    if (stick) return stick.start + frameLocal;
    if (!e?.clips?.length) return 0;
    return frameIndex;
  },
  hasStickFrame: () => !!stickClipFor(doc.enemies[enemyIndex], activeTimelineClip()),
  getSelectedVerts: () => selectedVerts,
  onSelectVert: (i, additive) => {
    if (i < 0) selectedVerts = [];
    else if (additive) {
      if (!selectedVerts.includes(i)) selectedVerts.push(i);
    } else selectedVerts = [i];
    markUi();
    refreshPanels();
  },
  onSelectVerts: (indices, additive) => {
    if (additive) {
      for (const i of indices) {
        if (!selectedVerts.includes(i)) selectedVerts.push(i);
      }
    } else selectedVerts = [...indices];
    markUi();
    refreshPanels();
  },
  onChange: () => {
    markDirty();
    refreshPanels();
  },
  onViewChanged: () => {
    markUi();
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
    const mdlFi = clip.mdlFrames[local]?.index ?? 0;
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
});

const itemView = new ItemView(document.getElementById("view-canvas"), {
  stage: document.getElementById("map-stage"),
  getMesh: () => {
    if (!doc.items) doc.items = {};
    if (!doc.items[itemMeshKey]) doc.items[itemMeshKey] = { verts: [], lines: [] };
    return doc.items[itemMeshKey];
  },
  beginUndo,
  endUndo,
  onChange: () => {
    markDirty();
    renderInspector();
  },
  onSelect: () => renderInspector(),
  onStatus: (msg, isError) => setStatus(msg, isError),
  onViewChanged: () => markUi(),
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

function mdlRigBackupRaw() {
  try {
    const raw = JSON.parse(localStorage.getItem(MDL_RIG_BACKUP_KEY) || "null");
    return raw && typeof raw === "object" ? raw : null;
  } catch {
    return null;
  }
}

function persistMdlRigBackup() {
  const out = { ...(mdlRigBackupRaw() || {}) };
  for (const e of doc.enemies || []) {
    const jv = e.mdlRig?.jointVerts;
    if (!Array.isArray(jv) || !jv.some((list) => list.length)) {
      delete out[e.name];
      continue;
    }
    out[e.name] = jv.map((list) => [...list]);
  }
  try {
    if (!Object.keys(out).length) localStorage.removeItem(MDL_RIG_BACKUP_KEY);
    else localStorage.setItem(MDL_RIG_BACKUP_KEY, JSON.stringify(out));
  } catch {
    /* private mode / quota */
  }
}

/** Fill empty in-memory rigs from localStorage (survives refresh without doc reload). */
function restoreMdlRigBackup() {
  const raw = mdlRigBackupRaw();
  if (!raw) return false;
  let changed = false;
  for (const e of doc.enemies || []) {
    const jv = e.mdlRig?.jointVerts;
    if (Array.isArray(jv) && jv.some((list) => list.length)) continue;
    const saved = raw[e.name];
    if (!Array.isArray(saved)) continue;
    e.mdlRig = normalizeMdlRig({ jointVerts: saved });
    changed = true;
  }
  return changed;
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

function markUi() {
  if (applyingEditor || !editorSettingsReady) return;
  schedulePersistEditor();
}

function collectEditorState() {
  const cam = layoutView.camera;
  const orb = animView.orbit;
  const iorb = itemView.orbit;
  const enemy = doc.enemies[enemyIndex];
  return parseEditorState({
    mode: editorMode,
    localDraw,
    neighbourDraw,
    selectedIds: [...selectedIds],
    enemy: enemy?.name || "Grunt",
    frameIndex,
    clipIndex,
    frameLocal,
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
    overlayOn,
    orthoMode: overheadView.mode,
    collapsedRooms: [...collapsedRooms],
    activeLevel: doc.activeLevel,
    item: itemMeshKey,
    itemOrbit: {
      yaw: iorb.yaw,
      pitch: iorb.pitch,
      dist: iorb.dist,
      target: { x: iorb.target.x, y: iorb.target.y, z: iorb.target.z },
    },
  });
}

function persistEditorSettings() {
  if (!editorSettingsReady) return;
  if (editorSaveRaf) {
    cancelAnimationFrame(editorSaveRaf);
    editorSaveRaf = 0;
  }
  saveEditorSettings(docFileName(), collectEditorState());
}

function schedulePersistEditor() {
  if (!editorSettingsReady || applyingEditor) return;
  if (editorSaveRaf) return;
  editorSaveRaf = requestAnimationFrame(() => {
    editorSaveRaf = 0;
    persistEditorSettings();
  });
}

function applyEditorState(ed) {
  ed = parseEditorState(ed);
  applyingEditor = true;
  try {
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
    const ei = doc.enemies.findIndex((e) => e.name === ed.enemy);
    enemyIndex = ei >= 0 ? ei : 0;
    frameIndex = ed.frameIndex;
    clampFrameIndex(activeEnemy());
    syncClipFromFrameIndex(activeEnemy());
    const have = new Set(activeMap(doc).objects.map((o) => o.id));
    selectedIds = ed.selectedIds.filter((id) => have.has(id));
    rememberSelectedRoom();
    selectedVerts = [...ed.selectedVerts];
    setMdlScale(ed.mdlScale);
    weaponKey = WEAPON_KEYS.includes(ed.weapon) ? ed.weapon : "axe";
    weaponFrame = Math.max(0, ed.weaponFrame | 0);
    setOverlayOn(ed.overlayOn);
    setOrthoMode(ed.orthoMode);
    collapsedRooms.clear();
    for (const id of ed.collapsedRooms) collapsedRooms.add(id);
    if (ed.activeLevel && LEVEL_NAMES.includes(ed.activeLevel)) doc.activeLevel = ed.activeLevel;
    itemMeshKey = ALL_MESH_KEYS.includes(ed.item) ? ed.item : "backpack";
    const iorb = itemView.orbit;
    iorb.yaw = ed.itemOrbit.yaw;
    iorb.pitch = ed.itemOrbit.pitch;
    iorb.dist = ed.itemOrbit.dist;
    iorb.target.x = ed.itemOrbit.target.x;
    iorb.target.y = ed.itemOrbit.target.y;
    iorb.target.z = ed.itemOrbit.target.z;
    setNeighbourDraw(ed.neighbourDraw, false);
    setDrawMode(ed.localDraw);
    setMode(ed.mode);
  } finally {
    applyingEditor = false;
  }
}

async function saveNow(okMsg = "Saved") {
  if (saving) return;
  saving = true;
  try {
    persistEditorSettings();
    const payload = gameDocument(doc);
    const how = hasDocFileHandle()
      ? await autosaveDocJSON(payload)
      : await saveDocJSON(payload, DEFAULT_DOC_PATH);
    if (!how) {
      setStatus("Save cancelled", true);
      return;
    }
    markClean();
    persistMdlRigBackup();
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
    items: doc.items,
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

function stickClipFor(e, clip) {
  if (!clip || !e?.clips?.length) return null;
  return e.clips.find((c) => c.name === clip.name) || null;
}

function exportClipNames(e, mdl) {
  const mdlNames = new Set((mdl?.clips || []).map((c) => c.name));
  if (Array.isArray(e?.exportClips)) {
    return e.exportClips.filter((n) => !mdlNames.size || mdlNames.has(n));
  }
  if (e?.clips?.length) {
    return e.clips.map((c) => c.name).filter((n) => !mdlNames.size || mdlNames.has(n));
  }
  return filterMdlClips(mdl?.clips).map((c) => c.name);
}

function formatPackedPoseMem(packed) {
  const { bytes, nLogical, nStored } = packed;
  const size =
    bytes >= 1024
      ? `${bytes / 1024 < 10 ? (bytes / 1024).toFixed(1) : Math.round(bytes / 1024)} KB`
      : `${bytes} bytes`;
  const over =
    bytes > ENEMY_POSE_MAX ? ` OVER ${bytes - ENEMY_POSE_MAX}` : "";
  return `≈ ${size} in-game (${nStored} stored / ${nLogical} logical)${over}`;
}

function getTimeline(e) {
  const mdl = sharewareModels[e?.name];
  if (mdl?.clips?.length) {
    const byName = new Map((e.clips || []).map((c) => [c.name, c]));
    return mdl.clips.map((c) => {
      const stick = byName.get(c.name);
      return {
        name: c.name,
        len: c.frames.length,
        start: stick ? stick.start : 0,
        frameNames: c.frames.map((fr) => fr.name),
        mdlFrames: c.frames,
        hasStick: !!stick,
      };
    });
  }
  if (e?.clips?.length) {
    return e.clips.map((c) => ({
      name: c.name,
      len: c.len,
      start: c.start,
      frameNames: [],
      mdlFrames: [],
      hasStick: true,
    }));
  }
  return [];
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
  const mdl = sharewareModels[e?.name];
  if (e?.clips?.length) {
    const stick = clipForFrame(e.clips, frameIndex);
    if (stick) {
      const idx = timeline.findIndex((c) => c.name === stick.name);
      if (idx >= 0) {
        clipIndex = idx;
        frameLocal = frameIndex - stick.start;
        return;
      }
      if (!mdl) {
        clipIndex = Math.max(0, e.clips.indexOf(stick));
        frameLocal = frameIndex - stick.start;
        return;
      }
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
  document.getElementById("btn-mode-items")?.classList.toggle("active", mode === "items");
  document.getElementById("layout-left").hidden = mode !== "layout";
  document.querySelector(".left")?.classList.toggle("left-map", mode === "layout");
  document.getElementById("anim-left").hidden = mode !== "anim";
  document.getElementById("weapons-left").hidden = mode !== "weapons";
  const itemsLeft = document.getElementById("items-left");
  if (itemsLeft) itemsLeft.hidden = mode !== "items";
  document.getElementById("draw-mode-group").classList.toggle("inactive", mode !== "layout");
  for (const id of ["btn-draw-all", "btn-draw-local", "btn-draw-neighbours"]) {
    document.getElementById(id).disabled = mode !== "layout";
  }
  document.getElementById("overhead-panel").hidden = mode !== "layout";
  document.getElementById("weapon-preview-panel").hidden = mode !== "weapons";
  updateCenterChrome();
  document.getElementById("hint").textContent =
    mode === "layout"
      ? "Drag palette to place · LMB box/click-select · Shift add · WASD/wheel fly · Q/E up · RMB look · Alt+LMB / Alt+MMB orbit · MMB pan · Alt+RMB zoom · F focus · G drop · gizmo moves selection · Del"
      : mode === "weapons"
        ? "LMB drag pans · wheel scale"
        : mode === "items"
          ? "LMB box-select verts · click vert/line to select · Shift add · gizmo moves · V add vert · L add line · Ctrl+C/V copy/paste · Del · F focus · MMB pan · Alt+LMB / RMB orbit · Alt+RMB zoom"
          : bindJoint >= 0
            ? `Box-select mesh verts for ${JOINT_NAMES[bindJoint]} · Shift add · Esc stops bind · F focus · RMB orbit`
            : "LMB box-select verts · click-drag unselected on camera plane · gizmo moves selection · X/Y/Z nudge · [ ] frames · F focus · MMB pan · Alt+LMB / RMB orbit · Alt+RMB zoom";
  layoutView.enabled = mode === "layout";
  animView.enabled = mode === "anim";
  weaponView.enabled = mode === "weapons";
  itemView.enabled = mode === "items";
  if (mode === "layout") layoutView.resize();
  else if (mode === "anim") animView.resize();
  else if (mode === "weapons") weaponView.resize();
  else if (mode === "items") itemView.resize();
  if (mode !== "anim") stopAnimPlay();
  refreshAll();
  markUi();
}

function setOrthoMode(mode) {
  overheadView.setMode(mode);
  document.getElementById("btn-ortho-top").classList.toggle("active", mode === "top");
  document.getElementById("btn-ortho-left").classList.toggle("active", mode === "left");
  document.getElementById("btn-ortho-forward").classList.toggle("active", mode === "forward");
  const hint = document.getElementById("ortho-hint");
  if (hint) hint.textContent = overheadView.hint();
  markUi();
}

function syncDrawButtons() {
  document.getElementById("btn-draw-all").classList.toggle("active", !localDraw);
  document.getElementById("btn-draw-local").classList.toggle("active", localDraw);
  document.getElementById("btn-draw-neighbours")?.classList.toggle("active", neighbourDraw);
}

function drawModeStatus() {
  if (!localDraw) return "All rooms";
  if (!localFocusRoom(doc, selectedIds, lastRoomId)) return "Local: no room selected";
  return neighbourDraw ? "Local + neighbours" : "Local draw";
}

function setDrawMode(local) {
  localDraw = local;
  syncDrawButtons();
  const msg = drawModeStatus();
  setStatus(msg, local && msg.startsWith("Local: no"));
  refreshAll();
  markUi();
}

function setNeighbourDraw(on, redraw = true) {
  neighbourDraw = !!on;
  syncDrawButtons();
  if (redraw) {
    const msg = drawModeStatus();
    if (localDraw) setStatus(msg, msg.startsWith("Local: no"));
    refreshAll();
    markUi();
  }
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
  const owner = kind === "room" ? null : placementRoom();
  if (kind === "enemy" && !canAddEnemyType(activeMap(doc), place.enemy, owner?.id)) {
    setStatus(`Max ${ROOM_MAX_TYPES} enemy types per room`, true);
    return;
  }
  const extra = place.enemy ? { enemy: place.enemy } : {};
  if (owner) extra.roomId = owner.id;
  const obj = createObject(kind, p.x, p.y, p.z, extra);
  if (owner && kind !== "room" && kind !== "doorway") {
    obj.y = roomFloorY(owner, obj.x + obj.sx / 2, obj.z + obj.sz / 2);
  }
  clampObject(obj);
  activeMap(doc).objects.push(obj);
  if (kind === "doorway") {
    assignDoorRooms(doc, obj, owner);
    clampObject(obj);
  } else if (kind === "switch" && owner) {
    snapSwitchToRoom(obj, owner);
    clampObject(obj);
  }
  if (kind === "room") lastRoomId = obj.id;
  selectedIds = [obj.id];
  rememberSelectedRoom();
  markDirty();
  refreshAll();
  setStatus(place.enemy ? `Placed ${place.enemy}` : `Placed ${KINDS[kind].label}`);
}

function selectedObject() {
  if (selectedIds.length !== 1) return null;
  return activeMap(doc).objects.find((o) => o.id === selectedIds[0]) || null;
}

function rememberSelectedRoom() {
  for (let i = selectedIds.length - 1; i >= 0; i--) {
    const obj = activeMap(doc).objects.find((o) => o.id === selectedIds[i]);
    if (!obj) continue;
    if (obj.kind === "room") {
      lastRoomId = obj.id;
      break;
    }
    if (obj.roomId) {
      lastRoomId = obj.roomId;
      break;
    }
  }
  if (localDraw && !applyingEditor) {
    const msg = drawModeStatus();
    setStatus(msg, msg.startsWith("Local: no"));
  }
}

function placementRoom() {
  const obj = selectedObject();
  if (obj?.kind === "room") return obj;
  if (obj?.roomId) {
    const r = roomById(doc, obj.roomId);
    if (r) return r;
  }
  return roomById(doc, lastRoomId);
}

function deleteSelected() {
  if (editorMode === "layout") {
    if (!selectedIds.length) return;
    pushUndo();
    const drop = new Set(selectedIds);
    for (const o of activeMap(doc).objects) {
      if (o.kind === "room") continue;
      if (o.roomId && drop.has(o.roomId)) o.roomId = null;
      if (o.otherRoomId && drop.has(o.otherRoomId)) o.otherRoomId = null;
    }
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
    if (!obj || obj.kind === "room" || obj.kind === "doorway") continue;
    const room = roomUnderObject(doc, obj);
    obj.y = room ? roomFloorY(room, obj.x + obj.sx / 2, obj.z + obj.sz / 2) : 0;
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
  lastRoomId = null;
  collapsedRooms.clear();
  markDirty();
  markUi();
  refreshAll();
  setStatus(name);
}

function updateCenterChrome() {
  const titleEl = document.getElementById("center-title");
  const statsEl = document.getElementById("map-stats");
  if (editorMode === "layout") {
    const map = activeMap(doc);
    titleEl.textContent = map.name
      ? `Map ${doc.activeLevel} — ${map.name}`
      : `Map ${doc.activeLevel}`;
    if (statsEl) {
      const stats = mapStats(doc);
      statsEl.hidden = false;
      statsEl.textContent = formatMapStats(stats);
      statsEl.title = formatMapLoadTitle(stats);
      statsEl.classList.toggle("error", !!stats.overBudget);
    }
    return;
  }
  titleEl.textContent =
    editorMode === "weapons"
      ? WEAPON_LABELS[weaponKey] || "Weapons"
      : editorMode === "items"
        ? itemMeshKey === "backpack"
          ? "Backpack"
          : itemMeshKey
        : "Enemy";
  if (statsEl) {
    statsEl.hidden = true;
    statsEl.textContent = "";
    statsEl.title = "";
    statsEl.classList.remove("error");
  }
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
    btn.textContent = name;
    btn.title = display ? `${name} — ${display}` : name;
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
  rememberSelectedRoom();
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
      markUi();
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
      applyFrameLocal();
      markUi();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  });
}

function renderMeshKeyList(ul, keys) {
  if (!ul) return;
  ul.innerHTML = "";
  if (!doc.items) doc.items = {};
  for (const key of keys) {
    const li = document.createElement("li");
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = key === "backpack" ? "Backpack" : key;
    if (key === itemMeshKey) btn.className = "active";
    btn.addEventListener("click", () => {
      itemMeshKey = key;
      if (!doc.items[key]) doc.items[key] = { verts: [], lines: [] };
      itemView.clearSelection();
      persistEditorSettings();
      refreshAll();
    });
    li.appendChild(btn);
    ul.appendChild(li);
  }
}

function renderItemList() {
  renderMeshKeyList(document.getElementById("item-mesh-list"), ITEM_MESH_KEYS);
  renderMeshKeyList(document.getElementById("door-mesh-list"), DOOR_MESH_KEYS);
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

function syncSharewareFolderButtons() {
  const folder = sharewareFolderName();
  const label = folder ? "Change folder…" : "Open shareware folder";
  const weaponBtn = document.getElementById("btn-weapon-folder");
  if (weaponBtn) weaponBtn.textContent = label;
  const animBtn = document.getElementById("btn-anim-folder");
  if (animBtn) animBtn.textContent = label;
  const exportBtn = document.getElementById("btn-weapon-export");
  if (exportBtn) exportBtn.disabled = !Object.keys(sharewareWeapons).length;
}

function refreshWeaponClipStatus() {
  if (editorMode !== "weapons") return;
  if (!sharewareWeapons[weaponKey]) return;
  const n = selectedWeaponFrames().length;
  setStatus(`${WEAPON_LABELS[weaponKey]} · ${n} export frame${n === 1 ? "" : "s"}`);
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
      clampWeaponPreviewFrame();
      markUi();
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

function rotateRow(labelText, onClick) {
  const wrap = document.createElement("div");
  wrap.className = "vec3-inputs";
  const btn = document.createElement("button");
  btn.type = "button";
  btn.textContent = "Rotate";
  btn.addEventListener("click", onClick);
  const lbl = document.createElement("span");
  lbl.className = "rot-label";
  lbl.textContent = labelText;
  wrap.append(btn, lbl);
  return field("Rotate", wrap);
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

/** @type {"bg"|"line"|"fx"|"wpn"} */
let roomColorChannel = "bg";

const ROOM_COLOR_CHANNELS = [
  { id: "bg", label: "Background", get: (o) => o.bgColor ?? ROOM_BG_DEFAULT, set: (o, v) => (o.bgColor = v) },
  { id: "line", label: "Lines", get: (o) => o.lineColor ?? ROOM_LINE_DEFAULT, set: (o, v) => (o.lineColor = v) },
  { id: "fx", label: "FX", get: (o) => o.fxColor ?? ROOM_FX_DEFAULT, set: (o, v) => (o.fxColor = v) },
  { id: "wpn", label: "Weapon", get: (o) => o.weaponColor ?? ROOM_WPN_DEFAULT, set: (o, v) => (o.weaponColor = v) },
];

function roomPaletteEditor(obj, apply) {
  const wrap = document.createElement("div");
  wrap.className = "field color-field room-palette";
  const span = document.createElement("span");
  span.textContent = "Colours";
  const channels = document.createElement("div");
  channels.className = "room-color-channels";
  const active = ROOM_COLOR_CHANNELS.find((c) => c.id === roomColorChannel) || ROOM_COLOR_CHANNELS[0];
  for (const ch of ROOM_COLOR_CHANNELS) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "room-color-channel" + (ch.id === active.id ? " active" : "");
    const val = ch.get(obj);
    btn.title = `${ch.label}: ${val} ${C64_NAMES[val]}`;
    btn.style.background = C64_HEX[val];
    const lbl = document.createElement("span");
    lbl.textContent = ch.label;
    btn.appendChild(lbl);
    btn.addEventListener("click", () => {
      roomColorChannel = ch.id;
      renderInspector();
    });
    channels.appendChild(btn);
  }
  const row = document.createElement("div");
  row.className = "color-swatches";
  const cur = active.get(obj);
  for (let i = 0; i < 16; i++) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "swatch" + (i === cur ? " selected" : "");
    btn.title = `${i}: ${C64_NAMES[i]}`;
    btn.style.background = C64_HEX[i];
    btn.addEventListener("click", () =>
      apply(() => {
        active.set(obj, i);
      })
    );
    row.appendChild(btn);
  }
  wrap.append(span, channels, row);
  return wrap;
}

function renderInspector() {
  const root = document.getElementById("right-editors");
  root.innerHTML = "";
  if (editorMode === "items") {
    const h = document.createElement("h2");
    h.textContent = "Item";
    root.appendChild(h);
    if (!doc.items) doc.items = {};
    if (!doc.items[itemMeshKey]) doc.items[itemMeshKey] = { verts: [], lines: [] };
    const stats = itemMeshStats(doc.items[itemMeshKey]);
    const p = document.createElement("p");
    p.className = stats.over ? "error" : "muted";
    p.textContent = `${stats.nv} verts · ${stats.ne} lines · unique X ${stats.nx}/${ITEM_MAX_UNIQUE} · unique Z ${stats.nz}/${ITEM_MAX_UNIQUE} · ~${stats.bytes} B`;
    root.appendChild(p);
    if (itemMeshKey !== "backpack" && !doc.items[itemMeshKey].verts.length) {
      const f = document.createElement("p");
      f.className = "muted";
      f.textContent = isDoorMeshKey(itemMeshKey)
        ? "Empty — falls back to Tech."
        : "Empty — falls back to backpack.";
      root.appendChild(f);
    }
    const sel = itemView.selection();
    const row = document.createElement("div");
    row.className = "btn-row";
    const addV = document.createElement("button");
    addV.type = "button";
    addV.textContent = "Add Vert";
    addV.title = "V";
    addV.addEventListener("click", () => itemView.addVertAtOrigin());
    const addL = document.createElement("button");
    addL.type = "button";
    addL.textContent = "Add Line";
    addL.title = "L";
    addL.disabled = sel.verts.length !== 2;
    addL.addEventListener("click", () => itemView.addLineFromSelection());
    const copy = document.createElement("button");
    copy.type = "button";
    copy.textContent = "Copy";
    copy.title = "Ctrl+C — verts plus connected edges";
    copy.disabled = !sel.verts.length && !sel.lines.length;
    copy.addEventListener("click", () => itemView.copySelection());
    const paste = document.createElement("button");
    paste.type = "button";
    paste.textContent = "Paste";
    paste.title = "Ctrl+V — skipped if it would exceed counts";
    paste.disabled = !itemView.hasClipboard();
    paste.addEventListener("click", () => itemView.pasteSelection());
    const del = document.createElement("button");
    del.type = "button";
    del.className = "danger";
    del.textContent = "Delete";
    del.disabled = !sel.verts.length && !sel.lines.length;
    del.addEventListener("click", () => itemView.deleteSelection());
    row.append(addV, addL, copy, paste, del);
    root.appendChild(row);
    const hint = document.createElement("p");
    hint.className = "muted";
    hint.textContent = "Grid −4…4 · origin at 0,0,0 · Add Vert places at origin.";
    root.appendChild(hint);
    return;
  }
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
      const map = activeMap(doc);
      const selectedRooms = selectedIds
        .map((id) => map.objects.find((o) => o.id === id))
        .filter((o) => o && o.kind === "room");
      if (selectedRooms.length >= 2) {
        const rotY = document.createElement("button");
        rotY.type = "button";
        rotY.textContent = "Rotate Y";
        rotY.addEventListener("click", () => {
          pushUndo();
          rotateRoomsBlockY(
            doc,
            selectedRooms.map((r) => r.id),
            1
          );
          markDirty();
          refreshAll();
        });
        row.append(rotY);
      }
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
      root.appendChild(roomPaletteEditor(obj, apply));

      const shapeSel = document.createElement("select");
      for (const s of ROOM_SHAPES) {
        const opt = document.createElement("option");
        opt.value = s;
        opt.textContent = s === "box" ? "Box" : s;
        if (clampRoomShape(obj.shape) === s) opt.selected = true;
        shapeSel.appendChild(opt);
      }
      shapeSel.addEventListener("change", () => apply(() => applyRoomShape(obj, shapeSel.value)));
      root.appendChild(field("Shape", shapeSel));

      const rotAxes = clampRoomShape(obj.shape) !== "box" ? ["x", "y", "z"] : ["y"];
      const rotRow = document.createElement("div");
      rotRow.className = "btn-row rot-axes";
      for (const axis of rotAxes) {
        const btn = document.createElement("button");
        btn.type = "button";
        btn.textContent = axis.toUpperCase();
        btn.addEventListener("click", () =>
          apply(() => {
            if (axis === "y") rotateRoomY(doc, obj, 1);
            else rotateRoom(obj, axis, 1);
          })
        );
        rotRow.append(btn);
      }
      root.appendChild(field("Rotate", rotRow));
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
      sel.addEventListener("change", () => {
        const next = sel.value;
        if (next !== obj.enemy && !canAddEnemyType(activeMap(doc), next, obj.roomId)) {
          sel.value = obj.enemy || "Grunt";
          setStatus(`Max ${ROOM_MAX_TYPES} enemy types per room`, true);
          return;
        }
        apply(() => (obj.enemy = next));
      });
      root.appendChild(field("Type", sel));
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = !!obj.patrol;
      chk.addEventListener("change", () => apply(() => (obj.patrol = chk.checked)));
      root.appendChild(field("Patrol", chk));
    }
    if (isFigureObject(obj) || obj.kind === "teleporter_dest") {
      root.appendChild(
        rotateRow(ENEMY_FACINGS[clampEnemyRot(obj.rot ?? 0)], () =>
          apply(() => (obj.rot = cycleEnemyRot(obj.rot ?? 0)))
        )
      );
    }
    if (obj.kind === "trigger") {
      const sel = document.createElement("select");
      for (const p of TRIGGER_PURPOSES) {
        const opt = document.createElement("option");
        opt.value = p;
        opt.textContent = TRIGGER_PURPOSE_LABELS[p];
        if (clampTriggerPurpose(obj.purpose) === p) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () => apply(() => (obj.purpose = sel.value)));
      root.appendChild(field("Purpose", sel));
      if (clampTriggerPurpose(obj.purpose) === "message") {
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
      if (triggerUsesTag(obj.purpose)) {
        const tagInp = document.createElement("input");
        tagInp.type = "text";
        tagInp.maxLength = MAX_TAG_LEN;
        tagInp.value = obj.tag || "";
        tagInp.placeholder = "destination tag";
        tagInp.addEventListener("change", () => apply(() => (obj.tag = clampTag(tagInp.value))));
        root.appendChild(field("Tag", tagInp));
      }
    }
    if (usesLinkTag(obj.kind)) {
      const tagInp = document.createElement("input");
      tagInp.type = "text";
      tagInp.maxLength = MAX_TAG_LEN;
      tagInp.value = obj.tag || "";
      tagInp.placeholder =
        obj.kind === "switch" || obj.kind === "elevator" ? "elevator link" : "destination tag";
      tagInp.addEventListener("change", () => apply(() => (obj.tag = clampTag(tagInp.value))));
      root.appendChild(field("Tag", tagInp));
    }
    if (obj.kind === "elevator") {
      const autoChk = document.createElement("input");
      autoChk.type = "checkbox";
      autoChk.checked = elevHeightsAuto(obj);
      autoChk.addEventListener("change", () =>
        apply(() => {
          obj.elevAuto = autoChk.checked;
          if (!obj.elevAuto) {
            const room = roomById(doc, obj.roomId);
            const floorY = room ? room.y | 0 : 0;
            const stops = elevStopBottoms(doc, { ...obj, elevAuto: true });
            obj.elevLow = stops.dest - floorY;
            obj.elevHigh = stops.home - floorY;
            clampElevHeights(obj);
          }
        })
      );
      root.appendChild(field("Auto heights", autoChk));
      if (!elevHeightsAuto(obj)) {
        clampElevHeights(obj);
        const lowInp = document.createElement("input");
        lowInp.type = "number";
        lowInp.step = "1";
        lowInp.value = String(obj.elevLow);
        lowInp.addEventListener("change", () =>
          apply(() => {
            obj.elevLow = lowInp.value | 0;
            clampElevHeights(obj);
          })
        );
        root.appendChild(field("Low (vs room)", lowInp));
        const highInp = document.createElement("input");
        highInp.type = "number";
        highInp.step = "1";
        highInp.value = String(obj.elevHigh);
        highInp.addEventListener("change", () =>
          apply(() => {
            obj.elevHigh = highInp.value | 0;
            clampElevHeights(obj);
          })
        );
        root.appendChild(field("High (vs room)", highInp));
      }
    }
    if (obj.kind === "pickup") {
      const sel = document.createElement("select");
      for (const t of PICKUP_TYPES) {
        const opt = document.createElement("option");
        opt.value = t;
        opt.textContent = t;
        if (clampPickupType(obj.pickup) === t) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () => apply(() => (obj.pickup = sel.value)));
      root.appendChild(field("Contains", sel));
    }
    if (obj.kind === "platform") {
      const chk = document.createElement("input");
      chk.type = "checkbox";
      chk.checked = obj.collide !== false;
      chk.addEventListener("change", () => apply(() => (obj.collide = chk.checked)));
      root.appendChild(field("Collide", chk));
    }
    if (obj.kind !== "room") {
      const sel = document.createElement("select");
      const none = document.createElement("option");
      none.value = "";
      none.textContent = "(none)";
      sel.appendChild(none);
      for (const r of roomsOf(doc)) {
        const opt = document.createElement("option");
        opt.value = r.id;
        opt.textContent = r.name ? `Room  ${r.name}` : "Room";
        if (r.id === obj.roomId) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () =>
        apply(() => {
          obj.roomId = sel.value || null;
          if (obj.kind === "doorway") assignDoorRooms(doc, obj, roomById(doc, obj.roomId));
          if (obj.kind === "switch") snapSwitchToRoom(obj, roomById(doc, obj.roomId));
        })
      );
      root.appendChild(field("Room", sel));
    }
    if (obj.kind === "doorway") {
      const sel = document.createElement("select");
      const none = document.createElement("option");
      none.value = "";
      none.textContent = "(none)";
      sel.appendChild(none);
      for (const r of roomsOf(doc)) {
        const opt = document.createElement("option");
        opt.value = r.id;
        opt.textContent = r.name ? `Room  ${r.name}` : "Room";
        if (r.id === obj.otherRoomId) opt.selected = true;
        sel.appendChild(opt);
      }
      sel.addEventListener("change", () =>
        apply(() => {
          obj.otherRoomId = sel.value || null;
          snapDoorBetweenRooms(obj, roomById(doc, obj.roomId), roomById(doc, obj.otherRoomId));
        })
      );
      root.appendChild(field("Other room", sel));
      const lockSel = document.createElement("select");
      for (const t of DOOR_LOCKS) {
        const opt = document.createElement("option");
        opt.value = t;
        opt.textContent = DOOR_LOCK_LABELS[t];
        if (clampDoorLock(obj.lockKey) === t) opt.selected = true;
        lockSel.appendChild(opt);
      }
      lockSel.addEventListener("change", () => apply(() => (obj.lockKey = lockSel.value)));
      root.appendChild(field("Lock", lockSel));
      const typeSel = document.createElement("select");
      for (const t of DOOR_TYPES) {
        const opt = document.createElement("option");
        opt.value = t;
        opt.textContent = t;
        if (clampDoorType(obj.doorType) === t) opt.selected = true;
        typeSel.appendChild(opt);
      }
      typeSel.addEventListener("change", () => apply(() => (obj.doorType = typeSel.value)));
      root.appendChild(field("Type", typeSel));
    }
    const sizeP = document.createElement("p");
    sizeP.className = "muted";
    sizeP.textContent = KINDS[obj.kind].fixed
      ? `Fixed size ${obj.sx}×${obj.sy}×${obj.sz}`
      : `Size ${obj.sx}×${obj.sy}×${obj.sz}`;
    root.appendChild(sizeP);
    if (obj.kind === "slope") {
      const axis = (obj.axis === "x" ? "X" : "Z") + (obj.dir === 1 ? "+" : "−");
      root.appendChild(rotateRow(axis, () => apply(() => cycleSlopeOrient(obj))));
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

  const lodInp = document.createElement("input");
  lodInp.type = "number";
  lodInp.min = "0";
  lodInp.max = "255";
  lodInp.step = "1";
  lodInp.value = String(clampEnemyLodZ(e.lodZ, e.name));
  lodInp.title = "Full stick project while view Z < this (cheap LOD beyond)";
  lodInp.addEventListener("change", () => {
    pushUndo();
    e.lodZ = clampEnemyLodZ(lodInp.value, e.name);
    lodInp.value = String(e.lodZ);
    markDirty();
    refreshAll();
  });
  root.appendChild(field("LOD Z", lodInp));

  const timeline = getTimeline(e);
  const mdl = sharewareModels[e.name];
  const hasStick = !!stickClipFor(e, activeTimelineClip());
  if (timeline.length) {
    const clip = activeTimelineClip() || timeline[0];
    if (clipIndex >= timeline.length) clipIndex = 0;
    frameLocal = Math.max(0, Math.min(frameLocal, clip.len - 1));

    if (mdl?.clips?.length) {
      const selected = new Set(exportClipNames(e, mdl));
      const listLbl = document.createElement("h2");
      listLbl.textContent = "Export clips";
      root.appendChild(listLbl);
      const ul = document.createElement("ul");
      ul.className = "export-clip-list";
      timeline.forEach((c, i) => {
        const li = document.createElement("li");
        const chk = document.createElement("input");
        chk.type = "checkbox";
        chk.checked = selected.has(c.name);
        chk.addEventListener("change", () => {
          pushUndo();
          const next = new Set(exportClipNames(e, mdl));
          if (chk.checked) next.add(c.name);
          else next.delete(c.name);
          e.exportClips = timeline.map((cl) => cl.name).filter((n) => next.has(n));
          markDirty();
          retargetMdlFrames({ status: true });
          refreshAll();
        });
        const nameBtn = document.createElement("button");
        nameBtn.type = "button";
        nameBtn.className = "frame-name" + (i === clipIndex ? " current" : "");
        nameBtn.textContent = `${c.name} (${c.len})`;
        nameBtn.addEventListener("click", () => {
          clipIndex = i;
          frameLocal = 0;
          applyFrameLocal();
          markUi();
          refreshAll();
        });
        li.append(chk, nameBtn);
        ul.appendChild(li);
      });
      root.appendChild(ul);
      const packed = packedPoseBytes(e);
      const mem = document.createElement("p");
      mem.className = "muted anim-mem";
      mem.classList.toggle("error", packed.bytes > ENEMY_POSE_MAX);
      mem.title = "Packed pose PRG: 2 + logical map + stored gx/gy/gz (13×3). Clip tables are in GAME.";
      mem.textContent = formatPackedPoseMem(packed);
      root.appendChild(mem);
    } else {
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
        applyFrameLocal();
        markUi();
        refreshAll();
      });
      root.appendChild(field("Clip", clipSel));
    }

    const transport = document.createElement("div");
    transport.className = "anim-transport";
    const slider = document.createElement("input");
    slider.id = "anim-frame-slider";
    slider.type = "range";
    slider.min = "0";
    slider.max = String(Math.max(0, clip.len - 1));
    slider.value = String(frameLocal);
    slider.addEventListener("input", () => {
      frameLocal = Number(slider.value) | 0;
      applyFrameLocal();
      markUi();
      animView.draw();
    });
    transport.appendChild(slider);

    const playRow = document.createElement("div");
    playRow.className = "btn-row anim-transport-btns";
    const playBtn = document.createElement("button");
    playBtn.id = "btn-anim-play";
    playBtn.type = "button";
    playBtn.textContent = animPlaying ? "Pause" : "Play";
    if (animPlaying) playBtn.className = "active";
    playBtn.addEventListener("click", toggleAnimPlay);
    const loopBtn = document.createElement("button");
    loopBtn.id = "btn-anim-loop";
    loopBtn.type = "button";
    loopBtn.textContent = "Loop";
    if (animLoop) loopBtn.className = "active";
    loopBtn.addEventListener("click", () => {
      animLoop = !animLoop;
      updateLoopButton();
    });
    playRow.append(playBtn, loopBtn);
    transport.appendChild(playRow);
    root.appendChild(transport);
  }

  const counts = document.createElement("p");
  counts.className = "muted";
  const clip = activeTimelineClip() || (e.clips?.length ? clipForFrame(e.clips, frameIndex) : null);
  const stick = stickClipFor(e, clip);
  const stickFrame = stick ? stick.start + frameLocal : 0;
  const height = frameHeight(e.frames[stickFrame] || e.frames[0]);
  counts.textContent = `13 verts · 13 lines · height ${height}`;
  root.appendChild(counts);

  if (hasStick && selectedVerts.length === 1) {
    const vi = selectedVerts[0];
    const v = e.frames[stickFrame][vi];
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
      ? `Box-select mesh verts for ${JOINT_NAMES[bindJoint]} · Shift add · Esc stops bind · F focus · RMB orbit`
      : "LMB box-select verts · click-drag unselected on camera plane · gizmo moves selection · X/Y/Z nudge · [ ] frames · F focus · MMB pan · Alt+LMB / RMB orbit · Alt+RMB zoom";
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
  persistMdlRigBackup();
  retargetMdlFrames({ status: true });
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
  if (restoreMdlRigBackup()) markDirty();
  refreshPanels();
  if (editorMode === "anim") {
    animView.draw();
    retargetMdlFrames();
    refreshPanels();
  }
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

function rigBindingComplete(rig) {
  return rig.jointVerts.every((list) => list.length > 0);
}

/** Retarget checked MDL clips onto stick frames when all joints are bound. */
function retargetMdlFrames(options = {}) {
  const { status = false } = options;
  const e = activeEnemy();
  if (!e) return false;
  const mdl = activeMdl();
  if (!mdl) return false;
  const rig = ensureEnemyRig(e);
  if (!rigBindingComplete(rig)) return false;
  const names = exportClipNames(e, mdl);
  if (!names.length) return false;
  const rest = e.frames[0] || dummyFrameFor(e.name);
  const { frames, clips } = buildStickFramesFromMdl(mdl, rig, mdlScale, rest, clampVert, names);
  if (!frames.length) return false;
  const keepName = activeTimelineClip()?.name;
  e.frames = frames;
  e.clips = clips;
  e.exportClips = clips.map((c) => c.name);
  frameLocal = 0;
  if (keepName) {
    const timeline = getTimeline(e);
    const idx = timeline.findIndex((c) => c.name === keepName);
    clipIndex = idx >= 0 ? idx : 0;
  } else {
    clipIndex = 0;
  }
  applyFrameLocal();
  markDirty();
  if (status) setStatus(`Retargeted ${frames.length} frames`);
  return true;
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
  const names = mdl ? exportClipNames(e, mdl) : [];
  const selCount = names.length;
  const totalClips = mdl?.clips?.length || 0;
  const selFrames = names.reduce((n, name) => {
    const c = mdl?.clips?.find((cl) => cl.name === name);
    return n + (c?.frames.length || 0);
  }, 0);
  if (mdl) {
    status.textContent = folder
      ? `${folder} · ${mdl.numVerts} mesh verts · ${selCount}/${totalClips} clips · ${selFrames} frames`
      : `${mdl.numVerts} mesh verts · ${selCount}/${totalClips} clips · ${selFrames} frames`;
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

  const jointList = document.createElement("ul");
  jointList.className = "joint-list";
  const rig = ensureEnemyRig(e);
  JOINT_NAMES.forEach((name, i) => {
    const li = document.createElement("li");
    li.className = "joint-row" + (bindJoint === i ? " active" : "");
    const label = document.createElement("span");
    label.className = "joint-name";
    const n = rig.jointVerts[i].length;
    label.classList.toggle("unbound", !n);
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
    li.append(label, bindBtn);
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
  const stick = stickClipFor(e, activeTimelineClip());
  if (stick) frameIndex = stick.start + frameLocal;
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
  const slider = document.getElementById("anim-frame-slider");
  if (slider) slider.value = String(frameLocal);
  if (editorMode === "anim") animView.draw();
}

function stepFrame(d) {
  if (!advanceFrame(d)) return;
  markUi();
  refreshAll();
}

function stepWeaponFrame(d) {
  const frames = selectedWeaponFrames();
  if (!frames.length) return;
  let i = frames.indexOf(weaponFrame);
  if (i < 0) i = 0;
  weaponFrame = frames[(i + d + frames.length) % frames.length];
  markUi();
  refreshAll();
}

function stopAnimPlay() {
  animPlaying = false;
  if (animPlayTimer) {
    clearInterval(animPlayTimer);
    animPlayTimer = null;
  }
}

function updateLoopButton() {
  const loopBtn = document.getElementById("btn-anim-loop");
  if (!loopBtn) return;
  loopBtn.classList.toggle("active", animLoop);
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
  markUi();
}

function setMdlScale(value) {
  mdlScale = clampMdlScale(value);
  const range = document.getElementById("mdl-scale");
  const numInp = document.getElementById("mdl-scale-num");
  const shown = String(mdlScale);
  if (range && range.value !== shown) range.value = shown;
  if (numInp && numInp.value !== shown) numInp.value = shown;
  if (editorMode === "anim") {
    retargetMdlFrames();
    animView.draw();
  }
  markUi();
}

function nudgeVert(axis, delta) {
  const e = activeEnemy();
  if (!e.clips?.length) {
    setStatus("Bind all joints to retarget from MDL first", true);
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
  renderItemList();
  renderInspector();
  syncWeaponScaleInputs();
  syncSharewareFolderButtons();
  overheadView.draw();
  if (editorMode === "layout") layoutView.draw();
  if (editorMode === "anim") animView.draw();
  if (editorMode === "weapons") weaponView.draw();
  if (editorMode === "items") itemView.draw();
}

function refreshAll() {
  updateCenterChrome();
  refreshPanels();
  if (editorMode === "layout") layoutView.draw();
  else if (editorMode === "weapons") weaponView.draw();
  else if (editorMode === "items") itemView.draw();
  else animView.draw();
}

document.getElementById("btn-mode-layout").addEventListener("click", () => {
  setMode("layout");
});
document.getElementById("btn-mode-anim").addEventListener("click", () => {
  setMode("anim");
});
document.getElementById("btn-mode-weapons").addEventListener("click", () => {
  setMode("weapons");
});
document.getElementById("btn-mode-items")?.addEventListener("click", () => {
  setMode("items");
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
document.getElementById("btn-anim-folder")?.addEventListener("click", () => void openSharewareFolder());
document.getElementById("btn-weapon-export")?.addEventListener("click", () => {
  exportWeaponPngs().catch((err) => setStatus(String(err.message || err), true));
});
document.getElementById("btn-draw-all").addEventListener("click", () => {
  setDrawMode(false);
});
document.getElementById("btn-draw-local").addEventListener("click", () => {
  setDrawMode(true);
});
document.getElementById("btn-draw-neighbours")?.addEventListener("click", () => {
  setNeighbourDraw(!neighbourDraw);
});
document.getElementById("btn-ortho-top").addEventListener("click", () => setOrthoMode("top"));
document.getElementById("btn-ortho-left").addEventListener("click", () => setOrthoMode("left"));
document.getElementById("btn-ortho-forward").addEventListener("click", () => setOrthoMode("forward"));
document.getElementById("btn-undo").addEventListener("click", undo);
document.getElementById("btn-redo").addEventListener("click", redo);
document.getElementById("btn-save").addEventListener("click", async () => {
  await saveNow("Saved");
});

window.addEventListener("pagehide", () => persistEditorSettings());
document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "hidden") persistEditorSettings();
});

function applyLoadedDoc(loaded) {
  doc = normalizeDocument(loaded);
  persistMdlRigBackup();
  const stored = loadEditorSettings(docFileName());
  applyEditorState(stored || loaded.editor || doc.editor);
  if (doc.editor) delete doc.editor;
  editorSettingsReady = true;
  persistEditorSettings();
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
      await restoreSharewareQuietly();
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
  if (editorMode === "items" && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "c") {
    e.preventDefault();
    itemView.copySelection();
    return;
  }
  if (editorMode === "items" && (e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "v") {
    e.preventDefault();
    itemView.pasteSelection();
    return;
  }
  if (e.key === "Delete" || e.key === "Backspace") {
    if (editorMode === "layout") {
      e.preventDefault();
      deleteSelected();
    }
    if (editorMode === "items") {
      e.preventDefault();
      itemView.deleteSelection();
      return;
    }
  }
  if (editorMode === "items" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    const k = e.key.toLowerCase();
    if (k === "v") {
      e.preventDefault();
      itemView.addVertAtOrigin();
      return;
    }
    if (k === "l") {
      e.preventDefault();
      itemView.addLineFromSelection();
      return;
    }
  }
  if (e.key.toLowerCase() === "g" && editorMode === "layout" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    if (selectedIds.length) {
      e.preventDefault();
      dropSelectedToFloor();
      return;
    }
  }
  if (e.key.toLowerCase() === "f" && !e.ctrlKey && !e.metaKey && !e.altKey) {
    if (editorMode === "layout") {
      if (selectedIds.length) {
        e.preventDefault();
        if (layoutView.focusSelection()) setStatus("Focused selection");
      }
      return;
    }
    if (editorMode === "anim") {
      e.preventDefault();
      animView.focusObject();
      setStatus("Focused object");
      return;
    }
    if (editorMode === "items") {
      e.preventDefault();
      itemView.focusObject();
      setStatus("Focused object");
      return;
    }
  }
  if (e.key.toLowerCase() === "r" && editorMode === "layout") {
    const obj = selectedObject();
    if (obj && (isFigureObject(obj) || obj.kind === "teleporter_dest")) {
      e.preventDefault();
      pushUndo();
      obj.rot = cycleEnemyRot(obj.rot ?? 0);
      markDirty();
      refreshAll();
    }
    if (obj && obj.kind === "slope") {
      e.preventDefault();
      pushUndo();
      cycleSlopeOrient(obj);
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
    if (dir) {
      await loadSharewareFromHandle(dir);
      return;
    }
    const stored = await getStoredSharewareHandle();
    if (stored && !Object.keys(sharewareModels).length) {
      const name = sharewareFolderName();
      setStatus(
        name
          ? `${name} saved — click Change folder… to reload MDL data`
          : "Click Open shareware folder to load MDL data"
      );
    }
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
    if (restoreMdlRigBackup()) {
      markDirty();
      refreshAll();
    }
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
