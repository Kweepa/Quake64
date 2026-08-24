"""I/P nibble sizes: GOP vs reuse-any-P; I omitted on P frames."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
doc = json.loads((ROOT / "editor" / "quake64.json").read_text(encoding="utf-8"))
NIB = (-8, 7)
TYPES = ["Grunt", "Knight", "Rottweiler", "Scrag", "Ogre", "Shambler", "Chthon"]


def s_frame(fr):
    xyz = []
    for key in ("x", "y", "z"):
        for v in fr:
            xyz.append(int(v[key]))
    return xyz


def fits(fr, P):
    return all(NIB[0] <= fr[k] - P[k] <= NIB[1] for k in range(39))


def pack_gop(frs):
    plist = [frs[0][:]]
    P = frs[0]
    nI = 0
    nPfr = 1  # frame 0 is P
    for fr in frs[1:]:
        if fits(fr, P):
            nI += 1
        else:
            plist.append(fr[:])
            P = fr
            nPfr += 1
    return len(plist), nI, nPfr


def pack_any(frs):
    plist = [frs[0][:]]
    nI = 0
    nPfr = 1
    for fr in frs[1:]:
        hit = False
        for P in reversed(plist):
            if fits(fr, P):
                hit = True
                break
        if hit:
            nI += 1
        else:
            plist.append(fr[:])
            nPfr += 1
    return len(plist), nI, nPfr


def size(nf, n_p, nI):
    return 2 + nf + n_p * 39 + nI * 20


print(f"{'type':12} {'unpk':>5}  GOP nP/I/bytes  ANY nP/I/bytes")
for e in doc["enemies"]:
    if e["name"] not in TYPES:
        continue
    frs = [s_frame(fr) for fr in e["frames"]]
    nf = len(frs)
    unpk = 1 + nf * 39
    n_p, nI, _ = pack_gop(frs)
    g = size(nf, n_p, nI)
    n_pa, nIa, _ = pack_any(frs)
    a = size(nf, n_pa, nIa)
    print(
        f"{e['name']:12} {unpk:5}  "
        f"{n_p:3}/{nI:3}/{g:5}  "
        f"{n_pa:3}/{nIa:3}/{a:5}  "
        f"gop {g / unpk:.2f} any {a / unpk:.2f}"
    )
