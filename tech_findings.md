# Tech findings

Runtime lessons. Prefer these over re-deriving the same dead ends.

## ACME conditionals

`!if !FLAG` is **not** “if flag is off.” ACME `!` is bitwise NOT, so `!1` is `$FE` (non-zero) and the block **always assembles**. Gate call sites with `!if FLAG { jsr ... }` instead of inverting the flag inside the routine.

## Door / room floor alignment

Door verts are one coplanar face (constant X or Z), not an 8-corner box. The BL–TR triangle split is correct. On E1M1 start the door BL sits on room edge 2–3 (far floor, `y=104`, `z=123`). A visible gap there is a **projection/clip** bug, not a mesh bug.

**Do not** lerp door verts onto the room’s face corners in view or screen space. That needs a perspective-correct parameter, and doors are not always on a wall edge.

Rotate error (`smul16_7`) is ~0. Log `persp88` vs an exact divide is ~1 px. Neither explains an 8–12 px floor gap.

### What actually caused the gap

A near-clipped room corner has large view X/Y at `z = ZCLIP` (1.0). Clamping that projection to **±127** (`PERSP_MAX`) before Cohen–Sutherland bends the 2D line. The door BL is in front of the near plane, so it projects correctly and sits **off** the bent wall.

3D-colinear points stay 2D-colinear only if **both** endpoints use the true perspective (`x * FOCAL / z`) with enough range for CS to hit the real screen edge.

**Do now:** 16-bit `(x * FOCAL) / z` via `scale_nd` + `lerp16` (`.p16`). No ±127 clamp. CS uses the same 16-bit lerp.

### Near-plane lerp — what not to do

`.nlrun` must keep **y 16-bit** and shrink only **n and d** to signed 8-bit (`scale_nd`), then `lerp16`. That is `(y * n) / d` with the ratio preserved.

**Do not** use `scale3` (ASR y, n, **and** d) and then left-shift the quotient. `scale3` already shrinks all three, so `(y>>k)*(n>>k)/(d>>k) = (y*n)/(d<<k)`. Shifting the result back overshoots and yanks clipped endpoints across the viewport (skewed door uprights, walls off course).

`div24u8` saturates only if the **quotient** does not fit in 16 bits (`rot2 ≠ 0` after 24 shifts). A product like `3647×51` is fine; a broken shift-direction sim of `div24u8` will lie about saturation.

### Screen clip lerp — what not to do

**Do not** `scale3` + 8-bit `lerpdv` (±127) for CS. Same 2^k undershoot on long lines (near-clipped endpoints with large |ox|). Use `scale_nd` + `lerp16` and add the 16-bit delta. `lerp16` clobbers `rot0/rot1/rot2` and X — save the clip plane and endpoint index first.

## VICE dumps

End of draw is after `jsr draw_enemies` in `main` (`lda #$35` / `sta $01`). `$01` must be `$34` to see RAM under I/O. A dump taken mid-`stroke_mesh` is a mix of the current mesh and leftover slots — capture after the frame, not during room draw.

Do not treat `ent_wx/wy/wz` after `fill_door_verts` as door BL; those are the last vert (v5).
