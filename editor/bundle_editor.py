#!/usr/bin/env python3
"""Bundle the editor into a single self-contained HTML file (no server)."""

from __future__ import annotations

import base64
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "index.html"

JS_ORDER = [
    "js/model.js",
    "js/math3d.js",
    "js/io.js",
    "js/layoutView.js",
    "js/overheadView.js",
    "js/animView.js",
    "js/main.js",
]


def strip_module(src: str) -> str:
    src = re.sub(r"^import\s[\s\S]*?;\s*\n", "", src, flags=re.M)
    lines = []
    for line in src.splitlines():
        line = re.sub(r"^export\s+default\s+", "", line)
        line = re.sub(r"^export\s+", "", line)
        lines.append(line)
    return "\n".join(lines)


def main() -> None:
    css = (ROOT / "styles.css").read_text(encoding="utf-8")
    parts = []
    for rel in JS_ORDER:
        raw = (ROOT / rel).read_text(encoding="utf-8")
        parts.append(f"// ---- {rel} ----\n{strip_module(raw)}")
    js = "\n\n".join(parts)

    icon_path = ROOT / "icon.png"
    favicon_link = ""
    if icon_path.exists():
        b64 = base64.b64encode(icon_path.read_bytes()).decode("ascii")
        favicon_link = f'  <link rel="icon" type="image/png" href="data:image/png;base64,{b64}" />\n'

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Quake64 Editor</title>
{favicon_link}  <style>
{css}
  </style>
</head>
<body>
  <header class="toolbar">
    <h1>Quake64</h1>
    <div class="toolbar-actions" role="group" aria-label="Editor mode">
      <button type="button" id="btn-mode-layout" class="active">Layout</button>
      <button type="button" id="btn-mode-anim">Animation</button>
    </div>
    <div class="toolbar-actions" id="draw-mode-group" role="group" aria-label="Draw mode">
      <button type="button" id="btn-draw-all" class="active">All</button>
      <button type="button" id="btn-draw-local">Local</button>
    </div>
    <div class="toolbar-actions">
      <button type="button" id="btn-undo" title="Ctrl+Z" disabled>Undo</button>
      <button type="button" id="btn-redo" title="Ctrl+Y" disabled>Redo</button>
      <button type="button" id="btn-save">Save</button>
      <button type="button" id="btn-load">Load</button>
    </div>
    <p id="status" class="status" role="status"></p>
  </header>

  <main class="layout">
    <aside class="left">
      <section id="layout-left">
        <section id="level-list"></section>
        <h2>Place</h2>
        <div id="item-palette" class="item-palette"></div>
        <h2>Objects</h2>
        <ul id="object-list" class="object-list"></ul>
      </section>
      <section id="anim-left" hidden>
        <h2>Enemies</h2>
        <ul id="enemy-list" class="object-list"></ul>
      </section>
    </aside>

    <section class="center">
      <h2 id="center-title">Map</h2>
      <div class="map-stage" id="map-stage">
        <canvas id="view-canvas" tabindex="0"></canvas>
      </div>
      <p class="hint" id="hint"></p>
    </section>

    <aside class="right">
      <div class="right-editors" id="right-editors"></div>
      <div id="overhead-panel" class="preview-panel panel">
        <div class="toolbar-actions ortho-tabs" role="group" aria-label="Ortho view">
          <button type="button" id="btn-ortho-top" class="active">Top</button>
          <button type="button" id="btn-ortho-left">Left</button>
          <button type="button" id="btn-ortho-forward">Forward</button>
        </div>
        <div class="preview-frame">
          <canvas id="overhead-canvas"></canvas>
        </div>
        <p class="muted" id="ortho-hint">XZ · +Z up · camera arrow</p>
      </div>
    </aside>
  </main>

  <script>
{js}
  </script>
</body>
</html>
"""
    OUT.write_text(html, encoding="utf-8")
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
