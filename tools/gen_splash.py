#!/usr/bin/env python3
"""Split ui/QUAKE_11.kla into the boot splash pair.

Koala: load $6000, 8000 bitmap, 1000 screen, 1000 colour, 1 background.
splashc_data.bin → screen + colour + bg (ACME splashc.asm stages at $4000).
splash.prg       → $6000 bitmap, loaded after colour so it paints in already coloured.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_menu_cursor_sprites import PEPTO_RGB  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
KLA = ROOT / "ui" / "QUAKE_11.kla"
OUT_COL_BIN = ROOT / "tmp" / "splashc_data.bin"
OUT_BMP = ROOT / "splash.prg"
PREVIEW = ROOT / "tmp" / "splash_preview.png"

LOAD_BMP = 0x6000
COLS = 40
ROWS = 25
BITMAP_SIZE = 8000
SCR_SIZE = 1000
KLA_SIZE = 2 + BITMAP_SIZE + SCR_SIZE + SCR_SIZE + 1


def decode_preview(
	bmp: bytes,
	scr: bytes,
	col: bytes,
	bg: int,
) -> Image.Image:
	im = Image.new("RGB", (COLS * 8, ROWS * 8), PEPTO_RGB[bg])
	pp = im.load()
	for cy in range(ROWS):
		for cx in range(COLS):
			cell = cy * COLS + cx
			lut = (bg, scr[cell] >> 4, scr[cell] & 15, col[cell] & 15)
			base = cy * 320 + cx * 8
			for y in range(8):
				b = bmp[base + y]
				for p in range(4):
					bits = (b >> (6 - p * 2)) & 3
					c = PEPTO_RGB[lut[bits]]
					xx = cx * 8 + p * 2
					yy = cy * 8 + y
					pp[xx, yy] = c
					pp[xx + 1, yy] = c
	return im


def main() -> None:
	if not KLA.is_file():
		print(f"missing: {KLA}", file=sys.stderr)
		sys.exit(1)
	data = KLA.read_bytes()
	if len(data) != KLA_SIZE:
		print(
			f"{KLA.name} expected {KLA_SIZE} bytes, got {len(data)}",
			file=sys.stderr,
		)
		sys.exit(1)
	load = struct.unpack_from("<H", data, 0)[0]
	if load != LOAD_BMP:
		print(
			f"{KLA.name} load address ${load:04x}, expected ${LOAD_BMP:04x}",
			file=sys.stderr,
		)
		sys.exit(1)

	bmp = data[2 : 2 + BITMAP_SIZE]
	scr = data[2 + BITMAP_SIZE : 2 + BITMAP_SIZE + SCR_SIZE]
	col = bytes(b & 15 for b in data[2 + BITMAP_SIZE + SCR_SIZE : -1])
	bg = data[-1] & 15

	OUT_COL_BIN.parent.mkdir(parents=True, exist_ok=True)
	col_data = scr + col + bytes([bg])
	OUT_COL_BIN.write_bytes(col_data)
	OUT_BMP.write_bytes(struct.pack("<H", LOAD_BMP) + bmp)
	decode_preview(bmp, scr, col, bg).save(PREVIEW)
	print(f"wrote {OUT_COL_BIN.relative_to(ROOT)} data={len(col_data)} bg={bg}")
	print(f"wrote {OUT_BMP.relative_to(ROOT)} load=${LOAD_BMP:04x} data={len(bmp)}")
	print(f"wrote {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
