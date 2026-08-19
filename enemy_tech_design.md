Enemies will all be 13 verts/13 lines with exactly the same skeleton layout, just different proportions and poses. Vertex 12 is a weapon tip parented to the right wrist (Grunt rifle, Knight sword, Ogre chainsaw; others use the same slot).

Animation poses are authored in the editor from shareware Quake MDLs: bind mesh verts to the 13 stick joints, then **Copy all frames**. Each character keeps its own Quake clip set (stand, walk/prowl/fly, run, attacks, etc.) with **only the first pain and first death** variant; extra pain/death clips are dropped.

Poses are stored as variable-length frame arrays plus a per-enemy `clips` table (`name`, `start`, `len`). Animation frames are defined in local space, with signed byte offsets from the base of the creature. Overlay scale defaults to **0.7**.

With 45° baked rotation tables, budget is roughly **65 bytes per pose** (13×3 + 13×2 for gx45/gz45). Typical kept clip counts land around 54–97 poses per character (~3.5–6.3 KB).

The C64 ROM still exports a short **4-frame walk loop** per type (`tools/genenemies.py` looks up the `prowl` clip for Grunt, `walk` for most others, `fly` for Scrag). Full clip export to binary is a later step.

Each level will have 3 enemy types selected from Grunt, Knight, Rottweiler, Scrag, Ogre, Shambler, Chthon.
