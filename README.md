# Quake64

A Commodore 64 *Quake* demake: a 3D line-drawn world in custom character graphics, with portal rooms, stick-figure enemies, and sprite weapons.

This is an early prototype. The running program is the **core line engine** — a double-buffered Bresenham line drawn world in VIC Bank 3 — plus a HUD font, frame profiler, and sprite weapons (axe, super shotgun, nailgun, grenade launcher).

## Display

The 3D view is a **192×128** custom-charset window (24×16 tiles), double-buffered in VIC Bank 3 (`$C000–$FFFF`). A raster IRQ at the mid-window split (`$D018`) switches between two 256-tile charsets so the viewport can use **512 unique glyphs**. Buffer flips only retarget screen and charset pointers, so the visible frame never gets drawn into.

Each frame **wipes the live 24 charset columns** (~16.6k cycles). Dirty-tile tracking was dropped: the bookkeeping slowed the line plotter, and the savings only showed up in sparse frames. The HUD occupies the full-width rows above the 3D viewport (black, dark-red labels / orange digits): title, map name, ammo, health, and armour. The viewport sits at the bottom (brown sky, orange world lines).

## World (design)

The map is **rooms as axis-aligned boxes**, not a global mesh. Collision is 8-bit bounds against the active room. Closed doors are blocking planes; open doors are portals that reveal the next room index. I might extend the room boxes to arbitrary meshes, chosen to make collision easy and to give the levels maximum variety. For example, T junctions, L hallways.

Elevation is locked to **1:2 ramps** (`height = local_x >> 1`) so slopes never need multiply or divide. Elevators, switches, and crates share the same box tests.

Off-screen **items** (AABB meshes) and **enemies** skip rotate/project/draw. Horizontal and vertical tests use a fat 45° cone (`|axis| ≤ z` plus a size pad) so the miss is drawing something a bit off-screen, not dropping something that is still in the 192×128 view. The active room's bounding lines are not frustum-culled.

There's an editor that can be used to put together levels. I also used it to export weapon sprites and enemy animations.

## Entities (design)

Enemies are **13 vertices / 13 lines** on a shared skeleton (Grunt, Knight, Rottweiler, Scrag, Ogre, Shambler, Chthon - three types per level). Poses live in local space as signed offsets from the creature base. All animations are imported from the original data by retargeting the vertex animation to the skeleton. About **2 KB** per enemy plus one line layout.

Yaw is rolled(!) into the world rotation to avoid a double rotate. Perspective and rotation use 8-bit **log / antilog LUTs** (`alog(log|x| + log|cos θ|)`). Nails are raycasts whose results are delayed a frame or two.

The view-model is **four hardware sprites** in a 2×2 grid. Unplotted sprite pixels stay transparent so world lines show through the gun; bob and recoil are sprite x,y offsets.

## Build

6502 (ACME) plus Python table generators. Copy `setup-env.example.bat` to `setup-env.bat` and point `ACME` / `VICE` at your installs.

```bat
build.bat          :: generate tables, assemble quake64.prg
make.bat           :: build and autostart in VICE
run-editor.bat     :: local map / skeleton editor
```

Keys in the current E1M1 demo: **WASD** move / strafe, **J/L** turn, **K** use, **SPACE** fire, **1–4** axe / shotgun / nailgun / grenade launcher. Stick-figure Grunt / Rottweiler are in room 2 and beyond.