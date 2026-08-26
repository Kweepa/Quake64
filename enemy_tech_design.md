Enemies will all be 13 verts/13 lines with exactly the same skeleton layout, just different proportions and poses. Vertex 12 is a weapon tip parented to the right wrist (Grunt rifle, Knight sword, Ogre chainsaw; others use the same slot).

Animation poses are authored in the editor from shareware Quake MDLs: bind mesh verts to the 13 stick joints, then **Copy selected frames**. The Animation tab previews every original MDL clip; checkboxes choose which clips to copy. Defaults keep the first pain and first death variant (extra `painb` / `deathb` clips start unchecked). In-game pain and death each pick at random among whatever matching clips were exported.

Poses are stored as variable-length frame arrays plus a per-enemy `clips` table (`name`, `start`, `len`). Animation frames are defined in local space, with signed byte offsets from the base of the creature. Overlay scale defaults to **0.7**.

With 45° baked rotation tables, budget is roughly **65 bytes per pose** (13×3 + 13×2 for gx45/gz45). Typical kept clip counts land around 54–97 poses per character (~3.5–6.3 KB).

`tools/genenemies.py` writes the full Grunt and Rottweiler clip sets into `src/enemy_data.asm`. Role windows (stand / alert / walk / attack / …) are looked up by clip name. Pain and death are per-type variant tables (`PAIN_MAX` slots); AI rolls among `enemy_pain_n` / `enemy_death_n` exported clips.

Each level will have 3 enemy types selected from Grunt, Knight, Rottweiler, Scrag, Ogre, Shambler, Chthon, Zombie.
