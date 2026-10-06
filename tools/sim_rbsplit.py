#!/usr/bin/env python3
"""Cycle-level check of the raster-split writes (src/irq.asm, rbdelay, rbcal).

Runs the *assembled* bytes under py65 (pip install py65) against a model of the
VIC raster counter: the CPU runs N x the video clock (N = 1 is stock C64), line
length V video cycles (PAL 63, NTSC 65), $d012 steps at line cycle e (0 or 1).

  handler    irq_entry -> .split / .view with a given rb cell. Reports where
             the stores land, in cycles after the start of line L:
               mid split   $d018          window 48..55 (L = 186, IRQ on 184)
               HUD -> view $d018, $d021   untimed (L = 122, IRQ on 118): after
                                          row 8's c-access on 115 (>= -6V) and
                                          before 123's (<= V+11); row 8 is a
                                          solid black bar, so nothing else
                                          depends on the cycle
  calibrate  rb_calibrate from the assembled menu, from a random frame phase,
             then the handler with the cells it wrote.
  init_irq   cold-start cell sanity (garbage -> 1 MHz counts).

  python tools/sim_rbsplit.py                  # PAL sweep, all speeds
  python tools/sim_rbsplit.py -n 16 --ntsc     # one speed
"""

from __future__ import annotations

import argparse
import random
import re
import subprocess
import sys
import tempfile
from pathlib import Path

from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"

CELL = 0x08F5  # rb_n_lo, rb_n_hi
IRQ_PHASE = 0x2B
TRAP = 0xFFF0
SPLIT_WIN = (48, 55)
VIEW_MIN = -6  # lines before 122 (row 8 = 115..122, c-access done on 115)
VIEW_MAX = 11  # line 123 cycles; V is added (c-access starts at 12)
LEAD_SPLIT = 2  # IRQ fires on L - LEAD (184 for L = 186)
LEAD_VIEW = 4  # 118 for L = 122


def acme_exe() -> str:
    env = ROOT / "setup-env.bat"
    if env.exists():
        for line in env.read_text(errors="replace").splitlines():
            m = re.match(r"\s*set\s+ACME=(.+)", line, re.I)
            if m:
                return m.group(1).strip()
    return "acme"


def assemble(asm: str, outdir: Path) -> tuple[bytes, dict[str, int]]:
    base = Path(asm).stem
    prg = outdir / f"{base}.prg"
    lbl = outdir / f"{base}.lbl"
    cmd = [acme_exe(), "-f", "cbm", "-o", str(prg), "--vicelabels", str(lbl), asm]
    r = subprocess.run(cmd, cwd=SRC, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"ACME failed on {asm}:\n{r.stdout}\n{r.stderr}")
    labels: dict[str, int] = {}
    for line in lbl.read_text().splitlines():
        m = re.match(r"al C:([0-9a-fA-F]+) \.(\S+)", line)
        if m:
            labels[m.group(2)] = int(m.group(1), 16)
    return prg.read_bytes(), labels


class Machine:
    """6510 + a $d012 that follows (cpu cycle) / N video cycles."""

    def __init__(self, prg: bytes, n: float, v: int, e: int, t0: float):
        mpu = MPU()
        base = mpu.memory
        load = prg[0] | (prg[1] << 8)
        for i, b in enumerate(prg[2:]):
            base[load + i] = b
        mem = ObservableMemory(subject=base)
        mpu.memory = mem
        self.mpu, self.mem = mpu, mem
        self.n, self.v, self.e = n, v, e
        self.lines = 312 if v == 63 else 263
        self.t0 = t0  # video time (cycles since frame start) when mpu cycles == 0
        self.writes: list[tuple[int, float]] = []
        mem.subscribe_to_read([0xD012], self._d012)
        mem.subscribe_to_read([0xD011], self._d011)
        mem.subscribe_to_read([0xD019], lambda a: 1)
        mem.subscribe_to_write([0xD018, 0xD021, 0xD020], self._wr)

    def t(self, extra: int = 3) -> float:
        # every device access here is the 4th cycle of an abs op (start + 3)
        return self.t0 + (self.mpu.processorCycles + extra) / self.n

    def line(self) -> int:
        return int((self.t() - self.e) // self.v) % self.lines

    def _d012(self, addr: int) -> int:
        return self.line() & 0xFF

    def _d011(self, addr: int) -> int:
        return 0x1B | (0x80 if self.line() >= 256 else 0)

    def _wr(self, addr: int, val: int) -> None:
        self.writes.append((addr, self.t()))

    def call(self, pc: int, limit: int = 60_000_000) -> None:
        m = self.mpu
        ret = TRAP - 1
        m.memory[0x1FF] = (ret >> 8) & 0xFF
        m.memory[0x1FE] = ret & 0xFF
        m.sp = 0xFD
        m.pc = pc
        while m.pc != TRAP:
            m.step()
            if m.processorCycles > limit:
                raise RuntimeError("runaway")


def run_handler(game: bytes, lab: dict, n: float, v: int, e: int, lat: int,
                frac: float, which: str, cell: tuple[int, int]):
    """Cycles after the start of line L of the first $d018 store (and $d021)."""
    L = 186 if which == "split" else 122
    lead = LEAD_SPLIT if which == "split" else LEAD_VIEW
    t_start = (L - lead) * v + (lat + 7 + frac) / n  # 7 = IRQ sequence
    mach = Machine(game, n, v, e, t_start)
    mem = mach.mem
    for i, b in enumerate(cell):
        mem[CELL + i] = b
    mem[IRQ_PHASE] = 1 if which == "split" else 0
    mem[0x01] = 0x36
    m = mach.mpu
    m.pc = lab["irq_entry"]
    m.sp = 0xF0
    need = 1 if which == "split" else 2
    while m.processorCycles < 4_000_000:
        m.step()
        if sum(1 for a, _ in mach.writes if a in (0xD018, 0xD021)) >= need:
            break
    base = L * v
    d018 = next(t for a, t in mach.writes if a == 0xD018) - base
    d021 = next((t for a, t in mach.writes if a == 0xD021), None)
    return d018, (d021 - base if d021 is not None else None)


def run_cal(menu: bytes, lab: dict, n: float, v: int, e: int, rng: random.Random):
    lines = 312 if v == 63 else 263
    mach = Machine(menu, n, v, e, rng.uniform(0, lines * v))
    mem = mach.mem
    for i in range(2):
        mem[CELL + i] = 0
    mem[0xD018] = 0x15
    mem[0x02A6] = 1 if v == 63 else 0  # KERNAL PAL flag
    mach.call(lab["rb_calibrate"])
    cell = tuple(mem[CELL + i] for i in range(2))
    return cell, mach.mpu.processorCycles / n / v  # lines spent


def sweep(game, glab, cell, n, v, e, which):
    lo, hi = 1e9, -1e9
    d2lo, d2hi = 1e9, -1e9
    fracs = (0.0,) if n == 1 else (0.0, 0.25, 0.5, 0.75)  # N=1 is phase-locked
    for lat in range(0, 8):
        for frac in fracs:
            w, w3 = run_handler(game, glab, n, v, e, lat, frac, which, cell)
            lo, hi = min(lo, w), max(hi, w)
            if w3 is not None:
                d2lo, d2hi = min(d2lo, w3), max(d2hi, w3)
    return lo, hi, d2lo, d2hi


def check_init(game: bytes, glab: dict) -> int:
    """init_irq: garbage / unset cells -> 1 MHz counts; valid cells untouched."""
    bad = 0
    cases = [
        ((0, 0), (3, 1)),
        ((0xFF, 0xFF), (3, 1)),
        ((9, 9), (3, 1)),
        ((77, 3), (77, 3)),
        ((5, 8), (5, 8)),
        ((77, 0), (3, 1)),
    ]
    for cell, want in cases:
        mach = Machine(game, 1, 63, 0, 0.0)
        for i, b in enumerate(cell):
            mach.mem[CELL + i] = b
        mach.call(glab["init_irq"])
        got = tuple(mach.mem[CELL + i] for i in range(2))
        ok = got == want
        bad += not ok
        print(f"  init_irq {cell} -> {got}{'' if ok else f'  WANT {want}'}")
    return bad


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("-n", type=float, action="append", help="CPU:VIC ratio (repeat)")
    ap.add_argument("--ntsc", action="store_true")
    ap.add_argument("--seeds", type=int, default=3, help="calibrator frame phases")
    args = ap.parse_args()

    speeds = args.n or [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64]
    with tempfile.TemporaryDirectory() as td:
        out = Path(td)
        game, glab = assemble("quake64.asm", out)
        menu, mlab = assemble("menu.asm", out)
    print(f"rb_delay game ${glab['rb_delay']:04x}-${glab['rb_delay_end']:04x}  "
          f"menu ${mlab['rb_delay']:04x}-${mlab['rb_delay_end']:04x}")
    bad = check_init(game, glab)
    rng = random.Random(64)
    v = 65 if args.ntsc else 63
    print(f"\n{'NTSC' if v == 65 else 'PAL'} V={v}   mid split W {SPLIT_WIN[0]}..{SPLIT_WIN[1]}, "
          f"view (both stores) {VIEW_MIN * v}..{v + VIEW_MAX}")
    print(f"{'N':>4} {'e':>1} {'cell n':>10} {'lines':>6}  {'split W':>13}  {'view $d018':>15}  {'view $d021':>15}")
    for n in speeds:
        for e in (0, 1):
            for _ in range(args.seeds):
                cell, lines = run_cal(menu, mlab, n, v, e, rng)
                sl, sh, _, _ = sweep(game, glab, cell, n, v, e, "split")
                vl, vh, wl, wh = sweep(game, glab, cell, n, v, e, "view")
                ok = (SPLIT_WIN[0] <= sl and sh <= SPLIT_WIN[1]
                      and min(vl, wl) >= VIEW_MIN * v and max(vh, wh) <= v + VIEW_MAX)
                bad += not ok
                print(f"{n:>4} {e:>1} {str(cell):>10} {lines:>6.0f}  "
                      f"{sl:6.1f}..{sh:<6.1f}  {vl:7.1f}..{vh:<7.1f}  {wl:7.1f}..{wh:<7.1f}"
                      f"{'' if ok else '  <-- outside'}")
    print(f"\n{bad} failure(s)")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
