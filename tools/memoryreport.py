#!/usr/bin/env python3
"""Report authoritative GAME module bounds from zero-byte mod_* labels."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from mkreloc import parse_labels, parse_mem_const

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    ap = argparse.ArgumentParser(description="Report GAME module sizes")
    ap.add_argument("--labels", default="game.lbl")
    ap.add_argument("--json", type=Path, default=None)
    args = ap.parse_args()

    labels_path = Path(args.labels)
    if not labels_path.is_file():
        labels_path = ROOT / labels_path
    labels = parse_labels(labels_path)
    if "end_game" not in labels:
        raise SystemExit(f"{labels_path}: no end_game")

    starts = sorted(
        ((addr, name[4:]) for name, addr in labels.items() if name.startswith("mod_"))
    )
    if not starts:
        raise SystemExit(f"{labels_path}: no mod_* boundary labels")

    modules: list[dict[str, int | str]] = []
    for i, (start, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else labels["end_game"]
        modules.append({"name": name, "start": start, "end": end, "bytes": end - start})

    locode = parse_mem_const("LOCODE_BASE")
    end_game = labels["end_game"]
    report = {
        "labels": str(labels_path),
        "load": locode,
        "end": end_game,
        "bytes": end_game - locode,
        "modules": modules,
    }
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
