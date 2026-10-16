#!/usr/bin/env python3
"""Report authoritative GAME module bounds from zero-byte mod_* labels."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from mkreloc import parse_labels, parse_mem_const

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
GAME_ASM = SRC / "quake64.asm"

LABEL_ROW = re.compile(r"al C:([0-9a-fA-F]+) \.(.+)$")
LABEL_LINE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\b\s*(?:=\s*([^;]*))?")
SOURCE_LINE = re.compile(r'!source\s+"([^"]+)"')


def _label_rows(path: Path) -> list[tuple[int, str]]:
    rows: list[tuple[int, str]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = LABEL_ROW.match(line.strip())
        if m:
            rows.append((int(m.group(1), 16) & 0xFFFF, m.group(2)))
    return rows


def _equate_only(root_asm: Path) -> set[str]:
    """Names defined only as `name = expr`, not as a placed label.

    VICE label dumps give constants and code the same `al` records, so a
    constant whose value lands in the GAME image (5000 = $1388) would
    otherwise split a real routine. `name = *` is a PC marker, not an equate.
    """
    placed: set[str] = set()
    equated: set[str] = set()
    seen: set[Path] = set()

    def walk(path: Path) -> None:
        path = path.resolve()
        if path in seen or not path.is_file():
            return
        seen.add(path)
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            src = SOURCE_LINE.search(line)
            if src and not line.lstrip().startswith(";"):
                walk((path.parent / src.group(1)).resolve())
            if not line or line[0].isspace() or line[0] == ";":
                continue
            m = LABEL_LINE.match(line)
            if not m:
                continue
            name, expr = m.group(1), m.group(2)
            if expr is None or expr.strip().startswith("*"):
                placed.add(name)
            else:
                equated.add(name)

    if not root_asm.is_file():
        raise SystemExit(f"missing: {root_asm}")
    walk(root_asm)
    return equated - placed


def _module_symbols(
    rows: list[tuple[int, str]],
    start: int,
    end: int,
    skip: set[str],
) -> list[dict[str, int | str]]:
    at: dict[int, list[str]] = {}
    for addr, name in rows:
        if addr < start or addr >= end or name.startswith("mod_") or name in skip:
            continue
        names = at.setdefault(addr, [])
        if name not in names:
            names.append(name)
    addrs = sorted(at)
    symbols: list[dict[str, int | str]] = []
    for i, addr in enumerate(addrs):
        nxt = addrs[i + 1] if i + 1 < len(addrs) else end
        size = nxt - addr
        if size <= 0:
            continue
        names = [n for n in at[addr] if not (n.endswith("_end") and len(at[addr]) > 1)]
        if not names:
            names = at[addr]
        symbols.append({"name": " / ".join(names), "start": addr, "bytes": size})
    return symbols


def module_report(labels_path: Path | str, *, symbols: bool = False) -> dict:
    """GAME load/end and mod_* spans. Raises SystemExit if the label file is unusable.

    symbols=True adds each module's placed labels (routines and data) as
    ``symbols``, sized to the next placed label. KERNAL report only; the
    editor Advanced section does not ask for the Krill image.
    """
    path = Path(labels_path)
    if not path.is_file():
        path = ROOT / path
    if not path.is_file():
        raise SystemExit(f"missing: {labels_path}")
    labels = parse_labels(path)
    if "end_game" not in labels:
        raise SystemExit(f"{path}: no end_game")

    starts = sorted(
        ((addr, name[4:]) for name, addr in labels.items() if name.startswith("mod_"))
    )
    if not starts:
        raise SystemExit(f"{path}: no mod_* boundary labels")

    rows = _label_rows(path) if symbols else []
    skip = _equate_only(GAME_ASM) if symbols else set()

    modules: list[dict] = []
    for i, (start, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else labels["end_game"]
        mod: dict = {"name": name, "start": start, "end": end, "bytes": end - start}
        if symbols:
            mod["symbols"] = _module_symbols(rows, start, end, skip)
        modules.append(mod)

    locode = parse_mem_const("LOCODE_BASE")
    end_game = labels["end_game"]
    return {
        "labels": str(path),
        "load": locode,
        "end": end_game,
        "bytes": end_game - locode,
        "modules": modules,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Report GAME module sizes")
    ap.add_argument("--labels", default="game.lbl")
    ap.add_argument("--json", type=Path, default=None)
    args = ap.parse_args()

    report = module_report(args.labels)
    modules = report["modules"]
    locode = int(report["load"])
    end_game = int(report["end"])
    print(f"GAME ${locode:04X}-${end_game:04X}  {end_game - locode} bytes")
    for mod in modules:
        print(
            f"  ${mod['start']:04X}-${mod['end']:04X}  "
            f"{mod['bytes']:5d}  {mod['name']}"
        )

    if args.json is not None:
        out = args.json if args.json.is_absolute() else ROOT / args.json
        out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(f"Wrote {out}")


if __name__ == "__main__":
    main()
