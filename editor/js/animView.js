import { FRAME_NAMES, MAX_VERTS, VERT_MAX, VERT_MIN, clampVert } from "./model.js";
import { lookVectors, projectLine, projectPoint } from "./math3d.js";

export class AnimView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.orbit = { yaw: 0.5, pitch: 0.15, dist: 48 };
    this.drag = null;
    this.hover = -1;
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

  #projectedVerts() {
    const enemy = this.opts.getEnemy();
    const frame = this.opts.getFrame();
    const cam = this.#cam();
    const verts = enemy.frames[frame];
    return verts.map((v) => ({
      v,
      p: projectPoint(v, cam, this.cssW, this.cssH),
    }));
  }

  #hitVert(mx, my) {
    const pts = this.#projectedVerts();
    let best = -1;
    let bestD = 10;
    pts.forEach((pt, i) => {
      if (!pt.p.ok) return;
      const d = Math.hypot(mx - pt.p.sx, my - pt.p.sy);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    });
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
    const vi = this.#hitVert(p.x, p.y);
    if (vi >= 0) {
      this.opts.beginUndo?.();
      const additive = e.shiftKey;
      this.opts.onSelectVert?.(vi, additive);
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const v = enemy.frames[frame][vi];
      this.drag = { kind: "vert", index: vi, orig: { ...v }, start: p };
      this.canvas.setPointerCapture(e.pointerId);
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
      this.hover = this.#hitVert(p.x, p.y);
      this.draw();
      return;
    }
    if (this.drag.kind === "orbit") {
      const dx = p.x - this.drag.last.x;
      const dy = p.y - this.drag.last.y;
      this.drag.last = p;
      this.orbit.yaw += dx * 0.01;
      this.orbit.pitch = Math.max(-1.2, Math.min(1.2, this.orbit.pitch + dy * 0.01));
      this.draw();
      return;
    }
    if (this.drag.kind === "vert") {
      const enemy = this.opts.getEnemy();
      const frame = this.opts.getFrame();
      const v = enemy.frames[frame][this.drag.index];
      const cam = this.#cam();
      const { right, up } = lookVectors(cam.yaw, cam.pitch);
      const dx = (p.x - this.drag.start.x) / 8;
      const dy = -(p.y - this.drag.start.y) / 8;
      v.x = clampVert(this.drag.orig.x + right.x * dx + up.x * dy);
      v.y = clampVert(this.drag.orig.y + right.y * dx + up.y * dy);
      v.z = clampVert(this.drag.orig.z + right.z * dx + up.z * dy);
      this.opts.onChange?.();
      this.draw();
    }
  }

  #onUp(e) {
    if (!this.enabled) return;
    if (this.drag?.kind === "vert") this.opts.endUndo?.();
    this.drag = null;
    try {
      this.canvas.releasePointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    this.draw();
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

    ctx.strokeStyle = "#3d4658";
    const step = 8;
    const strokeSeg = (p0, p1, col) => {
      const seg = projectLine(p0, p1, cam, w, h);
      if (!seg) return;
      if (col) ctx.strokeStyle = col;
      ctx.beginPath();
      ctx.moveTo(seg.ax, seg.ay);
      ctx.lineTo(seg.bx, seg.by);
      ctx.stroke();
    };
    for (let i = -24; i <= 24; i += step) {
      strokeSeg({ x: i, y: 0, z: -24 }, { x: i, y: 0, z: 24 });
      strokeSeg({ x: -24, y: 0, z: i }, { x: 24, y: 0, z: i });
    }
    const axes = [
      [{ x: -20, y: 0, z: 0 }, { x: 20, y: 0, z: 0 }, "#a66"],
      [{ x: 0, y: 0, z: 0 }, { x: 0, y: 24, z: 0 }, "#6a6"],
      [{ x: 0, y: 0, z: -20 }, { x: 0, y: 0, z: 20 }, "#66a"],
    ];
    for (const [a, b, col] of axes) strokeSeg(a, b, col);

    ctx.lineWidth = 1.5;
    ctx.strokeStyle = "#c8ccd4";
    for (const [i, j] of enemy.lines) {
      strokeSeg(verts[i], verts[j], "#c8ccd4");
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

    ctx.fillStyle = "#8b91a0";
    ctx.font = "11px Segoe UI, sans-serif";
    ctx.fillText(
      `${enemy.name} · ${FRAME_NAMES[frame]} · ${enemy.verts}/${MAX_VERTS} verts  ${VERT_MIN}..${VERT_MAX}`,
      8,
      16
    );
  }
}
