#!/usr/bin/env python3
"""Build src/pcsounds.asm from editor/quake64.json sounds (exported rows)."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
OUT = ROOT / "src" / "pcsounds.asm"
ENEMY_DIR = ROOT / "enemies"
PAYLOAD_MAX = 4096
MAX_TICKS = 255

# Pose PRG DOS names (must match tools/genenemies.py).
DOS_NAME = ["grunt", "knight", "rott", "scrag", "ogre", "shambl", "chthon", "zombie"]
HUM_DOS = [d for d in DOS_NAME if d != "rott"]
# Folder → pose files that carry a copy. HUM (soldier) cues are duplicated for now.
STREAM_FOLDERS = {
    "dog": ["rott"],
    "ogre": ["ogre"],
    "soldier": HUM_DOS,
}

# Locked aliases must exist so game lda #SOUND_* still assembles.
LOCKED = [
    ("HITWALL", "sound/weapons/tink1.wav"),
    ("PLAYERDEATH", "sound/player/death1.wav"),
    ("DOGDEATH", "sound/dog/ddeath.wav"),
    ("TAKEDAMAGE", "sound/player/pain1.wav"),
    ("OPENDOOR", "sound/doors/hydro1.wav"),
    ("HALT", "sound/soldier/sight1.wav"),
    ("ATKMACHINEGUN", "sound/weapons/spike2.wav"),
    ("HITENEMY", "sound/weapons/lhit.wav"),
    ("DEATHSCREAM1", "sound/soldier/death1.wav"),
    ("SHOOT", "sound/weapons/grenade.wav"),
    ("DOGBARK", "sound/dog/dsight.wav"),
    ("GETKEY", "sound/items/itembk2.wav"),
    ("GETAMMO", "sound/weapons/pkup.wav"),
    ("HEALTH1", "sound/items/health1.wav"),
    ("SWITCH", "sound/misc/menu2.wav"),
    ("BONUS1", "sound/items/damage.wav"),
    ("SHOTGN", "sound/weapons/shotgn2.wav"),
    ("BAREXP", "sound/weapons/r_exp3.wav"),
    ("SAWFUL", "sound/ogre/ogsawatk.wav"),
    ("SAWHIT", "sound/ogre/ogdrag.wav"),
    ("OOF", "sound/player/land.wav"),
    ("DMPAIN", "sound/dog/dpain1.wav"),
    ("POPAIN", "sound/soldier/pain1.wav"),
]
LOCKED_PATHS = {path: alias for alias, path in LOCKED}
EXTRA_ALIASES = {}
LOCKED_VOICE = {
    "HITWALL": 0,
    "PLAYERDEATH": 0,
    "DOGDEATH": 1,
    "TAKEDAMAGE": 0,
    "OPENDOOR": 2,
    "HALT": 1,
    "ATKMACHINEGUN": 0,
    "HITENEMY": 0,
    "DEATHSCREAM1": 1,
    "SHOOT": 1,
    "DOGBARK": 1,
    "GETKEY": 0,
    "GETAMMO": 0,
    "HEALTH1": 0,
    "SWITCH": 0,
    "BONUS1": 0,
    "SHOTGN": 0,
    "BAREXP": 0,
    "SAWFUL": 0,
    "SAWHIT": 0,
    "OOF": 0,
    "DMPAIN": 1,
    "POPAIN": 1,
}
LOCKED_PRI = {
    "HITWALL": 1,
    "PLAYERDEATH": 99,
    "DOGDEATH": 50,
    "TAKEDAMAGE": 90,
    "OPENDOOR": 20,
    "HALT": 50,
    "ATKMACHINEGUN": 50,
    "HITENEMY": 50,
    "DEATHSCREAM1": 50,
    "SHOOT": 20,
    "DOGBARK": 50,
    "GETKEY": 90,
    "GETAMMO": 80,
    "HEALTH1": 85,
    "SWITCH": 1,
    "BONUS1": 70,
    "SHOTGN": 50,
    "BAREXP": 50,
    "SAWFUL": 20,
    "SAWHIT": 50,
    "OOF": 50,
    "DMPAIN": 50,
    "POPAIN": 50,
}
WOLF_FREQ = {
    "HITWALL": [131, 142, 134],
    "PLAYERDEATH": [21, 30, 39, 45, 52, 15, 77, 98, 17, 0, 30, 0, 36, 0, 79, 79],
    "DOGDEATH": [19, 16, 15, 27, 40, 43, 57, 69, 83, 103, 111, 157, 145, 152, 159],
    "TAKEDAMAGE": [62, 59, 55, 52, 49, 63, 75, 80, 69, 78, 65, 77, 68, 62, 56, 74, 67, 61, 55],
    "OPENDOOR": [119, 118, 118, 116, 114, 111, 107, 101, 95, 89, 83, 77],
    "HALT": [42, 38, 35, 31, 31, 31, 32, 46, 60, 77, 85, 105, 132, 140, 145, 148, 151, 153, 157, 0, 0, 0, 138, 138, 138],
    "ATKMACHINEGUN": [104, 107, 101, 123],
    "HITENEMY": [130, 25, 33, 78, 26, 18, 18, 25, 0, 32],
    "DEATHSCREAM1": [60, 55, 51, 26, 37, 31, 15, 16, 23, 29, 74, 28, 31, 27, 34, 42, 38, 34, 36, 41],
    "SHOOT": [16, 110, 40, 40, 33, 103, 41, 115, 137],
    "DOGBARK": [64, 56, 47, 41, 142, 144, 37, 48, 144, 57, 67, 82, 93, 104, 123, 151, 151],
    "GETKEY": [36, 36, 36, 36, 36, 36, 36, 36, 0, 0, 55, 55, 55, 55, 55, 55, 55, 55, 0, 55, 55, 55, 55, 0, 25, 25, 25, 25, 25, 25],
    "GETAMMO": [34, 34, 34, 34, 34, 34, 0, 0, 0, 20, 20, 20, 0, 20, 20, 20, 20, 20, 20, 20, 20],
    "HEALTH1": [58, 0, 0, 51, 51, 0, 0, 38, 38, 0, 0, 22, 22, 0, 0, 22, 22, 22, 0, 0, 21, 21, 21],
    "SWITCH": [114, 60, 114],
    "BONUS1": [61, 53, 49, 46, 45, 51, 57, 64, 71, 74, 73, 69, 58, 41, 33, 30, 29, 28, 31, 35, 41, 46, 49, 47, 41, 30, 20, 0, 0, 0, 18, 18, 18, 0, 18, 18, 18, 18, 18, 18],
    "SHOTGN": [40, 57, 49, 60, 48, 52, 64, 68, 57, 74, 78, 81, 72, 70, 83, 107],
    "BAREXP": [81, 78, 60, 107, 83, 64, 32, 83, 107, 33, 36, 60, 44, 47, 64, 114, 107, 105, 26, 47, 47, 78, 101, 32, 83, 47, 43],
    "SAWFUL": [59, 47, 59, 37, 59, 47, 59],
    "SAWHIT": [48, 55, 44, 54, 36, 49, 30, 47, 26],
    "OOF": [83, 78, 78, 85],
    "DMPAIN": [15, 28, 31, 23, 31, 29, 38, 45, 45, 52, 64, 96],
    "POPAIN": [88, 62, 57, 39, 28, 35, 28, 28, 31, 44, 57, 81, 83],
}


def emit_bytes(arr: list[int], per_line: int = 16) -> str:
    lines = []
    for i in range(0, len(arr), per_line):
        chunk = arr[i : i + per_line]
        lines.append("\t!byte " + ", ".join(str(int(b) & 255) for b in chunk))
    return "\n".join(lines)


def ident_from_path(path: str) -> str:
    rest = path.replace("\\", "/")
    if rest.lower().startswith("sound/"):
        rest = rest[6:]
    if rest.lower().endswith(".wav"):
        rest = rest[:-4]
    ident = re.sub(r"[^A-Za-z0-9]+", "_", rest).strip("_").upper()
    return ident or "SFX"


def sound_folder(path: str) -> str:
    rest = path.replace("\\", "/")
    if rest.lower().startswith("sound/"):
        rest = rest[6:]
    i = rest.find("/")
    return rest[:i].lower() if i >= 0 else ""


def clamp_u8(n: int, lo: int, hi: int) -> int:
    v = int(n)
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v


def normalize_entry(path: str, raw: dict) -> dict:
    freq = [clamp_u8(x, 0, 255) for x in (raw.get("freq") or [])][:MAX_TICKS]
    vol = [clamp_u8(x, 0, 15) for x in (raw.get("vol") or [])][:MAX_TICKS]
    n = max(len(freq), len(vol))
    freq.extend([0] * (n - len(freq)))
    vol.extend([0] * (n - len(vol)))
    voice = clamp_u8(raw.get("voice", 0), 0, 2)
    priority = clamp_u8(raw.get("priority", 50), 0, 99)
    attack = clamp_u8(raw.get("attack", 0), 0, 15)
    alias = raw.get("alias")
    extra = list(raw.get("extraAliases") or [])
    locked_alias = LOCKED_PATHS.get(path)
    if locked_alias:
        extra = list(EXTRA_ALIASES.get(ident_from_path(path), []))
    return {
        "path": path,
        "export": True if locked_alias else bool(raw.get("export")),
        "alias": alias,
        "extraAliases": extra,
        "voice": voice,
        "priority": priority,
        "attack": attack,
        "freq": freq,
        "vol": vol,
    }


def main() -> None:
    if not DOC.is_file():
        raise SystemExit(f"missing {DOC}")
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    raw_sounds = doc.get("sounds") or {}
    if not isinstance(raw_sounds, dict):
        raise SystemExit("sounds must be an object")

    by_path: dict[str, dict] = {}
    for path, src in raw_sounds.items():
        key = str(path).replace("\\", "/").lower()
        if not key.startswith("sound/") or not key.endswith(".wav"):
            continue
        if not isinstance(src, dict):
            continue
        by_path[key] = normalize_entry(key, src)

    ordered: list[dict] = []
    used_idents: set[str] = set()

    for alias, path in LOCKED:
        snd = by_path.get(path)
        if not snd or not snd["freq"]:
            freq = WOLF_FREQ[alias]
            snd = normalize_entry(
                path,
                {
                    "export": True,
                    "alias": alias,
                    "voice": LOCKED_VOICE[alias],
                    "priority": LOCKED_PRI[alias],
                    "freq": freq,
                    "vol": [15] * len(freq),
                    "attack": 0,
                    "extraAliases": EXTRA_ALIASES.get(alias, []),
                },
            )
            by_path[path] = snd
        if not snd["freq"]:
            raise SystemExit(f"locked {path} missing samples")
        snd["export"] = True
        ident = ident_from_path(path)
        snd["alias"] = ident
        ordered.append(snd)
        used_idents.add(ident)
        for extra in snd["extraAliases"]:
            used_idents.add(extra)

    extras = []
    for path, snd in sorted(by_path.items()):
        if path in LOCKED_PATHS:
            continue
        if not snd["export"]:
            continue
        if not snd["freq"]:
            raise SystemExit(f"{path}: exported but empty")
        ident = ident_from_path(path)
        if ident in used_idents:
            raise SystemExit(f"{path}: ident SOUND_{ident} already used")
        snd["alias"] = ident
        extras.append(snd)
        used_idents.add(ident)
    ordered.extend(extras)

    equates: list[str] = []
    blocks: list[str] = []
    table_words: list[str] = []
    priorities: list[int] = []
    voices: list[int] = []
    streamed_flags: list[int] = []
    aliases: list[str] = []
    type_parts: dict[str, list[bytes]] = {d: [] for d in DOS_NAME}
    total = 0
    local_i = 0

    for snd in ordered:
        name = snd["alias"]
        freq = snd["freq"]
        vol = snd["vol"]
        n = len(freq)
        if n > MAX_TICKS:
            raise SystemExit(f"{name}: {n} ticks > {MAX_TICKS}")
        hosts = STREAM_FOLDERS.get(sound_folder(snd["path"]))
        body = [n, (snd["attack"] << 4) & 0xF0, *freq, *vol]
        equates.append(f"SOUND_{name}\t= {local_i}")
        for extra in snd.get("extraAliases") or []:
            aliases.append(f"SOUND_{extra}\t= SOUND_{name}")
        priorities.append(snd["priority"])
        voices.append(snd["voice"])
        if hosts:
            streamed_flags.append(1)
            table_words.append("0")
            packed = bytes([local_i, *body])
            for dos in hosts:
                if dos not in type_parts:
                    raise SystemExit(f"SOUND_{name}: unknown stream type {dos}")
                type_parts[dos].append(packed)
        else:
            streamed_flags.append(0)
            label = "pc_" + name.lower()
            total += len(body)
            blocks.append(f"{label}\n{emit_bytes(body)}")
            table_words.append(label)
        local_i += 1

    if total > PAYLOAD_MAX:
        raise SystemExit(f"resident sound payload {total} bytes > {PAYLOAD_MAX}")

    ENEMY_DIR.mkdir(parents=True, exist_ok=True)
    for dos, parts in type_parts.items():
        if len(parts) > 255:
            raise SystemExit(f"{dos}: {len(parts)} streamed effects > 255")
        blob = bytes([len(parts)]) + b"".join(parts)
        (ENEMY_DIR / f"sfx_{dos}.bin").write_bytes(blob)

    header = (
        "; Autogenerated by tools/gensounds.py from editor/quake64.json.\n"
        "; Each effect: N, AD (attack<<4, decay 0), freq[0..N-1], vol[0..N-1] (pulse, same Y).\n"
        "; freq = Wolf inverse-freq (0 = silence); vol = SID sustain nibble 0..15.\n"
        "; SOUND_* = FOLDER_STEM from the WAV path (sound/dog/ddeath.wav → SOUND_DOG_DDEATH).\n"
        "; Streamed enemy cues live on pose PRGs; sound_table hi=0 until bind.\n"
        "\n"
    )
    asm = (
        header
        + "!zone pcsounds\n\n"
        + "\n".join(equates)
        + "\n"
        + f"SOUND_COUNT\t= {local_i}\n"
        + ("\n" + "\n".join(aliases) + "\n" if aliases else "")
        + "\n"
        + "\n".join(blocks)
        + "\n\n"
        f"; resident sound payload {total} bytes\n"
        "sound_priorities\n"
        + emit_bytes(priorities)
        + "\n\n"
        "; 0 = player V1, 1 = enemy V2, 2 = world V3 (mixer; all pulse)\n"
        "sound_voices\n"
        + emit_bytes(voices)
        + "\n\n"
        "; 1 = payload on pose heap (sound_table patched at room stream)\n"
        "sound_streamed\n"
        + emit_bytes(streamed_flags)
        + "\n\n"
        "sound_table\n"
        + "\n".join(f"\t!word {w}" for w in table_words)
        + "\n"
    )
    OUT.write_text(asm, encoding="utf-8", newline="\n")
    streamed_n = sum(streamed_flags)
    print(
        f"wrote {OUT.relative_to(ROOT)} ({local_i} effects, {total} resident bytes, "
        f"{streamed_n} streamed)"
    )


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
