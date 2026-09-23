#!/usr/bin/env python3
"""Simulate LoadLevel heap vs GAME size; fail the build if a map cannot load.

Heap grows down from SCR_A. LoadLevel: one E1Mn (prefix overlay+reloc, then
packed map), dump prefix (heap_top = map_base), then pose banks. heap_alloc
fails when new top <= end_game, so need must be strictly less than
SCR_A - end_game.

PROFILE = 1 in src/build_flags.asm still prints OVER maps, but those lines do not
fail the build. PROFILE = 0 fails when slack is zero or negative.

Streaming holds at most ROOM_MAX_TYPES banks — the types that cohabit in the
room being played. The gate is the worst SINGLE ROOM pose sum, not a map-wide
pair of the heaviest types. tools/perroom.py extracts per-room sets by
replaying bind_tab over the packed payload.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mkreloc import parse_labels, parse_mem_const
from perroom import ROOM_MAX_TYPES, packed_payload, per_room_types, field_offsets

ROOT = Path(__file__).resolve().parents[1]
MAP_DIR = ROOT / "maps"
ENEMY_DIR = ROOT / "enemies"
ENEMY_SIZES = ROOT / "src" / "enemy_sizes.asm"
PREFIX_ASM = ROOT / "src" / "level_prefix.asm"
FLAGS_ASM = ROOT / "src" / "build_flags.asm"

LEVEL_NAMES = [f"E1M{i}" for i in range(1, 9)]
DOS_NAME = ["grunt", "knight", "rott", "scrag", "ogre", "shambl", "chthon", "zombie"]
ENEMY_NTYPES = len(DOS_NAME)


def prg_payload(path: Path) -> bytes:
    raw = path.read_bytes()
    if len(raw) < 2:
        raise SystemExit(f"{path}: too short")
    return raw[2:]


def parse_size_table(path: Path, lo_name: str, hi_name: str) -> list[int]:
    text = path.read_text(encoding="utf-8")

    def row(name: str) -> list[int]:
        m = re.search(rf"^{re.escape(name)}\s+!byte\s+(.+)$", text, re.M)
        if not m:
            raise SystemExit(f"{path}: missing {name}")
        return [int(x.strip()) for x in m.group(1).split(",")]

    lo, hi = row(lo_name), row(hi_name)
    if len(lo) != len(hi):
        raise SystemExit(f"{path}: {lo_name}/{hi_name} length mismatch")
    return [l + (h << 8) for l, h in zip(lo, hi)]


def parse_profile() -> int:
    if not FLAGS_ASM.is_file():
        raise SystemExit(f"missing: {FLAGS_ASM}")
    m = re.search(
        r"^PROFILE\s*=\s*(\d+)",
        FLAGS_ASM.read_text(encoding="utf-8"),
        re.M,
    )
    if not m:
        raise SystemExit(f"{FLAGS_ASM}: no PROFILE")
    return int(m.group(1))


def parse_level_prefix() -> int:
    if not PREFIX_ASM.is_file():
        raise SystemExit(f"missing: {PREFIX_ASM}")
    m = re.search(r"^LEVEL_PREFIX\s*=\s*(\d+)\s*$", PREFIX_ASM.read_text(), re.M)
    if not m:
        raise SystemExit(f"{PREFIX_ASM}: no LEVEL_PREFIX")
    return int(m.group(1))


def enemy_sizes() -> list[int]:
    sizes = [0] * ENEMY_NTYPES
    table: list[int] | None = None
    if ENEMY_SIZES.is_file():
        table = parse_size_table(ENEMY_SIZES, "enemy_size_lo", "enemy_size_hi")
        if len(table) < ENEMY_NTYPES:
            raise SystemExit(f"{ENEMY_SIZES}: expected {ENEMY_NTYPES} sizes")
        sizes = table[:ENEMY_NTYPES]
    for i, dos in enumerate(DOS_NAME):
        prg = ENEMY_DIR / f"{dos}.prg"
        if prg.is_file() and prg.stat().st_size > 2:
            sizes[i] = len(prg_payload(prg))
    return sizes


def crush_bank_size() -> int:
    prg = ENEMY_DIR / "crush.prg"
    if prg.is_file() and prg.stat().st_size > 2:
        return len(prg_payload(prg))
    return 0


def crush_rooms(payload: bytes) -> set[int]:
    offs, counts = field_offsets(payload)
    packed = packed_payload(payload)
    n = counts.get("map_ncrush", 0)
    if not n or "crush_room" not in offs:
        return set()
    rooms = packed[offs["crush_room"] : offs["crush_room"] + n]
    nrooms = counts.get("map_nrooms", 0)
    out: set[int] = set()
    for r in rooms:
        if nrooms and r >= nrooms:
            raise SystemExit(f"checkheap: crusher room {r} out of range (>= {nrooms})")
        out.add(r)
    return out


def used_types(per_room: dict[int, set[int]]) -> list[int]:
    out: set[int] = set()
    for ts in per_room.values():
        out |= ts
    return sorted(out)


def main() -> None:
    ap = argparse.ArgumentParser(description="Check LoadLevel heap vs GAME size")
    ap.add_argument("--labels", default="game.lbl")
    ap.add_argument("--json", type=Path, default=None, help="write the per-level manifest")
    args = ap.parse_args()

    lbl = Path(args.labels)
    if not lbl.is_file():
        lbl = ROOT / args.labels
    if not lbl.is_file():
        print(f"missing: {args.labels}", file=sys.stderr)
        sys.exit(1)

    labels = parse_labels(lbl)
    if "end_game" not in labels:
        print(f"{lbl}: no end_game", file=sys.stderr)
        sys.exit(1)

    end_game = labels["end_game"]
    locode = parse_mem_const("LOCODE_BASE")
    scr_a = parse_mem_const("SCR_A")
    prefix = parse_level_prefix()
    profile = parse_profile() == 1
    avail = scr_a - end_game
    poses = enemy_sizes()
    crush_sz = crush_bank_size()

    print(
        f"heap  GAME ${locode:04X}-${end_game:04X}  "
        f"avail {avail}  prefix {prefix}"
    )
    print(
        f"      per-room model (max {ROOM_MAX_TYPES} types/room): "
        "gate is packed + max(prefix, worst room pose sum)."
    )

    failed = False
    any_level = False
    report = {
        "game": {
            "load": locode,
            "end": end_game,
            "bytes": end_game - locode,
            "heap_available": avail,
        },
        "level_prefix": prefix,
        "room_max_types": ROOM_MAX_TYPES,
        "enemy_sizes": {DOS_NAME[i]: poses[i] for i in range(ENEMY_NTYPES)},
        "levels": {},
    }
    for key in LEVEL_NAMES:
        prg = MAP_DIR / f"{key.lower()}.prg"
        if not prg.is_file() or prg.stat().st_size <= 2:
            continue
        payload = prg_payload(prg)
        if not payload:
            continue
        any_level = True
        packed = packed_payload(payload)

        per_room = per_room_types(payload)
        c_rooms = crush_rooms(payload)
        for room, ts in sorted(per_room.items()):
            if len(ts) > ROOM_MAX_TYPES:
                print(
                    f"{key}: room {room} has {len(ts)} types "
                    f"(max {ROOM_MAX_TYPES})",
                    file=sys.stderr,
                )
                failed = True

        types = used_types(per_room)
        for t in types:
            if poses[t] == 0:
                print(
                    f"{key}: missing pose PRG for {DOS_NAME[t]}",
                    file=sys.stderr,
                )
                failed = True

        level_sum = sum(poses[t] for t in types)

        worst_room, worst_sum, worst_names = -1, 0, []
        for room in sorted(set(per_room) | c_rooms):
            s = sum(poses[t] for t in per_room.get(room, ()))
            names = [DOS_NAME[t] for t in sorted(per_room.get(room, ()))]
            if room in c_rooms and crush_sz:
                s += crush_sz
                names = names + ["crush"]
            if s > worst_sum:
                worst_room = room
                worst_sum = s
                worst_names = names

        need = len(packed) + max(prefix, worst_sum)
        slack = avail - need
        pose_s = ",".join(worst_names) if worst_names else "-"
        where = f"room {worst_room}" if worst_room >= 0 else "no enemies"
        saved = level_sum - worst_sum
        report["levels"][key] = {
            "map_bytes": len(packed),
            "load_peak": len(packed) + prefix,
            "worst_room": worst_room,
            "worst_types": worst_names,
            "room_assets": worst_sum,
            "play_peak": len(packed) + worst_sum,
            "need": need,
            "slack": slack,
            "types": [DOS_NAME[t] for t in types],
            "rooms": {
                str(room): [DOS_NAME[t] for t in sorted(per_room[room])]
                for room in sorted(per_room)
            },
        }
        head = (
            f"{key}  map {len(packed)}  prefix {prefix}  "
            f"worst {worst_sum} ({where}: {pose_s})"
            f"  level-wide {level_sum} (-{saved})  need {need}"
        )
        if slack <= 0:
            tag = "  (profile)" if profile else ""
            print(f"{head}  OVER {need - avail}{tag}")
            if not profile:
                failed = True
        else:
            print(f"{head}  slack {slack}")

    if not any_level:
        print("checkheap: no map PRGs", file=sys.stderr)
        sys.exit(1)
    if args.json is not None:
        out = args.json if args.json.is_absolute() else ROOT / args.json
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {out}")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
