# Editor notes

## Names
* Maps keep the Quake episode keys **E1M1 … E1M8** as the real identity (tabs, save file, game export).
* The editor can still give each map a **display name** (e.g. "Slipgate Complex") shown in the UI next to the key.
* Rooms can have display names too. Names are for authors; the game addresses rooms by index.

## Object tree
* The Objects panel is a **shallow collapsible tree**: each **room** is a parent, the objects that sit in that room are its children.
* Same grouping the game uses: a room owns its crates, elevators, switches, triggers, destinations, keys, enemies, spawn, backpacks. **Doors appear under every room they overlap.**
* Flat object lists are an authoring hazard; don't flatten for the game binary either.
* List labels are **type only** (e.g. "Crate", "Trigger") — no XYZ in the name. Rooms may show their display name.
* Non-room labels that would wrap stay on **one line** and elide with an ellipsis (`…`). Room names may wrap.

## Tags (editor) → indices (game)
* Shared **tag** strings in the editor link controllers to targets (switch ↔ elevator, trigger ↔ elevator/dest, door ↔ key).
* Export resolves tags to **indices**. The 6502 side never stores or compares tag strings.

## Locked doors
* A door can be marked **locked** and given a **key** requirement (same tag/index idea: named key in the editor, key index in the game).
* Place **key** pickups in the tree like other room objects. Until the player holds that key, the door stays a blocking plane.

## Triggers
* One placeable **trigger** volume (undrawn AABB; editor shows it dashed / ghosted).
* Inspector has a **purpose** dropdown, then fields that depend on it. Purposes:
  * **Display message** — one-line HUD text while the player is inside (text field; no tag).
  * **End of level** — fires once on entry; no HUD. Level transitions come later.
  * **Hurt player** — 10% health on enter, then every 2 seconds while inside (no tag).
  * **Teleport** — destination **tag** targets a **teleport dest**; stepping in warps to that pose (including another room).
  * **Activate elevator** — destination **tag** targets an elevator; fires on entry if that elevator is not busy.
* There is no separate teleporter entry object — teleport entry is a trigger with purpose **Teleport**.
* **Teleport dest** stays its own placeable (exit point + facing + tag). The dest object's room is the arrival room. Editor marks the dest; the game does not draw it.

## Patrol
* Enemies have a **Patrol** checkbox. When set, an idle enemy picks a random cardinal, walks at least 6 units if that ray is clear of walls, then idles 1–2 seconds and repeats. Failed rays stay idle and retry next frame.
* There are no placeable patrol-point markers.
