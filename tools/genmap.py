#!/usr/bin/env python3
"""Cook E1M1 from editor JSON → src/map_e1m1.asm (room-first SoA, tags→indices)."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from roomgeom import clamp_room_shape, nudge_door_outside, room_geometry

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
OUT = ROOT / "src" / "map_e1m1.asm"

ENEMY_TYPE = {"Grunt": 0, "Rottweiler": 1}
ELEV_DESCENDING = 0
ELEV_AUTOMATIC = 1
ELEV_TOGGLE = 2
FACE = {"+z": 0, "-z": 1, "+x": 2, "-x": 3}
ROOM_BG_DEFAULT = 9
ROOM_LINE_DEFAULT = 7
ROOM_FX_DEFAULT = 1
ROOM_WPN_DEFAULT = 0
ROOM_SKY_DEFAULT = ROOM_BG_DEFAULT  # legacy alias


def norm_color(val, default: int) -> int:
    if isinstance(val, int) and 0 <= val <= 15:
        return val
    try:
        n = int(val)
        if 0 <= n <= 15:
            return n
    except (TypeError, ValueError):
        pass
    return default


def aabb_overlap(a: dict, b: dict) -> bool:
    """Inclusive face-touch counts as overlap (editor model.js)."""
    return (
        a["x"] <= b["x"] + b["sx"]
        and b["x"] <= a["x"] + a["sx"]
        and a["y"] <= b["y"] + b["sy"]
        and b["y"] <= a["y"] + a["sy"]
        and a["z"] <= b["z"] + b["sz"]
        and b["z"] <= a["z"] + a["sz"]
    )


def aabb_volume(box: dict) -> int:
    return int(box["sx"]) * int(box["sy"]) * int(box["sz"])


def room_index(rooms: list[dict], obj: dict, kind: str) -> int:
    rid = obj.get("roomId")
    id_to_i = {r.get("id"): i for i, r in enumerate(rooms)}
    if rid in id_to_i:
        return id_to_i[rid]
    raise SystemExit(f"{kind} at {obj.get('x')},{obj.get('y')},{obj.get('z')} has no room")


def unique_u8(vals: list[int], cap: int, what: str, name: str) -> tuple[list[int], list[int]]:
    seen: list[int] = []
    idx: list[int] = []
    for v in vals:
        v = v & 0xFF
        if v not in seen:
            if len(seen) >= cap:
                raise SystemExit(f"room {name!r} has >{cap} unique {what}")
            seen.append(v)
        idx.append(seen.index(v))
    return seen, idx


def assign_missing_parents(objs: list[dict], rooms: list[dict]) -> None:
    """JSON v6 fallback: smallest overlapping room, like the old editor tree."""
    for obj in objs:
        if obj.get("kind") == "room":
            continue
        if obj.get("kind") == "doorway":
            hits = [r for r in rooms if aabb_overlap(obj, r)]
            hits.sort(key=lambda r: aabb_volume(r))
            if not obj.get("roomId") and hits:
                obj["roomId"] = hits[0].get("id")
            if not obj.get("otherRoomId"):
                other = next((r for r in hits if r.get("id") != obj.get("roomId")), None)
                if other:
                    obj["otherRoomId"] = other.get("id")
            continue
        if obj.get("roomId"):
            continue
        hits = [r for r in rooms if aabb_overlap(obj, r)]
        hits.sort(key=lambda r: aabb_volume(r))
        if hits:
            obj["roomId"] = hits[0].get("id")


def door_rooms(rooms: list[dict], d: dict) -> tuple[int, int]:
    id_to_i = {r.get("id"): i for i, r in enumerate(rooms)}
    ra = id_to_i.get(d.get("roomId"), 255)
    rb = id_to_i.get(d.get("otherRoomId"), 255)
    if ra == 255:
        raise SystemExit(f"doorway at {d.get('x')},{d.get('y')},{d.get('z')} has no owner room")
    return ra, rb


def xz_aabb_gap(a: dict, b: dict) -> int:
    """XZ separation between AABBs; 0 if footprints overlap or touch on an edge."""
    ax0, ax1 = a["x"], a["x"] + a["sx"]
    bx0, bx1 = b["x"], b["x"] + b["sx"]
    if ax1 < bx0:
        dx = bx0 - ax1
    elif bx1 < ax0:
        dx = ax0 - bx1
    else:
        dx = 0
    az0, az1 = a["z"], a["z"] + a["sz"]
    bz0, bz1 = b["z"], b["z"] + b["sz"]
    if az1 < bz0:
        dz = bz0 - az1
    elif bz1 < az0:
        dz = az0 - bz1
    else:
        dz = 0
    return dx + dz


def nearest_floor_home(elev: dict, room: dict, floor_y: int) -> int | None:
    """Upper stop so elev top meets another collider floor in this room, or None."""
    elev_sy = int(elev["sy"])
    elev_top = int(elev["y"]) + elev_sy
    best_key: tuple[int, int] | None = None
    best_home: int | None = None
    for c in room_geometry(room).get("colliders") or []:
        if int(c.get("sx") or 0) <= 0:
            continue
        cy = int(c["y"])
        if cy <= floor_y:
            continue
        home = cy - elev_sy
        if home <= floor_y:
            continue
        key = (xz_aabb_gap(elev, c), abs(cy - elev_top))
        if best_key is None or key < best_key:
            best_key = key
            best_home = home
    return best_home


def nearest_plat_home(
    elev: dict, room_i: int, plats: list[dict], plat_rooms: list[int], floor_y: int
) -> int | None:
    """Upper stop so elev top meets nearest same-room platform top, or None."""
    elev_sy = int(elev["sy"])
    elev_top = int(elev["y"]) + elev_sy
    best_key: tuple[int, int] | None = None
    best_home: int | None = None
    for pi, p in enumerate(plats):
        if plat_rooms[pi] != room_i:
            continue
        home = int(p["y"]) - elev_sy
        if home <= floor_y:
            continue
        key = (xz_aabb_gap(elev, p), abs(int(p["y"]) - elev_top))
        if best_key is None or key < best_key:
            best_key = key
            best_home = home
    return best_home


def btable(name: str, vals: list[int]) -> str:
    if not vals:
        return f"{name}\n"
    lines = [name]
    for i in range(0, len(vals), 16):
        chunk = vals[i : i + 16]
        lines.append("\t!byte " + ",".join(str(v & 0xFF) for v in chunk))
    return "\n".join(lines) + "\n"


def ascii_screen(s: str, maxlen: int = 40) -> list[int]:
    """ASCII screen codes for the UI font (mixed case, 32..126)."""
    line = s.replace("\r\n", "\n").split("\n", 1)[0]
    out = []
    for ch in line[:maxlen]:
        o = ord(ch)
        out.append(o if 32 <= o <= 126 else 32)
    return out


def main() -> None:
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    level = doc["maps"]["E1M1"]
    objs = level["objects"]

    rooms = [o for o in objs if o["kind"] == "room"]
    assign_missing_parents(objs, rooms)
    id_to_room = {r.get("id"): r for r in rooms}
    doors = [o for o in objs if o["kind"] == "doorway"]
    for d in doors:
        room = id_to_room.get(d.get("roomId")) or id_to_room.get(d.get("otherRoomId"))
        if room:
            nudge_door_outside(d, room)
    crates = [o for o in objs if o["kind"] == "crate"]
    slopes = [o for o in objs if o["kind"] == "slope"]
    plats = [o for o in objs if o["kind"] == "platform"]
    switches = [o for o in objs if o["kind"] == "switch"]
    elevs = [o for o in objs if o["kind"] == "elevator"]
    enemies = [o for o in objs if o["kind"] == "enemy"]
    triggers = [o for o in objs if o["kind"] == "trigger"]
    dests = [o for o in objs if o["kind"] == "teleporter_dest"]
    backpacks = [o for o in objs if o["kind"] in ("pickup", "backpack", "key")]
    spawns = [o for o in objs if o["kind"] == "spawn"]

    if not spawns:
        raise SystemExit("E1M1 needs a spawn")
    spawn = spawns[0]

    if len(objs) > 256:
        raise SystemExit(f"E1M1 has {len(objs)} objects; map id is u8")
    # Unique id per world object (order in level.objects)
    map_id = {id(o): i for i, o in enumerate(objs)}

    BP_TYPE = {
        "shells": 0,
        "nailgun": 1,
        "nails": 2,
        "grenade launcher": 3,
        "grenades": 4,
        "health 25%": 5,
        "health 50%": 6,
        "armour": 8,
        "quad damage": 9,
        "pentagram of protection": 10,
        "ring of shadows": 11,
        "silver key": 12,
        "gold key": 13,
    }

    # Tag → elevator index
    elev_by_tag: dict[str, int] = {}
    for i, e in enumerate(elevs):
        tag = (e.get("tag") or "").strip()
        if tag:
            elev_by_tag[tag] = i

    TRIG_MSG = 0
    TRIG_END = 1
    TRIG_HURT = 2
    TRIG_TELE = 3
    TRIG_ELEV = 4
    TRIG_PURPOSE = {
        "message": TRIG_MSG,
        "end_level": TRIG_END,
        "hurt": TRIG_HURT,
        "teleport": TRIG_TELE,
        "elevator": TRIG_ELEV,
    }

    # Rooms SoA
    room_x = [r["x"] for r in rooms]
    room_y = [r["y"] for r in rooms]
    room_z = [r["z"] for r in rooms]
    room_sx = [r["sx"] for r in rooms]
    room_sy = [r["sy"] for r in rooms]
    room_sz = [r["sz"] for r in rooms]
    room_bg = [
        norm_color(r.get("bgColor", r.get("skyColor")), ROOM_BG_DEFAULT) for r in rooms
    ]
    room_line = [norm_color(r.get("lineColor"), ROOM_LINE_DEFAULT) for r in rooms]
    room_fx = [norm_color(r.get("fxColor"), ROOM_FX_DEFAULT) for r in rooms]
    room_wpn = [norm_color(r.get("weaponColor"), ROOM_WPN_DEFAULT) for r in rooms]
    room_id = [map_id[id(r)] for r in rooms]

    col_x: list[int] = []
    col_y: list[int] = []
    col_z: list[int] = []
    col_sx: list[int] = []
    col_sy: list[int] = []
    col_sz: list[int] = []
    cut_x: list[int] = []
    cut_y: list[int] = []
    cut_z: list[int] = []
    cut_sx: list[int] = []
    cut_sy: list[int] = []
    cut_sz: list[int] = []
    room_nv: list[int] = []
    room_ne: list[int] = []
    room_vo: list[int] = []
    room_eo: list[int] = []
    room_nx: list[int] = []
    room_nz: list[int] = []
    room_uo: list[int] = []
    room_zo: list[int] = []
    mesh_ux: list[int] = []
    mesh_uz: list[int] = []
    mesh_vy: list[int] = []
    mesh_xid: list[int] = []
    mesh_zid: list[int] = []
    mesh_col: list[int] = []
    mesh_e0: list[int] = []
    mesh_e1: list[int] = []
    mesh_evert: list[int] = []
    mesh_efaces: list[int] = []

    for r in rooms:
        geom = room_geometry(r)
        cols = geom["colliders"]
        if len(cols) > 3:
            raise SystemExit(f"room {r.get('name') or '?'} has {len(cols)} floor areas (max 3)")
        while len(cols) < 3:
            cols.append({"x": 0, "y": 0, "z": 0, "sx": 0, "sy": 0, "sz": 0})
        for c in cols:
            col_x.append(int(c["x"]) & 0xFF)
            col_y.append(int(c["y"]) & 0xFF)
            col_z.append(int(c["z"]) & 0xFF)
            col_sx.append(int(c["sx"]) & 0xFF)
            col_sy.append(int(c["sy"]) & 0xFF)
            col_sz.append(int(c["sz"]) & 0xFF)
        cuts = geom.get("cutouts", [])[:2]
        while len(cuts) < 2:
            cuts.append({"x": 0, "y": 0, "z": 0, "sx": 0, "sy": 0, "sz": 0})
        for c in cuts:
            cut_x.append(int(c["x"]) & 0xFF)
            cut_y.append(int(c["y"]) & 0xFF)
            cut_z.append(int(c["z"]) & 0xFF)
            cut_sx.append(int(c["sx"]) & 0xFF)
            cut_sy.append(int(c["sy"]) & 0xFF)
            cut_sz.append(int(c["sz"]) & 0xFF)
        if clamp_room_shape(r.get("shape")) == "box":
            room_nv.append(0)
            room_ne.append(0)
            room_vo.append(0)
            room_eo.append(0)
            room_nx.append(0)
            room_nz.append(0)
            room_uo.append(0)
            room_zo.append(0)
            continue
        verts = geom["verts"]
        edges = geom["edges"]
        rname = r.get("name") or "?"
        if len(verts) > 16:
            raise SystemExit(f"room {rname!r} has {len(verts)} verts (max 16)")
        if len(edges) > 32:
            raise SystemExit(f"room {rname!r} has {len(edges)} edges (max 32)")
        ux, xid = unique_u8([int(v["x"]) for v in verts], 4, "X", rname)
        uz, zid = unique_u8([int(v["z"]) for v in verts], 4, "Z", rname)
        pairs: list[tuple[int, int]] = []
        col: list[int] = []
        for xi, zi in zip(xid, zid):
            p = (xi, zi)
            if p not in pairs:
                if len(pairs) >= 16:
                    raise SystemExit(f"room {rname!r} has >16 unique XZ columns")
                pairs.append(p)
            col.append(pairs.index(p))
        room_nv.append(len(verts))
        room_ne.append(len(edges))
        room_vo.append(len(mesh_vy))
        room_eo.append(len(mesh_e0))
        room_nx.append(len(ux))
        room_nz.append(len(uz))
        room_uo.append(len(mesh_ux))
        room_zo.append(len(mesh_uz))
        mesh_ux.extend(ux)
        mesh_uz.extend(uz)
        for v, xi, zi, ci in zip(verts, xid, zid, col):
            mesh_vy.append(int(v["y"]) & 0xFF)
            mesh_xid.append(xi)
            mesh_zid.append(zi)
            mesh_col.append(ci)
        for e in edges:
            mesh_e0.append(int(e["a"]) & 0xFF)
            mesh_e1.append(int(e["b"]) & 0xFF)
            mesh_evert.append(1 if e["vert"] else 0)
            mesh_efaces.append(int(e["faces"]) & 0xFF)

    # Doors
    door_x, door_y, door_z = [], [], []
    door_sx, door_sy, door_sz = [], [], []
    door_ra, door_rb, door_home_y, door_face, door_key = [], [], [], [], []
    door_id = []
    for d in doors:
        ra, rb = door_rooms(rooms, d)
        door_x.append(d["x"])
        door_y.append(d["y"])
        door_z.append(d["z"])
        door_sx.append(d["sx"])
        door_sy.append(d["sy"])
        door_sz.append(d["sz"])
        door_home_y.append(d["y"])
        door_ra.append(ra)
        door_rb.append(rb)
        door_face.append(FACE.get(d.get("face") or "+z", 0))
        lk = str(d.get("lockKey") or "").strip().lower()
        if lk == "gold":
            door_key.append(2)
        elif lk == "silver":
            door_key.append(1)
        elif d.get("locked"):
            tag = str(d.get("keyTag") or "").lower()
            door_key.append(2 if "gold" in tag else 1)
        else:
            door_key.append(0)
        door_id.append(map_id[id(d)])

    # Crates
    crate_x, crate_y, crate_z = [], [], []
    crate_sx, crate_sy, crate_sz, crate_room = [], [], [], []
    crate_id = []
    for c in crates:
        ri = room_index(rooms, c, "crate")
        crate_x.append(c["x"])
        crate_y.append(c["y"])
        crate_z.append(c["z"])
        crate_sx.append(c["sx"])
        crate_sy.append(c["sy"])
        crate_sz.append(c["sz"])
        crate_room.append(ri)
        crate_id.append(map_id[id(c)])

    # Slopes
    slope_x, slope_y, slope_z = [], [], []
    slope_sx, slope_sy, slope_sz = [], [], []
    slope_axis, slope_dir, slope_room = [], [], []
    slope_id = []
    for s in slopes:
        ri = room_index(rooms, s, "slope")
        slope_x.append(s["x"])
        slope_y.append(s["y"])
        slope_z.append(s["z"])
        slope_sx.append(s["sx"])
        slope_sy.append(s["sy"])
        slope_sz.append(s["sz"])
        slope_axis.append(0 if s.get("axis") == "x" else 1)
        slope_dir.append(1 if s.get("dir", 1) >= 0 else 0)  # 1=+ 0=-
        slope_room.append(ri)
        slope_id.append(map_id[id(s)])

    # Platforms (horizontal floor quads)
    plat_x, plat_y, plat_z = [], [], []
    plat_sx, plat_sz, plat_room, plat_solid = [], [], [], []
    plat_id = []
    for p in plats:
        ri = room_index(rooms, p, "platform")
        plat_x.append(p["x"])
        plat_y.append(p["y"])
        plat_z.append(p["z"])
        plat_sx.append(p["sx"])
        plat_sz.append(p["sz"])
        plat_room.append(ri)
        plat_solid.append(0 if p.get("collide") is False else 1)
        plat_id.append(map_id[id(p)])

    # Elevators
    elev_x, elev_y, elev_z = [], [], []
    elev_sx, elev_sy, elev_sz = [], [], []
    elev_type, elev_home, elev_dest, elev_room = [], [], [], []
    elev_id = []
    for e in elevs:
        ri = room_index(rooms, e, "elevator")
        et = e.get("elevType") or "descending"
        floor_y = rooms[ri]["y"]
        elev_x.append(e["x"])
        elev_y.append(e["y"])
        elev_z.append(e["z"])
        elev_sx.append(e["sx"])
        elev_sy.append(e["sy"])
        elev_sz.append(e["sz"])
        if et == "automatic":
            elev_type.append(ELEV_AUTOMATIC)
        elif et == "toggle":
            elev_type.append(ELEV_TOGGLE)
        else:
            elev_type.append(ELEV_DESCENDING)
        home = e["y"]
        if et == "toggle" and e["y"] == floor_y:
            raised = nearest_floor_home(e, rooms[ri], floor_y)
            if raised is None:
                raised = nearest_plat_home(e, ri, plats, plat_room, floor_y)
            if raised is not None:
                home = raised
        elev_home.append(home)
        elev_dest.append(floor_y)
        elev_room.append(ri)
        elev_id.append(map_id[id(e)])

    # Switches
    sw_x, sw_y, sw_z = [], [], []
    sw_sx, sw_sy, sw_sz = [], [], []
    sw_elev, sw_room, sw_face = [], [], []
    sw_id = []
    for s in switches:
        ri = room_index(rooms, s, "switch")
        tag = (s.get("tag") or "").strip()
        if tag not in elev_by_tag:
            raise SystemExit(f"switch tag {tag!r} has no elevator")
        sw_x.append(s["x"])
        sw_y.append(s["y"])
        sw_z.append(s["z"])
        sw_sx.append(s["sx"])
        sw_sy.append(s["sy"])
        sw_sz.append(s["sz"])
        sw_elev.append(elev_by_tag[tag])
        sw_room.append(ri)
        sw_face.append(FACE.get(s.get("face") or "+z", 0))
        sw_id.append(map_id[id(s)])

    # Enemies
    en_x, en_y, en_z = [], [], []
    en_type, en_rot, en_room, en_patrol = [], [], [], []
    en_id = []
    for e in enemies:
        ri = room_index(rooms, e, "enemy")
        name = e.get("enemy") or "Grunt"
        if name not in ENEMY_TYPE:
            raise SystemExit(f"unknown enemy type {name}")
        # Center of placement box (feet on y)
        en_x.append(e["x"] + e["sx"] // 2)
        en_y.append(e["y"])
        en_z.append(e["z"] + e["sz"] // 2)
        en_type.append(ENEMY_TYPE[name])
        en_rot.append(int(e.get("rot") or 0) & 7)
        en_room.append(ri)
        en_patrol.append(1 if e.get("patrol") else 0)
        en_id.append(map_id[id(e)])

    # Teleport destinations
    td_x, td_y, td_z, td_rot, td_room = [], [], [], [], []
    dest_by_tag: dict[str, int] = {}
    for i, d in enumerate(dests):
        ri = room_index(rooms, d, "teleporter_dest")
        tag = (d.get("tag") or "").strip()
        if tag:
            if tag in dest_by_tag:
                raise SystemExit(f"duplicate teleport dest tag {tag!r}")
            dest_by_tag[tag] = i
        td_x.append((int(d["x"]) + int(d["sx"]) // 2) & 0xFF)
        td_y.append(int(d["y"]) & 0xFF)
        td_z.append((int(d["z"]) + int(d["sz"]) // 2) & 0xFF)
        td_rot.append(int(d.get("rot") or 0) & 7)
        td_room.append(ri)

    # Triggers
    tr_x, tr_y, tr_z = [], [], []
    tr_sx, tr_sy, tr_sz, tr_room = [], [], [], []
    tr_purpose, tr_arg, tr_id = [], [], []
    text_blob: list[int] = []
    for t in triggers:
        ri = room_index(rooms, t, "trigger")
        purpose_s = t.get("purpose") or "message"
        if purpose_s not in TRIG_PURPOSE:
            raise SystemExit(f"unknown trigger purpose {purpose_s!r}")
        purpose = TRIG_PURPOSE[purpose_s]
        arg = 0
        if purpose == TRIG_MSG:
            text = t.get("text") or ""
            arg = len(text_blob)
            chars = ascii_screen(text)
            text_blob.extend(chars)
            text_blob.append(0)  # NUL
        elif purpose == TRIG_TELE:
            tag = (t.get("tag") or "").strip()
            if tag not in dest_by_tag:
                raise SystemExit(f"teleport trigger tag {tag!r} has no destination")
            arg = dest_by_tag[tag]
        elif purpose == TRIG_ELEV:
            tag = (t.get("tag") or "").strip()
            if tag not in elev_by_tag:
                raise SystemExit(f"elevator trigger tag {tag!r} has no elevator")
            arg = elev_by_tag[tag]
        tr_x.append(t["x"])
        tr_y.append(t["y"])
        tr_z.append(t["z"])
        tr_sx.append(t["sx"])
        tr_sy.append(t["sy"])
        tr_sz.append(t["sz"])
        tr_room.append(ri)
        tr_purpose.append(purpose)
        tr_arg.append(arg)
        tr_id.append(map_id[id(t)])

    # Backpacks (pickup tetrahedrons)
    bp_x, bp_y, bp_z, bp_type, bp_room = [], [], [], [], []
    bp_id = []
    for b in backpacks:
        kind = b.get("kind")
        ri = room_index(rooms, b, "pickup")
        if kind == "key":
            tag = f"{b.get('tag') or ''} {b.get('keyTag') or ''} {b.get('pickup') or ''}".lower()
            bt = 13 if "gold" in tag else 12
        else:
            name = (b.get("pickup") or b.get("backpack") or "shells").strip()
            bt = BP_TYPE.get(name, 0)
        bp_x.append(b["x"])
        bp_y.append(b["y"])
        bp_z.append(b["z"])
        bp_type.append(bt)
        bp_room.append(ri)
        bp_id.append(map_id[id(b)])

    spawn_room = room_index(rooms, spawn, "spawn")
    spawn_id = map_id[id(spawn)]

    frustum = 1
    for r in rooms:
        frustum = max(frustum, int(r["sx"]), int(r["sz"]))
    frustum = max(1, frustum // 2)
    frustum_half = frustum // 2

    parts_counts = [
        "; Generated by tools/genmap.py — counts / types",
        f"MAP_NROOMS\t= {len(rooms)}",
        f"MAP_NDOORS\t= {len(doors)}",
        f"MAP_NCRATES\t= {len(crates)}",
        f"MAP_NSLOPES\t= {len(slopes)}",
        f"MAP_NPLATS\t= {len(plats)}",
        f"MAP_NSWITCHES\t= {len(switches)}",
        f"MAP_NELEVS\t= {len(elevs)}",
        f"MAP_NENEMIES\t= {len(enemies)}",
        f"MAP_NTRIGS\t= {len(triggers)}",
        f"MAP_NDESTS\t= {len(dests)}",
        f"MAP_NBACKPACKS\t= {len(backpacks)}",
        "ELEV_TYPE_DESCEND\t= 0",
        "ELEV_TYPE_AUTO\t= 1",
        "ELEV_TYPE_TOGGLE\t= 2",
        "TRIG_MSG\t= 0",
        "TRIG_END\t= 1",
        "TRIG_HURT\t= 2",
        "TRIG_TELE\t= 3",
        "TRIG_ELEV\t= 4",
        "FACE_PZ\t= 0",
        "FACE_MZ\t= 1",
        "FACE_PX\t= 2",
        "FACE_MX\t= 3",
        "BP_SHELLS\t= 0",
        "BP_NAILGUN\t= 1",
        "BP_NAILS\t= 2",
        "BP_GRENLAUNCHER\t= 3",
        "BP_GRENADES\t= 4",
        "BP_HEALTH25\t= 5",
        "BP_HEALTH50\t= 6",
        "BP_SHELLS5\t= 7",
        "BP_ARMOUR\t= 8",
        "BP_QUAD\t= 9",
        "BP_PENT\t= 10",
        "BP_RING\t= 11",
        "BP_SILVER\t= 12",
        "BP_GOLD\t= 13",
        "BP_NTYPES\t= 14",
        "DOOR_KEY_NONE\t= 0",
        "DOOR_KEY_SILVER\t= 1",
        "DOOR_KEY_GOLD\t= 2",
        f"MAP_FRUSTUM\t= {frustum}",
        f"MAP_FRUSTUM_HALF\t= {frustum_half}",
        "",
    ]
    (ROOT / "src" / "map_counts.asm").write_text("\n".join(parts_counts), encoding="utf-8")

    parts = [
        "; Generated by tools/genmap.py — do not edit",
        f"; E1M1 {level.get('name')!r}",
        "",
        f"spawn_x\t!byte {spawn['x']}",
        f"spawn_y\t!byte {spawn['y']}",
        f"spawn_z\t!byte {spawn['z']}",
        f"spawn_rot\t!byte {int(spawn.get('rot') or 0) & 7}",
        f"spawn_room\t!byte {spawn_room}",
        f"spawn_id\t!byte {spawn_id}",
        "",
        btable("room_x", room_x).rstrip(),
        btable("room_y", room_y).rstrip(),
        btable("room_z", room_z).rstrip(),
        btable("room_sx", room_sx).rstrip(),
        btable("room_sy", room_sy).rstrip(),
        btable("room_sz", room_sz).rstrip(),
        btable("room_bg", room_bg).rstrip(),
        btable("room_line", room_line).rstrip(),
        btable("room_fx", room_fx).rstrip(),
        btable("room_wpn", room_wpn).rstrip(),
        btable("room_id", room_id).rstrip(),
        "",
        btable("rc_x", col_x).rstrip(),
        btable("rc_y", col_y).rstrip(),
        btable("rc_z", col_z).rstrip(),
        btable("rc_sx", col_sx).rstrip(),
        btable("rc_sy", col_sy).rstrip(),
        btable("rc_sz", col_sz).rstrip(),
        btable("rb_x", cut_x).rstrip(),
        btable("rb_y", cut_y).rstrip(),
        btable("rb_z", cut_z).rstrip(),
        btable("rb_sx", cut_sx).rstrip(),
        btable("rb_sy", cut_sy).rstrip(),
        btable("rb_sz", cut_sz).rstrip(),
        btable("room_nv", room_nv).rstrip(),
        btable("room_ne", room_ne).rstrip(),
        btable("room_vo", room_vo).rstrip(),
        btable("room_eo", room_eo).rstrip(),
        btable("room_nx", room_nx).rstrip(),
        btable("room_nz", room_nz).rstrip(),
        btable("room_uo", room_uo).rstrip(),
        btable("room_zo", room_zo).rstrip(),
        btable("room_ux", mesh_ux or [0]).rstrip(),
        btable("room_uz", mesh_uz or [0]).rstrip(),
        btable("room_vy", mesh_vy or [0]).rstrip(),
        btable("room_xid", mesh_xid or [0]).rstrip(),
        btable("room_zid", mesh_zid or [0]).rstrip(),
        btable("room_col", mesh_col or [0]).rstrip(),
        btable("room_e0", mesh_e0 or [0]).rstrip(),
        btable("room_e1", mesh_e1 or [0]).rstrip(),
        btable("room_evert", mesh_evert or [0]).rstrip(),
        btable("room_efaces", mesh_efaces or [0]).rstrip(),
        "",
        btable("door_x", door_x).rstrip(),
        btable("door_y", door_y).rstrip(),
        btable("door_z", door_z).rstrip(),
        btable("door_sx", door_sx).rstrip(),
        btable("door_sy", door_sy).rstrip(),
        btable("door_sz", door_sz).rstrip(),
        btable("door_ra", door_ra).rstrip(),
        btable("door_rb", door_rb).rstrip(),
        btable("door_home_y", door_home_y).rstrip(),
        btable("door_face", door_face).rstrip(),
        btable("door_key", door_key).rstrip(),
        btable("door_id", door_id).rstrip(),
        "",
        btable("crate_x", crate_x).rstrip(),
        btable("crate_y", crate_y).rstrip(),
        btable("crate_z", crate_z).rstrip(),
        btable("crate_sx", crate_sx).rstrip(),
        btable("crate_sy", crate_sy).rstrip(),
        btable("crate_sz", crate_sz).rstrip(),
        btable("crate_room", crate_room).rstrip(),
        btable("crate_id", crate_id).rstrip(),
        "",
        btable("slope_x", slope_x).rstrip(),
        btable("slope_y", slope_y).rstrip(),
        btable("slope_z", slope_z).rstrip(),
        btable("slope_sx", slope_sx).rstrip(),
        btable("slope_sy", slope_sy).rstrip(),
        btable("slope_sz", slope_sz).rstrip(),
        btable("slope_axis", slope_axis).rstrip(),
        btable("slope_dir", slope_dir).rstrip(),
        btable("slope_room", slope_room).rstrip(),
        btable("slope_id", slope_id).rstrip(),
        "",
        btable("plat_x", plat_x).rstrip(),
        btable("plat_y", plat_y).rstrip(),
        btable("plat_z", plat_z).rstrip(),
        btable("plat_sx", plat_sx).rstrip(),
        btable("plat_sz", plat_sz).rstrip(),
        btable("plat_room", plat_room).rstrip(),
        btable("plat_solid", plat_solid).rstrip(),
        btable("plat_id", plat_id).rstrip(),
        "",
        btable("elev_x", elev_x).rstrip(),
        btable("elev_y0", elev_y).rstrip(),  # home/init Y (const)
        btable("elev_z", elev_z).rstrip(),
        btable("elev_sx", elev_sx).rstrip(),
        btable("elev_sy", elev_sy).rstrip(),
        btable("elev_sz", elev_sz).rstrip(),
        btable("elev_type", elev_type).rstrip(),
        btable("elev_home", elev_home).rstrip(),
        btable("elev_dest", elev_dest).rstrip(),
        btable("elev_room", elev_room).rstrip(),
        btable("elev_id", elev_id).rstrip(),
        "",
        btable("sw_x", sw_x).rstrip(),
        btable("sw_y", sw_y).rstrip(),
        btable("sw_z", sw_z).rstrip(),
        btable("sw_sx", sw_sx).rstrip(),
        btable("sw_sy", sw_sy).rstrip(),
        btable("sw_sz", sw_sz).rstrip(),
        btable("sw_elev", sw_elev).rstrip(),
        btable("sw_room", sw_room).rstrip(),
        btable("sw_face", sw_face).rstrip(),
        btable("sw_id", sw_id).rstrip(),
        "",
        btable("en_x", en_x).rstrip(),
        btable("en_y", en_y).rstrip(),
        btable("en_z", en_z).rstrip(),
        btable("en_type", en_type).rstrip(),
        btable("en_rot", en_rot).rstrip(),
        btable("en_room", en_room).rstrip(),
        btable("en_patrol", en_patrol).rstrip(),
        btable("en_id", en_id).rstrip(),
        "",
        btable("tr_x", tr_x).rstrip(),
        btable("tr_y", tr_y).rstrip(),
        btable("tr_z", tr_z).rstrip(),
        btable("tr_sx", tr_sx).rstrip(),
        btable("tr_sy", tr_sy).rstrip(),
        btable("tr_sz", tr_sz).rstrip(),
        btable("tr_room", tr_room).rstrip(),
        btable("tr_purpose", tr_purpose).rstrip(),
        btable("tr_arg", tr_arg).rstrip(),
        btable("tr_id", tr_id).rstrip(),
        "",
        btable("td_x", td_x).rstrip(),
        btable("td_y", td_y).rstrip(),
        btable("td_z", td_z).rstrip(),
        btable("td_rot", td_rot).rstrip(),
        btable("td_room", td_room).rstrip(),
        "",
        btable("bp_x", bp_x).rstrip(),
        btable("bp_y", bp_y).rstrip(),
        btable("bp_z", bp_z).rstrip(),
        btable("bp_type", bp_type).rstrip(),
        btable("bp_room", bp_room).rstrip(),
        btable("bp_id", bp_id).rstrip(),
        "",
        "map_name",
        "\t!byte " + ",".join(str(b) for b in (ascii_screen(level.get("name") or "") + [0])),
        "",
        "map_text",
        "\t!byte " + ",".join(str(b) for b in text_blob) if text_blob else "\t!byte 0",
        "",
    ]
    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(
        f"Wrote {OUT.relative_to(ROOT)} + map_counts.asm: "
        f"{len(rooms)} rooms, {len(doors)} doors, {len(crates)} crates, "
        f"{len(plats)} plats, {len(elevs)} elevs, {len(enemies)} enemies, "
        f"{len(backpacks)} backpacks"
    )


if __name__ == "__main__":
    main()
