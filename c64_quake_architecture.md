# Commodore 64 Quake Demake Engine Architecture
*Extracted Architecture Blueprint & Technical Discussions*

---

## 1. Core Technical Specifications & Performance Boundaries

### Viewport Layout & Display Engine
* **Resolution:** 256 × 128 pixels (prototype currently 192 × 128).
* **Screen Space:** Occupies 32 × 16 text character tiles. The **3D viewport sits at the bottom of the screen**; the **HUD occupies the rows above it**. Weapon sprites overlay the bottom of the viewport, not the HUD.
* **Drive Mechanism:** Custom Character Graphics Mode utilizing 512 unique custom characters divided into two sets of 256 tiles via a mid-viewport raster split.
* **Raster Timing:** Raster IRQs must land on the intended scanlines (HUD → viewport boundary, mid-viewport charset flip). The current chain is late / jittery; stabilize so `$D018` / `$D021` switches hit the exact raster lines rather than drifting a few lines into the next character row.
* **Double Buffering:** Implemented within VIC Bank 3 (`$C000–$FFFF`). Buffer swaps change register `$D018` pointers instantly, allowing an active background drawing buffer with absolute zero screen-space rendering flicker.

### Performance & Buffer Manipulation
* **Traditional Clear Cost:** ~17,664 CPU cycles (consuming ~90% of a standard PAL frame's processing budget).
* **The "Lazy Erase" List Strategy:** The engine records modified Tile IDs to a localized "Dirty List" array during active 3D line plotting. However, this severely slows down line rendering and in the worst case isn't much faster to clear than a full unrolled clear.

---

## 2. Memory Map Layout (VIC Bank 3)

| Memory Address | Size | Allocation / Usage |
| :--- | :--- | :--- |
| **`$C000` – `$C3E7`** | 1,000 bytes | **Screen RAM Buffer A** (Defines top viewport construction layout) |
| **`$C400` – `$C7E7`** | 1,000 bytes | **Screen RAM Buffer B** (Defines alternate viewport layout) |
| **`$C800` – `$CFFF`** | 2,000 bytes | **Main Code Space** (Engine execution & game logic) |
| **`$D000` – `$D7FF`** | 2,000 bytes | **Buffer A: Top Half Charset** (256 tiles × 8 bytes) |
| **`$D800` – `$DFFF`** | 2,000 bytes | **Buffer A: Bottom Half Charset** (256 tiles × 8 bytes) |
| **`$E000` – `$E7FF`** | 2,000 bytes | **Buffer B: Top Half Charset** (256 tiles × 8 bytes) |
| **`$E800` – `$EFFF`** | 2,000 bytes | **Buffer B: Bottom Half Charset** (256 tiles × 8 bytes) |
| **`$F000` – `$F7FF`** | 2,000 bytes | **UI Character Set** (Dedicated HUD/Dashboard font & borders) |
| **`$F800` – `$FFFF`** | 2,000 bytes | **Free Memory & Look-Up Tables (LUTs)** (Log/Anti-log multiplication data) |

*Note: Access to pure RAM under `$D000–$FFFF` requires unmapping the KERNAL ROM via the CPU processor port register (`$01`).*

---

## 3. World Architecture & Physics Mechanics

### The Portal-Room Framework
* **Data Definition:** The game map is discretized into an array of isolated bounding boxes rather than an expansive global coordinate layout. Runtime data is **room-first**: each room owns the objects that sit inside it (crates, elevators, switches, triggers, destinations, keys, enemies, spawn). Same grouping the editor tree uses.
* **One Room Visible:** Only the room the player is in is drawn. Adjacent rooms are not projected through doorways. When the player crosses a **door threshold**, switch the active room index and start drawing that room instead.
* **Local Boundaries:** Movement algorithms isolate collision checking explicitly to the dimensions of the player's active room index block using 8-bit `CMP` bounds operations.
* **State Gates (Doors):** Doors operate as structural bounding boxes. In a closed state, they map as standard blocking planes. When open they allow physical entity transition; they do not punch a view into the next room. A door may be **locked** and stay closed until the player has the matching **key**. After unlock it behaves as a normal open/close door.
* **Triggers:** Undrawn AABBs with a **purpose** (message, open door, operate elevator, teleporter). Message shows one HUD line while inside. Other purposes fire via a **tag** → index link to the target. Teleport entry is a trigger purpose, not a separate object type; destination is a tagged exit pose.

### View (Yaw Only)
* The projector is **yaw-only**. View Y is `world_y − cam_yh` (no pitch shear, no extra pitch trig per vertex). Look-up/down was dropped so AABB uprights stay screen-vertical.
* Viewport is **192×128**, `FOCAL=100`: a point is on-screen if `|x|/z ≤ 96/100` and `|y|/z ≤ 64/100` (about **44°** / **33°** half-angles).

### View Frustum Cull (Items and Enemies)
* **Cheap over exact.** Fail-open: drawing something a bit off-screen is OK; skipping something that still has pixels in the viewport is not. Tests use a **45°** cone `|axis| ≤ z` (fatter than both FOVs) plus a size pad.
* **Items** (crates, doors, switches, elevators, slopes, platforms): `frustum_hits` runs **Y first** (no muls), then the three inward XZ planes (left / right / front). Active room is interior-culled only — not frustum-culled.
  * Y: reject only if the **whole** AABB is above or below the cone. `y_lo = box_y − cam_yh`, `y_hi = y_lo + box_sy`. Eye-height overlap (`y_lo ≤ 0 ≤ y_hi`) always keeps. Otherwise compare `|y|` to Chebyshev XZ of the four box corners vs the camera, plus `ITEM_CULL_Y` (2). Use the **farthest** corner (max of the four `|Δ|`), not the nearest.
  * XZ: supporting-vertex dots against yaw±`FOV_HALF` inward normals; keep unless the box is fully outside any plane.
* **Enemies:** one origin transform, then `enemy_in_view`: `z ≥ 0`, `|x| ≤ z+ENEMY_CULL_R` (2), `|y| ≤ z+ENEMY_CULL_H` (6, figure height). Miss skips rotate/project/draw. Same-floor figures almost always pass Y; the win is stacked floors in a tall room.

### Axis-Aligned Mechanical Elements
* **Standard 1:2 Ramps:** Elevation geometry is locked to a fixed 1:2 gradient ratio. Height changes are computed instantly without real-time division or multiplication using arithmetic bitwise shifts: `Height = (Local_Position) >> 1`.
* **Dynamic Interactive Elements:** Elevators (translating Y-axis base planes), switches (proximity check targets), and crates (solid vertical obstacle boxes) utilize a singular uniform bounding-box logic routine, allowing multi-object processing under a unified assembly subroutine loops.
* **Switch → Elevator:** In the editor, a switch is bound to its elevator(s) by a **tag** string. Export compiles tags to **indices** (switch *n* toggles elevator *m*). The game never stores or compares tag strings. Same tag/index pattern as trigger purposes.
* **Message Triggers:** Covered by trigger purpose **message** — undrawn AABB, one HUD line while the player is inside.

### Cuboid Hidden Surface / Hidden Line Removal
* Rooms, crates, and elevators are convex axis-aligned boxes. Use **back-face culling**, then drop any edge that is not on a visible face.
* **Outside** (crate, elevator): keep faces whose outward normal points toward the camera (at most three faces).
* **Inside** (room): invert the test — keep the interior faces the camera looks at.
* Shared edges of two culled faces are never stroked. No painter's algorithm; convexity makes the visible silhouette enough.

### Motion Motes
* When the view contains no world edges (blank wall, empty volume), camera motion is invisible. Scatter **5–6 single-pixel motes** in a volume around the player so parallax still reads as movement. Cheap plot, not sprites.

---

## 4. Entity Rendering & Animation Pipelines

### Arbitrary 3D Stick Figures
* **Structural Assembly:** Enemies are built from 10–12 vector lines using a target budget of 8–10 vertices per model frame. Animations span a 12-frame asset allocation footprint (e.g., 4 walk, 2 attack, 2 death, 1 flinch frames) costing only 480 bytes per character type.
* **Fixed-Point Rotation Matrix Simulation:** To calculate arbitrary 3D rotation, the engine sidesteps native multiplication loops. 8-bit Log and Anti-log lookup tables evaluate vector transformations via fast addition: `AntiLog(Log(|X|) + Log(|cos(θ)|))`.
* **Generational Advancements:** Employs true multi-axis 3D coordinates allowing room-over-room overlapping map geometries, and complex, cascading 3D ragdoll spin trajectories on dead or tumbling entities. Player view stays yaw-only (no pitch rotate).

### Projectiles (Nine Inch Nails)
* **Collision Routine:** Tracked as single-point vectors shifting through active local spaces.
* **Spatial Optimization:** Nails filter impact checks exclusively inside the current room's boundary array, preventing multi-sector traversal parsing bottlenecks and using fast structural wall/box containment tests.

---

## 5. Visual Aesthetics, Palette & Hardware Weapon Display

### Viewport Tone & Contrast Map
* **3D Sandbox Space:** Screen background is explicitly assigned to **VIC Color 11 (Dark Grey)** or **Color 9 (Brown)**, drawing white or light grey vector lines. This breaks from traditional neon/dark retro game tones to evoke *Quake's* oppressive, industrial dark-fantasy space.
* **HUD Dashboard Split:** The HUD lives in the **rows above the 3D viewport**. Raster-switch that band to **Color 0 (Black)** with gauges in **Color 2 (Dark Red)** and **Color 8 (Orange)** to replicate the original stone-carved HUD. The viewport band stays brown / dark grey. Trigger messages occupy **one HUD line** while the player is inside the volume.

### Hardware Sprite View-Model
* **Zero-Overhead Weapon:** The player's weapon is structured out of **4 multiplexed hardware sprites** configured in a 2×2 grid (extending to a 48×42 canvas or 96×42 layout via horizontal hardware scaling).
* **Negative Space Illusion:** Interior weapon boundaries are left unplotted/transparent within the sprite asset structure. This ensures background world-lines naturally show through the weapon assembly, providing a perfect transparent wireframe aesthetic.
* **Kinematics:** Simple coordinate shifts on sprite positioning variables drive satisfying view-bobbing calculations and explosive vertical recoil offsets.