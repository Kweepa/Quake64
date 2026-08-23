const IDPO = 0x4f504449;
const ALIAS_VERSION = 6;
const ALIAS_SINGLE = 0;

export const ENEMY_MDL_PATHS = {
  Grunt: "progs/soldier.mdl",
  Knight: "progs/knight.mdl",
  Rottweiler: "progs/dog.mdl",
  Scrag: "progs/wizard.mdl",
  Ogre: "progs/ogre.mdl",
  Shambler: "progs/shambler.mdl",
  Chthon: "progs/boss.mdl",
};

function cstr(view, offset, len) {
  let s = "";
  for (let i = 0; i < len; i++) {
    const c = view.getUint8(offset + i);
    if (!c) break;
    s += String.fromCharCode(c);
  }
  return s;
}

function clipKey(name) {
  const k = name.replace(/\d+$/, "");
  return k || name;
}

/** Drop extra pain/death variants; keep first pain and first death. */
const EXTRA_PAIN_DEATH = /^pain[b-z]|^death[b-z]|^deathc$|^bdeath$/;

export function shouldKeepMdlClip(name) {
  return !EXTRA_PAIN_DEATH.test(name);
}

export function filterMdlClips(clips) {
  return (clips || []).filter((c) => shouldKeepMdlClip(c.name));
}

/** Clips named in `names`, in MDL order. Missing/undefined names → default kept set. */
export function selectMdlClips(mdl, names) {
  const clips = mdl?.clips || [];
  if (!clips.length) return [];
  if (!Array.isArray(names)) return filterMdlClips(clips);
  const want = new Set(names);
  return clips.filter((c) => want.has(c.name));
}

/** Global stick index → MDL frame index (same order as filterMdlClips). */
export function mdlFrameIndexAt(mdl, globalIndex) {
  const kept = filterMdlClips(mdl.clips);
  let i = 0;
  for (const clip of kept) {
    for (const fr of clip.frames) {
      if (i === globalIndex) return fr.index;
      i++;
    }
  }
  return kept[0]?.frames[0]?.index ?? 0;
}

function uniqueEdges(tris) {
  const seen = new Set();
  const edges = [];
  const add = (a, b) => {
    if (a === b) return;
    const lo = a < b ? a : b;
    const hi = a < b ? b : a;
    const key = lo + ":" + hi;
    if (seen.has(key)) return;
    seen.add(key);
    edges.push([lo, hi]);
  };
  for (const t of tris) {
    add(t[0], t[1]);
    add(t[1], t[2]);
    add(t[2], t[0]);
  }
  return edges;
}

function reader(buffer) {
  const view = new DataView(buffer);
  let o = 0;
  return {
    i32() {
      const v = view.getInt32(o, true);
      o += 4;
      return v;
    },
    f32() {
      const v = view.getFloat32(o, true);
      o += 4;
      return v;
    },
    vec3() {
      return [this.f32(), this.f32(), this.f32()];
    },
    skip(n) {
      o += n;
    },
    u8() {
      const v = view.getUint8(o);
      o += 1;
      return v;
    },
    name16() {
      const s = cstr(view, o, 16);
      o += 16;
      return s;
    },
    check(n, what) {
      if (o + n > buffer.byteLength) throw new Error(`MDL truncated (${what})`);
    },
  };
}

function skipSkins(r, numSkins, skinWidth, skinHeight) {
  const skinSize = skinWidth * skinHeight;
  if (skinSize < 0 || skinSize > 2_000_000) throw new Error("MDL skin size invalid");
  for (let i = 0; i < numSkins; i++) {
    r.check(4, "skin type");
    const typ = r.i32();
    if (typ === ALIAS_SINGLE) {
      r.check(skinSize, "skin");
      r.skip(skinSize);
    } else {
      r.check(4, "skin group");
      const n = r.i32();
      if (n < 0 || n > 256) throw new Error("MDL skin group too large");
      r.check(n * 4 + n * skinSize, "skin group");
      r.skip(n * 4);
      r.skip(n * skinSize);
    }
  }
}

function readSimpleFrame(r, numVerts) {
  r.check(8 + 16 + numVerts * 4, "frame");
  r.skip(8);
  const name = r.name16();
  const verts = new Uint8Array(numVerts * 3);
  for (let i = 0; i < numVerts; i++) {
    verts[i * 3] = r.u8();
    verts[i * 3 + 1] = r.u8();
    verts[i * 3 + 2] = r.u8();
    r.u8();
  }
  return { name, verts };
}

export function parseMdl(buffer) {
  const r = reader(buffer);
  r.check(84, "header");
  const ident = r.i32();
  if (ident !== IDPO) throw new Error("Not an IDPO MDL");
  const version = r.i32();
  if (version !== ALIAS_VERSION) throw new Error(`MDL version ${version}, expected 6`);
  const scale = r.vec3();
  const origin = r.vec3();
  r.f32();
  r.vec3();
  const numSkins = r.i32();
  const skinWidth = r.i32();
  const skinHeight = r.i32();
  const numVerts = r.i32();
  const numTris = r.i32();
  const numFrames = r.i32();
  r.i32();
  r.i32();
  r.f32();

  if (numVerts <= 0 || numVerts > 10000 || numTris <= 0 || numTris > 20000 || numFrames <= 0) {
    throw new Error("MDL has no geometry");
  }

  skipSkins(r, numSkins, skinWidth, skinHeight);

  r.check(numVerts * 12, "stverts");
  r.skip(numVerts * 12);

  const tris = [];
  r.check(numTris * 16, "tris");
  for (let i = 0; i < numTris; i++) {
    r.i32();
    tris.push([r.i32(), r.i32(), r.i32()]);
  }

  const frames = [];
  for (let i = 0; i < numFrames; i++) {
    r.check(4, "frame type");
    const typ = r.i32();
    if (typ === ALIAS_SINGLE) {
      frames.push(readSimpleFrame(r, numVerts));
    } else {
      r.check(4, "group count");
      const n = r.i32();
      if (n < 0 || n > 256) throw new Error("MDL frame group too large");
      r.check(8 + n * 4, "group header");
      r.skip(8);
      r.skip(n * 4);
      for (let j = 0; j < n; j++) frames.push(readSimpleFrame(r, numVerts));
    }
  }

  const clips = [];
  const byKey = new Map();
  for (let i = 0; i < frames.length; i++) {
    const key = clipKey(frames[i].name);
    let clip = byKey.get(key);
    if (!clip) {
      clip = { name: key, frames: [] };
      byKey.set(key, clip);
      clips.push(clip);
    }
    clip.frames.push({ name: frames[i].name, index: i });
  }

  return {
    numVerts,
    scale,
    origin,
    tris,
    edges: uniqueEdges(tris),
    frames,
    clips,
  };
}

/** Quake hull mins.z / modelgen $origin z — origin sits this far above the floor. */
const HULL_FLOOR = 24;

/** Quake +X forward / +Z up → editor +Z forward / +Y up. */
function quakeToEditor(qx, qy, qz) {
  return { x: -qy, y: qz, z: qx };
}

function decodeConverted(mdl, frameIndex) {
  const fr = mdl.frames[frameIndex];
  const [sx, sy, sz] = mdl.scale;
  const [ox, oy, oz] = mdl.origin;
  const packed = fr.verts;
  const out = new Array(mdl.numVerts);
  for (let i = 0; i < mdl.numVerts; i++) {
    const qx = packed[i * 3] * sx + ox;
    const qy = packed[i * 3 + 1] * sy + oy;
    const qz = packed[i * 3 + 2] * sz + oz;
    out[i] = quakeToEditor(qx, qy, qz);
  }
  return out;
}

export function mdlEditorVerts(mdl, frameIndex, scale) {
  const raw = decodeConverted(mdl, frameIndex);
  const n = Number(scale);
  const s = Number.isFinite(n) ? Math.max(0.1, Math.min(2, n)) : 0.7;
  return raw.map((v) => ({ x: v.x * s, y: (v.y + HULL_FLOOR) * s, z: v.z * s }));
}

/** Build stick poses + clip table from bound MDL clips (selected names, or default kept set). */
export function buildStickFramesFromMdl(mdl, rig, scale, restFrame, clampVert, clipNames) {
  const kept = selectMdlClips(mdl, clipNames);
  const frames = [];
  const clips = [];
  let start = 0;
  for (const clip of kept) {
    clips.push({ name: clip.name, start, len: clip.frames.length });
    for (const fr of clip.frames) {
      const verts = mdlEditorVerts(mdl, fr.index, scale);
      const avg = averageJointPositions(verts, rig.jointVerts);
      const pose = restFrame.map((v, i) => {
        if (avg[i]) {
          return {
            x: clampVert(Math.round(avg[i].x)),
            y: clampVert(Math.round(avg[i].y)),
            z: clampVert(Math.round(avg[i].z)),
          };
        }
        return { x: v.x, y: v.y, z: v.z };
      });
      frames.push(pose);
    }
    start += clip.frames.length;
  }
  return { frames, clips };
}

export function averageJointPositions(verts, jointVerts) {
  return jointVerts.map((indices) => {
    if (!indices || !indices.length) return null;
    let x = 0;
    let y = 0;
    let z = 0;
    let n = 0;
    for (const i of indices) {
      const v = verts[i];
      if (!v) continue;
      x += v.x;
      y += v.y;
      z += v.z;
      n++;
    }
    if (!n) return null;
    return { x: x / n, y: y / n, z: z / n };
  });
}

export function loadEnemyMdls(lumps) {
  const models = {};
  const missing = [];
  for (const [enemy, path] of Object.entries(ENEMY_MDL_PATHS)) {
    const buf = lumps.get(path.toLowerCase());
    if (!buf) {
      missing.push(enemy);
      continue;
    }
    try {
      models[enemy] = parseMdl(buf);
    } catch (err) {
      missing.push(enemy);
      console.warn(`Failed to parse ${path}:`, err);
    }
  }
  return { models, missing };
}

export const WEAPON_MDL_PATHS = {
  axe: "progs/v_axe.mdl",
  shot2: "progs/v_shot2.mdl",
  nail: "progs/v_nail.mdl",
  rock: "progs/v_rock.mdl",
};

export const WEAPON_SPRITE_W = 48;
export const WEAPON_SPRITE_H = 42;
export const WEAPON_FOV_X = 90;
export const WEAPON_VIEW_W = 320;
export const WEAPON_VIEW_H = 200;
export const WEAPON_NEAR = 0.05;

function calcFovY(fovXDeg, width, height) {
  const x = width / Math.tan((fovXDeg / 360) * Math.PI);
  return (Math.atan(height / x) * 360) / Math.PI;
}

const WEAPON_FOV_Y = calcFovY(WEAPON_FOV_X, WEAPON_VIEW_W, WEAPON_VIEW_H);
const WEAPON_XSCALE = WEAPON_VIEW_W * 0.5 / Math.tan((WEAPON_FOV_X * Math.PI) / 360);
const WEAPON_YSCALE = WEAPON_VIEW_H * 0.5 / Math.tan((WEAPON_FOV_Y * Math.PI) / 360);

export const QUAD_COPLANAR_DOT = 0.9;
export const QUAD_PLANE_REL = 0.15;

function edgeKey(a, b) {
  return a < b ? `${a}:${b}` : `${b}:${a}`;
}

function sub3(a, b) {
  return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };
}

function dot3(a, b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}

function cross3(a, b) {
  return { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x };
}

function len3v(v) {
  return Math.hypot(v.x, v.y, v.z);
}

function triEdges(t) {
  return [
    [t[0], t[1]],
    [t[1], t[2]],
    [t[2], t[0]],
  ];
}

function triFace(t) {
  return {
    tri: t,
    tris: [t],
    edges: triEdges(t),
  };
}

function quadFace(t0, t1, sharedKey) {
  const edges = [];
  for (const [a, b] of [...triEdges(t0), ...triEdges(t1)]) {
    if (edgeKey(a, b) === sharedKey) continue;
    edges.push([a, b]);
  }
  return { tri: t0, tris: [t0, t1], edges };
}

function apexOf(t, sa, sb) {
  for (const i of t) {
    if (i !== sa && i !== sb) return i;
  }
  return -1;
}

function triNormal(verts, t) {
  const a = verts[t[0]];
  const b = verts[t[1]];
  const c = verts[t[2]];
  if (!a || !b || !c) return null;
  const n = cross3(sub3(b, a), sub3(c, a));
  const l = len3v(n);
  if (l < 1e-12) return null;
  return { x: n.x / l, y: n.y / l, z: n.z / l, origin: a };
}

function triMeanEdge(verts, t) {
  const a = verts[t[0]];
  const b = verts[t[1]];
  const c = verts[t[2]];
  return (len3v(sub3(b, a)) + len3v(sub3(c, b)) + len3v(sub3(a, c))) / 3;
}

function unitDir(a, b) {
  const d = sub3(b, a);
  const l = len3v(d);
  if (l < 1e-12) return null;
  return { x: d.x / l, y: d.y / l, z: d.z / l };
}

/** Pair coplanar neighbor tris that share an MDL edge (drop that diagonal). */
export function mdlQuadEdges(tris, verts) {
  const n = tris.length;
  const quads = [];
  if (!n) return quads;
  if (!verts?.length) {
    for (const t of tris) quads.push(triFace(t));
    return quads;
  }

  const byEdge = new Map();
  for (let ti = 0; ti < n; ti++) {
    for (const [a, b] of triEdges(tris[ti])) {
      const k = edgeKey(a, b);
      let list = byEdge.get(k);
      if (!list) {
        list = [];
        byEdge.set(k, list);
      }
      list.push({ ti, a, b });
    }
  }

  const cands = [];
  for (const [k, list] of byEdge) {
    for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const i0 = list[i].ti;
        const i1 = list[j].ti;
        if (i0 === i1) continue;
        const scored = scoreNeighborTris(verts, tris[i0], tris[i1], list[i].a, list[i].b);
        if (!scored?.pass) continue;
        const sa = verts[list[i].a];
        const sb = verts[list[i].b];
        cands.push({
          i0,
          i1,
          k,
          score: scored.coplanarDot + 0.25 * scored.parallelMax,
          len: sa && sb ? len3v(sub3(sb, sa)) : 0,
        });
      }
    }
  }

  cands.sort((a, b) => b.len - a.len || b.score - a.score);
  const used = new Uint8Array(n);
  for (const c of cands) {
    if (used[c.i0] || used[c.i1]) continue;
    used[c.i0] = 1;
    used[c.i1] = 1;
    quads.push(quadFace(tris[c.i0], tris[c.i1], c.k));
  }
  for (let i = 0; i < n; i++) {
    if (!used[i]) quads.push(triFace(tris[i]));
  }
  return quads;
}

function quadConvex(ring, n) {
  let sign = 0;
  for (let i = 0; i < 4; i++) {
    const a = ring[i];
    const b = ring[(i + 1) % 4];
    const c = ring[(i + 2) % 4];
    const turn = dot3(n, cross3(sub3(b, a), sub3(c, b)));
    if (Math.abs(turn) < 1e-8) continue;
    const s = turn > 0 ? 1 : -1;
    if (sign === 0) sign = s;
    else if (s !== sign) return false;
  }
  return sign !== 0;
}

function sideSign(sa, sb, p, n) {
  return dot3(n, cross3(sub3(sb, sa), sub3(p, sa)));
}

function apexesOpposite(sa, sb, p0, p1, n) {
  return sideSign(sa, sb, p0, n) * sideSign(sa, sb, p1, n) < 0;
}

/** [sa, p0, sb, p1] is a bowtie if both apexes sit on the same side of sa–sb. */
function orderQuadRing(sa, p0, sb, p1, n) {
  const tries = [
    [sa, p0, sb, p1],
    [sa, p1, sb, p0],
    [sa, p0, p1, sb],
    [sa, p1, p0, sb],
  ];
  for (const ring of tries) {
    if (quadConvex(ring, n)) return ring;
  }
  return null;
}

function oppositeParallel(ring) {
  const d0 = unitDir(ring[0], ring[1]);
  const d1 = unitDir(ring[1], ring[2]);
  const d2 = unitDir(ring[2], ring[3]);
  const d3 = unitDir(ring[3], ring[0]);
  if (!d0 || !d1 || !d2 || !d3) return 0;
  return Math.max(Math.abs(dot3(d0, d2)), Math.abs(dot3(d1, d3)));
}

function pointsNormal(a, b, c) {
  return triNormal([a, b, c], [0, 1, 2]);
}

/** One triangle: unit normal used by the coplanar gate. */
export function inspectTriNormal(a, b, c) {
  const n = pointsNormal(a, b, c);
  if (!n) return null;
  return { x: n.x, y: n.y, z: n.z };
}

function scoreNeighborTris(verts, t0, t1, sa, sb) {
  const n0 = triNormal(verts, t0);
  let n1 = triNormal(verts, t1);
  if (!n0 || !n1) return null;
  let coplanarDot = dot3(n0, n1);
  if (coplanarDot < 0) {
    n1 = { x: -n1.x, y: -n1.y, z: -n1.z, origin: n1.origin };
    coplanarDot = -coplanarDot;
  }
  const p0 = apexOf(t0, sa, sb);
  const p1 = apexOf(t1, sa, sb);
  if (p0 < 0 || p1 < 0) return null;
  const mean = (triMeanEdge(verts, t0) + triMeanEdge(verts, t1)) * 0.5 || 1;
  const plane0 = Math.abs(dot3(n1, sub3(verts[p0], n1.origin))) / mean;
  const plane1 = Math.abs(dot3(n0, sub3(verts[p1], n0.origin))) / mean;
  const nAvg = { x: n0.x + n1.x, y: n0.y + n1.y, z: n0.z + n1.z };
  const nl = len3v(nAvg);
  if (nl < 1e-12) return null;
  nAvg.x /= nl;
  nAvg.y /= nl;
  nAvg.z /= nl;
  const va = verts[sa];
  const vb = verts[sb];
  const vp0 = verts[p0];
  const vp1 = verts[p1];
  const diagonal = apexesOpposite(va, vb, vp0, vp1, nAvg);
  const ring = orderQuadRing(va, vp0, vb, vp1, nAvg);
  const convex = !!ring;
  const parallelMax = ring ? oppositeParallel(ring) : 0;
  const planeRel = Math.max(plane0, plane1);
  return {
    coplanarDot,
    planeRel,
    convex,
    diagonal,
    parallelMax,
    shared: [sa, sb],
    pass:
      coplanarDot >= QUAD_COPLANAR_DOT &&
      planeRel < QUAD_PLANE_REL &&
      convex &&
      diagonal,
  };
}

function sharedEdgeIndices(t0, t1) {
  const s1 = new Set(t1);
  const shared = [];
  for (const i of t0) {
    if (s1.has(i)) shared.push(i);
  }
  return shared.length === 2 ? shared : null;
}

function triKey(t) {
  return [t[0], t[1], t[2]].sort((a, b) => a - b).join(":");
}

function quadsIncludePair(quads, t0, t1) {
  if (!quads?.length || !t0 || !t1) return false;
  const a = triKey(t0);
  const b = triKey(t1);
  for (const q of quads) {
    const ts = q.tris;
    if (!ts || ts.length !== 2) continue;
    const keys = [triKey(ts[0]), triKey(ts[1])];
    if (keys.includes(a) && keys.includes(b)) return true;
  }
  return false;
}

export function mdlEnsureQuads(mdl) {
  if (!mdl) return [];
  if (!mdl.quads) mdl.quads = mdlQuadEdges(mdl.tris, mdlQuakeVerts(mdl, 0));
  return mdl.quads;
}

/** Four selected indices: score the MDL triangle pair that uses them, if any. */
export function inspectQuadPair(tris, indices, verts, quads) {
  if (!tris?.length || !indices || indices.length !== 4 || !verts?.length) return null;
  const set = new Set(indices);
  if (set.size !== 4) return null;
  const hits = [];
  for (const t of tris) {
    if (t.every((i) => set.has(i))) hits.push(t);
  }
  for (let i = 0; i < hits.length; i++) {
    for (let j = i + 1; j < hits.length; j++) {
      const se = sharedEdgeIndices(hits[i], hits[j]);
      if (!se) continue;
      const union = new Set([...hits[i], ...hits[j]]);
      if (union.size !== 4) continue;
      const scored = scoreNeighborTris(verts, hits[i], hits[j], se[0], se[1]);
      if (!scored) return { noModelPair: true };
      scored.paired = quadsIncludePair(quads, hits[i], hits[j]);
      return scored;
    }
  }
  return { noModelPair: true };
}

/** Packed MDL verts in Quake model space (+X forward, +Y left, +Z up). */
export function mdlQuakeVerts(mdl, frameIndex) {
  const fr = mdl.frames[frameIndex];
  if (!fr) return [];
  const [sx, sy, sz] = mdl.scale;
  const [ox, oy, oz] = mdl.origin;
  const packed = fr.verts;
  const out = new Array(mdl.numVerts);
  for (let i = 0; i < mdl.numVerts; i++) {
    out[i] = {
      x: packed[i * 3] * sx + ox,
      y: packed[i * 3 + 1] * sy + oy,
      z: packed[i * 3 + 2] * sz + oz,
    };
  }
  return out;
}

/** Identity view-model: camera X=-Y, Y=+Z, Z=+X; FOV 90 on 320×200. */
export function projectViewVert(v) {
  const cx = -v.y;
  const cy = v.z;
  const cz = v.x;
  if (cz < WEAPON_NEAR) return { cx, cy, cz, ok: false, sx: 0, sy: 0 };
  return {
    cx,
    cy,
    cz,
    ok: true,
    sx: WEAPON_VIEW_W * 0.5 + WEAPON_XSCALE * (cx / cz),
    sy: WEAPON_VIEW_H * 0.5 - WEAPON_YSCALE * (cy / cz),
  };
}

export function viewFaceTowardCamera(p0, p1, p2) {
  if (!p0.ok || !p1.ok || !p2.ok) return false;
  const ax = p1.cx - p0.cx;
  const ay = p1.cy - p0.cy;
  const az = p1.cz - p0.cz;
  const bx = p2.cx - p0.cx;
  const by = p2.cy - p0.cy;
  const bz = p2.cz - p0.cz;
  const nx = ay * bz - az * by;
  const ny = az * bx - ax * bz;
  const nz = ax * by - ay * bx;
  return nx * p0.cx + ny * p0.cy + nz * p0.cz < 0;
}

export function toSpritePos(sx, sy, scale, pan) {
  return {
    x: scale * (sx - WEAPON_VIEW_W * 0.5) + WEAPON_SPRITE_W * 0.5 + (pan?.x || 0),
    y: scale * (sy - WEAPON_VIEW_H * 0.5) + WEAPON_SPRITE_H * 0.5 + (pan?.y || 0),
  };
}

export function defaultWeaponFrames(mdl, key) {
  if (!mdl?.frames?.length) return [0];
  if (key !== "axe") return [0];
  const out = [];
  const seen = new Set();
  const add = (i) => {
    const n = i | 0;
    if (n < 0 || n >= mdl.frames.length || seen.has(n)) return;
    seen.add(n);
    out.push(n);
  };
  add(0);
  for (const clip of mdl.clips || []) {
    if (/^axea/i.test(clip.name)) {
      for (const fr of clip.frames) add(fr.index);
    }
  }
  return out.length ? out : [0];
}

export function resolveWeaponFrames(item, mdl, key) {
  if (Array.isArray(item?.frames)) {
    const max = mdl?.frames?.length ?? 4096;
    const seen = new Set();
    const out = [];
    for (const f of item.frames) {
      const n = f | 0;
      if (n < 0 || n >= max || seen.has(n)) continue;
      seen.add(n);
      out.push(n);
    }
    return out;
  }
  return defaultWeaponFrames(mdl, key);
}

export function loadWeaponMdls(lumps) {
  const models = {};
  const missing = [];
  for (const [key, path] of Object.entries(WEAPON_MDL_PATHS)) {
    const buf = lumps.get(path.toLowerCase());
    if (!buf) {
      missing.push(key);
      continue;
    }
    try {
      models[key] = parseMdl(buf);
    } catch (err) {
      missing.push(key);
      console.warn(`Failed to parse ${path}:`, err);
    }
  }
  return { models, missing };
}

const ZBUF_MAX = 256;
const VIEW_Z_SCALE = 8;
const VIEW_ZBUF_MAX = 768;
const TRI_ID_EMPTY = 0xffff;
const Z_EDGE_SLACK = 1.02;

function spriteAabb(pts) {
  let minX = 0;
  let minY = 0;
  let maxX = WEAPON_SPRITE_W;
  let maxY = WEAPON_SPRITE_H;
  for (const p of pts) {
    if (p.x < minX) minX = p.x;
    if (p.y < minY) minY = p.y;
    if (p.x > maxX) maxX = p.x;
    if (p.y > maxY) maxY = p.y;
  }
  return {
    minX: Math.floor(minX) - 1,
    minY: Math.floor(minY) - 1,
    maxX: Math.ceil(maxX) + 1,
    maxY: Math.ceil(maxY) + 1,
  };
}

function scaledVert(p, originX, originY, scale) {
  return {
    x: (p.x - originX) * scale,
    y: (p.y - originY) * scale,
    z: p.z,
    iz: p.iz,
  };
}

function makeZctx(frontTris, aabb, scale, maxDim) {
  const spanX = Math.max(1, aabb.maxX - aabb.minX);
  const spanY = Math.max(1, aabb.maxY - aabb.minY);
  let s = Math.min(scale, maxDim / spanX, maxDim / spanY);
  if (!(s > 0)) s = 1;
  const bw = Math.max(1, Math.ceil(spanX * s));
  const bh = Math.max(1, Math.ceil(spanY * s));
  const zbuf = new Float32Array(bw * bh);
  zbuf.fill(1e12);
  const triId = new Uint16Array(bw * bh);
  triId.fill(TRI_ID_EMPTY);
  for (const ft of frontTris) {
    fillTriZ(
      zbuf,
      triId,
      ft.ti,
      0,
      0,
      bw,
      bh,
      scaledVert(ft.a, aabb.minX, aabb.minY, s),
      scaledVert(ft.b, aabb.minX, aabb.minY, s),
      scaledVert(ft.c, aabb.minX, aabb.minY, s)
    );
  }
  return { zbuf, triId, minX: 0, minY: 0, bw, bh, originX: aabb.minX, originY: aabb.minY, scale: s };
}

function spriteVert(p, scale, pan) {
  const s = toSpritePos(p.sx, p.sy, scale, pan);
  return { x: s.x, y: s.y, z: p.cz, iz: 1 / p.cz };
}

function faceToward(proj, tri) {
  return viewFaceTowardCamera(proj[tri[0]], proj[tri[1]], proj[tri[2]]);
}

function trisSharingEdge(tris, proj, ia, ib) {
  const adj = new Set();
  for (let ti = 0; ti < tris.length; ti++) {
    const t = tris[ti];
    if (t[0] !== ia && t[1] !== ia && t[2] !== ia) continue;
    if (t[0] !== ib && t[1] !== ib && t[2] !== ib) continue;
    if (!faceToward(proj, t)) continue;
    adj.add(ti);
  }
  return adj;
}

function fillTriZ(zbuf, triId, ti, ox, oy, bw, bh, a, b, c) {
  const minX = Math.max(0, Math.floor(Math.min(a.x, b.x, c.x) - ox));
  const maxX = Math.min(bw - 1, Math.ceil(Math.max(a.x, b.x, c.x) - ox));
  const minY = Math.max(0, Math.floor(Math.min(a.y, b.y, c.y) - oy));
  const maxY = Math.min(bh - 1, Math.ceil(Math.max(a.y, b.y, c.y) - oy));
  if (minX > maxX || minY > maxY) return;
  const denom = (b.y - c.y) * (a.x - c.x) + (c.x - b.x) * (a.y - c.y);
  if (Math.abs(denom) < 1e-8) return;
  const inv = 1 / denom;
  for (let y = minY; y <= maxY; y++) {
    const py = y + oy + 0.5;
    for (let x = minX; x <= maxX; x++) {
      const px = x + ox + 0.5;
      const w0 = ((b.y - c.y) * (px - c.x) + (c.x - b.x) * (py - c.y)) * inv;
      const w1 = ((c.y - a.y) * (px - c.x) + (a.x - c.x) * (py - c.y)) * inv;
      const w2 = 1 - w0 - w1;
      if (w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4) continue;
      const iz = w0 * a.iz + w1 * b.iz + w2 * c.iz;
      if (iz <= 0) continue;
      const z = 1 / iz;
      const i = y * bw + x;
      if (z < zbuf[i]) {
        zbuf[i] = z;
        triId[i] = ti;
      }
    }
  }
}

function segmentT(a, b, px, py) {
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  const len2 = dx * dx + dy * dy;
  if (len2 < 1e-12) return 0;
  let t = ((px - a.x) * dx + (py - a.y) * dy) / len2;
  if (t < 0) return 0;
  if (t > 1) return 1;
  return t;
}

function lerpDepth(a, b, t) {
  const iz = a.iz * (1 - t) + b.iz * t;
  return iz > 0 ? 1 / iz : 1e9;
}

function edgePixelVisible(zctx, x, y, a, b, adj) {
  const bx = Math.floor(x - zctx.minX);
  const by = Math.floor(y - zctx.minY);
  if (bx < 0 || by < 0 || bx >= zctx.bw || by >= zctx.bh) return false;
  const i = by * zctx.bw + bx;
  const owner = zctx.triId[i];
  if (owner === TRI_ID_EMPTY) return true;
  if (adj.has(owner)) return true;
  const cx = bx + zctx.minX + 0.5;
  const cy = by + zctx.minY + 0.5;
  const z = lerpDepth(a, b, segmentT(a, b, cx, cy));
  return z <= zctx.zbuf[i] * Z_EDGE_SLACK;
}

function toZspace(p, zctx) {
  return scaledVert(p, zctx.originX, zctx.originY, zctx.scale);
}

function fromZspace(x, y, zctx) {
  return {
    x: x / zctx.scale + zctx.originX,
    y: y / zctx.scale + zctx.originY,
  };
}

/** Visible bits of an edge in projected sprite space (no pixel snapping). */
function edgeRuns(zctx, a, b, adj) {
  const ha = toZspace(a, zctx);
  const hb = toZspace(b, zctx);
  const dist = Math.hypot(hb.x - ha.x, hb.y - ha.y);
  const n = Math.max(2, Math.ceil(dist * 2));
  const runs = [];
  let run = null;
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const x = ha.x + (hb.x - ha.x) * t;
    const y = ha.y + (hb.y - ha.y) * t;
    if (edgePixelVisible(zctx, x, y, ha, hb, adj)) {
      const p = fromZspace(x, y, zctx);
      if (!run) run = { ax: p.x, ay: p.y, bx: p.x, by: p.y };
      else {
        run.bx = p.x;
        run.by = p.y;
      }
    } else if (run) {
      runs.push(run);
      run = null;
    }
  }
  if (run) runs.push(run);
  return runs;
}

function leftToRight(a, b) {
  if (a.x < b.x || (a.x === b.x && a.y <= b.y)) return [a, b];
  return [b, a];
}

function plotSpritePixel(pixels, x, y, zctx, adj, za, zb) {
  if (x < 0 || y < 0 || x >= WEAPON_SPRITE_W || y >= WEAPON_SPRITE_H) return;
  if (zctx) {
    const p = toZspace({ x: x + 0.5, y: y + 0.5, iz: 0 }, zctx);
    if (!edgePixelVisible(zctx, p.x, p.y, za, zb, adj)) return;
  }
  pixels[y * WEAPON_SPRITE_W + x] = 1;
}

/** Thin 8-connected Bresenham: one pixel per major-axis step, no corner elbows. */
function plotSpriteLine(pixels, a, b, zctx, adj) {
  [a, b] = leftToRight(a, b);
  const za = zctx ? toZspace(a, zctx) : null;
  const zb = zctx ? toZspace(b, zctx) : null;
  let x = Math.round(a.x);
  let y = Math.round(a.y);
  const xEnd = Math.round(b.x);
  const yEnd = Math.round(b.y);
  const dx = Math.abs(xEnd - x);
  const dy = Math.abs(yEnd - y);
  const sx = x < xEnd ? 1 : -1;
  const sy = y < yEnd ? 1 : -1;
  if (dx >= dy) {
    let err = 2 * dy - dx;
    for (;;) {
      plotSpritePixel(pixels, x, y, zctx, adj, za, zb);
      if (x === xEnd) break;
      if (err >= 0) {
        y += sy;
        err -= 2 * dx;
      }
      err += 2 * dy;
      x += sx;
    }
  } else {
    let err = 2 * dx - dy;
    for (;;) {
      plotSpritePixel(pixels, x, y, zctx, adj, za, zb);
      if (y === yEnd) break;
      if (err >= 0) {
        x += sx;
        err -= 2 * dy;
      }
      err += 2 * dx;
      y += sy;
    }
  }
}

function visibleWeaponMesh(mdl, frameIndex, scale, pan) {
  const verts = mdlQuakeVerts(mdl, frameIndex);
  const proj = verts.map(projectViewVert);
  const quads = mdlEnsureQuads(mdl);
  const pts = [];
  const frontTris = [];
  const frontEdges = [];
  const seenEdge = new Set();
  let clipped = false;

  for (let ti = 0; ti < mdl.tris.length; ti++) {
    const t = mdl.tris[ti];
    if (!faceToward(proj, t)) continue;
    const a = proj[t[0]];
    const b = proj[t[1]];
    const c = proj[t[2]];
    if (!a.ok || !b.ok || !c.ok) continue;
    const pa = spriteVert(a, scale, pan);
    const pb = spriteVert(b, scale, pan);
    const pc = spriteVert(c, scale, pan);
    frontTris.push({ a: pa, b: pb, c: pc, ti });
    pts.push(pa, pb, pc);
  }

  for (const q of quads) {
    const tris = q.tris || [q.tri];
    if (!tris.some((t) => faceToward(proj, t))) continue;
    for (const [ia, ib] of q.edges) {
      const a = proj[ia];
      const b = proj[ib];
      if (!a?.ok || !b?.ok) {
        clipped = true;
        continue;
      }
      const k = edgeKey(ia, ib);
      if (seenEdge.has(k)) continue;
      seenEdge.add(k);
      const pa = spriteVert(a, scale, pan);
      const pb = spriteVert(b, scale, pan);
      const adj = trisSharingEdge(mdl.tris, proj, ia, ib);
      const [la, lb] = leftToRight(pa, pb);
      frontEdges.push({ a: la, b: lb, adj });
      pts.push(pa, pb);
      if (
        pa.x < 0 ||
        pa.y < 0 ||
        pa.x >= WEAPON_SPRITE_W ||
        pa.y >= WEAPON_SPRITE_H ||
        pb.x < 0 ||
        pb.y < 0 ||
        pb.x >= WEAPON_SPRITE_W ||
        pb.y >= WEAPON_SPRITE_H
      ) {
        clipped = true;
      }
    }
  }

  const segs = [];
  const pixels = new Uint8Array(WEAPON_SPRITE_W * WEAPON_SPRITE_H);
  const viewAabb = spriteAabb(pts);
  const zView = makeZctx(frontTris, viewAabb, VIEW_Z_SCALE, VIEW_ZBUF_MAX);
  const zBake = makeZctx(frontTris, { minX: 0, minY: 0, maxX: WEAPON_SPRITE_W, maxY: WEAPON_SPRITE_H }, 1, ZBUF_MAX);
  for (const e of frontEdges) {
    for (const run of edgeRuns(zView, e.a, e.b, e.adj)) segs.push(run);
  }
  for (const e of frontEdges) plotSpriteLine(pixels, e.a, e.b, zBake, e.adj);

  return { segs, pixels, clipped };
}

export function projectedWeaponEdges(mdl, frameIndex, scale, pan) {
  const { segs, clipped } = visibleWeaponMesh(mdl, frameIndex, scale, pan);
  return { segs, clipped };
}

export function rasterWeaponFrame(mdl, frameIndex, scale, pan) {
  return visibleWeaponMesh(mdl, frameIndex, scale, pan);
}
