"""Shared sprite packing: 24×21 cells, leftover-ink, zero-byte occupancy mask."""

from __future__ import annotations

import re
from pathlib import Path

W = 48
H = 42
SW = 24
SH = 21
CELL = 64


def bchunk(data: list[int], width: int = 16) -> str:
    lines = []
    for i in range(0, len(data), width):
        chunk = data[i : i + width]
        lines.append("\t!byte " + ",".join(f"${b:02x}" for b in chunk))
    return "\n".join(lines) + "\n"


def pack_zeromask(data: list[int]) -> list[int]:
    raw = list(data[:CELL]) + [0] * max(0, CELL - len(data))
    mask = [0] * 8
    payload: list[int] = []
    for i, b in enumerate(raw):
        if b:
            mask[i >> 3] |= 1 << (i & 7)
            payload.append(b)
    return mask + payload


def unpack_zeromask(packed: list[int]) -> list[int]:
    out = [0] * CELL
    p = 8
    for i in range(CELL):
        if packed[i >> 3] & (1 << (i & 7)):
            out[i] = packed[p]
            p += 1
    return out


def pack_24x21(pix: list[list[int]]) -> list[int]:
    out = [0] * CELL
    for y in range(SH):
        for col in range(3):
            b = 0
            for bit in range(8):
                if pix[y][col * 8 + bit]:
                    b |= 0x80 >> bit
            out[y * 3 + col] = b
    return out


def pack_window(pix: list[list[int]], ox: int, oy: int) -> list[int]:
    out = [0] * CELL
    for y in range(SH):
        py = oy + y
        for col in range(3):
            b = 0
            for bit in range(8):
                px = ox + col * 8 + bit
                if 0 <= py < H and 0 <= px < W and pix[py][px]:
                    b |= 0x80 >> bit
            out[y * 3 + col] = b
    return out


def blit_cell(pix: list[list[int]], cell: list[int], ox: int, oy: int) -> None:
    for y in range(SH):
        py = oy + y
        if py < 0 or py >= H:
            continue
        for col in range(3):
            b = cell[y * 3 + col]
            for bit in range(8):
                if not (b & (0x80 >> bit)):
                    continue
                px = ox + col * 8 + bit
                if 0 <= px < W:
                    pix[py][px] = 1


def unpack_2x2(data: list[int]) -> list[list[int]]:
    pix = [[0] * W for _ in range(H)]
    blit_cell(pix, data[0:64], 0, 0)
    blit_cell(pix, data[64:128], 24, 0)
    blit_cell(pix, data[128:192], 0, 21)
    blit_cell(pix, data[192:256], 24, 21)
    return pix


def composite(windows: list[tuple[int, int]], cells: list[list[int]]) -> list[list[int]]:
    pix = [[0] * W for _ in range(H)]
    for (ox, oy), cell in zip(windows, cells):
        blit_cell(pix, cell, ox, oy)
    return pix


def leftover_ink(pix: list[list[int]], windows: list[tuple[int, int]]) -> list[tuple[int, int]]:
    pts: list[tuple[int, int]] = []
    for y in range(H):
        for x in range(W):
            if not pix[y][x]:
                continue
            if not any(ox <= x < ox + SW and oy <= y < oy + SH for ox, oy in windows):
                pts.append((x, y))
    return pts


def parse_label_bytes(path: Path, label: str) -> list[int]:
    text = path.read_text(encoding="utf-8")
    lines = text.splitlines()
    acc: list[int] = []
    grab = False
    for line in lines:
        s = line.strip()
        if s.startswith(";"):
            continue
        m = re.match(r"^([a-z0-9_]+)$", s)
        if m:
            if grab:
                break
            grab = m.group(1) == label
            continue
        if grab and "!byte" in line:
            acc.extend(int(h, 16) for h in re.findall(r"\$([0-9a-fA-F]{2})", line))
    if not acc:
        raise SystemExit(f"{path}: no bytes for {label}")
    return acc


def load_png_1bit(path: Path, width: int, height: int) -> list[list[int]]:
    from PIL import Image

    im = Image.open(path).convert("RGB")
    if im.size != (width, height):
        raise SystemExit(f"{path.name}: expected {width}x{height}, got {im.size[0]}x{im.size[1]}")
    pix = [[0] * width for _ in range(height)]
    src = im.load()
    for y in range(height):
        for x in range(width):
            r, g, b = src[x, y][:3]
            if r > 16 or g > 16 or b > 16:
                pix[y][x] = 1
    return pix


def load_fx_raw(png: Path, asm: Path, label: str) -> list[int]:
    if png.is_file():
        return pack_24x21(load_png_1bit(png, SW, SH))
    if not asm.is_file():
        raise SystemExit(f"missing {png} and {asm}")
    raw = parse_label_bytes(asm, label)
    header = asm.read_text(encoding="utf-8")[:400]
    if "zeromask" in header:
        return unpack_zeromask(raw)
    return list(raw[:CELL])


leftover_ink = leftover_ink
pack_window = pack_window
unpack_2x2 = unpack_2x2
pack_zeromask = pack_zeromask
unpack_zeromask = unpack_zeromask
parse_label_bytes = parse_label_bytes
