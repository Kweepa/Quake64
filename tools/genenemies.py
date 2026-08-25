#!/usr/bin/env python3
"""Export per-type pose PRGs + slim enemy_data.asm metadata."""

from __future__ import annotations

import json
import re
import struct
from copy import deepcopy
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
# Clip-local fire frames (matches enemy_fire_frame). Pinned as an attack key.
FIRE_FRAME = [2, 4, 4, 6, 4, 4, 8]
# Mid-distance stick LOD threshold (CAM_ZH); Ogre needs more for chainsaw tip.
DEFAULT_LOD_Z = {
    "Grunt": 4,
    "Knight": 4,
    "Rottweiler": 4,
    "Scrag": 4,
    "Ogre": 10,
    "Shambler": 4,
    "Chthon": 4,
}

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


def find_role(enemy: dict, role: str) -> tuple[int, int] | None:
    spec = ROLE_CLIPS.get(enemy["name"], {}).get(role)
    if spec is None:
        return None
    name, len_override = spec
    found = find_clip(enemy, name)
    if found is None:
        return None
    start, length = found
    if len_override is not None:
        length = min(length, int(len_override))
    return start, length


def require_role(enemy: dict, role: str) -> tuple[int, int]:
    found = find_role(enemy, role)
    if found is not None:
        return found
    found = find_clip(enemy, "stand", "walk", "hover")
    if found is not None:
        return found
    clips = enemy.get("clips") or []
    if clips:
        return int(clips[0]["start"]), max(1, int(clips[0]["len"]))
    raise SystemExit(f"{enemy['name']}: no {role} clip (and no fallback)")


def apply_export_clips(enemy: dict) -> None:
    """Keep only exportClips, remapping stick frames/starts. Missing list → all clips."""
    names = enemy.get("exportClips")
    if not isinstance(names, list):
        return
    clips = enemy.get("clips") or []
    frames = enemy.get("frames") or []
    by_name = {c.get("name", ""): c for c in clips}
    by_key = {clip_key(c.get("name", "")): c for c in clips}
    new_frames: list = []
    new_clips: list[dict] = []
    start = 0
    for name in names:
        c = by_name.get(name) or by_key.get(clip_key(name))
        if c is None:
            continue
        a, n = int(c["start"]), int(c["len"])
        sl = frames[a : a + n]
        if not sl:
            continue
        new_clips.append({"name": c.get("name", name), "start": start, "len": len(sl)})
        new_frames.extend(sl)
        start += len(sl)
    enemy["frames"] = new_frames
    enemy["clips"] = new_clips


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
            clips = enemy.get("clips") or []
            if not clips:
                raise SystemExit(f"{enemy['name']}: no {what} clip")
            out.append((int(clips[0]["start"]), 1))
        else:
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


def s8_val(b: int) -> int:
    return b if b < 128 else b - 256


def frames_xyz(gx: list[int], gy: list[int], gz: list[int], nframes: int) -> list[list[int]]:
    frs: list[list[int]] = []
    for i in range(nframes):
        xyz: list[int] = []
        off = i * NVERTS
        for arr in (gx, gy, gz):
            for v in range(NVERTS):
                xyz.append(s8_val(arr[off + v]))
        frs.append(xyz)
    return frs


def acc_at(frs: list[list[int]], i: int) -> int:
    if i <= 0 or i >= len(frs) - 1:
        return 0
    return max(abs(frs[i + 1][k] - 2 * frs[i][k] + frs[i - 1][k]) for k in range(NVERTS * 3))


def clip_ranges(enemy: dict, nframes: int) -> list[tuple[str, int, int]]:
    out: list[tuple[str, int, int]] = []
    for role in ("stand", "alert", "run", "walk", "attack"):
        found = find_role(enemy, role)
        if found is None:
            continue
        start, length = found
        if start < nframes and length > 0:
            out.append((role, start, min(length, nframes - start)))
    for what, key in (("pain", PAIN_KEY), ("death", DEATH_KEY)):
        for i, (start, length) in enumerate(find_variant_clips(enemy, key, what)):
            if start < nframes and length > 0:
                out.append((f"{what}{i}", start, min(length, nframes - start)))
    return out


def json_clip_ranges(enemy: dict, nframes: int) -> list[tuple[str, int, int]]:
    out: list[tuple[str, int, int]] = []
    for c in enemy.get("clips") or []:
        start = int(c["start"])
        length = int(c["len"])
        if start >= nframes or length <= 0:
            continue
        length = min(length, nframes - start)
        out.append((clip_key(c.get("name", "")), start, length))
    return out


def uncovered_runs(covered: list[bool]) -> list[tuple[int, int]]:
    out: list[tuple[int, int]] = []
    i = 0
    n = len(covered)
    while i < n:
        if covered[i]:
            i += 1
            continue
        j = i + 1
        while j < n and not covered[j]:
            j += 1
        out.append((i, j - i))
        i = j
    return out


def pick_keys(frs: list[list[int]], start: int, length: int, extra: tuple[int, ...] = ()) -> list[int]:
    if length <= 2:
        return []
    min_sep = max(2, length // 3)
    keys: list[int] = []
    for e in extra:
        if start < e < start + length - 1:
            keys.append(e)
        if len(keys) >= 2:
            return sorted(keys[:2])
    scored = [(acc_at(frs, i), i) for i in range(start + 1, start + length - 1)]
    scored.sort(reverse=True)
    for _acc, i in scored:
        if any(abs(i - k) < min_sep for k in keys):
            continue
        keys.append(i)
        if len(keys) == 2:
            break
    return sorted(keys)


def cadence_keep(start: int, length: int, keys: list[int]) -> set[int]:
    if length <= 0:
        return set()
    last = start + length - 1
    keyset = set(keys)
    kept: list[int] = []
    f = start
    while f < last:
        plug = [k for k in sorted(keyset) if f < k < f + 2]
        kept.append(f)
        if plug:
            k = plug[0]
            kept.append(k)
            f = k + 2
        else:
            f += 2
    kept.append(last)
    return set(kept)


def pack_poses(
    gx: list[int], gy: list[int], gz: list[int], enemy: dict, nframes: int, type_i: int
) -> tuple[list[int], list[int], list[int], list[int], int]:
    """Keep first/+2/keys/last per clip (roles and leftover JSON clips). pose_map: stored or $FF."""
    frs = frames_xyz(gx, gy, gz, nframes)
    covered = [False] * nframes
    keep: set[int] = set()
    atk = find_role(enemy, "attack")
    fire = (atk[0] + FIRE_FRAME[type_i]) if atk else -1
    for name, start, length in clip_ranges(enemy, nframes):
        extra = (fire,) if name == "attack" and fire >= 0 else ()
        keep |= cadence_keep(start, length, pick_keys(frs, start, length, extra))
        for i in range(start, start + length):
            covered[i] = True
    for _name, start, length in json_clip_ranges(enemy, nframes):
        if all(covered[start : start + length]):
            continue
        keep |= cadence_keep(start, length, pick_keys(frs, start, length))
        for i in range(start, start + length):
            covered[i] = True
    for start, length in uncovered_runs(covered):
        keep |= cadence_keep(start, length, pick_keys(frs, start, length))
    kept_sorted = sorted(keep)
    idx_of = {g: i for i, g in enumerate(kept_sorted)}
    pose_map = [idx_of[i] if i in idx_of else 0xFF for i in range(nframes)]
    for i, m in enumerate(pose_map):
        if m != 0xFF:
            continue
        if i == 0 or i == nframes - 1:
            raise SystemExit(f"{enemy['name']}: lerp at endpoint {i}")
        if pose_map[i - 1] == 0xFF or pose_map[i + 1] == 0xFF:
            raise SystemExit(f"{enemy['name']}: lerp {i} missing stored neighbor")
    n_stored = len(kept_sorted)
    if n_stored > 127:
        raise SystemExit(f"{enemy['name']}: {n_stored} stored poses > 127")

    def pack_axis(src: list[int]) -> list[int]:
        out: list[int] = []
        for fi in kept_sorted:
            off = fi * NVERTS
            out.extend(src[off : off + NVERTS])
        return out

    return pack_axis(gx), pack_axis(gy), pack_axis(gz), pose_map, n_stored


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
    stored_list: list[int] = []
    lod_z_list: list[int] = []

    for ti, name in enumerate(TYPES):
        if name not in by_name:
            raise SystemExit(f"missing enemy {name}")
        enemy = deepcopy(by_name[name])
        apply_export_clips(enemy)
        gx, gy, gz, lines, _clips = export_type(enemy)
        nframes = trim_to_budget(gx, gy, gz, enemy)
        gx, gy, gz, pose_map, n_stored = pack_poses(gx, gy, gz, enemy, nframes, ti)
        payload = bytes([n_stored, nframes]) + bytes(pose_map) + bytes(gx) + bytes(gy) + bytes(gz)
        if len(payload) > ENEMY_POSE_MAX:
            raise SystemExit(f"{name} pose {len(payload)} exceeds {ENEMY_POSE_MAX}")
        dos = DOS_NAME[ti]
        (ENEMY_DIR / f"{dos}.prg").write_bytes(struct.pack("<H", 0) + payload)
        pose_sizes.append(len(payload))
        nframes_list.append(nframes)
        stored_list.append(n_stored)
        raw_lod = enemy.get("lodZ", DEFAULT_LOD_Z.get(name, 4))
        try:
            lod = int(raw_lod)
        except (TypeError, ValueError):
            lod = DEFAULT_LOD_Z.get(name, 4)
        lod_z_list.append(max(0, min(255, lod)))
        n_lerp = sum(1 for v in pose_map if v == 0xFF)
        print(f"{name}: logical={nframes} stored={n_stored} lerp={n_lerp} bytes={len(payload)} lodZ={lod_z_list[-1]}")
        for role in ("stand", "alert", "run", "walk", "attack"):
            start, length = require_role(enemy, role)
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
    parts.append("; LOD Z by type: " + ", ".join(TYPES))
    parts.append(
        "enemy_lod_z		!byte " + ", ".join(str(n) for n in lod_z_list)
        + "	; full project while CAM_ZH < this"
    )
    parts.append("; Stored pose count (PRG header / gy stride). Clip tables stay logical.")
    parts.append("enemy_nframes	!byte " + ", ".join(str(n) for n in stored_list))
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
    print(
        f"Wrote {OUT.relative_to(ROOT)} + enemy PRGs sizes={pose_sizes} "
        f"logical={nframes_list} stored={stored_list}"
    )


if __name__ == "__main__":
    main()
