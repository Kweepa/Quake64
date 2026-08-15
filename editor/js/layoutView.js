import {
  KINDS,
  aabbCenter,
  clampObject,
  objectVisible,
  WORLD_SIZE,
} from "./model.js";
import {
  BOX_CORNERS,
  BOX_EDGES,
  cornerWorld,
  distPointToSegment2d,
  faceCorners,
  intersectPlane,
  lookVectors,
  projectLine,
  projectPoint,
  rayAabb,
  screenRay,
} from "./math3d.js";

const HANDLE = 7;

export class LayoutView {
  /**
   * @param {HTMLCanvasElement} canvas
   * @param {object} opts
   */
  constructor(canvas, opts) {
    this.canvas = canvas;
    this.ctx = canvas.getContext("2d");
    this.opts = opts;
    this.camera = {
      x: 28,
      y: 10,
      z: -6,
      yaw: 0.35,
      pitch: -0.2,
      speed: 28,
    };
    this.keys = new Set();
    this.look = false;
    this.lastT = 0;
    this.hoverId = null;
    this.drag = null;
    this.enabled = true;
    this._ro = new ResizeObserver(() => this.resize());
    this._ro.observe(opts.stage || canvas.parentElement);
    this.resize();

    canvas.addEventListener("pointerdown", (e) => this.#onDown(e));
    canvas.addEventListener("pointermove", (e) => this.#onMove(e));
    canvas.addEventListener("pointerup", (e) => this.#onUp(e));
    canvas.addEventListener("pointerleave", (e) => this.#onUp(e));
    canvas.addEventListener("wheel", (e) => this.#onWheel(e), { passive: false });
    canvas.addEventListener("contextmenu", (e) => e.preventDefault());
    window.addEventListener("keydown", (e) => this.#onKey(e, true));
    window.addEventListener("keyup", (e) => this.#onKey(e, false));

    this._raf = (t) => {
      if (this.enabled) this.#tick(t);
      else this.lastT = t;
      requestAnimationFrame(this._raf);
    };
    requestAnimationFrame(this._raf);
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

  #focused() {
    return document.activeElement === this.canvas;
  }

  #onKey(e, down) {
    if (!this.enabled) return;
    if (!this.#focused() && down) return;
    const k = e.key.toLowerCase();
    if ("wasdqe".includes(k) || k === "shift") {
      if (down) this.keys.add(k);
      else this.keys.delete(k);
      if (down) e.preventDefault();
    }
  }

  #tick(t) {
    const dt = this.lastT ? Math.min(0.05, (t - this.lastT) / 1000) : 0;
    this.lastT = t;
    if (this.#focused()) {
      const { forward, right, up } = lookVectors(this.camera.yaw, this.camera.pitch);
      const boost = this.keys.has("shift") ? 3 : 1;
      const sp = this.camera.speed * boost * dt;
      if (this.keys.has("w")) {
        this.camera.x += forward.x * sp;
        this.camera.y += forward.y * sp;
        this.camera.z += forward.z * sp;
      }
      if (this.keys.has("s")) {
        this.camera.x -= forward.x * sp;
        this.camera.y -= forward.y * sp;
        this.camera.z -= forward.z * sp;
      }
      if (this.keys.has("d")) {
        this.camera.x += right.x * sp;
        this.camera.y += right.y * sp;
        this.camera.z += right.z * sp;
      }
      if (this.keys.has("a")) {
        this.camera.x -= right.x * sp;
        this.camera.y -= right.y * sp;
        this.camera.z -= right.z * sp;
      }
      if (this.keys.has("e")) {
        this.camera.x += up.x * sp;
        this.camera.y += up.y * sp;
        this.camera.z += up.z * sp;
      }
      if (this.keys.has("q")) {
        this.camera.x -= up.x * sp;
        this.camera.y -= up.y * sp;
        this.camera.z -= up.z * sp;
      }
    }
    this.draw();
  }

  #eventPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * this.cssW,
      y: ((e.clientY - rect.top) / rect.height) * this.cssH,
    };
  }

  #onWheel(e) {
    if (!this.enabled || !this.#focused()) return;
    e.preventDefault();
    this.camera.speed = Math.max(6, Math.min(80, this.camera.speed + (e.deltaY > 0 ? -4 : 4)));
    this.opts.onStatus?.(`Fly speed ${this.camera.speed | 0}`);
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    const p = this.#eventPos(e);
    if (e.button === 2 || e.button === 1) {
      this.look = true;
      this.lookLast = p;
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;

    const doc = this.opts.getDoc();
    const selected = this.opts.getSelectedId?.();
    const hitHandle = selected ? this.#hitHandle(doc, selected, p.x, p.y) : null;
    if (hitHandle) {
      this.opts.beginUndo?.();
      const obj = doc.map.objects.find((o) => o.id === selected);
      this.drag = {
        kind: hitHandle.kind,
        axis: hitHandle.axis,
        corner: hitHandle.corner,
        start: p,
        orig: { ...obj },
        grab: hitHandle.world,
      };
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const hit = this.#pick(doc, p.x, p.y);
    this.opts.onSelect?.(hit?.id || null);
    if (hit) {
      this.opts.beginUndo?.();
      const obj = doc.map.objects.find((o) => o.id === hit.id);
      this.drag = {
        kind: "move",
        start: p,
        orig: { ...obj },
        grab: hit.point,
        planeN: lookVectors(this.camera.yaw, this.camera.pitch).forward,
      };
      this.canvas.setPointerCapture(e.pointerId);
    }
  }

  #onMove(e) {
    if (!this.enabled) return;
    const p = this.#eventPos(e);
    if (this.look) {
      const dx = p.x - this.lookLast.x;
      const dy = p.y - this.lookLast.y;
      this.lookLast = p;
      this.camera.yaw += dx * 0.008;
      this.camera.pitch = Math.max(-1.4, Math.min(1.4, this.camera.pitch - dy * 0.008));
      return;
    }
    if (this.drag) {
      this.#applyDrag(p);
      this.opts.onChange?.();
      return;
    }
    const doc = this.opts.getDoc();
    this.hoverId = this.#pick(doc, p.x, p.y)?.id || null;
  }

  #onUp(e) {
    if (!this.enabled) return;
    if (this.look) this.look = false;
    if (this.drag) {
      this.drag = null;
      this.opts.endUndo?.();
    }
    try {
      this.canvas.releasePointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
  }

  #applyDrag(p) {
    const doc = this.opts.getDoc();
    const obj = doc.map.objects.find((o) => o.id === this.drag.orig.id);
    if (!obj) return;
    const ray = screenRay(p.x, p.y, this.camera, this.cssW, this.cssH);
    const orig = this.drag.orig;

    if (this.drag.kind === "move") {
      const hit = intersectPlane(ray.origin, ray.dir, this.drag.grab, this.drag.planeN);
      if (!hit) return;
      const dx = Math.round(hit.point.x - this.drag.grab.x);
      const dy = Math.round(hit.point.y - this.drag.grab.y);
      const dz = Math.round(hit.point.z - this.drag.grab.z);
      obj.x = orig.x + dx;
      obj.y = orig.y + dy;
      obj.z = orig.z + dz;
      clampObject(obj);
      return;
    }

    if (this.drag.kind === "axis") {
      const axis = this.drag.axis;
      const n = { x: 0, y: 0, z: 0 };
      if (axis === "x") n.y = 1;
      else if (axis === "y") n.x = 1;
      else n.y = 1;
      const hit = intersectPlane(ray.origin, ray.dir, this.drag.grab, n);
      if (!hit) return;
      const delta = Math.round(hit.point[axis] - this.drag.grab[axis]);
      obj[axis] = orig[axis] + delta;
      clampObject(obj);
      return;
    }

    if (this.drag.kind === "scale") {
      const def = KINDS[obj.kind];
      if (def.fixed) return;
      const c = this.drag.corner;
      const opp = { x: c[0] ? orig.x : orig.x + orig.sx, y: c[1] ? orig.y : orig.y + orig.sy, z: c[2] ? orig.z : orig.z + orig.sz };
      const hit = intersectPlane(
        ray.origin,
        ray.dir,
        this.drag.grab,
        lookVectors(this.camera.yaw, this.camera.pitch).forward
      );
      if (!hit) return;
      const px = Math.round(hit.point.x);
      const py = Math.round(hit.point.y);
      const pz = Math.round(hit.point.z);
      const x0 = Math.min(opp.x, px);
      const y0 = Math.min(opp.y, py);
      const z0 = Math.min(opp.z, pz);
      const x1 = Math.max(opp.x, px);
      const y1 = Math.max(opp.y, py);
      const z1 = Math.max(opp.z, pz);
      obj.x = x0;
      obj.y = y0;
      obj.z = z0;
      obj.sx = Math.max(1, x1 - x0);
      obj.sy = Math.max(1, y1 - y0);
      obj.sz = Math.max(1, z1 - z0);
      clampObject(obj);
    }
  }

  #visibleObjects(doc) {
    const local = this.opts.getLocalMode?.() || false;
    const cam = this.camera;
    return doc.map.objects.filter((o) => objectVisible(doc, o, cam, local));
  }

  #pick(doc, mx, my) {
    const ray = screenRay(mx, my, this.camera, this.cssW, this.cssH);
    let best = null;
    for (const obj of this.#visibleObjects(doc)) {
      const hit = rayAabb(ray.origin, ray.dir, obj);
      if (!hit) continue;
      if (!best || hit.t < best.t) best = { id: obj.id, t: hit.t, point: hit.point };
    }
    return best;
  }

  #hitHandle(doc, id, mx, my) {
    const obj = doc.map.objects.find((o) => o.id === id);
    if (!obj) return null;
    const cam = this.camera;
    const w = this.cssW;
    const h = this.cssH;
    const c = aabbCenter(obj);
    const axes = [
      { axis: "x", p: { x: c.x + 8, y: c.y, z: c.z } },
      { axis: "y", p: { x: c.x, y: c.y + 8, z: c.z } },
      { axis: "z", p: { x: c.x, y: c.y, z: c.z + 8 } },
    ];
    const pc = projectPoint(c, cam, w, h);
    for (const a of axes) {
      const pa = projectPoint(a.p, cam, w, h);
      if (!pc.ok || !pa.ok) continue;
      if (distPointToSegment2d(mx, my, pc.sx, pc.sy, pa.sx, pa.sy) < 8) {
        return { kind: "axis", axis: a.axis, world: c };
      }
    }
    if (!KINDS[obj.kind].fixed) {
      for (let i = 0; i < 8; i++) {
        const cw = cornerWorld(obj, i);
        const pr = projectPoint(cw, cam, w, h);
        if (!pr.ok) continue;
        if (Math.hypot(mx - pr.sx, my - pr.sy) < HANDLE) {
          return { kind: "scale", corner: BOX_CORNERS[i], world: cw };
        }
      }
    }
    return null;
  }

  placeInFront(kind) {
    const { forward } = lookVectors(this.camera.yaw, this.camera.pitch);
    const dist = 12;
    return {
      x: Math.round(this.camera.x + forward.x * dist),
      y: Math.max(0, Math.round(this.camera.y + forward.y * dist - 3)),
      z: Math.round(this.camera.z + forward.z * dist),
    };
  }

  draw() {
    if (!this.enabled) return;
    const ctx = this.ctx;
    const w = this.cssW;
    const h = this.cssH;
    if (!w || !h) return;
    ctx.fillStyle = "#0a0a0c";
    ctx.fillRect(0, 0, w, h);

    const doc = this.opts.getDoc();
    const cam = this.camera;
    const selected = this.opts.getSelectedId?.();
    const local = this.opts.getLocalMode?.() || false;

    this.#drawGrid(ctx, cam, w, h);

    const objs = [...this.#visibleObjects(doc)].sort((a, b) => {
      const ca = aabbCenter(a);
      const cb = aabbCenter(b);
      const da = (ca.x - cam.x) ** 2 + (ca.y - cam.y) ** 2 + (ca.z - cam.z) ** 2;
      const db = (cb.x - cam.x) ** 2 + (cb.y - cam.y) ** 2 + (cb.z - cam.z) ** 2;
      return db - da;
    });

    for (const obj of objs) {
      const hi = obj.id === selected || obj.id === this.hoverId;
      this.#drawObject(ctx, obj, cam, w, h, hi, obj.id === selected);
    }

    ctx.fillStyle = "#8b91a0";
    ctx.font = "11px Segoe UI, sans-serif";
    ctx.fillText(
      `xyz ${cam.x | 0},${cam.y | 0},${cam.z | 0}  ${local ? "LOCAL" : "ALL"}  spd ${cam.speed | 0}`,
      8,
      16
    );
  }

  #drawGrid(ctx, cam, w, h) {
    ctx.lineWidth = 1;
    ctx.strokeStyle = "#3d4658";
    for (let i = 0; i <= WORLD_SIZE; i += 8) {
      this.#line3(ctx, { x: i, y: 0, z: 0 }, { x: i, y: 0, z: WORLD_SIZE }, cam, w, h);
      this.#line3(ctx, { x: 0, y: 0, z: i }, { x: WORLD_SIZE, y: 0, z: i }, cam, w, h);
    }
    ctx.strokeStyle = "#6a7388";
    for (let i = 0; i <= WORLD_SIZE; i += 32) {
      this.#line3(ctx, { x: i, y: 0, z: 0 }, { x: i, y: 0, z: WORLD_SIZE }, cam, w, h);
      this.#line3(ctx, { x: 0, y: 0, z: i }, { x: WORLD_SIZE, y: 0, z: i }, cam, w, h);
    }
    ctx.strokeStyle = "#9aa3b5";
    this.#line3(ctx, { x: 0, y: 0, z: 0 }, { x: WORLD_SIZE, y: 0, z: 0 }, cam, w, h);
    this.#line3(ctx, { x: 0, y: 0, z: 0 }, { x: 0, y: 0, z: WORLD_SIZE }, cam, w, h);
    this.#line3(ctx, { x: 0, y: 0, z: 0 }, { x: 0, y: WORLD_SIZE, z: 0 }, cam, w, h);
  }

  #line3(ctx, a, b, cam, w, h, color) {
    const seg = projectLine(a, b, cam, w, h);
    if (!seg) return;
    if (color) ctx.strokeStyle = color;
    ctx.beginPath();
    ctx.moveTo(seg.ax, seg.ay);
    ctx.lineTo(seg.bx, seg.by);
    ctx.stroke();
  }

  #drawObject(ctx, obj, cam, w, h, highlight, selected) {
    const color = highlight ? "#f2d36b" : KINDS[obj.kind].color;
    ctx.lineWidth = selected ? 2 : 1;
    ctx.strokeStyle = color;
    for (const [i, j] of BOX_EDGES) {
      this.#line3(ctx, cornerWorld(obj, i), cornerWorld(obj, j), cam, w, h);
    }
    this.#drawGlyphs(ctx, obj, cam, w, h, color);
    if (selected) this.#drawGizmo(ctx, obj, cam, w, h);
  }

  #drawGlyphs(ctx, obj, cam, w, h, color) {
    ctx.strokeStyle = color;
    if (obj.kind === "crate") {
      const f = faceCorners(obj.face || "+z");
      this.#line3(ctx, cornerWorld(obj, f[0]), cornerWorld(obj, f[2]), cam, w, h);
      this.#line3(ctx, cornerWorld(obj, f[1]), cornerWorld(obj, f[3]), cam, w, h);
    }
    if (obj.kind === "doorway") {
      const f = faceCorners(obj.face);
      this.#line3(ctx, cornerWorld(obj, f[0]), cornerWorld(obj, f[2]), cam, w, h);
    }
    if (obj.kind === "switch") {
      const f = faceCorners(obj.face);
      const a = cornerWorld(obj, f[0]);
      const b = cornerWorld(obj, f[1]);
      const c = cornerWorld(obj, f[2]);
      const d = cornerWorld(obj, f[3]);
      const apex = {
        x: (a.x + b.x + c.x + d.x) / 4,
        y: Math.max(a.y, b.y, c.y, d.y),
        z: (a.z + b.z + c.z + d.z) / 4,
      };
      const left = {
        x: (a.x + d.x) / 2,
        y: (a.y + d.y) / 2,
        z: (a.z + d.z) / 2,
      };
      const right = {
        x: (b.x + c.x) / 2,
        y: (b.y + c.y) / 2,
        z: (b.z + c.z) / 2,
      };
      this.#line3(ctx, apex, left, cam, w, h);
      this.#line3(ctx, left, right, cam, w, h);
      this.#line3(ctx, right, apex, cam, w, h);
    }
    if (obj.kind === "slope") {
      const lowY = obj.y;
      const highY = obj.y + obj.sy;
      let p0, p1, p2, p3;
      if (obj.axis === "x") {
        const x0 = obj.dir === 1 ? obj.x : obj.x + obj.sx;
        const x1 = obj.dir === 1 ? obj.x + obj.sx : obj.x;
        p0 = { x: x0, y: lowY, z: obj.z };
        p1 = { x: x0, y: lowY, z: obj.z + obj.sz };
        p2 = { x: x1, y: highY, z: obj.z + obj.sz };
        p3 = { x: x1, y: highY, z: obj.z };
      } else {
        const z0 = obj.dir === 1 ? obj.z : obj.z + obj.sz;
        const z1 = obj.dir === 1 ? obj.z + obj.sz : obj.z;
        p0 = { x: obj.x, y: lowY, z: z0 };
        p1 = { x: obj.x + obj.sx, y: lowY, z: z0 };
        p2 = { x: obj.x + obj.sx, y: highY, z: z1 };
        p3 = { x: obj.x, y: highY, z: z1 };
      }
      this.#line3(ctx, p0, p1, cam, w, h);
      this.#line3(ctx, p1, p2, cam, w, h);
      this.#line3(ctx, p2, p3, cam, w, h);
      this.#line3(ctx, p3, p0, cam, w, h);
      this.#line3(ctx, p0, p2, cam, w, h);
    }
  }

  #drawGizmo(ctx, obj, cam, w, h) {
    const c = aabbCenter(obj);
    this.#line3(ctx, c, { x: c.x + 8, y: c.y, z: c.z }, cam, w, h, "#e55");
    this.#line3(ctx, c, { x: c.x, y: c.y + 8, z: c.z }, cam, w, h, "#5e5");
    this.#line3(ctx, c, { x: c.x, y: c.y, z: c.z + 8 }, cam, w, h, "#55e");
    if (KINDS[obj.kind].fixed) return;
    ctx.fillStyle = "#f2d36b";
    for (let i = 0; i < 8; i++) {
      const pr = projectPoint(cornerWorld(obj, i), cam, w, h);
      if (!pr.ok) continue;
      ctx.fillRect(pr.sx - 3, pr.sy - 3, 6, 6);
    }
  }
}
