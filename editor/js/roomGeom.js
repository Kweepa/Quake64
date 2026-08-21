/** Tetromino room geometry: canonical UV footprint, 90° axis rots, hull + colliders. */

export const ROOM_SHAPES = ["box", "T", "L", "S"];

export function clampQuarter(n) {
  const r = n | 0;
  if (!Number.isFinite(r)) return 0;
  return ((r % 4) + 4) % 4;
}

export function clampRoomShape(s) {
  return ROOM_SHAPES.includes(s) ? s : "box";
}

function rot90(p, axis) {
  if (axis === 0) return { x: p.x, y: -p.z, z: p.y };
  if (axis === 1) return { x: p.z, y: p.y, z: -p.x };
  return { x: -p.y, y: p.x, z: p.z };
}

function applyRots(p, rx, ry, rz) {
  let q = p;
  for (let i = 0; i < rx; i++) q = rot90(q, 0);
  for (let i = 0; i < ry; i++) q = rot90(q, 1);
  for (let i = 0; i < rz; i++) q = rot90(q, 2);
  return q;
}

export function roomBasis(room) {
  const rx = clampQuarter(room.rx);
  const ry = clampQuarter(room.ry);
  const rz = clampQuarter(room.rz);
  const u = applyRots({ x: 1, y: 0, z: 0 }, rx, ry, rz);
  const w = applyRots({ x: 0, y: 1, z: 0 }, rx, ry, rz);
  const v = applyRots({ x: 0, y: 0, z: 1 }, rx, ry, rz);
  const sizeOn = (hat) => {
    if (hat.x) return room.sx | 0;
    if (hat.y) return room.sy | 0;
    return room.sz | 0;
  };
  return {
    u,
    w,
    v,
    uSize: sizeOn(u),
    wSize: sizeOn(w),
    vSize: sizeOn(v),
    rx,
    ry,
    rz,
  };
}

function hatAxis(hat) {
  if (hat.x) return "x";
  if (hat.y) return "y";
  return "z";
}

function hatSign(hat) {
  return hat.x + hat.y + hat.z;
}

function localToWorld(room, u, w, v, basis) {
  const pos = { x: room.x | 0, y: room.y | 0, z: room.z | 0 };
  const add = (hat, t, tSize) => {
    const coord = hatSign(hat) > 0 ? t : tSize - t;
    if (hat.x) pos.x += coord;
    else if (hat.y) pos.y += coord;
    else pos.z += coord;
  };
  add(basis.u, u, basis.uSize);
  add(basis.w, w, basis.wSize);
  add(basis.v, v, basis.vSize);
  return pos;
}

function uvwBoxToWorld(room, box, basis) {
  const xs = [];
  const ys = [];
  const zs = [];
  for (const u of [box.u, box.u + box.su]) {
    for (const w of [0, basis.wSize]) {
      for (const v of [box.v, box.v + box.sv]) {
        const p = localToWorld(room, u, w, v, basis);
        xs.push(p.x);
        ys.push(p.y);
        zs.push(p.z);
      }
    }
  }
  const x0 = Math.min(...xs);
  const y0 = Math.min(...ys);
  const z0 = Math.min(...zs);
  return {
    x: x0,
    y: y0,
    z: z0,
    sx: Math.max(1, Math.max(...xs) - x0),
    sy: Math.max(1, Math.max(...ys) - y0),
    sz: Math.max(1, Math.max(...zs) - z0),
  };
}

export function defaultRoomSplits(shape, uSize, vSize) {
  const u = Math.max(1, uSize | 0);
  const v = Math.max(1, vSize | 0);
  if (shape === "L") {
    return {
      cutU: Math.max(1, Math.min(u - 1, u >> 1)),
      cutV: Math.max(1, Math.min(v - 1, v >> 1)),
    };
  }
  if (shape === "T") {
    const stemW = Math.max(1, Math.min(Math.max(1, u - 2), Math.max(1, u >> 2)));
    const stemPos = Math.max(1, Math.min(u - stemW - 1, (u - stemW) >> 1));
    const barD = Math.max(1, Math.min(v - 1, Math.max(1, v >> 2)));
    return { stemW, stemPos, barD };
  }
  if (shape === "S") {
    const maxShift = Math.max(1, Math.floor((u - 1) / 2));
    const shift = Math.max(1, Math.min(maxShift, Math.max(1, u >> 2)));
    const mid = Math.max(1, Math.min(v - 1, v >> 1));
    return { shift, mid };
  }
  return {};
}

export function clampRoomSplits(room) {
  const shape = clampRoomShape(room.shape);
  room.shape = shape;
  room.flip = !!room.flip;
  room.rx = clampQuarter(room.rx);
  room.ry = clampQuarter(room.ry);
  room.rz = clampQuarter(room.rz);
  const basis = roomBasis(room);
  let { uSize, vSize } = basis;
  if (shape === "L") {
    if (uSize < 2) {
      bumpAxis(room, basis.u, 2);
      uSize = 2;
    }
    if (vSize < 2) {
      bumpAxis(room, basis.v, 2);
      vSize = 2;
    }
    const d = defaultRoomSplits("L", uSize, vSize);
    room.cutU = clampInt(room.cutU, 1, uSize - 1, d.cutU);
    room.cutV = clampInt(room.cutV, 1, vSize - 1, d.cutV);
  } else if (shape === "T") {
    if (uSize < 3) {
      bumpAxis(room, basis.u, 3);
      uSize = 3;
    }
    if (vSize < 2) {
      bumpAxis(room, basis.v, 2);
      vSize = 2;
    }
    const d = defaultRoomSplits("T", uSize, vSize);
    room.stemW = clampInt(room.stemW, 1, uSize - 2, d.stemW);
    room.stemPos = clampInt(room.stemPos, 1, uSize - room.stemW - 1, d.stemPos);
    room.barD = clampInt(room.barD, 1, vSize - 1, d.barD);
  } else if (shape === "S") {
    if (uSize < 3) {
      bumpAxis(room, basis.u, 3);
      uSize = 3;
    }
    if (vSize < 2) {
      bumpAxis(room, basis.v, 2);
      vSize = 2;
    }
    const maxShift = Math.max(1, Math.floor((uSize - 1) / 2));
    const d = defaultRoomSplits("S", uSize, vSize);
    room.shift = clampInt(room.shift, 1, maxShift, d.shift);
    room.mid = clampInt(room.mid, 1, vSize - 1, d.mid);
  }
  return room;
}

function clampInt(n, lo, hi, fallback) {
  if (n == null || n === "" || !Number.isFinite(Number(n))) return fallback;
  const x = n | 0;
  if (x === 0 && lo >= 1) return fallback;
  return Math.max(lo, Math.min(hi, x));
}

function bumpAxis(room, hat, minSize) {
  const a = hatAxis(hat);
  const key = a === "x" ? "sx" : a === "y" ? "sy" : "sz";
  if ((room[key] | 0) < minSize) room[key] = minSize;
}

export function applyRoomShape(room, shape) {
  room.shape = clampRoomShape(shape);
  const b = roomBasis(room);
  const d = defaultRoomSplits(room.shape, b.uSize, b.vSize);
  Object.assign(room, d);
  return clampRoomSplits(room);
}

function coordAlongHat(room, t, hat, tSize) {
  const min = room[hatAxis(hat)] | 0;
  return hatSign(hat) > 0 ? min + t : min + tSize - t;
}

function tAlongHat(room, world, hat, tSize) {
  const min = room[hatAxis(hat)] | 0;
  return hatSign(hat) > 0 ? world - min : min + tSize - world;
}

function uvEndMoved(orig, room, hat) {
  const axis = hatAxis(hat);
  const sizeKey = axis === "x" ? "sx" : axis === "y" ? "sy" : "sz";
  const oldMin = orig[axis] | 0;
  const newMin = room[axis] | 0;
  const oldMax = oldMin + (orig[sizeKey] | 0);
  const newMax = newMin + (room[sizeKey] | 0);
  const minMoved = newMin !== oldMin;
  const maxMoved = newMax !== oldMax;
  if (hatSign(hat) > 0) return { minusMoved: minMoved, plusMoved: maxMoved };
  return { minusMoved: maxMoved, plusMoved: minMoved };
}

/** Keep inner walls in world space when the AABB is resized from a face/corner. */
export function preserveRoomSplits(room, orig) {
  const shape = clampRoomShape(room.shape);
  if (shape === "box" || !orig) return clampRoomSplits(room);
  const basis = roomBasis(orig);
  const newBasis = roomBasis(room);
  const oldU = basis.uSize;
  const oldV = basis.vSize;
  const newU = newBasis.uSize;
  const newV = newBasis.vSize;
  const mapU = (t) => Math.round(tAlongHat(room, coordAlongHat(orig, t, basis.u, oldU), newBasis.u, newU));
  const mapV = (t) => Math.round(tAlongHat(room, coordAlongHat(orig, t, basis.v, oldV), newBasis.v, newV));

  if (shape === "L") {
    const uInner = orig.flip ? orig.cutU | 0 : oldU - (orig.cutU | 0);
    const mapped = mapU(uInner);
    room.cutU = orig.flip ? mapped : newU - mapped;
    room.cutV = newV - mapV(oldV - (orig.cutV | 0));
  } else if (shape === "T") {
    let p0 = orig.stemPos | 0;
    let p1 = p0 + (orig.stemW | 0);
    if (orig.flip) {
      p0 = oldU - (orig.stemPos | 0) - (orig.stemW | 0);
      p1 = oldU - (orig.stemPos | 0);
    }
    let n0 = mapU(p0);
    let n1 = mapU(p1);
    if (n1 < n0) {
      const t = n0;
      n0 = n1;
      n1 = t;
    }
    room.stemW = n1 - n0;
    room.stemPos = orig.flip ? newU - n1 : n0;
    room.barD = newV - mapV(oldV - (orig.barD | 0));
  } else if (shape === "S") {
    const s0 = orig.shift | 0;
    const from0 = mapU(s0);
    const from1 = newU - mapU(oldU - s0);
    if (from0 === from1) {
      room.shift = from0;
    } else {
      const u = uvEndMoved(orig, room, basis.u);
      if (u.plusMoved && !u.minusMoved) room.shift = from0;
      else if (u.minusMoved && !u.plusMoved) room.shift = from1;
      else room.shift = Math.round((from0 + from1) / 2);
    }
    room.mid = mapV(orig.mid | 0);
  }
  return clampRoomSplits(room);
}

function localFootprint(room, basis) {
  const shape = clampRoomShape(room.shape);
  const uSize = basis.uSize;
  const vSize = basis.vSize;
  const flip = !!room.flip;
  const mirrorU = (box) =>
    flip ? { u: uSize - box.u - box.su, v: box.v, su: box.su, sv: box.sv } : box;

  if (shape === "box") {
    return [{ u: 0, v: 0, su: uSize, sv: vSize }];
  }
  if (shape === "L") {
    const cutU = room.cutU | 0;
    const cutV = room.cutV | 0;
    return [
      mirrorU({ u: 0, v: 0, su: uSize, sv: vSize - cutV }),
      mirrorU({ u: 0, v: vSize - cutV, su: uSize - cutU, sv: cutV }),
    ];
  }
  if (shape === "T") {
    const stemW = room.stemW | 0;
    const stemPos = room.stemPos | 0;
    const barD = room.barD | 0;
    return [
      mirrorU({ u: 0, v: vSize - barD, su: uSize, sv: barD }),
      mirrorU({ u: stemPos, v: 0, su: stemW, sv: vSize - barD }),
    ];
  }
  if (shape === "S") {
    const shift = room.shift | 0;
    const mid = room.mid | 0;
    if (flip) {
      return [
        { u: shift, v: mid, su: uSize - shift, sv: vSize - mid },
        { u: 0, v: 0, su: uSize - shift, sv: mid },
      ];
    }
    return [
      { u: 0, v: mid, su: uSize - shift, sv: vSize - mid },
      { u: shift, v: 0, su: uSize - shift, sv: mid },
    ];
  }
  return [{ u: 0, v: 0, su: uSize, sv: vSize }];
}

function aabbFaces(box) {
  const x0 = box.x;
  const y0 = box.y;
  const z0 = box.z;
  const x1 = box.x + box.sx;
  const y1 = box.y + box.sy;
  const z1 = box.z + box.sz;
  return [
    { axis: "x", sign: -1, plane: x0, a0: y0, a1: y1, b0: z0, b1: z1, faceId: "-x" },
    { axis: "x", sign: 1, plane: x1, a0: y0, a1: y1, b0: z0, b1: z1, faceId: "+x" },
    { axis: "y", sign: -1, plane: y0, a0: x0, a1: x1, b0: z0, b1: z1, faceId: "-y" },
    { axis: "y", sign: 1, plane: y1, a0: x0, a1: x1, b0: z0, b1: z1, faceId: "+y" },
    { axis: "z", sign: -1, plane: z0, a0: x0, a1: x1, b0: y0, b1: y1, faceId: "-z" },
    { axis: "z", sign: 1, plane: z1, a0: x0, a1: x1, b0: y0, b1: y1, faceId: "+z" },
  ];
}

function planeTouches(box, axis, plane) {
  const o0 = box[axis];
  const o1 = box[axis] + box["s" + axis];
  return o0 <= plane && o1 >= plane;
}

function otherOnFace(other, face) {
  if (!planeTouches(other, face.axis, face.plane)) return null;
  let a0;
  let a1;
  let b0;
  let b1;
  if (face.axis === "x") {
    a0 = other.y;
    a1 = other.y + other.sy;
    b0 = other.z;
    b1 = other.z + other.sz;
  } else if (face.axis === "y") {
    a0 = other.x;
    a1 = other.x + other.sx;
    b0 = other.z;
    b1 = other.z + other.sz;
  } else {
    a0 = other.x;
    a1 = other.x + other.sx;
    b0 = other.y;
    b1 = other.y + other.sy;
  }
  return { a0, a1, b0, b1 };
}

function subtractRect(r, c) {
  const ia0 = Math.max(r.a0, c.a0);
  const ia1 = Math.min(r.a1, c.a1);
  const ib0 = Math.max(r.b0, c.b0);
  const ib1 = Math.min(r.b1, c.b1);
  if (ia0 >= ia1 || ib0 >= ib1) return [r];
  const out = [];
  if (r.a0 < ia0) out.push({ a0: r.a0, a1: ia0, b0: r.b0, b1: r.b1 });
  if (ia1 < r.a1) out.push({ a0: ia1, a1: r.a1, b0: r.b0, b1: r.b1 });
  if (r.b0 < ib0) out.push({ a0: ia0, a1: ia1, b0: r.b0, b1: ib0 });
  if (ib1 < r.b1) out.push({ a0: ia0, a1: ia1, b0: ib1, b1: r.b1 });
  return out.filter((q) => q.a1 > q.a0 && q.b1 > q.b0);
}

function composePoint(face, a, b) {
  if (face.axis === "x") return { x: face.plane, y: a, z: b };
  if (face.axis === "y") return { x: a, y: face.plane, z: b };
  return { x: a, y: b, z: face.plane };
}

const FACE_BIT = {
  "-x": 0x01,
  "+x": 0x02,
  "-y": 0x04,
  "+y": 0x08,
  "-z": 0x10,
  "+z": 0x20,
};

function outerFaceBits(outer, a, b) {
  let bits = 0;
  const on = (axis, plane, bit) => {
    if (a[axis] === plane && b[axis] === plane) bits |= bit;
  };
  on("x", outer.x, 0x01);
  on("x", outer.x + outer.sx, 0x02);
  on("y", outer.y, 0x04);
  on("y", outer.y + outer.sy, 0x08);
  on("z", outer.z, 0x10);
  on("z", outer.z + outer.sz, 0x20);
  return bits;
}

function weldKey(p) {
  return `${p.x},${p.y},${p.z}`;
}

function vertOnOpenSeg(a, b, p) {
  if (a.x === b.x && a.y === b.y && a.z !== b.z && p.x === a.x && p.y === a.y) {
    return p.z > Math.min(a.z, b.z) && p.z < Math.max(a.z, b.z);
  }
  if (a.x === b.x && a.z === b.z && a.y !== b.y && p.x === a.x && p.z === a.z) {
    return p.y > Math.min(a.y, b.y) && p.y < Math.max(a.y, b.y);
  }
  if (a.y === b.y && a.z === b.z && a.x !== b.x && p.y === a.y && p.z === a.z) {
    return p.x > Math.min(a.x, b.x) && p.x < Math.max(a.x, b.x);
  }
  return false;
}

function faceContainsPoint(f, p) {
  if (f.axis === "x") {
    if (p.x !== f.plane) return false;
    return p.y >= f.a0 && p.y <= f.a1 && p.z >= f.b0 && p.z <= f.b1;
  }
  if (f.axis === "y") {
    if (p.y !== f.plane) return false;
    return p.x >= f.a0 && p.x <= f.a1 && p.z >= f.b0 && p.z <= f.b1;
  }
  if (p.z !== f.plane) return false;
  return p.x >= f.a0 && p.x <= f.a1 && p.y >= f.b0 && p.y <= f.b1;
}

function inPlanePerp(axis, va, vb) {
  if (axis === "y") return va.x !== vb.x ? "z" : "x";
  if (axis === "x") return va.y !== vb.y ? "z" : "y";
  return va.x !== vb.x ? "y" : "x";
}

function buriedOnPlane(va, vb, faces) {
  if (!faces.length) return false;
  const axis = faces[0].axis;
  const mid = {
    x: (va.x + vb.x) / 2,
    y: (va.y + vb.y) / 2,
    z: (va.z + vb.z) / 2,
  };
  const perp = inPlanePerp(axis, va, vb);
  const inside = (p) => faces.some((f) => faceContainsPoint(f, p));
  const a = { ...mid, [perp]: mid[perp] - 0.5 };
  const b = { ...mid, [perp]: mid[perp] + 0.5 };
  return inside(a) && inside(b);
}

function unionHull(colliders, outer) {
  const hullFaces = [];
  for (let i = 0; i < colliders.length; i++) {
    const box = colliders[i];
    for (const face of aabbFaces(box)) {
      let pieces = [{ a0: face.a0, a1: face.a1, b0: face.b0, b1: face.b1 }];
      for (let j = 0; j < colliders.length; j++) {
        if (i === j) continue;
        const clip = otherOnFace(colliders[j], face);
        if (!clip) continue;
        pieces = pieces.flatMap((p) => subtractRect(p, clip));
      }
      for (const p of pieces) {
        hullFaces.push({
          axis: face.axis,
          sign: face.sign,
          plane: face.plane,
          faceId: face.faceId,
          a0: p.a0,
          a1: p.a1,
          b0: p.b0,
          b1: p.b1,
          corners: [
            composePoint(face, p.a0, p.b0),
            composePoint(face, p.a1, p.b0),
            composePoint(face, p.a1, p.b1),
            composePoint(face, p.a0, p.b1),
          ],
        });
      }
    }
  }

  const vertMap = new Map();
  const verts = [];
  const addVert = (p) => {
    const k = weldKey(p);
    if (vertMap.has(k)) return vertMap.get(k);
    const i = verts.length;
    verts.push({ x: p.x, y: p.y, z: p.z });
    vertMap.set(k, i);
    return i;
  };

  const raw = [];
  for (const f of hullFaces) {
    const ids = f.corners.map(addVert);
    raw.push([ids[0], ids[1]], [ids[1], ids[2]], [ids[2], ids[3]], [ids[3], ids[0]]);
    f.center = {
      x: (f.corners[0].x + f.corners[2].x) / 2,
      y: (f.corners[0].y + f.corners[2].y) / 2,
      z: (f.corners[0].z + f.corners[2].z) / 2,
    };
  }

  const atomic = new Map();
  const addAtomic = (ia, ib) => {
    if (ia === ib) return;
    const a = Math.min(ia, ib);
    const b = Math.max(ia, ib);
    atomic.set(`${a}-${b}`, [a, b]);
  };
  for (const [ia, ib] of raw) {
    const va = verts[ia];
    const vb = verts[ib];
    const hits = [];
    for (let i = 0; i < verts.length; i++) {
      if (i === ia || i === ib) continue;
      if (vertOnOpenSeg(va, vb, verts[i])) hits.push(i);
    }
    hits.sort((i, j) => {
      const da = (verts[i].x - va.x) ** 2 + (verts[i].y - va.y) ** 2 + (verts[i].z - va.z) ** 2;
      const db = (verts[j].x - va.x) ** 2 + (verts[j].y - va.y) ** 2 + (verts[j].z - va.z) ** 2;
      return da - db;
    });
    const chain = [ia, ...hits, ib];
    for (let k = 0; k < chain.length - 1; k++) addAtomic(chain[k], chain[k + 1]);
  }

  const byPlane = new Map();
  for (const f of hullFaces) {
    const k = `${f.axis}:${f.plane}`;
    if (!byPlane.has(k)) byPlane.set(k, []);
    byPlane.get(k).push(f);
  }

  const kept = [];
  for (const [ia, ib] of atomic.values()) {
    const va = verts[ia];
    const vb = verts[ib];
    const mid = {
      x: (va.x + vb.x) / 2,
      y: (va.y + vb.y) / 2,
      z: (va.z + vb.z) / 2,
    };
    const covering = hullFaces.filter((f) => faceContainsPoint(f, mid));
    let buried = false;
    const seen = new Set();
    for (const f of covering) {
      const k = `${f.axis}:${f.plane}`;
      if (seen.has(k)) continue;
      seen.add(k);
      if (buriedOnPlane(va, vb, byPlane.get(k) || [])) {
        buried = true;
        break;
      }
    }
    if (buried) continue;
    kept.push({
      a: ia,
      b: ib,
      vert: va.x === vb.x && va.z === vb.z && va.y !== vb.y ? 1 : 0,
      faces: outerFaceBits(outer, va, vb),
    });
  }
  const used = new Set();
  for (const e of kept) {
    used.add(e.a);
    used.add(e.b);
  }
  const remap = new Map();
  const compact = [];
  for (let i = 0; i < verts.length; i++) {
    if (!used.has(i)) continue;
    remap.set(i, compact.length);
    compact.push(verts[i]);
  }
  for (const e of kept) {
    e.a = remap.get(e.a);
    e.b = remap.get(e.b);
  }
  return { hullFaces, verts: compact, edges: kept };
}

function innerHandles(room, basis) {
  const shape = clampRoomShape(room.shape);
  if (shape === "box") return [];
  const uSize = basis.uSize;
  const vSize = basis.vSize;
  const w2 = basis.wSize / 2;
  const handles = [];
  const push = (u, w, v, key, alongHat, scale) => {
    const world = localToWorld(room, u, w, v, basis);
    handles.push({
      kind: "split",
      key,
      world,
      axis: hatAxis(alongHat),
      scale: scale * hatSign(alongHat),
    });
  };

  if (shape === "L") {
    const cutU = room.cutU | 0;
    const cutV = room.cutV | 0;
    const uFace = room.flip ? cutU : uSize - cutU;
    const uMid = room.flip ? cutU / 2 : uSize - cutU / 2;
    push(uFace, w2, vSize - cutV / 2, "cutU", basis.u, room.flip ? 1 : -1);
    push(uMid, w2, vSize - cutV, "cutV", basis.v, -1);
  } else if (shape === "T") {
    const stemW = room.stemW | 0;
    let stemPos = room.stemPos | 0;
    const barD = room.barD | 0;
    if (room.flip) stemPos = uSize - stemPos - stemW;
    push(stemPos, w2, (vSize - barD) / 2, "stemPos", basis.u, room.flip ? -1 : 1);
    push(stemPos + stemW, w2, (vSize - barD) / 2, "stemW", basis.u, room.flip ? -1 : 1);
    push(stemPos / 2, w2, vSize - barD, "barD", basis.v, -1);
  } else if (shape === "S") {
    const shift = room.shift | 0;
    const mid = room.mid | 0;
    if (room.flip) {
      push(shift, w2, mid + (vSize - mid) / 2, "shift", basis.u, 1);
    } else {
      push(uSize - shift, w2, mid + (vSize - mid) / 2, "shift", basis.u, -1);
    }
    push(uSize / 2, w2, mid, "mid", basis.v, 1);
  }
  return handles;
}

/** Outer AABB walls: one handle per hull face that sits on the room bounds. */
function wallHandles(room, hullFaces) {
  const x0 = room.x | 0;
  const y0 = room.y | 0;
  const z0 = room.z | 0;
  const x1 = x0 + (room.sx | 0);
  const y1 = y0 + (room.sy | 0);
  const z1 = z0 + (room.sz | 0);
  const handles = [];
  for (const f of hullFaces) {
    let side = null;
    if (f.axis === "x") {
      if (f.plane === x0) side = "x0";
      else if (f.plane === x1) side = "x1";
    } else if (f.axis === "y") {
      if (f.plane === y0) side = "y0";
      else if (f.plane === y1) side = "y1";
    } else if (f.axis === "z") {
      if (f.plane === z0) side = "z0";
      else if (f.plane === z1) side = "z1";
    }
    if (!side || !f.center) continue;
    handles.push({
      kind: "face",
      side,
      axis: f.axis,
      world: f.center,
    });
  }
  return handles;
}

export function roomGeometry(room) {
  const outer = {
    x: room.x | 0,
    y: room.y | 0,
    z: room.z | 0,
    sx: room.sx | 0,
    sy: room.sy | 0,
    sz: room.sz | 0,
  };
  const shape = clampRoomShape(room.shape);
  if (shape === "box") {
    const verts = [
      { x: outer.x, y: outer.y, z: outer.z },
      { x: outer.x + outer.sx, y: outer.y, z: outer.z },
      { x: outer.x + outer.sx, y: outer.y + outer.sy, z: outer.z },
      { x: outer.x, y: outer.y + outer.sy, z: outer.z },
      { x: outer.x, y: outer.y, z: outer.z + outer.sz },
      { x: outer.x + outer.sx, y: outer.y, z: outer.z + outer.sz },
      { x: outer.x + outer.sx, y: outer.y + outer.sy, z: outer.z + outer.sz },
      { x: outer.x, y: outer.y + outer.sy, z: outer.z + outer.sz },
    ];
    const edges = [
      [0, 1, 0x14],
      [1, 2, 0x06],
      [2, 3, 0x24],
      [3, 0, 0x05],
      [4, 5, 0x18],
      [5, 6, 0x0a],
      [6, 7, 0x28],
      [7, 4, 0x09],
      [0, 4, 0x11],
      [1, 5, 0x12],
      [2, 6, 0x22],
      [3, 7, 0x21],
    ].map(([a, b, faces]) => ({
      a,
      b,
      vert: a < 4 && b >= 4 ? 1 : 0,
      faces,
    }));
    const hullFaces = aabbFaces(outer).map((f) => ({
      ...f,
      corners: [
        composePoint(f, f.a0, f.b0),
        composePoint(f, f.a1, f.b0),
        composePoint(f, f.a1, f.b1),
        composePoint(f, f.a0, f.b1),
      ],
      center: composePoint(f, (f.a0 + f.a1) / 2, (f.b0 + f.b1) / 2),
    }));
    return {
      outer,
      shape: "box",
      colliders: [{ ...outer }],
      verts,
      edges,
      hullFaces,
      handles: wallHandles(room, hullFaces),
    };
  }

  const basis = roomBasis(room);
  const fp = localFootprint(room, basis);
  const colliders = fp.map((box) => uvwBoxToWorld(room, box, basis));
  const { hullFaces, verts, edges } = unionHull(colliders, outer);
  return {
    outer,
    shape,
    colliders,
    verts,
    edges,
    hullFaces,
    handles: [...wallHandles(room, hullFaces), ...innerHandles(room, basis)],
  };
}

export function pointInRoom(p, room) {
  return roomGeometry(room).colliders.some(
    (c) =>
      p.x >= c.x &&
      p.x <= c.x + c.sx &&
      p.y >= c.y &&
      p.y <= c.y + c.sy &&
      p.z >= c.z &&
      p.z <= c.z + c.sz
  );
}

export function aabbOverlapsRoom(obj, room) {
  return roomGeometry(room).colliders.some(
    (c) =>
      obj.x <= c.x + c.sx &&
      obj.x + obj.sx >= c.x &&
      obj.y <= c.y + c.sy &&
      obj.y + obj.sy >= c.y &&
      obj.z <= c.z + c.sz &&
      obj.z + obj.sz >= c.z
  );
}

export function roomFloorY(room, x, z) {
  const geom = roomGeometry(room);
  let y = room.y | 0;
  let hit = false;
  for (const c of geom.colliders) {
    if (x >= c.x && x <= c.x + c.sx && z >= c.z && z <= c.z + c.sz) {
      if (!hit || c.y > y) y = c.y;
      hit = true;
    }
  }
  return y;
}

const DOOR_FACE_IDS = ["+x", "-x", "+z", "-z"];

function bestDoorHullFace(door, room) {
  const geom = roomGeometry(room);
  const faces = geom.hullFaces || [];
  const cx = door.x + door.sx / 2;
  const cy = door.y + door.sy / 2;
  const cz = door.z + door.sz / 2;
  let best = null;
  for (const f of faces) {
    if (f.axis === "y") continue;
    if (!DOOR_FACE_IDS.includes(f.faceId)) continue;
    const dist = f.axis === "x" ? Math.abs(cx - f.plane) : Math.abs(cz - f.plane);
    const a = f.axis === "x" ? cy : cx;
    const b = f.axis === "x" ? cz : cy;
    const inA = a >= f.a0 - 1 && a <= f.a1 + 1;
    const inB = b >= f.b0 - 1 && b <= f.b1 + 1;
    const score = dist + (inA && inB ? 0 : 8);
    if (!best || score < best.score) best = { f, score };
  }
  return best?.f || null;
}

/** Face of the door AABB closer to the given room (in-game stroke plane). */
export function doorNearFaceId(door, room) {
  if (!door) return "+z";
  if (!room) return door.face || "+z";
  const geom = roomGeometry(room);
  const cols = (geom.colliders || []).filter((c) => (c.sx | 0) > 0);
  const zThin = (door.sz | 0) <= (door.sx | 0);
  let best = cols[0] || room;
  for (const c of cols) {
    if (zThin) {
      if (door.x < c.x + c.sx && door.x + door.sx > c.x) {
        best = c;
        break;
      }
    } else if (door.z < c.z + c.sz && door.z + door.sz > c.z) {
      best = c;
      break;
    }
  }
  const cx = best.x + best.sx / 2;
  const cz = best.z + best.sz / 2;
  if (zThin) {
    const d0 = Math.abs(cz - door.z);
    const d1 = Math.abs(cz - (door.z + door.sz));
    return d0 <= d1 ? "-z" : "+z";
  }
  const d0 = Math.abs(cx - door.x);
  const d1 = Math.abs(cx - (door.x + door.sx));
  return d0 <= d1 ? "-x" : "+x";
}

/** If the door sits inside-flush on a hull face, shift the box outside (thickness out). */
export function nudgeDoorOutside(door, room) {
  if (!door || !room) return door;
  const f = bestDoorHullFace(door, room);
  if (!f) return door;
  if (f.axis === "x") {
    const thick = door.sx | 0;
    if (f.sign > 0) {
      if (door.x === f.plane - thick) door.x = f.plane;
    } else if (door.x === f.plane) {
      door.x = Math.max(0, f.plane - thick);
    }
  } else {
    const thick = door.sz | 0;
    if (f.sign > 0) {
      if (door.z === f.plane - thick) door.z = f.plane;
    } else if (door.z === f.plane) {
      door.z = Math.max(0, f.plane - thick);
    }
  }
  return door;
}

export function snapDoorToRoom(door, room) {
  const f = bestDoorHullFace(door, room);
  if (!f) return door;
  const cx = door.x + door.sx / 2;
  const cy = door.y + door.sy / 2;
  const cz = door.z + door.sz / 2;
  door.face = f.faceId;
  const [fw, fh, thick] = [4, 5, 1];
  if (f.axis === "x") {
    door.sx = thick;
    door.sy = fh;
    door.sz = fw;
    door.x = f.sign > 0 ? f.plane : f.plane - door.sx;
    const z0 = f.b0;
    const z1 = f.b1;
    door.z = Math.round(cz - door.sz / 2);
    door.z = Math.max(z0, Math.min(z1 - door.sz, door.z));
    door.y = Math.round(cy - door.sy / 2);
    door.y = Math.max(f.a0, Math.min(f.a1 - door.sy, door.y));
  } else {
    door.sx = fw;
    door.sy = fh;
    door.sz = thick;
    door.z = f.sign > 0 ? f.plane : f.plane - door.sz;
    const x0 = f.a0;
    const x1 = f.a1;
    door.x = Math.round(cx - door.sx / 2);
    door.x = Math.max(x0, Math.min(x1 - door.sx, door.x));
    door.y = Math.round(cy - door.sy / 2);
    door.y = Math.max(f.b0, Math.min(f.b1 - door.sy, door.y));
  }
  if (door.x < 0) door.x = 0;
  if (door.y < 0) door.y = 0;
  if (door.z < 0) door.z = 0;
  return door;
}

export function rotateRoom(room, axis, delta) {
  const key = axis === "x" ? "rx" : axis === "y" ? "ry" : "rz";
  room[key] = clampQuarter((room[key] | 0) + delta);
  return clampRoomSplits(room);
}
