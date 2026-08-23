#!/usr/bin/env python3
"""Build quake64.d64 from boot/menu/tab/fnt/scr/sqt/game PRGs via c1541."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Optional

FILES = (
    ("boot.prg", "quake64"),
    ("menu.prg", "menu,p"),
    ("tab.prg", "tab,p"),
    ("fnt.prg", "fnt,p"),
    ("scr.prg", "scr,p"),
    ("sqt.prg", "sqt,p"),
    ("game.prg", "game,p"),
)


def find_c1541(explicit: Optional[Path] = None) -> Optional[Path]:
    if explicit is not None:
        return explicit if explicit.is_file() else None
    env = os.environ.get("VICE_BIN")
    if env:
        for name in ("c1541.exe", "c1541"):
            p = Path(env) / name
            if p.is_file():
                return p
    w = shutil.which("c1541")
    return Path(w) if w else None


def main() -> None:
    ap = argparse.ArgumentParser(description="Build quake64.d64 via c1541")
    ap.add_argument("--out", default="quake64.d64")
    ap.add_argument("--c1541", type=Path, default=None)
    args = ap.parse_args()

    c1541 = find_c1541(args.c1541)
    if not c1541:
        print(
            "c1541 not found. Install VICE or set VICE_BIN / --c1541.",
            file=sys.stderr,
        )
        sys.exit(1)

    for src, _dos in FILES:
        p = Path(src)
        if not p.is_file():
            print(f"missing: {p}", file=sys.stderr)
            sys.exit(1)

    d64 = Path(args.out)
    cmd = [
        str(c1541),
        "-format",
        "quake64,64",
        "d64",
        str(d64),
        "-attach",
        str(d64),
    ]
    for src, dos in FILES:
        cmd.extend(["-write", str(Path(src).resolve()), dos])
    subprocess.check_call(cmd)
    print(f"Wrote {d64} via {c1541}")


if __name__ == "__main__":
    main()
