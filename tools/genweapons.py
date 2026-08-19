#!/usr/bin/env python3
"""Pack cleaned view-model PNGs → src/weapon_spr.asm (+ optional contact sheet).

Editor exports {key}_{frame}.png. Copy to {key}_{frame}_edit.png and clean those.
This script reads only the _edit files.

    python tools/genweapons.py
"""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
PNG_DIR = ROOT / "assets" / "weapons"
OUT = ROOT / "src" / "weapon_spr.asm"
SHEET = PNG_DIR / "sheet.png"

AXE_KEY = "axe"
W = 48
H = 42
EDIT_RE = re.compile(r"^([a-z0-9]+)_(\d+)_edit\.png$", re.I)


def bchunk(data: list[int], width: int = 16) -> str:
    lines = []
    for i in range(0, len(data), width):
        chunk = data[i : i + width]
        lines.append("\t!byte " + ",".join(f"${b:02x}" for b in chunk))
    return "\n".join(lines) + "\n"


def pack_48x42(pix: list[list[int]]) -> list[int]:
    out = [0] * 256

    def blit(spr: int, ox: int, oy: int) -> None:
        base = spr * 64
        for y in range(21):
            for col in range(3):
                b = 0
                for bit in range(8):
                    if pix[oy + y][ox + col * 8 + bit]:
                        b |= 0x80 >> bit
                out[base + y * 3 + col] = b

    blit(0, 0, 0)
    blit(1, 24, 0)
    blit(2, 0, 21)
    blit(3, 24, 21)
    return out


def unpack_48x42(data: list[int]) -> list[list[int]]:
    pix = [[0] * W for _ in range(H)]

    def blit(spr: int, ox: int, oy: int) -> None:
        base = spr * 64
        for y in range(21):
            for col in range(3):
                b = data[base + y * 3 + col]
                for bit in range(8):
                    if b & (0x80 >> bit):
                        pix[oy + y][ox + col * 8 + bit] = 1

    blit(0, 0, 0)
    blit(1, 24, 0)
    blit(2, 0, 21)
    blit(3, 24, 21)
    return pix


def load_edit_png(path: Path) -> list[list[int]]:
    try:
        from PIL import Image
    except ImportError as e:
        raise SystemExit("Pillow is required: pip install Pillow") from e
    im = Image.open(path).convert("RGB")
    if im.size != (W, H):
        raise SystemExit(f"{path.name}: expected {W}x{H}, got {im.size[0]}x{im.size[1]}")
    pix = [[0] * W for _ in range(H)]
    src = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b = src[x, y]
            if r > 16 or g > 16 or b > 16:
                pix[y][x] = 1
    return pix


def glob_edit_frames(key: str) -> list[int]:
    found: list[int] = []
    if not PNG_DIR.is_dir():
        return found
    for p in PNG_DIR.iterdir():
        m = EDIT_RE.match(p.name)
        if not m or m.group(1).lower() != key:
            continue
        found.append(int(m.group(2)))
    return sorted(set(found))


def item_frames(weapons: dict, key: str) -> list[int]:
    items = weapons.get("items") or weapons
    item = items.get(key) or {}
    raw = item.get("frames")
    if isinstance(raw, list) and raw:
        seen: set[int] = set()
        out: list[int] = []
        for f in raw:
            n = int(f)
            if n < 0 or n in seen:
                continue
            seen.add(n)
            out.append(n)
        return out
    found = glob_edit_frames(key)
    if found:
        return found
    return [0]


def load_item_sprites(key: str, frames: list[int]) -> list[list[int]]:
    packed = []
    for fi in frames:
        path = PNG_DIR / f"{key}_{fi}_edit.png"
        if not path.is_file():
            raise SystemExit(f"missing {path.relative_to(ROOT)} (copy the export to *_edit.png and clean it)")
        packed.append(pack_48x42(load_edit_png(path)))
    return packed


def write_sheet(rows: list[list[tuple[str, list[int]]]]) -> None:
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("Pillow not installed; skip PNG sheet")
        return
    pad = 8
    label_h = 16
    cols = max((len(row) for row in rows), default=1)
    img_w = cols * (W + pad) + pad
    img_h = len(rows) * (H + label_h + pad) + pad
    im = Image.new("RGB", (img_w, img_h), (12, 12, 14))
    draw = ImageDraw.Draw(im)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    y = pad
    for row in rows:
        x = pad
        for name, data in row:
            draw.text((x, y), name, fill=(212, 160, 23), font=font)
            pix = unpack_48x42(data)
            cell = Image.new("RGB", (W, H), (10, 10, 12))
            px = cell.load()
            for yy in range(H):
                for xx in range(W):
                    if pix[yy][xx]:
                        px[xx, yy] = (232, 228, 216)
            cy = y + label_h
            im.paste(cell, (x, cy))
            draw.rectangle((x - 1, cy - 1, x + W, cy + H), outline=(80, 70, 40))
            x += W + pad
        y += label_h + H + pad
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    im.save(SHEET)
    print(f"Wrote {SHEET.relative_to(ROOT)}")


def main() -> None:
    if not DOC.is_file():
        raise SystemExit(f"missing {DOC}")
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    weapons = doc.get("weapons") or {}
    shot2 = load_item_sprites("shot2", item_frames(weapons, "shot2"))
    nail = load_item_sprites("nail", item_frames(weapons, "nail"))
    rock = load_item_sprites("rock", item_frames(weapons, "rock"))
    axe_frames = item_frames(weapons, AXE_KEY)
    axe = load_item_sprites(AXE_KEY, axe_frames)
    parts = [
        "; Generated by tools/genweapons.py from assets/weapons/*_edit.png — do not edit",
        "; Each image is 4 hi-res sprites (24x21, 64 bytes) in 2x2 = 48x42",
        "",
        "spr_shot2",
        bchunk(shot2[0]).rstrip(),
        "",
        "spr_nail",
        bchunk(nail[0]).rstrip(),
        "",
        "spr_rock",
        bchunk(rock[0]).rstrip(),
        "",
        "spr_axe_count",
        f"\t!byte {len(axe)}",
        "spr_axe",
    ]
    for i, fr in enumerate(axe):
        parts.append(f"spr_axe_{i}")
        parts.append(bchunk(fr).rstrip())
    parts.append("")
    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    write_sheet(
        [
            [("axe", axe[0]), ("shot2", shot2[0]), ("rock", rock[0])],
            [(f"nail {i}", fr) for i, fr in enumerate(nail)],
        ]
    )


if __name__ == "__main__":
    main()
