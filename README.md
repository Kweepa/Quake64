# Quake64

A Commodore 64 *Quake* demake: a 3D line-drawn world in custom character graphics, with portal rooms, stick-figure monsters, and a hardware-sprite view-model.

This is an early prototype. The running program is the **core line engine** — a double-buffered Bresenham cube in VIC Bank 3 — plus a HUD font and frame profiler. Portal maps, enemies, and weapons are designed but not in the binary yet.

## Display

The 3D view is a **192×128** custom-charset window (24×16 tiles), double-buffered in VIC Bank 3 (`$C000–$FFFF`). A raster IRQ at the mid-window split (`$D018`) switches between two 256-tile charsets so the viewport can use **512 unique glyphs**. Buffer flips only retarget screen and charset pointers, so the visible frame never gets drawn into.

Each frame **wipes the live 24 charset columns** (~16.6k cycles). Dirty-tile tracking was dropped: the bookkeeping slowed the line plotter, and the savings only showed up in sparse frames. Background is brown; world lines are orange; the HUD strip below the split is black with dark-red / orange Quake-style type.

## World (design)

The map is **rooms as axis-aligned boxes**, not a global mesh. Collision is 8-bit bounds against the active room. Closed doors are blocking planes; open doors are portals that reveal the next room index.

Elevation is locked to **1:2 ramps** (`height = local_x >> 1`) so slopes never need multiply or divide. Elevators, switches, and crates share the same box tests.

## Entities (design)

Monsters are **12 vertices / 12 lines** on a shared skeleton (Grunt, Knight, Rottweiler, Scrag, Ogre, Shambler, Chthon — three types per level). Poses live in local space as signed offsets from the creature base: idle, alert, walk, three attacks, flinch, death (**24 frames**). About **2 KB** per enemy plus one line layout.

Yaw is cheap at runtime: a **45°** pose is **pre-rotated into tables**; the other six views are coord flips and sign changes. Perspective and remaining rotation use 8-bit **log / antilog LUTs** (`alog(log|x| + log|cos θ|)`). Nails are point traces clipped to the current room.

The view-model is **four hardware sprites** in a 2×2 grid. Unplotted sprite pixels stay transparent so world lines show through the gun; bob and recoil are sprite Y/X offsets.

## Build

6502 (ACME) plus Python table generators. Copy `setup-env.example.bat` to `setup-env.bat` and point `ACME` / `VICE` at your installs.

```bat
build.bat          :: generate tables, assemble quake64.prg
make.bat           :: build and autostart in VICE
run-editor.bat     :: local map / skeleton editor
```

Keys in the current cube demo: **J** / **L** yaw.
