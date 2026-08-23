#!/usr/bin/env python3
"""Export per-type pose PRGs + slim enemy_data.asm metadata."""

from __future__ import annotations

import json
import re
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
OUT = ROOT / "src" / "enemy_data.asm"
SIZES_OUT = ROOT / "src" / "enemy_sizes.asm"
ENEMY_DIR = ROOT / "enemies"

NVERTS = 13
TYPES = ["Grunt", "Knight", "Rottweiler", "Scrag", "Ogre", "Shambler", "Chthon"]
DOS_NAME = ["grunt", "knight", "rott", "scrag", "ogre", "shambl", "chthon"]
ENEMY_POSE_MAX = 4096
PAIN_MAX = 4
PAIN_KEY = re.compile(r"^pain[a-z]?$")
DEATH_KEY = re.compile(r"^(bdeath|death[a-z]?)$")

HP_QUAKE = {
    "Grunt": 30,
    "Rottweiler": 25,
    "Knight": 75,
    "Scrag": 80,
    "Ogre": 200,
    "Shambler": 600,
    "Chthon": 400,
}

ROLE_CLIPS = {
    "Grunt": {
        "stand": ("stand", None),
        "alert": ("load", None),
        "run": ("run", None),
        "walk": ("prowl", None),
        "attack": ("shoot", None),
    },
    "Knight": {
        "stand": ("stand", None),
        "alert": ("standing", None),
        "run": ("runb", None),
        "walk": ("walk", None),
        "attack": ("attackb", None),
    },
    "Rottweiler": {
        "stand": ("stand", None),
        "alert": ("stand", 2),
        "run": ("run", None),
        "walk": ("walk", None),
        "attack": ("leap", None),
    },
    "Scrag": {
        "stand": ("hover", None),
        "alert": ("hover", 4),
        "run": ("fly", None),
        "walk": ("fly", None),
        "attack": ("magatt", None),
    },
    "Ogre": {
        "stand": ("stand", None),
        "alert": ("stand", 4),
        "run": ("run", None),
        "walk": ("walk", None),
        "attack": ("smash", None),
    },
    "Shambler": {
        "stand": ("stand", None),
        "alert": ("stand", 4),
        "run": ("run", None),
        "walk": ("walk", None),
        "attack": ("smash", None),
    },
    "Chthon": {
        "stand": ("walk", 8),
        "alert": ("walk", 4),
        "run": ("walk", None),
        "walk": ("walk", None),
        "attack": ("attack", None),
    },
}


def clip_key(name: str) -> str:
    return str(name).rstrip("_").lower()


def find_clip(enemy: dict, *names: str) -> tuple[int, int] | None:
    clips = enemy.get("clips") or []
    for want in names:
        for c in clips:
            if clip_key(c.get("name", "")) == want:
                return int(c["start"]), int(c["len"])
    return None


def find_role(enemy: dict, role: str) -> tuple[int, int]:
    spec = ROLE_CLIPS.get(enemy["name"], {}).get(role)
    if spec is None:
        raise SystemExit(f"{enemy['name']}: no role {role}")
    name, len_override = spec
    found = find_clip(enemy, name)
    if found is None:
        raise SystemExit(f"{enemy['name']}: no {name} clip for role {role}")
    start, length = found
    if len_override is not None:
        length = min(length, int(len_override))
    return start, length


def find_variant_clips(enemy: dict, key_re: re.Pattern, what: str) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    for c in enemy.get("clips") or []:
        if key_re.match(clip_key(c.get("name", ""))):
            out.append((int(c["start"]), int(c["len"])))
            if len(out) >= PAIN_MAX:
                break
    if not out:
        stand = find_clip(enemy, "stand", "walk", "hover")
        if stand is None:
            raise SystemExit(f"{enemy['name']}: no {what} clip")
        out.append((stand[0], 1))
    return out


def pad_variants(clips: list[tuple[int, int]]) -> tuple[int, list[int], list[int]]:
    starts: list[int] = []
    lens: list[int] = []
    for i in range(PAIN_MAX):
        if i < len(clips):
            starts.append(clips[i][0])
            lens.append(clips[i][1])
        else:
            starts.append(0)
            lens.append(0)
    return len(clips), starts, lens


def s8(n: int) -> int:
    n = int(n)
    if n < -128 or n > 127:
        raise ValueError(f"vert coord out of signed byte range: {n}")
    return n & 0xFF


def export_type(enemy: dict) -> tuple[list[int], list[int], list[int], list[list[int]], list[dict]]:
    lines = enemy["lines"]
    frames = enemy["frames"]
    clips = enemy.get("clips") or []
    if len(lines) != NVERTS:
        raise SystemExit(f"{enemy['name']}: expected {NVERTS} lines, got {len(lines)}")
    if not frames:
        raise SystemExit(f"{enemy['name']}: no frames")
    gx: list[int] = []
    gy: list[int] = []
    gz: list[int] = []
    for fi, fr in enumerate(frames):
        if len(fr) != NVERTS:
            raise SystemExit(f"{enemy['name']} frame {fi}: bad vert count")
        for v in fr:
            gx.append(s8(v["x"]))
            gy.append(s8(v["y"]))
            gz.append(s8(v["z"]))
    return gx, gy, gz, lines, clips


def trim_to_budget(gx: list[int], gy: list[int], gz: list[int], enemy: dict) -> int:
    nframes = len(gx) // NVERTS
    max_frames = (ENEMY_POSE_MAX - 1) // (NVERTS * 3)
    if nframes <= max_frames:
        return nframes
    print(f"warning: {enemy['name']} {nframes} frames > {max_frames}; truncating")
    nframes = max_frames
    n = nframes * NVERTS
    gx[:] = gx[:n]
    gy[:] = gy[:n]
    gz[:] = gz[:n]
    kept = []
    for c in enemy.get("clips") or []:
        start = int(c["start"])
        if start >= nframes:
            continue
        length = min(int(c["len"]), nframes - start)
        if length <= 0:
            continue
        nc = dict(c)
        nc["start"] = start
        nc["len"] = length
        kept.append(nc)
    enemy["clips"] = kept
    return nframes


def main() -> None:
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    by_name = {e["name"]: e for e in doc["enemies"]}
    ENEMY_DIR.mkdir(exist_ok=True)
    parts = [
        "; Generated by tools/genenemies.py — metadata only; poses load from disk",
        "PAIN_MAX	= 4		; variants per type; pain_var_off uses ASL×2",
        "",
    ]
    all_edges = None
    roles: dict[str, list[int]] = {
        "stand_start": [],
        "stand_len": [],
        "alert_start": [],
        "alert_len": [],
        "run_start": [],
        "run_len": [],
        "walk_start": [],
        "walk_len": [],
        "attack_start": [],
        "attack_len": [],
    }
    pain_n: list[int] = []
    pain_start: list[int] = []
    pain_len: list[int] = []
    death_n: list[int] = []
    death_start: list[int] = []
    death_len: list[int] = []
    pose_sizes: list[int] = []
    max_nframes = 0
    nframes_list: list[int] = []

    for ti, name in enumerate(TYPES):
        if name not in by_name:
            raise SystemExit(f"missing enemy {name}")
        enemy = by_name[name]
        gx, gy, gz, lines, _clips = export_type(enemy)
        nframes = trim_to_budget(gx, gy, gz, enemy)
        payload = bytes([nframes]) + bytes(gx) + bytes(gy) + bytes(gz)
        if len(payload) > ENEMY_POSE_MAX:
            raise SystemExit(f"{name} pose {len(payload)} exceeds {ENEMY_POSE_MAX}")
        dos = DOS_NAME[ti]
        (ENEMY_DIR / f"{dos}.prg").write_bytes(struct.pack("<H", 0) + payload)
        pose_sizes.append(len(payload))
        nframes_list.append(nframes)
        for role in ("stand", "alert", "run", "walk", "attack"):
            start, length = find_role(enemy, role)
            if start + length > nframes:
                length = max(1, nframes - start)
            roles[f"{role}_start"].append(start)
            roles[f"{role}_len"].append(length)
        n, starts, lens = pad_variants(find_variant_clips(enemy, PAIN_KEY, "pain"))
        pain_n.append(n)
        pain_start.extend(starts)
        pain_len.extend(lens)
        n, starts, lens = pad_variants(find_variant_clips(enemy, DEATH_KEY, "death"))
        death_n.append(n)
        death_start.extend(starts)
        death_len.extend(lens)
        if all_edges is None:
            all_edges = lines
        elif lines != all_edges:
            print(f"warning: {name} edges differ from Grunt; using Grunt edges")
        if nframes > max_nframes:
            max_nframes = nframes

    edge_bytes: list[int] = []
    assert all_edges is not None
    for a, b in all_edges:
        edge_bytes.append(int(a))
        edge_bytes.append(int(b))
    parts.append("enemy_edges")
    parts.append("\t!byte " + ",".join(str(b) for b in edge_bytes))
    parts.append("enemy_edge_vert")
    parts.append("\t!byte " + ",".join("0" for _ in all_edges))
    parts.append("")
    parts.append("; Role clips")
    parts.append("enemy_stand_start	!byte " + ", ".join(str(n) for n in roles["stand_start"]))
    parts.append("enemy_stand_len		!byte " + ", ".join(str(n) for n in roles["stand_len"]))
    parts.append("enemy_alert_start	!byte " + ", ".join(str(n) for n in roles["alert_start"]))
    parts.append("enemy_alert_len		!byte " + ", ".join(str(n) for n in roles["alert_len"]))
    parts.append("enemy_run_start		!byte " + ", ".join(str(n) for n in roles["run_start"]))
    parts.append("enemy_run_len		!byte " + ", ".join(str(n) for n in roles["run_len"]))
    parts.append("enemy_walk_start		!byte " + ", ".join(str(n) for n in roles["walk_start"]))
    parts.append("enemy_walk_len		!byte " + ", ".join(str(n) for n in roles["walk_len"]))
    parts.append("enemy_attack_start	!byte " + ", ".join(str(n) for n in roles["attack_start"]))
    parts.append("enemy_attack_len	!byte " + ", ".join(str(n) for n in roles["attack_len"]))
    parts.append("enemy_pain_n		!byte " + ", ".join(str(n) for n in pain_n))
    parts.append("enemy_pain_start	!byte " + ", ".join(str(n) for n in pain_start))
    parts.append("enemy_pain_len		!byte " + ", ".join(str(n) for n in pain_len))
    parts.append("enemy_death_n		!byte " + ", ".join(str(n) for n in death_n))
    parts.append("enemy_death_start	!byte " + ", ".join(str(n) for n in death_start))
    parts.append("enemy_death_len		!byte " + ", ".join(str(n) for n in death_len))
    parts.append("enemy_range		!byte 30, 30, 4, 24, 20, 16, 40")
    hp_bytes = ", ".join(str(min(255, HP_QUAKE[t] // 5)) for t in TYPES)
    parts.append(f"enemy_hp_init		!byte {hp_bytes}")
    parts.append("enemy_pain_chance	!byte $80, $80, $c0, $80, $80, $80, $80")
    parts.append("enemy_drop_type	!byte 7, $ff, $ff, $ff, 4, $ff, $ff")
    parts.append("enemy_fire_frame	!byte 2, 4, 4, 6, 4, 4, 8")
    parts.append("enemy_class		!byte 0, 0, 1, 0, 0, 0, 0")
    parts.append("enemy_nframes	!byte " + ", ".join(str(n) for n in nframes_list))
    parts.append("")

    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    size_lo = ",".join(str(s & 0xFF) for s in pose_sizes)
    size_hi = ",".join(str((s >> 8) & 0xFF) for s in pose_sizes)
    SIZES_OUT.write_text(
        "; Generated by tools/genenemies.py — pose payload bytes per type 0..6\n"
        f"enemy_size_lo	!byte {size_lo}\n"
        f"enemy_size_hi	!byte {size_hi}\n",
        encoding="utf-8",
    )
    print(f"Wrote {OUT.relative_to(ROOT)} + enemy PRGs sizes={pose_sizes} nframes={nframes_list}")


if __name__ == "__main__":
    main()
