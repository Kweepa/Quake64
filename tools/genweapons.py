#!/usr/bin/env python3
"""Pack cleaned view-model PNGs → src/weapon_spr.asm (+ optional contact sheet).

Occupancy is measured on the 48×42 `*_N_edit.png` files (not packed asm).

    axe   TL (14,0)  BL (13,21)  mid-right (24,8)     → 3 cells
    shot  stacked 24-wide at x=13 (edit ink 13..36)   → 2 cells
    gren  top-mid (12,0) BL (0,21) BR (24,21)         → 3 cells
    nail  full 2×2 on frames 0,1,2                    → 4 cells each

Flashes are occupancy-masked (8-byte mask + nonzero bytes).

    python tools/genweapons.py
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

from sprmask import (  # noqa: E402
    CELL,
    H,
    W,
    bchunk,
    blit_cell,
    leftover_ink,
    load_png_1bit,
    pack_24x21,
    pack_window,
    pack_zeromask,
    parse_label_bytes,
    unpack_2x2,
    unpack_zeromask,
)

DOC = ROOT / "editor" / "quake64.json"
PNG_DIR = ROOT / "assets" / "weapons"
OUT = ROOT / "src" / "weapon_spr.asm"
SHEET = PNG_DIR / "sheet.png"

AXE_KEY = "axe"
EDIT_RE = re.compile(r"^([a-z0-9]+)_(\d+)_edit\.png$", re.I)

FLASHES = [
    ("muzzle_flash.png", "spr_muzzle"),
    ("axe_flash.png", "spr_spark"),
    ("nail_flash_left.png", "spr_nail_fl"),
    ("nail_flash_right.png", "spr_nail_fr"),
]

# Weapon order in tables: axe, shot, nail, gren
WINDOWS = {
    "axe": [(14, 0), (13, 21), (24, 8)],
    "shot2": [(13, 0), (13, 21)],
    "nail": [(0, 0), (24, 0), (0, 21), (24, 21)],
    "rock": [(12, 0), (0, 21), (24, 21)],
}


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


def edit_png(key: str, frame: int) -> Path:
    return PNG_DIR / f"{key}_{frame}_edit.png"


def pix_from_png(key: str, frame: int) -> list[list[int]] | None:
    path = edit_png(key, frame)
    if path.is_file():
        return load_png_1bit(path, W, H)
    return None


def pix_from_asm(label: str, windows: list[tuple[int, int]]) -> list[list[int]]:
    raw = parse_label_bytes(OUT, label)
    if len(raw) >= 256:
        return unpack_2x2(raw[:256])
    n = len(windows)
    if len(raw) < n * CELL:
        raise SystemExit(f"{label}: expected {n * CELL} occupancy bytes, got {len(raw)}")
    pix = [[0] * W for _ in range(H)]
    for i, (ox, oy) in enumerate(windows):
        blit_cell(pix, raw[i * CELL : (i + 1) * CELL], ox, oy)
    return pix


def load_pix(key: str, frame: int, label: str) -> list[list[int]]:
    path = edit_png(key, frame)
    pix = pix_from_png(key, frame)
    if pix is not None:
        print(f"  occupancy {key}: {path.name}")
        return pix
    raise SystemExit(f"occupancy needs {path} (not packed asm / unedited png)")


def cut_cells(key: str, pix: list[list[int]]) -> list[list[int]]:
    windows = WINDOWS[key]
    left = leftover_ink(pix, windows)
    if left:
        raise SystemExit(f"{key}: leftover ink {left[:20]}{'…' if len(left) > 20 else ''} ({len(left)})")
    return [pack_window(pix, ox, oy) for ox, oy in windows]


def flash_raw(png_name: str, label: str) -> list[int]:
    path = PNG_DIR / png_name
    if path.is_file():
        return pack_24x21(load_png_1bit(path, 24, 21))
    if OUT.is_file():
        raw = parse_label_bytes(OUT, label)
        head = OUT.read_text(encoding="utf-8")[:500]
        if "zeromask" in head:
            return unpack_zeromask(raw)
        return list(raw[:CELL])
    raise SystemExit(f"missing {path} and {OUT}")


def write_sheet(rows: list[list[tuple[str, list[list[int]], list[tuple[int, int]]]]]) -> None:
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
        for name, cells, windows in row:
            draw.text((x, y), name, fill=(212, 160, 23), font=font)
            pix = [[0] * W for _ in range(H)]
            for cell, (ox, oy) in zip(cells, windows):
                blit_cell(pix, cell, ox, oy)
            cell_im = Image.new("RGB", (W, H), (10, 10, 12))
            px = cell_im.load()
            for yy in range(H):
                for xx in range(W):
                    if pix[yy][xx]:
                        px[xx, yy] = (232, 228, 216)
            cy = y + label_h
            im.paste(cell_im, (x, cy))
            draw.rectangle((x - 1, cy - 1, x + W, cy + H), outline=(80, 70, 40))
            x += W + pad
        y += label_h + H + pad
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    im.save(SHEET)
    print(f"Wrote {SHEET.relative_to(ROOT)}")


def emit_cells(label: str, cells: list[list[int]]) -> list[str]:
    flat: list[int] = []
    for c in cells:
        flat.extend(c)
    return [label, bchunk(flat).rstrip(), ""]


def main() -> None:
    if not DOC.is_file():
        raise SystemExit(f"missing {DOC}")
    doc = json.loads(DOC.read_text(encoding="utf-8"))
    weapons = doc.get("weapons") or {}

    shot_frames = item_frames(weapons, "shot2")
    nail_frames = item_frames(weapons, "nail")
    rock_frames = item_frames(weapons, "rock")
    axe_frames = item_frames(weapons, AXE_KEY)

    shot_pix = load_pix("shot2", shot_frames[0], "spr_shot2")
    rock_pix = load_pix("rock", rock_frames[0], "spr_rock")
    axe_pix = load_pix("axe", axe_frames[0], "spr_axe_0")
    nail_pix = [load_pix("nail", f, f"spr_nail_{f}") for f in nail_frames]

    shot = cut_cells("shot2", shot_pix)
    rock = cut_cells("rock", rock_pix)
    axe = cut_cells("axe", axe_pix)
    nail = [cut_cells("nail", pix) for pix in nail_pix]

    flashes = [(label, pack_zeromask(flash_raw(png, label))) for png, label in FLASHES]

    # Tables: weapon order axe, shot, nail, gren. 4 slots; unused dx/dy = 0.
    def pad4(windows: list[tuple[int, int]]) -> list[tuple[int, int]]:
        w = list(windows) + [(0, 0)] * (4 - len(windows))
        return w[:4]

    axe_w, shot_w, nail_w, rock_w = (pad4(WINDOWS[k]) for k in ("axe", "shot2", "nail", "rock"))
    dx = [p[0] for w in (axe_w, shot_w, nail_w, rock_w) for p in w]
    dy = [p[1] for w in (axe_w, shot_w, nail_w, rock_w) for p in w]
    en = [
        (1 << len(WINDOWS["axe"])) - 1,
        (1 << len(WINDOWS["shot2"])) - 1,
        (1 << len(WINDOWS["nail"])) - 1,
        (1 << len(WINDOWS["rock"])) - 1,
    ]
    nbytes = [len(WINDOWS[k]) * CELL % 256 for k in ("axe", "shot2", "nail", "rock")]
    # 256 cells → 0 so blit_n cpx #0 wraps after 256 copies

    parts = [
        "; Generated by tools/genweapons.py from assets/weapons — do not edit",
        "; Body cells are 24x21 occupancy windows (see wpn_dx / wpn_dy).",
        "; Flashes: zeromask (8-byte occupancy + nonzero bytes).",
        "",
        "; Slot dx/dy and enable: weapon order axe, shot, nail, gren (4 slots).",
        "wpn_dx",
        bchunk(dx).rstrip(),
        "wpn_dy",
        bchunk(dy).rstrip(),
        "wpn_body_en",
        bchunk(en).rstrip(),
        "wpn_body_n",
        bchunk(nbytes).rstrip(),
        "",
    ]
    parts += emit_cells("spr_shot2", shot)
    parts += [
        "spr_nail_count",
        f"\t!byte {len(nail)}",
        "spr_nail",
    ]
    for i, cells in enumerate(nail):
        parts += emit_cells(f"spr_nail_{i}", cells)
    parts += emit_cells("spr_rock", rock)
    parts += [
        "spr_axe_count",
        "\t!byte 1",
        "spr_axe",
    ]
    parts += emit_cells("spr_axe_0", axe)
    for label, data in flashes:
        parts += [label, bchunk(data).rstrip(), ""]

    OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
    print(f"Wrote {OUT.relative_to(ROOT)}")
    for k, cells in (("axe", axe), ("shot2", shot), ("rock", rock)):
        print(f"  {k}: {len(cells)} cells ({len(cells) * CELL} bytes)")
    print(f"  nail: {len(nail)} frames × {len(nail[0]) if nail else 0} cells")
    for label, data in flashes:
        print(f"  {label}: {len(data)} packed")

    write_sheet(
        [
            [
                ("axe", axe, WINDOWS["axe"]),
                ("shot2", shot, WINDOWS["shot2"]),
                ("rock", rock, WINDOWS["rock"]),
            ],
            [(f"nail {i}", cells, WINDOWS["nail"]) for i, cells in enumerate(nail)],
        ]
    )


if __name__ == "__main__":
    main()
