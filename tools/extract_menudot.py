#!/usr/bin/env python3
"""Extract gfx/menudot1-6.lmp from ref/id1/PAK0.PAK into a horizontal sprite sheet."""
from __future__ import annotations

import struct
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PAK = ROOT / "ref" / "id1" / "PAK0.PAK"
OUT = ROOT / "ui" / "menudot_sheet.png"
FRAMES = [f"gfx/menudot{i}.lmp" for i in range(1, 7)]


def parse_pak(path: Path) -> dict[str, bytes]:
	data = path.read_bytes()
	magic, dir_ofs, dir_size = struct.unpack_from("<4sII", data, 0)
	if magic != b"PACK":
		raise SystemExit(f"not a PACK: {path}")
	files: dict[str, bytes] = {}
	for i in range(dir_size // 64):
		off = dir_ofs + i * 64
		raw = data[off : off + 56].split(b"\x00", 1)[0]
		name = raw.decode("latin1").replace("\\", "/").lower()
		foff, fsz = struct.unpack_from("<II", data, off + 56)
		files[name] = data[foff : foff + fsz]
	return files


def decode_lmp(blob: bytes, pal: list[tuple[int, int, int]]) -> Image.Image:
	w, h = struct.unpack_from("<ii", blob, 0)
	if w <= 0 or h <= 0 or 8 + w * h > len(blob):
		raise SystemExit(f"bad lmp {w}x{h} size {len(blob)}")
	pix = blob[8 : 8 + w * h]
	im = Image.new("RGBA", (w, h))
	put = im.putpixel
	for y in range(h):
		row = y * w
		for x in range(w):
			idx = pix[row + x]
			if idx == 255:
				put((x, y), (0, 0, 0, 0))
			else:
				r, g, b = pal[idx]
				put((x, y), (r, g, b, 255))
	return im


def main() -> None:
	if not PAK.is_file():
		raise SystemExit(f"missing {PAK}")
	pak = parse_pak(PAK)
	pal_blob = pak.get("gfx/palette.lmp")
	if pal_blob is None or len(pal_blob) < 768:
		raise SystemExit("missing gfx/palette.lmp")
	pal = [
		(pal_blob[i], pal_blob[i + 1], pal_blob[i + 2])
		for i in range(0, 768, 3)
	]
	frames: list[Image.Image] = []
	for name in FRAMES:
		blob = pak.get(name)
		if blob is None:
			raise SystemExit(f"missing {name}")
		frames.append(decode_lmp(blob, pal))
	fw, fh = frames[0].size
	for i, im in enumerate(frames):
		if im.size != (fw, fh):
			raise SystemExit(f"frame {i + 1} is {im.size}, expected {(fw, fh)}")
	sheet = Image.new("RGBA", (fw * len(frames), fh))
	for i, im in enumerate(frames):
		sheet.paste(im, (i * fw, 0))
	OUT.parent.mkdir(parents=True, exist_ok=True)
	sheet.save(OUT)
	print(f"wrote {OUT.relative_to(ROOT)} ({fw}x{fh} x {len(frames)})")


if __name__ == "__main__":
	main()
