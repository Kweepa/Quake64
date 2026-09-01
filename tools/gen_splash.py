#!/usr/bin/env python3
"""Pack ui/conback_c64.png as a split MCM koala (Pepto palette).

320×200 RGB → VIC-II Pepto palette, 2px MCM pairs, 4 colours/cell (bg black + 3).
splashc_data.bin → ACME splashc.asm prepends load $4000 and appends do_splash.
splash.prg      → $6000 bitmap, loaded after colour so it paints in already coloured.
"""
from __future__ import annotations

import struct
import sys
from collections import Counter
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gen_menu_cursor_sprites import PEPTO_RGB, nearest_pepto  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
PNG = ROOT / "ui" / "conback_c64.png"
OUT_COL_BIN = ROOT / "tmp" / "splashc_data.bin"
OUT_BMP = ROOT / "splash.prg"
PREVIEW = ROOT / "tmp" / "splash_preview.png"

LOAD_BMP = 0x6000
COLS = 40
ROWS = 25
BG = 0
BITMAP_SIZE = 8000
SCR_SIZE = 1000


def pack_cell(colors: list[int]) -> tuple[bytes, int, int]:
	"""Auto palette: up to 3 non-black + bg black. Extras remap to nearest slot."""
	assert len(colors) == 32
	counts = Counter(c for c in colors if c != BG)
	top = [c for c, _ in counts.most_common(3)]
	while len(top) < 3:
		top.append(0)
	c01, c10, c11 = top
	slots = (c01, c10, c11)
	pair = {BG: 0}
	for i, c in enumerate(slots):
		if c not in pair:
			pair[c] = i + 1
	cands = [s for s in slots if s != BG] or [BG]

	def map_bits(c: int) -> int:
		if c in pair:
			return pair[c]
		rgb = PEPTO_RGB[c]
		best, best_d = cands[0], 1 << 30
		for cand in cands:
			cr, cg, cb = PEPTO_RGB[cand]
			d = (rgb[0] - cr) ** 2 * 2 + (rgb[1] - cg) ** 2 * 4 + (rgb[2] - cb) ** 2 * 3
			if d < best_d:
				best_d = d
				best = cand
		return pair.get(best, 0)

	out = bytearray(8)
	for row in range(8):
		b = 0
		for p in range(4):
			b = (b << 2) | map_bits(colors[row * 4 + p])
		out[row] = b
	screen = ((c01 & 15) << 4) | (c10 & 15)
	colram = c11 & 15
	return bytes(out), screen, colram


def cell_mcm_colors(img: Image.Image, cx: int, cy: int) -> list[int]:
	"""One MCM colour per 2×1 hires pair (average RGB, then nearest Pepto)."""
	px = img.load()
	cols: list[int] = []
	for y in range(cy * 8, cy * 8 + 8):
		for x in range(cx * 8, cx * 8 + 8, 2):
			r1, g1, b1 = px[x, y][:3]
			r2, g2, b2 = px[x + 1, y][:3]
			cols.append(
				nearest_pepto(((r1 + r2) // 2, (g1 + g2) // 2, (b1 + b2) // 2))
			)
	return cols


def decode_preview(
	bmp: list[int],
	scr: list[int],
	col: list[int],
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
	if not PNG.is_file():
		print(f"missing: {PNG}", file=sys.stderr)
		sys.exit(1)
	src = Image.open(PNG).convert("RGB")
	if src.size != (COLS * 8, ROWS * 8):
		print(
			f"{PNG.name} expected {COLS * 8}×{ROWS * 8}, got {src.size}",
			file=sys.stderr,
		)
		sys.exit(1)

	bmp = [0] * BITMAP_SIZE
	scr = [0] * SCR_SIZE
	col = [0] * SCR_SIZE
	for cy in range(ROWS):
		for cx in range(COLS):
			data, s, c = pack_cell(cell_mcm_colors(src, cx, cy))
			base = cy * 320 + cx * 8
			bmp[base : base + 8] = data
			scr[cy * COLS + cx] = s
			col[cy * COLS + cx] = c

	OUT_COL_BIN.parent.mkdir(parents=True, exist_ok=True)
	col_data = bytes(scr) + bytes(col) + bytes([BG])
	OUT_COL_BIN.write_bytes(col_data)
	OUT_BMP.write_bytes(struct.pack("<H", LOAD_BMP) + bytes(bmp))
	decode_preview(bmp, scr, col, BG).save(PREVIEW)
	print(f"wrote {OUT_COL_BIN.relative_to(ROOT)} data={len(col_data)}")
	print(f"wrote {OUT_BMP.relative_to(ROOT)} load=${LOAD_BMP:04x} data={len(bmp)}")
	print(f"wrote {PREVIEW.relative_to(ROOT)}")


if __name__ == "__main__":
	main()
