import {
  KINDS,
  aabbCenter,
  clampObject,
  objectVisible,
  activeMap,
  WORLD_SIZE,
  enemyPlacementWorldVerts,
  findEnemyTemplate,
  isFigureObject,
  isGhostKind,
  figureTemplateName,
  roomsOf,
  clampEnemyRot,
  colorHex,
  ROOM_LINE_DEFAULT,
  roomGeometry,
  preserveRoomSplits,
  applyRoomSplitDelta,
  assignDoorRooms,
  snapSwitchToRoom,
  roomFloorY,
  roomById,
  itemMeshFor,
  itemMeshWorldSegs,
  elevStopBottoms,
} from "./model.js";
import {
  BOX_CORNERS,
  BOX_EDGES,
  cornerWorld,
  closestTOnSegment2d,
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
const LINE_HIT = 8;
const LAYOUT_BOX_CLICK = 4;
const ZOOM_K = 0.008;

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
    this.orbit = null;
    this.pan = null;
    this.zoom = null;
    this.lastT = 0;
    this.hoverId = null;
    this.drag = null;
    this.gridY = 0;
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
    canvas.addEventListener("mousedown", (e) => {
      if (e.button === 1) e.preventDefault();
    });
    canvas.addEventListener("auxclick", (e) => {
      if (e.button === 1) e.preventDefault();
    });
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
    let moved = false;
    if (this.#focused()) {
      const { forward, right, up } = lookVectors(this.camera.yaw, this.camera.pitch);
      const boost = this.keys.has("shift") ? 3 : 1;
      const sp = this.camera.speed * boost * dt;
      if (this.keys.has("w")) {
        this.camera.x += forward.x * sp;
        this.camera.y += forward.y * sp;
        this.camera.z += forward.z * sp;
        moved = true;
      }
      if (this.keys.has("s")) {
        this.camera.x -= forward.x * sp;
        this.camera.y -= forward.y * sp;
        this.camera.z -= forward.z * sp;
        moved = true;
      }
      if (this.keys.has("d")) {
        this.camera.x += right.x * sp;
        this.camera.y += right.y * sp;
        this.camera.z += right.z * sp;
        moved = true;
      }
      if (this.keys.has("a")) {
        this.camera.x -= right.x * sp;
        this.camera.y -= right.y * sp;
        this.camera.z -= right.z * sp;
        moved = true;
      }
      if (this.keys.has("e")) {
        this.camera.x += up.x * sp;
        this.camera.y += up.y * sp;
        this.camera.z += up.z * sp;
        moved = true;
      }
      if (this.keys.has("q")) {
        this.camera.x -= up.x * sp;
        this.camera.y -= up.y * sp;
        this.camera.z -= up.z * sp;
        moved = true;
      }
    }
    if (moved) this.opts.onViewChanged?.();
    this.draw();
  }

  #eventPos(e) {
    const rect = this.canvas.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * this.cssW,
      y: ((e.clientY - rect.top) / rect.height) * this.cssH,
    };
  }

  #selectedIds() {
    return this.opts.getSelectedIds?.() || [];
  }

  #primaryId() {
    const ids = this.#selectedIds();
    return ids.length ? ids[ids.length - 1] : null;
  }

  #onWheel(e) {
    if (!this.enabled) return;
    e.preventDefault();
    this.canvas.focus();
    const { forward } = lookVectors(this.camera.yaw, this.camera.pitch);
    const notches = e.deltaY / 100;
    const dist = -notches * this.camera.speed * 0.35;
    this.camera.x += forward.x * dist;
    this.camera.y += forward.y * dist;
    this.camera.z += forward.z * dist;
    this.opts.onViewChanged?.();
    this.draw();
  }

  #onDown(e) {
    if (!this.enabled) return;
    this.canvas.focus();
    const p = this.#eventPos(e);
    if (e.button === 1) {
      if (e.altKey) {
        this.orbit = this.#beginOrbit(p);
      } else {
        this.pan = this.#beginOrbit(p);
      }
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button === 2) {
      if (e.altKey) {
        this.zoom = this.#beginOrbit(p);
        this.canvas.setPointerCapture(e.pointerId);
        return;
      }
      this.look = true;
      this.lookLast = p;
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }
    if (e.button !== 0) return;
    if (e.altKey) {
      e.preventDefault();
      this.orbit = this.#beginOrbit(p);
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    const doc = this.opts.getDoc();
    const primary = this.#primaryId();
    const hitHandle = primary ? this.#hitHandle(doc, primary, p.x, p.y) : null;
    if (hitHandle) {
      this.opts.beginUndo?.();
      const ids = this.#selectedIds().length ? this.#selectedIds() : [primary];
      this.drag = this.#makeTransformDrag(doc, ids, hitHandle, p);
      this.canvas.setPointerCapture(e.pointerId);
      return;
    }

    this.drag = { kind: "box", start: p, end: p, additive: e.shiftKey };
    this.canvas.setPointerCapture(e.pointerId);
  }

  #makeTransformDrag(doc, ids, handle, p) {
    const objs = activeMap(doc).objects;
    const origs = ids
      .map((id) => objs.find((o) => o.id === id))
      .filter(Boolean)
      .map((o) => ({
        ...o,
        cuts: (o.cuts || []).map((c) => ({ su: c.su | 0, sv: c.sv | 0 })),
      }));
    const contents = [];
    const claimed = new Set(ids);
    for (const o of origs) {
      if (o.kind !== "room") continue;
      for (const other of objs) {
        if (other.kind === "room" || other.kind === "doorway" || claimed.has(other.id)) continue;
        if (other.roomId !== o.id) continue;
        claimed.add(other.id);
        contents.push({ ...other });
      }
    }
    return {
      kind: handle.kind,
      axis: handle.axis,
      corner: handle.corner,
      key: handle.key,
      side: handle.side,
      scale: handle.scale,
      start: p,
      origs,
      contents,
      grab: handle.world,
      planeN: lookVectors(this.camera.yaw, this.camera.pitch).forward,
      primaryId: ids[ids.length - 1],
    };
  }

  #beginOrbit(p) {
    const cam = this.camera;
    const doc = this.opts.getDoc();
    const id = this.#primaryId();
    const obj = id ? activeMap(doc).objects.find((o) => o.id === id) : null;
    let dist = Math.max(48, cam.speed * 2.5);
    if (obj) {
      const c = aabbCenter(obj);
      dist = Math.hypot(c.x - cam.x, c.y - cam.y, c.z - cam.z);
      if (dist < 1) dist = 1;
    } else {
      const ray = screenRay(p.x, p.y, cam, this.cssW, this.cssH);
      const hit = intersectPlane(ray.origin, ray.dir, { x: 0, y: this.gridY, z: 0 }, { x: 0, y: 1, z: 0 });
      if (hit && hit.t >= 1) dist = Math.min(400, Math.max(24, hit.t));
    }
    return { last: p, dist };
  }

  #applyOrbit(p) {
    const o = this.orbit;
    const cam = this.camera;
    const dx = p.x - o.last.x;
    const dy = p.y - o.last.y;
    o.last = p;
    if (!dx && !dy) return;

    const dist = o.dist;
    const { forward } = lookVectors(cam.yaw, cam.pitch);
    const px = cam.x + forward.x * dist;
    const py = cam.y + forward.y * dist;
    const pz = cam.z + forward.z * dist;
    cam.yaw += dx * 0.008;
    cam.pitch = Math.max(-1.4, Math.min(1.4, cam.pitch - dy * 0.008));
    const f2 = lookVectors(cam.yaw, cam.pitch).forward;
    cam.x = px - f2.x * dist;
    cam.y = py - f2.y * dist;
    cam.z = pz - f2.z * dist;
  }

  #applyPan(p) {
    const pan = this.pan;
    const cam = this.camera;
    const dx = p.x - pan.last.x;
    const dy = p.y - pan.last.y;
    pan.last = p;
    if (!dx && !dy) return;

    const focal = Math.min(this.cssW, this.cssH) * 0.9;
    const scale = pan.dist / focal;
    const { right, up } = lookVectors(cam.yaw, cam.pitch);
    cam.x += (-right.x * dx + up.x * dy) * scale;
    cam.y += (-right.y * dx + up.y * dy) * scale;
    cam.z += (-right.z * dx + up.z * dy) * scale;
  }

  #applyZoom(p) {
    const z = this.zoom;
    const dx = p.x - z.last.x;
    const dy = p.y - z.last.y;
    z.last = p;
    const delta = dx + dy;
    if (!delta) return;

    const cam = this.camera;
    const { forward } = lookVectors(cam.yaw, cam.pitch);
    const px = cam.x + forward.x * z.dist;
    const py = cam.y + forward.y * z.dist;
    const pz = cam.z + forward.z * z.dist;
    z.dist = Math.max(1, z.dist * Math.exp(-delta * ZOOM_K));
    cam.x = px - forward.x * z.dist;
    cam.y = py - forward.y * z.dist;
    cam.z = pz - forward.z * z.dist;
  }

  #onMove(e) {
    if (!this.enabled) return;
    const p = this.#eventPos(e);
    if (this.orbit) {
      this.#applyOrbit(p);
      return;
    }
    if (this.pan) {
      this.#applyPan(p);
      return;
    }
    if (this.zoom) {
      this.#applyZoom(p);
      return;
    }
    if (this.look) {
      const dx = p.x - this.lookLast.x;
      const dy = p.y - this.lookLast.y;
      this.lookLast = p;
      this.camera.yaw += dx * 0.008;
      this.camera.pitch = Math.max(-1.4, Math.min(1.4, this.camera.pitch - dy * 0.008));
      return;
    }
    if (this.drag?.kind === "box") {
      this.drag.end = p;
      this.draw();
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
    const viewEnded = this.look || this.orbit || this.pan || this.zoom;
    if (this.look) this.look = false;
    if (this.orbit) this.orbit = null;
    if (this.pan) this.pan = null;
    if (this.zoom) this.zoom = null;
    if (this.drag?.kind === "box") this.#finishBox();
    else if (this.drag && this.drag.kind !== "select") {
      this.#finishTransform();
      this.opts.endUndo?.();
    }
    this.drag = null;
    if (viewEnded) this.opts.onViewChanged?.();
    try {
      this.canvas.releasePointerCapture(e.pointerId);
    } catch {
      /* ignore */
    }
    this.draw();
  }

  #finishTransform() {
    const d = this.drag;
    if (!d || (d.kind !== "move" && d.kind !== "axis")) return;
    const doc = this.opts.getDoc();
    const objs = activeMap(doc).objects;
    for (const orig of d.origs) {
      const obj = objs.find((o) => o.id === orig.id);
      if (!obj) continue;
      if (obj.kind === "doorway") {
        assignDoorRooms(doc, obj, roomById(doc, obj.roomId));
        clampObject(obj);
      } else if (obj.kind === "switch") {
        snapSwitchToRoom(obj, roomById(doc, obj.roomId));
        clampObject(obj);
      }
    }
  }

  #axisDelta(p, grab, axis, start) {
    const along = { x: grab.x, y: grab.y, z: grab.z };
    along[axis] += 8;
    const pa = projectPoint(grab, this.camera, this.cssW, this.cssH);
    const pb = projectPoint(along, this.camera, this.cssW, this.cssH);
    if (!pa.ok || !pb.ok) return null;
    const ax = pb.sx - pa.sx;
    const ay = pb.sy - pa.sy;
    const alen2 = ax * ax + ay * ay;
    if (alen2 < 16) return null;
    const t = ((p.x - start.x) * ax + (p.y - start.y) * ay) / alen2;
    return Math.round(t * 8);
  }

  #applyFaceDelta(obj, orig, side, delta) {
    const min = 1;
    obj.x = orig.x;
    obj.y = orig.y;
    obj.z = orig.z;
    obj.sx = orig.sx;
    obj.sy = orig.sy;
    obj.sz = orig.sz;
    if (side === "x1") obj.sx = Math.max(min, orig.sx + delta);
    else if (side === "x0") {
      const x1 = orig.x + orig.sx;
      obj.x = Math.min(x1 - min, orig.x + delta);
      obj.sx = x1 - obj.x;
    } else if (side === "y1") obj.sy = Math.max(min, orig.sy + delta);
    else if (side === "y0") {
      const y1 = orig.y + orig.sy;
      obj.y = Math.min(y1 - min, orig.y + delta);
      obj.sy = y1 - obj.y;
    } else if (side === "z1") obj.sz = Math.max(min, orig.sz + delta);
    else if (side === "z0") {
      const z1 = orig.z + orig.sz;
      obj.z = Math.min(z1 - min, orig.z + delta);
      obj.sz = z1 - obj.z;
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

  #finishBox() {
    const rect = this.#boxRect();
    const additive = this.drag.additive;
    if (rect.w < LAYOUT_BOX_CLICK && rect.h < LAYOUT_BOX_CLICK) {
      const hit = this.#pick(this.opts.getDoc(), this.drag.start.x, this.drag.start.y);
      if (hit) {
        if (additive) this.opts.onToggleSelect?.(hit.id);
        else this.opts.onSelectIds?.([hit.id]);
      } else if (!additive) {
        this.opts.onSelectIds?.([]);
      }
      return;
    }
    const doc = this.opts.getDoc();
    const cam = this.camera;
    const w = this.cssW;
    const h = this.cssH;
    const hits = [];
    for (const obj of this.#visibleObjects(doc)) {
      let inside = false;
      for (let i = 0; i < 8; i++) {
        const pr = projectPoint(cornerWorld(obj, i), cam, w, h);
        if (!pr.ok) continue;
        if (pr.sx >= rect.x0 && pr.sx <= rect.x1 && pr.sy >= rect.y0 && pr.sy <= rect.y1) {
          inside = true;
          break;
        }
      }
      if (!inside) {
        const c = projectPoint(aabbCenter(obj), cam, w, h);
        if (c.ok && c.sx >= rect.x0 && c.sx <= rect.x1 && c.sy >= rect.y0 && c.sy <= rect.y1) {
          inside = true;
        }
      }
      if (inside) hits.push(obj.id);
    }
    this.opts.onSelectIds?.(hits, additive);
  }

  #applyDrag(p) {
    const doc = this.opts.getDoc();
    const objs = activeMap(doc).objects;
    const ray = screenRay(p.x, p.y, this.camera, this.cssW, this.cssH);
    const d = this.drag;

    if (d.kind === "move") {
      const hit = intersectPlane(ray.origin, ray.dir, d.grab, d.planeN);
      if (!hit) return;
      const dx = Math.round(hit.point.x - d.grab.x);
      const dy = Math.round(hit.point.y - d.grab.y);
      const dz = Math.round(hit.point.z - d.grab.z);
      for (const orig of d.origs) {
        const obj = objs.find((o) => o.id === orig.id);
        if (!obj) continue;
        obj.x = orig.x + dx;
        obj.y = orig.y + dy;
        obj.z = orig.z + dz;
        clampObject(obj);
      }
      for (const orig of d.contents) {
        const obj = objs.find((o) => o.id === orig.id);
        if (!obj) continue;
        obj.x = orig.x + dx;
        obj.y = orig.y + dy;
        obj.z = orig.z + dz;
        clampObject(obj);
      }
      return;
    }

    if (d.kind === "axis") {
      const delta = this.#axisDelta(p, d.grab, d.axis, d.start);
      if (delta == null) return;
      for (const orig of d.origs) {
        const obj = objs.find((o) => o.id === orig.id);
        if (!obj) continue;
        obj[d.axis] = orig[d.axis] + delta;
        clampObject(obj);
      }
      for (const orig of d.contents) {
        const obj = objs.find((o) => o.id === orig.id);
        if (!obj) continue;
        obj[d.axis] = orig[d.axis] + delta;
        clampObject(obj);
      }
      return;
    }

    if (d.kind === "scale") {
      const primary = d.origs.find((o) => o.id === d.primaryId) || d.origs[0];
      if (!primary || KINDS[primary.kind].fixed) return;
      const obj = objs.find((o) => o.id === primary.id);
      if (!obj) return;
      const c = d.corner;
      const opp = {
        x: c[0] ? primary.x : primary.x + primary.sx,
        y: c[1] ? primary.y : primary.y + primary.sy,
        z: c[2] ? primary.z : primary.z + primary.sz,
      };
      const hit = intersectPlane(ray.origin, ray.dir, d.grab, d.planeN);
      if (!hit) return;
      const px = Math.round(hit.point.x);
      const py = Math.round(hit.point.y);
      const pz = Math.round(hit.point.z);
      obj.x = Math.min(opp.x, px);
      obj.y = Math.min(opp.y, py);
      obj.z = Math.min(opp.z, pz);
      obj.sx = Math.max(1, Math.max(opp.x, px) - obj.x);
      obj.sy = Math.max(1, Math.max(opp.y, py) - obj.y);
      obj.sz = Math.max(1, Math.max(opp.z, pz) - obj.z);
      if (obj.kind === "room") preserveRoomSplits(obj, primary);
      clampObject(obj);
      return;
    }

    if (d.kind === "split") {
      const orig = d.origs.find((o) => o.id === d.primaryId) || d.origs[0];
      const obj = objs.find((o) => o.id === orig.id);
      if (!obj || obj.kind !== "room") return;
      const delta = this.#axisDelta(p, d.grab, d.axis, d.start);
      if (delta == null) return;
      applyRoomSplitDelta(obj, orig, d.key, delta * (d.scale || 1));
      clampObject(obj);
      return;
    }

    if (d.kind === "face") {
      const orig = d.origs.find((o) => o.id === d.primaryId) || d.origs[0];
      const obj = objs.find((o) => o.id === orig.id);
      if (!obj || KINDS[obj.kind].fixed) return;
      const delta = this.#axisDelta(p, d.grab, d.axis, d.start);
      if (delta == null) return;
      this.#applyFaceDelta(obj, orig, d.side, delta);
      if (obj.kind === "room") preserveRoomSplits(obj, orig);
      clampObject(obj);
    }
  }

  #visibleObjects(doc) {
    const local = this.opts.getLocalMode?.() || false;
    const focus = this.opts.getFocusRoom?.() || null;
    const neighbours = !!(local && this.opts.getNeighbourMode?.());
    return activeMap(doc).objects.filter((o) => objectVisible(doc, o, local, focus, neighbours));
  }

  #objectSegments(doc, obj) {
    /** @type {{a:{x:number,y:number,z:number},b:{x:number,y:number,z:number}}[]} */
    const segs = [];
    if (obj.kind === "room") {
      const g = roomGeometry(obj);
      for (const e of g.edges) {
        segs.push({ a: g.verts[e.a], b: g.verts[e.b] });
      }
      return segs;
    }
    if (isFigureObject(obj)) {
      const tmpl = findEnemyTemplate(doc, figureTemplateName(obj));
      const verts = enemyPlacementWorldVerts(obj, tmpl);
      if (tmpl && verts.length) {
        for (const [i, j] of tmpl.lines) {
          if (verts[i] && verts[j]) segs.push({ a: verts[i], b: verts[j] });
        }
      }
      for (const [i, j] of BOX_EDGES) {
        segs.push({ a: cornerWorld(obj, i), b: cornerWorld(obj, j) });
      }
      return segs;
    }
    if (obj.kind === "platform") {
      const y = (obj.y | 0) + (obj.sy | 0);
      segs.push(
        { a: { x: obj.x, y, z: obj.z }, b: { x: obj.x + obj.sx, y, z: obj.z } },
        { a: { x: obj.x + obj.sx, y, z: obj.z }, b: { x: obj.x + obj.sx, y, z: obj.z + obj.sz } },
        { a: { x: obj.x + obj.sx, y, z: obj.z + obj.sz }, b: { x: obj.x, y, z: obj.z + obj.sz } },
        { a: { x: obj.x, y, z: obj.z + obj.sz }, b: { x: obj.x, y, z: obj.z } }
      );
      return segs;
    }
    if (obj.kind === "pickup") {
      const mesh = itemMeshFor(doc, obj.pickup);
      for (const s of itemMeshWorldSegs(obj, mesh)) segs.push(s);
      return segs;
    }
    for (const [i, j] of BOX_EDGES) {
      segs.push({ a: cornerWorld(obj, i), b: cornerWorld(obj, j) });
    }
    for (const s of this.#glyphSegments(obj)) segs.push(s);
    return segs;
  }

  #glyphSegments(obj) {
    const segs = [];
    if (obj.kind === "doorway") {
      const zThin = (obj.sz | 0) <= (obj.sx | 0);
      if (zThin) {
        segs.push({ a: cornerWorld(obj, 0), b: cornerWorld(obj, 2) });
        segs.push({ a: cornerWorld(obj, 4), b: cornerWorld(obj, 6) });
      } else {
        segs.push({ a: cornerWorld(obj, 0), b: cornerWorld(obj, 7) });
        segs.push({ a: cornerWorld(obj, 1), b: cornerWorld(obj, 6) });
      }
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
      const left = { x: (a.x + d.x) / 2, y: (a.y + d.y) / 2, z: (a.z + d.z) / 2 };
      const right = { x: (b.x + c.x) / 2, y: (b.y + c.y) / 2, z: (b.z + c.z) / 2 };
      segs.push({ a: apex, b: left }, { a: left, b: right }, { a: right, b: apex });
    }
    if (obj.kind === "trigger") {
      segs.push(
        { a: cornerWorld(obj, 0), b: cornerWorld(obj, 5) },
        { a: cornerWorld(obj, 1), b: cornerWorld(obj, 4) }
      );
    }
    if (obj.kind === "teleporter_dest") {
      const c = aabbCenter(obj);
      const rot = clampEnemyRot(obj.rot ?? 0);
      const th = (rot * Math.PI) / 4;
      const fx = Math.sin(th);
      const fz = Math.cos(th);
      segs.push(
        { a: c, b: { x: c.x + fx * 4, y: c.y, z: c.z + fz * 4 } },
        {
          a: { x: c.x + fx * 4, y: c.y, z: c.z + fz * 4 },
          b: { x: c.x + fx * 2 - fz * 1.5, y: c.y, z: c.z + fz * 2 + fx * 1.5 },
        },
        {
          a: { x: c.x + fx * 4, y: c.y, z: c.z + fz * 4 },
          b: { x: c.x + fx * 2 + fz * 1.5, y: c.y, z: c.z + fz * 2 - fx * 1.5 },
        }
      );
    }
    if (obj.kind === "slope") {
      const ramp = this.#rampCorners(obj);
      segs.push(
        { a: ramp.p1, b: ramp.p2 },
        { a: ramp.p3, b: ramp.p0 }
      );
    }
    return segs;
  }

  #rampCorners(obj) {
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

  #pick(doc, mx, my) {
    const cam = this.camera;
    const w = this.cssW;
    const h = this.cssH;
    let bestLine = null;
    for (const obj of this.#visibleObjects(doc)) {
      for (const seg of this.#objectSegments(doc, obj)) {
        const pl = projectLine(seg.a, seg.b, cam, w, h);
        if (!pl) continue;
        const d = distPointToSegment2d(mx, my, pl.ax, pl.ay, pl.bx, pl.by);
        if (d > LINE_HIT) continue;
        const mid = {
          x: (seg.a.x + seg.b.x) / 2,
          y: (seg.a.y + seg.b.y) / 2,
          z: (seg.a.z + seg.b.z) / 2,
        };
        const depth =
          (mid.x - cam.x) ** 2 + (mid.y - cam.y) ** 2 + (mid.z - cam.z) ** 2;
        if (!bestLine || d < bestLine.d - 0.01 || (Math.abs(d - bestLine.d) < 0.01 && depth < bestLine.depth)) {
          bestLine = { id: obj.id, d, depth, point: mid };
        }
      }
    }
    if (bestLine) return { id: bestLine.id, t: bestLine.depth, point: bestLine.point };

    const ray = screenRay(mx, my, cam, w, h);
    let best = null;
    for (const obj of this.#visibleObjects(doc)) {
      if (obj.kind === "room") {
        const g = roomGeometry(obj);
        for (const c of g.colliders) {
          const hit = rayAabb(ray.origin, ray.dir, c);
          if (hit && (!best || hit.t < best.t)) best = { id: obj.id, t: hit.t, point: hit.point };
        }
        continue;
      }
      const hit = rayAabb(ray.origin, ray.dir, obj);
      if (!hit) continue;
      if (!best || hit.t < best.t) best = { id: obj.id, t: hit.t, point: hit.point };
    }
    return best;
  }

  #hitHandle(doc, id, mx, my) {
    const obj = activeMap(doc).objects.find((o) => o.id === id);
    if (!obj) return null;
    const cam = this.camera;
    const w = this.cssW;
    const h = this.cssH;
    if (obj.kind === "room") {
      const g = roomGeometry(obj);
      for (const handle of g.handles) {
        const pr = projectPoint(handle.world, cam, w, h);
        if (!pr.ok) continue;
        if (Math.hypot(mx - pr.sx, my - pr.sy) < HANDLE + 2) {
          if (handle.kind === "face") {
            return { kind: "face", side: handle.side, axis: handle.axis, world: handle.world };
          }
          return { kind: "split", key: handle.key, axis: handle.axis, scale: handle.scale, world: handle.world };
        }
      }
    } else if (!KINDS[obj.kind].fixed) {
      for (const handle of this.#aabbFaceHandles(obj)) {
        const pr = projectPoint(handle.world, cam, w, h);
        if (!pr.ok) continue;
        if (Math.hypot(mx - pr.sx, my - pr.sy) < HANDLE + 2) {
          return { kind: "face", side: handle.side, axis: handle.axis, world: handle.world };
        }
      }
    }
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
        const t = closestTOnSegment2d(mx, my, pc.sx, pc.sy, pa.sx, pa.sy);
        return {
          kind: "axis",
          axis: a.axis,
          world: {
            x: c.x + (a.p.x - c.x) * t,
            y: c.y + (a.p.y - c.y) * t,
            z: c.z + (a.p.z - c.z) * t,
          },
        };
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

  /** Drop position from screen coords: selected room floor, else grid plane. */
  placeAtScreen(mx, my, kind) {
    const doc = this.opts.getDoc();
    const ray = screenRay(mx, my, this.camera, this.cssW, this.cssH);
    const def = KINDS[kind] || KINDS.crate;
    const sx = def.defaultSize[0];
    const sz = def.defaultSize[2];
    const placeRoom = kind === "room" || kind === "doorway" ? null : this.opts.getPlaceRoom?.() || null;
    if (placeRoom) {
      const g = roomGeometry(placeRoom);
      let bestHit = null;
      for (const c of g.colliders) {
        const hit = rayAabb(ray.origin, ray.dir, c);
        if (hit && hit.t >= 0 && (!bestHit || hit.t < bestHit.t)) bestHit = hit;
      }
      const fy = roomFloorY(placeRoom, placeRoom.x + placeRoom.sx / 2, placeRoom.z + placeRoom.sz / 2);
      const floor = intersectPlane(ray.origin, ray.dir, { x: 0, y: fy, z: 0 }, { x: 0, y: 1, z: 0 });
      const pt = floor?.point || bestHit?.point || aabbCenter(placeRoom);
      return {
        x: Math.round(pt.x - sx / 2),
        y: fy,
        z: Math.round(pt.z - sz / 2),
      };
    }
    if (kind !== "doorway") {
      let bestRoom = null;
      let bestT = Infinity;
      for (const room of roomsOf(doc)) {
        const g = roomGeometry(room);
        for (const c of g.colliders) {
          const hit = rayAabb(ray.origin, ray.dir, c);
          if (!hit || hit.t < 0 || hit.t >= bestT) continue;
          bestT = hit.t;
          bestRoom = { room, point: hit.point };
        }
      }
      if (bestRoom) {
        const fy = roomFloorY(bestRoom.room, bestRoom.point.x, bestRoom.point.z);
        const floor = intersectPlane(ray.origin, ray.dir, { x: 0, y: fy, z: 0 }, { x: 0, y: 1, z: 0 });
        const pt = floor?.point || bestRoom.point;
        return {
          x: Math.round(pt.x - sx / 2),
          y: fy,
          z: Math.round(pt.z - sz / 2),
        };
      }
    }
    const gy = this.gridY;
    const floor = intersectPlane(ray.origin, ray.dir, { x: 0, y: gy, z: 0 }, { x: 0, y: 1, z: 0 });
    if (floor) {
      return {
        x: Math.round(floor.point.x - sx / 2),
        y: gy,
        z: Math.round(floor.point.z - sz / 2),
      };
    }
    const { forward } = lookVectors(this.camera.yaw, this.camera.pitch);
    return {
      x: Math.round(this.camera.x + forward.x * 12 - sx / 2),
      y: gy,
      z: Math.round(this.camera.z + forward.z * 12 - sz / 2),
    };
  }

  /** Keep look; put selection in view center. Pull back to frame if closer than that. */
  focusSelection() {
    const ids = this.#selectedIds();
    if (!ids.length) return false;
    const doc = this.opts.getDoc();
    const objs = ids
      .map((id) => activeMap(doc).objects.find((o) => o.id === id))
      .filter(Boolean);
    if (!objs.length) return false;

    let minx = Infinity;
    let miny = Infinity;
    let minz = Infinity;
    let maxx = -Infinity;
    let maxy = -Infinity;
    let maxz = -Infinity;
    for (const o of objs) {
      minx = Math.min(minx, o.x);
      miny = Math.min(miny, o.y);
      minz = Math.min(minz, o.z);
      maxx = Math.max(maxx, o.x + o.sx);
      maxy = Math.max(maxy, o.y + o.sy);
      maxz = Math.max(maxz, o.z + o.sz);
    }
    const box = { x: minx, y: miny, z: minz, sx: maxx - minx, sy: maxy - miny, sz: maxz - minz };
    const center = aabbCenter(box);
    const cam = this.camera;
    const { forward, right, up } = lookVectors(cam.yaw, cam.pitch);
    const w = this.cssW;
    const h = this.cssH;
    const focal = Math.min(w, h) * 0.9;
    const pad = 0.82;
    const halfW = Math.max(1, w * 0.5 * pad);
    const halfH = Math.max(1, h * 0.5 * pad);

    let frameDist = 4;
    for (let i = 0; i < 8; i++) {
      const c = cornerWorld(box, i);
      const rx = c.x - center.x;
      const ry = c.y - center.y;
      const rz = c.z - center.z;
      const cx = rx * right.x + ry * right.y + rz * right.z;
      const cy = rx * up.x + ry * up.y + rz * up.z;
      const cz = rx * forward.x + ry * forward.y + rz * forward.z;
      frameDist = Math.max(frameDist, (Math.abs(cx) * focal) / halfW - cz);
      frameDist = Math.max(frameDist, (Math.abs(cy) * focal) / halfH - cz);
      frameDist = Math.max(frameDist, 1 - cz);
    }

    const currentDist = Math.hypot(cam.x - center.x, cam.y - center.y, cam.z - center.z);
    const dist = Math.max(frameDist, currentDist);
    cam.x = center.x - forward.x * dist;
    cam.y = center.y - forward.y * dist;
    cam.z = center.z - forward.z * dist;
    this.opts.onViewChanged?.();
    this.draw();
    return true;
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
    const selected = new Set(this.#selectedIds());
    if (this.drag?.kind === "box") {
      const r = this.#boxRect();
      if (r.w >= LAYOUT_BOX_CLICK || r.h >= LAYOUT_BOX_CLICK) {
        for (const obj of this.#visibleObjects(doc)) {
          for (let i = 0; i < 8; i++) {
            const pr = projectPoint(cornerWorld(obj, i), cam, w, h);
            if (pr.ok && pr.sx >= r.x0 && pr.sx <= r.x1 && pr.sy >= r.y0 && pr.sy <= r.y1) {
              selected.add(obj.id);
              break;
            }
          }
        }
      }
    }
    const local = this.opts.getLocalMode?.() || false;
    const neighbours = !!(local && this.opts.getNeighbourMode?.());
    const tag = local ? (neighbours ? "LOCAL+N" : "LOCAL") : "ALL";
    const primary = this.#primaryId();
    this.#syncGridY(doc);

    this.#drawGrid(ctx, cam, w, h);

    const objs = [...this.#visibleObjects(doc)].sort((a, b) => {
      const ca = aabbCenter(a);
      const cb = aabbCenter(b);
      const da = (ca.x - cam.x) ** 2 + (ca.y - cam.y) ** 2 + (ca.z - cam.z) ** 2;
      const db = (cb.x - cam.x) ** 2 + (cb.y - cam.y) ** 2 + (cb.z - cam.z) ** 2;
      return db - da;
    });

    for (const obj of objs) {
      const sel = selected.has(obj.id);
      const hi = sel || obj.id === this.hoverId;
      this.#drawObject(ctx, doc, obj, cam, w, h, hi, sel, obj.id === primary);
    }

    const selIds = this.#selectedIds();
    if (selIds.length === 1) {
      const elev = objs.find((o) => o.id === selIds[0] && o.kind === "elevator");
      if (elev) this.#drawElevDestGhosts(ctx, doc, elev, cam, w, h);
    }

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
    ctx.fillText(
      `xyz ${cam.x | 0},${cam.y | 0},${cam.z | 0}  ${tag}  spd ${cam.speed | 0}`,
      8,
      16
    );
  }

  #syncGridY(doc) {
    const id = this.#primaryId();
    if (!id) return;
    const obj = activeMap(doc).objects.find((o) => o.id === id);
    if (obj?.kind === "room") this.gridY = obj.y;
  }

  #drawGrid(ctx, cam, w, h) {
    const y = this.gridY;
    ctx.lineWidth = 1;
    ctx.strokeStyle = "#3d4658";
    for (let i = 0; i <= WORLD_SIZE; i += 8) {
      this.#line3(ctx, { x: i, y, z: 0 }, { x: i, y, z: WORLD_SIZE }, cam, w, h);
      this.#line3(ctx, { x: 0, y, z: i }, { x: WORLD_SIZE, y, z: i }, cam, w, h);
    }
    ctx.strokeStyle = "#6a7388";
    for (let i = 0; i <= WORLD_SIZE; i += 32) {
      this.#line3(ctx, { x: i, y, z: 0 }, { x: i, y, z: WORLD_SIZE }, cam, w, h);
      this.#line3(ctx, { x: 0, y, z: i }, { x: WORLD_SIZE, y, z: i }, cam, w, h);
    }
    ctx.strokeStyle = "#9aa3b5";
    this.#line3(ctx, { x: 0, y, z: 0 }, { x: WORLD_SIZE, y, z: 0 }, cam, w, h);
    this.#line3(ctx, { x: 0, y, z: 0 }, { x: 0, y, z: WORLD_SIZE }, cam, w, h);
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

  #drawObject(ctx, doc, obj, cam, w, h, highlight, selected, primary) {
    const color =
      highlight ? "#f2d36b" : obj.kind === "room" ? colorHex(obj.lineColor ?? ROOM_LINE_DEFAULT) : KINDS[obj.kind].color;
    ctx.lineWidth = selected ? 2 : 1;
    ctx.strokeStyle = color;

    if (isFigureObject(obj)) {
      ctx.globalAlpha = selected ? 0.35 : 0.2;
      for (const [i, j] of BOX_EDGES) {
        this.#line3(ctx, cornerWorld(obj, i), cornerWorld(obj, j), cam, w, h);
      }
      ctx.globalAlpha = 1;
      const tmpl = findEnemyTemplate(doc, figureTemplateName(obj));
      const verts = enemyPlacementWorldVerts(obj, tmpl);
      if (tmpl && verts.length) {
        ctx.lineWidth = selected ? 2 : 1.5;
        for (const [i, j] of tmpl.lines) {
          if (verts[i] && verts[j]) this.#line3(ctx, verts[i], verts[j], cam, w, h);
        }
      }
    } else if (obj.kind === "pickup") {
      const mesh = itemMeshFor(doc, obj.pickup);
      for (const seg of itemMeshWorldSegs(obj, mesh)) {
        this.#line3(ctx, seg.a, seg.b, cam, w, h);
      }
    } else if (obj.kind === "room") {
      const g = roomGeometry(obj);
      for (const e of g.edges) {
        this.#line3(ctx, g.verts[e.a], g.verts[e.b], cam, w, h);
      }
    } else {
      if (isGhostKind(obj.kind)) ctx.setLineDash([5, 4]);
      for (const [i, j] of BOX_EDGES) {
        this.#line3(ctx, cornerWorld(obj, i), cornerWorld(obj, j), cam, w, h);
      }
      ctx.setLineDash([]);
      this.#drawGlyphs(ctx, obj, cam, w, h, color);
    }
    if (primary) this.#drawGizmo(ctx, obj, cam, w, h);
  }

  #drawElevDestGhosts(ctx, doc, elev, cam, w, h) {
    const stops = elevStopBottoms(doc, elev);
    const liveTop = (elev.y | 0) + (elev.sy | 0);
    const x0 = elev.x | 0;
    const z0 = elev.z | 0;
    const sx = elev.sx | 0;
    const sz = elev.sz | 0;
    const sy = elev.sy | 0;
    ctx.strokeStyle = KINDS.elevator.color;
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 3]);
    for (const bottom of [stops.dest, stops.home]) {
      const top = bottom + sy;
      if (top === liveTop) continue;
      const corners = [
        { x: x0, y: top, z: z0 },
        { x: x0 + sx, y: top, z: z0 },
        { x: x0 + sx, y: top, z: z0 + sz },
        { x: x0, y: top, z: z0 + sz },
      ];
      for (let i = 0; i < 4; i++) {
        this.#line3(ctx, corners[i], corners[(i + 1) % 4], cam, w, h);
      }
    }
    ctx.setLineDash([]);
  }

  #drawGlyphs(ctx, obj, cam, w, h, color) {
    ctx.strokeStyle = color;
    for (const seg of this.#glyphSegments(obj)) {
      this.#line3(ctx, seg.a, seg.b, cam, w, h);
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
    ctx.fillStyle = "#7ec8e8";
    const handles = obj.kind === "room" ? roomGeometry(obj).handles : this.#aabbFaceHandles(obj);
    for (const handle of handles) {
      const pr = projectPoint(handle.world, cam, w, h);
      if (!pr.ok) continue;
      ctx.fillRect(pr.sx - 4, pr.sy - 4, 8, 8);
    }
  }

  #aabbFaceHandles(obj) {
    const x0 = obj.x | 0;
    const y0 = obj.y | 0;
    const z0 = obj.z | 0;
    const sx = obj.sx | 0;
    const sy = obj.sy | 0;
    const sz = obj.sz | 0;
    const cx = x0 + sx / 2;
    const cy = y0 + sy / 2;
    const cz = z0 + sz / 2;
    const handles = [
      { kind: "face", side: "x0", axis: "x", world: { x: x0, y: cy, z: cz } },
      { kind: "face", side: "x1", axis: "x", world: { x: x0 + sx, y: cy, z: cz } },
      { kind: "face", side: "z0", axis: "z", world: { x: cx, y: cy, z: z0 } },
      { kind: "face", side: "z1", axis: "z", world: { x: cx, y: cy, z: z0 + sz } },
    ];
    if (obj.kind !== "platform") {
      handles.push(
        { kind: "face", side: "y0", axis: "y", world: { x: cx, y: y0, z: cz } },
        { kind: "face", side: "y1", axis: "y", world: { x: cx, y: y0 + sy, z: cz } }
      );
    }
    return handles;
  }
}
