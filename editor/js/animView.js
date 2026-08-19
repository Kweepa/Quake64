import { clipForFrame, clampVert, ANIM_ORBIT_DIST_MIN, ANIM_ORBIT_DIST_MAX } from "./model.js";
import {
  distPointToSegment2d,
  intersectPlane,
  lookVectors,
  projectLine,
  projectPoint,
  screenRay,
} from "./math3d.js";

const AXIS_LEN = 8;
const AXIS_HIT = 9;
const ANIM_BOX_CLICK = 4;
function clampAnimDist(d) {
  return Math.max(ANIM_ORBIT_DIST_MIN, Math.min(ANIM_ORBIT_DIST_MAX, d));
}
const AXIS_COLS = { x: "#e55", y: "#5e5", z: "#55e" };

export class AnimView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.orbit = { yaw: 0.5, pitch: 0.15, dist: 48 };
    this.drag = null;
    this.hover = -1;
    this.hoverAxis = null;
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

  #overlay() {
    return this.opts.getMeshOverlay?.() || null;
  }

  #binding() {
    const overlay = this.#overlay();
    return overlay && overlay.bindJoint >= 0;
  }

  #cam() {
    const { yaw, pitch, dist } = this.orbit;
    const { forward } = lookVectors(yaw, pitch);
    return {
      x: -forward.x * dist,
      y: 10 - forward.y * dist,
      z: -forward.z * dist,
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

  #primaryVert() {
    return this.#selectionAnchor();
  }

  #selectedIndices() {
    return this.opts.getSelectedVerts?.() || [];
  }

  #selectionAnchor() {
    const selected = this.#selectedIndices();
    if (!selected.length) return null;
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const verts = enemy.frames[frame];
    if (selected.length === 1) {
      const i = selected[0];
      return { index: i, v: verts[i], indices: selected };
    }
    let x = 0;
    let y = 0;
    let z = 0;
    for (const i of selected) {
      x += verts[i].x;
      y += verts[i].y;
      z += verts[i].z;
    }
    const n = selected.length;
    return { index: selected[selected.length - 1], v: { x: x / n, y: y / n, z: z / n }, indices: selected };
  }

  #axisEnd(v, axis) {
    return {
      x: v.x + (axis === "x" ? AXIS_LEN : 0),
      y: v.y + (axis === "y" ? AXIS_LEN : 0),
      z: v.z + (axis === "z" ? AXIS_LEN : 0),
    };
  }

  #hitAmong(verts, mx, my, radius = 10) {
    const cam = this.#cam();
    let best = -1;
    let bestD = radius;
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

  #hitVert(mx, my) {
    const overlay = this.#overlay();
    if (overlay && overlay.bindJoint >= 0) return this.#hitAmong(overlay.verts, mx, my, 8);
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    return this.#hitAmong(enemy.frames[frame], mx, my, 10);
  }

  #hitAxis(mx, my) {
    const prim = this.#primaryVert();
    if (!prim) return null;
    const cam = this.#cam();
    const w = this.cssW;
    const h = this.cssH;
    const pa = projectPoint(prim.v, cam, w, h);
    if (!pa.ok) return null;
    let best = null;
    let bestD = AXIS_HIT;
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

  #onWheel(e) {
    if (!this.enabled) return;
    e.preventDefault();
    this.orbit.dist = clampAnimDist(this.orbit.dist * (e.deltaY > 0 ? 1.1 : 1 / 1.1));
    this.opts.onViewChanged?.();
    this.draw();
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    const p = this.#eventPos(e);
    if (e.button === 2 && e.altKey) {
      this.drag = { kind: "zoom", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button === 2 || e.button === 1) {
      this.drag = { kind: "orbit", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;

    const binding = this.#binding();
    const axis = binding ? null : this.#hitAxis(p.x, p.y);
    if (axis) {
      const prim = this.#selectionAnchor();
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const verts = enemy.frames[frame];
      this.opts.beginUndo?.();
      this.drag = {
        kind: "axis",
        axis,
        origs: prim.indices.map((i) => ({ i, x: verts[i].x, y: verts[i].y, z: verts[i].z })),
        orig: { x: prim.v.x, y: prim.v.y, z: prim.v.z },
        start: p,
      };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const vi = this.#hitVert(p.x, p.y);
    if (vi >= 0) {
      if (binding) {
        this.opts.onSelectMeshVert?.(vi, e.shiftKey);
        this.drag = { kind: "select" };
        this.canvas.setPointerCapture(e.pointerId);
        this.draw();
        return;
      }
      const selected = this.opts.getSelectedVerts?.() || [];
      const wasSelected = selected.includes(vi);
      this.opts.onSelectVert?.(vi, e.shiftKey);
      if (!wasSelected && !e.shiftKey) {
        const enemy = this.opts.getEnemy();
        const frame = this.opts.getFrame();
        const v = enemy.frames[frame][vi];
        this.drag = {
          kind: "plane",
          index: vi,
          lock: this.#lockAxis(),
          orig: { x: v.x, y: v.y, z: v.z },
          undoStarted: false,
        };
      } else {
        this.drag = { kind: "select" };
      }
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
    if (!this.drag) {
      this.hoverAxis = this.#binding() ? null : this.#hitAxis(p.x, p.y);
      this.hover = this.hoverAxis ? -1 : this.#hitVert(p.x, p.y);
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
    if (this.drag.kind === "zoom") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      const delta = dx + dy;
      if (delta) {
        this.orbit.dist = clampAnimDist(this.orbit.dist * Math.exp(-delta * ANIM_ZOOM_K));
      }
      this.draw();
      return;
    }
    if (this.drag.kind === "box") {
      this.drag.end = p;
      this.draw();
      return;
    }
    if (this.drag.kind === "axis") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const verts = enemy.frames[frame];
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
      const delta = Math.round(t * AXIS_LEN);
      for (const o of this.drag.origs) {
        const v = verts[o.i];
        v.x = o.x;
        v.y = o.y;
        v.z = o.z;
        v[this.drag.axis] = clampVert(o[this.drag.axis] + delta);
      }
      this.opts.onChange?.();
      this.draw();
      return;
    }
    if (this.drag.kind === "plane") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const v = enemy.frames[frame][this.drag.index];
      const orig = this.drag.orig;
      const cam = this.#cam();
      const ray = screenRay(p.x, p.y, cam, this.cssW, this.cssH);
      const n = { x: 0, y: 0, z: 0 };
      n[this.drag.lock] = 1;
      const hit = intersectPlane(ray.origin, ray.dir, orig, n);
      if (!hit) return;
      const next = {
        x: this.drag.lock === "x" ? orig.x : clampVert(Math.round(hit.point.x)),
        y: this.drag.lock === "y" ? orig.y : clampVert(Math.round(hit.point.y)),
        z: this.drag.lock === "z" ? orig.z : clampVert(Math.round(hit.point.z)),
      };
      if (next.x === v.x && next.y === v.y && next.z === v.z) return;
      if (!this.drag.undoStarted) {
        this.opts.beginUndo?.();
        this.drag.undoStarted = true;
      }
      v.x = next.x;
      v.y = next.y;
      v.z = next.z;
      this.opts.onChange?.();
      this.draw();
    }
  }

  #lockAxis() {
    const { forward } = lookVectors(this.orbit.yaw, this.orbit.pitch);
    const ax = Math.abs(forward.x);
    const ay = Math.abs(forward.y);
    const az = Math.abs(forward.z);
    if (ax >= ay && ax >= az) return "x";
    if (ay >= az) return "y";
    return "z";
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
    const overlay = this.#overlay();
    const verts =
      overlay && overlay.bindJoint >= 0
        ? overlay.verts
        : this.opts.getEnemy().frames[this.opts.getFrame()];
    const cam = this.#cam();
    const hits = [];
    verts.forEach((v, i) => {
      const p = projectPoint(v, cam, this.cssW, this.cssH);
      if (!p.ok) return;
      if (p.sx >= rect.x0 && p.sx <= rect.x1 && p.sy >= rect.y0 && p.sy <= rect.y1) hits.push(i);
    });
    return hits;
  }

  #finishBox() {
    const rect = this.#boxRect();
    const additive = this.drag.additive;
    const binding = this.#binding();
    if (rect.w < ANIM_BOX_CLICK && rect.h < ANIM_BOX_CLICK) {
      if (!binding && !additive) this.opts.onSelectVerts?.([]);
      return;
    }
    const hits = this.#vertsInBox(rect);
    if (binding) this.opts.onSelectMeshVerts?.(hits, additive);
    else this.opts.onSelectVerts?.(hits, additive);
  }

  #onUp(e) {
    if (!this.enabled) return;
    const orbitEnded = this.drag?.kind === "orbit" || this.drag?.kind === "zoom";
    if (this.drag?.kind === "box") this.#finishBox();
    if (this.drag?.kind === "axis" || this.drag?.undoStarted) this.opts.endUndo?.();
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

  #drawForwardArrow(ctx, cam, w, h) {
    const y = 0.2;
    const tip = { x: 0, y, z: 14 };
    const col = "#d4a017";
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y, z: 0 }, tip, col, 2.5);
    this.#strokeSeg(ctx, cam, w, h, tip, { x: 2.5, y, z: 10 }, col, 2);
    this.#strokeSeg(ctx, cam, w, h, tip, { x: -2.5, y, z: 10 }, col, 2);
    this.#strokeSeg(ctx, cam, w, h, tip, { x: 0, y: 2.5, z: 10 }, col, 2);
    const label = projectPoint({ x: 0, y: 1.5, z: 16 }, cam, w, h);
    if (label.ok) {
      ctx.fillStyle = col;
      ctx.font = "11px Segoe UI, sans-serif";
      ctx.fillText("fwd", label.sx - 10, label.sy);
    }
  }

  #drawGizmo(ctx, cam, w, h, v) {
    for (const axis of ["x", "y", "z"]) {
      const hi = this.hoverAxis === axis || this.drag?.axis === axis;
      const col = hi ? "#fff" : AXIS_COLS[axis];
      this.#strokeSeg(ctx, cam, w, h, v, this.#axisEnd(v, axis), col, hi ? 3 : 2);
      const tip = projectPoint(this.#axisEnd(v, axis), cam, w, h);
      if (tip.ok) {
        ctx.fillStyle = col;
        ctx.beginPath();
        ctx.arc(tip.sx, tip.sy, hi ? 5 : 4, 0, Math.PI * 2);
        ctx.fill();
      }
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
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const selected = this.opts.getSelectedVerts?.() || [];
    const verts = enemy.frames[frame] || enemy.frames[0];
    const overlay = this.#overlay();
    const binding = overlay && overlay.bindJoint >= 0;
    let shown = selected;
    let meshShown = overlay ? [...(overlay.jointVerts[overlay.bindJoint] || [])] : [];
    if (this.drag?.kind === "box") {
      const r = this.#boxRect();
      if (r.w >= ANIM_BOX_CLICK || r.h >= ANIM_BOX_CLICK) {
        const hits = this.#vertsInBox(r);
        if (binding) {
          meshShown = this.drag.additive ? [...new Set([...meshShown, ...hits])] : hits;
        } else {
          shown = this.drag.additive ? [...new Set([...selected, ...hits])] : hits;
        }
      }
    }

    ctx.lineWidth = 1;
    for (let i = -24; i <= 24; i += 8) {
      this.#strokeSeg(ctx, cam, w, h, { x: i, y: 0, z: -24 }, { x: i, y: 0, z: 24 }, "#3d4658");
      this.#strokeSeg(ctx, cam, w, h, { x: -24, y: 0, z: i }, { x: 24, y: 0, z: i }, "#3d4658");
    }
    this.#strokeSeg(ctx, cam, w, h, { x: -20, y: 0, z: 0 }, { x: 20, y: 0, z: 0 }, "#a66");
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: 0 }, { x: 0, y: 24, z: 0 }, "#6a6");
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: -20 }, { x: 0, y: 0, z: 20 }, "#66a");
    this.#drawForwardArrow(ctx, cam, w, h);

    if (overlay) {
      ctx.lineWidth = 1;
      for (const [i, j] of overlay.edges) {
        const a = overlay.verts[i];
        const b = overlay.verts[j];
        if (a && b) this.#strokeSeg(ctx, cam, w, h, a, b, "#3a4458", 1);
      }
      if (overlay.ghost) {
        for (const [i, j] of overlay.lines || enemy.lines) {
          const a = overlay.ghost[i];
          const b = overlay.ghost[j];
          if (a && b) this.#strokeSeg(ctx, cam, w, h, a, b, "#5ec8c8", 1.5);
        }
        overlay.ghost.forEach((v) => {
          if (!v) return;
          const p = projectPoint(v, cam, w, h);
          if (!p.ok) return;
          ctx.fillStyle = "#5ec8c8";
          ctx.beginPath();
          ctx.arc(p.sx, p.sy, 4, 0, Math.PI * 2);
          ctx.fill();
        });
      }
    }

    ctx.lineWidth = 1.5;
    for (const [i, j] of enemy.lines) {
      this.#strokeSeg(ctx, cam, w, h, verts[i], verts[j], "#c8ccd4", 1.5);
    }

    verts.forEach((v, i) => {
      const p = projectPoint(v, cam, w, h);
      if (!p.ok) return;
      const sel = !binding && shown.includes(i);
      const hover = !binding && i === this.hover;
      ctx.fillStyle = sel ? "#d4a017" : hover ? "#fff" : "#8b91a0";
      const r = sel ? 5 : 4;
      ctx.beginPath();
      ctx.arc(p.sx, p.sy, r, 0, Math.PI * 2);
      ctx.fill();
    });

    if (binding) {
      const assignedOther = new Set();
      overlay.jointVerts.forEach((list, ji) => {
        if (ji === overlay.bindJoint) return;
        for (const i of list) assignedOther.add(i);
      });
      overlay.verts.forEach((v, i) => {
        const p = projectPoint(v, cam, w, h);
        if (!p.ok) return;
        const sel = meshShown.includes(i);
        const hover = i === this.hover;
        const other = assignedOther.has(i);
        ctx.fillStyle = sel ? "#d4a017" : hover ? "#fff" : other ? "#5ec8c8" : "#5a6270";
        const r = sel || hover ? 3.5 : 2.5;
        ctx.beginPath();
        ctx.arc(p.sx, p.sy, r, 0, Math.PI * 2);
        ctx.fill();
      });
    }

    const prim = this.#selectionAnchor();
    if (prim && !binding) this.#drawGizmo(ctx, cam, w, h, prim.v);

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

    ctx.fillStyle = "#8b91a0";
    ctx.font = "11px Segoe UI, sans-serif";
    const clip = clipForFrame(enemy.clips, frame);
    let label;
    if (enemy.clips?.length && clip) {
      label = `${clip.name} ${frame - clip.start}`;
    } else if (overlay?.frameName) {
      label = overlay.frameName;
    } else {
      label = "rest";
    }
    const frameTotal = enemy.clips?.length ? enemy.frames.length : overlay ? "MDL" : enemy.frames.length;
    ctx.fillText(`${enemy.name} · ${label} · 13 verts · ${frameTotal} frames`, 8, 16);
  }
}
