"""Tetromino room geometry — keep in sync with editor/js/roomGeom.js."""

from __future__ import annotations


ROOM_SHAPES = ("box", "T", "L", "S")


def clamp_quarter(n) -> int:
    try:
        r = int(n or 0)
    except (TypeError, ValueError):
        r = 0
    return ((r % 4) + 4) % 4


def clamp_room_shape(s) -> str:
    return s if s in ROOM_SHAPES else "box"


def _rot90(p: dict, axis: int) -> dict:
    x, y, z = p["x"], p["y"], p["z"]
    if axis == 0:
        return {"x": x, "y": -z, "z": y}
    if axis == 1:
        return {"x": z, "y": y, "z": -x}
    return {"x": -y, "y": x, "z": z}


def _apply_rots(p: dict, rx: int, ry: int, rz: int) -> dict:
    q = dict(p)
    for _ in range(rx):
        q = _rot90(q, 0)
    for _ in range(ry):
        q = _rot90(q, 1)
    for _ in range(rz):
        q = _rot90(q, 2)
    return q


def _hat_sign(hat: dict) -> int:
    return hat["x"] + hat["y"] + hat["z"]


def room_basis(room: dict) -> dict:
    rx = clamp_quarter(room.get("rx"))
    ry = clamp_quarter(room.get("ry"))
    rz = clamp_quarter(room.get("rz"))
    u = _apply_rots({"x": 1, "y": 0, "z": 0}, rx, ry, rz)
    w = _apply_rots({"x": 0, "y": 1, "z": 0}, rx, ry, rz)
    v = _apply_rots({"x": 0, "y": 0, "z": 1}, rx, ry, rz)

    def size_on(hat: dict) -> int:
        if hat["x"]:
            return int(room["sx"])
        if hat["y"]:
            return int(room["sy"])
        return int(room["sz"])

    return {
        "u": u,
        "w": w,
        "v": v,
        "uSize": size_on(u),
        "wSize": size_on(w),
        "vSize": size_on(v),
    }


def _local_to_world(room: dict, u: int, w: int, v: int, basis: dict) -> dict:
    pos = {"x": int(room["x"]), "y": int(room["y"]), "z": int(room["z"])}

    def add(hat: dict, t: int, t_size: int) -> None:
        coord = t if _hat_sign(hat) > 0 else t_size - t
        if hat["x"]:
            pos["x"] += coord
        elif hat["y"]:
            pos["y"] += coord
        else:
            pos["z"] += coord

    add(basis["u"], u, basis["uSize"])
    add(basis["w"], w, basis["wSize"])
    add(basis["v"], v, basis["vSize"])
    return pos


def _uvw_box_to_world(room: dict, box: dict, basis: dict) -> dict:
    xs, ys, zs = [], [], []
    for u in (box["u"], box["u"] + box["su"]):
        for w in (0, basis["wSize"]):
            for v in (box["v"], box["v"] + box["sv"]):
                p = _local_to_world(room, u, w, v, basis)
                xs.append(p["x"])
                ys.append(p["y"])
                zs.append(p["z"])
    x0, y0, z0 = min(xs), min(ys), min(zs)
    return {
        "x": x0,
        "y": y0,
        "z": z0,
        "sx": max(1, max(xs) - x0),
        "sy": max(1, max(ys) - y0),
        "sz": max(1, max(zs) - z0),
    }


def _local_footprint(room: dict, basis: dict) -> list[dict]:
    shape = clamp_room_shape(room.get("shape"))
    u_size = basis["uSize"]
    v_size = basis["vSize"]
    flip = bool(room.get("flip"))

    def mirror_u(box: dict) -> dict:
        if not flip:
            return box
        return {"u": u_size - box["u"] - box["su"], "v": box["v"], "su": box["su"], "sv": box["sv"]}

    if shape == "box":
        return [{"u": 0, "v": 0, "su": u_size, "sv": v_size}]
    if shape == "L":
        cut_u = int(room.get("cutU") or 1)
        cut_v = int(room.get("cutV") or 1)
        return [
            mirror_u({"u": 0, "v": 0, "su": u_size, "sv": v_size - cut_v}),
            mirror_u({"u": 0, "v": v_size - cut_v, "su": u_size - cut_u, "sv": cut_v}),
        ]
    if shape == "T":
        stem_w = int(room.get("stemW") or 1)
        stem_pos = int(room.get("stemPos") or 1)
        bar_d = int(room.get("barD") or 1)
        return [
            mirror_u({"u": 0, "v": v_size - bar_d, "su": u_size, "sv": bar_d}),
            mirror_u({"u": stem_pos, "v": 0, "su": stem_w, "sv": v_size - bar_d}),
        ]
    if shape == "S":
        shift = int(room.get("shift") or 1)
        mid = int(room.get("mid") or 1)
        if flip:
            return [
                {"u": shift, "v": mid, "su": u_size - shift, "sv": v_size - mid},
                {"u": 0, "v": 0, "su": u_size - shift, "sv": mid},
            ]
        return [
            {"u": 0, "v": mid, "su": u_size - shift, "sv": v_size - mid},
            {"u": shift, "v": 0, "su": u_size - shift, "sv": mid},
        ]
    return [{"u": 0, "v": 0, "su": u_size, "sv": v_size}]


def _aabb_faces(box: dict) -> list[dict]:
    x0, y0, z0 = box["x"], box["y"], box["z"]
    x1, y1, z1 = x0 + box["sx"], y0 + box["sy"], z0 + box["sz"]
    return [
        {"axis": "x", "sign": -1, "plane": x0, "a0": y0, "a1": y1, "b0": z0, "b1": z1, "faceId": "-x"},
        {"axis": "x", "sign": 1, "plane": x1, "a0": y0, "a1": y1, "b0": z0, "b1": z1, "faceId": "+x"},
        {"axis": "y", "sign": -1, "plane": y0, "a0": x0, "a1": x1, "b0": z0, "b1": z1, "faceId": "-y"},
        {"axis": "y", "sign": 1, "plane": y1, "a0": x0, "a1": x1, "b0": z0, "b1": z1, "faceId": "+y"},
        {"axis": "z", "sign": -1, "plane": z0, "a0": x0, "a1": x1, "b0": y0, "b1": y1, "faceId": "-z"},
        {"axis": "z", "sign": 1, "plane": z1, "a0": x0, "a1": x1, "b0": y0, "b1": y1, "faceId": "+z"},
    ]


def _plane_touches(box: dict, axis: str, plane: int) -> bool:
    o0 = box[axis]
    o1 = box[axis] + box["s" + axis]
    return o0 <= plane <= o1


def _other_on_face(other: dict, face: dict) -> dict | None:
    if not _plane_touches(other, face["axis"], face["plane"]):
        return None
    if face["axis"] == "x":
        return {"a0": other["y"], "a1": other["y"] + other["sy"], "b0": other["z"], "b1": other["z"] + other["sz"]}
    if face["axis"] == "y":
        return {"a0": other["x"], "a1": other["x"] + other["sx"], "b0": other["z"], "b1": other["z"] + other["sz"]}
    return {"a0": other["x"], "a1": other["x"] + other["sx"], "b0": other["y"], "b1": other["y"] + other["sy"]}


def _subtract_rect(r: dict, c: dict) -> list[dict]:
    ia0, ia1 = max(r["a0"], c["a0"]), min(r["a1"], c["a1"])
    ib0, ib1 = max(r["b0"], c["b0"]), min(r["b1"], c["b1"])
    if ia0 >= ia1 or ib0 >= ib1:
        return [r]
    out = []
    if r["a0"] < ia0:
        out.append({"a0": r["a0"], "a1": ia0, "b0": r["b0"], "b1": r["b1"]})
    if ia1 < r["a1"]:
        out.append({"a0": ia1, "a1": r["a1"], "b0": r["b0"], "b1": r["b1"]})
    if r["b0"] < ib0:
        out.append({"a0": ia0, "a1": ia1, "b0": r["b0"], "b1": ib0})
    if ib1 < r["b1"]:
        out.append({"a0": ia0, "a1": ia1, "b0": ib1, "b1": r["b1"]})
    return [q for q in out if q["a1"] > q["a0"] and q["b1"] > q["b0"]]


def _compose(face: dict, a: int, b: int) -> dict:
    if face["axis"] == "x":
        return {"x": face["plane"], "y": a, "z": b}
    if face["axis"] == "y":
        return {"x": a, "y": face["plane"], "z": b}
    return {"x": a, "y": b, "z": face["plane"]}


def _outer_face_bits(outer: dict, a: dict, b: dict) -> int:
    bits = 0

    def on(axis: str, plane: int, bit: int) -> None:
        nonlocal bits
        if a[axis] == plane and b[axis] == plane:
            bits |= bit

    on("x", outer["x"], 0x01)
    on("x", outer["x"] + outer["sx"], 0x02)
    on("y", outer["y"], 0x04)
    on("y", outer["y"] + outer["sy"], 0x08)
    on("z", outer["z"], 0x10)
    on("z", outer["z"] + outer["sz"], 0x20)
    return bits


def _vert_on_open_seg(a: dict, b: dict, p: dict) -> bool:
    if a["x"] == b["x"] and a["y"] == b["y"] and a["z"] != b["z"] and p["x"] == a["x"] and p["y"] == a["y"]:
        return min(a["z"], b["z"]) < p["z"] < max(a["z"], b["z"])
    if a["x"] == b["x"] and a["z"] == b["z"] and a["y"] != b["y"] and p["x"] == a["x"] and p["z"] == a["z"]:
        return min(a["y"], b["y"]) < p["y"] < max(a["y"], b["y"])
    if a["y"] == b["y"] and a["z"] == b["z"] and a["x"] != b["x"] and p["y"] == a["y"] and p["z"] == a["z"]:
        return min(a["x"], b["x"]) < p["x"] < max(a["x"], b["x"])
    return False


def _face_contains_point(f: dict, p: dict) -> bool:
    if f["axis"] == "x":
        if p["x"] != f["plane"]:
            return False
        return f["a0"] <= p["y"] <= f["a1"] and f["b0"] <= p["z"] <= f["b1"]
    if f["axis"] == "y":
        if p["y"] != f["plane"]:
            return False
        return f["a0"] <= p["x"] <= f["a1"] and f["b0"] <= p["z"] <= f["b1"]
    if p["z"] != f["plane"]:
        return False
    return f["a0"] <= p["x"] <= f["a1"] and f["b0"] <= p["y"] <= f["b1"]


def _in_plane_perp(axis: str, va: dict, vb: dict) -> str:
    if axis == "y":
        return "z" if va["x"] != vb["x"] else "x"
    if axis == "x":
        return "z" if va["y"] != vb["y"] else "y"
    return "y" if va["x"] != vb["x"] else "x"


def _buried_on_plane(va: dict, vb: dict, faces: list[dict]) -> bool:
    if not faces:
        return False
    axis = faces[0]["axis"]
    mid = {"x": (va["x"] + vb["x"]) / 2, "y": (va["y"] + vb["y"]) / 2, "z": (va["z"] + vb["z"]) / 2}
    perp = _in_plane_perp(axis, va, vb)
    a = dict(mid)
    b = dict(mid)
    a[perp] = mid[perp] - 0.5
    b[perp] = mid[perp] + 0.5
    inside = lambda p: any(_face_contains_point(f, p) for f in faces)
    return inside(a) and inside(b)


def _union_hull(colliders: list[dict], outer: dict) -> dict:
    hull_faces = []
    for i, box in enumerate(colliders):
        for face in _aabb_faces(box):
            pieces = [{"a0": face["a0"], "a1": face["a1"], "b0": face["b0"], "b1": face["b1"]}]
            for j, other in enumerate(colliders):
                if i == j:
                    continue
                clip = _other_on_face(other, face)
                if clip is None:
                    continue
                nxt = []
                for p in pieces:
                    nxt.extend(_subtract_rect(p, clip))
                pieces = nxt
            for p in pieces:
                hull_faces.append(
                    {
                        **face,
                        "a0": p["a0"],
                        "a1": p["a1"],
                        "b0": p["b0"],
                        "b1": p["b1"],
                        "corners": [
                            _compose(face, p["a0"], p["b0"]),
                            _compose(face, p["a1"], p["b0"]),
                            _compose(face, p["a1"], p["b1"]),
                            _compose(face, p["a0"], p["b1"]),
                        ],
                    }
                )

    vert_map: dict[tuple, int] = {}
    verts: list[dict] = []

    def add_vert(p: dict) -> int:
        k = (p["x"], p["y"], p["z"])
        if k in vert_map:
            return vert_map[k]
        i = len(verts)
        verts.append({"x": p["x"], "y": p["y"], "z": p["z"]})
        vert_map[k] = i
        return i

    raw: list[tuple[int, int]] = []
    for f in hull_faces:
        ids = [add_vert(c) for c in f["corners"]]
        raw.extend([(ids[0], ids[1]), (ids[1], ids[2]), (ids[2], ids[3]), (ids[3], ids[0])])

    atomic: dict[tuple[int, int], tuple[int, int]] = {}
    for ia, ib in raw:
        if ia == ib:
            continue
        va, vb = verts[ia], verts[ib]
        hits = [i for i in range(len(verts)) if i not in (ia, ib) and _vert_on_open_seg(va, vb, verts[i])]
        hits.sort(
            key=lambda i: (verts[i]["x"] - va["x"]) ** 2
            + (verts[i]["y"] - va["y"]) ** 2
            + (verts[i]["z"] - va["z"]) ** 2
        )
        chain = [ia, *hits, ib]
        for k in range(len(chain) - 1):
            a, b = min(chain[k], chain[k + 1]), max(chain[k], chain[k + 1])
            if a != b:
                atomic[(a, b)] = (a, b)

    by_plane: dict[tuple, list[dict]] = {}
    for f in hull_faces:
        by_plane.setdefault((f["axis"], f["plane"]), []).append(f)

    edges = []
    for ia, ib in atomic.values():
        va, vb = verts[ia], verts[ib]
        mid = {
            "x": (va["x"] + vb["x"]) / 2,
            "y": (va["y"] + vb["y"]) / 2,
            "z": (va["z"] + vb["z"]) / 2,
        }
        covering = [f for f in hull_faces if _face_contains_point(f, mid)]
        buried = False
        seen: set[tuple] = set()
        for f in covering:
            key = (f["axis"], f["plane"])
            if key in seen:
                continue
            seen.add(key)
            if _buried_on_plane(va, vb, by_plane.get(key, [])):
                buried = True
                break
        if buried:
            continue
        edges.append(
            {
                "a": ia,
                "b": ib,
                "vert": 1 if va["x"] == vb["x"] and va["z"] == vb["z"] and va["y"] != vb["y"] else 0,
                "faces": _outer_face_bits(outer, va, vb),
            }
        )
    used = set()
    for e in edges:
        used.add(e["a"])
        used.add(e["b"])
    remap = {}
    compact = []
    for i, v in enumerate(verts):
        if i not in used:
            continue
        remap[i] = len(compact)
        compact.append(v)
    for e in edges:
        e["a"] = remap[e["a"]]
        e["b"] = remap[e["b"]]
    return {"hullFaces": hull_faces, "verts": compact, "edges": edges}


def room_geometry(room: dict) -> dict:
    outer = {
        "x": int(room["x"]),
        "y": int(room["y"]),
        "z": int(room["z"]),
        "sx": int(room["sx"]),
        "sy": int(room["sy"]),
        "sz": int(room["sz"]),
    }
    shape = clamp_room_shape(room.get("shape"))
    if shape == "box":
        return {
            "outer": outer,
            "shape": "box",
            "colliders": [dict(outer)],
            "verts": [],
            "edges": [],
            "hullFaces": _aabb_faces(outer),
        }

    basis = room_basis(room)
    fp = _local_footprint(room, basis)
    colliders = [_uvw_box_to_world(room, box, basis) for box in fp]
    hull = _union_hull(colliders, outer)
    return {"outer": outer, "shape": shape, "colliders": colliders, **hull}


_DOOR_FACE_IDS = ("+x", "-x", "+z", "-z")


def _best_door_hull_face(door: dict, room: dict) -> dict | None:
    geom = room_geometry(room)
    cx = door["x"] + door["sx"] / 2
    cy = door["y"] + door["sy"] / 2
    cz = door["z"] + door["sz"] / 2
    best = None
    best_score = None
    for f in geom.get("hullFaces") or []:
        if f.get("axis") == "y":
            continue
        if f.get("faceId") not in _DOOR_FACE_IDS:
            continue
        dist = abs(cx - f["plane"]) if f["axis"] == "x" else abs(cz - f["plane"])
        a = cy if f["axis"] == "x" else cx
        b = cz if f["axis"] == "x" else cy
        in_a = f["a0"] - 1 <= a <= f["a1"] + 1
        in_b = f["b0"] - 1 <= b <= f["b1"] + 1
        score = dist + (0 if in_a and in_b else 8)
        if best is None or score < best_score:
            best = f
            best_score = score
    return best


def nudge_door_outside(door: dict, room: dict) -> dict:
    """If the door sits inside-flush on a hull face, shift the box outside."""
    f = _best_door_hull_face(door, room)
    if not f:
        return door
    if f["axis"] == "x":
        thick = int(door["sx"])
        if f["sign"] > 0:
            if door["x"] == f["plane"] - thick:
                door["x"] = f["plane"]
        elif door["x"] == f["plane"]:
            door["x"] = max(0, f["plane"] - thick)
    else:
        thick = int(door["sz"])
        if f["sign"] > 0:
            if door["z"] == f["plane"] - thick:
                door["z"] = f["plane"]
        elif door["z"] == f["plane"]:
            door["z"] = max(0, f["plane"] - thick)
    return door

