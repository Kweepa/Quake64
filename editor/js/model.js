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
/** L/R hip, elbow, wrist, knee, ankle. Neck 2 and head 3 stay. */
export const SKELETON_MIRROR_PAIRS = [
  [0, 1],
  [4, 6],
  [5, 7],
  [8, 10],
  [9, 11],
];
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

export const LEVEL_NAMES = ["E1M1", "E1M2", "E1M3", "E1M4", "E1M5", "E1M6", "E1M7", "E1M8"];

export const FRAME_NAMES = [
  "Idle 0",
  "Idle 1",
  "Alert 0",
  "Alert 1",
  "Walk 0",
  "Walk 1",
  "Walk 2",
  "Walk 3",
  "AtkA 0",
  "AtkA 1",
  "AtkA 2",
  "AtkA 3",
  "AtkB 0",
  "AtkB 1",
  "AtkB 2",
  "AtkB 3",
  "AtkC 0",
  "AtkC 1",
  "AtkC 2",
  "AtkC 3",
  "Flinch",
  "Death 0",
  "Death 1",
  "Death 2",
];

export const ANIM_CLIPS = [
  { name: "Idle", start: 0, len: 2 },
  { name: "Alert", start: 2, len: 2 },
  { name: "Walk", start: 4, len: 4 },
  { name: "AtkA", start: 8, len: 4 },
  { name: "AtkB", start: 12, len: 4 },
  { name: "AtkC", start: 16, len: 4 },
  { name: "Flinch", start: 20, len: 1 },
  { name: "Death", start: 21, len: 3 },
];

export function clipForFrame(index) {
  return ANIM_CLIPS.find((c) => index >= c.start && index < c.start + c.len) || ANIM_CLIPS[0];
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

/** Mirror one pose across X: swap L/R limbs, keep weapon offset from right wrist. */
export function flipFrameX(verts) {
  const snap = verts.map((v) => ({ x: v.x, y: v.y, z: v.z }));
  const srcOf = verts.map((_, i) => i);
  for (const [a, b] of SKELETON_MIRROR_PAIRS) {
    srcOf[a] = b;
    srcOf[b] = a;
  }
  for (let i = 0; i < WEAPON_VERT; i++) {
    const src = snap[srcOf[i]];
    verts[i].x = clampVert(-src.x);
    verts[i].y = clampVert(src.y);
    verts[i].z = clampVert(src.z);
  }
  const relx = snap[WEAPON_VERT].x - snap[WRIST_R].x;
  const rely = snap[WEAPON_VERT].y - snap[WRIST_R].y;
  const relz = snap[WEAPON_VERT].z - snap[WRIST_R].z;
  verts[WEAPON_VERT].x = clampVert(verts[WRIST_R].x + relx);
  verts[WEAPON_VERT].y = clampVert(verts[WRIST_R].y + rely);
  verts[WEAPON_VERT].z = clampVert(verts[WRIST_R].z + relz);
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

export function emptyMap() {
  return { objects: [] };
}

export function activeMap(doc) {
  const name = LEVEL_NAMES.includes(doc.activeLevel) ? doc.activeLevel : LEVEL_NAMES[0];
  doc.activeLevel = name;
  if (!doc.maps) doc.maps = {};
  if (!doc.maps[name]) doc.maps[name] = emptyMap();
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
  for (const obj of activeMap(doc).objects) {
    if (obj.kind === "room") continue;
    if (rooms.some((r) => aabbOverlap(obj, r))) ids.add(obj.id);
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

function swing(phase, amp) {
  const s = [0, amp, 0, -amp][phase & 3];
  return {
    4: [0, 0, (s / 2) | 0],
    5: [0, 0, s],
    6: [0, 0, (-s / 2) | 0],
    7: [0, 0, -s],
    12: [0, 0, -s],
    8: [0, 0, (-s / 2) | 0],
    9: [0, 0, -s],
    10: [0, 0, (s / 2) | 0],
    11: [0, 0, s],
  };
}

const FRAME_OFFSETS = [
  { 2: [0, 0, 0], 3: [0, 0, 0] },
  { 2: [0, 1, 0], 3: [0, 1, 0] },
  { 3: [0, 2, 1], 4: [-2, 1, 0], 5: [-3, 2, 1], 6: [2, 1, 0], 7: [3, 2, 1] },
  { 3: [1, 3, 2], 4: [-3, 2, 1], 5: [-4, 3, 2], 6: [3, 2, 1], 7: [4, 3, 2] },
  swing(0, 3),
  swing(1, 3),
  swing(2, 3),
  swing(3, 3),
  { 4: [0, 1, 2], 5: [0, 2, 4], 3: [1, 0, 1] },
  { 4: [0, 2, 3], 5: [1, 3, 6], 3: [2, 0, 2] },
  { 4: [0, 1, 4], 5: [2, 2, 7], 3: [1, 0, 3] },
  { 4: [0, 0, 1], 5: [0, 0, 2], 3: [0, 0, 0] },
  { 6: [0, 1, 2], 7: [0, 2, 4], 5: [0, 1, -1] },
  { 6: [0, 2, 3], 7: [1, 4, 6], 5: [0, 2, -2] },
  { 6: [0, 1, 5], 7: [2, 3, 8], 5: [0, 1, -1] },
  { 6: [0, 0, 1], 7: [0, 1, 2] },
  { 4: [-1, 2, 0], 5: [-2, 4, 0], 6: [1, 2, 0], 7: [2, 4, 0], 2: [0, -1, 0] },
  { 4: [-2, 3, 1], 5: [-3, 6, 2], 6: [2, 3, 1], 7: [3, 6, 2], 2: [0, -2, 0] },
  { 4: [-1, 1, 2], 5: [-2, 2, 4], 6: [1, 1, 2], 7: [2, 2, 4] },
  { 4: [0, 0, 0], 5: [0, 0, 0], 6: [0, 0, 0], 7: [0, 0, 0] },
  { 2: [2, -2, -1], 3: [3, -2, 0], 4: [1, -1, -1], 6: [-1, -1, -1] },
  { 2: [0, -3, 2], 3: [0, -4, 3], 5: [0, -2, 0], 7: [0, -2, 0] },
  { 0: [2, -4, 2], 1: [3, -5, 3], 2: [3, -4, 4], 3: [5, -3, 5], 9: [2, -5, 1], 11: [3, -5, 2] },
  {
    0: [5, -6, 3],
    1: [7, -6, 4],
    2: [6, -5, 5],
    3: [8, -4, 6],
    8: [5, -6, 2],
    9: [5, -6, 1],
    10: [8, -6, 3],
    11: [8, -6, 2],
  },
];

function add3(a, b) {
  const o = b || [0, 0, 0];
  return [a[0] + o[0], a[1] + o[1], a[2] + o[2]];
}

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

export function dummyFramesFor(name) {
  const base = skeletonBase(enemyTypeByName(name));
  return FRAME_OFFSETS.map((off) =>
    base.map((p, i) => {
      const o = off[i] || (i === 12 ? off[7] : null);
      const v = add3(p, o);
      return { x: clampVert(v[0]), y: clampVert(v[1]), z: clampVert(v[2]) };
    })
  );
}

export function createEnemy(name = "Grunt") {
  return {
    id: uid(),
    name,
    verts: 13,
    lines: TEMPLATE_LINES.map((p) => [p[0], p[1]]),
    frames: dummyFramesFor(name),
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
    });
    if (!KINDS[o.kind].fixed) {
      obj.sx = o.sx ?? obj.sx;
      obj.sy = o.sy ?? obj.sy;
      obj.sz = o.sz ?? obj.sz;
    }
    out.push(clampObject(obj));
  }
  return out;
}

function starterObjects() {
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
  return [roomA, roomB, door, crate];
}

export function createDefaultDocument() {
  const maps = {};
  for (const name of LEVEL_NAMES) maps[name] = emptyMap();
  maps.E1M1 = { objects: starterObjects() };
  return {
    version: 3,
    activeLevel: "E1M1",
    maps,
    enemies: createAllCreatures(),
  };
}

export function cloneDoc(doc) {
  return JSON.parse(JSON.stringify(doc));
}

export function normalizeDocument(raw) {
  const doc = createDefaultDocument();
  if (!raw || typeof raw !== "object") return doc;
  if (raw.maps && typeof raw.maps === "object") {
    for (const name of LEVEL_NAMES) {
      doc.maps[name] = { objects: parseObjects(raw.maps[name]?.objects) };
    }
  } else {
    doc.maps.E1M1 = { objects: parseObjects(raw.map?.objects || raw.objects) };
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
      const srcFrames = Array.isArray(e.frames) ? e.frames : [];
      const dummy = dummyFramesFor(enemy.name);
      enemy.frames = FRAME_NAMES.map((_, fi) => {
        const src = srcFrames[fi] || srcFrames[0] || dummy[fi];
        const verts = [];
        for (let i = 0; i < 13; i++) {
          const v = src[i] || dummy[fi][i];
          verts.push({ x: clampVert(v.x), y: clampVert(v.y), z: clampVert(v.z) });
        }
        return verts;
      });
      doc.enemies.push(enemy);
    }
    const have = new Set(doc.enemies.map((e) => e.name));
    for (const t of ENEMY_TYPES) {
      if (!have.has(t.name)) doc.enemies.push(createEnemy(t.name));
    }
  }
  if (!doc.enemies.length) doc.enemies = createAllCreatures();
  doc.version = 3;
  return doc;
}
