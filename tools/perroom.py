#!/usr/bin/env python3
"""Locate en_type / en_room inside a packed map payload.

The packed layout is defined in exactly one place: bind_map in src/loader.asm,
which walks the payload adding one array per `+bind_add field, count`. Rather
than duplicate that order here and let the two drift, this parses bind_map and
replays it.

Payload layout:
    24 bytes  counts header (map_nrooms .. spawn_id, see src/map_bss.asm)
    n bytes   NUL-terminated map name
    ...       the bind_add arrays, in source order

Counts are either a header symbol or `bind_n`, which bind_map recomputes twice
(nrooms*3 for the rc_* colliders, nrooms*2 for the rb_* boxes).

Everything extracted is validated before use: room ids must be < map_nrooms and
type ids < ENEMY_NTYPES. If the layout is ever changed without this being
updated, the values go out of range and the caller is told, rather than being
handed a confident wrong answer.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / "src" / "loader.asm"
MAP_BSS = ROOT / "src" / "map_bss.asm"

HDR_LEN = 24
ENEMY_NTYPES = 7


def header_symbols() -> list[str]:
    """The 24 count bytes, in address order, from map_bss.asm."""
    text = MAP_BSS.read_text(encoding="utf-8", errors="replace")
    found: dict[int, str] = {}
    for m in re.finditer(r"^([a-z_0-9]+)\s*=\s*\$0([0-9a-fA-F]{3})\s*$",
                         text, re.M):
        addr = int(m.group(2), 16)
        if 0x400 <= addr < 0x400 + HDR_LEN:
            found.setdefault(addr, m.group(1))
    if len(found) != HDR_LEN:
        raise SystemExit(
            f"perroom: expected {HDR_LEN} header symbols at $0400, "
            f"found {len(found)}")
    return [found[0x400 + i] for i in range(HDR_LEN)]


def bind_sequence() -> list[tuple[str, str]]:
    """[(field, count_expr)] in bind_map order, count_expr already resolved
    for the two bind_n recomputations."""
    text = LOADER.read_text(encoding="utf-8", errors="replace")
    m = re.search(r"^bind_map\b(.*?)^\s*rts", text, re.M | re.S)
    if not m:
        raise SystemExit("perroom: no bind_map in loader.asm")
    body = m.group(1)

    seq: list[tuple[str, str]] = []
    pending = None      # what bind_n currently holds
    for line in body.splitlines():
        s = line.strip()
        # bind_map sets bind_n twice; both are multiples of map_nrooms and
        # both are annotated. Match the arithmetic, not the comment.
        if re.match(r"^sta\s+bind_n\b", s):
            if pending is None:
                raise SystemExit("perroom: sta bind_n with no preceding shift")
            continue
        if re.match(r"^asl\s*$", s):
            pending = "nrooms*2"
            continue
        if re.match(r"^adc\s+map_nrooms\b", s) and pending == "nrooms*2":
            pending = "nrooms*3"
            continue
        b = re.match(r"^\+bind_add\s+([a-z_0-9]+)\s*,\s*([a-z_0-9]+)\s*$", s)
        if b:
            field, count = b.group(1), b.group(2)
            if count == "bind_n":
                if pending is None:
                    raise SystemExit(
                        f"perroom: {field} uses bind_n before it is set")
                count = pending
            seq.append((field, count))
    if not seq:
        raise SystemExit("perroom: bind_map has no bind_add lines")
    return seq


def field_offsets(payload: bytes) -> tuple[dict[str, int], dict[str, int]]:
    """(offset of each field, header counts). Offsets are into payload."""
    if len(payload) < HDR_LEN:
        raise SystemExit("perroom: payload shorter than the header")
    syms = header_symbols()
    counts = {syms[i]: payload[i] for i in range(HDR_LEN)}

    # map name, NUL-terminated, follows the header
    end = payload.find(b"\x00", HDR_LEN)
    if end < 0:
        raise SystemExit("perroom: unterminated map name")
    cur = end + 1

    def resolve(expr: str) -> int:
        if expr == "nrooms*2":
            return counts["map_nrooms"] * 2
        if expr == "nrooms*3":
            return counts["map_nrooms"] * 3
        if expr in counts:
            return counts[expr]
        raise SystemExit(f"perroom: unknown count `{expr}`")

    offs: dict[str, int] = {}
    for field, count in bind_sequence():
        offs[field] = cur
        cur += resolve(count)
    if cur > len(payload):
        raise SystemExit(
            f"perroom: replayed layout runs {cur - len(payload)} bytes past "
            f"the payload -- bind_map and this tool disagree")
    return offs, counts


def per_room_types(payload: bytes) -> dict[int, set[int]]:
    """{room: {enemy type, ...}} for every room holding enemies."""
    offs, counts = field_offsets(payload)
    n = counts["map_nenemies"]
    if n == 0:
        return {}
    for need in ("en_type", "en_room"):
        if need not in offs:
            raise SystemExit(f"perroom: bind_map has no {need}")
    types = payload[offs["en_type"]:offs["en_type"] + n]
    rooms = payload[offs["en_room"]:offs["en_room"] + n]
    if len(types) != n or len(rooms) != n:
        raise SystemExit("perroom: enemy arrays run past the payload")

    # Validate before anyone acts on it. Wrong offsets produce garbage that
    # would otherwise sail through as a confident, wrong heap figure.
    nrooms = counts["map_nrooms"]
    for t in types:
        if t >= ENEMY_NTYPES:
            raise SystemExit(
                f"perroom: enemy type {t} out of range (>= {ENEMY_NTYPES}); "
                f"the packed layout has changed and this tool is stale")
    for r in rooms:
        if r >= nrooms:
            raise SystemExit(
                f"perroom: enemy room {r} out of range (>= {nrooms}); "
                f"the packed layout has changed and this tool is stale")

    out: dict[int, set[int]] = {}
    for r, t in zip(rooms, types):
        out.setdefault(r, set()).add(t)
    return out
