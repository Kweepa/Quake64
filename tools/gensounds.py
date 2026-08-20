#!/usr/bin/env python3
"""
Build Quake64 src/pcsounds.asm from sibling Wolf64 + SquareDoom banks.

Wolf effects are copied as-is (already 3× first-nonzero decimated).
SquareDoom-only lumps: Doom pitch → Hz → nearest Wolf inverse-freq byte,
then the same 3× first-nonzero decimate for ~50 Hz Timer A playback.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WOLF_ASM = ROOT.parent / "Wolf64" / "src" / "pcsounds.asm"
DOOM_ASM = ROOT.parent / "SquareDoom" / "dpsounds.asm"
SPEAKER = ROOT.parent / "SquareDoom" / "pcsounds" / "speaker.txt"
OUT = ROOT / "src" / "pcsounds.asm"

DECIMATE = 3
PC_BASE_TIMER = 1193181

# Wolf CORE names to keep (skip menu-only MOVEGUN2 / ESCPRESSED).
# MOVEGUN1 is emitted as SOUND_SWITCH (alias SOUND_MOVEGUN1).
WOLF_KEEP = [
    "HITWALL",
    "PLAYERDEATH",
    "DOGDEATH",
    "ATKGATLING",
    "TAKEDAMAGE",
    "OPENDOOR",
    "CLOSEDOOR",
    "HALT",
    "DEATHSCREAM2",
    "ATKPISTOL",
    "DEATHSCREAM3",
    "ATKMACHINEGUN",
    "HITENEMY",
    "DEATHSCREAM1",
    "SHOOT",
    "DOGBARK",
    "SCHUTZAD",
    "AHHHG",
    "NAZIFIRE",
    "SSFIRE",
    "ATKKNIFE",
    "GETKEY",
    "GETMACHINE",
    "GETAMMO",
    "HEALTH1",
    "HEALTH2",
    "LEVELDONE",
    "PUSHWALL",
    "MOVEGUN1",
    "BONUS1",
]

# SquareDoom lumps with no Wolf equivalent. Priority: Doom 0/1/2 → 0/20/50.
DOOM_KEEP = [
    ("dpstnmov", "STNMOV", 0),
    ("dpshotgn", "SHOTGN", 50),
    ("dpsgcock", "SGCOCK", 50),
    ("dpbarexp", "BAREXP", 50),
    ("dpclaw", "CLAW", 50),
    ("dpsawidl", "SAWIDL", 0),
    ("dpsawful", "SAWFUL", 20),
    ("dpsawhit", "SAWHIT", 50),
    ("dpbgact", "GURGLE", 0),
    ("dpoof", "OOF", 50),
    ("dpdmpain", "DMPAIN", 50),
    ("dppopain", "POPAIN", 50),
    ("dpsgtdth", "SGTDTH", 50),
]

# SID channel: 0 = player V1 pulse, 1 = enemy V2 pulse, 2 = world V3 noise
VOICE_WORLD = frozenset({"OPENDOOR", "CLOSEDOOR", "STNMOV", "PUSHWALL"})
VOICE_ENEMY = frozenset(
    {
        "DOGDEATH",
        "HALT",
        "DEATHSCREAM1",
        "DEATHSCREAM2",
        "DEATHSCREAM3",
        "SHOOT",
        "DOGBARK",
        "SCHUTZAD",
        "NAZIFIRE",
        "SSFIRE",
        "CLAW",
        "GURGLE",
        "DMPAIN",
        "POPAIN",
        "SGTDTH",
    }
)


def sound_voice(name: str) -> int:
    if name in VOICE_WORLD:
        return 2
    if name in VOICE_ENEMY:
        return 1
    return 0


def emit_bytes(arr: list[int], per_line: int = 16) -> str:
    lines = []
    for i in range(0, len(arr), per_line):
        chunk = arr[i : i + per_line]
        lines.append("\t!byte " + ", ".join(str(b) for b in chunk))
    return "\n".join(lines)


def parse_byte_lines(block: str) -> list[int]:
    data: list[int] = []
    for line in block.splitlines():
        if "!byte" not in line:
            continue
        payload = line.split("!byte", 1)[1]
        data.extend(int(x.strip()) for x in payload.split(",") if x.strip())
    return data


def parse_wolf(text: str) -> tuple[dict[str, int], dict[str, list[int]], list[int]]:
    names = {n: int(i) for n, i in re.findall(r"SOUND_(\w+)\s*=\s*(\d+)", text)}
    bodies: dict[str, list[int]] = {}
    for m in re.finditer(r"^(pc_\w+)\n((?:\t!byte .+\n?)+)", text, re.M):
        bodies[m.group(1)] = parse_byte_lines(m.group(2))
    pri: list[int] = []
    pm = re.search(r"sound_priorities\n((?:\t!byte .+\n)+)", text)
    if not pm:
        raise SystemExit("Wolf sound_priorities not found")
    pri = parse_byte_lines(pm.group(1))
    return names, bodies, pri


def parse_doom(text: str) -> dict[str, list[int]]:
    bodies: dict[str, list[int]] = {}
    for m in re.finditer(r"^(dp\w+)\n((?:\t!byte .+\n?)+)", text, re.M):
        raw = parse_byte_lines(m.group(2))
        if not raw:
            raise SystemExit(f"{m.group(1)}: empty")
        count, pitches = raw[0], raw[1:]
        if count != len(pitches):
            raise SystemExit(f"{m.group(1)}: count {count} != {len(pitches)}")
        bodies[m.group(1)] = pitches
    return bodies


def parse_speaker_hz(text: str) -> list[float]:
    hz = [0.0] * 96
    for line in text.splitlines():
        m = re.match(r"^(\d+)\s+(\d+|-)\s+([\d.]+|-)", line)
        if not m:
            continue
        v = int(m.group(1))
        if 1 <= v <= 95 and m.group(3) != "-":
            hz[v] = float(m.group(3))
    return hz


def hz_to_wolf_byte(hz: float) -> int:
    if hz <= 0:
        return 0
    b = round(PC_BASE_TIMER / (hz * 60.0))
    return max(1, min(255, int(b)))


def decimate(data: list[int]) -> list[int]:
    samples = []
    for i in range(0, len(data), DECIMATE):
        group = data[i : i + DECIMATE]
        samples.append(next((x for x in group if x), 0))
    if len(samples) > 255:
        raise SystemExit(f"decimated length {len(samples)} > 255")
    return samples


def main() -> None:
    if not WOLF_ASM.is_file():
        raise SystemExit(f"missing {WOLF_ASM}")
    if not DOOM_ASM.is_file():
        raise SystemExit(f"missing {DOOM_ASM}")
    if not SPEAKER.is_file():
        raise SystemExit(f"missing {SPEAKER}")

    wolf_names, wolf_bodies, wolf_pri = parse_wolf(WOLF_ASM.read_text(encoding="utf-8"))
    doom_bodies = parse_doom(DOOM_ASM.read_text(encoding="utf-8"))
    pitch_hz = parse_speaker_hz(SPEAKER.read_text(encoding="utf-8"))

    equates: list[str] = []
    blocks: list[str] = []
    labels: list[str] = []
    priorities: list[int] = []
    voices: list[int] = []
    aliases: list[str] = []
    total = 0
    local_i = 0

    for name in WOLF_KEEP:
        if name not in wolf_names:
            raise SystemExit(f"Wolf SOUND_{name} missing")
        src_i = wolf_names[name]
        label = f"pc_{name.lower()}"
        if name == "MOVEGUN1":
            emit_name = "SWITCH"
            emit_label = "pc_switch"
            aliases.append(f"SOUND_MOVEGUN1\t= SOUND_SWITCH")
        else:
            emit_name = name
            emit_label = label
        body = wolf_bodies[label]
        if body[0] != len(body) - 1:
            raise SystemExit(f"{label}: count {body[0]} != {len(body) - 1}")
        total += len(body)
        equates.append(f"SOUND_{emit_name}\t= {local_i}")
        blocks.append(f"{emit_label}\n{emit_bytes(body)}")
        labels.append(emit_label)
        priorities.append(wolf_pri[src_i])
        voices.append(sound_voice(emit_name))
        local_i += 1

    for src_label, name, pri in DOOM_KEEP:
        pitches = doom_bodies.get(src_label)
        if pitches is None:
            raise SystemExit(f"Doom {src_label} missing")
        converted = [hz_to_wolf_byte(pitch_hz[p]) if p else 0 for p in pitches]
        samples = decimate(converted)
        body = [len(samples), *samples]
        total += len(body)
        emit_label = f"pc_{name.lower()}"
        equates.append(f"SOUND_{name}\t= {local_i}")
        blocks.append(f"{emit_label}\n{emit_bytes(body)}")
        labels.append(emit_label)
        priorities.append(pri)
        voices.append(sound_voice(name))
        local_i += 1

    header = (
        "; Autogenerated by tools/gensounds.py — Wolf64 CORE (as-is) + SquareDoom-only\n"
        "; converted to Wolf inverse-freq bytes and decimated 3x (first non-zero in window).\n"
        "; Each effect: first byte = sample count; following = inverse-freq (0 = silence).\n"
        f"; Decimated {DECIMATE}x from 140 Hz source for ~50 Hz Timer A playback.\n"
        "\n"
    )
    asm = (
        header
        + "!zone pcsounds\n\n"
        + "\n".join(equates)
        + "\n"
        + ("\n" + "\n".join(aliases) + "\n" if aliases else "")
        + "\n"
        + "\n".join(blocks)
        + "\n\n"
        f"; unique sound payload {total} bytes\n"
        "sound_priorities\n"
        + emit_bytes(priorities)
        + "\n\n"
        "; 0 = player V1 pulse, 1 = enemy V2 pulse, 2 = world V3 noise\n"
        "sound_voices\n"
        + emit_bytes(voices)
        + "\n\n"
        "sound_table\n"
        + "\n".join(f"\t!word {lab}" for lab in labels)
        + "\n"
    )
    OUT.write_text(asm, encoding="utf-8", newline="\n")
    print(
        f"wrote {OUT.relative_to(ROOT)} ({local_i} effects, {total} sample bytes)"
    )


if __name__ == "__main__":
    main()
