#!/usr/bin/env python3
"""Build editor/js/pclib.js from Wolf AUDIOT and Doom DP* lumps.

Wolf bytes are inverse-freq (0 = silence), decimated 3x from 140 Hz the same
way as wolf64 tools/gensounds.py. Doom pitch 0..95 is decimated the same way,
then mapped through pcsounds/speaker.txt into that Wolf byte.
"""
from __future__ import annotations

import re
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "editor" / "js" / "pclib.js"

WOLF_HED = Path(r"c:\dev\wolf64\shareware\AUDIOHED.WL1")
WOLF_AUD = Path(r"c:\dev\wolf64\shareware\AUDIOT.WL1")
DOOM_WAD = Path(r"C:\games\ChocDoom\DOOM.WAD")
SPEAKER = Path(r"c:\dev\squaredoom\pcsounds\speaker.txt")

DECIMATE = 3
PC_TIMER = 1193181
NUM_PC_SOUNDS = 87
HITWALL = [131, 142, 134]

# WL6 soundnames, SND suffix dropped. Indices match wolf64 CORE.
WOLF_NAMES = [
    "HITWALL",
    "SELECTWPN",
    "SELECTITEM",
    "HEARTBEAT",
    "MOVEGUN2",
    "MOVEGUN1",
    "NOWAY",
    "NAZIHITPLAYER",
    "SCHABBSTHROW",
    "PLAYERDEATH",
    "DOGDEATH",
    "ATKGATLING",
    "GETKEY",
    "NOITEM",
    "WALK1",
    "WALK2",
    "TAKEDAMAGE",
    "GAMEOVER",
    "OPENDOOR",
    "CLOSEDOOR",
    "DONOTHING",
    "HALT",
    "DEATHSCREAM2",
    "ATKKNIFE",
    "ATKPISTOL",
    "DEATHSCREAM3",
    "ATKMACHINEGUN",
    "HITENEMY",
    "SHOOTDOOR",
    "DEATHSCREAM1",
    "GETMACHINE",
    "GETAMMO",
    "SHOOT",
    "HEALTH1",
    "HEALTH2",
    "BONUS1",
    "BONUS2",
    "BONUS3",
    "GETGATLING",
    "ESCPRESSED",
    "LEVELDONE",
    "DOGBARK",
    "ENDBONUS1",
    "ENDBONUS2",
    "BONUS1UP",
    "BONUS4",
    "PUSHWALL",
    "NOBONUS",
    "PERCENT100",
    "BOSSACTIVE",
    "MUTTI",
    "SCHUTZAD",
    "AHHHG",
    "DIE",
    "EVA",
    "GUTENTAG",
    "LEBEN",
    "SCHEIST",
    "NAZIFIRE",
    "BOSSFIRE",
    "SSFIRE",
    "SLURPIE",
    "TOT_HUND",
    "MEINGOTT",
    "SCHABBSHA",
    "HITLERHA",
    "SPION",
    "NEINSOVAS",
    "DOGATTACK",
    "FLAMETHROWER",
    "MECHSTEP",
    "GOOBS",
    "YEAH",
    "DEATHSCREAM4",
    "DEATHSCREAM5",
    "DEATHSCREAM6",
    "DEATHSCREAM7",
    "DEATHSCREAM8",
    "DEATHSCREAM9",
    "DONNER",
    "EINE",
    "ERLAUBEN",
    "KEIN",
    "MEIN",
    "ROSE",
    "MISSILEFIRE",
    "MISSILEHIT",
]

# wolf64 tools/gensounds.py CORE (index, name). Names must match WOLF_NAMES.
WOLF_CORE = [
    (0, "HITWALL"),
    (9, "PLAYERDEATH"),
    (10, "DOGDEATH"),
    (11, "ATKGATLING"),
    (16, "TAKEDAMAGE"),
    (18, "OPENDOOR"),
    (19, "CLOSEDOOR"),
    (21, "HALT"),
    (22, "DEATHSCREAM2"),
    (24, "ATKPISTOL"),
    (25, "DEATHSCREAM3"),
    (26, "ATKMACHINEGUN"),
    (27, "HITENEMY"),
    (29, "DEATHSCREAM1"),
    (32, "SHOOT"),
    (41, "DOGBARK"),
    (51, "SCHUTZAD"),
    (52, "AHHHG"),
    (58, "NAZIFIRE"),
    (60, "SSFIRE"),
    (23, "ATKKNIFE"),
    (12, "GETKEY"),
    (30, "GETMACHINE"),
    (31, "GETAMMO"),
    (33, "HEALTH1"),
    (34, "HEALTH2"),
    (40, "LEVELDONE"),
    (46, "PUSHWALL"),
    (4, "MOVEGUN2"),
    (5, "MOVEGUN1"),
    (39, "ESCPRESSED"),
    (35, "BONUS1"),
]


def decimate(data: list[int]) -> list[int]:
    samples: list[int] = []
    for i in range(0, len(data), DECIMATE):
        group = data[i : i + DECIMATE]
        samples.append(next((x for x in group if x), 0))
    if len(samples) > 255:
        raise SystemExit(f"decimated length {len(samples)} > 255")
    return samples


def pitch_hz(pitch: int, table: list[float]) -> float:
    if pitch <= 0:
        return 0.0
    if pitch < len(table) and table[pitch] > 0:
        return table[pitch]
    # speaker.txt covers 1..95 (24 steps/octave, value 1 = 175 Hz).
    # DPPLASMA uses 96; keep the same scale past the printed table.
    return 175.0 * (2 ** ((pitch - 1) / 24))


def hz_to_wolf(hz: float) -> int:
    if hz <= 0:
        return 0
    return max(1, min(255, round(PC_TIMER / (hz * 60))))


def parse_speaker(text: str) -> list[float]:
    hz = [0.0] * 96
    row = re.compile(r"^(\d+)\s+(\d+|-)\s+([\d.]+|-)")
    for line in text.splitlines():
        m = row.match(line)
        if not m:
            continue
        v = int(m.group(1))
        if 1 <= v <= 95 and m.group(3) != "-":
            hz[v] = float(m.group(3))
    missing = [i for i in range(1, 96) if hz[i] <= 0]
    if missing:
        raise SystemExit(f"speaker.txt missing pitch {missing[0]}")
    return hz


def load_wolf() -> list[dict]:
    if len(WOLF_NAMES) != NUM_PC_SOUNDS:
        raise SystemExit(f"WOLF_NAMES {len(WOLF_NAMES)} != {NUM_PC_SOUNDS}")
    for idx, name in WOLF_CORE:
        if WOLF_NAMES[idx] != name:
            raise SystemExit(f"WOLF_NAMES[{idx}] is {WOLF_NAMES[idx]}, want {name}")
    hed = WOLF_HED.read_bytes()
    aud = WOLF_AUD.read_bytes()
    offs = [struct.unpack_from("<I", hed, i)[0] for i in range(0, len(hed), 4)]
    if len(offs) < NUM_PC_SOUNDS + 1:
        raise SystemExit(f"AUDIOHED too short: {len(offs)} offsets")
    out = []
    for i, name in enumerate(WOLF_NAMES):
        start = offs[i]
        end = offs[i + 1]
        chunk = aud[start:end]
        length, _priority = struct.unpack_from("<IH", chunk, 0)
        data = list(chunk[6 : 6 + length])
        if len(data) != length:
            raise SystemExit(f"{name}: truncated PC chunk")
        freq = decimate(data)
        out.append({"name": name, "freq": freq})
    if out[0]["freq"] != HITWALL:
        raise SystemExit(f"HITWALL decimate {out[0]['freq']} != {HITWALL}")
    return out


def load_doom(hz: list[float]) -> list[dict]:
    blob = DOOM_WAD.read_bytes()
    ident = blob[:4]
    if ident not in (b"IWAD", b"PWAD"):
        raise SystemExit(f"{DOOM_WAD} is not a WAD ({ident!r})")
    numlumps, dirofs = struct.unpack_from("<II", blob, 4)
    order: list[str] = []
    lumps: dict[str, bytes] = {}
    for i in range(numlumps):
        o = dirofs + i * 16
        filepos, size = struct.unpack_from("<II", blob, o)
        name = blob[o + 8 : o + 16].split(b"\0", 1)[0].decode("ascii", "replace").upper()
        if not name.startswith("DP"):
            continue
        if name not in lumps:
            order.append(name)
        lumps[name] = blob[filepos : filepos + size]
    if len(order) != 67:
        raise SystemExit(f"expected 67 unique DP lumps, got {len(order)}")
    out = []
    for name in order:
        buf = lumps[name]
        if len(buf) < 4:
            raise SystemExit(f"{name}: lump shorter than header")
        length = buf[2] | (buf[3] << 8)
        data = list(buf[4 : 4 + length])
        if len(data) != length:
            raise SystemExit(f"{name}: truncated (header {length}, got {len(data)})")
        for b in data:
            if b > 255:
                raise SystemExit(f"{name}: pitch {b} out of range")
        freq = [hz_to_wolf(pitch_hz(p, hz)) for p in decimate(data)]
        out.append({"name": name, "freq": freq})
    return out


def emit_side(rows: list[dict]) -> str:
    lines = []
    for row in rows:
        freq = ", ".join(str(b) for b in row["freq"])
        lines.append(f'    {{ name: "{row["name"]}", freq: [{freq}] }},')
    return "\n".join(lines)


def main() -> None:
    for path in (WOLF_HED, WOLF_AUD, DOOM_WAD, SPEAKER):
        if not path.is_file():
            raise SystemExit(f"missing {path}")
    wolf = load_wolf()
    doom = load_doom(parse_speaker(SPEAKER.read_text(encoding="utf-8")))
    js = (
        "// Autogenerated by tools/genpclib.py. Wolf inverse-freq and Doom pitch\n"
        "// decimated 3x from 140 Hz. Doom pitch is already converted to Wolf bytes.\n"
        "\n"
        "export const PC_LIBRARY = {\n"
        "  wolf: [\n"
        f"{emit_side(wolf)}\n"
        "  ],\n"
        "  doom: [\n"
        f"{emit_side(doom)}\n"
        "  ],\n"
        "};\n"
    )
    OUT.write_text(js, encoding="utf-8", newline="\n")
    print(f"wrote {OUT.relative_to(ROOT)} ({len(wolf)} wolf, {len(doom)} doom)")


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
