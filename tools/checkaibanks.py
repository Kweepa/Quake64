#!/usr/bin/env python3
"""Validate fused QAI1 banks and relocation records."""

from __future__ import annotations

import struct
from pathlib import Path

from genaibanks import DOS_NAMES, HEADER_SIZE, MAGIC, NO_ENTRY
from genaimeta import scan
from mkreloc import parse_mem_const

ROOT = Path(__file__).resolve().parents[1]
ENEMY_DIR = ROOT / "enemies"


def main() -> None:
    link = parse_mem_const("AI_LINK_BASE")
    sentinel = parse_mem_const("MAP_SMC_HI")
    for dos in DOS_NAMES:
        path = ENEMY_DIR / f"{dos}.prg"
        raw = path.read_bytes()
        if len(raw) < 2 + HEADER_SIZE:
            raise SystemExit(f"{path}: too short")
        payload = raw[2:]
        magic, code_n, rel_n, map_n, entry, pose_off = struct.unpack_from(
            "<4sHHHHH", payload, 0
        )
        if magic != MAGIC:
            raise SystemExit(f"{path}: bad magic {magic!r}")
        code_off = HEADER_SIZE + 2 * (rel_n + map_n)
        if pose_off != code_off + code_n or pose_off >= len(payload):
            raise SystemExit(f"{path}: inconsistent code/pose offsets")
        if entry != NO_ENTRY and not (code_off <= entry < pose_off):
            raise SystemExit(f"{path}: entry outside code")
        words = list(struct.unpack_from(f"<{rel_n + map_n}H", payload, HEADER_SIZE))
        internal = [off - code_off for off in words[:rel_n]]
        map_sites = [off - code_off for off in words[rel_n:]]
        code = payload[code_off:pose_off]
        scanned_internal, scanned_map = scan(code, link, sentinel)
        if internal != scanned_internal or map_sites != scanned_map:
            raise SystemExit(f"{path}: relocation metadata does not match code")
        for off in internal:
            target = code[off] | (code[off + 1] << 8)
            if not (link <= target < link + code_n):
                raise SystemExit(f"{path}: internal target ${target:04x} outside module")
        if len(payload) - pose_off < 2:
            raise SystemExit(f"{path}: missing pose header")
        print(
            f"{dos}: ok bank={len(payload)} code={code_n} "
            f"reloc={rel_n} map={map_n} pose={len(payload) - pose_off}"
        )


if __name__ == "__main__":
    main()
