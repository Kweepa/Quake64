#!/usr/bin/env python3
"""Simulate LoadLevel heap vs GAME size; fail the build if a map cannot load.

Heap grows down from SCR_A. LoadLevel: map, RELOC_MAX (then drop), pose banks
for map_type0..2. heap_alloc fails when new top <= end_game, so need must be
strictly less than SCR_A - end_game.

Must run after GAME assemble (game.lbl) and genmap/genenemies PRGs, before
tools/mkdisk.py (see build.bat).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from mkreloc import parse_labels, parse_mem_const

ROOT = Path(__file__).resolve().parents[1]
MAP_DIR = ROOT / "maps"
ENEMY_DIR = ROOT / "enemies"
ENEMY_SIZES = ROOT / "src" / "enemy_sizes.asm"

LEVEL_NAMES = [f"E1M{i}" for i in range(1, 9)]
DOS_NAME = ["grunt", "knight", "rott", "scrag", "ogre", "shambl", "chthon"]
ENEMY_NTYPES = len(DOS_NAME)
MAP_MAX_TYPES = 3
TYPE_OFF = 11  # packed header: 11 count bytes, then type0..2


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


def map_types(payload: bytes) -> list[int]:
    if len(payload) < TYPE_OFF + MAP_MAX_TYPES:
        raise SystemExit("map payload shorter than packed header")
    types: list[int] = []
    for t in payload[TYPE_OFF : TYPE_OFF + MAP_MAX_TYPES]:
        if t == 0xFF:
            continue
        if t >= ENEMY_NTYPES:
            raise SystemExit(f"map type id {t} out of range")
        types.append(t)
    return types


def main() -> None:
    ap = argparse.ArgumentParser(description="Check LoadLevel heap vs GAME size")
    ap.add_argument("--labels", default="game.lbl")
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
    reloc_max = parse_mem_const("RELOC_MAX")
    avail = scr_a - end_game
    poses = enemy_sizes()

    print(
        f"heap  GAME ${locode:04X}-${end_game:04X}  "
        f"avail {avail}  reloc_max {reloc_max}"
    )

    failed = False
    any_level = False
    for key in LEVEL_NAMES:
        prg = MAP_DIR / f"{key.lower()}.prg"
        if not prg.is_file() or prg.stat().st_size <= 2:
            continue
        payload = prg_payload(prg)
        if not payload:
            continue
        any_level = True
        types = map_types(payload)
        pose_sum = 0
        names: list[str] = []
        for t in types:
            sz = poses[t]
            if sz == 0:
                print(
                    f"{key}: missing pose PRG for {DOS_NAME[t]}",
                    file=sys.stderr,
                )
                failed = True
                continue
            pose_sum += sz
            names.append(DOS_NAME[t])
        need = len(payload) + max(reloc_max, pose_sum)
        slack = avail - need
        pose_s = ",".join(names) if names else "-"
        if slack <= 0:
            over = need - avail
            print(
                f"{key}  map {len(payload)}  poses {pose_sum} ({pose_s})  "
                f"need {need}  OVER {over}"
            )
            failed = True
        else:
            print(
                f"{key}  map {len(payload)}  poses {pose_sum} ({pose_s})  "
                f"need {need}  slack {slack}"
            )

    if not any_level:
        print("checkheap: no map PRGs", file=sys.stderr)
        sys.exit(1)
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
