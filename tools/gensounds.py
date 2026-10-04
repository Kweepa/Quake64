#!/usr/bin/env python3
"""Build src/pcsounds.asm from editor/quake64.json sounds.

Exported = locked resident alias, or named by an enemy's cues
(sight/wince/melee/shoot/death). Cue sounds ride on that enemy's pose bank."""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from pcsrc import resolve

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
OUT = ROOT / "src" / "pcsounds.asm"
ENEMY_DIR = ROOT / "enemies"
PAYLOAD_MAX = 4096
MAX_TICKS = 255

# Pose PRG DOS names (must match tools/genenemies.py).
TYPES = ["Grunt", "Knight", "Rottweiler", "Scrag", "Ogre", "Shambler", "Chthon", "Zombie", "Demon"]
DOS_NAME = ["grunt", "knight", "rott", "scrag", "ogre", "shambl", "chthon", "zombie", "demon"]
# Fixed per-enemy cue set. sight/wince/death are required; melee/shoot are optional.
CUES = ["sight", "wince", "melee", "shoot", "death"]
CUES_REQUIRED = ["sight", "wince", "death"]

# Locked aliases must exist so game lda #SOUND_* still assembles.
LOCKED = [
    ("HITWALL", "sound/weapons/tink1.wav"),
    ("PLAYERDEATH", "sound/player/death1.wav"),
    ("TAKEDAMAGE", "sound/player/pain1.wav"),
    ("OPENDOOR", "sound/doors/hydro1.wav"),
    ("ATKMACHINEGUN", "sound/weapons/spike2.wav"),
    ("HITENEMY", "sound/weapons/lhit.wav"),
    ("SHOOT", "sound/weapons/grenade.wav"),
    ("GETKEY", "sound/items/itembk2.wav"),
    ("GETAMMO", "sound/weapons/pkup.wav"),
    ("HEALTH1", "sound/items/health1.wav"),
    ("SWITCH", "sound/misc/menu2.wav"),
    ("BONUS1", "sound/items/damage.wav"),
    ("SHOTGN", "sound/weapons/shotgn2.wav"),
    ("BAREXP", "sound/weapons/r_exp3.wav"),
    ("OOF", "sound/player/land.wav"),
]
LOCKED_PATHS = {path: alias for alias, path in LOCKED}
EXTRA_ALIASES = {}
LOCKED_VOICE = {
    "HITWALL": 0,
    "PLAYERDEATH": 0,
    "TAKEDAMAGE": 0,
    "OPENDOOR": 2,
    "ATKMACHINEGUN": 0,
    "HITENEMY": 0,
    "SHOOT": 1,
    "GETKEY": 0,
    "GETAMMO": 0,
    "HEALTH1": 0,
    "SWITCH": 0,
    "BONUS1": 0,
    "SHOTGN": 0,
    "BAREXP": 0,
    "OOF": 0,
}
LOCKED_PRI = {
    "HITWALL": 1,
    "PLAYERDEATH": 99,
    "TAKEDAMAGE": 90,
    "OPENDOOR": 20,
    "ATKMACHINEGUN": 50,
    "HITENEMY": 50,
    "SHOOT": 20,
    "GETKEY": 90,
    "GETAMMO": 80,
    "HEALTH1": 85,
    "SWITCH": 1,
    "BONUS1": 70,
    "SHOTGN": 50,
    "BAREXP": 50,
    "OOF": 50,
}
# Locked path → (origin, library name). BAREXP exports no samples.
LOCKED_LIB = {
    "HITWALL": ("wolf", "HITWALL"),
    "PLAYERDEATH": ("wolf", "PLAYERDEATH"),
    "TAKEDAMAGE": ("wolf", "TAKEDAMAGE"),
    "OPENDOOR": ("wolf", "OPENDOOR"),
    "ATKMACHINEGUN": ("wolf", "ATKMACHINEGUN"),
    "HITENEMY": ("wolf", "HITENEMY"),
    "SHOOT": ("wolf", "SHOOT"),
    "GETKEY": ("wolf", "GETKEY"),
    "GETAMMO": ("wolf", "GETAMMO"),
    "HEALTH1": ("wolf", "HEALTH1"),
    "SWITCH": ("wolf", "MOVEGUN1"),
    "BONUS1": ("wolf", "BONUS1"),
    "SHOTGN": ("doom", "DPSHOTGN"),
    "BAREXP": None,
    "OOF": ("doom", "DPOOF"),
}
LIBRARY_ORIGINS = {"wolf", "doom", "dave", "keen"}


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


def clamp_u8(n: int, lo: int, hi: int) -> int:
    v = int(n)
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v


def library_freq(path: str, raw: dict, locked_alias: str | None) -> list[int]:
    origin = str(raw.get("origin") or "").strip().lower()
    library = str(raw.get("library") or "").strip().upper()
    # Empty cue (BAREXP, or a placeholder export with no library yet): no samples.
    if locked_alias == "BAREXP" or origin in ("", "empty"):
        return []
    if origin in LIBRARY_ORIGINS:
        if not library:
            raise SystemExit(f"{path}: exported sound has no library name")
        freq = resolve(origin, library)
    elif locked_alias:
        pair = LOCKED_LIB[locked_alias]
        freq = [] if pair is None else resolve(*pair)
    elif raw.get("export"):
        raise SystemExit(f"{path}: exported sound has no library name")
    else:
        return []
    if len(freq) > MAX_TICKS:
        raise SystemExit(f"{path}: {len(freq)} ticks > {MAX_TICKS}")
    return [clamp_u8(x, 0, 255) for x in freq]


def normalize_entry(path: str, raw: dict) -> dict:
    locked_alias = LOCKED_PATHS.get(path)
    freq = library_freq(path, raw, locked_alias)
    voice = clamp_u8(raw.get("voice", 0), 0, 2)
    priority = clamp_u8(raw.get("priority", 50), 0, 99)
    attack = clamp_u8(raw.get("attack", 0), 0, 15)
    alias = raw.get("alias")
    extra = list(raw.get("extraAliases") or [])
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
    }


def cue_path(raw) -> str:
    p = str(raw or "").strip().replace("\\", "/").lower()
    return p if p.startswith("sound/") and p.endswith(".wav") else ""


def load_cue_hosts(doc: dict, known: set[str]) -> dict[str, list[str]]:
    """Validate every enemy's cues; return path -> pose DOS names that reference it."""
    by_name = {e.get("name"): e for e in doc.get("enemies") or []}
    hosts: dict[str, list[str]] = {}
    for name, dos in zip(TYPES, DOS_NAME):
        enemy = by_name.get(name)
        if enemy is None:
            raise SystemExit(f"missing enemy {name}")
        cues = enemy.get("cues") or {}
        for extra in cues:
            if extra not in CUES:
                raise SystemExit(f"{name}: unknown cue {extra!r} (allowed: {', '.join(CUES)})")
        for cue in CUES:
            raw = cues.get(cue)
            path = cue_path(raw)
            if not path:
                if cue in CUES_REQUIRED:
                    raise SystemExit(f"{name}: required cue '{cue}' is not set")
                if raw:
                    raise SystemExit(f"{name}: cue '{cue}' is not a sound path: {raw!r}")
                continue
            # The path is only a key into sounds (origin + library). No entry means
            # the cue is unset. A missing wav file is not an error.
            if path not in known and path not in LOCKED_PATHS:
                if cue in CUES_REQUIRED:
                    raise SystemExit(f"{name}: required cue '{cue}' has no sound")
                continue
            if dos not in hosts.setdefault(path, []):
                hosts[path].append(dos)
    return hosts


def main() -> None:
    if not DOC.is_file():
        raise SystemExit(f"missing {DOC}")
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    raw_sounds = doc.get("sounds") or {}
    if not isinstance(raw_sounds, dict):
        raise SystemExit("sounds must be an object")

    # path -> pose types (DOS names) whose cue set references it.
    cue_hosts = load_cue_hosts(doc, {str(p).replace("\\", "/").lower() for p in raw_sounds})

    by_path: dict[str, dict] = {}
    for path, src in raw_sounds.items():
        key = str(path).replace("\\", "/").lower()
        if not key.startswith("sound/") or not key.endswith(".wav"):
            continue
        if not isinstance(src, dict):
            continue
        # Exported = resident alias or referenced by an enemy cue. Nothing else ships.
        src = {**src, "export": key in cue_hosts or key in LOCKED_PATHS}
        by_path[key] = normalize_entry(key, src)

    ordered: list[dict] = []
    used_idents: set[str] = set()

    for alias, path in LOCKED:
        snd = by_path.get(path)
        if not snd:
            pair = LOCKED_LIB[alias]
            fallback = {
                "export": True,
                "alias": alias,
                "voice": LOCKED_VOICE[alias],
                "priority": LOCKED_PRI[alias],
                "attack": 0,
                "extraAliases": EXTRA_ALIASES.get(alias, []),
                "origin": "empty" if pair is None else pair[0],
            }
            if pair is not None:
                fallback["library"] = pair[1]
            snd = normalize_entry(path, fallback)
            by_path[path] = snd
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
        n = len(freq)
        if n > MAX_TICKS:
            raise SystemExit(f"{name}: {n} ticks > {MAX_TICKS}")
        # Resident aliases stay resident (game code plays them by name); every
        # other exported sound rides on the pose banks of the enemies whose cues name it.
        hosts = None if snd["path"] in LOCKED_PATHS else cue_hosts.get(snd["path"])
        body = [n, (snd["attack"] << 4) & 0xF0, *freq]
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

    ids = {snd["alias"]: i for i, snd in enumerate(ordered)}
    for i, snd in enumerate(ordered):
        for extra in snd.get("extraAliases") or []:
            ids[extra] = i
    (ENEMY_DIR / "sound_ids.json").write_text(json.dumps(ids, indent=2) + "\n", encoding="utf-8")

    header = (
        "; Autogenerated by tools/gensounds.py from editor/quake64.json.\n"
        "; Each effect: N, AD (attack<<4, decay 0), freq[0..N-1].\n"
        "; freq = Wolf inverse-freq (0 = silence). Sustain is full; master is effects_vol.\n"
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
        f"{streamed_n} streamed, wrote enemies/sound_ids.json)"
    )


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(0)
