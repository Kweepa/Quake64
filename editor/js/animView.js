import { FRAME_NAMES, clampVert } from "./model.js";
import {
  distPointToSegment2d,
  lookVectors,
  projectLine,
  projectPoint,
} from "./math3d.js";

const AXIS_LEN = 8;
const AXIS_HIT = 9;
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
    const selected = this.opts.getSelectedVerts?.() || [];
    if (!selected.length) return null;
    const i = selected[selected.length - 1];
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    return { index: i, v: enemy.frames[frame][i] };
  }

  #axisEnd(v, axis) {
    return {
      x: v.x + (axis === "x" ? AXIS_LEN : 0),
      y: v.y + (axis === "y" ? AXIS_LEN : 0),
      z: v.z + (axis === "z" ? AXIS_LEN : 0),
    };
  }

  #hitVert(mx, my) {
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const cam = this.#cam();
    const verts = enemy.frames[frame];
    let best = -1;
    let bestD = 10;
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
    this.orbit.dist = Math.max(16, Math.min(120, this.orbit.dist + (e.deltaY > 0 ? 4 : -4)));
    this.draw();
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    const p = this.#eventPos(e);
    if (e.button === 2 || e.button === 1) {
      this.drag = { kind: "orbit", last: p };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;

    const axis = this.#hitAxis(p.x, p.y);
    if (axis) {
      const prim = this.#primaryVert();
      this.opts.beginUndo?.();
      this.drag = {
        kind: "axis",
        axis,
        index: prim.index,
        orig: { ...prim.v },
        start: p,
      };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const vi = this.#hitVert(p.x, p.y);
    if (vi >= 0) {
      this.opts.onSelectVert?.(vi, e.shiftKey);
      this.drag = { kind: "select" };
      this.canvas.setPointerCapture(e.pointerId);
      this.draw();
      return;
    }
    this.opts.onSelectVert?.(-1, false);
    this.drag = { kind: "orbit", last: p };
    this.canvas.setPointerCapture(e.pointerId);
  }

  #onMove(e) {
    if (!this.enabled) return;
    const p = this.#eventPos(e);
    if (!this.drag) {
      this.hoverAxis = this.#hitAxis(p.x, p.y);
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
    if (this.drag.kind === "axis") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const v = enemy.frames[frame][this.drag.index];
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
      v.x = orig.x;
      v.y = orig.y;
      v.z = orig.z;
      v[this.drag.axis] = clampVert(orig[this.drag.axis] + delta);
      this.opts.onChange?.();
      this.draw();
    }
  }

  #onUp(e) {
    if (!this.enabled) return;
    if (this.drag?.kind === "axis") this.opts.endUndo?.();
    this.drag = null;
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
    const verts = enemy.frames[frame];

    ctx.lineWidth = 1;
    for (let i = -24; i <= 24; i += 8) {
      this.#strokeSeg(ctx, cam, w, h, { x: i, y: 0, z: -24 }, { x: i, y: 0, z: 24 }, "#3d4658");
      this.#strokeSeg(ctx, cam, w, h, { x: -24, y: 0, z: i }, { x: 24, y: 0, z: i }, "#3d4658");
    }
    this.#strokeSeg(ctx, cam, w, h, { x: -20, y: 0, z: 0 }, { x: 20, y: 0, z: 0 }, "#a66");
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: 0 }, { x: 0, y: 24, z: 0 }, "#6a6");
    this.#strokeSeg(ctx, cam, w, h, { x: 0, y: 0, z: -20 }, { x: 0, y: 0, z: 20 }, "#66a");
    this.#drawForwardArrow(ctx, cam, w, h);

    ctx.lineWidth = 1.5;
    for (const [i, j] of enemy.lines) {
      this.#strokeSeg(ctx, cam, w, h, verts[i], verts[j], "#c8ccd4", 1.5);
    }

    verts.forEach((v, i) => {
      const p = projectPoint(v, cam, w, h);
      if (!p.ok) return;
      const sel = selected.includes(i);
      const hover = i === this.hover;
      ctx.fillStyle = sel ? "#d4a017" : hover ? "#fff" : "#8b91a0";
      const r = sel ? 5 : 4;
      ctx.beginPath();
      ctx.arc(p.sx, p.sy, r, 0, Math.PI * 2);
      ctx.fill();
    });

    const prim = this.#primaryVert();
    if (prim) this.#drawGizmo(ctx, cam, w, h, prim.v);

    ctx.fillStyle = "#8b91a0";
    ctx.font = "11px Segoe UI, sans-serif";
    ctx.fillText(
      `${enemy.name} · ${FRAME_NAMES[frame]} · 13 verts · 24 frames`,
      8,
      16
    );
  }
}
