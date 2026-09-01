import {
  ROOM_SHAPES,
  clampRoomShape,
  clampQuarter,
  clampRoomSplits,
  applyRoomShape,
  roomGeometry,
  pointInRoom,
  aabbOverlapsRoom,
  roomFloorY,
  snapDoorToRoom,
  snapDoorBetweenRooms,
  orientDoorToRooms,
  snapSwitchToRoom,
  doorRoomScores,
  doorNearFaceId,
  nudgeDoorOutside,
  rotateRoom,
  preserveRoomSplits,
  applyRoomSplitDelta,
  roomBasis,
  defaultRoomSplits,
} from "./roomGeom.js";

export {
  ROOM_SHAPES,
  clampRoomShape,
  clampQuarter,
  clampRoomSplits,
  applyRoomShape,
  roomGeometry,
  pointInRoom,
  aabbOverlapsRoom,
  roomFloorY,
  snapDoorToRoom,
  snapDoorBetweenRooms,
  orientDoorToRooms,
  snapSwitchToRoom,
  doorNearFaceId,
  nudgeDoorOutside,
  rotateRoom,
  preserveRoomSplits,
  applyRoomSplitDelta,
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
export const ITEM_ORBIT_DIST_MIN = 8;
export const ITEM_ORBIT_DIST_MAX = 80;
export const DOC_VERSION = 9;
/** Mid-distance stick LOD: full project while CAM_ZH < lodZ (world units). */
export const DEFAULT_ENEMY_LOD_Z = 4;
export const ENEMY_LOD_Z_BY_NAME = {
  Grunt: 4,
  Knight: 4,
  Rottweiler: 4,
  Scrag: 4,
  Ogre: 10,
  Shambler: 4,
  Chthon: 4,
  Zombie: 4,
};
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

export function defaultEnemyLodZ(name) {
  return ENEMY_LOD_Z_BY_NAME[name] ?? DEFAULT_ENEMY_LOD_Z;
}

export function clampEnemyLodZ(n, name) {
  const v = Number(n);
  if (!Number.isFinite(v)) return defaultEnemyLodZ(name);
  return Math.max(0, Math.min(255, v | 0));
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
    fixed: true,
    slope: false,
  },
  spawn: {
    id: "spawn",
    label: "Spawn",
    color: "#3ee06a",
    defaultSize: [2, 4, 2],
    fixed: true,
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
  teleporter_dest: {
    id: "teleporter_dest",
    label: "Teleport dest",
    color: "#c4a8ff",
    defaultSize: [2, 2, 2],
    fixed: true,
    slope: false,
  },
  pickup: {
    id: "pickup",
    label: "Pickup",
    color: "#6ec4a8",
    defaultSize: [1, 2, 1], // overwritten by applyBackpackProportions (1.5 tall, φ base)
    fixed: true,
    slope: false,
  },
};

/** Editor-only dashed / ghost volumes (not solid world geometry). */
export function isGhostKind(kind) {
  return kind === "trigger" || kind === "teleporter_dest";
}

/** Kinds that always carry a link tag (resolved to indices on export). */
export function usesLinkTag(kind) {
  return kind === "switch" || kind === "elevator" || kind === "teleporter_dest";
}

/** Trigger purposes. Tag is used for teleport / elevator / summon. */
export const TRIGGER_PURPOSES = ["message", "end_level", "hurt", "teleport", "elevator", "summon"];
export const TRIGGER_PURPOSE_LABELS = {
  message: "Display message",
  end_level: "End of level",
  hurt: "Hurt player",
  teleport: "Teleport",
  elevator: "Activate elevator",
  summon: "Summon elevator",
};

export function clampTriggerPurpose(s) {
  return TRIGGER_PURPOSES.includes(s) ? s : "message";
}

export function triggerUsesTag(purpose) {
  const p = clampTriggerPurpose(purpose);
  return p === "teleport" || p === "elevator" || p === "summon";
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

export function cycleEnemyRot(n, delta = 1) {
  return clampEnemyRot((n | 0) + delta);
}

/** Ramp surface horizontals: bit0 = low end, bit1 = high end. */
export const SLOPE_FLAG_BOTTOM = 1;
export const SLOPE_FLAG_TOP = 2;

export function clampSlopeFlags(n) {
  return (n | 0) & (SLOPE_FLAG_BOTTOM | SLOPE_FLAG_TOP);
}

/** (z,+1) → (z,−1) → (x,+1) → (x,−1) → … */
export function cycleSlopeOrient(obj) {
  if (!obj || obj.kind !== "slope") return obj;
  if (obj.axis === "z" && obj.dir === 1) obj.dir = -1;
  else if (obj.axis === "z") {
    obj.axis = "x";
    obj.dir = 1;
  } else if (obj.dir === 1) obj.dir = -1;
  else {
    obj.axis = "z";
    obj.dir = 1;
  }
  return obj;
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
  "teleporter_dest",
  "pickup",
];
export const MAX_TRIGGER_TEXT = 80;
export const MAX_NAME_LEN = 40;
export const MAX_TAG_LEN = 16;

/** Elevator height mode: Auto invents home/dest at cook; off uses elevLow/elevHigh vs room.y. */
export function elevHeightsAuto(obj) {
  return obj?.elevAuto !== false;
}

export function clampElevHeights(obj) {
  let low = Number.isFinite(Number(obj.elevLow)) ? obj.elevLow | 0 : 0;
  let high = Number.isFinite(Number(obj.elevHigh)) ? obj.elevHigh | 0 : 1;
  if (high <= low) high = low + 1;
  obj.elevLow = low;
  obj.elevHigh = high;
  obj.elevAuto = elevHeightsAuto(obj);
  delete obj.elevType;
}

function xzAabbGap(a, b) {
  const ax1 = (a.x | 0) + (a.sx | 0);
  const bx1 = (b.x | 0) + (b.sx | 0);
  const az1 = (a.z | 0) + (a.sz | 0);
  const bz1 = (b.z | 0) + (b.sz | 0);
  const dx = Math.max(0, (a.x | 0) - bx1, (b.x | 0) - ax1);
  const dz = Math.max(0, (a.z | 0) - bz1, (b.z | 0) - az1);
  return dx + dz;
}

function nearestFloorHome(elev, room, floorY) {
  const elevSy = elev.sy | 0;
  const elevTop = (elev.y | 0) + elevSy;
  let bestKey = null;
  let bestHome = null;
  for (const c of roomGeometry(room).colliders || []) {
    if ((c.sx | 0) <= 0) continue;
    const cy = c.y | 0;
    if (cy <= floorY) continue;
    const home = cy - elevSy;
    if (home <= floorY) continue;
    const key = [xzAabbGap(elev, c), Math.abs(cy - elevTop)];
    if (
      bestKey == null ||
      key[0] < bestKey[0] ||
      (key[0] === bestKey[0] && key[1] < bestKey[1])
    ) {
      bestKey = key;
      bestHome = home;
    }
  }
  return bestHome;
}

function nearestPlatHome(elev, roomId, plats, floorY) {
  const elevSy = elev.sy | 0;
  const elevTop = (elev.y | 0) + elevSy;
  let bestKey = null;
  let bestHome = null;
  for (const p of plats) {
    if (p.roomId !== roomId) continue;
    const surface = (p.y | 0) + ((p.sy | 0) || 1);
    const home = surface - elevSy;
    if (home <= floorY) continue;
    const key = [xzAabbGap(elev, p), Math.abs(surface - elevTop)];
    if (
      bestKey == null ||
      key[0] < bestKey[0] ||
      (key[0] === bestKey[0] && key[1] < bestKey[1])
    ) {
      bestKey = key;
      bestHome = home;
    }
  }
  return bestHome;
}

/**
 * Absolute elev_y bottoms for dest (low) and home (high), matching tools/genmap.py.
 * @returns {{ dest: number, home: number }}
 */
export function elevStopBottoms(doc, elev) {
  const room = roomUnderObject(doc, elev) || roomById(doc, elev.roomId);
  const floorY = room ? room.y | 0 : 0;
  if (!elevHeightsAuto(elev)) {
    clampElevHeights(elev);
    return { dest: floorY + elev.elevLow, home: floorY + elev.elevHigh };
  }
  let home = elev.y | 0;
  const dest = floorY;
  if ((elev.y | 0) === floorY && room) {
    const map = activeMap(doc);
    const plats = (map?.objects || []).filter((o) => o.kind === "platform");
    let raised = nearestFloorHome(elev, room, floorY);
    if (raised == null) raised = nearestPlatHome(elev, elev.roomId, plats, floorY);
    if (raised != null) home = raised;
  }
  return { dest, home };
}

/** Placeable pickup contents (not including death-drop shells5). */
export const PICKUP_TYPES = [
  "shells",
  "nailgun",
  "nails",
  "grenade launcher",
  "grenades",
  "health 25%",
  "health 50%",
  "armour",
  "quad damage",
  "pentagram of protection",
  "ring of shadows",
  "silver key",
  "gold key",
  "rune of earth magic",
];
/** @deprecated Use PICKUP_TYPES */
export const BACKPACK_TYPES = PICKUP_TYPES;

export const ITEM_MESH_KEYS = ["backpack", ...PICKUP_TYPES];
export const DOOR_TYPES = ["Tech", "Arch", "Tri"];
export const DOOR_MESH_KEYS = DOOR_TYPES;
export const ALL_MESH_KEYS = [...ITEM_MESH_KEYS, ...DOOR_MESH_KEYS];
/** Items-tab floor/cube and paste-nudge window. Not a coord cap. */
export const ITEM_MIN = -4;
export const ITEM_MAX = 4;
/** Signed 8-bit local X/Y/Z. $80 is −128. */
export const ITEM_COORD_MIN = -128;
export const ITEM_COORD_MAX = 127;
export const ITEM_ORIGIN = 0;
/** Editor 0 sits at the centre of the 2×2 pickup footprint. */
export const ITEM_WORLD_BIAS = 1;
export const ITEM_MAX_VERTS = 16;
export const ITEM_MAX_LINES = 16;
export const ITEM_MAX_UNIQUE = 6;

export const DOOR_LOCKS = ["unlocked", "silver", "gold"];
export const DOOR_LOCK_LABELS = {
  unlocked: "Unlocked",
  silver: "Silver key",
  gold: "Gold key",
};
/** Discrete AABB scales of the 4×5×1 doorway. Thickness stays 1. */
export const DOOR_SCALES = [1, 1.5, 2];
export const DOOR_SCALE_LABELS = { 1: "1.0", 1.5: "1.5", 2: "2.0" };

/** Height / base-side = φ. Fixed backpack: 1.5 tall. */
export const GOLDEN_RATIO = (1 + Math.sqrt(5)) / 2;
export const BACKPACK_HEIGHT = 1.5;
export const BACKPACK_SIDE = BACKPACK_HEIGHT / GOLDEN_RATIO;
export const BACKPACK_DEPTH = (BACKPACK_SIDE * Math.sqrt(3)) / 2;

export function clampPickupType(s) {
  return PICKUP_TYPES.includes(s) ? s : "shells";
}

/** @deprecated Use clampPickupType */
export function clampBackpackType(s) {
  return clampPickupType(s);
}

export function clampDoorLock(s) {
  return s === "silver" || s === "gold" ? s : "unlocked";
}

export function clampDoorType(s) {
  const t = String(s ?? "");
  if (DOOR_TYPES.includes(t)) return t;
  const lower = t.toLowerCase();
  if (lower === "tech") return "Tech";
  if (lower === "arch") return "Arch";
  if (lower === "tri") return "Tri";
  return "Tech";
}

export function clampDoorScale(s) {
  const n = Number(s);
  if (n === 2) return 2;
  if (n === 1.5) return 1.5;
  return 1;
}

/** Width × height × thickness for a doorway scale (1 / 1.5 / 2). */
export function doorSizeForScale(scale) {
  const s = clampDoorScale(scale);
  if (s === 2) return [8, 10, 1];
  if (s === 1.5) return [6, 8, 1];
  return [4, 5, 1];
}

export function isDoorMeshKey(key) {
  const t = String(key ?? "");
  return DOOR_TYPES.includes(t) || t === "tech" || t === "arch" || t === "tri";
}

export function clampItemCoord(n) {
  const v = n | 0;
  if (v < ITEM_COORD_MIN) return ITEM_COORD_MIN;
  if (v > ITEM_COORD_MAX) return ITEM_COORD_MAX;
  return v;
}

export function emptyItemMesh() {
  return { verts: [], lines: [] };
}

function v3(x, y, z) {
  return { x, y, z };
}

function meshOf(verts, lines) {
  return { verts: verts.map((p) => v3(p[0], p[1], p[2])), lines: lines.map((p) => [p[0], p[1]]) };
}

/** Seeded meshes that obey 6 unique X / 6 unique Z. Empty types fall back to backpack. */
export function defaultItemMeshes() {
  return {
    backpack: meshOf(
      [
        [-1, 0, -1],
        [1, 0, -1],
        [0, 0, 1],
        [0, 2, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 0],
        [3, 0],
        [3, 1],
        [3, 2],
      ]
    ),
    "health 25%": meshOf(
      [
        [0, 2, 0],
        [-1, 1, 0],
        [0, 1, 1],
        [1, 1, 0],
        [0, 1, -1],
        [0, 0, 0],
      ],
      [
        [4, 5],
        [3, 5],
        [1, 5],
        [2, 5],
        [1, 4],
        [1, 2],
        [2, 3],
        [3, 4],
        [0, 1],
        [0, 2],
        [0, 4],
        [0, 3],
      ]
    ),
    "health 50%": meshOf(
      [
        [0, 4, 0],
        [-2, 2, 0],
        [0, 2, 2],
        [2, 2, 0],
        [0, 2, -2],
        [0, 0, 0],
      ],
      [
        [4, 5],
        [3, 5],
        [1, 5],
        [2, 5],
        [1, 4],
        [1, 2],
        [2, 3],
        [3, 4],
        [0, 1],
        [0, 2],
        [0, 4],
        [0, 3],
      ]
    ),
    "quad damage": meshOf(
      [
        [-1, 0, -1],
        [1, 0, -1],
        [1, 0, 1],
        [-1, 0, 1],
        [0, 3, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
        [4, 0],
        [4, 1],
        [4, 2],
        [4, 3],
      ]
    ),
    "pentagram of protection": meshOf(
      [
        [0, 0, -2],
        [2, 0, 0],
        [0, 0, 2],
        [-2, 0, 0],
        [0, 4, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
        [4, 0],
        [4, 1],
        [4, 2],
        [4, 3],
      ]
    ),
    "ring of shadows": meshOf(
      [
        [-2, 2, 0],
        [-1, 1, 0],
        [1, 1, 0],
        [2, 2, 0],
        [1, 4, 0],
        [-1, 4, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 4],
        [4, 5],
        [5, 0],
      ]
    ),
    "silver key": meshOf(
      [
        [-2, 1, 0],
        [-2, 2, 0],
        [-1, 2, 0],
        [-1, 1, 0],
        [2, 1, 0],
        [2, 0, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
        [3, 4],
        [4, 5],
      ]
    ),
    "gold key": meshOf(
      [
        [-2, 1, 0],
        [-2, 3, 0],
        [-1, 3, 0],
        [-1, 1, 0],
        [2, 1, 0],
        [2, 2, 0],
        [2, 0, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
        [3, 4],
        [4, 5],
        [4, 6],
      ]
    ),
    "rune of earth magic": meshOf(
      [
        [0, 0, 0],
        [-2, 1, 0],
        [-2, 3, 0],
        [0, 4, 0],
        [2, 3, 0],
        [2, 1, 0],
        [0, 2, 0],
        [-1, 1, 0],
        [1, 1, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 4],
        [4, 5],
        [5, 0],
        [3, 6],
        [6, 0],
        [6, 7],
        [6, 8],
      ]
    ),
    Tech: meshOf(
      [
        [-2, 0, 0],
        [2, 0, 0],
        [2, 5, 0],
        [-2, 5, 0],
        [-2, 2, 0],
        [2, 2, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 0],
        [4, 5],
      ]
    ),
    Arch: meshOf(
      [
        [-2, 0, 0],
        [2, 0, 0],
        [2, 4, 0],
        [0, 5, 0],
        [-2, 4, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 3],
        [3, 4],
        [4, 0],
      ]
    ),
    Tri: meshOf(
      [
        [-2, 0, 0],
        [2, 0, 0],
        [0, 5, 0],
      ],
      [
        [0, 1],
        [1, 2],
        [2, 0],
      ]
    ),
  };
}

function parseItemVert(v) {
  if (Array.isArray(v) && v.length >= 3) return { x: clampItemCoord(v[0]), y: clampItemCoord(v[1]), z: clampItemCoord(v[2]) };
  if (v && typeof v === "object") return { x: clampItemCoord(v.x), y: clampItemCoord(v.y), z: clampItemCoord(v.z) };
  return null;
}

export function parseItemMesh(raw) {
  if (!raw || typeof raw !== "object") return emptyItemMesh();
  const verts = [];
  const seen = new Set();
  for (const src of raw.verts || []) {
    const v = parseItemVert(src);
    if (!v) continue;
    const k = `${v.x},${v.y},${v.z}`;
    if (seen.has(k) || verts.length >= ITEM_MAX_VERTS) continue;
    seen.add(k);
    verts.push(v);
  }
  const lines = [];
  const lineSeen = new Set();
  for (const src of raw.lines || []) {
    const a = src?.[0] | 0;
    const b = src?.[1] | 0;
    if (a === b || a < 0 || b < 0 || a >= verts.length || b >= verts.length) continue;
    const lo = Math.min(a, b);
    const hi = Math.max(a, b);
    const k = `${lo}-${hi}`;
    if (lineSeen.has(k) || lines.length >= ITEM_MAX_LINES) continue;
    lineSeen.add(k);
    lines.push([lo, hi]);
  }
  return { verts, lines };
}

export function parseItemMeshes(raw) {
  const d = defaultItemMeshes();
  if (!raw || typeof raw !== "object") return d;
  const src = { ...raw };
  if (src.tech != null && src.Tech == null) src.Tech = src.tech;
  if (src.arch != null && src.Arch == null) src.Arch = src.arch;
  if (src.tri != null && src.Tri == null) src.Tri = src.tri;
  for (const key of ALL_MESH_KEYS) {
    if (src[key] == null) continue;
    const mesh = parseItemMesh(src[key]);
    if (!mesh.verts.length && (key === "backpack" || isDoorMeshKey(key))) continue;
    d[key] = mesh;
  }
  return d;
}

function vertsMatch(verts, pts) {
  if (!verts || verts.length !== pts.length) return false;
  return pts.every((p, i) => verts[i].x === p[0] && verts[i].y === p[1] && verts[i].z === p[2]);
}

/** v8 stored 0..7 with origin at 4. Shift X/Z so origin is 0. */
export function migrateItemMeshes(rawItems, fromVersion) {
  if (fromVersion >= 9 || !rawItems || typeof rawItems !== "object") return rawItems;
  const out = { ...rawItems };
  for (const key of Object.keys(out)) {
    const mesh = out[key];
    if (!mesh || typeof mesh !== "object") continue;
    const verts = (mesh.verts || []).map((src) => {
      let x = 0;
      let y = 0;
      let z = 0;
      if (Array.isArray(src) && src.length >= 3) {
        x = src[0] | 0;
        y = src[1] | 0;
        z = src[2] | 0;
      } else if (src && typeof src === "object") {
        x = src.x | 0;
        y = src.y | 0;
        z = src.z | 0;
      }
      return { x: clampItemCoord(x - 4), y: clampItemCoord(y), z: clampItemCoord(z - 4) };
    });
    out[key] = { ...mesh, verts };
  }
  const bp = out.backpack;
  if (bp && vertsMatch(bp.verts, [
    [0, 0, 0],
    [2, 0, 0],
    [1, 0, 2],
    [1, 2, 1],
  ])) {
    out.backpack = defaultItemMeshes().backpack;
  }
  return out;
}

export function itemMeshHasGeom(mesh) {
  return !!(mesh && mesh.verts?.length && mesh.lines?.length);
}

export function itemMeshFor(doc, type) {
  const items = doc?.items || defaultItemMeshes();
  if (type === "backpack") {
    const mesh = items.backpack;
    if (itemMeshHasGeom(mesh)) return mesh;
    return defaultItemMeshes().backpack;
  }
  if (isDoorMeshKey(type)) {
    const key = clampDoorType(type);
    const mesh = items[key];
    if (itemMeshHasGeom(mesh)) return mesh;
    return items.Tech || defaultItemMeshes().Tech;
  }
  const key = clampPickupType(type);
  const mesh = items[key];
  if (itemMeshHasGeom(mesh)) return mesh;
  return items.backpack || defaultItemMeshes().backpack;
}

export function itemUniqueXZ(verts) {
  const xs = new Set();
  const zs = new Set();
  for (const v of verts || []) {
    xs.add(v.x | 0);
    zs.add(v.z | 0);
  }
  return { nx: xs.size, nz: zs.size, xs, zs };
}

export function itemMeshStats(mesh) {
  const verts = mesh?.verts || [];
  const lines = mesh?.lines || [];
  const { nx, nz } = itemUniqueXZ(verts);
  const nv = verts.length;
  const ne = lines.length;
  return {
    nv,
    ne,
    nx,
    nz,
    bytes: nx + nz + nv * 4 + ne * 3,
    over: nx > ITEM_MAX_UNIQUE || nz > ITEM_MAX_UNIQUE || nv > ITEM_MAX_VERTS || ne > ITEM_MAX_LINES,
  };
}

export function itemMeshWorldSegs(obj, mesh) {
  const m = mesh && itemMeshHasGeom(mesh) ? mesh : defaultItemMeshes().backpack;
  const verts = m.verts.map((v) => ({
    x: obj.x + (v.x | 0) + ITEM_WORLD_BIAS,
    y: obj.y + (v.y | 0),
    z: obj.z + (v.z | 0) + ITEM_WORLD_BIAS,
  }));
  const segs = [];
  for (const [a, b] of m.lines) {
    if (verts[a] && verts[b]) segs.push({ a: verts[a], b: verts[b] });
  }
  return segs;
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

export function normalizeExportClips(raw) {
  if (!Array.isArray(raw)) return undefined;
  const out = [];
  const seen = new Set();
  for (const n of raw) {
    const name = String(n ?? "").trim();
    if (!name || seen.has(name)) continue;
    seen.add(name);
    out.push(name);
  }
  return out;
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
  {
    name: "Zombie",
    scale: [1, 1.05, 1],
    rest: { 12: [0, 8, 6] },
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

/** Interior volume overlap only; face-touch is OK. */
export function aabbStrictOverlap(a, b) {
  return (
    a.x < b.x + b.sx &&
    a.x + a.sx > b.x &&
    a.y < b.y + b.sy &&
    a.y + a.sy > b.y &&
    a.z < b.z + b.sz &&
    a.z + a.sz > b.z
  );
}

/** +90° Y face map matching rot90({x:z,y:y,z:-x}). */
const FACE_Y_PLUS = { "+z": "+x", "+x": "-z", "-z": "-x", "-x": "+z" };

/** Rotate AABB footprint around pivot in XZ by delta quarter-turns (Y). */
export function rotateAabbYAround(obj, pivotX, pivotZ, delta) {
  const steps = ((delta | 0) % 4 + 4) % 4;
  for (let i = 0; i < steps; i++) {
    const sx = obj.sx | 0;
    const sz = obj.sz | 0;
    const ox = (obj.x | 0) + sx / 2;
    const oz = (obj.z | 0) + sz / 2;
    const dx = ox - pivotX;
    const dz = oz - pivotZ;
    obj.sx = sz;
    obj.sz = sx;
    obj.x = Math.round(pivotX + dz - obj.sx / 2);
    obj.z = Math.round(pivotZ - dx - obj.sz / 2);
  }
  return obj;
}

function rotateSlopeOrientY(obj, delta) {
  const steps = ((delta | 0) % 4 + 4) % 4;
  for (let i = 0; i < steps; i++) {
    if (obj.axis === "z" && obj.dir === 1) {
      obj.axis = "x";
      obj.dir = 1;
    } else if (obj.axis === "x" && obj.dir === 1) {
      obj.axis = "z";
      obj.dir = -1;
    } else if (obj.axis === "z" && obj.dir === -1) {
      obj.axis = "x";
      obj.dir = -1;
    } else {
      obj.axis = "z";
      obj.dir = 1;
    }
  }
  return obj;
}

/** Facing / slope / figure yaw for +delta Y quarter-turns. */
export function applyYawQuarterMeta(obj, delta) {
  if (!obj) return obj;
  const steps = ((delta | 0) % 4 + 4) % 4;
  if (!steps) return obj;
  if (obj.kind === "enemy" || obj.kind === "spawn" || obj.kind === "teleporter_dest") {
    obj.rot = clampEnemyRot((obj.rot | 0) + 2 * steps);
  }
  if (obj.kind === "doorway" || obj.kind === "switch") {
    for (let i = 0; i < steps; i++) {
      obj.face = FACE_Y_PLUS[obj.face] || "+z";
    }
  }
  if (obj.kind === "slope") rotateSlopeOrientY(obj, steps);
  return obj;
}

/** +90° Y: (x,z) → (pivotX+dz, pivotZ-dx), matching rotateAabbYAround. */
function yawPoint(x, z, pivotX, pivotZ, delta) {
  const steps = ((delta | 0) % 4 + 4) % 4;
  let px = x;
  let pz = z;
  for (let i = 0; i < steps; i++) {
    const dx = px - pivotX;
    const dz = pz - pivotZ;
    px = pivotX + dz;
    pz = pivotZ - dx;
  }
  return { x: px, z: pz };
}

/** Selected owner for a doorway: roomId if in the set, else otherRoomId. */
function doorAnchorRoomId(door, idSet) {
  const a = door.roomId != null ? String(door.roomId) : "";
  const b = door.otherRoomId != null ? String(door.otherRoomId) : "";
  if (idSet.has(a)) return a;
  if (idSet.has(b)) return b;
  return null;
}

/** Rigid Y rotate room AABB/orient and transform owned contents + doorways. */
export function rotateRoomY(doc, room, delta = 1) {
  if (!room || room.kind !== "room") return room;
  rotateRoomsBlockY(doc, [room.id], delta);
  return room;
}

function translatedRoomBox(room, dx, dz) {
  return {
    x: (room.x | 0) + dx,
    y: room.y | 0,
    z: (room.z | 0) + dz,
    sx: room.sx | 0,
    sy: room.sy | 0,
    sz: room.sz | 0,
  };
}

function blockFitsAt(rooms, outsiders, dx, dz) {
  for (const r of rooms) {
    const box = translatedRoomBox(r, dx, dz);
    if (box.x < WORLD_MIN || box.z < WORLD_MIN) return false;
    if (box.x + box.sx > WORLD_SIZE || box.z + box.sz > WORLD_SIZE) return false;
    if (box.y < WORLD_MIN || box.y + box.sy > WORLD_SIZE) return false;
    for (const o of outsiders) {
      if (aabbStrictOverlap(box, o)) return false;
    }
  }
  return true;
}

/** Smallest |dx|+|dz| translation (spiral) so rooms clear outsiders; face-touch OK. */
export function findFreeRoomTranslation(rooms, outsiders) {
  if (blockFitsAt(rooms, outsiders, 0, 0)) return { dx: 0, dz: 0 };
  const maxR = WORLD_SIZE;
  for (let rad = 1; rad < maxR; rad++) {
    for (let dx = -rad; dx <= rad; dx++) {
      for (const dz of [-rad, rad]) {
        if (blockFitsAt(rooms, outsiders, dx, dz)) return { dx, dz };
      }
    }
    for (let dz = -rad + 1; dz <= rad - 1; dz++) {
      for (const dx of [-rad, rad]) {
        if (blockFitsAt(rooms, outsiders, dx, dz)) return { dx, dz };
      }
    }
  }
  return { dx: 0, dz: 0 };
}

/**
 * World-Y rotate each selected room about its AABB center (contents + attached
 * doors), then translate so room centers orbit the union XZ pivot. Doors keep
 * IDs and yawed face (no re-pair). If the set overlaps outsiders, nudge it.
 */
export function rotateRoomsBlockY(doc, roomIds, delta = 1) {
  const d = delta | 0;
  if (!d) return;
  const idSet = new Set((roomIds || []).map(String));
  const rooms = roomsOf(doc).filter((r) => idSet.has(String(r.id)));
  if (!rooms.length) return;

  let minX = Infinity;
  let maxX = -Infinity;
  let minZ = Infinity;
  let maxZ = -Infinity;
  const origCenter = new Map();
  for (const r of rooms) {
    const c = aabbCenter(r);
    origCenter.set(String(r.id), { x: c.x, z: c.z });
    minX = Math.min(minX, r.x | 0);
    maxX = Math.max(maxX, (r.x | 0) + (r.sx | 0));
    minZ = Math.min(minZ, r.z | 0);
    maxZ = Math.max(maxZ, (r.z | 0) + (r.sz | 0));
  }
  const pivotX = (minX + maxX) / 2;
  const pivotZ = (minZ + maxZ) / 2;

  const byRoom = new Map();
  const doors = [];
  for (const obj of activeMap(doc).objects) {
    if (obj.kind === "room") continue;
    if (obj.kind === "doorway") {
      const anchor = doorAnchorRoomId(obj, idSet);
      if (anchor) doors.push({ obj, anchor });
      continue;
    }
    if (obj.roomId != null && idSet.has(String(obj.roomId))) {
      const k = String(obj.roomId);
      if (!byRoom.has(k)) byRoom.set(k, []);
      byRoom.get(k).push(obj);
    }
  }

  for (const room of rooms) {
    const c = origCenter.get(String(room.id));
    rotateRoom(room, "y", d);
    for (const obj of byRoom.get(String(room.id)) || []) {
      rotateAabbYAround(obj, c.x, c.z, d);
      applyYawQuarterMeta(obj, d);
    }
  }
  for (const { obj, anchor } of doors) {
    const c = origCenter.get(anchor);
    rotateAabbYAround(obj, c.x, c.z, d);
    applyYawQuarterMeta(obj, d);
  }

  const shift = new Map();
  for (const room of rooms) {
    const orig = origCenter.get(String(room.id));
    const target = yawPoint(orig.x, orig.z, pivotX, pivotZ, d);
    const destX = Math.round(target.x - (room.sx | 0) / 2);
    const destZ = Math.round(target.z - (room.sz | 0) / 2);
    const dx = destX - (room.x | 0);
    const dz = destZ - (room.z | 0);
    shift.set(String(room.id), { dx, dz });
    if (dx || dz) {
      room.x = (room.x | 0) + dx;
      room.z = (room.z | 0) + dz;
      for (const obj of byRoom.get(String(room.id)) || []) {
        obj.x = (obj.x | 0) + dx;
        obj.z = (obj.z | 0) + dz;
      }
    }
  }
  for (const { obj, anchor } of doors) {
    const s = shift.get(anchor);
    if (s && (s.dx || s.dz)) {
      obj.x = (obj.x | 0) + s.dx;
      obj.z = (obj.z | 0) + s.dz;
    }
  }

  const moving = [...rooms];
  for (const list of byRoom.values()) moving.push(...list);
  for (const { obj } of doors) moving.push(obj);

  const outsiders = roomsOf(doc).filter((r) => !idSet.has(String(r.id)));
  const { dx, dz } = findFreeRoomTranslation(rooms, outsiders);
  if (dx || dz) {
    for (const obj of moving) {
      obj.x = (obj.x | 0) + dx;
      obj.z = (obj.z | 0) + dz;
    }
  }

  for (const obj of moving) clampObject(obj);
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

export function sizeForFace(kind, faceId, scale) {
  const def = KINDS[kind];
  const face = FACES.find((f) => f.id === faceId) || FACES[0];
  const [a, b, thick] = kind === "doorway" ? doorSizeForScale(scale) : def.defaultSize;
  if (face.axis === "x") return { sx: thick, sy: b, sz: a };
  return { sx: a, sy: b, sz: thick };
}

export function applyFaceSize(obj) {
  if (obj.kind !== "doorway" && obj.kind !== "switch") return obj;
  const s = sizeForFace(obj.kind, obj.face, obj.doorScale);
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

/** Axis x/z, dir ±1; sizes independent (rise = sy, run = sx or sz). */
export function applySlopeConstraint(obj) {
  if (obj.kind !== "slope") return obj;
  obj.sy = clampSize(obj.y, Math.max(1, obj.sy | 0));
  if (obj.axis === "x") {
    obj.sx = clampSize(obj.x, Math.max(1, obj.sx | 0));
    obj.sz = clampSize(obj.z, Math.max(1, obj.sz | 0));
  } else {
    obj.axis = "z";
    obj.sz = clampSize(obj.z, Math.max(1, obj.sz | 0));
    obj.sx = clampSize(obj.x, Math.max(1, obj.sx | 0));
  }
  if (obj.dir !== -1) obj.dir = 1;
  return obj;
}

export function clampObject(obj) {
  obj.x = clampByte(obj.x);
  obj.y = clampByte(obj.y);
  obj.z = clampByte(obj.z);
  if (obj.kind === "doorway") obj.doorScale = clampDoorScale(obj.doorScale);
  if (obj.kind === "doorway" || obj.kind === "switch") {
    applyFaceSize(obj);
  } else if (obj.kind === "pickup") {
    applyBackpackProportions(obj);
  } else if (obj.kind === "slope") {
    obj.sx = clampSize(obj.x, obj.sx);
    obj.sy = clampSize(obj.y, obj.sy);
    obj.sz = clampSize(obj.z, obj.sz);
    applySlopeConstraint(obj);
    obj.flags = clampSlopeFlags(obj.flags);
  } else {
    obj.sx = clampSize(obj.x, obj.sx);
    obj.sy = clampSize(obj.y, obj.sy);
    obj.sz = clampSize(obj.z, obj.sz);
  }
  if (obj.kind === "enemy" || obj.kind === "spawn" || obj.kind === "teleporter_dest") {
    obj.rot = clampEnemyRot(obj.rot ?? 0);
  }
  if (obj.kind === "trigger") {
    obj.purpose = clampTriggerPurpose(obj.purpose);
    obj.text = clampTriggerText(obj.text);
    obj.tag = clampTag(obj.tag);
  }
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
  if (obj.kind === "elevator") clampElevHeights(obj);
  if (obj.kind === "pickup") obj.pickup = clampPickupType(obj.pickup);
  if (obj.kind === "enemy") obj.patrol = !!obj.patrol;
  if (obj.kind === "doorway") {
    obj.lockKey = clampDoorLock(obj.lockKey);
    obj.doorType = clampDoorType(obj.doorType);
    obj.locked = obj.lockKey !== "unlocked";
    delete obj.keyTag;
    if (obj.otherRoomId != null) obj.otherRoomId = String(obj.otherRoomId);
    else obj.otherRoomId = null;
  }
  if (obj.kind === "platform") {
    obj.sy = 1;
    obj.collide = obj.collide !== false;
  }
  if (obj.kind === "spawn") obj.enabled = !!obj.enabled;
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
    obj.flags = extra.flags;
  }
  if (kind === "spawn" || kind === "enemy" || kind === "teleporter_dest") {
    obj.rot = clampEnemyRot(extra.rot ?? 0);
  }
  if (kind === "spawn") obj.enabled = extra.enabled === true;
  if (kind === "enemy") {
    const name = extra.enemy || "Grunt";
    obj.enemy = ENEMY_TYPES.some((t) => t.name === name) ? name : "Grunt";
    obj.patrol = !!extra.patrol;
  }
  if (kind === "trigger") {
    obj.purpose = clampTriggerPurpose(extra.purpose);
    obj.text = extra.text;
    obj.tag = extra.tag;
  }
  if (kind === "room") {
    obj.name = clampName(extra.name);
    obj.bgColor = normalizeColor(extra.bgColor ?? extra.skyColor, ROOM_BG_DEFAULT);
    obj.lineColor = normalizeColor(extra.lineColor, ROOM_LINE_DEFAULT);
    obj.fxColor = normalizeColor(extra.fxColor, ROOM_FX_DEFAULT);
    obj.weaponColor = normalizeColor(extra.weaponColor, ROOM_WPN_DEFAULT);
    obj.shape = clampRoomShape(extra.shape);
    obj.rx = extra.rx | 0;
    obj.ry = extra.ry | 0;
    obj.rz = extra.rz | 0;
    if (Array.isArray(extra.cuts)) obj.cuts = extra.cuts.map((c) => ({ su: c.su | 0, sv: c.sv | 0 }));
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
  if (kind === "elevator") {
    obj.elevAuto = extra.elevAuto !== false;
    if (extra.elevLow != null) obj.elevLow = extra.elevLow | 0;
    if (extra.elevHigh != null) obj.elevHigh = extra.elevHigh | 0;
  }
  if (kind === "pickup") obj.pickup = clampPickupType(extra.pickup);
  if (kind === "doorway") {
    obj.lockKey = clampDoorLock(extra.lockKey ?? (extra.locked ? "silver" : "unlocked"));
    obj.doorType = clampDoorType(extra.doorType);
    obj.doorScale = clampDoorScale(extra.doorScale);
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

/** Exactly one spawn `enabled` when any exist. None marked → first in list (old maps). */
export function ensureSpawnExclusive(objects) {
  const spawns = (objects || []).filter((o) => o.kind === "spawn");
  if (!spawns.length) return;
  const on = spawns.filter((s) => s.enabled);
  const keep = on[0] || spawns[0];
  for (const s of spawns) s.enabled = s === keep;
}

export function enableSpawn(objects, spawnId) {
  for (const o of objects || []) {
    if (o.kind === "spawn") o.enabled = o.id === spawnId;
  }
}

/** Objects-panel label: type only (no XYZ). Rooms may include display name. */
export function objectLabel(obj) {
  if (!obj || !KINDS[obj.kind]) return "?";
  if (obj.kind === "room") {
    return obj.name ? `Room  ${obj.name}` : "Room";
  }
  if (obj.kind === "enemy") return obj.enemy || "Enemy";
  if (obj.kind === "pickup") return `Pickup (${clampPickupType(obj.pickup)})`;
  if (obj.kind === "doorway") return `Doorway (${clampDoorType(obj.doorType)})`;
  if (obj.kind === "spawn" && !obj.enabled) return "Spawn (off)";
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
export const ROOM_MAX = 20; // keep in sync with tools/genmap.py
export const ROOM_MAX_TYPES = 2;
export const MAP_MAX_BYTES = 4096;
export const ENEMY_POSE_MAX = 4096;
export const STICK_POSE_BYTES = 13 * 3; // gx+gy+gz per stored pose

/** Packed map header: 11 counts + 3 type ids + 6 spawn + 4 mesh lens. */
export const MAP_HDR_BYTES = 24;

// Keep in sync with tools/genenemies.py (clip-local fire + role names).
const FIRE_FRAME = [2, 4, 4, 6, 2, 4, 8, 4];
const PAIN_MAX = 4;
const ROLE_CLIPS = {
  Grunt: { stand: ["stand"], alert: ["load"], run: ["run"], walk: ["prowl"], attack: ["shoot"] },
  Knight: {
    stand: ["stand"],
    alert: ["standing"],
    run: ["runb"],
    walk: ["walk"],
    attack: ["attackb"],
  },
  Rottweiler: {
    stand: ["stand"],
    alert: ["stand", 2],
    run: ["run"],
    walk: ["walk"],
    attack: ["leap", "attack"],
  },
  Scrag: {
    stand: ["hover"],
    alert: ["hover", 4],
    run: ["fly"],
    walk: ["fly"],
    attack: ["magatt"],
  },
  Ogre: {
    stand: ["stand"],
    alert: ["pull"],
    run: ["run"],
    walk: ["walk"],
    attack: ["swing", "shoot"],
  },
  Shambler: {
    stand: ["stand"],
    alert: ["stand", 4],
    run: ["run"],
    walk: ["walk"],
    attack: ["smash"],
  },
  Chthon: {
    stand: ["walk", 8],
    alert: ["walk", 4],
    run: ["walk"],
    walk: ["walk"],
    attack: ["attack"],
  },
  Zombie: {
    stand: ["stand"],
    alert: ["stand", 4],
    run: ["run"],
    walk: ["walk"],
    attack: ["atta", "attb", "attc"],
  },
};

function poseClipKey(name) {
  return String(name).replace(/_+$/, "").toLowerCase();
}

function poseClipByName(clips, name) {
  for (const c of clips) {
    if (c.name === name) return c;
  }
  const k = poseClipKey(name);
  for (const c of clips) {
    if (poseClipKey(c.name) === k) return c;
  }
  return null;
}

/**
 * Stick clips/frames that will go in the pose PRG (exportClips checkboxes).
 * Missing exportClips → all copied clips. Checked names with no stick frames are skipped.
 */
export function exportPoseData(enemy) {
  const frames = enemy?.frames || [];
  const clips = enemy?.clips || [];
  const names = Array.isArray(enemy?.exportClips) ? enemy.exportClips : null;
  if (!names) return { clips, frames };
  const outClips = [];
  const outFrames = [];
  let start = 0;
  for (const name of names) {
    const c = poseClipByName(clips, name);
    if (!c) continue;
    const slice = frames.slice(c.start | 0, (c.start | 0) + (c.len | 0));
    if (!slice.length) continue;
    outClips.push({ name: c.name, start, len: slice.length });
    outFrames.push(...slice);
    start += slice.length;
  }
  return { clips: outClips, frames: outFrames };
}

function findPoseClip(clips, ...names) {
  for (const want of names) {
    for (const c of clips) {
      if (poseClipKey(c.name) === want) return [c.start | 0, c.len | 0];
    }
  }
  return null;
}

function findPoseRole(name, clips, role) {
  if (role === "attack") return null;
  const spec = ROLE_CLIPS[name]?.[role];
  if (!spec) return null;
  const found = findPoseClip(clips, spec[0]);
  if (!found) return null;
  let [start, length] = found;
  if (spec[1] != null) length = Math.min(length, spec[1]);
  return [start, length];
}

/** Attack ROLE candidates present in clips (export order), up to PAIN_MAX. */
function findPoseAttackVariants(name, clips) {
  const names = ROLE_CLIPS[name]?.attack || [];
  const want = new Set(names.filter((n) => typeof n === "string").map(poseClipKey));
  const out = [];
  for (const c of clips) {
    if (!want.has(poseClipKey(c.name))) continue;
    out.push([c.start | 0, c.len | 0]);
    if (out.length >= PAIN_MAX) break;
  }
  if (!out.length) {
    const stand = findPoseClip(clips, "stand", "walk", "hover");
    if (stand) out.push([stand[0], 1]);
  }
  return out;
}

function findPoseVariants(clips, kind) {
  const re = kind === "pain" ? /^pain[a-z]?$/ : /^(bdeath|death[a-z]?)$/;
  const out = [];
  for (const c of clips) {
    if (!re.test(poseClipKey(c.name))) continue;
    out.push([c.start | 0, c.len | 0]);
    if (out.length >= PAIN_MAX) break;
  }
  if (!out.length) {
    const stand = findPoseClip(clips, "stand", "walk", "hover");
    if (stand) out.push([stand[0], 1]);
  }
  return out;
}

function poseAccAt(frs, i) {
  if (!frs || i <= 0 || i >= frs.length - 1) return 0;
  let m = 0;
  const a = frs[i - 1];
  const b = frs[i];
  const c = frs[i + 1];
  if (!a || !b || !c) return 0;
  for (let v = 0; v < 13; v++) {
    for (const k of ["x", "y", "z"]) {
      const d = Math.abs((c[v][k] | 0) - 2 * (b[v][k] | 0) + (a[v][k] | 0));
      if (d > m) m = d;
    }
  }
  return m;
}

function posePickKeys(frs, start, length, extra) {
  if (length <= 2) return [];
  const minSep = Math.max(2, (length / 3) | 0);
  const keys = [];
  for (const e of extra) {
    if (start < e && e < start + length - 1) keys.push(e);
    if (keys.length >= 2) return keys.slice(0, 2).sort((a, b) => a - b);
  }
  if (!frs) return keys.sort((a, b) => a - b);
  const scored = [];
  for (let i = start + 1; i < start + length - 1; i++) {
    scored.push([poseAccAt(frs, i), i]);
  }
  scored.sort((a, b) => b[0] - a[0] || b[1] - a[1]);
  for (const [, i] of scored) {
    if (keys.some((k) => Math.abs(i - k) < minSep)) continue;
    keys.push(i);
    if (keys.length === 2) break;
  }
  return keys.sort((a, b) => a - b);
}

function poseCadenceKeep(start, length, keys) {
  if (length <= 0) return new Set();
  const last = start + length - 1;
  const keyset = new Set(keys);
  const kept = [];
  let f = start;
  while (f < last) {
    const plug = [...keyset].filter((k) => f < k && k < f + 2).sort((a, b) => a - b);
    kept.push(f);
    if (plug.length) {
      kept.push(plug[0]);
      f = plug[0] + 2;
    } else {
      f += 2;
    }
  }
  kept.push(last);
  return new Set(kept);
}

function poseUncoveredRuns(covered) {
  const out = [];
  let i = 0;
  while (i < covered.length) {
    if (covered[i]) {
      i += 1;
      continue;
    }
    let j = i + 1;
    while (j < covered.length && !covered[j]) j += 1;
    out.push([i, j - i]);
    i = j;
  }
  return out;
}

/**
 * Packed pose PRG size (tools/genenemies.py pack_poses).
 * clips: [{name, start, len}] covering the logical timeline.
 * frames: stick verts for those logical indices, or null → cadence + fire pin only.
 */
export function packedPoseBytes(enemy, clips, frames) {
  const name = enemy?.name || "Grunt";
  if (clips === undefined) {
    const pose = exportPoseData(enemy);
    clips = pose.clips;
    frames = pose.frames;
  }
  const clipList = clips || [];
  const frs = frames && frames.length ? frames : null;
  let nLogical = 0;
  for (const c of clipList) {
    const end = (c.start | 0) + (c.len | 0);
    if (end > nLogical) nLogical = end;
  }
  if (frs && frs.length > nLogical) nLogical = frs.length;
  if (nLogical <= 0) return { bytes: 0, nLogical: 0, nStored: 0 };

  const typeI = Math.max(
    0,
    ENEMY_TYPES.findIndex((t) => t.name === name),
  );
  const covered = Array(nLogical).fill(false);
  const keep = new Set();
  const fireOff = FIRE_FRAME[typeI] ?? 2;

  const ranges = [];
  for (const role of ["stand", "alert", "run", "walk"]) {
    const found = findPoseRole(name, clipList, role);
    if (!found) continue;
    let [start, length] = found;
    if (start >= nLogical || length <= 0) continue;
    length = Math.min(length, nLogical - start);
    ranges.push([role, start, length]);
  }
  findPoseAttackVariants(name, clipList).forEach(([start, length], i) => {
    if (start >= nLogical || length <= 0) return;
    ranges.push([`attack${i}`, start, Math.min(length, nLogical - start)]);
  });
  for (const kind of ["pain", "death"]) {
    findPoseVariants(clipList, kind).forEach(([start, length], i) => {
      if (start >= nLogical || length <= 0) return;
      ranges.push([`${kind}${i}`, start, Math.min(length, nLogical - start)]);
    });
  }
  for (const [role, start, length] of ranges) {
    const extra =
      typeof role === "string" && role.startsWith("attack") && fireOff >= 0
        ? [start + fireOff]
        : [];
    for (const i of poseCadenceKeep(start, length, posePickKeys(frs, start, length, extra))) {
      keep.add(i);
    }
    for (let i = start; i < start + length; i++) covered[i] = true;
  }
  for (const c of clipList) {
    const start = c.start | 0;
    let length = c.len | 0;
    if (start >= nLogical || length <= 0) continue;
    length = Math.min(length, nLogical - start);
    let all = true;
    for (let i = start; i < start + length; i++) {
      if (!covered[i]) {
        all = false;
        break;
      }
    }
    if (all) continue;
    for (const i of poseCadenceKeep(start, length, posePickKeys(frs, start, length, []))) {
      keep.add(i);
    }
    for (let i = start; i < start + length; i++) covered[i] = true;
  }
  for (const [start, length] of poseUncoveredRuns(covered)) {
    for (const i of poseCadenceKeep(start, length, posePickKeys(frs, start, length, []))) {
      keep.add(i);
    }
  }

  const nStored = keep.size;
  const bytes = 2 + nLogical + nStored * STICK_POSE_BYTES;
  return { bytes, nLogical, nStored };
}

/** Unique enemy type names in one room (unknown names count as Grunt). */
export function roomEnemyTypeNames(map, roomId) {
  const names = [];
  if (roomId == null) return names;
  const rid = String(roomId);
  for (const obj of map?.objects || []) {
    if (obj.kind !== "enemy") continue;
    if (String(obj.roomId) !== rid) continue;
    const raw = obj.enemy || "Grunt";
    const name = ENEMY_TYPES.some((t) => t.name === raw) ? raw : "Grunt";
    if (!names.includes(name)) names.push(name);
  }
  return names;
}

/** Unique enemy type names placed on a map (unknown names count as Grunt). */
export function mapEnemyTypeNames(map) {
  const names = [];
  for (const obj of map?.objects || []) {
    if (obj.kind !== "enemy") continue;
    const raw = obj.enemy || "Grunt";
    const name = ENEMY_TYPES.some((t) => t.name === raw) ? raw : "Grunt";
    if (!names.includes(name)) names.push(name);
  }
  return names;
}

/** True if placing/changing to typeName in roomId stays within ROOM_MAX_TYPES. */
export function canAddEnemyType(map, typeName, roomId) {
  const names = roomEnemyTypeNames(map, roomId);
  const raw = typeName || "Grunt";
  const name = ENEMY_TYPES.some((t) => t.name === raw) ? raw : "Grunt";
  if (names.includes(name)) return true;
  return names.length < ROOM_MAX_TYPES;
}

/**
 * Bytes per instance in the cooked C64 SoA (tools/genmap.py).
 * Trigger text blob is counted separately. Spawn lives in the 24-byte header.
 */
export const C64_OBJECT_BYTES = {
  room: 11,
  doorway: 11, // one baked instance; +11 if otherRoomId (see mapStats)
  crate: 8,
  slope: 11,
  platform: 8,
  elevator: 11,
  switch: 10,
  enemy: 8,
  trigger: 10,
  spawn: 0,
  pickup: 6,
  teleporter_dest: 5,
};

/** Counts + packed map RAM for the active level (matches genmap cook_one). */
export function mapStats(doc) {
  const map = activeMap(doc);
  const byKind = {};
  let total = 0;
  let c64Bytes = MAP_HDR_BYTES;
  c64Bytes += clampName(map.name).length + 1; // map_name + NUL
  let hasSpawn = false;
  let mapText = 0;
  for (const obj of map.objects) {
    const kind = obj.kind;
    if (!KINDS[kind]) continue;
    total += 1;
    byKind[kind] = (byKind[kind] || 0) + 1;
    if (kind === "spawn") {
      if (hasSpawn) continue; // engine keeps one spawn record in the header
      hasSpawn = true;
      continue;
    }
    c64Bytes += C64_OBJECT_BYTES[kind] ?? 8;
    if (kind === "doorway" && obj.otherRoomId) {
      c64Bytes += 11; // second baked instance for the far room
    }
    if (kind === "room") {
      c64Bytes += 18; // three collider slots (3×6)
      c64Bytes += 12; // two cutout slots (2×6), always padded
      c64Bytes += 8; // nv/ne/vo/eo/nx/nz/uo/zo (zeros on box)
      c64Bytes += 2; // room_door_o + room_ndoor
      if (clampRoomShape(obj.shape) !== "box") {
        const g = roomGeometry(obj);
        const nx = new Set(g.verts.map((v) => v.x)).size;
        const nz = new Set(g.verts.map((v) => v.z)).size;
        c64Bytes += nx + nz + g.verts.length * 4 + g.edges.length * 4;
      }
    }
    if (kind === "trigger" && clampTriggerPurpose(obj.purpose) === "message") {
      const text = String(obj.text || "")
        .replace(/\r\n/g, "\n")
        .split("\n", 1)[0]
        .slice(0, 40);
      mapText += text.length + 1; // chars + NUL in map_text
    }
  }
  c64Bytes += mapText || 1; // dummy NUL if no message triggers
  const enemyTypes = mapEnemyTypeNames(map);
  const enemyTypeCount = enemyTypes.length;
  let overTypes = false;
  const roomTypeCounts = new Map();
  for (const obj of map.objects) {
    if (obj.kind !== "enemy") continue;
    const rid = obj.roomId != null ? String(obj.roomId) : "";
    const raw = obj.enemy || "Grunt";
    const name = ENEMY_TYPES.some((t) => t.name === raw) ? raw : "Grunt";
    let set = roomTypeCounts.get(rid);
    if (!set) {
      set = new Set();
      roomTypeCounts.set(rid, set);
    }
    set.add(name);
  }
  for (const set of roomTypeCounts.values()) {
    if (set.size > ROOM_MAX_TYPES) {
      overTypes = true;
      break;
    }
  }
  // Pose peak = worst room's cohabiting types (streaming holds ≤ ROOM_MAX_TYPES).
  const poseSize = (name) => {
    const e = (doc.enemies || []).find((en) => en.name === name);
    return e ? packedPoseBytes(e).bytes : 0;
  };
  let poseBytes = 0;
  let poseParts = [];
  for (const set of roomTypeCounts.values()) {
    const names = [...set].sort();
    const sum = names.reduce((s, n) => s + poseSize(n), 0);
    if (sum > poseBytes) {
      poseBytes = sum;
      poseParts = names.map((n) => `${n} ${poseSize(n)}`);
    }
  }
  const loadBytes = c64Bytes + poseBytes;
  return {
    total,
    byKind,
    c64Bytes,
    poseBytes,
    loadBytes,
    poseParts,
    max: MAX_MAP_OBJECTS,
    enemyTypes,
    enemyTypeCount,
    overTypes,
    overRooms: (byKind.room || 0) > ROOM_MAX,
    overBudget: overTypes || (byKind.room || 0) > ROOM_MAX,
  };
}

export function formatMapStats(stats) {
  const load = `${stats.c64Bytes}:${stats.loadBytes}`;
  const parts = [load, `${stats.total}/${stats.max} objects`];
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
    "pickup",
    "teleporter_dest",
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
    pickup: "pickups",
    teleporter_dest: "dests",
  };
  for (const kind of order) {
    const n = stats.byKind[kind];
    if (!n) continue;
    const one = KINDS[kind]?.label?.toLowerCase() || kind;
    const label = n === 1 ? one : plurals[kind] || `${one}s`;
    if (kind === "room") {
      parts.push(`${n}/${ROOM_MAX} ${label}`);
      continue;
    }
    parts.push(`${n} ${label}`);
  }
  parts.push(`≤${ROOM_MAX_TYPES} types/room`);
  return parts.join(" · ");
}

export function formatMapLoadTitle(stats) {
  const bits = [`map ${stats.c64Bytes}`, ...(stats.poseParts || [])];
  return `${bits.join(" + ")} = ${stats.loadBytes}`;
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

/** Hull-face scores below this are on-wall; +50 is a lateral miss. */
const DOOR_PAIR_MAX = 8;
const DOOR_PAIR_SLACK = 4;

/** Closest room, plus a second room across the same portal if still close. */
export function inferDoorRoomPair(doc, door) {
  if (!door || door.kind !== "doorway") return { room: null, other: null };
  const scored = doorRoomScores(door, roomsOf(doc));
  if (!scored.length || scored[0].score >= 50) return { room: null, other: null };
  const best = scored[0];
  const closeLimit = Math.min(DOOR_PAIR_MAX, best.score + DOOR_PAIR_SLACK);
  let otherHit = null;
  for (const hit of scored) {
    if (hit.room.id === best.room.id) continue;
    if (hit.score > closeLimit) continue;
    const opposite = hit.f.axis === best.f.axis && hit.f.sign !== best.f.sign;
    const ranked = opposite ? hit.score : hit.score + 100;
    if (!otherHit || ranked < otherHit.ranked) otherHit = { hit, ranked };
  }
  return { room: best.room, other: otherHit?.hit.room || null };
}

export function assignDoorRooms(doc, door, owner, snap = true) {
  if (!door || door.kind !== "doorway") return door;
  const pair = inferDoorRoomPair(doc, door);
  const a = pair.room;
  const b = pair.other;
  const ownerId = owner?.id || null;
  if (ownerId && a && ownerId === a.id) {
    door.roomId = a.id;
    door.otherRoomId = b?.id || null;
  } else if (ownerId && b && ownerId === b.id) {
    door.roomId = b.id;
    door.otherRoomId = a?.id || null;
  } else if (a) {
    door.roomId = a.id;
    door.otherRoomId = b?.id || null;
  } else if (ownerId) {
    door.roomId = ownerId;
    door.otherRoomId = door.otherRoomId === ownerId ? null : door.otherRoomId || null;
  } else {
    door.roomId = null;
    door.otherRoomId = null;
  }
  if (door.otherRoomId === door.roomId) door.otherRoomId = null;
  const roomA = roomById(doc, door.roomId);
  const roomB = roomById(doc, door.otherRoomId);
  if (snap) snapDoorBetweenRooms(door, roomA, roomB);
  else orientDoorToRooms(door, roomA, roomB);
  return door;
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

/** Selected room, or owner room of the newest selected object; else lastRoomId. */
export function localFocusRoom(doc, selectedIds, lastId) {
  const ids = Array.isArray(selectedIds) ? selectedIds : [];
  const objs = activeMap(doc).objects;
  for (let i = ids.length - 1; i >= 0; i--) {
    const obj = objs.find((o) => o.id === ids[i]);
    if (!obj) continue;
    if (obj.kind === "room") return obj;
    const r = roomById(doc, obj.roomId);
    if (r) return r;
  }
  return roomById(doc, lastId);
}

export function localVisibleIds(doc, focus, includeNeighbours) {
  if (!focus) return new Set();
  const rooms = [focus, ...(includeNeighbours ? neighbourRooms(doc, focus) : [])];
  const roomIds = new Set(rooms.map((r) => r.id));
  const ids = new Set(roomIds);
  for (const obj of activeMap(doc).objects) {
    if (obj.kind === "room") continue;
    if (roomIds.has(obj.roomId) || (obj.kind === "doorway" && roomIds.has(obj.otherRoomId))) {
      ids.add(obj.id);
    }
  }
  return ids;
}

export function objectVisible(doc, obj, localMode, focus, neighbours) {
  if (!localMode) return true;
  return localVisibleIds(doc, focus, neighbours).has(obj.id);
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
    lodZ: defaultEnemyLodZ(name),
  };
}

export function createAllCreatures() {
  return ENEMY_TYPES.map((t) => createEnemy(t.name));
}

function migrateDoorLock(o) {
  if (o.lockKey != null) return clampDoorLock(o.lockKey);
  if (o.locked) {
    const t = String(o.keyTag || o.tag || "").toLowerCase();
    return t.includes("gold") ? "gold" : "silver";
  }
  return "unlocked";
}

function migrateLoadedObject(o) {
  if (!o || typeof o !== "object") return o;
  const out = { ...o };
  if (out.kind === "backpack") {
    out.kind = "pickup";
    out.pickup = out.pickup || out.backpack;
  }
  if (out.kind === "key") {
    out.kind = "pickup";
    const t = `${out.tag || ""} ${out.keyTag || ""} ${out.pickup || ""}`.toLowerCase();
    out.pickup = t.includes("gold") ? "gold key" : "silver key";
  }
  if (out.kind === "doorway") out.lockKey = migrateDoorLock(out);
  return out;
}

function parseObjects(list) {
  const out = [];
  for (const raw of list || []) {
    const o = migrateLoadedObject(raw);
    if (!KINDS[o.kind]) continue;
    const obj = createObject(o.kind, o.x, o.y, o.z, {
      id: o.id,
      face: o.face,
      axis: o.axis,
      dir: o.dir,
      flags: o.flags,
      enemy: o.enemy,
      patrol: o.patrol,
      rot: o.rot,
      text: o.text,
      purpose: o.purpose,
      name: o.name,
      tag: o.tag,
      lockKey: o.lockKey,
      doorType: o.doorType,
      doorScale: o.doorScale,
      locked: o.locked,
      keyTag: o.keyTag,
      elevAuto: o.elevAuto,
      elevLow: o.elevLow,
      elevHigh: o.elevHigh,
      pickup: o.pickup,
      backpack: o.backpack,
      order: o.order,
      collide: o.collide,
      enabled: o.enabled,
      bgColor: o.bgColor ?? o.skyColor,
      skyColor: o.skyColor,
      lineColor: o.lineColor,
      fxColor: o.fxColor,
      weaponColor: o.weaponColor,
      shape: o.shape,
      rx: o.rx,
      ry: o.ry,
      rz: o.rz,
      cuts: o.cuts,
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
    if (o.kind === "enemy") obj.patrol = !!o.patrol;
    if (o.kind === "trigger") {
      if (o.text != null) obj.text = clampTriggerText(o.text);
      if (o.purpose != null) obj.purpose = clampTriggerPurpose(o.purpose);
      if (o.tag != null) obj.tag = clampTag(o.tag);
    }
    if (o.kind === "room") {
      if (o.name != null) obj.name = clampName(o.name);
      const bg = o.bgColor ?? o.skyColor;
      if (bg != null) obj.bgColor = normalizeColor(bg, ROOM_BG_DEFAULT);
      if (o.lineColor != null) obj.lineColor = normalizeColor(o.lineColor, ROOM_LINE_DEFAULT);
      if (o.fxColor != null) obj.fxColor = normalizeColor(o.fxColor, ROOM_FX_DEFAULT);
      if (o.weaponColor != null) obj.weaponColor = normalizeColor(o.weaponColor, ROOM_WPN_DEFAULT);
      if (o.shape != null) obj.shape = clampRoomShape(o.shape);
      if (o.rx != null) obj.rx = o.rx | 0;
      if (o.ry != null) obj.ry = o.ry | 0;
      if (o.rz != null) obj.rz = o.rz | 0;
      if (Array.isArray(o.cuts)) obj.cuts = o.cuts.map((c) => ({ su: c.su | 0, sv: c.sv | 0 }));
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
    if (o.kind === "elevator") {
      obj.elevAuto = o.elevAuto !== false;
      if (o.elevLow != null) obj.elevLow = o.elevLow | 0;
      if (o.elevHigh != null) obj.elevHigh = o.elevHigh | 0;
      delete obj.elevType;
    }
    if (o.kind === "pickup" || o.kind === "backpack") {
      obj.pickup = clampPickupType(o.pickup || o.backpack);
    }
    if (o.kind === "doorway") {
      obj.lockKey = migrateDoorLock(o);
      if (o.otherRoomId != null) obj.otherRoomId = String(o.otherRoomId);
    }
    if (o.kind === "platform" && o.collide != null) obj.collide = o.collide !== false;
    if (o.kind === "spawn") obj.enabled = o.enabled === true;
    out.push(clampObject(obj));
  }
  ensureSpawnExclusive(out);
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
    neighbourDraw: false,
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
    layoutCameras: {},
    item: "backpack",
    itemOrbit: { yaw: 0.6, pitch: 0.35, dist: 16, target: { x: 0, y: 0, z: 0 } },
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

function parseLayoutCamera(raw, fallback) {
  return {
    x: num(raw?.x, fallback.x),
    y: num(raw?.y, fallback.y),
    z: num(raw?.z, fallback.z),
    yaw: num(raw?.yaw, fallback.yaw),
    pitch: num(raw?.pitch, fallback.pitch),
    speed: Math.max(6, Math.min(80, num(raw?.speed, fallback.speed))),
  };
}

export function parseEditorState(raw) {
  const d = defaultEditorState();
  if (!raw || typeof raw !== "object") return d;
  if (raw.mode === "anim" || raw.mode === "layout" || raw.mode === "weapons" || raw.mode === "items") d.mode = raw.mode;
  d.localDraw = !!raw.localDraw;
  d.neighbourDraw = !!raw.neighbourDraw;
  if (Array.isArray(raw.selectedIds)) d.selectedIds = raw.selectedIds.map(String);
  if (typeof raw.enemy === "string" && raw.enemy) d.enemy = raw.enemy;
  d.frameIndex = Math.max(0, num(raw.frameIndex, 0) | 0);
  d.clipIndex = Math.max(0, num(raw.clipIndex, 0) | 0);
  d.frameLocal = Math.max(0, num(raw.frameLocal, 0) | 0);
  if (Array.isArray(raw.selectedVerts)) {
    d.selectedVerts = raw.selectedVerts.map((i) => i | 0).filter((i) => i >= 0 && i < 13);
  }
  const cam = raw.layoutCamera || {};
  d.layoutCamera = parseLayoutCamera(cam, d.layoutCamera);
  d.layoutCameras = {};
  if (raw.layoutCameras && typeof raw.layoutCameras === "object") {
    for (const name of LEVEL_NAMES) {
      if (raw.layoutCameras[name]) {
        d.layoutCameras[name] = parseLayoutCamera(raw.layoutCameras[name], d.layoutCamera);
      }
    }
  }
  const camLevel =
    typeof raw.activeLevel === "string" && LEVEL_NAMES.includes(raw.activeLevel)
      ? raw.activeLevel
      : d.activeLevel || LEVEL_NAMES[0];
  if (raw.layoutCamera && !d.layoutCameras[camLevel]) {
    d.layoutCameras[camLevel] = { ...d.layoutCamera };
  }
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
  if (typeof raw.item === "string" && ALL_MESH_KEYS.includes(raw.item)) d.item = raw.item;
  const io = raw.itemOrbit || {};
  const tgt = io.target || {};
  d.itemOrbit = {
    yaw: num(io.yaw, d.itemOrbit.yaw),
    pitch: Math.max(-1.2, Math.min(1.2, num(io.pitch, d.itemOrbit.pitch))),
    dist: Math.max(ITEM_ORBIT_DIST_MIN, Math.min(ITEM_ORBIT_DIST_MAX, num(io.dist, d.itemOrbit.dist))),
    target: {
      x: num(tgt.x, d.itemOrbit.target.x),
      y: num(tgt.y, d.itemOrbit.target.y),
      z: num(tgt.z, d.itemOrbit.target.z),
    },
  };
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
    items: doc.items,
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
    items: defaultItemMeshes(),
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
      enemy.lodZ = clampEnemyLodZ(e.lodZ, enemy.name);
      const exportClips = normalizeExportClips(e.exportClips);
      if (exportClips) enemy.exportClips = exportClips;
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
  doc.items = parseItemMeshes(migrateItemMeshes(raw.items, fromVersion));
  doc.editor = parseEditorState(raw.editor);
  return doc;
}
