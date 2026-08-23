"""Pixel oracle: old per-pixel y=64 checks vs setup-split drawer.

Models 6502 SBC/ADC wrapping and the rest_cnt steep continuation.
"""
from __future__ import annotations

import random
import sys


def u8(n: int) -> int:
    return n & 255


def sbc(a: int, m: int) -> tuple[int, int]:
    """SBC with C=1. Returns (A, C)."""
    r = a - m
    return u8(r), (1 if r >= 0 else 0)


def adc0(a: int, m: int) -> tuple[int, int]:
    """ADC with C=0. Returns (A, C)."""
    r = a + m
    return u8(r), (1 if r > 255 else 0)


def clamp_ltr(x0, y0, x1, y1):
    x0 = 0 if x0 < 0 else 191 if x0 > 191 else x0
    x1 = 0 if x1 < 0 else 191 if x1 > 191 else x1
    y0 = 0 if y0 < 0 else 127 if y0 > 127 else y0
    y1 = 0 if y1 < 0 else 127 if y1 > 127 else y1
    if x0 > x1:
        x0, x1 = x1, x0
        y0, y1 = y1, y0
    return x0, y0, x1, y1


def vline(x, y0, y1):
    if y0 > y1:
        y0, y1 = y1, y0
    return [(x, y) for y in range(y0, y1 + 1)]


def flat_pixels(x0, y0, x1, y1, sy, dx, dy):
    err = dx >> 1
    n = dx + 1
    x, y = x0, y0
    out = []
    while True:
        out.append((x, y))
        n -= 1
        if n == 0:
            break
        err, c = sbc(err, dy)
        if c == 0:
            err, _ = adc0(err, dx)
            y += sy
        x += 1
    return out


def steep_pixels(x0, y0, sy, dx, dy):
    """Y-major Bresenham, one stroke (old inner loop)."""
    err = dy >> 1
    n = dy + 1
    x, y = x0, y0
    out = []
    while True:
        out.append((x, y))
        n -= 1
        if n == 0:
            break
        y += sy
        err, c = sbc(err, dx)
        if c == 0:
            err, _ = adc0(err, dy)
            x += 1
    return out


def steep_split_pixels(x0, y0, sy, dx, dy, first, second):
    """Y-major with rest_cnt continuation after `first` plots."""
    err = dy >> 1
    xcnt = first
    rest = second
    x, y = x0, y0
    out = []
    while True:
        out.append((x, y))
        xcnt -= 1
        if xcnt == 0:
            if rest == 0:
                break
            xcnt = rest
            rest = 0
            y += sy
            err, c = sbc(err, dx)
            if c == 0:
                err, _ = adc0(err, dy)
                x += 1
            continue
        y += sy
        err, c = sbc(err, dx)
        if c == 0:
            err, _ = adc0(err, dy)
            x += 1
    return out


def pixels_old(x0, y0, x1, y1):
    x0, y0, x1, y1 = clamp_ltr(x0, y0, x1, y1)
    dx = x1 - x0
    if dx == 0:
        return vline(x0, y0, y1)
    if y1 >= y0:
        dy, sy = y1 - y0, 1
    else:
        dy, sy = y0 - y1, -1
    if dx >= dy:
        return flat_pixels(x0, y0, x1, y1, sy, dx, dy)
    return steep_pixels(x0, y0, sy, dx, dy)


def pixels_new(x0, y0, x1, y1):
    x0, y0, x1, y1 = clamp_ltr(x0, y0, x1, y1)
    dx = x1 - x0
    if dx == 0:
        return vline(x0, y0, y1)
    if y1 >= y0:
        dy, sy = y1 - y0, 1
    else:
        dy, sy = y0 - y1, -1
    if dx >= dy:
        return flat_pixels(x0, y0, x1, y1, sy, dx, dy)
    crosses = (y0 ^ y1) & 0x40
    if not crosses:
        return steep_pixels(x0, y0, sy, dx, dy)
    if sy > 0:
        first = 64 - y0
        second = y1 - 63
    else:
        first = y0 - 63
        second = 64 - y1
    if first + second != dy + 1:
        raise AssertionError(
            f"count {first}+{second} != dy+1={dy + 1} for {(x0, y0, x1, y1)}"
        )
    return steep_split_pixels(x0, y0, sy, dx, dy, first, second)


def check(x0, y0, x1, y1):
    a = pixels_old(x0, y0, x1, y1)
    b = pixels_new(x0, y0, x1, y1)
    if a != b:
        return False, a, b
    return True, a, b


def main() -> int:
    edges = [
        (0, 63, 10, 64),
        (0, 64, 10, 63),
        (5, 0, 5, 127),
        (5, 0, 6, 127),
        (5, 127, 6, 0),
        (10, 63, 10, 63),
        (0, 63, 40, 63),
        (0, 64, 40, 64),
        (3, 50, 3, 80),
        (8, 63, 9, 64),
        (0, 0, 0, 0),
        (191, 127, 0, 0),
        (20, 70, 80, 10),
        (0, 0, 191, 127),
        (15, 64, 15, 64),
        (40, 63, 100, 65),
        (40, 65, 100, 63),
        (1, 1, 2, 100),
        (50, 63, 51, 127),
        (50, 64, 51, 0),
    ]
    fails = []
    for e in edges:
        ok, a, b = check(*e)
        if not ok:
            fails.append((e, a, b))

    for x0 in range(0, 32):
        for y0 in range(0, 32):
            for x1 in range(0, 32):
                for y1 in range(0, 32):
                    ok, a, b = check(x0, y0, x1, y1)
                    if not ok:
                        fails.append(((x0, y0, x1, y1), a, b))
                        if len(fails) > 8:
                            break
                if len(fails) > 8:
                    break
            if len(fails) > 8:
                break
        if len(fails) > 8:
            break

    rng = random.Random(1)
    for _ in range(4000):
        e = (
            rng.randint(0, 191),
            rng.randint(0, 127),
            rng.randint(0, 191),
            rng.randint(0, 127),
        )
        ok, a, b = check(*e)
        if not ok:
            fails.append((e, a, b))
            if len(fails) > 8:
                break

    if fails:
        print(f"FAIL {len(fails)} mismatches, first:")
        e, a, b = fails[0]
        print("  line", e)
        print("  old", a[:40], "len", len(a))
        print("  new", b[:40], "len", len(b))
        return 1
    print("ok: edges, 32x32 window, 4000 random 192x128 lines")
    return 0


if __name__ == "__main__":
    sys.exit(main())
