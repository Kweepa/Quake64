import {
  KINDS,
  currentRoom,
  localVisibleIds,
  neighbourRooms,
  WORLD_SIZE,
} from "./model.js";
import { lookVectors } from "./math3d.js";

export class OverheadView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this._ro = new ResizeObserver(() => this.resize());
    this._ro.observe(canvas.parentElement);
    this.resize();
  }

  resize() {
    const parent = this.canvas.parentElement;
    const rect = parent.getBoundingClientRect();
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

  draw() {
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);

    const pad = 8;
    const side = Math.min(w, h) - pad * 2;
    const ox = (w - side) / 2;
    const oy = (h - side) / 2;
    const s = side / WORLD_SIZE;

    ctx.strokeStyle = "#8b91a0";
    ctx.strokeRect(ox, oy, side, side);
    ctx.strokeStyle = "#3d4658";
    for (let i = 0; i <= WORLD_SIZE; i += 8) {
      ctx.beginPath();
      ctx.moveTo(ox + i * s, oy);
      ctx.lineTo(ox + i * s, oy + side);
      ctx.moveTo(ox, oy + i * s);
      ctx.lineTo(ox + side, oy + i * s);
      ctx.stroke();
    }
    ctx.strokeStyle = "#6a7388";
    for (let i = 0; i <= WORLD_SIZE; i += 32) {
      ctx.beginPath();
      ctx.moveTo(ox + i * s, oy);
      ctx.lineTo(ox + i * s, oy + side);
      ctx.moveTo(ox, oy + i * s);
      ctx.lineTo(ox + side, oy + i * s);
      ctx.stroke();
    }

    const doc = this.opts.getDoc();
    const cam = this.opts.getCamera();
    const local = this.opts.getLocalMode?.() || false;
    const cur = currentRoom(doc, cam);
    const neigh = cur ? neighbourRooms(doc, cur) : [];
    const vis = local ? localVisibleIds(doc, cam) : null;
    const selected = this.opts.getSelectedId?.();

    const toScreen = (x, z) => ({ x: ox + x * s, y: oy + z * s });

    const drawBox = (obj, fill, stroke, lw = 1) => {
      const p = toScreen(obj.x, obj.z);
      ctx.lineWidth = lw;
      if (fill) {
        ctx.fillStyle = fill;
        ctx.fillRect(p.x, p.y, obj.sx * s, obj.sz * s);
      }
      ctx.strokeStyle = stroke;
      ctx.strokeRect(p.x, p.y, obj.sx * s, obj.sz * s);
    };

    for (const obj of doc.map.objects) {
      if (obj.kind !== "room") continue;
      const isCur = cur && obj.id === cur.id;
      const isN = neigh.some((n) => n.id === obj.id);
      const faded = vis && !vis.has(obj.id);
      drawBox(
        obj,
        isCur ? "rgba(212,160,23,0.28)" : isN ? "rgba(90,180,90,0.22)" : "rgba(200,204,212,0.08)",
        faded ? "#333" : KINDS.room.color,
        isCur ? 2 : 1
      );
    }

    for (const obj of doc.map.objects) {
      if (obj.kind === "room") continue;
      const faded = vis && !vis.has(obj.id);
      const col = faded ? "#444" : KINDS[obj.kind].color;
      drawBox(obj, null, obj.id === selected ? "#f2d36b" : col, obj.id === selected ? 2 : 1);
    }

    const { forward } = lookVectors(cam.yaw, cam.pitch);
    const c = toScreen(cam.x, cam.z);
    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.arc(c.x, c.y, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#d4a017";
    ctx.beginPath();
    ctx.moveTo(c.x, c.y);
    ctx.lineTo(c.x + forward.x * 14, c.y + forward.z * 14);
    ctx.stroke();
  }
}
