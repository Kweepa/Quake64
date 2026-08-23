#!/usr/bin/env python3
"""One-shot: convert packed-map SoA abs,x/y and MAP_N* immediates.

Run from repo root. Safe to re-run (skips +macro lines).
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"

MAP_FIELDS = {
    "room_x", "room_y", "room_z", "room_sx", "room_sy", "room_sz",
    "room_bg", "room_line", "room_fx", "room_wpn", "room_id",
    "rc_x", "rc_y", "rc_z", "rc_sx", "rc_sy", "rc_sz",
    "rb_x", "rb_y", "rb_z", "rb_sx", "rb_sy", "rb_sz",
    "room_nv", "room_ne", "room_vo", "room_eo", "room_nx", "room_nz",
    "room_uo", "room_zo", "room_ux", "room_uz", "room_vy",
    "room_xid", "room_zid", "room_col",
    "room_e0", "room_e1", "room_evert", "room_efaces",
    "door_x", "door_y", "door_z", "door_sx", "door_sy", "door_sz",
    "door_ra", "door_rb", "door_home_y", "door_face", "door_key", "door_id",
    "crate_x", "crate_y", "crate_z", "crate_sx", "crate_sy", "crate_sz",
    "crate_room", "crate_id",
    "slope_x", "slope_y", "slope_z", "slope_sx", "slope_sy", "slope_sz",
    "slope_axis", "slope_dir", "slope_room", "slope_id",
    "plat_x", "plat_y", "plat_z", "plat_sx", "plat_sz",
    "plat_room", "plat_solid", "plat_id",
    "elev_x", "elev_y0", "elev_z", "elev_sx", "elev_sy", "elev_sz",
    "elev_type", "elev_home", "elev_dest", "elev_room", "elev_id",
    "sw_x", "sw_y", "sw_z", "sw_sx", "sw_sy", "sw_sz",
    "sw_elev", "sw_room", "sw_face", "sw_id",
    "en_x", "en_y", "en_z", "en_type", "en_rot", "en_room", "en_patrol", "en_id",
    "tr_x", "tr_y", "tr_z", "tr_sx", "tr_sy", "tr_sz",
    "tr_room", "tr_purpose", "tr_arg", "tr_id",
    "td_x", "td_y", "td_z", "td_rot", "td_room",
    "bp_x", "bp_y", "bp_z", "bp_type", "bp_room", "bp_id",
    "map_name", "map_text",
}

OPS = {
    "lda", "sta", "cmp", "adc", "sbc", "ora", "and", "eor",
    "ldx", "ldy", "cpx", "cpy",
}

IDX_ACC = re.compile(
    r"^([ \t+\-]*)(" + "|".join(OPS) + r")[ \t]+"
    r"([A-Za-z_][A-Za-z0-9_]*)\s*,\s*([xy])(\s*(?:;.*)?)?$"
)

IMM_PTR = re.compile(
    r"^([ \t+\-]*)(lda|ldx|ldy|cpx|cpy|cmp|adc|sbc)[ \t]+"
    r"#([<>])(" + "|".join(sorted(MAP_FIELDS, key=len, reverse=True)) + r")(\s*(?:;.*)?)?$"
)

MAP_N = {
    "MAP_NROOMS": "map_nrooms",
    "MAP_NDOORS": "map_ndoors",
    "MAP_NCRATES": "map_ncrates",
    "MAP_NSLOPES": "map_nslopes",
    "MAP_NPLATS": "map_nplats",
    "MAP_NSWITCHES": "map_nswitches",
    "MAP_NELEVS": "map_nelevs",
    "MAP_NENEMIES": "map_nenemies",
    "MAP_NTRIGS": "map_ntrigs",
    "MAP_NDESTS": "map_ndests",
    "MAP_NBACKPACKS": "map_nbackpacks",
}

CPX_N = re.compile(
    r"^([ \t+\-]*)(cpx|cpy|cmp|ldx|ldy)[ \t]+#(" + "|".join(MAP_N) + r")(\s*(?:;.*)?)?$"
)

FILES = [
    "world.asm", "mesh.asm", "door.asm", "enemy.asm", "cube.asm",
    "elevator.asm", "process.asm", "hud.asm", "util.asm", "vic.asm",
]


def rewrite_line(line: str) -> str:
    stripped = line.rstrip("\n")
    nl = "\n" if line.endswith("\n") else ""
    if stripped.lstrip().startswith("+"):
        return line

    m = IDX_ACC.match(stripped)
    if m:
        pre, op, fld, idx, comment = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5) or ""
        if fld in MAP_FIELDS:
            mac = f"{op}_m{idx}"
            return f"{pre}+{mac} {fld}{comment}{nl}"

    m = IMM_PTR.match(stripped)
    if m:
        pre, op, which, fld, comment = m.group(1), m.group(2), m.group(3), m.group(4), m.group(5) or ""
        if which == "<":
            return f"{pre}{op}\t{fld}{comment}{nl}"
        return f"{pre}{op}\t{fld}+1{comment}{nl}"

    m = CPX_N.match(stripped)
    if m:
        pre, op, name, comment = m.group(1), m.group(2), m.group(3), m.group(4) or ""
        return f"{pre}{op}\t{MAP_N[name]}{comment}{nl}"

    return line


def main() -> None:
    nchg = 0
    for rel in FILES:
        path = SRC / rel
        text = path.read_text(encoding="utf-8")
        out = []
        file_n = 0
        for line in text.splitlines(keepends=True):
            new = rewrite_line(line)
            if new != line:
                file_n += 1
            out.append(new)
        if file_n:
            path.write_text("".join(out), encoding="utf-8", newline="\n")
            print(f"{rel}: {file_n} lines")
            nchg += file_n
        else:
            print(f"{rel}: unchanged")
    print(f"total {nchg}")


if __name__ == "__main__":
    main()
