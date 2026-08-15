# Commodore 64 Quake Demake Engine Architecture
*Extracted Architecture Blueprint & Technical Discussions*

---

## 1. Core Technical Specifications & Performance Boundaries

### Viewport Layout & Display Engine
* **Resolution:** 256 × 128 pixels centered viewport.
* **Screen Space:** Occupies 32 × 16 text character tiles, taking up approximately 80% horizontal and 64% vertical space.
* **Drive Mechanism:** Custom Character Graphics Mode utilizing 512 unique custom characters divided into two sets of 256 tiles via a mid-viewport raster split.
* **Double Buffering:** Implemented within VIC Bank 3 (`$C000–$FFFF`). Buffer swaps change register `$D018` pointers instantly, allowing an active background drawing buffer with absolute zero screen-space rendering flicker.

### Performance & Buffer Manipulation
* **Traditional Clear Cost:** ~17,664 CPU cycles (consuming ~90% of a standard PAL frame's processing budget).
* **The "Lazy Erase" List Strategy:** The engine records modified Tile IDs to a localized "Dirty List" array during active 3D line plotting. The clear phase only erases touched tiles, reducing cycles to ~1,400 per frame. This reclaims ~83% of the CPU budget for geometry projection.

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
* **Data Definition:** The game map is discretized into an array of isolated bounding boxes rather than an expansive global coordinate layout.
* **Local Boundaries:** Movement algorithms isolate collision checking explicitly to the dimensions of the player's active room index block using 8-bit `CMP` bounds operations.
* **State Gates (Doors):** Doors operate as structural bounding boxes. In a closed state, they map as standard blocking planes. When triggered open, they function as dynamic gateway portals. They reveal adjacent room indices to the camera's sight-cone and allow physical entity transition.

### Axis-Aligned Mechanical Elements
* **Standard 1:2 Ramps:** Elevation geometry is locked to a fixed 1:2 gradient ratio. Height changes are computed instantly without real-time division or multiplication using arithmetic bitwise shifts: `Height = (Local_Position) >> 1`.
* **Dynamic Interactive Elements:** Elevators (translating Y-axis base planes), switches (proximity check targets), and crates (solid vertical obstacle boxes) utilize a singular uniform bounding-box logic routine, allowing multi-object processing under a unified assembly subroutine loops.

---

## 4. Entity Rendering & Animation Pipelines

### Arbitrary 3D Stick Figures
* **Structural Assembly:** Enemies are built from 10–12 vector lines using a target budget of 8–10 vertices per model frame. Animations span a 12-frame asset allocation footprint (e.g., 4 walk, 2 attack, 2 death, 1 flinch frames) costing only 480 bytes per character type.
* **Fixed-Point Rotation Matrix Simulation:** To calculate arbitrary 3D rotation, the engine sidesteps native multiplication loops. 8-bit Log and Anti-log lookup tables evaluate vector transformations via fast addition: `AntiLog(Log(|X|) + Log(|cos(θ)|))`.
* **Generational Advancements:** Employs true multi-axis 3D coordinates allowing authentic vertical view-pitch controls (looking up/down smoothly), room-over-room overlapping map geometries, and complex, cascading 3D ragdoll spin trajectories on dead or tumbling entities.

### Projectiles (Nine Inch Nails)
* **Collision Routine:** Tracked as single-point vectors shifting through active local spaces.
* **Spatial Optimization:** Nails filter impact checks exclusively inside the current room's boundary array, preventing multi-sector traversal parsing bottlenecks and using fast structural wall/box containment tests.

---

## 5. Visual Aesthetics, Palette & Hardware Weapon Display

### Viewport Tone & Contrast Map
* **3D Sandbox Space:** Screen background is explicitly assigned to **VIC Color 11 (Dark Grey)** or **Color 9 (Brown)**, drawing white or light grey vector lines. This breaks from traditional neon/dark retro game tones to evoke *Quake's* oppressive, industrial dark-fantasy space.
* **HUD Dashboard Split:** The mid-screen raster split forces the bottom text display area into **Color 0 (Black)** with text and asset gauges drawn in **Color 2 (Dark Red)** and **Color 8 (Orange)** to replicate the original stone-carved HUD layout.

### Hardware Sprite View-Model
* **Zero-Overhead Weapon:** The player's weapon is structured out of **4 multiplexed hardware sprites** configured in a 2×2 grid (extending to a 48×42 canvas or 96×42 layout via horizontal hardware scaling).
* **Negative Space Illusion:** Interior weapon boundaries are left unplotted/transparent within the sprite asset structure. This ensures background world-lines naturally show through the weapon assembly, providing a perfect transparent wireframe aesthetic.
* **Kinematics:** Simple coordinate shifts on sprite positioning variables drive satisfying view-bobbing calculations and explosive vertical recoil offsets.