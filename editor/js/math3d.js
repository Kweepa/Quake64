export function len3(x, y, z) {
  return Math.hypot(x, y, z);
}

export function norm3(x, y, z) {
  const l = len3(x, y, z) || 1;
  return { x: x / l, y: y / l, z: z / l };
}

export function lookVectors(yaw, pitch) {
  const cy = Math.cos(yaw);
  const sy = Math.sin(yaw);
  const cp = Math.cos(pitch);
  const sp = Math.sin(pitch);
  const forward = { x: sy * cp, y: sp, z: cy * cp };
  const right = { x: cy, y: 0, z: -sy };
  const up = {
    x: -sy * sp,
    y: cp,
    z: -cy * sp,
  };
  return { forward, right, up };
}

export function worldToCamera(p, cam) {
  const dx = p.x - cam.x;
  const dy = p.y - cam.y;
  const dz = p.z - cam.z;
  const { forward, right, up } = lookVectors(cam.yaw, cam.pitch);
  return {
    x: dx * right.x + dy * right.y + dz * right.z,
    y: dx * up.x + dy * up.y + dz * up.z,
    z: dx * forward.x + dy * forward.y + dz * forward.z,
  };
}

export const NEAR = 0.15;

function projectCam(c, w, h, f) {
  return {
    sx: w * 0.5 + (c.x / c.z) * f,
    sy: h * 0.5 - (c.y / c.z) * f,
  };
}

export function projectPoint(p, cam, w, h, focal) {
  const c = worldToCamera(p, cam);
  if (c.z < NEAR) return { ...c, ok: false, sx: 0, sy: 0 };
  const f = focal ?? Math.min(w, h) * 0.9;
  const s = projectCam(c, w, h, f);
  return { ...c, ok: true, sx: s.sx, sy: s.sy };
}

/** Clip a world-space segment to the camera near plane, then project. */
export function projectLine(a, b, cam, w, h, focal) {
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
  const f = focal ?? Math.min(w, h) * 0.9;
  const sa = projectCam(pa, w, h, f);
  const sb = projectCam(pb, w, h, f);
  return { ax: sa.sx, ay: sa.sy, bx: sb.sx, by: sb.sy };
}

export function screenRay(mx, my, cam, w, h, focal) {
  const f = focal ?? Math.min(w, h) * 0.9;
  const nx = (mx - w * 0.5) / f;
  const ny = -(my - h * 0.5) / f;
  const { forward, right, up } = lookVectors(cam.yaw, cam.pitch);
  const dir = norm3(
    forward.x + right.x * nx + up.x * ny,
    forward.y + right.y * nx + up.y * ny,
    forward.z + right.z * nx + up.z * ny
  );
  return { origin: { x: cam.x, y: cam.y, z: cam.z }, dir };
}

export function rayAabb(origin, dir, box) {
  const min = { x: box.x, y: box.y, z: box.z };
  const max = { x: box.x + box.sx, y: box.y + box.sy, z: box.z + box.sz };
  let tmin = 0;
  let tmax = 1e9;
  for (const a of ["x", "y", "z"]) {
    if (Math.abs(dir[a]) < 1e-8) {
      if (origin[a] < min[a] || origin[a] > max[a]) return null;
      continue;
    }
    let t1 = (min[a] - origin[a]) / dir[a];
    let t2 = (max[a] - origin[a]) / dir[a];
    if (t1 > t2) [t1, t2] = [t2, t1];
    tmin = Math.max(tmin, t1);
    tmax = Math.min(tmax, t2);
    if (tmin > tmax) return null;
  }
  if (tmax < 0) return null;
  const t = tmin >= 0 ? tmin : tmax;
  return {
    t,
    point: {
      x: origin.x + dir.x * t,
      y: origin.y + dir.y * t,
      z: origin.z + dir.z * t,
    },
  };
}

export function intersectPlane(origin, dir, point, normal) {
  const denom = dir.x * normal.x + dir.y * normal.y + dir.z * normal.z;
  if (Math.abs(denom) < 1e-8) return null;
  const t =
    ((point.x - origin.x) * normal.x +
      (point.y - origin.y) * normal.y +
      (point.z - origin.z) * normal.z) /
    denom;
  if (t < 0) return null;
  return {
    t,
    point: {
      x: origin.x + dir.x * t,
      y: origin.y + dir.y * t,
      z: origin.z + dir.z * t,
    },
  };
}

export function distPointToSegment2d(px, py, ax, ay, bx, by) {
  const dx = bx - ax;
  const dy = by - ay;
  const l2 = dx * dx + dy * dy;
  if (l2 < 1e-6) return Math.hypot(px - ax, py - ay);
  let t = ((px - ax) * dx + (py - ay) * dy) / l2;
  t = Math.max(0, Math.min(1, t));
  return Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
}

export const BOX_CORNERS = [
  [0, 0, 0],
  [1, 0, 0],
  [1, 1, 0],
  [0, 1, 0],
  [0, 0, 1],
  [1, 0, 1],
  [1, 1, 1],
  [0, 1, 1],
];

export const BOX_EDGES = [
  [0, 1],
  [1, 2],
  [2, 3],
  [3, 0],
  [4, 5],
  [5, 6],
  [6, 7],
  [7, 4],
  [0, 4],
  [1, 5],
  [2, 6],
  [3, 7],
];

export function cornerWorld(box, i) {
  const c = BOX_CORNERS[i];
  return {
    x: box.x + c[0] * box.sx,
    y: box.y + c[1] * box.sy,
    z: box.z + c[2] * box.sz,
  };
}

export function faceCorners(faceId) {
  switch (faceId) {
    case "+z":
      return [4, 5, 6, 7];
    case "-z":
      return [1, 0, 3, 2];
    case "+x":
      return [1, 5, 6, 2];
    case "-x":
      return [4, 0, 3, 7];
    default:
      return [4, 5, 6, 7];
  }
}
