# Quake64

A Commodore 64 *Quake* demake: a 3D line-drawn world in custom character graphics, with portal rooms, stick-figure enemies, and sprite weapons.

The playable binary is `quake64.d64` (download from the repo). Autostart it in VICE. A hires menu boots into **E1M1**. The layout is in: doors, ramps, elevators, switches, pickups, and combat.

## Display

The 3D view is a **192×128** custom-charset window (24×16 tiles), double-buffered in VIC Bank 3 (`$C000–$FFFF`). A raster IRQ at the mid-window split (`$D018`) switches between two 256-tile charsets.

Each frame **wipes the live 24 charset columns** (~16.6k cycles). Dirty-tile tracking was dropped: the bookkeeping slowed the line plotter, and the savings only showed up in sparse frames. Lines are Mike’s 8×-unrolled Bresenham from Denial (cached column pointer, immediate bit masks), with special cases for verticals and the y=64 charset join.

The HUD contains title, map name, shells / nails / grenades, health, armour, and a powerup icon. Pickup names and trigger messages flash on a status line. Frame time in ms can sit on row 0 for now. The viewport sits at the bottom  with per-room sky, line, and weapon colours.

## World

The map is **rooms as axis-aligned hulls**, not a global mesh. Floor plans can be a box or a tetromino (**T / L / S**, including a proper S dogleg). Collision is 8-bit tests against the room’s collider boxes. Closed doors are blocking planes; open doors are walk-throughs that switch the active room. Silver and gold keys unlock matching doors. Only the current room is drawn — doorways do not punch a view into the next one.

Ramps use the AABB for **rise/run** (`height = slope_y + (local * sy) / run` in 8.8) so the eye rides the slope. Elevators, switches, and crates share the same box tests. Step off a ledge and you fall; a hard landing costs health.

Walk-over **backpacks** grant ammo, weapons, health, armour, keys, and the exclusive powerups (quad / pentagram / ring). Killed enemies can drop a pack. Message, hurt, teleport, and elevator **triggers** are undrawn AABBs; end-of-level advances `e1mN` or returns to the menu endings.

Off-screen **items** (AABB meshes) and **enemies** skip rotate/project/draw. Horizontal and vertical tests use a fat 45° cone (`|axis| ≤ z` plus a size pad) so the miss is drawing something a bit off-screen, not dropping something that is still in the 192×128 view. The active room’s bounding lines are not frustum-culled.

There’s an editor for maps (Unity-style orbit in the viewport), item meshes, weapon sprites, and enemy animations retargeted from the original MDLs.

## Entities

Enemies are **13 vertices / 13 lines** on a shared skeleton (Grunt, Knight, Rottweiler, Scrag, Ogre, Shambler, Chthon, Zombie). Poses live in local space as signed offsets from the creature base. All animations are imported from the original data by retargeting the vertex animation to the skeleton. A few KB of poses per type, plus one line layout.

They run a room-scoped state machine (idle / patrol / alert / approach / attack / pain / death). Grunt and Rottweiler behaviour is in; the others still share the skeleton and clips. E1M1 places Grunts and a rottweiler.

Yaw is rolled(!) into the world rotation to avoid a double rotate. Perspective and rotation use 8-bit **log / antilog LUTs** (`alog(log|x| + log|cos θ|)`).

**Axe** is melee. **Super shotgun** is a hitscan with range falloff, blood on a hit and a wall splat on a miss. **Nailgun** is a tighter hitscan (smaller cone, lower damage, same LOS / splat path). **Grenade launcher** throws a bouncing grenade (player and ogre) with splash damage. The blast is a half-dome of charset pixels: six unique directions, the other three quadrants filled with 90° Y rotates.

The player weapon is **four hardware sprites** in a 2×2 grid, plus extra sprites for muzzle flash, enemy muzzle, and impact splat. Unplotted sprite pixels stay transparent so world lines show through the gun; bob and recoil are sprite x,y offsets.

SFX are PC-speaker envelopes on all three SID voices (player / enemy / world).

## Build

6502 (ACME) plus Python table generators. Copy `setup-env.example.bat` to `setup-env.bat` and point `ACME` / `VICE` at your installs.

```bat
build.bat          :: generate listings, assemble PRGs, write quake64.d64
make.bat           :: build and autostart quake64.d64 in VICE
run-editor.bat     :: local map / skeleton / item editor
```

Keys: **WASD** move / strafe, **J/L** turn, **K** use, **SPACE** fire, **1–4** axe / shotgun / nailgun / grenade launcher. Enable the mouse in Options to turn and shoot from port 1.

