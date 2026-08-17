#!/usr/bin/env python3
"""Cook E1M1 from editor JSON → src/map_e1m1.asm (room-first SoA, tags→indices)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
OUT = ROOT / "src" / "map_e1m1.asm"

ENEMY_TYPE = {"Grunt": 0, "Rottweiler": 1}
ELEV_DESCENDING = 0
ELEV_AUTOMATIC = 1
FACE = {"+z": 0, "-z": 1, "+x": 2, "-x": 3}


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


def room_under(rooms: list[dict], obj: dict) -> int | None:
    hits = [i for i, r in enumerate(rooms) if aabb_overlap(obj, r)]
    if not hits:
        return None
    hits.sort(key=lambda i: aabb_volume(rooms[i]))
    return hits[0]


def rooms_for(rooms: list[dict], obj: dict) -> list[int]:
    return [i for i, r in enumerate(rooms) if aabb_overlap(obj, r)]


def btable(name: str, vals: list[int]) -> str:
    if not vals:
        return f"{name}\n"
    lines = [name]
    for i in range(0, len(vals), 16):
        chunk = vals[i : i + 16]
        lines.append("\t!byte " + ",".join(str(v & 0xFF) for v in chunk))
    return "\n".join(lines) + "\n"


def ascii_petscii_ish(s: str) -> list[int]:
    """Screen codes matching UI font (ASCII-indexed)."""
    out = []
    for ch in s[:22]:
        o = ord(ch)
        if 32 <= o <= 90:
            out.append(o)
        elif 97 <= o <= 122:
            out.append(o - 32)
        else:
            out.append(32)
    return out


def main() -> None:
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    level = doc["maps"]["E1M1"]
    objs = level["objects"]

    rooms = [o for o in objs if o["kind"] == "room"]
    doors = [o for o in objs if o["kind"] == "doorway"]
    crates = [o for o in objs if o["kind"] == "crate"]
    slopes = [o for o in objs if o["kind"] == "slope"]
    switches = [o for o in objs if o["kind"] == "switch"]
    elevs = [o for o in objs if o["kind"] == "elevator"]
    enemies = [o for o in objs if o["kind"] == "enemy"]
    triggers = [o for o in objs if o["kind"] == "trigger"]
    spawns = [o for o in objs if o["kind"] == "spawn"]

    if not spawns:
        raise SystemExit("E1M1 needs a spawn")
    spawn = spawns[0]

    # Tag → elevator index
    elev_by_tag: dict[str, int] = {}
    for i, e in enumerate(elevs):
        tag = (e.get("tag") or "").strip()
        if tag:
            elev_by_tag[tag] = i

    # Rooms SoA
    room_x = [r["x"] for r in rooms]
    room_y = [r["y"] for r in rooms]
    room_z = [r["z"] for r in rooms]
    room_sx = [r["sx"] for r in rooms]
    room_sy = [r["sy"] for r in rooms]
    room_sz = [r["sz"] for r in rooms]

    # Doors
    door_x, door_y, door_z = [], [], []
    door_sx, door_sy, door_sz = [], [], []
    door_ra, door_rb, door_home_y, door_face = [], [], [], []
    for d in doors:
        ids = rooms_for(rooms, d)
        door_x.append(d["x"])
        door_y.append(d["y"])
        door_z.append(d["z"])
        door_sx.append(d["sx"])
        door_sy.append(d["sy"])
        door_sz.append(d["sz"])
        door_home_y.append(d["y"])
        door_ra.append(ids[0] if len(ids) > 0 else 255)
        door_rb.append(ids[1] if len(ids) > 1 else 255)
        door_face.append(FACE.get(d.get("face") or "+z", 0))

    # Crates
    crate_x, crate_y, crate_z = [], [], []
    crate_sx, crate_sy, crate_sz, crate_room = [], [], [], []
    for c in crates:
        ri = room_under(rooms, c)
        if ri is None:
            raise SystemExit(f"crate at {c['x']},{c['y']},{c['z']} has no room")
        crate_x.append(c["x"])
        crate_y.append(c["y"])
        crate_z.append(c["z"])
        crate_sx.append(c["sx"])
        crate_sy.append(c["sy"])
        crate_sz.append(c["sz"])
        crate_room.append(ri)

    # Slopes
    slope_x, slope_y, slope_z = [], [], []
    slope_sx, slope_sy, slope_sz = [], [], []
    slope_axis, slope_dir, slope_room = [], [], []
    for s in slopes:
        ri = room_under(rooms, s)
        if ri is None:
            raise SystemExit("slope has no room")
        slope_x.append(s["x"])
        slope_y.append(s["y"])
        slope_z.append(s["z"])
        slope_sx.append(s["sx"])
        slope_sy.append(s["sy"])
        slope_sz.append(s["sz"])
        slope_axis.append(0 if s.get("axis") == "x" else 1)
        slope_dir.append(1 if s.get("dir", 1) >= 0 else 0)  # 1=+ 0=-
        slope_room.append(ri)

    # Elevators
    elev_x, elev_y, elev_z = [], [], []
    elev_sx, elev_sy, elev_sz = [], [], []
    elev_type, elev_home, elev_dest, elev_room = [], [], [], []
    for e in elevs:
        ri = room_under(rooms, e)
        if ri is None:
            raise SystemExit("elevator has no room")
        et = e.get("elevType") or "descending"
        elev_x.append(e["x"])
        elev_y.append(e["y"])
        elev_z.append(e["z"])
        elev_sx.append(e["sx"])
        elev_sy.append(e["sy"])
        elev_sz.append(e["sz"])
        elev_type.append(ELEV_AUTOMATIC if et == "automatic" else ELEV_DESCENDING)
        elev_home.append(e["y"])
        elev_dest.append(rooms[ri]["y"])  # room floor
        elev_room.append(ri)

    # Switches
    sw_x, sw_y, sw_z = [], [], []
    sw_sx, sw_sy, sw_sz = [], [], []
    sw_elev, sw_room, sw_face = [], [], []
    for s in switches:
        ri = room_under(rooms, s)
        if ri is None:
            raise SystemExit("switch has no room")
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

    # Enemies
    en_x, en_y, en_z = [], [], []
    en_type, en_rot, en_room = [], [], []
    for e in enemies:
        ri = room_under(rooms, e)
        if ri is None:
            raise SystemExit("enemy has no room")
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

    # Message triggers
    tr_x, tr_y, tr_z = [], [], []
    tr_sx, tr_sy, tr_sz, tr_room = [], [], [], []
    tr_text_off = []
    text_blob: list[int] = []
    for t in triggers:
        ri = room_under(rooms, t)
        if ri is None:
            raise SystemExit("trigger has no room")
        text = t.get("text") or ""
        off = len(text_blob)
        chars = ascii_petscii_ish(text)
        text_blob.extend(chars)
        text_blob.append(0)  # NUL
        tr_x.append(t["x"])
        tr_y.append(t["y"])
        tr_z.append(t["z"])
        tr_sx.append(t["sx"])
        tr_sy.append(t["sy"])
        tr_sz.append(t["sz"])
        tr_room.append(ri)
        tr_text_off.append(off)

    spawn_room = room_under(rooms, spawn)
    if spawn_room is None:
        raise SystemExit("spawn has no room")

    frustum = 1
    for r in rooms:
        frustum = max(frustum, int(r["sx"]), int(r["sz"]))
    frustum_half = frustum // 2

    parts_counts = [
        "; Generated by tools/genmap.py — counts / types",
        f"MAP_NROOMS\t= {len(rooms)}",
        f"MAP_NDOORS\t= {len(doors)}",
        f"MAP_NCRATES\t= {len(crates)}",
        f"MAP_NSLOPES\t= {len(slopes)}",
        f"MAP_NSWITCHES\t= {len(switches)}",
        f"MAP_NELEVS\t= {len(elevs)}",
        f"MAP_NENEMIES\t= {len(enemies)}",
        f"MAP_NTRIGS\t= {len(triggers)}",
        "ELEV_TYPE_DESCEND\t= 0",
        "ELEV_TYPE_AUTO\t= 1",
        "FACE_PZ\t= 0",
        "FACE_MZ\t= 1",
        "FACE_PX\t= 2",
        "FACE_MX\t= 3",
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
        "",
        btable("room_x", room_x).rstrip(),
        btable("room_y", room_y).rstrip(),
        btable("room_z", room_z).rstrip(),
        btable("room_sx", room_sx).rstrip(),
        btable("room_sy", room_sy).rstrip(),
        btable("room_sz", room_sz).rstrip(),
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
        "",
        btable("crate_x", crate_x).rstrip(),
        btable("crate_y", crate_y).rstrip(),
        btable("crate_z", crate_z).rstrip(),
        btable("crate_sx", crate_sx).rstrip(),
        btable("crate_sy", crate_sy).rstrip(),
        btable("crate_sz", crate_sz).rstrip(),
        btable("crate_room", crate_room).rstrip(),
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
        "",
        btable("en_x", en_x).rstrip(),
        btable("en_y", en_y).rstrip(),
        btable("en_z", en_z).rstrip(),
        btable("en_type", en_type).rstrip(),
        btable("en_rot", en_rot).rstrip(),
        btable("en_room", en_room).rstrip(),
        "",
        btable("tr_x", tr_x).rstrip(),
        btable("tr_y", tr_y).rstrip(),
        btable("tr_z", tr_z).rstrip(),
        btable("tr_sx", tr_sx).rstrip(),
        btable("tr_sy", tr_sy).rstrip(),
        btable("tr_sz", tr_sz).rstrip(),
        btable("tr_room", tr_room).rstrip(),
        btable("tr_text_off", tr_text_off).rstrip(),
        "",
        "map_text",
        "\t!byte " + ",".join(str(b) for b in text_blob) if text_blob else "\t!byte 0",
        "",
    ]
    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(
        f"Wrote {OUT.relative_to(ROOT)} + map_counts.asm: "
        f"{len(rooms)} rooms, {len(doors)} doors, {len(crates)} crates, "
        f"{len(elevs)} elevs, {len(enemies)} enemies"
    )


if __name__ == "__main__":
    main()
