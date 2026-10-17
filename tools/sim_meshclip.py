#!/usr/bin/env python3
"""Differential check of mesh_project + mesh_clip and clip_draw_xy under py65.

Loads the assembled GAME (game.prg / game.lbl) plus tab.prg / sqt.prg, feeds
random view-space meshes through mesh_project + mesh_clip, and traps every
draw_line call. With --ref DIR it runs the same cases on a second build and
requires the stroked segments to match exactly (endpoint order ignored;
draw_line normalizes it). Reports mesh_clip / clip_draw_xy cycles per scenario.

  python tools/sim_meshclip.py                       # current build only
  python tools/sim_meshclip.py --ref %TEMP%/q64_ref  # ref vs current
"""

from __future__ import annotations

import argparse
import random
import re
import sys
from pathlib import Path

from py65.devices.mpu6502 import MPU

ROOT = Path(__file__).resolve().parents[1]
TRAP = 0xFFF0
EDGES_AT = 0xB000  # heap range: free in this harness
COLS_AT = 0xB100
EVERT_AT = 0xB200
ZCLIP = 0x0100
MAX_EDGES = 32
MAX_VERTS = 16
TAB_INVZ = 512 + 256 + 320  # tab.prg staging order: alog, log, sin, invzl, invzh
TAB_LEN = TAB_INVZ + 256
LIMIT = 4_000_000


def labels(path: Path) -> dict[str, int]:
    out: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.match(r"al C:([0-9a-fA-F]+) \.(\S+)$", line.strip())
        if m:
            out[m.group(2)] = int(m.group(1), 16)
    return out


def prg(path: Path) -> tuple[int, bytes]:
    raw = path.read_bytes()
    return raw[0] | (raw[1] << 8), raw[2:]


class Build:
    def __init__(self, d: Path):
        self.dir = d
        self.lab = labels(d / "game.lbl")
        mem = [0] * 0x10000
        for name in ("game.prg", "sqt.prg"):
            load, body = prg(d / name)
            mem[load : load + len(body)] = body
        _, tab = prg(d / "tab.prg")
        if len(tab) != TAB_LEN:
            sys.exit(f"{d / 'tab.prg'}: {len(tab)} bytes, expected {TAB_LEN}")
        for name, off in (("LOGTAB", 512), ("invzl", TAB_INVZ), ("invzh", TAB_INVZ + 128)):
            n = 256 if name == "LOGTAB" else 128
            a = self.lab[name]
            mem[a : a + n] = tab[off : off + n]
        self.base = mem
        self.mpu = MPU()
        self.mpu.memory = list(mem)
        self.call("mulset_init")
        self.base = list(self.mpu.memory)
        self.evert = "edge_vert_ptr" in self.lab

    def reset(self) -> None:
        self.mpu.memory = list(self.base)
        self.segs: list[tuple[int, int, int, int]] = []

    def call(self, name: str) -> int:
        m = self.mpu
        mem = m.memory
        ret = TRAP - 1
        mem[0x1FF] = (ret >> 8) & 0xFF
        mem[0x1FE] = ret & 0xFF
        m.sp = 0xFD
        m.p &= ~0x08
        m.pc = self.lab[name]
        dl = self.lab["draw_line"]
        x0, y0, x1, y1 = (self.lab[k] for k in ("x0", "y0", "x1", "y1"))
        c0 = m.processorCycles
        while m.pc != TRAP:
            if m.pc == dl:
                self.segs.append((mem[x0], mem[y0], mem[x1], mem[y1]))
                lo = mem[0x100 + ((m.sp + 1) & 0xFF)]
                hi = mem[0x100 + ((m.sp + 2) & 0xFF)]
                m.sp = (m.sp + 2) & 0xFF
                m.pc = ((hi << 8) | lo) + 1
                continue
            m.step()
            if m.processorCycles - c0 > LIMIT:
                raise RuntimeError(f"{name}: runaway at ${m.pc:04X}")
        return m.processorCycles - c0

    def poke16(self, lo: str, hi: str, i: int, v: int) -> None:
        mem = self.mpu.memory
        mem[self.lab[lo] + i] = v & 0xFF
        mem[self.lab[hi] + i] = (v >> 8) & 0xFF


def norm(segs):
    out = []
    for x0, y0, x1, y1 in segs:
        a, b = (x0, y0), (x1, y1)
        out.append(a + b if a <= b else b + a)
    return out


def s16(rng: random.Random, lo: int, hi: int) -> int:
    return rng.randint(lo, hi)


def make_mesh(rng: random.Random, kind: str) -> dict:
    """View-space 8.8 verts, edge list, column ids (shared XZ => shared column)."""
    ncol = rng.randint(1, 8)
    cols = []
    for _ in range(ncol):
        if kind == "inside":
            z = s16(rng, 0x0400, 0x3000)
            span = z * 80 // 100
            x = s16(rng, -span, span)
        elif kind == "near":
            z = s16(rng, -0x0300, 0x0800)
            x = s16(rng, -0x0800, 0x0800)
        else:
            z = s16(rng, 0x0100, 0x2000)
            x = s16(rng, -0x1800, 0x1800)
        cols.append((x, z))
    nv = rng.randint(2, MAX_VERTS)
    verts, col_id = [], []
    for i in range(nv):
        c = i % ncol if i < 2 * ncol else rng.randrange(ncol)
        x, z = cols[c]
        if kind == "inside":
            span = max(z, 0x100) * 50 // 100
            y = s16(rng, -span, span)
        elif kind == "near":
            y = s16(rng, -0x0800, 0x0800)
        else:
            y = s16(rng, -0x1800, 0x1800)
        verts.append((x, y, z))
        col_id.append(c)
    edges = []
    for a in range(nv):
        for b in range(a + 1, nv):
            if col_id[a] == col_id[b] and rng.random() < 0.7:
                edges.append((a, b))
    while len(edges) < rng.randint(1, MAX_EDGES):
        a, b = rng.randrange(nv), rng.randrange(nv)
        if a != b:
            edges.append((a, b))
    rng.shuffle(edges)
    edges = edges[:MAX_EDGES]
    return {"verts": verts, "col": col_id, "edges": edges, "shared": kind != "near" or rng.random() < 0.5}


def run_mesh(b: Build, mesh: dict) -> tuple[list, int]:
    b.reset()
    mem = b.mpu.memory
    lab = b.lab
    verts, edges = mesh["verts"], mesh["edges"]
    for i, (x, y, z) in enumerate(verts):
        b.poke16("CAM_X", "CAM_XH", i, x)
        b.poke16("CAM_Y", "CAM_YH", i, y)
        b.poke16("CAM_Z", "CAM_ZH", i, z)
    for i, (e0, e1) in enumerate(edges):
        mem[EDGES_AT + 2 * i] = e0
        mem[EDGES_AT + 2 * i + 1] = e1
        if b.evert:
            va, vb = verts[e0], verts[e1]
            mem[EVERT_AT + i] = 1 if va[0] == vb[0] and va[2] == vb[2] and va[1] != vb[1] else 0
    if mesh["shared"]:
        for i, c in enumerate(mesh["col"]):
            mem[COLS_AT + i] = c
        col = COLS_AT
    else:
        col = lab["ident_col"]
    mem[lab["col_ptr"]] = col & 0xFF
    mem[lab["col_ptr"] + 1] = col >> 8
    mem[lab["edge_ptr"]] = EDGES_AT & 0xFF
    mem[lab["edge_ptr"] + 1] = EDGES_AT >> 8
    if b.evert:
        mem[lab["edge_vert_ptr"]] = EVERT_AT & 0xFF
        mem[lab["edge_vert_ptr"] + 1] = EVERT_AT >> 8
    mem[lab["mesh_nv"]] = len(verts)
    mem[lab["mesh_ne"]] = len(edges)
    mem[lab["mesh_vmask"]] = 0xFF
    b.call("mesh_project")
    cyc = b.call("mesh_clip")
    return norm(b.segs), cyc


def run_cdxy(b: Build, pts: tuple[int, int, int, int]) -> tuple[list, int, int]:
    b.reset()
    mem = b.mpu.memory
    a = b.lab["ox0l"]
    for i, v in enumerate(pts):
        mem[a + 2 * i] = v & 0xFF
        mem[a + 2 * i + 1] = (v >> 8) & 0xFF
    cyc = b.call("clip_draw_xy")
    return norm(b.segs), b.mpu.p & 1, cyc


def rand_pt(rng: random.Random) -> int:
    r = rng.random()
    if r < 0.4:
        return rng.randint(-120, 120)
    if r < 0.8:
        return rng.randint(-1500, 1500)
    return rng.randint(-20000, 20000)


def check_range(segs, tag: str) -> None:
    for x0, y0, x1, y1 in segs:
        if max(x0, x1) > 191 or max(y0, y1) > 127:
            sys.exit(f"{tag}: segment out of viewport {(x0, y0, x1, y1)}")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--ref", type=Path, help="reference build dir (game.prg/lbl, tab.prg, sqt.prg)")
    ap.add_argument("--new", type=Path, default=ROOT, help="build under test (default: repo root)")
    ap.add_argument("-n", type=int, default=300, help="meshes per scenario")
    ap.add_argument("--seed", type=int, default=64)
    args = ap.parse_args()

    builds = [("new", Build(args.new))]
    if args.ref:
        builds.insert(0, ("ref", Build(args.ref)))
    names = [n for n, _ in builds]

    fails = 0
    print(
        f"{'scenario':10} "
        + " ".join(f"{n + ' cyc/edge':>14}" for n in names)
        + f" {'edges':>7} {'segs':>6} {'xnear':>6} {'vert':>6}"
    )
    for kind in ("inside", "mixed", "near"):
        rng = random.Random(f"{args.seed}:{kind}")
        tot = {n: 0 for n in names}
        nedge = nseg = nx = nvert = 0
        for k in range(args.n):
            mesh = make_mesh(rng, kind)
            vs = mesh["verts"]
            for e0, e1 in mesh["edges"]:
                nx += (vs[e0][2] < ZCLIP) != (vs[e1][2] < ZCLIP)
                nvert += vs[e0][0] == vs[e1][0] and vs[e0][2] == vs[e1][2]
            got = {}
            for n, b in builds:
                segs, cyc = run_mesh(b, mesh)
                check_range(segs, f"{n} {kind} #{k}")
                got[n] = segs
                tot[n] += cyc
            nedge += len(mesh["edges"])
            nseg += len(got["new"])
            if args.ref and got["ref"] != got["new"]:
                fails += 1
                if fails <= 5:
                    print(f"  MISMATCH {kind} #{k}: ref {got['ref']} new {got['new']}")
                    print(f"    verts {mesh['verts']} edges {mesh['edges']} shared {mesh['shared']}")
        print(
            f"{kind:10} "
            + " ".join(f"{tot[n] / nedge:14.1f}" for n in names)
            + f" {nedge:7} {nseg:6} {nx:6} {nvert:6}"
        )

    rng = random.Random(f"{args.seed}:cdxy")
    tot = {n: 0 for n in names}
    ncase = args.n * 4
    for k in range(ncase):
        pts = tuple(rand_pt(rng) for _ in range(4))
        got = {}
        for n, b in builds:
            segs, c, cyc = run_cdxy(b, pts)
            check_range(segs, f"{n} clip_draw_xy #{k}")
            if c != (0 if segs else 1):
                sys.exit(f"{n} clip_draw_xy #{k}: C={c} with segs {segs}")
            got[n] = segs
            tot[n] += cyc
        if args.ref and got["ref"] != got["new"]:
            fails += 1
            if fails <= 5:
                print(f"  MISMATCH clip_draw_xy {pts}: ref {got['ref']} new {got['new']}")
    print(f"{'cdxy':10} " + " ".join(f"{tot[n] / ncase:14.1f}" for n in names) + f" {ncase:7}  (cyc/call)")

    for n, b in builds:
        lab = b.lab
        print(f"{n}: mesh_clip span {lab['clip_draw_xy'] - lab['mesh_clip']} bytes ({b.dir})")
    if fails:
        sys.exit(f"{fails} mismatches")
    if args.ref:
        print("all segments match")


if __name__ == "__main__":
    main()
