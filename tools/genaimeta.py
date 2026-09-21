#!/usr/bin/env python3
"""Generate relocation metadata for AI modules linked at AI_LINK_BASE."""

from __future__ import annotations

import json
from pathlib import Path

from mkreloc import ABS_OPS, parse_mem_const

ROOT = Path(__file__).resolve().parents[1]
ENEMY_DIR = ROOT / "enemies"
DOS_NAMES = ["rott", "knight", "ogre", "scrag", "crush"]

ONE_BYTE = {
    0x00, 0x08, 0x18, 0x28, 0x38, 0x40, 0x48, 0x58, 0x60, 0x68, 0x78,
    0x88, 0x8A, 0x98, 0x9A, 0xA8, 0xAA, 0xB8, 0xBA, 0xC8, 0xCA, 0xD8,
    0xE8, 0xEA, 0xF8,
}
TWO_BYTE = {
    0x01, 0x05, 0x06, 0x09, 0x0A, 0x10, 0x11, 0x15, 0x16,
    0x21, 0x24, 0x25, 0x26, 0x29, 0x2A, 0x30, 0x31, 0x35, 0x36,
    0x41, 0x45, 0x46, 0x49, 0x4A, 0x50, 0x51, 0x55, 0x56,
    0x61, 0x65, 0x66, 0x69, 0x6A, 0x70, 0x71, 0x75, 0x76,
    0x81, 0x84, 0x85, 0x86, 0x90, 0x91, 0x94, 0x95, 0x96,
    0xA0, 0xA1, 0xA2, 0xA4, 0xA5, 0xA6, 0xA9, 0xB0, 0xB1, 0xB4, 0xB5, 0xB6,
    0xC0, 0xC1, 0xC4, 0xC5, 0xC6, 0xC9, 0xD0, 0xD1, 0xD5, 0xD6,
    0xE0, 0xE1, 0xE4, 0xE5, 0xE6, 0xE9, 0xF0, 0xF1, 0xF5, 0xF6,
}
ABSOLUTE = ABS_OPS | {
    0x0D, 0x0E, 0x20, 0x2C, 0x2D, 0x2E, 0x4C, 0x4D, 0x4E,
    0x6D, 0x6E, 0x8C, 0x8D, 0x8E, 0xAC, 0xAD, 0xAE,
    0xCC, 0xCD, 0xCE, 0xEC, 0xED, 0xEE,
}


def scan(code: bytes, link: int, sentinel: int) -> tuple[list[int], list[int]]:
    internal: list[int] = []
    map_sites: list[int] = []
    pc = 0
    while pc < len(code):
        op = code[pc]
        size = 1 if op in ONE_BYTE else 2 if op in TWO_BYTE else 3
        if pc + size > len(code):
            raise SystemExit(f"AI module ends inside opcode ${op:02x} at {pc}")
        if size == 3 and op in ABSOLUTE:
            lo, hi = code[pc + 1], code[pc + 2]
            target = lo | (hi << 8)
            if op in ABS_OPS and hi == sentinel:
                map_sites.append(pc + 1)
            elif link <= target < link + len(code):
                internal.append(pc + 1)
        pc += size
    return internal, map_sites


def main() -> None:
    link = parse_mem_const("AI_LINK_BASE")
    sentinel = parse_mem_const("MAP_SMC_HI")
    found = 0
    for dos in DOS_NAMES:
        path = ENEMY_DIR / f"ai_{dos}.bin"
        if not path.is_file():
            continue
        code = path.read_bytes()
        internal, map_sites = scan(code, link, sentinel)
        out = ENEMY_DIR / f"ai_{dos}.rel"
        out.write_text(
            json.dumps(
                {"entry": 0, "internal": internal, "map": map_sites},
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
        print(
            f"{dos}: code={len(code)} internal={len(internal)} "
            f"map={len(map_sites)}"
        )
        found += 1
    if found == 0:
        raise SystemExit("genaimeta: no AI module binaries")


if __name__ == "__main__":
    main()
