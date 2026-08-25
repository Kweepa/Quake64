#!/usr/bin/env python3
"""Cook pickup and door line meshes from editor JSON → src/item_mesh.asm (unique X/Z)."""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "editor" / "quake64.json"
OUT = ROOT / "src" / "item_mesh.asm"

ITEM_MIN = -4
ITEM_MAX = 4
ITEM_ORIGIN = 0
ITEM_BIAS = 1
ITEM_MAX_VERTS = 16
ITEM_MAX_LINES = 16
ITEM_MAX_UNIQUE = 6

# Index = BP_* (shells5=7 has no editor mesh → backpack fallback)
BP_MESH_KEY = [
    "shells",
    "nailgun",
    "nails",
    "grenade launcher",
    "grenades",
    "health 25%",
    "health 50%",
    None,
    "armour",
    "quad damage",
    "pentagram of protection",
    "ring of shadows",
    "silver key",
    "gold key",
    "rune of earth magic",
]
DOOR_MESH_KEY = ["Tech", "Arch", "Tri"]
DOOR_ALIAS = {"tech": "Tech", "arch": "Arch", "tri": "Tri"}


def v(x, y, z):
    return {"x": x, "y": y, "z": z}


DEFAULT_MESHES = {
    "backpack": {
        "verts": [v(-1, 0, -1), v(1, 0, -1), v(0, 0, 1), v(0, 2, 0)],
        "lines": [[0, 1], [1, 2], [2, 0], [3, 0], [3, 1], [3, 2]],
    },
    "health 25%": {
        "verts": [
            v(0, 2, 0),
            v(-1, 1, 0),
            v(0, 1, 1),
            v(1, 1, 0),
            v(0, 1, -1),
            v(0, 0, 0),
        ],
        "lines": [
            [4, 5],
            [3, 5],
            [1, 5],
            [2, 5],
            [1, 4],
            [1, 2],
            [2, 3],
            [3, 4],
            [0, 1],
            [0, 2],
            [0, 4],
            [0, 3],
        ],
    },
    "health 50%": {
        "verts": [
            v(0, 4, 0),
            v(-2, 2, 0),
            v(0, 2, 2),
            v(2, 2, 0),
            v(0, 2, -2),
            v(0, 0, 0),
        ],
        "lines": [
            [4, 5],
            [3, 5],
            [1, 5],
            [2, 5],
            [1, 4],
            [1, 2],
            [2, 3],
            [3, 4],
            [0, 1],
            [0, 2],
            [0, 4],
            [0, 3],
        ],
    },
    "quad damage": {
        "verts": [v(-1, 0, -1), v(1, 0, -1), v(1, 0, 1), v(-1, 0, 1), v(0, 3, 0)],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 0], [4, 1], [4, 2], [4, 3]],
    },
    "pentagram of protection": {
        "verts": [v(0, 0, -2), v(2, 0, 0), v(0, 0, 2), v(-2, 0, 0), v(0, 4, 0)],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 0], [4, 1], [4, 2], [4, 3]],
    },
    "ring of shadows": {
        "verts": [v(-2, 2, 0), v(-1, 1, 0), v(1, 1, 0), v(2, 2, 0), v(1, 4, 0), v(-1, 4, 0)],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 0]],
    },
    "silver key": {
        "verts": [v(-2, 1, 0), v(-2, 2, 0), v(-1, 2, 0), v(-1, 1, 0), v(2, 1, 0), v(2, 0, 0)],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 0], [3, 4], [4, 5]],
    },
    "gold key": {
        "verts": [
            v(-2, 1, 0),
            v(-2, 3, 0),
            v(-1, 3, 0),
            v(-1, 1, 0),
            v(2, 1, 0),
            v(2, 2, 0),
            v(2, 0, 0),
        ],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 0], [3, 4], [4, 5], [4, 6]],
    },
    "rune of earth magic": {
        "verts": [
            v(0, 0, 0),
            v(-2, 1, 0),
            v(-2, 3, 0),
            v(0, 4, 0),
            v(2, 3, 0),
            v(2, 1, 0),
            v(0, 2, 0),
            v(-1, 1, 0),
            v(1, 1, 0),
        ],
        "lines": [
            [0, 1],
            [1, 2],
            [2, 3],
            [3, 4],
            [4, 5],
            [5, 0],
            [3, 6],
            [6, 0],
            [6, 7],
            [6, 8],
        ],
    },
    "Tech": {
        "verts": [v(-2, 0, 0), v(2, 0, 0), v(2, 4, 0), v(-2, 4, 0), v(-2, 2, 0), v(2, 2, 0)],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5]],
    },
    "Arch": {
        "verts": [v(-2, 0, 0), v(2, 0, 0), v(2, 3, 0), v(0, 4, 0), v(-2, 3, 0)],
        "lines": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]],
    },
    "Tri": {
        "verts": [v(-2, 0, 0), v(2, 0, 0), v(0, 4, 0)],
        "lines": [[0, 1], [1, 2], [2, 0]],
    },
}


def clamp_grid(n: int) -> int:
    n = int(n)
    if n < ITEM_MIN:
        return ITEM_MIN
    if n > ITEM_MAX:
        return ITEM_MAX
    return n


def shift_legacy_vert(raw) -> dict | None:
    if isinstance(raw, (list, tuple)) and len(raw) >= 3:
        return {"x": int(raw[0]) - 4, "y": int(raw[1]), "z": int(raw[2]) - 4}
    if isinstance(raw, dict):
        return {
            "x": int(raw.get("x", 0)) - 4,
            "y": int(raw.get("y", 0)),
            "z": int(raw.get("z", 0)) - 4,
        }
    return None


def migrate_items(raw_items, version: int) -> dict:
    if version >= 9 or not isinstance(raw_items, dict):
        return raw_items if isinstance(raw_items, dict) else {}
    out: dict = {}
    for key, mesh in raw_items.items():
        if not isinstance(mesh, dict):
            continue
        verts = []
        for s in mesh.get("verts") or []:
            v = shift_legacy_vert(s)
            if v:
                verts.append(v)
        out[key] = {**mesh, "verts": verts}
    bp = out.get("backpack") or {}
    pts = [(int(v["x"]), int(v["y"]), int(v["z"])) for v in bp.get("verts") or []]
    if pts == [(0, 0, 0), (2, 0, 0), (1, 0, 2), (1, 2, 1)]:
        out["backpack"] = DEFAULT_MESHES["backpack"]
    return out


def parse_vert(raw) -> dict | None:
    if isinstance(raw, (list, tuple)) and len(raw) >= 3:
        return {"x": clamp_grid(raw[0]), "y": clamp_grid(raw[1]), "z": clamp_grid(raw[2])}
    if isinstance(raw, dict):
        return {
            "x": clamp_grid(raw.get("x", 0)),
            "y": clamp_grid(raw.get("y", 0)),
            "z": clamp_grid(raw.get("z", 0)),
        }
    return None


def parse_mesh(raw) -> dict:
    verts: list[dict] = []
    seen: set[tuple[int, int, int]] = set()
    src_verts = (raw or {}).get("verts") or []
    for s in src_verts:
        v = parse_vert(s)
        if not v:
            continue
        k = (v["x"], v["y"], v["z"])
        if k in seen or len(verts) >= ITEM_MAX_VERTS:
            continue
        seen.add(k)
        verts.append(v)
    lines: list[list[int]] = []
    line_seen: set[tuple[int, int]] = set()
    for s in (raw or {}).get("lines") or []:
        if not isinstance(s, (list, tuple)) or len(s) < 2:
            continue
        a, b = int(s[0]), int(s[1])
        if a == b or a < 0 or b < 0 or a >= len(verts) or b >= len(verts):
            continue
        lo, hi = (a, b) if a < b else (b, a)
        if (lo, hi) in line_seen or len(lines) >= ITEM_MAX_LINES:
            continue
        line_seen.add((lo, hi))
        lines.append([lo, hi])
    return {"verts": verts, "lines": lines}


def unique_u8(vals: list[int], cap: int, what: str, name: str) -> tuple[list[int], list[int]]:
    seen: list[int] = []
    idx: list[int] = []
    for v in vals:
        v = v & 0xFF
        if v not in seen:
            if len(seen) >= cap:
                raise SystemExit(f"item {name!r} has >{cap} unique {what}")
            seen.append(v)
        idx.append(seen.index(v))
    return seen, idx


def cook(mesh: dict, name: str) -> dict:
    verts = mesh["verts"]
    lines = mesh["lines"]
    if not verts or not lines:
        raise SystemExit(f"item {name!r} has no geometry")
    ux, xid = unique_u8([v["x"] for v in verts], ITEM_MAX_UNIQUE, "X", name)
    uz, zid = unique_u8([v["z"] for v in verts], ITEM_MAX_UNIQUE, "Z", name)
    pairs: list[tuple[int, int]] = []
    col: list[int] = []
    for xi, zi in zip(xid, zid):
        p = (xi, zi)
        if p not in pairs:
            if len(pairs) >= 16:
                raise SystemExit(f"item {name!r} has >16 unique XZ columns")
            pairs.append(p)
        col.append(pairs.index(p))
    e0, e1, evert = [], [], []
    for a, b in lines:
        e0.append(a)
        e1.append(b)
        va, vb = verts[a], verts[b]
        evert.append(1 if va["x"] == vb["x"] and va["z"] == vb["z"] and va["y"] != vb["y"] else 0)
    edges: list[int] = []
    for a, b in zip(e0, e1):
        edges.extend([a, b])
    return {
        "nv": len(verts),
        "ne": len(lines),
        "nx": len(ux),
        "nz": len(uz),
        "ux": ux,
        "uz": uz,
        "vy": [v["y"] & 0xFF for v in verts],
        "xid": xid,
        "zid": zid,
        "col": col,
        "edges": edges,
        "evert": evert,
    }


def btable(name: str, vals: list[int]) -> str:
    if not vals:
        return f"{name}\n\t!byte 0\n"
    lines = [f"{name}"]
    for i in range(0, len(vals), 16):
        chunk = vals[i : i + 16]
        lines.append("\t!byte " + ",".join(str(v & 0xFF) for v in chunk))
    return "\n".join(lines) + "\n"


def main() -> None:
    ntypes = len(BP_MESH_KEY)
    items = dict(DEFAULT_MESHES)
    if DOC.exists():
        doc = json.loads(DOC.read_text(encoding="utf-8"))
        raw = migrate_items(doc.get("items") or {}, int(doc.get("version") or 0))
        if isinstance(raw, dict):
            for k, v in raw.items():
                mesh = parse_mesh(v)
                key = DOOR_ALIAS.get(k, k)
                if key == "backpack" and not mesh["verts"]:
                    continue
                if key in DOOR_MESH_KEY and not mesh["verts"]:
                    continue
                items[key] = mesh if mesh["verts"] else items.get(key, {"verts": [], "lines": []})

    bp = cook(items["backpack"], "backpack")
    ux_blob, uz_blob, vy_blob = [], [], []
    xid_blob, zid_blob, col_blob = [], [], []
    edge_blob, evert_blob = [], []

    def append_mesh(c: dict) -> tuple[int, int, int, int]:
        vo, eo, uo, zo = len(vy_blob), len(edge_blob), len(ux_blob), len(uz_blob)
        ux_blob.extend(c["ux"])
        uz_blob.extend(c["uz"])
        vy_blob.extend(c["vy"])
        xid_blob.extend(c["xid"])
        zid_blob.extend(c["zid"])
        col_blob.extend(c["col"])
        edge_blob.extend(c["edges"])
        evert_blob.extend(c["evert"])
        return vo, eo, uo, zo

    bp_vo, bp_eo, bp_uo, bp_zo = append_mesh(bp)

    nv = [0] * ntypes
    ne = [0] * ntypes
    nx = [0] * ntypes
    nz = [0] * ntypes
    vo = [0] * ntypes
    eo = [0] * ntypes
    uo = [0] * ntypes
    zo = [0] * ntypes
    for i, key in enumerate(BP_MESH_KEY):
        if not key:
            continue
        mesh = items.get(key) or {"verts": [], "lines": []}
        if not mesh.get("verts") or not mesh.get("lines"):
            continue
        c = cook(mesh, key)
        nv[i], ne[i], nx[i], nz[i] = c["nv"], c["ne"], c["nx"], c["nz"]
        vo[i], eo[i], uo[i], zo[i] = append_mesh(c)

    # Trailing slot = backpack fallback (index BP_NTYPES)
    nv.append(bp["nv"])
    ne.append(bp["ne"])
    nx.append(bp["nx"])
    nz.append(bp["nz"])
    vo.append(bp_vo)
    eo.append(bp_eo)
    uo.append(bp_uo)
    zo.append(bp_zo)

    d_ux, d_uz, d_vy = [], [], []
    d_xid, d_zid, d_col = [], [], []
    d_edge, d_evert = [], []

    def append_door(c: dict) -> tuple[int, int, int, int]:
        dvo, deo, duo, dzo = len(d_vy), len(d_edge), len(d_ux), len(d_uz)
        d_ux.extend(c["ux"])
        d_uz.extend(c["uz"])
        d_vy.extend(c["vy"])
        d_xid.extend(c["xid"])
        d_zid.extend(c["zid"])
        d_col.extend(c["col"])
        d_edge.extend(c["edges"])
        d_evert.extend(c["evert"])
        return dvo, deo, duo, dzo

    d_nv, d_ne, d_nx, d_nz = [], [], [], []
    d_vo, d_eo, d_uo, d_zo = [], [], [], []
    for key in DOOR_MESH_KEY:
        mesh = items.get(key) or DEFAULT_MESHES[key]
        if not mesh.get("verts") or not mesh.get("lines"):
            mesh = DEFAULT_MESHES[key]
        c = cook(mesh, key)
        d_nv.append(c["nv"])
        d_ne.append(c["ne"])
        d_nx.append(c["nx"])
        d_nz.append(c["nz"])
        a, b, c_uo, c_zo = append_door(c)
        d_vo.append(a)
        d_eo.append(b)
        d_uo.append(c_uo)
        d_zo.append(c_zo)

    parts = [
        "; Generated by tools/genitems.py — do not edit",
        f"ITEM_ORIGIN\t= {ITEM_ORIGIN}",
        f"ITEM_BIAS\t= {ITEM_BIAS}",
        "",
        f"item_bp_nv\t!byte {bp['nv']}",
        f"item_bp_ne\t!byte {bp['ne']}",
        f"item_bp_nx\t!byte {bp['nx']}",
        f"item_bp_nz\t!byte {bp['nz']}",
        f"item_bp_vo\t!byte {bp_vo}",
        f"item_bp_eo\t!byte {bp_eo}",
        f"item_bp_uo\t!byte {bp_uo}",
        f"item_bp_zo\t!byte {bp_zo}",
        "",
        btable("item_nv", nv).rstrip(),
        btable("item_ne", ne).rstrip(),
        btable("item_nx", nx).rstrip(),
        btable("item_nz", nz).rstrip(),
        btable("item_vo", vo).rstrip(),
        btable("item_eo", eo).rstrip(),
        btable("item_uo", uo).rstrip(),
        btable("item_zo", zo).rstrip(),
        "",
        btable("item_ux", ux_blob or [0]).rstrip(),
        btable("item_uz", uz_blob or [0]).rstrip(),
        btable("item_vy", vy_blob or [0]).rstrip(),
        btable("item_xid", xid_blob or [0]).rstrip(),
        btable("item_zid", zid_blob or [0]).rstrip(),
        btable("item_col", col_blob or [0]).rstrip(),
        btable("item_edges", edge_blob or [0]).rstrip(),
        btable("item_evert", evert_blob or [0]).rstrip(),
        "",
        btable("door_nv", d_nv).rstrip(),
        btable("door_ne", d_ne).rstrip(),
        btable("door_nx", d_nx).rstrip(),
        btable("door_nz", d_nz).rstrip(),
        btable("door_vo", d_vo).rstrip(),
        btable("door_eo", d_eo).rstrip(),
        btable("door_uo", d_uo).rstrip(),
        btable("door_zo", d_zo).rstrip(),
        "",
        btable("door_ux", d_ux or [0]).rstrip(),
        btable("door_uz", d_uz or [0]).rstrip(),
        btable("door_vy", d_vy or [0]).rstrip(),
        btable("door_xid", d_xid or [0]).rstrip(),
        btable("door_zid", d_zid or [0]).rstrip(),
        btable("door_col", d_col or [0]).rstrip(),
        btable("door_edges", d_edge or [0]).rstrip(),
        btable("door_evert", d_evert or [0]).rstrip(),
        "",
    ]
    OUT.write_text("\n".join(parts), encoding="utf-8")
    n_custom = sum(1 for n in nv if n)
    print(f"Wrote {OUT.relative_to(ROOT)}: backpack + {n_custom} custom type meshes + {len(DOOR_MESH_KEY)} door meshes")


if __name__ == "__main__":
    main()
