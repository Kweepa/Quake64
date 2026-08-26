import {
  WEAPON_SPRITE_H,
  WEAPON_SPRITE_W,
  projectedWeaponEdges,
  rasterWeaponFrame,
} from "./mdl.js";

const ONION = "rgba(180, 170, 140, 0.28)";
const CURRENT = "#e8e4d8";
const OVERLAY = "rgba(212, 160, 23, 0.9)";
const GRID = "rgba(255, 255, 255, 0.06)";

export class WeaponView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.enabled = false;
    this.drag = null;
    this.cssW = 0;
    this.cssH = 0;
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

  #layout() {
    const w = this.cssW;
    const h = this.cssH;
    const cell = Math.min(w / (WEAPON_SPRITE_W * 2.15), h / (WEAPON_SPRITE_H * 2.15));
    const ow = WEAPON_SPRITE_W * cell;
    const oh = WEAPON_SPRITE_H * cell;
    return {
      cell,
      ox: (w - ow) / 2,
      oy: (h - oh) / 2,
      ow,
      oh,
    };
  }

  #eventPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * this.cssW,
      y: ((e.clientY - rect.top) / rect.height) * this.cssH,
    };
  }

  #toCanvas(layout, x, y) {
    return { x: layout.ox + x * layout.cell, y: layout.oy + y * layout.cell };
  }

  #onWheel(e) {
    if (!this.enabled) return;
    e.preventDefault();
    const cur = this.opts.getScale();
    const next = Math.max(0.05, Math.min(8, cur * (e.deltaY > 0 ? 0.92 : 1.08)));
    if (Math.abs(next - cur) < 1e-6) return;
    this.opts.beginUndo?.();
    this.opts.setScale(next);
    this.opts.endUndo?.();
    this.opts.onChange?.();
    this.opts.onPanEnd?.();
    this.draw();
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    if (e.button !== 0) return;
    const p = this.#eventPos(e);
    const pan = this.opts.getPan();
    this.opts.beginUndo?.();
    this.drag = { kind: "pan", last: p, pan: { x: pan.x, y: pan.y } };
    this.canvas.setPointerCapture(e.pointerId);
  }

  #onMove(e) {
    if (!this.enabled || !this.drag || this.drag.kind !== "pan") return;
    const p = this.#eventPos(e);
    const layout = this.#layout();
    const dx = (p.x - this.drag.last.x) / layout.cell;
    const dy = (p.y - this.drag.last.y) / layout.cell;
    this.drag.last = p;
    this.drag.pan = { x: this.drag.pan.x + dx, y: this.drag.pan.y + dy };
    this.opts.setPan(this.drag.pan.x, this.drag.pan.y);
    this.opts.onChange?.();
    this.draw();
  }

  #onUp() {
    if (!this.drag) return;
    const pan = this.drag.kind === "pan";
    this.drag = null;
    if (pan) {
      this.opts.endUndo?.();
      this.opts.onPanEnd?.();
    }
  }

  #strokeSegs(ctx, layout, segs, color, width) {
    ctx.strokeStyle = color;
    ctx.lineWidth = width;
    ctx.beginPath();
    for (const s of segs) {
      const a = this.#toCanvas(layout, s.ax, s.ay);
      const b = this.#toCanvas(layout, s.bx, s.by);
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
    }
    ctx.stroke();
  }

  drawPreview() {
    const canvas = this.opts.previewCanvas;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    const scale = 6;
    canvas.width = WEAPON_SPRITE_W * scale;
    canvas.height = WEAPON_SPRITE_H * scale;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    const mdl = this.opts.getMdl?.();
    if (!mdl) return;
    const { pixels } = rasterWeaponFrame(
      mdl,
      this.opts.getPreviewFrame(),
      this.opts.getScale(),
      this.opts.getPan()
    );
    ctx.fillStyle = "#e8e4d8";
    for (let y = 0; y < WEAPON_SPRITE_H; y++) {
      for (let x = 0; x < WEAPON_SPRITE_W; x++) {
        if (!pixels[y * WEAPON_SPRITE_W + x]) continue;
        ctx.fillRect(x * scale, y * scale, scale, scale);
      }
    }
    ctx.strokeStyle = "rgba(212, 160, 23, 0.5)";
    ctx.strokeRect(0.5, 0.5, canvas.width - 1, canvas.height - 1);
    ctx.strokeStyle = "rgba(255,255,255,0.12)";
    ctx.beginPath();
    ctx.moveTo(24 * scale + 0.5, 0);
    ctx.lineTo(24 * scale + 0.5, canvas.height);
    ctx.moveTo(0, 21 * scale + 0.5);
    ctx.lineTo(canvas.width, 21 * scale + 0.5);
    ctx.stroke();
  }

  draw() {
    if (!this.enabled) return;
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);

    const layout = this.#layout();
    ctx.fillStyle = "rgba(212, 160, 23, 0.06)";
    ctx.fillRect(layout.ox, layout.oy, layout.ow, layout.oh);
    ctx.strokeStyle = GRID;
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = 1; x < WEAPON_SPRITE_W; x++) {
      const px = layout.ox + x * layout.cell;
      ctx.moveTo(px, layout.oy);
      ctx.lineTo(px, layout.oy + layout.oh);
    }
    for (let y = 1; y < WEAPON_SPRITE_H; y++) {
      const py = layout.oy + y * layout.cell;
      ctx.moveTo(layout.ox, py);
      ctx.lineTo(layout.ox + layout.ow, py);
    }
    ctx.stroke();
    ctx.strokeStyle = OVERLAY;
    ctx.lineWidth = 1.5;
    ctx.strokeRect(layout.ox + 0.5, layout.oy + 0.5, layout.ow - 1, layout.oh - 1);
    ctx.strokeStyle = "rgba(212, 160, 23, 0.35)";
    ctx.beginPath();
    ctx.moveTo(layout.ox + 24 * layout.cell, layout.oy);
    ctx.lineTo(layout.ox + 24 * layout.cell, layout.oy + layout.oh);
    ctx.moveTo(layout.ox, layout.oy + 21 * layout.cell);
    ctx.lineTo(layout.ox + layout.ow, layout.oy + 21 * layout.cell);
    ctx.stroke();

    const mdl = this.opts.getMdl?.();
    if (!mdl) {
      ctx.fillStyle = "#8b91a0";
      ctx.font = "13px Segoe UI, sans-serif";
      ctx.fillText("Open shareware (pak0.pak) to load view-models", 16, 28);
      this.drawPreview();
      return;
    }

    const scale = this.opts.getScale();
    const pan = this.opts.getPan();
    const current = this.opts.getPreviewFrame();
    const onion = this.opts.getOnionFrames?.() || [];
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (const fi of onion) {
      if (fi === current) continue;
      const { segs } = projectedWeaponEdges(mdl, fi, scale, pan);
      this.#strokeSegs(ctx, layout, segs, ONION, 1);
    }
    const { segs } = projectedWeaponEdges(mdl, current, scale, pan);
    this.#strokeSegs(ctx, layout, segs, CURRENT, 1.4);

    ctx.fillStyle = OVERLAY;
    ctx.font = "11px Segoe UI, sans-serif";
    ctx.fillText("48×42", layout.ox + 4, layout.oy - 6);

    this.drawPreview();
  }
}
