import {
  ITEM_MIN,
  ITEM_MAX,
  ITEM_ORIGIN,
  ITEM_MAX_VERTS,
  ITEM_MAX_LINES,
  ITEM_MAX_UNIQUE,
  clampItemCoord,
  itemUniqueXZ,
} from "./model.js";
import {
  distPointToSegment2d,
  lookVectors,
  projectLine,
  projectPoint,
} from "./math3d.js";

const ITEM_VERT_HIT = 10;
const ITEM_LINE_HIT = 6;
const ITEM_DIST_MIN = 8;
const ITEM_DIST_MAX = 80;
const ITEM_BOX_CLICK = 4;
const ITEM_ZOOM_K = 0.008;
const ITEM_AXIS_LEN = 2;
const ITEM_AXIS_HIT = 9;
const ITEM_AXIS_COLS = { x: "#e55", y: "#5e5", z: "#55e" };

function clampItemDist(d) {
  return Math.max(ITEM_DIST_MIN, Math.min(ITEM_DIST_MAX, d));
}

/** { verts: [{x,y,z}], lines: [[i,j]] } in local indices. Survives mesh-type switches. */
let itemClip = null;

function offsetSortKey([dx, dy, dz]) {
  const m = Math.abs(dx) + Math.abs(dy) + Math.abs(dz);
  const axis = dx !== 0 ? 0 : dz !== 0 ? 1 : 2;
  const sign = dx + dy + dz < 0 ? 1 : 0;
  return m * 100 + axis * 10 + sign;
}

export class ItemView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.orbit = { yaw: 0.6, pitch: 0.35, dist: 16, target: { x: 0, y: 0, z: 0 } };
    this.drag = null;
    this.hoverVert = -1;
    this.hoverLine = -1;
    this.hoverAxis = null;
    this.selectedVerts = [];
    this.selectedLines = [];
    this.enabled = false;
    this._ro = new ResizeObserver(() => this.resize());
    this._ro.observe(opts.stage || canvas.parentElement);
    this.resize();

    canvas.addEventListener("pointerdown", (e) => this.#onDown(e));
    canvas.addEventListener("pointermove", (e) => this.#onMove(e));
    canvas.addEventListener("pointerup", (e) => this.#onUp(e));
    canvas.addEventListener("pointerleave", (e) => this.#onUp(e));
    canvas.addEventListener("wheel", (e) => this.#onWheel(e), { passive: false });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 1) e.preventDefault();
    });
    canvas.addEventListener("auxclick", (e) => {
      if (e.button === 1) e.preventDefault();
    });
  }

  resize() {
    const stage = this.opts.stage || this.canvas.parentElement;
    const rect = stage.getBoundingClientRect();
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const w = Math.max(64, Math.floor(rect.width));
    const h = Math.max(64, Math.floor(rect.height));
    this.canvas.width = Math.floor(w * dpr);
    this.canvas.height = Math.floor(h * dpr);
    this.canvas.style.width = `${w}px`;
    this.canvas.style.height = `${h}px`;
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.cssW = w;
    this.cssH = h;
    this.draw();
  }

  selection() {
    return { verts: [...this.selectedVerts], lines: [...this.selectedLines] };
  }

  clearSelection() {
    this.selectedVerts = [];
    this.selectedLines = [];
    this.hoverVert = -1;
    this.hoverLine = -1;
    this.hoverAxis = null;
  }

  addVertAtOrigin() {
    const mesh = this.#mesh();
    if (mesh.verts.length >= ITEM_MAX_VERTS) {
      this.opts.onStatus?.("Vertex cap (16)", true);
      return false;
    }
    const cell = { x: ITEM_ORIGIN, y: ITEM_ORIGIN, z: ITEM_ORIGIN };
    if (this.#occupied(mesh, cell.x, cell.y, cell.z)) {
      this.opts.onStatus?.("Origin is occupied", true);
      return false;
    }
    const next = [...mesh.verts, { ...cell }];
    if (!this.#uniqueOk(next)) {
      this.opts.onStatus?.(`Would exceed ${ITEM_MAX_UNIQUE} unique X or Z`, true);
      return false;
    }
    this.opts.beginUndo?.();
    mesh.verts.push({ ...cell });
    this.opts.endUndo?.();
    this.selectedVerts = [mesh.verts.length - 1];
    this.selectedLines = [];
    this.opts.onChange?.();
    this.opts.onSelect?.();
    this.draw();
    return true;
  }

  addLineFromSelection() {
    const mesh = this.#mesh();
    if (this.selectedVerts.length !== 2) {
      this.opts.onStatus?.("Select two vertices", true);
      return false;
    }
    const [a, b] = this.selectedVerts;
    if (!this.#canAddLine(mesh, a, b)) {
      this.opts.onStatus?.(mesh.lines.length >= ITEM_MAX_LINES ? "Line cap (16)" : "Line already exists", true);
      return false;
    }
    this.opts.beginUndo?.();
    this.#tryAddLine(mesh, a, b);
    this.opts.endUndo?.();
    this.opts.onChange?.();
    this.opts.onSelect?.();
    this.draw();
    return true;
  }

  deleteSelection() {
    const mesh = this.#mesh();
    if (!mesh) return false;
    const lines = [...this.selectedLines].filter((i) => i >= 0 && i < mesh.lines.length).sort((a, b) => b - a);
    const verts = [...this.selectedVerts].filter((i) => i >= 0 && i < mesh.verts.length).sort((a, b) => b - a);
    if (!lines.length && !verts.length) return false;
    this.opts.beginUndo?.();
    for (const i of lines) mesh.lines.splice(i, 1);
    for (const i of verts) {
      mesh.verts.splice(i, 1);
      mesh.lines = mesh.lines
        .filter(([a, b]) => a !== i && b !== i)
        .map(([a, b]) => [a > i ? a - 1 : a, b > i ? b - 1 : b]);
    }
    this.opts.endUndo?.();
    this.clearSelection();
    this.opts.onChange?.();
    this.opts.onSelect?.();
    this.draw();
    return true;
  }

  hasClipboard() {
    return !!(itemClip && itemClip.verts.length);
  }

  copySelection() {
    const clip = this.#gatherSelection();
    if (!clip) {
      this.opts.onStatus?.("Nothing selected", true);
      return false;
    }
    itemClip = clip;
    this.opts.onSelect?.();
    const nv = clip.verts.length;
    const ne = clip.lines.length;
    this.opts.onStatus?.(`Copied ${nv} vert${nv === 1 ? "" : "s"}, ${ne} line${ne === 1 ? "" : "s"}`);
    return true;
  }

  pasteSelection() {
    if (!itemClip?.verts.length) {
      this.opts.onStatus?.("Nothing to paste", true);
      return false;
    }
    const mesh = this.#mesh();
    const addV = itemClip.verts.length;
    const addE = itemClip.lines.length;
    if (mesh.verts.length + addV > ITEM_MAX_VERTS) {
      this.opts.onStatus?.("Vertex cap (16)", true);
      return false;
    }
    if (mesh.lines.length + addE > ITEM_MAX_LINES) {
      this.opts.onStatus?.("Line cap (16)", true);
      return false;
    }
    let uniqueFail = false;
    let placed = null;
    for (const [dx, dy, dz] of this.#pasteOffsets(itemClip.verts)) {
      const trial = this.#shiftedClip(dx, dy, dz);
      if (!trial || this.#cellsBlocked(mesh, trial)) continue;
      if (!this.#uniqueOk([...mesh.verts, ...trial])) {
        uniqueFail = true;
        continue;
      }
      placed = trial;
      break;
    }
    if (!placed) {
      this.opts.onStatus?.(
        uniqueFail ? `Would exceed ${ITEM_MAX_UNIQUE} unique X or Z` : "No free cells for paste",
        true
      );
      return false;
    }
    this.opts.beginUndo?.();
    const base = mesh.verts.length;
    for (const v of placed) mesh.verts.push({ x: v.x, y: v.y, z: v.z });
    for (const [a, b] of itemClip.lines) this.#tryAddLine(mesh, base + a, base + b);
    this.opts.endUndo?.();
    this.selectedVerts = placed.map((_, i) => base + i);
    this.selectedLines = [];
    this.opts.onChange?.();
    this.opts.onSelect?.();
    this.draw();
    this.opts.onStatus?.(`Pasted ${addV} vert${addV === 1 ? "" : "s"}, ${addE} line${addE === 1 ? "" : "s"}`);
    return true;
  }

  #gatherSelection() {
    const mesh = this.#mesh();
    const vset = new Set();
    const edgeKeys = new Set();
    const addEdge = (a, b) => {
      if (a === b || !mesh.verts[a] || !mesh.verts[b]) return;
      edgeKeys.add(`${Math.min(a, b)},${Math.max(a, b)}`);
    };
    for (const i of this.selectedVerts) {
      if (mesh.verts[i]) vset.add(i);
    }
    for (const i of this.selectedLines) {
      const e = mesh.lines[i];
      if (!e) continue;
      if (mesh.verts[e[0]]) vset.add(e[0]);
      if (mesh.verts[e[1]]) vset.add(e[1]);
      addEdge(e[0], e[1]);
    }
    if (!vset.size) return null;
    for (const [a, b] of mesh.lines) {
      if (vset.has(a) && vset.has(b)) addEdge(a, b);
    }
    const indices = [...vset].sort((a, b) => a - b);
    const imap = new Map(indices.map((i, j) => [i, j]));
    return {
      verts: indices.map((i) => {
        const v = mesh.verts[i];
        return { x: v.x | 0, y: v.y | 0, z: v.z | 0 };
      }),
      lines: [...edgeKeys].map((k) => {
        const [a, b] = k.split(",").map(Number);
        return [imap.get(a), imap.get(b)];
      }),
    };
  }

  #pasteOffsets(verts) {
    let minx = ITEM_MAX;
    let maxx = ITEM_MIN;
    let miny = ITEM_MAX;
    let maxy = ITEM_MIN;
    let minz = ITEM_MAX;
    let maxz = ITEM_MIN;
    for (const v of verts) {
      minx = Math.min(minx, v.x);
      maxx = Math.max(maxx, v.x);
      miny = Math.min(miny, v.y);
      maxy = Math.max(maxy, v.y);
      minz = Math.min(minz, v.z);
      maxz = Math.max(maxz, v.z);
    }
    const offs = [];
    for (let dx = ITEM_MIN - minx; dx <= ITEM_MAX - maxx; dx++) {
      for (let dy = ITEM_MIN - miny; dy <= ITEM_MAX - maxy; dy++) {
        for (let dz = ITEM_MIN - minz; dz <= ITEM_MAX - maxz; dz++) {
          offs.push([dx, dy, dz]);
        }
      }
    }
    offs.sort((a, b) => offsetSortKey(a) - offsetSortKey(b));
    return offs;
  }

  #shiftedClip(dx, dy, dz) {
    const placed = [];
    for (const v of itemClip.verts) {
      const x = v.x + dx;
      const y = v.y + dy;
      const z = v.z + dz;
      if (x < ITEM_MIN || x > ITEM_MAX || y < ITEM_MIN || y > ITEM_MAX || z < ITEM_MIN || z > ITEM_MAX) {
        return null;
      }
      placed.push({ x, y, z });
    }
    return placed;
  }

  #cellsBlocked(mesh, placed) {
    const seen = new Set();
    for (const v of placed) {
      const k = `${v.x},${v.y},${v.z}`;
      if (seen.has(k) || this.#occupied(mesh, v.x, v.y, v.z)) return true;
      seen.add(k);
    }
    return false;
  }

  #mesh() {
    return this.opts.getMesh?.() || { verts: [], lines: [] };
  }

  #cam() {
    const { yaw, pitch, dist, target } = this.orbit;
    const { forward } = lookVectors(yaw, pitch);
    return {
      x: target.x - forward.x * dist,
      y: target.y - forward.y * dist,
      z: target.z - forward.z * dist,
      yaw,
      pitch,
    };
  }

  #eventPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * this.cssW,
      y: ((e.clientY - rect.top) / rect.height) * this.cssH,
    };
  }

  #selectionAnchor() {
    const mesh = this.#mesh();
    const selected = this.selectedVerts.filter((i) => mesh.verts[i]);
    if (!selected.length) return null;
    if (selected.length === 1) {
      const i = selected[0];
      return { v: mesh.verts[i], indices: selected };
    }
    let x = 0;
    let y = 0;
    let z = 0;
    for (const i of selected) {
      x += mesh.verts[i].x;
      y += mesh.verts[i].y;
      z += mesh.verts[i].z;
    }
    const n = selected.length;
    return { v: { x: x / n, y: y / n, z: z / n }, indices: selected };
  }

  #axisEnd(v, axis) {
    return {
      x: v.x + (axis === "x" ? ITEM_AXIS_LEN : 0),
      y: v.y + (axis === "y" ? ITEM_AXIS_LEN : 0),
      z: v.z + (axis === "z" ? ITEM_AXIS_LEN : 0),
    };
  }

  #hitVert(mx, my, verts) {
    const cam = this.#cam();
    let best = -1;
    let bestD = ITEM_VERT_HIT;
    verts.forEach((v, i) => {
      const p = projectPoint(v, cam, this.cssW, this.cssH);
      if (!p.ok) return;
      const d = Math.hypot(mx - p.sx, my - p.sy);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    });
    return best;
  }

  #hitLine(mx, my, mesh) {
    const cam = this.#cam();
    let best = -1;
    let bestD = ITEM_LINE_HIT;
    mesh.lines.forEach(([ia, ib], i) => {
      const a = mesh.verts[ia];
      const b = mesh.verts[ib];
      if (!a || !b) return;
      const pl = projectLine(a, b, cam, this.cssW, this.cssH);
      if (!pl) return;
      const d = distPointToSegment2d(mx, my, pl.ax, pl.ay, pl.bx, pl.by);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    });
    return best;
  }

  #hitAxis(mx, my) {
    const prim = this.#selectionAnchor();
    if (!prim) return null;
    const cam = this.#cam();
    const w = this.cssW;
    const h = this.cssH;
    const pa = projectPoint(prim.v, cam, w, h);
    if (!pa.ok) return null;
    let best = null;
    let bestD = ITEM_AXIS_HIT;
    for (const axis of ["x", "y", "z"]) {
      const pb = projectPoint(this.#axisEnd(prim.v, axis), cam, w, h);
      if (!pb.ok) continue;
      const d = distPointToSegment2d(mx, my, pa.sx, pa.sy, pb.sx, pb.sy);
      if (d < bestD) {
        bestD = d;
        best = axis;
      }
    }
    return best;
  }

  #occupied(mesh, x, y, z, skip = new Set()) {
    return mesh.verts.some((v, i) => !skip.has(i) && v.x === x && v.y === y && v.z === z);
  }

  #uniqueOk(verts) {
    const { nx, nz } = itemUniqueXZ(verts);
    return nx <= ITEM_MAX_UNIQUE && nz <= ITEM_MAX_UNIQUE;
  }

  #canAddLine(mesh, a, b) {
    if (a === b || a < 0 || b < 0 || a >= mesh.verts.length || b >= mesh.verts.length) return false;
    if (mesh.lines.length >= ITEM_MAX_LINES) return false;
    const lo = Math.min(a, b);
    const hi = Math.max(a, b);
    return !mesh.lines.some(([ia, ib]) => Math.min(ia, ib) === lo && Math.max(ia, ib) === hi);
  }

  #tryAddLine(mesh, a, b) {
    if (!this.#canAddLine(mesh, a, b)) return false;
    mesh.lines.push([Math.min(a, b), Math.max(a, b)]);
    return true;
  }

  #selectVert(i, additive) {
    if (i < 0) this.selectedVerts = [];
    else if (additive) {
      if (!this.selectedVerts.includes(i)) this.selectedVerts.push(i);
    } else this.selectedVerts = [i];
    this.selectedLines = [];
    this.opts.onSelect?.();
  }

  #selectVerts(indices, additive) {
    if (additive) {
      for (const i of indices) {
        if (!this.selectedVerts.includes(i)) this.selectedVerts.push(i);
      }
    } else this.selectedVerts = [...indices];
    this.selectedLines = [];
    this.opts.onSelect?.();
  }

  #selectLine(i, additive) {
    if (i < 0) this.selectedLines = [];
    else if (additive) {
      if (!this.selectedLines.includes(i)) this.selectedLines.push(i);
    } else this.selectedLines = [i];
    this.selectedVerts = [];
    this.opts.onSelect?.();
  }

  #onWheel(e) {
    if (!this.enabled) return;
    e.preventDefault();
    this.orbit.dist = clampItemDist(this.orbit.dist * (e.deltaY > 0 ? 1.1 : 1 / 1.1));
    this.opts.onViewChanged?.();
    this.draw();
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    const p = this.#eventPos(e);
    const mesh = this.#mesh();

    if (e.button === 2 && e.altKey) {
      this.drag = { kind: "zoom", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button === 1) {
      this.drag = { kind: "pan", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button === 2) {
      this.drag = { kind: "orbit", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;
    if (e.altKey) {
      e.preventDefault();
      this.drag = { kind: "orbit", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const vi = this.#hitVert(p.x, p.y, mesh.verts);
    if (vi >= 0) {
      this.#selectVert(vi, e.shiftKey);
      this.drag = { kind: "select" };
      this.canvas.setPointerCapture(e.pointerId);
      this.draw();
      return;
    }

    const axis = this.#hitAxis(p.x, p.y);
    if (axis) {
      const prim = this.#selectionAnchor();
      this.opts.beginUndo?.();
      this.drag = {
        kind: "axis",
        axis,
        origs: prim.indices.map((i) => ({ i, x: mesh.verts[i].x, y: mesh.verts[i].y, z: mesh.verts[i].z })),
        orig: { x: prim.v.x, y: prim.v.y, z: prim.v.z },
        start: p,
      };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const li = this.#hitLine(p.x, p.y, mesh);
    if (li >= 0) {
      this.#selectLine(li, e.shiftKey);
      this.drag = { kind: "select" };
      this.canvas.setPointerCapture(e.pointerId);
      this.draw();
      return;
    }

    this.drag = { kind: "box", start: p, end: p, additive: e.shiftKey };
    this.canvas.setPointerCapture(e.pointerId);
  }

  #onMove(e) {
    if (!this.enabled) return;
    const p = this.#eventPos(e);
    const mesh = this.#mesh();
    if (!this.drag) {
      this.hoverVert = this.#hitVert(p.x, p.y, mesh.verts);
      this.hoverAxis = this.hoverVert >= 0 ? null : this.#hitAxis(p.x, p.y);
      this.hoverLine = this.hoverAxis || this.hoverVert >= 0 ? -1 : this.#hitLine(p.x, p.y, mesh);
      this.draw();
      return;
    }
    if (this.drag.kind === "orbit") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      this.orbit.yaw += dx * 0.01;
      this.orbit.pitch = Math.max(-1.2, Math.min(1.2, this.orbit.pitch - dy * 0.01));
      this.draw();
      return;
    }
    if (this.drag.kind === "pan") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      const focal = Math.min(this.cssW, this.cssH) * 0.9;
      const scale = this.orbit.dist / focal;
      const { right, up } = lookVectors(this.orbit.yaw, this.orbit.pitch);
      const t = this.orbit.target;
      t.x += (-right.x * dx + up.x * dy) * scale;
      t.y += (-right.y * dx + up.y * dy) * scale;
      t.z += (-right.z * dx + up.z * dy) * scale;
      this.draw();
      return;
    }
    if (this.drag.kind === "zoom") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      const delta = dx + dy;
      if (delta) this.orbit.dist = clampItemDist(this.orbit.dist * Math.exp(-delta * ITEM_ZOOM_K));
      this.draw();
      return;
    }
    if (this.drag.kind === "box") {
      this.drag.end = p;
      this.draw();
      return;
    }
    if (this.drag.kind === "axis") {
      const cam = this.#cam();
      const orig = this.drag.orig;
      const pa = projectPoint(orig, cam, this.cssW, this.cssH);
      const pb = projectPoint(this.#axisEnd(orig, this.drag.axis), cam, this.cssW, this.cssH);
      if (!pa.ok || !pb.ok) return;
      const ax = pb.sx - pa.sx;
      const ay = pb.sy - pa.sy;
      const alen2 = ax * ax + ay * ay;
      if (alen2 < 16) return;
      const t = ((p.x - this.drag.start.x) * ax + (p.y - this.drag.start.y) * ay) / alen2;
      const delta = Math.round(t * ITEM_AXIS_LEN);
      const next = mesh.verts.map((v) => ({ ...v }));
      for (const o of this.drag.origs) {
        next[o.i].x = o.x;
        next[o.i].y = o.y;
        next[o.i].z = o.z;
        next[o.i][this.drag.axis] = clampItemCoord(o[this.drag.axis] + delta);
      }
      const seen = new Set();
      for (const v of next) {
        const k = `${v.x},${v.y},${v.z}`;
        if (seen.has(k)) return;
        seen.add(k);
      }
      if (!this.#uniqueOk(next)) return;
      for (const o of this.drag.origs) {
        mesh.verts[o.i].x = next[o.i].x;
        mesh.verts[o.i].y = next[o.i].y;
        mesh.verts[o.i].z = next[o.i].z;
      }
      this.opts.onChange?.();
      this.draw();
    }
  }

  #boxRect() {
    const a = this.drag.start;
    const b = this.drag.end;
    const x0 = Math.min(a.x, b.x);
    const y0 = Math.min(a.y, b.y);
    const x1 = Math.max(a.x, b.x);
    const y1 = Math.max(a.y, b.y);
    return { x0, y0, x1, y1, w: x1 - x0, h: y1 - y0 };
  }

  #vertsInBox(rect) {
    const mesh = this.#mesh();
    const cam = this.#cam();
    const hits = [];
    mesh.verts.forEach((v, i) => {
      const p = projectPoint(v, cam, this.cssW, this.cssH);
      if (!p.ok) return;
      if (p.sx >= rect.x0 && p.sx <= rect.x1 && p.sy >= rect.y0 && p.sy <= rect.y1) hits.push(i);
    });
    return hits;
  }

  #finishBox() {
    const rect = this.#boxRect();
    const additive = this.drag.additive;
    if (rect.w < ITEM_BOX_CLICK && rect.h < ITEM_BOX_CLICK) {
      if (!additive) {
        this.selectedVerts = [];
        this.selectedLines = [];
        this.opts.onSelect?.();
      }
      return;
    }
    this.#selectVerts(this.#vertsInBox(rect), additive);
  }

  #onUp(e) {
    if (!this.enabled) return;
    const orbitEnded = this.drag?.kind === "orbit" || this.drag?.kind === "zoom" || this.drag?.kind === "pan";
    if (this.drag?.kind === "box") this.#finishBox();
    if (this.drag?.kind === "axis") this.opts.endUndo?.();
    this.drag = null;
    if (orbitEnded) this.opts.onViewChanged?.();
    try {
      this.canvas.releasePointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    this.draw();
  }

  #strokeSeg(ctx, cam, w, h, p0, p1, col, width = 1) {
    const seg = projectLine(p0, p1, cam, w, h);
    if (!seg) return;
    ctx.strokeStyle = col;
    ctx.lineWidth = width;
    ctx.beginPath();
    ctx.moveTo(seg.ax, seg.ay);
    ctx.lineTo(seg.bx, seg.by);
    ctx.stroke();
  }

  #drawGizmo(ctx, cam, w, h, v) {
    for (const axis of ["x", "y", "z"]) {
      const hi = this.hoverAxis === axis || this.drag?.axis === axis;
      const col = hi ? "#fff" : ITEM_AXIS_COLS[axis];
      this.#strokeSeg(ctx, cam, w, h, v, this.#axisEnd(v, axis), col, hi ? 3 : 2);
    }
  }

  draw() {
    if (!this.enabled) return;
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);
    const cam = this.#cam();
    const mesh = this.#mesh();
    const lo = ITEM_MIN;
    const hi = ITEM_MAX;

    for (let i = lo; i <= hi; i++) {
      const col = i === 0 ? "#3d4658" : "#2a3140";
      this.#strokeSeg(ctx, cam, w, h, { x: i, y: 0, z: lo }, { x: i, y: 0, z: hi }, col);
      this.#strokeSeg(ctx, cam, w, h, { x: lo, y: 0, z: i }, { x: hi, y: 0, z: i }, col);
    }
    const cube = [
      [
        { x: lo, y: lo, z: lo },
        { x: hi, y: lo, z: lo },
      ],
      [
        { x: hi, y: lo, z: lo },
        { x: hi, y: lo, z: hi },
      ],
      [
        { x: hi, y: lo, z: hi },
        { x: lo, y: lo, z: hi },
      ],
      [
        { x: lo, y: lo, z: hi },
        { x: lo, y: lo, z: lo },
      ],
      [
        { x: lo, y: hi, z: lo },
        { x: hi, y: hi, z: lo },
      ],
      [
        { x: hi, y: hi, z: lo },
        { x: hi, y: hi, z: hi },
      ],
      [
        { x: hi, y: hi, z: hi },
        { x: lo, y: hi, z: hi },
      ],
      [
        { x: lo, y: hi, z: hi },
        { x: lo, y: hi, z: lo },
      ],
      [
        { x: lo, y: lo, z: lo },
        { x: lo, y: hi, z: lo },
      ],
      [
        { x: hi, y: lo, z: lo },
        { x: hi, y: hi, z: lo },
      ],
      [
        { x: hi, y: lo, z: hi },
        { x: hi, y: hi, z: hi },
      ],
      [
        { x: lo, y: lo, z: hi },
        { x: lo, y: hi, z: hi },
      ],
    ];
    for (const [a, b] of cube) this.#strokeSeg(ctx, cam, w, h, a, b, "#252a35");

    const o = { x: 0, y: 0, z: 0 };
    this.#strokeSeg(ctx, cam, w, h, { x: lo, y: 0, z: 0 }, { x: hi, y: 0, z: 0 }, "#a66", 2);
    this.#strokeSeg(ctx, cam, w, h, o, { x: 0, y: hi, z: 0 }, "#6a6", 2);
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: lo }, { x: 0, y: 0, z: hi }, "#66a", 2);

    let shownVerts = this.selectedVerts;
    if (this.drag?.kind === "box") {
      const r = this.#boxRect();
      if (r.w >= ITEM_BOX_CLICK || r.h >= ITEM_BOX_CLICK) {
        const hits = this.#vertsInBox(r);
        shownVerts = this.drag.additive ? [...new Set([...this.selectedVerts, ...hits])] : hits;
      }
    }

    mesh.lines.forEach(([ia, ib], i) => {
      const a = mesh.verts[ia];
      const b = mesh.verts[ib];
      if (!a || !b) return;
      const sel = this.selectedLines.includes(i);
      this.#strokeSeg(ctx, cam, w, h, a, b, sel ? "#f2d36b" : "#c8ccd4", sel ? 2.5 : 1.5);
    });

    mesh.verts.forEach((v, i) => {
      const pr = projectPoint(v, cam, w, h);
      if (!pr.ok) return;
      const sel = shownVerts.includes(i);
      const ho = i === this.hoverVert;
      ctx.fillStyle = sel ? "#d4a017" : ho ? "#fff" : "#6ec4a8";
      const r = sel || ho ? 5 : 4;
      ctx.beginPath();
      ctx.arc(pr.sx, pr.sy, r, 0, Math.PI * 2);
      ctx.fill();
    });

    const prim = this.#selectionAnchor();
    if (prim) this.#drawGizmo(ctx, cam, w, h, prim.v);

    if (this.drag?.kind === "box") {
      const r = this.#boxRect();
      ctx.fillStyle = "rgba(212, 160, 23, 0.12)";
      ctx.fillRect(r.x0, r.y0, r.w, r.h);
      ctx.strokeStyle = "#d4a017";
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.strokeRect(r.x0 + 0.5, r.y0 + 0.5, r.w, r.h);
      ctx.setLineDash([]);
    }
  }
}
