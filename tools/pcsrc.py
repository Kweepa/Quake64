#!/usr/bin/env python3
"""Resolve a library sound name to Wolf inverse-freq bytes.

Sources live in ref/. Wolf and Doom are decimated 3x from 140 Hz. Dave and
Keen store PIT divisors and are resampled to 50 Hz. speaker.txt is not used.
"""
from __future__ import annotations

import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REF = ROOT / "ref"
WOLF_HED = REF / "AUDIOHED.WL1"
WOLF_AUD = REF / "AUDIOT.WL1"
DOOM_WAD = REF / "DOOM.WAD"
DAVE_EXE = REF / "DAVE.EXE"
SOUNDS_CK1 = REF / "SOUNDS.CK1"

PC_TIMER = 1193181
DECIMATE = 3
TICK_HZ = 50
MAX_TICKS = 255
KEEN_PIT = 0x2000
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

_BANKS: dict[str, dict[str, list[int]]] = {}


def decimate(data: list[int]) -> list[int]:
    samples: list[int] = []
    for i in range(0, len(data), DECIMATE):
        group = data[i : i + DECIMATE]
        samples.append(next((x for x in group if x), 0))
    if len(samples) > MAX_TICKS:
        raise SystemExit(f"decimated length {len(samples)} > {MAX_TICKS}")
    return samples


def pitch_hz(pitch: int) -> float:
    if pitch <= 0:
        return 0.0
    return 175.0 * (2 ** ((pitch - 1) / 24))


def hz_to_wolf(hz: float) -> int:
    if hz <= 0:
        return 0
    return max(1, min(255, round(PC_TIMER / (hz * 60))))


def divisor_to_wolf(divisor: int) -> int:
    if divisor <= 0:
        return 0
    return max(1, min(255, round(divisor / 60)))


def resample(samples: list[int], pit_div: int) -> list[int]:
    """Collapse PIT ticks onto 50 Hz. First non-zero in each bucket wins."""
    if not samples:
        return []
    if pit_div <= 0:
        pit_div = 65536
    step = TICK_HZ * pit_div
    out: list[int] = []
    acc = 0
    bucket: list[int] = []
    hold = 0
    for sample in samples:
        bucket.append(sample)
        acc += step
        while acc >= PC_TIMER and len(out) < MAX_TICKS:
            acc -= PC_TIMER
            if bucket:
                hold = next((x for x in bucket if x), 0)
                bucket = []
            out.append(hold)
        if len(out) >= MAX_TICKS:
            return out
    if bucket and len(out) < MAX_TICKS:
        out.append(next((x for x in bucket if x), 0))
    return out


def unpack_lz91(data: bytes) -> bytes:
    if data[0x1C:0x20] != b"LZ91":
        raise SystemExit("not an LZ91 executable")
    hdrsize = struct.unpack_from("<H", data, 8)[0]
    initcs = struct.unpack_from("<H", data, 0x16)[0]
    loader = initcs * 0x10 + hdrsize * 0x10
    indata = data[0x20:loader]
    out = bytearray()
    si = 0
    dx = 0x10
    bp = struct.unpack_from("<H", indata, si)[0]
    si += 2

    def getbit() -> int:
        nonlocal bp, si, dx
        bit = bp & 1
        bp >>= 1
        dx -= 1
        if dx == 0:
            bp = struct.unpack_from("<H", indata, si)[0]
            si += 2
            dx = 0x10
        return bit

    while True:
        if getbit():
            out.append(indata[si])
            si += 1
            continue
        if getbit() == 0:
            cx = (getbit() << 1) + getbit() + 2
            bx = indata[si] - 0x100
            si += 1
            for _ in range(cx):
                out.append(out[bx])
            continue
        ax = struct.unpack_from("<H", indata, si)[0]
        si += 2
        bx = ((ax >> 11) << 8) + (ax & 0xFF) - 0x2000
        ah = (ax >> 8) & 7
        if ah:
            for _ in range(ah + 2):
                out.append(out[bx])
            continue
        al = indata[si]
        si += 1
        if al == 0:
            break
        if al != 1:
            for _ in range(al + 1):
                out.append(out[bx])
    return bytes(out)


def _require(path: Path) -> bytes:
    if not path.is_file():
        raise SystemExit(f"missing {path}")
    return path.read_bytes()


def _load_wolf() -> dict[str, list[int]]:
    if len(WOLF_NAMES) != NUM_PC_SOUNDS:
        raise SystemExit(f"WOLF_NAMES {len(WOLF_NAMES)} != {NUM_PC_SOUNDS}")
    for idx, name in WOLF_CORE:
        if WOLF_NAMES[idx] != name:
            raise SystemExit(f"WOLF_NAMES[{idx}] is {WOLF_NAMES[idx]}, want {name}")
    hed = _require(WOLF_HED)
    aud = _require(WOLF_AUD)
    offs = [struct.unpack_from("<I", hed, i)[0] for i in range(0, len(hed), 4)]
    if len(offs) < NUM_PC_SOUNDS + 1:
        raise SystemExit(f"AUDIOHED too short: {len(offs)} offsets")
    out: dict[str, list[int]] = {}
    for i, name in enumerate(WOLF_NAMES):
        start = offs[i]
        end = offs[i + 1]
        chunk = aud[start:end]
        length, _priority = struct.unpack_from("<IH", chunk, 0)
        data = list(chunk[6 : 6 + length])
        if len(data) != length:
            raise SystemExit(f"{name}: truncated PC chunk")
        out[name] = decimate(data)
    if out["HITWALL"] != HITWALL:
        raise SystemExit(f"HITWALL decimate {out['HITWALL']} != {HITWALL}")
    return out


def _load_doom() -> dict[str, list[int]]:
    blob = _require(DOOM_WAD)
    ident = blob[:4]
    if ident not in (b"IWAD", b"PWAD"):
        raise SystemExit(f"{DOOM_WAD.name} is not a WAD ({ident!r})")
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
    out: dict[str, list[int]] = {}
    for name in order:
        buf = lumps[name]
        if len(buf) < 4:
            raise SystemExit(f"{name}: lump shorter than header")
        length = buf[2] | (buf[3] << 8)
        data = list(buf[4 : 4 + length])
        if len(data) != length:
            raise SystemExit(f"{name}: truncated (header {length}, got {len(data)})")
        freq = [hz_to_wolf(pitch_hz(p)) for p in decimate(data)]
        out[name] = freq
    return out


def _read_words(blob: bytes, offset: int) -> list[int]:
    words: list[int] = []
    p = offset
    while p + 1 < len(blob):
        word = struct.unpack_from("<H", blob, p)[0]
        p += 2
        if word == 0xFFFF:
            return words
        words.append(word)
    raise SystemExit(f"sound at {offset:#x} has no 0xFFFF terminator")


def _ident(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "", name).upper()


def _placeholder(name: str) -> bool:
    ident = _ident(name)
    return "UNUSED" in ident or ident == "UNNAMED"


def _parse_bank(blob: bytes, base: int, mode: str, blank_prefix: str) -> dict[str, list[int]]:
    sig = blob[base : base + 4]
    if sig not in (b"SPK\x00", b"SND\x00"):
        raise SystemExit(f"sound bank at {base:#x} is {sig!r}, want SPK or SND")
    _size, _unk, count = struct.unpack_from("<HHH", blob, base + 4)
    if count == 0:
        first = struct.unpack_from("<H", blob, base + 16)[0]
        count = first // 16 - 1
    if count <= 0:
        raise SystemExit(f"sound bank at {base:#x} has no entries")
    used: set[str] = set()
    invented = 0
    out: dict[str, list[int]] = {}
    for i in range(count):
        off = base + 16 * (i + 1)
        if off + 16 > len(blob):
            raise SystemExit(f"sound directory entry {i} is past the bank")
        doff, _pri, rate = struct.unpack_from("<HBB", blob, off)
        raw = blob[off + 4 : off + 16].split(b"\x00", 1)[0].decode("latin1")
        if _placeholder(raw):
            continue
        ident = _ident(raw)
        if not ident:
            invented += 1
            ident = f"{blank_prefix}{invented:02d}"
        base_name = ident
        n = 2
        while ident in used:
            ident = f"{base_name}{n}"
            n += 1
        used.add(ident)
        words = _read_words(blob, base + doff)
        if mode == "dave":
            pit = 65536 if rate <= 1 else 65536 // rate
        else:
            pit = KEEN_PIT
        out[ident] = resample([divisor_to_wolf(w) for w in words], pit)
    return out


def _load_dave() -> dict[str, list[int]]:
    image = unpack_lz91(_require(DAVE_EXE))
    base = image.find(b"SPK\x00")
    if base < 0:
        raise SystemExit(f"{DAVE_EXE.name} has no SPK sound bank")
    return _parse_bank(image, base, "dave", "DAVE")


def _load_keen() -> dict[str, list[int]]:
    blob = _require(SOUNDS_CK1)
    if not blob.startswith(b"SND\x00"):
        raise SystemExit(f"{SOUNDS_CK1.name} is not an SND sound bank")
    return _parse_bank(blob, 0, "keen", "KEEN")


_LOADERS = {
    "wolf": _load_wolf,
    "doom": _load_doom,
    "dave": _load_dave,
    "keen": _load_keen,
}


def bank(origin: str) -> dict[str, list[int]]:
    key = origin.strip().lower()
    if key not in _LOADERS:
        raise SystemExit(f"unknown sound library {origin!r}")
    cached = _BANKS.get(key)
    if cached is None:
        cached = _LOADERS[key]()
        _BANKS[key] = cached
    return cached


def names(origin: str) -> list[str]:
    return list(bank(origin))


def resolve(origin: str, name: str) -> list[int]:
    key = name.strip().upper()
    if not key:
        raise SystemExit("sound library name is empty")
    sounds = bank(origin)
    freq = sounds.get(key)
    if freq is None:
        raise SystemExit(f"unknown {origin} sound {key}")
    return list(freq)
