export function uid() {
  if (globalThis.crypto?.randomUUID) return crypto.randomUUID();
  return `id-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 8)}`;
}

export const WORLD_MIN = 0;
export const WORLD_MAX = 255;
export const WORLD_SIZE = 256;
export const MAX_VERTS = 16;
export const MAX_LINES = 16;
export const VERT_MIN = -64;
export const VERT_MAX = 63;

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
    defaultSize: [6, 6, 6],
    fixed: false,
    slope: false,
  },
  slope: {
    id: "slope",
    label: "Ramp",
    color: "#5cb85c",
    defaultSize: [6, 6, 12],
    fixed: false,
    slope: true,
  },
  doorway: {
    id: "doorway",
    label: "Doorway",
    color: "#e6c84a",
    defaultSize: [8, 8, 1],
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
};

export const PALETTE_ORDER = ["room", "doorway", "switch", "slope", "crate", "elevator"];

export const FRAME_NAMES = [
  "Walk 0",
  "Walk 1",
  "Attack A 0",
  "Attack A 1",
  "Attack B 0",
  "Attack B 1",
  "Flinch 0",
  "Flinch 1",
  "Death 0",
  "Death 1",
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
  return obj;
}

export function createObject(kind, x, y, z, extra = {}) {
  const def = KINDS[kind];
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
    obj.sx = 6;
    obj.sy = 6;
    obj.sz = 12;
  }
  return clampObject(obj);
}

export function cycleFace(faceId, delta) {
  const i = FACES.findIndex((f) => f.id === faceId);
  const n = (i + delta + FACES.length) % FACES.length;
  return FACES[n].id;
}

export function roomsOf(doc) {
  return doc.map.objects.filter((o) => o.kind === "room");
}

export function doorwaysOf(doc) {
  return doc.map.objects.filter((o) => o.kind === "doorway");
}

export function currentRoom(doc, cam) {
  const rooms = roomsOf(doc).filter((r) => pointInAabb(cam, r));
  if (!rooms.length) return null;
  rooms.sort((a, b) => aabbVolume(a) - aabbVolume(b));
  return rooms[0];
}

export function neighbourRooms(doc, room) {
  if (!room) return [];
  const doors = doorwaysOf(doc);
  const out = [];
  for (const other of roomsOf(doc)) {
    if (other.id === room.id) continue;
    const linked = doors.some((d) => aabbOverlap(d, room) && aabbOverlap(d, other));
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
  for (const obj of doc.map.objects) {
    if (obj.kind === "room") continue;
    if (rooms.some((r) => aabbOverlap(obj, r))) ids.add(obj.id);
  }
  return ids;
}

export function objectVisible(doc, obj, cam, localMode) {
  if (!localMode) return true;
  return localVisibleIds(doc, cam).has(obj.id);
}

function pose(overrides) {
  const base = [
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
  ];
  return base.map((p, i) => {
    const o = overrides[i];
    if (!o) return { x: p[0], y: p[1], z: p[2] };
    return { x: p[0] + o[0], y: p[1] + o[1], z: p[2] + o[2] };
  });
}

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
];

const FRAME_OFFSETS = [
  { 5: [0, 0, 2], 7: [0, 0, -2], 9: [0, 0, -2], 11: [0, 0, 2] },
  { 5: [0, 0, -2], 7: [0, 0, 2], 9: [0, 0, 2], 11: [0, 0, -2] },
  { 5: [0, 2, 4], 4: [0, 1, 2], 3: [1, 0, 1] },
  { 5: [1, 3, 6], 4: [0, 2, 3], 3: [2, 0, 2] },
  { 7: [0, 2, 4], 6: [0, 1, 2] },
  { 7: [1, 3, 6], 6: [0, 2, 3] },
  { 2: [1, -1, 0], 3: [2, -1, 0] },
  { 2: [2, -2, 0], 3: [3, -2, 1] },
  { 2: [0, -4, 2], 3: [0, -5, 4], 5: [0, -3, 0], 7: [0, -3, 0] },
  {
    0: [4, -5, 2],
    1: [6, -6, 3],
    2: [5, -4, 4],
    3: [8, -3, 5],
    8: [4, -6, 1],
    9: [4, -6, 0],
    10: [7, -6, 2],
    11: [8, -6, 1],
  },
];

export function defaultStickFrames() {
  return FRAME_OFFSETS.map((off) => pose(off));
}

export function createEnemy(name = "Grunt") {
  return {
    id: uid(),
    name,
    verts: 12,
    lines: TEMPLATE_LINES.map((p) => [p[0], p[1]]),
    frames: defaultStickFrames(),
  };
}

export function createDefaultDocument() {
  const roomA = createObject("room", 8, 0, 8);
  roomA.sx = 24;
  roomA.sy = 12;
  roomA.sz = 24;
  const roomB = createObject("room", 31, 0, 8);
  roomB.sx = 24;
  roomB.sy = 12;
  roomB.sz = 24;
  const door = createObject("doorway", 31, 0, 16, { face: "+x" });
  const crate = createObject("crate", 14, 0, 14);
  return {
    version: 1,
    map: { objects: [roomA, roomB, door, crate] },
    enemies: [createEnemy("Grunt")],
  };
}

export function cloneDoc(doc) {
  return JSON.parse(JSON.stringify(doc));
}

export function normalizeDocument(raw) {
  const doc = createDefaultDocument();
  if (!raw || typeof raw !== "object") return doc;
  doc.map.objects = [];
  const objs = raw.map?.objects || raw.objects || [];
  for (const o of objs) {
    if (!KINDS[o.kind]) continue;
    const obj = createObject(o.kind, o.x, o.y, o.z, {
      id: o.id,
      face: o.face,
      axis: o.axis,
      dir: o.dir,
    });
    if (!KINDS[o.kind].fixed) {
      obj.sx = o.sx ?? obj.sx;
      obj.sy = o.sy ?? obj.sy;
      obj.sz = o.sz ?? obj.sz;
    }
    doc.map.objects.push(clampObject(obj));
  }
  doc.enemies = [];
  const enemies = raw.enemies || [];
  for (const e of enemies) {
    const enemy = createEnemy(e.name || "Enemy");
    enemy.id = e.id || enemy.id;
    const lines = Array.isArray(e.lines) ? e.lines.slice(0, MAX_LINES) : enemy.lines;
    enemy.lines = lines
      .filter((p) => Array.isArray(p) && p.length >= 2)
      .map((p) => [p[0] | 0, p[1] | 0]);
    let nverts = e.verts | 0;
    if (Array.isArray(e.frames?.[0])) nverts = Math.max(nverts, e.frames[0].length);
    enemy.verts = Math.max(1, Math.min(MAX_VERTS, nverts || enemy.verts));
    const srcFrames = Array.isArray(e.frames) ? e.frames : [];
    enemy.frames = FRAME_NAMES.map((_, fi) => {
      const src = srcFrames[fi] || srcFrames[0] || enemy.frames[0];
      const verts = [];
      for (let i = 0; i < enemy.verts; i++) {
        const v = src[i] || { x: 0, y: 0, z: 0 };
        verts.push({ x: clampVert(v.x), y: clampVert(v.y), z: clampVert(v.z) });
      }
      return verts;
    });
    for (const ln of enemy.lines) {
      ln[0] = Math.max(0, Math.min(enemy.verts - 1, ln[0]));
      ln[1] = Math.max(0, Math.min(enemy.verts - 1, ln[1]));
    }
    doc.enemies.push(enemy);
  }
  if (!doc.enemies.length) doc.enemies.push(createEnemy("Grunt"));
  if (!doc.map.objects.length) return createDefaultDocument();
  return doc;
}
