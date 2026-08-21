import {
  KINDS,
  currentRoom,
  localVisibleIds,
  neighbourRooms,
  activeMap,
  WORLD_SIZE,
  isGhostKind,
  colorHex,
  ROOM_BG_DEFAULT,
  ROOM_LINE_DEFAULT,
  roomGeometry,
} from "./model.js";
import { lookVectors } from "./math3d.js";

const ORTHO = {
  top: { u: "x", v: "z", su: "sx", sv: "sz", hint: "XZ · +Z up · camera arrow" },
  left: { u: "z", v: "y", su: "sz", sv: "sy", hint: "YZ · +Y up · camera arrow" },
  forward: { u: "x", v: "y", su: "sx", sv: "sy", hint: "XY · +Y up · camera arrow" },
};

function hexAlpha(hex, alpha) {
  const h = hex.replace("#", "");
  const r = parseInt(h.slice(0, 2), 16);
  const g = parseInt(h.slice(2, 4), 16);
  const b = parseInt(h.slice(4, 6), 16);
  return `rgba(${r},${g},${b},${alpha})`;
}

export class OverheadView {
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.mode = "top";
    this._ro = new ResizeObserver(() => this.resize());
    this._ro.observe(canvas.parentElement);
    this.resize();
  }

  setMode(mode) {
    if (!ORTHO[mode] || mode === this.mode) return;
    this.mode = mode;
    this.draw();
  }

  hint() {
    return ORTHO[this.mode].hint;
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
    const axes = ORTHO[this.mode];

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
    const selected = new Set(this.opts.getSelectedIds?.() || []);
    const primary = this.opts.getSelectedId?.();
    if (primary) selected.add(primary);

    const toScreen = (u, v) => ({ x: ox + u * s, y: oy + side - v * s });

    const drawBox = (obj, fill, stroke, lw = 1) => {
      const uw = obj[axes.su] * s;
      const vh = obj[axes.sv] * s;
      const p = toScreen(obj[axes.u], obj[axes.v] + obj[axes.sv]);
      ctx.lineWidth = lw;
      if (fill) {
        ctx.fillStyle = fill;
        ctx.fillRect(p.x, p.y, uw, vh);
      }
      ctx.strokeStyle = stroke;
      ctx.strokeRect(p.x, p.y, uw, vh);
    };

    const drawRoom = (obj, fill, stroke, lw = 1) => {
      const g = roomGeometry(obj);
      ctx.lineWidth = lw;
      for (const c of g.colliders) {
        const uw = c[axes.su] * s;
        const vh = c[axes.sv] * s;
        const p = toScreen(c[axes.u], c[axes.v] + c[axes.sv]);
        if (fill) {
          ctx.fillStyle = fill;
          ctx.fillRect(p.x, p.y, uw, vh);
        }
      }
      ctx.strokeStyle = stroke;
      for (const e of g.edges) {
        const a = g.verts[e.a];
        const b = g.verts[e.b];
        if (a[axes.u] === b[axes.u] && a[axes.v] === b[axes.v]) continue;
        const pa = toScreen(a[axes.u], a[axes.v]);
        const pb = toScreen(b[axes.u], b[axes.v]);
        ctx.beginPath();
        ctx.moveTo(pa.x, pa.y);
        ctx.lineTo(pb.x, pb.y);
        ctx.stroke();
      }
    };

    for (const obj of activeMap(doc).objects) {
      if (obj.kind !== "room") continue;
      const isCur = cur && obj.id === cur.id;
      const isN = neigh.some((n) => n.id === obj.id);
      const faded = vis && !vis.has(obj.id);
      const bgHex = colorHex(obj.bgColor ?? ROOM_BG_DEFAULT);
      const lineHex = colorHex(obj.lineColor ?? ROOM_LINE_DEFAULT);
      const fill = isCur
        ? hexAlpha(bgHex, 0.28)
        : isN
          ? hexAlpha(bgHex, 0.18)
          : hexAlpha(bgHex, 0.08);
      drawRoom(obj, fill, faded ? "#333" : lineHex, isCur ? 2 : 1);
    }

    for (const obj of activeMap(doc).objects) {
      if (obj.kind === "room") continue;
      const faded = vis && !vis.has(obj.id);
      const col = faded ? "#444" : KINDS[obj.kind].color;
      if (isGhostKind(obj.kind)) ctx.setLineDash([4, 3]);
      drawBox(obj, null, selected.has(obj.id) ? "#f2d36b" : col, selected.has(obj.id) ? 2 : 1);
      ctx.setLineDash([]);
    }

    const { forward } = lookVectors(cam.yaw, cam.pitch);
    const c = toScreen(cam[axes.u], cam[axes.v]);
    ctx.fillStyle = "#fff";
    ctx.beginPath();
    ctx.arc(c.x, c.y, 3, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = "#d4a017";
    ctx.beginPath();
    ctx.moveTo(c.x, c.y);
    ctx.lineTo(c.x + forward[axes.u] * 14, c.y - forward[axes.v] * 14);
    ctx.stroke();
  }
}
