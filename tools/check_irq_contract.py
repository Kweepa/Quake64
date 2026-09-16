#!/usr/bin/env python3
"""Fail the build if GAME loaders poke CIA1 / $d01a / $0314 outside the contract.

irq_entry does not ack CIA1. CIA1 Timer A + $0314=irq_entry = IRQ storm.
The only GAME play-IRQ kill is load_irq_off. The only GAME disk entry is LoadPrg
(reboot_game is the KERNAL-boot exception: $EA31 then IOINIT+$FFD5).
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOADER = ROOT / "src" / "loader.asm"
IRQ = ROOT / "src" / "irq.asm"

LABEL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\b")

# GAME files that may talk to CIA1 / $d01a / $0314 / KERNAL LOAD.
# Everything else in src/ is play code and must go through load_irq_off / LoadPrg.
ALLOW_IRQ_FILES = {
    "loader.asm",
    "irq.asm",
    "boot.asm",
    "splashc.asm",
    "menu.asm",
    "menu_sfx.asm",
}

POKE = re.compile(
    r"\b(sta|lda)\s+(\$dc0d|\$d01a|\$0314|\$0315)\b"
    r"|\bjsr\s+(\$ff84|\$ffd5|\$ffc3)\b",
    re.IGNORECASE,
)


def code_of_line(line: str) -> str:
    if '"' not in line and "'" not in line:
        return line.split(";", 1)[0]
    out = []
    q = None
    for ch in line:
        if q:
            if ch == q:
                q = None
            out.append(ch)
            continue
        if ch in "\"'":
            q = ch
            out.append(ch)
            continue
        if ch == ";":
            break
        out.append(ch)
    return "".join(out)


def code_of(text: str) -> str:
    return "\n".join(code_of_line(line) for line in text.splitlines())


def routines(path: Path) -> dict[str, list[str]]:
    """Global-label name -> list of bodies (LoadPrg exists twice, Krill/KERNAL)."""
    found: dict[str, list[str]] = {}
    name = None
    buf: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = LABEL_RE.match(line)
        if m and not line[:1].isspace():
            if name is not None:
                found.setdefault(name, []).append("\n".join(buf))
            name = m.group(1)
            buf = [line]
        elif name is not None:
            buf.append(line)
    if name is not None:
        found.setdefault(name, []).append("\n".join(buf))
    return found


def has(body: str, needle: str) -> bool:
    return needle.lower() in code_of(body).lower()


def fail(msg: str) -> None:
    print(f"check_irq_contract: {msg}", file=sys.stderr)


def check_must_forbid(name: str, bodies: list[str], must: list[str], forbid: list[str]) -> int:
    errs = 0
    if not bodies:
        fail(f"{name}: missing")
        return 1
    for i, body in enumerate(bodies):
        tag = name if len(bodies) == 1 else f"{name}[{i}]"
        for n in must:
            if not has(body, n):
                fail(f"{tag}: missing `{n}`")
                errs += 1
        for n in forbid:
            if has(body, n):
                fail(f"{tag}: must not `{n}` (use load_irq_off / LoadPrg)")
                errs += 1
    return errs


def check_loader() -> int:
    r = routines(LOADER)
    errs = 0
    errs += check_must_forbid(
        "load_irq_off",
        r.get("load_irq_off", []),
        must=["sta $dc0d", "sta $d01a", "sei"],
        forbid=["sta $0314", "cli"],
    )
    if len(r.get("load_irq_off", [])) != 1:
        fail(f"load_irq_off: want exactly one definition, got {len(r.get('load_irq_off', []))}")
        errs += 1

    errs += check_must_forbid(
        "LoadPrg",
        r.get("LoadPrg", []),
        must=["jsr load_irq_off"],
        forbid=["sta $dc0d", "sta $d01a", "jsr $ff84"],
    )
    if len(r.get("LoadPrg", [])) != 2:
        fail(f"LoadPrg: want Krill+KERNAL (2), got {len(r.get('LoadPrg', []))}")
        errs += 1

    errs += check_must_forbid(
        "LoadLevel",
        r.get("LoadLevel", []),
        must=["jsr load_irq_off", "jsr LoadPrg"],
        forbid=["sta $dc0d", "sta $d01a", "sta $0314", "jsr $ffd5", "jsr $ff84"],
    )
    errs += check_must_forbid(
        "maybe_stream_room",
        r.get("maybe_stream_room", []),
        must=["jsr load_irq_off"],
        forbid=["sta $dc0d", "sta $0314", "jsr $ffd5", "jsr $ff84", "jsr $ffc3"],
    )
    errs += check_must_forbid(
        "reboot_game",
        r.get("reboot_game", []),
        must=["jsr load_irq_off", "sta $0314", "jsr $ff84", "jsr $ffd5"],
        forbid=["sta $dc0d"],
    )

    # Any remaining sta $dc0d in loader.asm outside load_irq_off.
    irq_off = r.get("load_irq_off", [""])[0]
    whole = LOADER.read_text(encoding="utf-8")
    # Count sta $dc0d in file vs in load_irq_off.
    file_dc = len(re.findall(r"\bsta\s+\$dc0d\b", code_of(whole), re.I))
    off_dc = len(re.findall(r"\bsta\s+\$dc0d\b", code_of(irq_off), re.I))
    if file_dc != off_dc:
        fail(f"loader.asm: sta $dc0d only allowed in load_irq_off ({file_dc} in file, {off_dc} in helper)")
        errs += 1
    return errs


def check_irq_entry() -> int:
    text = IRQ.read_text(encoding="utf-8")
    r = routines(IRQ)
    body = "\n".join(r.get("irq_entry", []))
    if not body:
        fail("irq_entry: missing")
        return 1
    # Must not ack CIA1.
    if has(body, "sta $dc0d") or has(body, "lda $dc0d"):
        fail("irq_entry: must not touch $dc0d (no CIA1 ack)")
        return 1
    if "irq_entry" not in text or "load_irq_off" not in text:
        fail("irq.asm: irq_entry must mention load_irq_off (CIA1 storm comment)")
        return 1
    return 0


def check_other_src() -> int:
    errs = 0
    src = ROOT / "src"
    for path in sorted(src.glob("*.asm")):
        if path.name in ALLOW_IRQ_FILES:
            continue
        for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            code = code_of_line(line)
            m = POKE.search(code)
            if m:
                fail(f"{path.name}:{i}: {m.group(0)} — GAME disk/IRQ poke belongs in loader.asm / irq.asm")
                errs += 1
    return errs


def main() -> int:
    errs = check_loader() + check_irq_entry() + check_other_src()
    if errs:
        fail(f"{errs} violation(s)")
        return 1
    print("check_irq_contract: ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
