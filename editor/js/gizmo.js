import {
  closestTOnSegment2d,
  distPointToSegment2d,
  NEAR,
  projectLine,
  projectPoint,
  worldToCamera,
} from "./math3d.js";

export const GIZMO_SCREEN_FRAC = 0.1;
export const GIZMO_FALLBACK_LEN = 8;
export const GIZMO_AXIS_COLS = { x: "#e55", y: "#5e5", z: "#55e" };
export const GIZMO_AXIS_HIT = 8;

const GIZMO_PLANES = [
  { plane: "yz", planeN: { x: 1, y: 0, z: 0 }, stroke: "#ee5555", fill: "rgba(238,85,85,0.3)" },
  { plane: "xz", planeN: { x: 0, y: 1, z: 0 }, stroke: "#55ee55", fill: "rgba(85,238,85,0.3)" },
  { plane: "xy", planeN: { x: 0, y: 0, z: 1 }, stroke: "#5555ee", fill: "rgba(85,85,238,0.3)" },
];

const AXIS_BASIS = {
  x: [
    { x: 0, y: 1, z: 0 },
    { x: 0, y: 0, z: 1 },
  ],
  y: [
    { x: 1, y: 0, z: 0 },
    { x: 0, y: 0, z: 1 },
  ],
  z: [
    { x: 1, y: 0, z: 0 },
    { x: 0, y: 1, z: 0 },
  ],
};

const CONE_FRAC = 0.2;
const CONE_RADIUS = 0.085;
const CONE_SEGS = 10;

function gizmoPlaneCorners(c, plane, planeLen) {
  const p = (dx, dy, dz) => ({ x: c.x + dx, y: c.y + dy, z: c.z + dz });
  if (plane === "xy") return [p(0, 0, 0), p(planeLen, 0, 0), p(planeLen, planeLen, 0), p(0, planeLen, 0)];
  if (plane === "xz") return [p(0, 0, 0), p(planeLen, 0, 0), p(planeLen, 0, planeLen), p(0, 0, planeLen)];
  return [p(0, 0, 0), p(0, planeLen, 0), p(0, planeLen, planeLen), p(0, 0, planeLen)];
}

function gizmoPlaneGrab(c, plane, planeLen) {
  const h = planeLen * 0.5;
  if (plane === "xy") return { x: c.x + h, y: c.y + h, z: c.z };
  if (plane === "xz") return { x: c.x + h, y: c.y, z: c.z + h };
  return { x: c.x, y: c.y + h, z: c.z + h };
}

function pointInPoly2d(x, y, poly) {
  let inside = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const xi = poly[i].x;
    const yi = poly[i].y;
    const xj = poly[j].x;
    const yj = poly[j].y;
    if ((yi > y) !== (yj > y) && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}

export function gizmoMetrics(c, cam, w, h) {
  const focal = Math.min(w, h) * 0.9;
  const targetPx = Math.min(w, h) * GIZMO_SCREEN_FRAC;
  const cc = worldToCamera(c, cam);
  const axisLen = cc.z >= NEAR ? (targetPx / focal) * cc.z : GIZMO_FALLBACK_LEN;
  return { axisLen, planeLen: axisLen / 3, focal, targetPx };
}

export function gizmoPlaneHandles(c, gizmo) {
  const { axisLen, planeLen } = gizmo;
  return GIZMO_PLANES.map((p) => ({
    kind: "plane",
    plane: p.plane,
    planeN: p.planeN,
    stroke: p.stroke,
    fill: p.fill,
    corners: gizmoPlaneCorners(c, p.plane, planeLen),
    world: gizmoPlaneGrab(c, p.plane, planeLen),
    gizmoAxisLen: axisLen,
  }));
}

export function gizmoAxisEnd(c, axis, axisLen) {
  const end = { x: c.x, y: c.y, z: c.z };
  end[axis] += axisLen;
  return end;
}

export function projectGizmoPoly(corners, cam, w, h) {
  const poly = [];
  for (const p of corners) {
    const pr = projectPoint(p, cam, w, h);
    if (!pr.ok) return null;
    poly.push({ x: pr.sx, y: pr.sy });
  }
  return poly;
}

export function drawGizmoPlaneQuad(ctx, corners, cam, w, h, fill, stroke, hi) {
  const poly = projectGizmoPoly(corners, cam, w, h);
  if (!poly) return;
  ctx.beginPath();
  ctx.moveTo(poly[0].x, poly[0].y);
  for (let i = 1; i < poly.length; i++) ctx.lineTo(poly[i].x, poly[i].y);
  ctx.closePath();
  ctx.fillStyle = hi ? "rgba(255,255,255,0.35)" : fill;
  ctx.fill();
  ctx.strokeStyle = hi ? "#fff" : stroke;
  ctx.lineWidth = hi ? 2 : 1.5;
  ctx.stroke();
}

function drawGizmoLine(ctx, a, b, cam, w, h, col, width = 2) {
  const seg = projectLine(a, b, cam, w, h);
  if (!seg) return;
  ctx.strokeStyle = col;
  ctx.lineWidth = width;
  ctx.beginPath();
  ctx.moveTo(seg.ax, seg.ay);
  ctx.lineTo(seg.bx, seg.by);
  ctx.stroke();
}

function gizmoConeRing(c, axis, axisLen) {
  const tip = gizmoAxisEnd(c, axis, axisLen);
  const coneLen = axisLen * CONE_FRAC;
  const r = axisLen * CONE_RADIUS;
  const base = gizmoAxisEnd(c, axis, axisLen - coneLen);
  const [u, v] = AXIS_BASIS[axis];
  const ring = [];
  for (let i = 0; i < CONE_SEGS; i++) {
    const a = (i / CONE_SEGS) * Math.PI * 2;
    const ca = Math.cos(a);
    const sa = Math.sin(a);
    ring.push({
      x: base.x + (u.x * ca + v.x * sa) * r,
      y: base.y + (u.y * ca + v.y * sa) * r,
      z: base.z + (u.z * ca + v.z * sa) * r,
    });
  }
  return { tip, ring, shaftEnd: base };
}

function drawGizmoCone(ctx, tip, ring, cam, w, h, col) {
  const pt = projectPoint(tip, cam, w, h);
  if (!pt.ok) return;
  const base = [];
  for (const p of ring) {
    const pr = projectPoint(p, cam, w, h);
    if (!pr.ok) return;
    base.push(pr);
  }
  ctx.fillStyle = col;
  for (let i = 0; i < base.length; i++) {
    const a = base[i];
    const b = base[(i + 1) % base.length];
    ctx.beginPath();
    ctx.moveTo(pt.sx, pt.sy);
    ctx.lineTo(a.sx, a.sy);
    ctx.lineTo(b.sx, b.sy);
    ctx.closePath();
    ctx.fill();
  }
}

function drawGizmoAxis(ctx, c, axis, axisLen, cam, w, h, col, width) {
  const { tip, ring, shaftEnd } = gizmoConeRing(c, axis, axisLen);
  drawGizmoLine(ctx, c, shaftEnd, cam, w, h, col, width);
  drawGizmoCone(ctx, tip, ring, cam, w, h, col);
}

/** Screen-fixed translate gizmo: plane quads then RGB axis lines. */
export function drawTranslateGizmo(ctx, c, cam, w, h, state = {}) {
  const { hoverGizmo = null, drag = null } = state;
  const gizmo = gizmoMetrics(c, cam, w, h);
  for (const handle of gizmoPlaneHandles(c, gizmo)) {
    const hi =
      (hoverGizmo?.kind === "plane" && hoverGizmo.plane === handle.plane) ||
      (drag?.kind === "plane" && drag.plane === handle.plane);
    drawGizmoPlaneQuad(ctx, handle.corners, cam, w, h, handle.fill, handle.stroke, hi);
  }
  for (const axis of ["x", "y", "z"]) {
    const hi =
      (hoverGizmo?.kind === "axis" && hoverGizmo.axis === axis) ||
      (drag?.kind === "axis" && drag.axis === axis);
    const col = hi ? "#fff" : GIZMO_AXIS_COLS[axis];
    drawGizmoAxis(ctx, c, axis, gizmo.axisLen, cam, w, h, col, hi ? 3 : 2);
  }
  return gizmo;
}

export function hitTranslateGizmo(c, cam, w, h, mx, my, axisHit = GIZMO_AXIS_HIT) {
  const gizmo = gizmoMetrics(c, cam, w, h);
  for (const handle of gizmoPlaneHandles(c, gizmo)) {
    const poly = projectGizmoPoly(handle.corners, cam, w, h);
    if (poly && pointInPoly2d(mx, my, poly)) return handle;
  }
  const pc = projectPoint(c, cam, w, h);
  if (!pc.ok) return null;
  for (const axis of ["x", "y", "z"]) {
    const end = gizmoAxisEnd(c, axis, gizmo.axisLen);
    const pa = projectPoint(end, cam, w, h);
    if (!pa.ok) continue;
    if (distPointToSegment2d(mx, my, pc.sx, pc.sy, pa.sx, pa.sy) < axisHit) {
      const t = closestTOnSegment2d(mx, my, pc.sx, pc.sy, pa.sx, pa.sy);
      return {
        kind: "axis",
        axis,
        world: {
          x: c.x + (end.x - c.x) * t,
          y: c.y + (end.y - c.y) * t,
          z: c.z + (end.z - c.z) * t,
        },
        gizmoAxisLen: gizmo.axisLen,
      };
    }
  }
  return null;
}

export function gizmoAxisDragDelta(p, grab, axis, start, axisLen, cam, w, h) {
  const along = gizmoAxisEnd(grab, axis, axisLen);
  const pa = projectPoint(grab, cam, w, h);
  const pb = projectPoint(along, cam, w, h);
  if (!pa.ok || !pb.ok) return null;
  const ax = pb.sx - pa.sx;
  const ay = pb.sy - pa.sy;
  const alen2 = ax * ax + ay * ay;
  if (alen2 < 16) return null;
  const t = ((p.x - start.x) * ax + (p.y - start.y) * ay) / alen2;
  return Math.round(t * axisLen);
}
