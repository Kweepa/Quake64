#!/usr/bin/env python3
"""Scan game.prg for SMC map-accessor sites; write reloc.prg for LoadLevel.

Macros in src/mapacc.asm emit abs,x / abs,y with operand hi = MAP_SMC_HI
and lo = field id. This must run after ACME writes game.prg and before
tools/mkdisk.py packs the d64 (see build.bat).
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MEM_ASM = ROOT / "src" / "mem.asm"

# abs,x: lda sta cmp adc sbc ora and eor ldy
ABS_X = {0xBD, 0x9D, 0xDD, 0x7D, 0xFD, 0x1D, 0x3D, 0x5D, 0xBC}
# abs,y: lda sta cmp adc sbc ora and eor ldx
ABS_Y = {0xB9, 0x99, 0xD9, 0x79, 0xF9, 0x19, 0x39, 0x59, 0xBE}
ABS_OPS = ABS_X | ABS_Y


def parse_mem_const(name: str) -> int:
    text = MEM_ASM.read_text(encoding="utf-8")
    m = re.search(rf"^{re.escape(name)}\s*=\s*\$([0-9a-fA-F]+)\b", text, re.M)
    if m:
        return int(m.group(1), 16)
    m = re.search(rf"^{re.escape(name)}\s*=\s*([0-9]+)\b", text, re.M)
    if m:
        return int(m.group(1), 10)
    raise SystemExit(f"{MEM_ASM}: missing {name}")


def parse_labels(lbl: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    if not lbl.is_file():
        return out
    for line in lbl.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"al C:([0-9a-fA-F]+) \.(.+)$", line.strip())
        if m:
            out[m.group(2)] = int(m.group(1), 16) & 0xFFFF
    return out


def scan(body: bytes, load: int, sentinel: int, max_id: int) -> list[tuple[int, int]]:
    recs: list[tuple[int, int]] = []
    i = 0
    n = len(body)
    while i + 2 < n:
        op, lo, hi = body[i], body[i + 1], body[i + 2]
        if op in ABS_OPS and hi == sentinel and lo <= max_id:
            recs.append((load + i + 1, lo))
            i += 3
            continue
        i += 1
    return recs


def main() -> None:
    ap = argparse.ArgumentParser(description="Build reloc.prg from game.prg SMC sites")
    ap.add_argument("game", nargs="?", default="game.prg")
    ap.add_argument("out", nargs="?", default="reloc.prg")
    ap.add_argument("--labels", default="game.lbl")
    args = ap.parse_args()

    sentinel = parse_mem_const("MAP_SMC_HI")
    reloc_max = parse_mem_const("RELOC_MAX")

    game = Path(args.game)
    if not game.is_file():
        print(f"missing: {game}", file=sys.stderr)
        sys.exit(1)

    raw = game.read_bytes()
    if len(raw) < 5:
        print(f"{game}: too short", file=sys.stderr)
        sys.exit(1)
    load = raw[0] | (raw[1] << 8)
    body = raw[2:]

    labels = parse_labels(Path(args.labels))
    max_id = 255
    if "room_x" in labels and "map_text" in labels:
        max_id = (labels["map_text"] - labels["room_x"]) // 2
        if max_id < 0 or max_id > 255:
            print("map pointer table field id out of range", file=sys.stderr)
            sys.exit(1)

    recs = scan(body, load, sentinel, max_id)
    if not recs:
        print("mkreloc: zero SMC sites (macros not emitting sentinel?)", file=sys.stderr)
        sys.exit(1)
    if len(recs) < 200:
        print(f"mkreloc: warning: only {len(recs)} sites (expected ~400+)", file=sys.stderr)

    payload = bytearray()
    payload += struct.pack("<H", len(recs))
    for addr, fid in recs:
        payload += struct.pack("<HB", addr, fid)

    if len(payload) > reloc_max:
        print(
            f"mkreloc: payload {len(payload)} exceeds RELOC_MAX {reloc_max}",
            file=sys.stderr,
        )
        sys.exit(1)

    out = Path(args.out)
    # Dummy load address; LoadPrg uses SA=0 and heap dest.
    out.write_bytes(struct.pack("<H", 0) + payload)
    print(f"Wrote {out} ({len(recs)} sites, {len(payload)} bytes)")


if __name__ == "__main__":
    main()
