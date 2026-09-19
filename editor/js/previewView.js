import {
  ROOM_BG_DEFAULT,
  ROOM_LINE_DEFAULT,
  ROOM_WPN_DEFAULT,
  WORLD_MIN,
  WORLD_MAX,
  activeMap,
  clampDoorScale,
  clampEnemyRot,
  clampSlopeFlags,
  colorHex,
  enemyPlacementWorldVerts,
  findEnemyTemplate,
  figureTemplateName,
  isFigureObject,
  isGhostKind,
  itemMeshFor,
  itemMeshWorldSegs,
  localVisibleIds,
  pointInRoom,
  roomFloorY,
  roomGeometry,
  SLOPE_FLAG_BOTTOM,
  SLOPE_FLAG_TOP,
} from "./model.js";
import { BOX_EDGES, cornerWorld, NEAR, worldToCamera } from "./math3d.js";

/** Game unique-char viewport (24×16 chars). */
const GAME_VIEW_W = 192;
const GAME_VIEW_H = 128;
const GAME_FOCAL = 100;
/** Draw buffer = CSS frame (C64 1:1.2 PAR). */
export const PREVIEW_W = 320;
export const PREVIEW_H = 256;
export const PREVIEW_EYE = 3;
export const PREVIEW_FRAME_W = PREVIEW_W;
export const PREVIEW_FRAME_H = PREVIEW_H;
const PREVIEW_SX = PREVIEW_W / GAME_VIEW_W;
const PREVIEW_SY = PREVIEW_H / GAME_VIEW_H;
const PREVIEW_FX = GAME_FOCAL * PREVIEW_SX;
const PREVIEW_FY = GAME_FOCAL * PREVIEW_SY;

const NAIL_W = 48;
const NAIL_H = 42;
/** Viewport-relative top-left in game pixels: sprite (160,214). */
const NAIL_VX = 72;
const NAIL_VY = 92;

/** FACE_PZ/MZ/PX/MX → yaw so local +Z points out of the door face (door_face_rot). */
const PV_DOOR_YAW = {
  "+z": 0,
  "-z": Math.PI,
  "+x": (192 / 256) * Math.PI * 2,
  "-x": (64 / 256) * Math.PI * 2,
};

function pvRampCorners(obj) {
  const lowY = obj.y;
  const highY = obj.y + obj.sy;
  if (obj.axis === "x") {
    const x0 = obj.dir === 1 ? obj.x : obj.x + obj.sx;
    const x1 = obj.dir === 1 ? obj.x + obj.sx : obj.x;
    return {
      p0: { x: x0, y: lowY, z: obj.z },
      p1: { x: x0, y: lowY, z: obj.z + obj.sz },
      p2: { x: x1, y: highY, z: obj.z + obj.sz },
      p3: { x: x1, y: highY, z: obj.z },
    };
  }
  const z0 = obj.dir === 1 ? obj.z : obj.z + obj.sz;
  const z1 = obj.dir === 1 ? obj.z + obj.sz : obj.z;
  return {
    p0: { x: obj.x, y: lowY, z: z0 },
    p1: { x: obj.x + obj.sx, y: lowY, z: z0 },
    p2: { x: obj.x + obj.sx, y: highY, z: z1 },
    p3: { x: obj.x, y: highY, z: z1 },
  };
}

/** Game ramp: hypotenuses always; flags add low/high horizontals. */
function pvSlopeSegs(obj) {
  const { p0, p1, p2, p3 } = pvRampCorners(obj);
  const segs = [
    { a: p1, b: p2 },
    { a: p3, b: p0 },
  ];
  const flags = clampSlopeFlags(obj.flags);
  if (flags & SLOPE_FLAG_BOTTOM) segs.push({ a: p0, b: p1 });
  if (flags & SLOPE_FLAG_TOP) segs.push({ a: p2, b: p3 });
  return segs;
}

/** Game platform: top plane only (cooked plat_y = y+sy). */
function pvPlatTopSegs(obj) {
  const y = (obj.y | 0) + (obj.sy | 0);
  const x0 = obj.x;
  const z0 = obj.z;
  const x1 = obj.x + obj.sx;
  const z1 = obj.z + obj.sz;
  const a = { x: x0, y, z: z0 };
  const b = { x: x1, y, z: z0 };
  const c = { x: x1, y, z: z1 };
  const d = { x: x0, y, z: z1 };
  return [
    { a, b },
    { a: b, b: c },
    { a: c, b: d },
    { a: d, b: a },
  ];
}

function pvDoorOrigin(obj) {
  const face = obj.face || "+z";
  const yaw = PV_DOOR_YAW[face] ?? 0;
  if (face === "+x") return { x: obj.x + obj.sx, y: obj.y, z: obj.z + obj.sz / 2, yaw };
  if (face === "-x") return { x: obj.x, y: obj.y, z: obj.z + obj.sz / 2, yaw };
  if (face === "-z") return { x: obj.x + obj.sx / 2, y: obj.y, z: obj.z, yaw };
  return { x: obj.x + obj.sx / 2, y: obj.y, z: obj.z + obj.sz, yaw };
}

/** Type mesh on the outward face (local X across, Y up, Z thickness). */
function pvDoorMeshSegs(obj, mesh) {
  const m = mesh?.verts?.length ? mesh : null;
  if (!m) return [];
  const o = pvDoorOrigin(obj);
  const s = clampDoorScale(obj.doorScale);
  const c = Math.cos(o.yaw);
  const sn = Math.sin(o.yaw);
  const verts = m.verts.map((v) => {
    const lx = (v.x | 0) * s;
    const ly = (v.y | 0) * s;
    const lz = v.z | 0;
    return {
      x: o.x + lx * c + lz * sn,
      y: o.y + ly,
      z: o.z - lx * sn + lz * c,
    };
  });
  const segs = [];
  for (const [ia, ib] of m.lines || []) {
    if (verts[ia] && verts[ib]) segs.push({ a: verts[ia], b: verts[ib] });
  }
  return segs;
}

function pvProjectCam(c) {
  return {
    sx: PREVIEW_W * 0.5 + (c.x / c.z) * PREVIEW_FX,
    sy: PREVIEW_H * 0.5 - (c.y / c.z) * PREVIEW_FY,
  };
}

function pvProjectLine(a, b, cam) {
  const ca = worldToCamera(a, cam);
  const cb = worldToCamera(b, cam);
  if (ca.z < NEAR && cb.z < NEAR) return null;
  let pa = ca;
  let pb = cb;
  if (ca.z < NEAR || cb.z < NEAR) {
    const t = (NEAR - ca.z) / (cb.z - ca.z);
    const clip = {
      x: ca.x + t * (cb.x - ca.x),
      y: ca.y + t * (cb.y - ca.y),
      z: NEAR,
    };
    if (ca.z < NEAR) pa = clip;
    else pb = clip;
  }
  const sa = pvProjectCam(pa);
  const sb = pvProjectCam(pb);
  return { ax: sa.sx, ay: sa.sy, bx: sb.sx, by: sb.sy };
}

function pvDisableSmoothing(ctx) {
  ctx.imageSmoothingEnabled = false;
  ctx.webkitImageSmoothingEnabled = false;
  ctx.mozImageSmoothingEnabled = false;
  ctx.msImageSmoothingEnabled = false;
}

function pvSpawnCam(spawn) {
  const rot = clampEnemyRot(spawn.rot);
  return {
    x: (spawn.x | 0) + 1,
    y: (spawn.y | 0) + PREVIEW_EYE,
    z: (spawn.z | 0) + 1,
    yaw: (rot * Math.PI) / 4,
    pitch: 0,
  };
}

function pvDefaultCam(room) {
  const g = roomGeometry(room);
  const cols = g.colliders?.length ? g.colliders : [g.outer];
  let x = 0;
  let z = 0;
  for (const c of cols) {
    x += c.x + c.sx / 2;
    z += c.z + c.sz / 2;
  }
  x /= cols.length;
  z /= cols.length;
  return {
    x,
    y: roomFloorY(room, x, z) + PREVIEW_EYE,
    z,
    yaw: 0,
    pitch: 0,
  };
}

function pvParseHex(hex) {
  const h = (hex || "#000000").replace("#", "");
  return {
    r: parseInt(h.slice(0, 2), 16) || 0,
    g: parseInt(h.slice(2, 4), 16) || 0,
    b: parseInt(h.slice(4, 6), 16) || 0,
  };
}

function pvTryStep(room, x, y, z) {
  if (x < WORLD_MIN || x > WORLD_MAX || z < WORLD_MIN || z > WORLD_MAX) return false;
  return pointInRoom({ x, y, z }, room);
}

export class PreviewView {
  /**
   * @param {HTMLCanvasElement} canvas
   * @param {{
   *   getDoc: () => any,
   *   getRoom: () => any,
   *   getSpawn: () => any,
   *   getEditSpawn?: () => any,
   *   onRotate?: (yaw: number) => void,
   *   onMove?: (x: number, z: number) => void,
   *   onEditStart?: () => void,
   *   onEditEnd?: () => void,
   *   onChange?: () => void,
   *   nailImg?: HTMLImageElement | null,
   * }} opts
   */
  constructor(canvas, opts) {
    this.display = canvas;
    this.frame = canvas.parentElement;
    this.dctx = canvas.getContext("2d", { alpha: false });
    this.buffer = document.createElement("canvas");
    this.buffer.width = PREVIEW_W;
    this.buffer.height = PREVIEW_H;
    this.ctx = this.buffer.getContext("2d", { alpha: false });
    this.opts = opts;
    this.dragging = false;
    this.lastX = 0;
    this.lastY = 0;
    this.live = null;
    this.stickyCam = null;
    this.nailTints = new Map();
    pvDisableSmoothing(this.ctx);
    pvDisableSmoothing(this.dctx);

    canvas.addEventListener("pointerdown", (e) => this.#onPointer(e));
    canvas.addEventListener("pointermove", (e) => this.#onPointer(e));
    canvas.addEventListener("pointerup", (e) => this.#onPointer(e));
    canvas.addEventListener("lostpointercapture", (e) => this.#onPointer(e));

    this._ro = new ResizeObserver(() => this.draw());
    if (this.frame) this._ro.observe(this.frame);

    const nail = opts.nailImg;
    if (nail && !nail.complete) {
      nail.addEventListener("load", () => {
        this.nailTints.clear();
        this.draw();
      });
    }
  }

  #editSpawn() {
    if (this.opts.getEditSpawn) return this.opts.getEditSpawn() || null;
    return this.opts.getSpawn?.() || null;
  }

  #forgetSticky(room) {
    if (this.#editSpawn()) {
      this.stickyCam = null;
      return;
    }
    if (this.stickyCam && (!room || this.stickyCam.roomId !== room.id)) {
      this.stickyCam = null;
    }
  }

  #cam(room, spawn) {
    if (this.dragging && this.live) return this.live;
    this.#forgetSticky(room);
    if (this.#editSpawn() && spawn) return pvSpawnCam(spawn);
    if (this.stickyCam) {
      this.stickyCam.cam.pitch = 0;
      return this.stickyCam.cam;
    }
    if (spawn) return pvSpawnCam(spawn);
    if (!room) return null;
    const cam = pvDefaultCam(room);
    cam.pitch = 0;
    return cam;
  }

  #onPointer(e) {
    const room = this.opts.getRoom?.();
    const spawn = this.#editSpawn();
    const viewSpawn = this.opts.getSpawn?.() || null;
    if (!room) return;

    if (e.type === "pointerdown") {
      if (e.button != null && e.button !== 0) return;
      this.dragging = true;
      this.dragMoved = false;
      this.live = { ...this.#cam(room, viewSpawn) };
      this.lastX = e.clientX;
      this.lastY = e.clientY;
      if (spawn) this.opts.onEditStart?.();
      try {
        e.currentTarget.setPointerCapture(e.pointerId);
      } catch {
        /* ignore */
      }
      return;
    }

    if (e.type === "pointerup" || e.type === "lostpointercapture") {
      if (this.dragging) {
        if (spawn) this.opts.onEditEnd?.();
        else if (this.dragMoved && this.live && room) {
          this.stickyCam = { roomId: room.id, cam: { ...this.live } };
        }
      }
      this.dragging = false;
      this.live = null;
      this.draw();
      return;
    }

    if (e.type !== "pointermove" || !this.dragging || !this.live) return;

    const dx = e.clientX - this.lastX;
    const dy = e.clientY - this.lastY;
    if (dx || dy) this.dragMoved = true;
    this.lastX = e.clientX;
    this.lastY = e.clientY;
    const rect = this.display.getBoundingClientRect();
    const w = rect.width || PREVIEW_FRAME_W;
    const h = rect.height || PREVIEW_FRAME_H;
    const cam = this.live;

    if (dx) {
      cam.yaw += dx * (Math.PI / w);
      if (spawn) this.opts.onRotate?.(cam.yaw);
    }
    if (dy) {
      const walkSens = 8 / h;
      const forward = -dy * walkSens;
      const nx = cam.x + Math.sin(cam.yaw) * forward;
      const nz = cam.z + Math.cos(cam.yaw) * forward;
      const y = spawn ? cam.y : roomFloorY(room, nx, nz) + PREVIEW_EYE;
      const yx = spawn ? cam.y : roomFloorY(room, nx, cam.z) + PREVIEW_EYE;
      const yz = spawn ? cam.y : roomFloorY(room, cam.x, nz) + PREVIEW_EYE;
      if (pvTryStep(room, nx, y, nz)) {
        cam.x = nx;
        cam.z = nz;
        cam.y = y;
        if (spawn) this.opts.onMove?.(cam.x, cam.z);
      } else if (pvTryStep(room, nx, yx, cam.z)) {
        cam.x = nx;
        cam.y = yx;
        if (spawn) this.opts.onMove?.(cam.x, cam.z);
      } else if (pvTryStep(room, cam.x, yz, nz)) {
        cam.z = nz;
        cam.y = yz;
        if (spawn) this.opts.onMove?.(cam.x, cam.z);
      }
    }
    if (spawn && (dx || dy)) this.opts.onChange?.();
    this.draw();
  }

  #stroke(ctx, cam, a, b, color) {
    const seg = pvProjectLine(a, b, cam);
    if (!seg) return;
    ctx.beginPath();
    ctx.strokeStyle = color;
    ctx.lineWidth = 1.5;
    ctx.moveTo(seg.ax + 0.5, seg.ay + 0.5);
    ctx.lineTo(seg.bx + 0.5, seg.by + 0.5);
    ctx.stroke();
  }

  #drawObject(ctx, doc, obj, cam, color) {
    if (obj.kind === "doorway") {
      const mesh = itemMeshFor(doc, obj.doorType);
      for (const seg of pvDoorMeshSegs(obj, mesh)) {
        this.#stroke(ctx, cam, seg.a, seg.b, color);
      }
      return;
    }
    if (obj.kind === "platform") {
      for (const seg of pvPlatTopSegs(obj)) {
        this.#stroke(ctx, cam, seg.a, seg.b, color);
      }
      return;
    }
    if (obj.kind === "pickup") {
      const mesh = itemMeshFor(doc, obj.pickup);
      for (const seg of itemMeshWorldSegs(obj, mesh)) {
        this.#stroke(ctx, cam, seg.a, seg.b, color);
      }
      return;
    }
    if (obj.kind === "slope") {
      for (const seg of pvSlopeSegs(obj)) {
        this.#stroke(ctx, cam, seg.a, seg.b, color);
      }
      return;
    }
    if (isFigureObject(obj)) {
      const tmpl = findEnemyTemplate(doc, figureTemplateName(obj));
      const verts = enemyPlacementWorldVerts(obj, tmpl);
      if (tmpl && verts.length) {
        for (const [i, j] of tmpl.lines) {
          if (verts[i] && verts[j]) this.#stroke(ctx, cam, verts[i], verts[j], color);
        }
      }
      return;
    }
    for (const [i, j] of BOX_EDGES) {
      this.#stroke(ctx, cam, cornerWorld(obj, i), cornerWorld(obj, j), color);
    }
  }

  #nailTint(hex) {
    const img = this.opts.nailImg;
    if (!img?.complete || !img.naturalWidth) return null;
    let tint = this.nailTints.get(hex);
    if (tint) return tint;
    const c = document.createElement("canvas");
    c.width = NAIL_W;
    c.height = NAIL_H;
    const ctx = c.getContext("2d");
    ctx.imageSmoothingEnabled = false;
    ctx.drawImage(img, 0, 0);
    const data = ctx.getImageData(0, 0, NAIL_W, NAIL_H);
    const px = data.data;
    const { r, g, b } = pvParseHex(hex);
    for (let i = 0; i < px.length; i += 4) {
      if (px[i] > 16 || px[i + 1] > 16 || px[i + 2] > 16) {
        px[i] = r;
        px[i + 1] = g;
        px[i + 2] = b;
        px[i + 3] = 255;
      } else {
        px[i + 3] = 0;
      }
    }
    ctx.putImageData(data, 0, 0);
    this.nailTints.set(hex, c);
    return c;
  }

  #drawNail(ctx, room) {
    const hex = colorHex(room.weaponColor ?? ROOM_WPN_DEFAULT);
    const tint = this.#nailTint(hex);
    if (!tint) return;
    const dx = NAIL_VX * PREVIEW_SX;
    const dy = NAIL_VY * PREVIEW_SY;
    const dw = NAIL_W * PREVIEW_SX;
    const dh = NAIL_H * PREVIEW_SY;
    const clipH = Math.min(dh, PREVIEW_H - dy);
    if (clipH <= 0) return;
    const srcH = NAIL_H * (clipH / dh);
    ctx.imageSmoothingEnabled = true;
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(tint, 0, 0, NAIL_W, srcH, dx, dy, dw, clipH);
  }

  #present() {
    const frame = this.frame || this.display;
    const rect = frame.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const outW = Math.max(1, Math.round(rect.width * dpr));
    const outH = Math.max(1, Math.round(rect.height * dpr));
    if (this.display.width !== outW || this.display.height !== outH) {
      this.display.width = outW;
      this.display.height = outH;
    }
    const dctx = this.dctx;
    pvDisableSmoothing(dctx);
    dctx.fillStyle = "#000";
    dctx.fillRect(0, 0, outW, outH);
    dctx.drawImage(this.buffer, 0, 0, PREVIEW_W, PREVIEW_H, 0, 0, outW, outH);
  }

  hint() {
    const room = this.opts.getRoom?.();
    if (this.#editSpawn()) return "Spawn view — drag L/R to set angle · U/D to move";
    if (this.stickyCam) return "Drag L/R to rotate · U/D to walk";
    if (this.opts.getSpawn?.()) return "Spawn view";
    if (room) return "Drag L/R to rotate · U/D to walk";
    return "Select a room";
  }

  draw() {
    const ctx = this.ctx;
    const doc = this.opts.getDoc?.();
    const room = this.opts.getRoom?.();
    const spawn = this.opts.getSpawn?.() || null;
    this.#forgetSticky(room);
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    pvDisableSmoothing(ctx);
    ctx.fillStyle = room ? colorHex(room.bgColor ?? ROOM_BG_DEFAULT) : "#000000";
    ctx.fillRect(0, 0, PREVIEW_W, PREVIEW_H);

    if (doc && room) {
      const cam = this.#cam(room, spawn);
      const line = colorHex(room.lineColor ?? ROOM_LINE_DEFAULT);
      const g = roomGeometry(room);
      for (const e of g.edges) {
        this.#stroke(ctx, cam, g.verts[e.a], g.verts[e.b], line);
      }
      const ids = localVisibleIds(doc, room, false);
      const roomsOnly = !!this.opts.getRoomsOnlyMode?.();
      for (const obj of activeMap(doc).objects) {
        if (!ids.has(obj.id)) continue;
        if (roomsOnly) {
          if (obj.kind !== "doorway") continue;
        } else if (obj.kind === "room" || obj.kind === "spawn" || isGhostKind(obj.kind)) {
          continue;
        }
        this.#drawObject(ctx, doc, obj, cam, line);
      }
      this.#drawNail(ctx, room);
    }

    this.#present();
    const hint = document.getElementById("preview-hint");
    if (hint) hint.textContent = this.hint();
  }
}
