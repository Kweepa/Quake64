#!/usr/bin/env python3
"""Write build-report.json for the editor Build tab.

Success replaces the file. --failed STEP keeps the previous sections and
stamps ok/step/time so a broken build still names the command that died.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import subprocess
import sys
from datetime import datetime
from pathlib import Path

from checkheap import heap_report
from genaibanks import DOS_NAMES, ENEMY_BANK_MAX, HEADER_SIZE, MAGIC
from memoryreport import module_report
from mkdisk import find_c1541

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build-report.json"
ENEMY_DIR = ROOT / "enemies"

VARIANTS = (
    ("kernal", "game.lbl"),
    ("krill", "game-krill.lbl"),
)
DISKS = ("quake64.d64", "quake64-krill.d64")

FILETYPES = {"prg", "seq", "usr", "rel", "del"}
DIR_LINE = re.compile(r'^\s*(\d+)\s+"([^"]*)"\s+(\S+)')
FREE_LINE = re.compile(r"(\d+)\s+blocks free", re.I)


def now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def parse_c1541_dir(text: str) -> dict:
    files: list[dict[str, int | str]] = []
    free: int | None = None
    for line in text.splitlines():
        free_m = FREE_LINE.search(line)
        if free_m:
            free = int(free_m.group(1))
            continue
        m = DIR_LINE.match(line)
        if not m:
            continue
        kind = m.group(3).lower().rstrip("<")
        if kind not in FILETYPES:
            continue
        files.append({"name": m.group(2).strip(), "blocks": int(m.group(1))})
    if free is None:
        raise SystemExit("c1541 directory has no blocks-free line")
    return {"free": free, "files": files}


def disk_listing(c1541: Path, name: str) -> dict:
    path = ROOT / name
    if not path.is_file():
        raise SystemExit(f"missing: {path}")
    proc = subprocess.run(
        [str(c1541), "-attach", str(path), "-dir"],
        capture_output=True,
        text=True,
        encoding="latin-1",
        errors="replace",
    )
    text = proc.stdout or ""
    if "blocks free" not in text.lower():
        text = (proc.stdout or "") + "\n" + (proc.stderr or "")
    if proc.returncode != 0 and "blocks free" not in text.lower():
        err = (proc.stderr or proc.stdout or "").strip()
        raise SystemExit(f"c1541 -dir {name} failed: {err}")
    listing = parse_c1541_dir(text)
    listing["name"] = name
    return listing


def read_bank(path: Path, name: str) -> dict:
    raw = path.read_bytes()
    if len(raw) < 2 + HEADER_SIZE:
        raise SystemExit(f"{path}: too short")
    payload = raw[2:]
    magic, code_n, rel_n, map_n, _entry, pose_off = struct.unpack_from(
        "<4sHHHHH", payload, 0
    )
    if magic != MAGIC:
        raise SystemExit(f"{path}: bad magic {magic!r}")
    if pose_off > len(payload):
        raise SystemExit(f"{path}: pose offset past end")
    return {
        "name": name,
        "bank": len(payload),
        "code": code_n,
        "pose": len(payload) - pose_off,
        "reloc": rel_n,
        "map": map_n,
        "max": ENEMY_BANK_MAX,
    }


def collect_banks() -> list[dict]:
    banks = []
    for name in DOS_NAMES:
        path = ENEMY_DIR / f"{name}.prg"
        if not path.is_file():
            raise SystemExit(f"missing: {path}")
        banks.append(read_bank(path, name))
    crush = ENEMY_DIR / "crush.prg"
    if crush.is_file() and crush.stat().st_size > 2:
        banks.append(read_bank(crush, "crush"))
    return banks


def slim_level(lv: dict) -> dict:
    return {
        "map_bytes": lv["map_bytes"],
        "worst_room": lv["worst_room"],
        "where": lv["where"],
        "worst_types": lv["worst_types"],
        "room_assets": lv["room_assets"],
        "need": lv["need"],
        "slack": lv["slack"],
    }


def collect_variant(labels: str, *, symbols: bool = False) -> dict:
    mods = module_report(labels, symbols=symbols)
    heap, failed = heap_report(labels)
    if failed:
        raise SystemExit(f"{labels}: heap check failed")
    game = heap["game"]
    return {
        "game": {
            "load": mods["load"],
            "end": mods["end"],
            "bytes": mods["bytes"],
            "heap": game["heap_available"],
        },
        "modules": mods["modules"],
        "levels": {key: slim_level(lv) for key, lv in heap["levels"].items()},
    }


def write_report(report: dict) -> None:
    OUT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT}")


def load_previous() -> dict:
    if not OUT.is_file():
        return {}
    try:
        data = json.loads(OUT.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def stamp_failure(step: str) -> None:
    report = load_previous()
    report["ok"] = False
    report["step"] = step
    report["time"] = now()
    report.setdefault("variants", {})
    report.setdefault("banks", [])
    report.setdefault("disks", {})
    write_report(report)


def collect_success() -> dict:
    c1541 = find_c1541()
    if not c1541:
        raise SystemExit("c1541 not found. Install VICE or set VICE_BIN.")
    return {
        "ok": True,
        "step": None,
        "time": now(),
        "variants": {
            name: collect_variant(labels, symbols=(name == "kernal"))
            for name, labels in VARIANTS
        },
        "banks": collect_banks(),
        "disks": {name: disk_listing(c1541, name) for name in DISKS},
    }


def main() -> None:
    ap = argparse.ArgumentParser(description="Write build-report.json")
    ap.add_argument(
        "--failed",
        metavar="STEP",
        help="stamp a failed build step and keep the previous report sections",
    )
    args = ap.parse_args()
    if args.failed is not None:
        stamp_failure(args.failed)
        return
    try:
        write_report(collect_success())
    except SystemExit:
        raise
    except Exception as exc:
        print(f"buildreport: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
