import {
  ROOM_SHAPES,
  clampRoomShape,
  clampRoomSplits,
  applyRoomShape,
  roomGeometry,
  pointInRoom,
  aabbOverlapsRoom,
  roomFloorY,
  snapDoorToRoom,
  doorNearFaceId,
  nudgeDoorOutside,
  rotateRoom,
  preserveRoomSplits,
  roomBasis,
  defaultRoomSplits,
} from "./roomGeom.js";

export {
  ROOM_SHAPES,
  clampRoomShape,
  clampRoomSplits,
  applyRoomShape,
  roomGeometry,
  pointInRoom,
  aabbOverlapsRoom,
  roomFloorY,
  snapDoorToRoom,
  doorNearFaceId,
  nudgeDoorOutside,
  rotateRoom,
  preserveRoomSplits,
  roomBasis,
  defaultRoomSplits,
};

export function uid() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  return `id-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export const WORLD_MIN = 0;
export const WORLD_MAX = 255;
export const WORLD_SIZE = 256;
export const MAX_VERTS = 13;
export const MAX_LINES = 13;
export const WEAPON_VERT = 12;
export const WRIST_R = 7;
export const JOINT_NAMES = [
  "Hip L",
  "Hip R",
  "Neck",
  "Head",
  "Elbow L",
  "Wrist L",
  "Elbow R",
  "Wrist R",
  "Knee L",
  "Ankle L",
  "Knee R",
  "Ankle R",
  "Weapon",
];
export const VERT_MIN = -64;
export const VERT_MAX = 63;
export const DEFAULT_MDL_SCALE = 0.7;
const OLD_DEFAULT_MDL_SCALE = 0.57;
export const ANIM_ORBIT_DIST_MIN = 16;
export const ANIM_ORBIT_DIST_MAX = 400;
export const DOC_VERSION = 7;
export const DEFAULT_WEAPON_SCALE = 0.4;
export const WEAPON_KEYS = ["axe", "shot2", "nail", "rock"];
export const WEAPON_LABELS = {
  axe: "Axe",
  shot2: "Super shotgun",
  nail: "Nailgun",
  rock: "Grenade launcher",
};

export function clampMdlScale(n) {
  const v = Number(n);
  if (!Number.isFinite(v)) return DEFAULT_MDL_SCALE;
  return Math.max(0.1, Math.min(2, v));
}

/** Default room viewport colours (C64 indices). */
export const ROOM_BG_DEFAULT = 9;
export const ROOM_LINE_DEFAULT = 7;
export const ROOM_FX_DEFAULT = 1;
export const ROOM_WPN_DEFAULT = 0;
/** @deprecated Use ROOM_BG_DEFAULT */
export const ROOM_SKY_DEFAULT = ROOM_BG_DEFAULT;
/** @deprecated */
export const ROOM_FLOOR_DEFAULT = ROOM_BG_DEFAULT;

/** Pepto Commodore 64 palette (indices 0–15). */
export const C64_HEX = [
  "#000000",
  "#ffffff",
  "#813338",
  "#75cec8",
  "#8e3c97",
  "#56ac4d",
  "#40318d",
  "#bfce72",
  "#8e5029",
  "#553f00",
  "#c46c71",
  "#4a4a4a",
  "#7b7b7b",
  "#a9ff9f",
  "#706deb",
  "#b2b2b2",
];

export const C64_NAMES = [
  "black",
  "white",
  "red",
  "cyan",
  "purple",
  "green",
  "blue",
  "yellow",
  "orange",
  "brown",
  "light red",
  "dark grey",
  "grey",
  "light green",
  "light blue",
  "light grey",
];

export function colorHex(index) {
  return C64_HEX[index & 15] || C64_HEX[0];
}

/** Normalize JSON colour (0–15) to a C64 index. */
export function normalizeColor(value, fallback = 0) {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.max(0, Math.min(15, value | 0));
  }
  const asNum = Number(value);
  if (Number.isFinite(asNum)) return Math.max(0, Math.min(15, asNum | 0));
  return fallback;
}

export const KINDS = {
  room: {
    id: "room",
    label: "Room",
    color: "#c8ccd4",
    defaultSize: [16, 12, 16],
    fixed: false,
    slope: false,
  },
  crate: {
    id: "crate",
    label: "Crate",
    color: "#d4893a",
    defaultSize: [6, 6, 6],
    fixed: false,
    slope: false,
  },
  elevator: {
    id: "elevator",
    label: "Elevator",
    color: "#3ab4d4",
    defaultSize: [4, 1, 4],
    fixed: false,
    slope: false,
  },
  slope: {
    id: "slope",
    label: "Ramp",
    color: "#5cb85c",
    defaultSize: [4, 2, 4],
    fixed: false,
    slope: true,
  },
  platform: {
    id: "platform",
    label: "Platform",
    color: "#b8a878",
    defaultSize: [4, 1, 4],
    fixed: false,
    slope: false,
  },
  doorway: {
    id: "doorway",
    label: "Doorway",
    color: "#e6c84a",
    defaultSize: [4, 5, 1],
    fixed: true,
    slope: false,
  },
  switch: {
    id: "switch",
    label: "Switch",
    color: "#d45ec8",
    defaultSize: [2, 3, 1],
    fixed: true,
    slope: false,
  },
  enemy: {
    id: "enemy",
    label: "Enemy",
    color: "#e07070",
    defaultSize: [2, 4, 2],
    fixed: false,
    slope: false,
  },
  spawn: {
    id: "spawn",
    label: "Spawn",
    color: "#3ee06a",
    defaultSize: [2, 4, 2],
    fixed: false,
    slope: false,
  },
  trigger: {
    id: "trigger",
    label: "Trigger",
    color: "#7ec8e8",
    defaultSize: [8, 4, 8],
    fixed: false,
    slope: false,
  },
  teleporter: {
    id: "teleporter",
    label: "Teleporter",
    color: "#9b7eed",
    defaultSize: [4, 1, 4],
    fixed: false,
    slope: false,
  },
  teleporter_dest: {
    id: "teleporter_dest",
    label: "Teleport dest",
    color: "#c4a8ff",
    defaultSize: [2, 2, 2],
    fixed: true,
    slope: false,
  },
  key: {
    id: "key",
    label: "Key",
    color: "#f0d060",
    defaultSize: [2, 2, 2],
    fixed: false,
    slope: false,
  },
  backpack: {
    id: "backpack",
    label: "Backpack",
    color: "#6ec4a8",
    defaultSize: [1, 2, 1], // overwritten by applyBackpackProportions (1.5 tall, φ base)
    fixed: true,
    slope: false,
  },
  patrol: {
    id: "patrol",
    label: "Patrol point",
    color: "#e89050",
    defaultSize: [2, 2, 2],
    fixed: true,
    slope: false,
  },
};

/** Editor-only dashed / ghost volumes (not solid world geometry). */
export function isGhostKind(kind) {
  return (
    kind === "trigger" ||
    kind === "teleporter" ||
    kind === "teleporter_dest" ||
    kind === "patrol"
  );
}

/** Kinds linked by a shared editor tag (resolved to indices on export). */
export function usesLinkTag(kind) {
  return (
    kind === "switch" ||
    kind === "elevator" ||
    kind === "teleporter" ||
    kind === "teleporter_dest" ||
    kind === "key" ||
    kind === "patrol" ||
    kind === "enemy"
  );
}

/** Layout placements draw the first stick frame at this fraction of anim units (Grunt ~4 world high). */
export const LAYOUT_ENEMY_SCALE = 1 / 8;

/** Yaw octants, 0 = +Z (N / game forward). */
export const ENEMY_FACINGS = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];

export function clampEnemyRot(n) {
  const r = n | 0;
  if (!Number.isFinite(r)) return 0;
  return ((r % 8) + 8) % 8;
}

export const PALETTE_ORDER = [
  "room",
  "doorway",
  "switch",
  "slope",
  "platform",
  "crate",
  "elevator",
  "spawn",
  "trigger",
  "teleporter",
  "teleporter_dest",
  "key",
  "backpack",
  "patrol",
];
export const MAX_TRIGGER_TEXT = 80;
export const MAX_NAME_LEN = 40;
export const MAX_TAG_LEN = 16;

/** Elevator motion: descending = switch lower→wait→raise; automatic = stand-on same cycle; toggle = switch, stay until retrigger. */
export const ELEV_TYPES = ["descending", "automatic", "toggle"];

export function clampElevType(s) {
  return ELEV_TYPES.includes(s) ? s : "descending";
}

/** Backpack contents (ammo, weapon, or health pickup). */
export const BACKPACK_TYPES = [
  "shells",
  "nailgun",
  "nails",
  "grenade launcher",
  "grenades",
  "health 25%",
  "health 50%",
];

/** Height / base-side = φ. Fixed backpack: 1.5 tall. */
export const GOLDEN_RATIO = (1 + Math.sqrt(5)) / 2;
export const BACKPACK_HEIGHT = 1.5;
export const BACKPACK_SIDE = BACKPACK_HEIGHT / GOLDEN_RATIO;
export const BACKPACK_DEPTH = (BACKPACK_SIDE * Math.sqrt(3)) / 2;

export function clampBackpackType(s) {
  return BACKPACK_TYPES.includes(s) ? s : "shells";
}

/** Sequence among patrol points that share a tag (lower first). */
export function clampPatrolOrder(n) {
  const v = n | 0;
  if (!Number.isFinite(v)) return 0;
  return Math.max(0, Math.min(255, v));
}

/** Fixed equilateral tetra: height 1.5, base side = height/φ. */
export function applyBackpackProportions(obj) {
  obj.sx = BACKPACK_SIDE;
  obj.sy = BACKPACK_HEIGHT;
  obj.sz = BACKPACK_DEPTH;
  return obj;
}

export const LEVEL_NAMES = ["E1M1", "E1M2", "E1M3", "E1M4", "E1M5", "E1M6", "E1M7", "E1M8"];

export function clipForFrame(clips, index) {
  const list = Array.isArray(clips) ? clips : [];
  const i = index | 0;
  return list.find((c) => i >= c.start && i < c.start + c.len) || list[0] || null;
}

export function normalizeClips(raw, frameCount) {
  const n = Math.max(0, frameCount | 0);
  if (!n || !Array.isArray(raw) || !raw.length) return [];
  const out = [];
  for (const c of raw) {
    const name = String(c?.name || "clip");
    if (name === "legacy") continue;
    const start = Math.max(0, c.start | 0);
    const len = Math.max(1, c.len | 0);
    if (start >= n) continue;
    out.push({ name, start, len: Math.min(len, n - start) });
  }
  return out;
}

/** Shared 13-vert skeleton: L/R hip, neck, head, L/R elbow, L/R wrist, L/R knee, L/R ankle, weapon tip on right wrist. */
export const ENEMY_TYPES = [
  { name: "Grunt", scale: [1, 1, 1], rest: { 12: [0, 1, 8] } },
  {
    name: "Knight",
    scale: [1.15, 1.3, 1],
    rest: { 3: [0, 2, 0], 4: [-1, 1, 0], 6: [1, 1, 0], 12: [0, 10, -6] },
  },
  {
    name: "Rottweiler",
    scale: [1, 0.55, 1.35],
    rest: {
      0: [0, 1, -5],
      1: [0, 1, -5],
      2: [0, -1, 3],
      3: [0, -3, 8],
      4: [0, -3, 3],
      5: [0, -6, 5],
      6: [0, -3, 3],
      7: [0, -6, 5],
      12: [0, -3, 6],
    },
  },
  {
    name: "Scrag",
    scale: [0.85, 1.15, 0.9],
    rest: {
      0: [0, 8, 0],
      1: [0, 8, 0],
      8: [0, 6, 0],
      9: [0, 5, 0],
      10: [0, 6, 0],
      11: [0, 5, 0],
      4: [-2, 2, 0],
      5: [-4, 0, 2],
      6: [2, 2, 0],
      7: [4, 0, 2],
      12: [3, 1, 7],
    },
  },
  {
    name: "Ogre",
    scale: [1.35, 1.05, 1.1],
    rest: { 5: [0, -1, 0], 7: [0, -1, 0], 12: [6, -4, 6] },
  },
  {
    name: "Shambler",
    scale: [1.5, 1.45, 1.2],
    rest: {
      4: [-2, -2, 0],
      5: [-3, -6, 1],
      6: [2, -2, 0],
      7: [3, -6, 1],
      12: [4, -8, 5],
    },
  },
  {
    name: "Chthon",
    scale: [1.8, 0.75, 1.6],
    rest: {
      2: [0, 2, 0],
      3: [0, 4, 2],
      4: [-3, 0, 0],
      5: [-5, -2, 0],
      6: [3, 0, 0],
      7: [5, -2, 0],
      12: [8, -2, 5],
    },
  },
];

export const FACES = [
  { id: "+z", axis: "z", sign: 1, label: "+Z" },
  { id: "-z", axis: "z", sign: -1, label: "-Z" },
  { id: "+x", axis: "x", sign: 1, label: "+X" },
  { id: "-x", axis: "x", sign: -1, label: "-X" },
];

export function clampByte(n) {
  return Math.max(WORLD_MIN, Math.min(WORLD_MAX, n | 0));
}

export function clampSize(origin, size) {
  const o = clampByte(origin);
  const s = Math.max(1, size | 0);
  return Math.min(s, WORLD_SIZE - o);
}

export function clampVert(n) {
  const v = n | 0;
  return Math.max(VERT_MIN, Math.min(VERT_MAX, v));
}

export function aabbEnd(box) {
  return {
    x: box.x + box.sx,
    y: box.y + box.sy,
    z: box.z + box.sz,
  };
}

/** Inclusive face-touch counts as overlap (shared portal wall). */
export function aabbOverlap(a, b) {
  return (
    a.x <= b.x + b.sx &&
    a.x + a.sx >= b.x &&
    a.y <= b.y + b.sy &&
    a.y + a.sy >= b.y &&
    a.z <= b.z + b.sz &&
    a.z + a.sz >= b.z
  );
}

export function pointInAabb(p, box) {
  return (
    p.x >= box.x &&
    p.x <= box.x + box.sx &&
    p.y >= box.y &&
    p.y <= box.y + box.sy &&
    p.z >= box.z &&
    p.z <= box.z + box.sz
  );
}

export function aabbVolume(box) {
  return box.sx * box.sy * box.sz;
}

export function aabbCenter(box) {
  return {
    x: box.x + box.sx / 2,
    y: box.y + box.sy / 2,
    z: box.z + box.sz / 2,
  };
}

export function sizeForFace(kind, faceId) {
  const def = KINDS[kind];
  const face = FACES.find((f) => f.id === faceId) || FACES[0];
  const [a, b, thick] = def.defaultSize;
  if (face.axis === "x") return { sx: thick, sy: b, sz: a };
  return { sx: a, sy: b, sz: thick };
}

export function applyFaceSize(obj) {
  if (obj.kind !== "doorway" && obj.kind !== "switch") return obj;
  const s = sizeForFace(obj.kind, obj.face);
  obj.sx = s.sx;
  obj.sy = s.sy;
  obj.sz = s.sz;
  obj.x = clampByte(obj.x);
  obj.y = clampByte(obj.y);
  obj.z = clampByte(obj.z);
  obj.sx = clampSize(obj.x, obj.sx);
  obj.sy = clampSize(obj.y, obj.sy);
  obj.sz = clampSize(obj.z, obj.sz);
  return obj;
}

/** Keep 2:1 run = 2 * rise. Rise is sy. */
export function applySlopeConstraint(obj) {
  if (obj.kind !== "slope") return obj;
  const rise = Math.max(1, obj.sy | 0);
  const run = Math.max(2, rise * 2);
  obj.sy = clampSize(obj.y, rise);
  if (obj.axis === "x") {
    obj.sx = clampSize(obj.x, run);
    obj.sz = clampSize(obj.z, Math.max(1, obj.sz | 0));
  } else {
    obj.axis = "z";
    obj.sz = clampSize(obj.z, run);
    obj.sx = clampSize(obj.x, Math.max(1, obj.sx | 0));
  }
  if (obj.dir !== -1) obj.dir = 1;
  return obj;
}

export function clampObject(obj) {
  obj.x = clampByte(obj.x);
  obj.y = clampByte(obj.y);
  obj.z = clampByte(obj.z);
  if (obj.kind === "doorway" || obj.kind === "switch") {
    applyFaceSize(obj);
  } else if (obj.kind === "backpack") {
    applyBackpackProportions(obj);
  } else if (obj.kind === "slope") {
    obj.sx = clampSize(obj.x, obj.sx);
    obj.sy = clampSize(obj.y, obj.sy);
    obj.sz = clampSize(obj.z, obj.sz);
    applySlopeConstraint(obj);
  } else {
    obj.sx = clampSize(obj.x, obj.sx);
    obj.sy = clampSize(obj.y, obj.sy);
    obj.sz = clampSize(obj.z, obj.sz);
  }
  if (obj.kind === "enemy" || obj.kind === "spawn" || obj.kind === "teleporter_dest") {
    obj.rot = clampEnemyRot(obj.rot ?? 0);
  }
  if (obj.kind === "trigger") obj.text = clampTriggerText(obj.text);
  if (obj.kind === "room") {
    obj.name = clampName(obj.name);
    obj.bgColor = normalizeColor(obj.bgColor ?? obj.skyColor, ROOM_BG_DEFAULT);
    obj.lineColor = normalizeColor(obj.lineColor, ROOM_LINE_DEFAULT);
    obj.fxColor = normalizeColor(obj.fxColor, ROOM_FX_DEFAULT);
    obj.weaponColor = normalizeColor(obj.weaponColor, ROOM_WPN_DEFAULT);
    delete obj.skyColor;
    delete obj.floorColor;
    clampRoomSplits(obj);
  } else {
    if (obj.roomId != null) obj.roomId = String(obj.roomId);
    else obj.roomId = null;
  }
  if (usesLinkTag(obj.kind)) obj.tag = clampTag(obj.tag);
  if (obj.kind === "elevator") obj.elevType = clampElevType(obj.elevType);
  if (obj.kind === "backpack") obj.backpack = clampBackpackType(obj.backpack);
  if (obj.kind === "patrol") obj.order = clampPatrolOrder(obj.order);
  if (obj.kind === "doorway") {
    obj.locked = !!obj.locked;
    obj.keyTag = clampTag(obj.keyTag);
    if (obj.otherRoomId != null) obj.otherRoomId = String(obj.otherRoomId);
    else obj.otherRoomId = null;
  }
  if (obj.kind === "platform") {
    obj.sy = 1;
    obj.collide = obj.collide !== false;
  }
  return obj;
}

export function createObject(kind, x, y, z, extra = {}) {
  const def = KINDS[kind];
  if (!def) throw new Error(`Unknown kind ${kind}`);
  const obj = {
    id: extra.id || uid(),
    kind,
    x: x | 0,
    y: y | 0,
    z: z | 0,
    sx: def.defaultSize[0],
    sy: def.defaultSize[1],
    sz: def.defaultSize[2],
    face: extra.face || "+z",
    axis: extra.axis || "z",
    dir: extra.dir ?? 1,
  };
  if (kind === "slope") {
    obj.sx = 4;
    obj.sy = 2;
    obj.sz = 4;
  }
  if (kind === "spawn" || kind === "enemy" || kind === "teleporter_dest") {
    obj.rot = clampEnemyRot(extra.rot ?? 0);
  }
  if (kind === "enemy") {
    const name = extra.enemy || "Grunt";
    obj.enemy = ENEMY_TYPES.some((t) => t.name === name) ? name : "Grunt";
  }
  if (kind === "trigger") obj.text = clampTriggerText(extra.text);
  if (kind === "room") {
    obj.name = clampName(extra.name);
    obj.bgColor = normalizeColor(extra.bgColor ?? extra.skyColor, ROOM_BG_DEFAULT);
    obj.lineColor = normalizeColor(extra.lineColor, ROOM_LINE_DEFAULT);
    obj.fxColor = normalizeColor(extra.fxColor, ROOM_FX_DEFAULT);
    obj.weaponColor = normalizeColor(extra.weaponColor, ROOM_WPN_DEFAULT);
    obj.shape = clampRoomShape(extra.shape);
    obj.flip = !!extra.flip;
    obj.rx = extra.rx | 0;
    obj.ry = extra.ry | 0;
    obj.rz = extra.rz | 0;
    obj.cutU = extra.cutU | 0;
    obj.cutV = extra.cutV | 0;
    obj.stemW = extra.stemW | 0;
    obj.stemPos = extra.stemPos | 0;
    obj.barD = extra.barD | 0;
    obj.shift = extra.shift | 0;
    obj.mid = extra.mid | 0;
  } else if (extra.roomId) {
    obj.roomId = String(extra.roomId);
  }
  if (usesLinkTag(kind)) obj.tag = clampTag(extra.tag);
  if (kind === "elevator") obj.elevType = clampElevType(extra.elevType);
  if (kind === "backpack") obj.backpack = clampBackpackType(extra.backpack);
  if (kind === "patrol") obj.order = clampPatrolOrder(extra.order);
  if (kind === "doorway") {
    obj.locked = !!extra.locked;
    obj.keyTag = clampTag(extra.keyTag);
    if (extra.otherRoomId) obj.otherRoomId = String(extra.otherRoomId);
  }
  if (kind === "platform") obj.collide = extra.collide !== false;
  return clampObject(obj);
}

export function clampTriggerText(s) {
  return String(s ?? "").replace(/\r\n/g, "\n").slice(0, MAX_TRIGGER_TEXT);
}

export function clampName(s) {
  return String(s ?? "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, MAX_NAME_LEN);
}

export function clampTag(s) {
  return String(s ?? "")
    .replace(/\s+/g, "")
    .slice(0, MAX_TAG_LEN);
}

export function isFigureObject(obj) {
  return obj.kind === "enemy" || obj.kind === "spawn";
}

/** Objects-panel label: type only (no XYZ). Rooms may include display name. */
export function objectLabel(obj) {
  if (!obj || !KINDS[obj.kind]) return "?";
  if (obj.kind === "room") {
    return obj.name ? `Room  ${obj.name}` : "Room";
  }
  if (obj.kind === "enemy") return obj.enemy || "Enemy";
  if (obj.kind === "backpack") return `Backpack (${clampBackpackType(obj.backpack)})`;
  if (obj.kind === "patrol") {
    const tag = clampTag(obj.tag);
    return tag ? `Patrol (${tag})` : "Patrol point";
  }
  return KINDS[obj.kind].label;
}

export function figureTemplateName(obj) {
  return obj.kind === "spawn" ? "Grunt" : obj.enemy || "Grunt";
}

/** World-space first-frame stick verts for a placed enemy (1/8 scale, feet on floor center). */
export function enemyPlacementWorldVerts(obj, template) {
  const frame = template?.frames?.[0];
  if (!frame) return [];
  const ox = obj.x + obj.sx / 2;
  const oy = obj.y;
  const oz = obj.z + obj.sz / 2;
  const s = LAYOUT_ENEMY_SCALE;
  const rot = clampEnemyRot(obj.rot ?? 0);
  const th = (rot * Math.PI) / 4;
  const c = Math.cos(th);
  const sn = Math.sin(th);
  return frame.map((v) => {
    const lx = v.x * s;
    const ly = v.y * s;
    const lz = v.z * s;
    return {
      x: ox + lx * c + lz * sn,
      y: oy + ly,
      z: oz - lx * sn + lz * c,
    };
  });
}

export function findEnemyTemplate(doc, name) {
  return (doc.enemies || []).find((e) => e.name === name) || doc.enemies?.[0] || null;
}

export function cycleFace(faceId, delta) {
  const i = FACES.findIndex((f) => f.id === faceId);
  const n = (i + delta + FACES.length) % FACES.length;
  return FACES[n].id;
}

export function emptyMap() {
  return { name: "", objects: [] };
}

export function mapDisplayName(map, key) {
  const n = clampName(map?.name);
  return n || key;
}

/** Soft cap: 8-bit object indices / editor budget. */
export const MAX_MAP_OBJECTS = 255;

/**
 * Bytes per instance in the cooked C64 SoA (tools/genmap.py).
 * Trigger text blob is counted separately. Spawn is always 5 bytes in the map.
 */
export const C64_OBJECT_BYTES = {
  room: 11,
  doorway: 10,
  crate: 7,
  slope: 9,
  platform: 7,
  elevator: 10,
  switch: 9,
  enemy: 6,
  trigger: 8,
  spawn: 5,
  backpack: 5,
  // Editor-only / not yet cooked — treat like a typical AABB + room link
  key: 7,
  teleporter: 8,
  teleporter_dest: 6,
  patrol: 5,
};

/** Counts + estimated packed map RAM for the active level. */
export function mapStats(doc) {
  const map = activeMap(doc);
  const byKind = {};
  let total = 0;
  let c64Bytes = 5; // spawn_x/y/z/rot/room always present once cooked
  let hasSpawn = false;
  for (const obj of map.objects) {
    const kind = obj.kind;
    if (!KINDS[kind]) continue;
    total += 1;
    byKind[kind] = (byKind[kind] || 0) + 1;
    if (kind === "spawn") {
      if (hasSpawn) continue; // engine keeps one spawn record
      hasSpawn = true;
      continue; // already counted in the fixed 5
    }
    c64Bytes += C64_OBJECT_BYTES[kind] ?? 8;
    if (kind === "room") {
      c64Bytes += 12; // two collider slots
      if (clampRoomShape(obj.shape) !== "box") {
        const g = roomGeometry(obj);
        const nx = new Set(g.verts.map((v) => v.x)).size;
        const nz = new Set(g.verts.map((v) => v.z)).size;
        c64Bytes += 8 + nx + nz + g.verts.length * 4 + g.edges.length * 3;
      }
    }
    if (kind === "trigger") {
      const text = String(obj.text || "")
        .replace(/\r\n/g, "\n")
        .split("\n", 1)[0]
        .slice(0, 40);
      c64Bytes += text.length + 1; // chars + NUL in map_text
    }
  }
  return { total, byKind, c64Bytes, max: MAX_MAP_OBJECTS };
}

export function formatMapStats(stats) {
  const parts = [`${stats.total}/${stats.max} objects`];
  const order = [
    "room",
    "doorway",
    "crate",
    "slope",
    "platform",
    "elevator",
    "switch",
    "enemy",
    "trigger",
    "spawn",
    "backpack",
    "key",
    "teleporter",
    "teleporter_dest",
    "patrol",
  ];
  const plurals = {
    room: "rooms",
    doorway: "doors",
    crate: "crates",
    slope: "ramps",
    platform: "platforms",
    elevator: "elevators",
    switch: "switches",
    enemy: "enemies",
    trigger: "triggers",
    spawn: "spawns",
    backpack: "backpacks",
    key: "keys",
    teleporter: "teleporters",
    teleporter_dest: "dests",
    patrol: "patrols",
  };
  for (const kind of order) {
    const n = stats.byKind[kind];
    if (!n) continue;
    const one = KINDS[kind]?.label?.toLowerCase() || kind;
    parts.push(`${n} ${n === 1 ? one : plurals[kind] || `${one}s`}`);
  }
  const kb = stats.c64Bytes >= 1024 ? `${(stats.c64Bytes / 1024).toFixed(1)}K` : `${stats.c64Bytes} B`;
  parts.push(`~${kb} C64`);
  return parts.join(" · ");
}

export function activeMap(doc) {
  const name = LEVEL_NAMES.includes(doc.activeLevel) ? doc.activeLevel : LEVEL_NAMES[0];
  doc.activeLevel = name;
  if (!doc.maps) doc.maps = {};
  if (!doc.maps[name]) doc.maps[name] = emptyMap();
  if (typeof doc.maps[name].name !== "string") doc.maps[name].name = "";
  if (!Array.isArray(doc.maps[name].objects)) doc.maps[name].objects = [];
  return doc.maps[name];
}

export function roomsOf(doc) {
  return activeMap(doc).objects.filter((o) => o.kind === "room");
}

export function doorwaysOf(doc) {
  return activeMap(doc).objects.filter((o) => o.kind === "doorway");
}

export function currentRoom(doc, cam) {
  const rooms = roomsOf(doc).filter((r) => pointInRoom(cam, r));
  if (!rooms.length) return null;
  rooms.sort((a, b) => aabbVolume(a) - aabbVolume(b));
  return rooms[0];
}

export function roomById(doc, id) {
  if (!id) return null;
  return roomsOf(doc).find((r) => r.id === id) || null;
}

export function roomUnderObject(doc, obj) {
  if (!obj || obj.kind === "room") return null;
  return roomById(doc, obj.roomId);
}

/** Rooms that contain / overlap an object (doors may sit in two). */
export function roomsForObject(doc, obj) {
  if (!obj || obj.kind === "room") return [];
  const out = [];
  const a = roomById(doc, obj.roomId);
  if (a) out.push(a);
  if (obj.kind === "doorway") {
    const b = roomById(doc, obj.otherRoomId);
    if (b && b.id !== a?.id) out.push(b);
  }
  return out;
}

/**
 * Shallow room → children tree for the Objects panel.
 * Doors appear under owner and associated room; other objects under roomId.
 */
export function objectTree(doc) {
  const map = activeMap(doc);
  const rooms = roomsOf(doc);
  const claimed = new Set();
  const nodes = rooms.map((room) => {
    const children = [];
    for (const obj of map.objects) {
      if (obj.kind === "room") continue;
      if (obj.kind === "doorway") {
        if (obj.roomId === room.id || obj.otherRoomId === room.id) children.push(obj);
        continue;
      }
      if (obj.roomId === room.id) {
        children.push(obj);
        claimed.add(obj.id);
      }
    }
    return { room, children };
  });
  const orphans = map.objects.filter((o) => {
    if (o.kind === "room") return false;
    if (o.kind === "doorway") return !roomById(doc, o.roomId) && !roomById(doc, o.otherRoomId);
    return !claimed.has(o.id);
  });
  return { nodes, orphans };
}

export function inferDoorOtherRoom(doc, door) {
  if (!door || door.kind !== "doorway") return null;
  const hits = roomsOf(doc).filter((r) => r.id !== door.roomId && aabbOverlapsRoom(door, r));
  if (!hits.length) return null;
  hits.sort((a, b) => aabbVolume(a) - aabbVolume(b));
  return hits[0];
}

export function neighbourRooms(doc, room) {
  if (!room) return [];
  const doors = doorwaysOf(doc);
  const out = [];
  for (const other of roomsOf(doc)) {
    if (other.id === room.id) continue;
    const linked = doors.some(
      (d) =>
        (d.roomId === room.id && d.otherRoomId === other.id) ||
        (d.roomId === other.id && d.otherRoomId === room.id)
    );
    if (linked) out.push(other);
  }
  return out;
}

export function localVisibleIds(doc, cam) {
  const cur = currentRoom(doc, cam);
  if (!cur) return new Set();
  const ids = new Set([cur.id]);
  const neigh = neighbourRooms(doc, cur);
  for (const r of neigh) ids.add(r.id);
  const rooms = [cur, ...neigh];
  const roomIds = new Set(rooms.map((r) => r.id));
  for (const obj of activeMap(doc).objects) {
    if (obj.kind === "room") continue;
    if (roomIds.has(obj.roomId) || (obj.kind === "doorway" && roomIds.has(obj.otherRoomId))) {
      ids.add(obj.id);
    }
  }
  return ids;
}

export function objectVisible(doc, obj, cam, localMode) {
  if (!localMode) return true;
  return localVisibleIds(doc, cam).has(obj.id);
}

const BASE_SKELETON = [
  [-3, 6, 0],
  [3, 6, 0],
  [0, 14, 0],
  [0, 20, 0],
  [-6, 11, 0],
  [-8, 7, 0],
  [6, 11, 0],
  [8, 7, 0],
  [-3, 3, 0],
  [-3, 0, 0],
  [3, 3, 0],
  [3, 0, 0],
  [8, 8, 8],
];

const TEMPLATE_LINES = [
  [0, 1],
  [1, 2],
  [2, 0],
  [2, 3],
  [2, 4],
  [4, 5],
  [2, 6],
  [6, 7],
  [0, 8],
  [8, 9],
  [1, 10],
  [10, 11],
  [7, 12],
];

function skeletonBase(type) {
  const [sx, sy, sz] = type.scale;
  return BASE_SKELETON.map((p, i) => {
    const r = type.rest[i] || [0, 0, 0];
    return [
      Math.round(p[0] * sx + r[0]),
      Math.round(p[1] * sy + r[1]),
      Math.round(p[2] * sz + r[2]),
    ];
  });
}

function enemyTypeByName(name) {
  return ENEMY_TYPES.find((t) => t.name === name) || ENEMY_TYPES[0];
}

export function restSkeletonHeight(name) {
  const base = skeletonBase(enemyTypeByName(name));
  let maxY = 1;
  for (const p of base) {
    if (p[1] > maxY) maxY = p[1];
  }
  return maxY;
}

export function emptyMdlRig() {
  return { jointVerts: Array.from({ length: 13 }, () => []) };
}

export function normalizeMdlRig(raw) {
  const rig = emptyMdlRig();
  const src = raw?.jointVerts;
  if (!Array.isArray(src)) return rig;
  for (let i = 0; i < 13; i++) {
    const list = src[i];
    if (!Array.isArray(list)) continue;
    const seen = new Set();
    for (const v of list) {
      const n = v | 0;
      if (n < 0 || seen.has(n)) continue;
      seen.add(n);
      rig.jointVerts[i].push(n);
    }
  }
  return rig;
}

export function dummyFrameFor(name) {
  const base = skeletonBase(enemyTypeByName(name));
  return base.map((p) => ({
    x: clampVert(p[0]),
    y: clampVert(p[1]),
    z: clampVert(p[2]),
  }));
}

function parseEnemyFrames(rawFrames, name) {
  const rest = dummyFrameFor(name);
  const srcFrames = Array.isArray(rawFrames) ? rawFrames : [];
  if (!srcFrames.length) return [rest.map((v) => ({ x: v.x, y: v.y, z: v.z }))];
  return srcFrames.map((src) => {
    const verts = [];
    for (let i = 0; i < 13; i++) {
      const v = src?.[i] || rest[i];
      verts.push({ x: clampVert(v.x), y: clampVert(v.y), z: clampVert(v.z) });
    }
    return verts;
  });
}

export function createEnemy(name = "Grunt") {
  return {
    id: uid(),
    name,
    verts: 13,
    lines: TEMPLATE_LINES.map((p) => [p[0], p[1]]),
    frames: [dummyFrameFor(name)],
    clips: [],
    mdlRig: emptyMdlRig(),
  };
}

export function createAllCreatures() {
  return ENEMY_TYPES.map((t) => createEnemy(t.name));
}

function parseObjects(list) {
  const out = [];
  for (const o of list || []) {
    if (!KINDS[o.kind]) continue;
    const obj = createObject(o.kind, o.x, o.y, o.z, {
      id: o.id,
      face: o.face,
      axis: o.axis,
      dir: o.dir,
      enemy: o.enemy,
      rot: o.rot,
      text: o.text,
      name: o.name,
      tag: o.tag,
      locked: o.locked,
      keyTag: o.keyTag,
      elevType: o.elevType,
      backpack: o.backpack,
      order: o.order,
      collide: o.collide,
      bgColor: o.bgColor ?? o.skyColor,
      skyColor: o.skyColor,
      lineColor: o.lineColor,
      fxColor: o.fxColor,
      weaponColor: o.weaponColor,
      shape: o.shape,
      flip: o.flip,
      rx: o.rx,
      ry: o.ry,
      rz: o.rz,
      cutU: o.cutU,
      cutV: o.cutV,
      stemW: o.stemW,
      stemPos: o.stemPos,
      barD: o.barD,
      shift: o.shift,
      mid: o.mid,
      roomId: o.roomId,
      otherRoomId: o.otherRoomId,
    });
    if (!KINDS[o.kind].fixed) {
      obj.sx = o.sx ?? obj.sx;
      obj.sy = o.sy ?? obj.sy;
      obj.sz = o.sz ?? obj.sz;
    }
    if (o.kind === "enemy" || o.kind === "spawn" || o.kind === "teleporter_dest") {
      if (o.enemy && o.kind === "enemy") obj.enemy = o.enemy;
      if (o.rot != null) obj.rot = o.rot;
    }
    if (o.kind === "trigger" && o.text != null) obj.text = clampTriggerText(o.text);
    if (o.kind === "room") {
      if (o.name != null) obj.name = clampName(o.name);
      const bg = o.bgColor ?? o.skyColor;
      if (bg != null) obj.bgColor = normalizeColor(bg, ROOM_BG_DEFAULT);
      if (o.lineColor != null) obj.lineColor = normalizeColor(o.lineColor, ROOM_LINE_DEFAULT);
      if (o.fxColor != null) obj.fxColor = normalizeColor(o.fxColor, ROOM_FX_DEFAULT);
      if (o.weaponColor != null) obj.weaponColor = normalizeColor(o.weaponColor, ROOM_WPN_DEFAULT);
      if (o.shape != null) obj.shape = clampRoomShape(o.shape);
      if (o.flip != null) obj.flip = !!o.flip;
      if (o.rx != null) obj.rx = o.rx | 0;
      if (o.ry != null) obj.ry = o.ry | 0;
      if (o.rz != null) obj.rz = o.rz | 0;
      if (o.cutU != null) obj.cutU = o.cutU | 0;
      if (o.cutV != null) obj.cutV = o.cutV | 0;
      if (o.stemW != null) obj.stemW = o.stemW | 0;
      if (o.stemPos != null) obj.stemPos = o.stemPos | 0;
      if (o.barD != null) obj.barD = o.barD | 0;
      if (o.shift != null) obj.shift = o.shift | 0;
      if (o.mid != null) obj.mid = o.mid | 0;
      delete obj.skyColor;
      delete obj.floorColor;
    }
    if (o.kind !== "room") {
      if (o.roomId != null) obj.roomId = String(o.roomId);
    }
    if (usesLinkTag(o.kind) && o.tag != null) obj.tag = clampTag(o.tag);
    if (o.kind === "elevator" && o.elevType != null) obj.elevType = clampElevType(o.elevType);
    if (o.kind === "backpack" && o.backpack != null) obj.backpack = clampBackpackType(o.backpack);
    if (o.kind === "patrol" && o.order != null) obj.order = clampPatrolOrder(o.order);
    if (o.kind === "doorway") {
      obj.locked = !!o.locked;
      if (o.keyTag != null) obj.keyTag = clampTag(o.keyTag);
      if (o.otherRoomId != null) obj.otherRoomId = String(o.otherRoomId);
    }
    if (o.kind === "platform" && o.collide != null) obj.collide = o.collide !== false;
    out.push(clampObject(obj));
  }
  return out;
}

function starterObjects() {
  const roomA = createObject("room", 8, 0, 8, { name: "Start" });
  roomA.sx = 24;
  roomA.sy = 12;
  roomA.sz = 24;
  const roomB = createObject("room", 31, 0, 8, { name: "Next" });
  roomB.sx = 24;
  roomB.sy = 12;
  roomB.sz = 24;
  const door = createObject("doorway", 31, 0, 16, { face: "+x", roomId: roomA.id, otherRoomId: roomB.id });
  const crate = createObject("crate", 14, 0, 14, { roomId: roomA.id });
  return [roomA, roomB, door, crate];
}

export function defaultEditorState() {
  return {
    mode: "layout",
    localDraw: false,
    selectedIds: [],
    enemy: "Grunt",
    frameIndex: 0,
    clipIndex: 0,
    frameLocal: 0,
    selectedVerts: [],
    layoutCamera: { x: 28, y: 10, z: -6, yaw: 0.35, pitch: -0.2, speed: 28 },
    animOrbit: { yaw: 0.5, pitch: 0.15, dist: 48 },
    mdlScale: DEFAULT_MDL_SCALE,
    weapon: "axe",
    weaponFrame: 0,
    overlayOn: true,
    orthoMode: "top",
    collapsedRooms: [],
    activeLevel: null,
  };
}

export function clampWeaponScale(n) {
  const v = Number(n);
  if (!Number.isFinite(v)) return DEFAULT_WEAPON_SCALE;
  return Math.max(0.05, Math.min(8, v));
}

function parseWeaponPan(raw) {
  return {
    x: Number.isFinite(Number(raw?.x)) ? Number(raw.x) : 0,
    y: Number.isFinite(Number(raw?.y)) ? Number(raw.y) : 0,
  };
}

function parseWeaponItem(raw) {
  const pan = parseWeaponPan(raw?.pan);
  let frames = null;
  if (Array.isArray(raw?.frames)) {
    const seen = new Set();
    frames = [];
    for (const f of raw.frames) {
      const n = f | 0;
      if (n < 0 || n > 4095 || seen.has(n)) continue;
      seen.add(n);
      frames.push(n);
    }
  }
  return { pan, frames };
}

export function defaultWeapons() {
  const items = {};
  for (const key of WEAPON_KEYS) {
    items[key] = { pan: { x: 0, y: 0 }, frames: null };
  }
  return { scale: DEFAULT_WEAPON_SCALE, items };
}

export function parseWeapons(raw) {
  const d = defaultWeapons();
  if (!raw || typeof raw !== "object") return d;
  d.scale = clampWeaponScale(raw.scale);
  const src = raw.items && typeof raw.items === "object" ? raw.items : raw;
  for (const key of WEAPON_KEYS) {
    d.items[key] = parseWeaponItem(src[key]);
  }
  return d;
}

function num(v, fallback) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

export function parseEditorState(raw) {
  const d = defaultEditorState();
  if (!raw || typeof raw !== "object") return d;
  if (raw.mode === "anim" || raw.mode === "layout" || raw.mode === "weapons") d.mode = raw.mode;
  d.localDraw = !!raw.localDraw;
  if (Array.isArray(raw.selectedIds)) d.selectedIds = raw.selectedIds.map(String);
  if (typeof raw.enemy === "string" && raw.enemy) d.enemy = raw.enemy;
  d.frameIndex = Math.max(0, num(raw.frameIndex, 0) | 0);
  d.clipIndex = Math.max(0, num(raw.clipIndex, 0) | 0);
  d.frameLocal = Math.max(0, num(raw.frameLocal, 0) | 0);
  if (Array.isArray(raw.selectedVerts)) {
    d.selectedVerts = raw.selectedVerts.map((i) => i | 0).filter((i) => i >= 0 && i < 13);
  }
  const cam = raw.layoutCamera || {};
  d.layoutCamera = {
    x: num(cam.x, d.layoutCamera.x),
    y: num(cam.y, d.layoutCamera.y),
    z: num(cam.z, d.layoutCamera.z),
    yaw: num(cam.yaw, d.layoutCamera.yaw),
    pitch: num(cam.pitch, d.layoutCamera.pitch),
    speed: Math.max(6, Math.min(80, num(cam.speed, d.layoutCamera.speed))),
  };
  const orb = raw.animOrbit || {};
  d.animOrbit = {
    yaw: num(orb.yaw, d.animOrbit.yaw),
    pitch: num(orb.pitch, d.animOrbit.pitch),
    dist: Math.max(ANIM_ORBIT_DIST_MIN, Math.min(ANIM_ORBIT_DIST_MAX, num(orb.dist, d.animOrbit.dist))),
  };
  const scaleIn = raw.mdlScale;
  const scaleNum = Number(scaleIn);
  if (scaleIn == null || !Number.isFinite(scaleNum) || Math.abs(scaleNum - OLD_DEFAULT_MDL_SCALE) < 1e-6) {
    d.mdlScale = DEFAULT_MDL_SCALE;
  } else {
    d.mdlScale = clampMdlScale(scaleNum);
  }
  if (typeof raw.weapon === "string" && WEAPON_KEYS.includes(raw.weapon)) d.weapon = raw.weapon;
  d.weaponFrame = Math.max(0, num(raw.weaponFrame, 0) | 0);
  if (raw.overlayOn != null) d.overlayOn = !!raw.overlayOn;
  if (raw.orthoMode === "top" || raw.orthoMode === "left" || raw.orthoMode === "forward") {
    d.orthoMode = raw.orthoMode;
  }
  if (Array.isArray(raw.collapsedRooms)) d.collapsedRooms = raw.collapsedRooms.map(String);
  if (typeof raw.activeLevel === "string" && LEVEL_NAMES.includes(raw.activeLevel)) {
    d.activeLevel = raw.activeLevel;
  } else {
    d.activeLevel = null;
  }
  return d;
}

/** Game JSON only — no editor camera/tab/selection. */
export function gameDocument(doc) {
  return {
    version: doc.version,
    activeLevel: doc.activeLevel,
    maps: doc.maps,
    enemies: doc.enemies,
    weapons: doc.weapons,
  };
}

export function createDefaultDocument() {
  const maps = {};
  for (const name of LEVEL_NAMES) maps[name] = emptyMap();
  maps.E1M1 = { name: "Slipgate Complex", objects: starterObjects() };
  return {
    version: DOC_VERSION,
    activeLevel: "E1M1",
    maps,
    enemies: createAllCreatures(),
    weapons: defaultWeapons(),
  };
}

export function cloneDoc(doc) {
  return JSON.parse(JSON.stringify(doc));
}

function nudgeDoorsOutside(doc) {
  for (const name of LEVEL_NAMES) {
    const map = doc.maps[name];
    if (!map) continue;
    const rooms = map.objects.filter((o) => o.kind === "room");
    const byId = new Map(rooms.map((r) => [r.id, r]));
    for (const obj of map.objects) {
      if (obj.kind !== "doorway") continue;
      const room = byId.get(obj.roomId) || byId.get(obj.otherRoomId);
      if (room) nudgeDoorOutside(obj, room);
    }
  }
}

function migrateRoomParents(doc) {
  for (const name of LEVEL_NAMES) {
    const map = doc.maps[name];
    if (!map) continue;
    const rooms = map.objects.filter((o) => o.kind === "room");
    for (const obj of map.objects) {
      if (obj.kind === "room") continue;
      if (obj.kind === "doorway") {
        const hits = rooms.filter((r) => aabbOverlap(obj, r));
        hits.sort((a, b) => aabbVolume(a) - aabbVolume(b));
        if (!obj.roomId) obj.roomId = hits[0]?.id || null;
        if (!obj.otherRoomId) obj.otherRoomId = hits[1]?.id || hits.find((r) => r.id !== obj.roomId)?.id || null;
        continue;
      }
      if (obj.roomId) continue;
      const hits = rooms.filter((r) => aabbOverlap(obj, r));
      if (!hits.length) {
        obj.roomId = null;
        continue;
      }
      hits.sort((a, b) => aabbVolume(a) - aabbVolume(b));
      obj.roomId = hits[0].id;
    }
  }
}

export function normalizeDocument(raw) {
  const doc = createDefaultDocument();
  if (!raw || typeof raw !== "object") return doc;
  const fromVersion = Number(raw.version) || 0;
  if (raw.maps && typeof raw.maps === "object") {
    for (const name of LEVEL_NAMES) {
      const src = raw.maps[name] || {};
      doc.maps[name] = {
        name: clampName(src.name),
        objects: parseObjects(src.objects),
      };
    }
  } else {
    doc.maps.E1M1 = {
      name: clampName(raw.map?.name),
      objects: parseObjects(raw.map?.objects || raw.objects),
    };
  }
  doc.activeLevel = LEVEL_NAMES.includes(raw.activeLevel) ? raw.activeLevel : "E1M1";
  doc.enemies = [];
  const stale = !raw.version || raw.version < 2;
  if (stale) {
    doc.enemies = createAllCreatures();
  } else {
    const enemies = raw.enemies || [];
    for (const e of enemies) {
      const enemy = createEnemy(e.name || "Enemy");
      enemy.id = e.id || enemy.id;
      enemy.name = e.name || enemy.name;
      enemy.verts = 13;
      enemy.lines = TEMPLATE_LINES.map((p) => [p[0], p[1]]);
      enemy.frames = parseEnemyFrames(e.frames, enemy.name);
      enemy.clips = normalizeClips(e.clips, enemy.frames.length);
      enemy.mdlRig = normalizeMdlRig(e.mdlRig);
      doc.enemies.push(enemy);
    }
    const have = new Set(doc.enemies.map((e) => e.name));
    for (const t of ENEMY_TYPES) {
      if (!have.has(t.name)) doc.enemies.push(createEnemy(t.name));
    }
  }
  if (!doc.enemies.length) doc.enemies = createAllCreatures();
  if (fromVersion < 7) migrateRoomParents(doc);
  nudgeDoorsOutside(doc);
  doc.version = DOC_VERSION;
  doc.weapons = parseWeapons(raw.weapons);
  doc.editor = parseEditorState(raw.editor);
  return doc;
}
