# Editor notes

## Names
* Maps keep the Quake episode keys **E1M1 … E1M8** as the real identity (tabs, save file, game export).
* The editor can still give each map a **display name** (e.g. "Slipgate Complex") shown in the UI next to the key.
* Rooms can have display names too. Names are for authors; the game addresses rooms by index.

## Object tree
* The Objects panel is a **shallow collapsible tree**: each **room** is a parent, the objects that sit in that room are its children.
* Same grouping the game uses: a room owns its crates, elevators, switches, triggers, destinations, keys, enemies, spawn, backpacks, patrol points. **Doors appear under every room they overlap.**
* Flat object lists are an authoring hazard; don't flatten for the game binary either.
* List labels are **type only** (e.g. "Crate", "Trigger") — no XYZ in the name. Rooms may show their display name.
* Non-room labels that would wrap stay on **one line** and elide with an ellipsis (`…`). Room names may wrap.

## Tags (editor) → indices (game)
* Shared **tag** strings in the editor link controllers to targets (switch ↔ elevator, trigger ↔ door/elevator/dest, door ↔ key, enemy ↔ patrol points).
* Export resolves tags to **indices**. The 6502 side never stores or compares tag strings.

## Locked doors
* A door can be marked **locked** and given a **key** requirement (same tag/index idea: named key in the editor, key index in the game).
* Place **key** pickups in the tree like other room objects. Until the player holds that key, the door stays a blocking plane.

## Triggers
* One placeable **trigger** volume (undrawn AABB; editor shows it dashed / ghosted).
* Inspector has a **purpose** dropdown, then fields that depend on it. Purposes:
  * **message** — one-line HUD text while the player is inside (text field; no tag).
  * **open door** — tag targets the door(s) to open.
  * **operate elevator** — tag targets the elevator(s) to run.
  * **teleporter** — tag targets a **teleporter destination**; stepping in warps to that pose.
* There is no separate teleporter object — teleport entry is a trigger with purpose **teleporter**.
* **Teleporter destination** stays its own placeable (exit point + facing). Tag matches the teleporter trigger. Editor marks the dest; game does not draw the dest marker.

## Patrol points
* Placeable **patrol point** markers (ghosted; editor-only until cook/AI land).
* Share a **tag** with an **enemy** to bind a route. Multiple points with the same tag are ordered by the **Order** field (lower first).
* Export will resolve tags → indices; the 6502 side never stores tag strings.
