"""Quake MDL + PAK readers. Pose decode matches editor/js/mdl.js."""

from __future__ import annotations

import math
import re
import struct
from pathlib import Path

IDPO = 0x4F504449
ALIAS_VERSION = 6
ALIAS_SINGLE = 0
HULL_FLOOR = 24
POSE_SCALE = 0.7

ENEMY_MDL_PATHS = {
    "Grunt": "progs/soldier.mdl",
    "Knight": "progs/knight.mdl",
    "Rottweiler": "progs/dog.mdl",
    "Scrag": "progs/wizard.mdl",
    "Ogre": "progs/ogre.mdl",
    "Shambler": "progs/shambler.mdl",
    "Chthon": "progs/boss.mdl",
    "Zombie": "progs/zombie.mdl",
}

_EXTRA_PAIN_DEATH = re.compile(r"^pain[b-z]|^death[b-z]|^deathc$|^bdeath$")


def js_round(n: float) -> int:
    """Math.round: halves go toward +inf."""
    return math.floor(n + 0.5)


def clip_name(frame_name: str) -> str:
    key = re.sub(r"\d+$", "", frame_name)
    return key or frame_name


def parse_pak(path: Path) -> dict[str, bytes]:
    data = path.read_bytes()
    if len(data) < 12:
        raise SystemExit(f"PAK too small: {path}")
    magic, dir_ofs, dir_size = struct.unpack_from("<4sII", data, 0)
    if magic != b"PACK":
        raise SystemExit(f"not a PACK: {path}")
    if dir_ofs + dir_size > len(data):
        raise SystemExit(f"PAK directory out of range: {path}")
    files: dict[str, bytes] = {}
    for i in range(dir_size // 64):
        off = dir_ofs + i * 64
        raw = data[off : off + 56].split(b"\x00", 1)[0]
        name = raw.decode("latin1").replace("\\", "/").lower()
        foff, fsz = struct.unpack_from("<II", data, off + 56)
        if foff + fsz > len(data):
            continue
        files[name] = data[foff : foff + fsz]
    return files


def _find_pak(root: Path, stem: str) -> Path | None:
    if not root.is_dir():
        return None
    for p in root.iterdir():
        if p.is_file() and p.name.lower() == stem:
            return p
    return None


def load_id1(root: Path) -> dict[str, bytes]:
    """pak0 then pak1. Later files override."""
    pak0 = _find_pak(root, "pak0.pak")
    if pak0 is None:
        raise SystemExit(f"missing {root / 'PAK0.PAK'}")
    files = parse_pak(pak0)
    pak1 = _find_pak(root, "pak1.pak")
    if pak1 is not None:
        files.update(parse_pak(pak1))
    return files


class _R:
    def __init__(self, data: bytes):
        self.data = data
        self.o = 0

    def need(self, n: int, what: str) -> None:
        if self.o + n > len(self.data):
            raise SystemExit(f"MDL truncated ({what})")

    def i32(self) -> int:
        self.need(4, "i32")
        v = struct.unpack_from("<i", self.data, self.o)[0]
        self.o += 4
        return v

    def f32(self) -> float:
        self.need(4, "f32")
        v = struct.unpack_from("<f", self.data, self.o)[0]
        self.o += 4
        return v

    def vec3(self) -> tuple[float, float, float]:
        return (self.f32(), self.f32(), self.f32())

    def u8(self) -> int:
        self.need(1, "u8")
        v = self.data[self.o]
        self.o += 1
        return v

    def skip(self, n: int) -> None:
        self.need(n, "skip")
        self.o += n

    def name16(self) -> str:
        self.need(16, "name")
        raw = self.data[self.o : self.o + 16].split(b"\x00", 1)[0]
        self.o += 16
        return raw.decode("latin1")


def _skip_skins(r: _R, num_skins: int, skin_w: int, skin_h: int) -> None:
    skin_size = skin_w * skin_h
    if skin_size < 0 or skin_size > 2_000_000:
        raise SystemExit("MDL skin size invalid")
    for _ in range(num_skins):
        typ = r.i32()
        if typ == ALIAS_SINGLE:
            r.skip(skin_size)
        else:
            n = r.i32()
            if n < 0 or n > 256:
                raise SystemExit("MDL skin group too large")
            r.skip(n * 4 + n * skin_size)


def _read_simple_frame(r: _R, num_verts: int) -> dict:
    r.need(8 + 16 + num_verts * 4, "frame")
    r.skip(8)
    name = r.name16()
    verts = bytearray(num_verts * 3)
    for i in range(num_verts):
        verts[i * 3] = r.u8()
        verts[i * 3 + 1] = r.u8()
        verts[i * 3 + 2] = r.u8()
        r.u8()
    return {"name": name, "verts": bytes(verts)}


def parse_mdl(data: bytes) -> dict:
    r = _R(data)
    r.need(84, "header")
    ident = r.i32() & 0xFFFFFFFF
    if ident != IDPO:
        raise SystemExit("Not an IDPO MDL")
    version = r.i32()
    if version != ALIAS_VERSION:
        raise SystemExit(f"MDL version {version}, expected 6")
    scale = r.vec3()
    origin = r.vec3()
    r.f32()
    r.vec3()
    num_skins = r.i32()
    skin_w = r.i32()
    skin_h = r.i32()
    num_verts = r.i32()
    num_tris = r.i32()
    num_frames = r.i32()
    r.i32()
    r.i32()
    r.f32()
    if num_verts <= 0 or num_verts > 10000 or num_tris <= 0 or num_tris > 20000 or num_frames <= 0:
        raise SystemExit("MDL has no geometry")
    _skip_skins(r, num_skins, skin_w, skin_h)
    r.skip(num_verts * 12)
    r.need(num_tris * 16, "tris")
    r.skip(num_tris * 16)
    frames = []
    for _ in range(num_frames):
        typ = r.i32()
        if typ == ALIAS_SINGLE:
            frames.append(_read_simple_frame(r, num_verts))
        else:
            n = r.i32()
            if n < 0 or n > 256:
                raise SystemExit("MDL frame group too large")
            r.skip(8 + n * 4)
            for _j in range(n):
                frames.append(_read_simple_frame(r, num_verts))
    clips = []
    by_key: dict[str, dict] = {}
    for i, fr in enumerate(frames):
        key = clip_name(fr["name"])
        clip = by_key.get(key)
        if clip is None:
            clip = {"name": key, "frames": []}
            by_key[key] = clip
            clips.append(clip)
        clip["frames"].append({"name": fr["name"], "index": i})
    return {
        "numVerts": num_verts,
        "scale": scale,
        "origin": origin,
        "frames": frames,
        "clips": clips,
    }


def select_mdl_clips(mdl: dict, names: list[str] | None) -> list[dict]:
    clips = mdl.get("clips") or []
    if not clips:
        return []
    if names is None:
        return [c for c in clips if not _EXTRA_PAIN_DEATH.search(c["name"])]
    want = set(names)
    return [c for c in clips if c["name"] in want]


def editor_verts(mdl: dict, frame_index: int, scale: float = POSE_SCALE) -> list[dict[str, float]]:
    fr = mdl["frames"][frame_index]
    sx, sy, sz = mdl["scale"]
    ox, oy, oz = mdl["origin"]
    packed = fr["verts"]
    s = scale if math.isfinite(scale) else POSE_SCALE
    s = max(0.1, min(2.0, s))
    out = []
    for i in range(mdl["numVerts"]):
        qx = packed[i * 3] * sx + ox
        qy = packed[i * 3 + 1] * sy + oy
        qz = packed[i * 3 + 2] * sz + oz
        # Quake +X forward / +Z up → editor +Z forward / +Y up.
        x = -qy
        y = qz
        z = qx
        out.append({"x": x * s, "y": (y + HULL_FLOOR) * s, "z": z * s})
    return out


def load_enemy_mdls(id1: Path) -> dict[str, dict]:
    lumps = load_id1(id1)
    models: dict[str, dict] = {}
    for enemy, path in ENEMY_MDL_PATHS.items():
        blob = lumps.get(path.lower())
        if blob is None:
            raise SystemExit(f"{enemy}: {path} missing from {id1}")
        models[enemy] = parse_mdl(blob)
    return models
