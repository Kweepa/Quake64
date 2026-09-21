# Memory map

CPU space (`$0000–$BFFF`) is boot, GAME, and the downward heap. VIC bank 3 (`$C000–$FFFF`) is screens, charsets, sprites, LUTs, and play scratch. Source of truth for abs addresses is [`src/mem.asm`](src/mem.asm); zero page is [`src/zp.asm`](src/zp.asm); map SoA pointers are [`src/map_bss.asm`](src/map_bss.asm). GAME module bounds below are from `game.lbl` (KERNAL assemble). Accessing `$D000–$FFFF` as RAM requires `$01` to unmap I/O and the KERNAL. Colour RAM (`$D800`) is the I/O overlay of charset A bottom.

`build.bat` regenerates `memory-report.json` / `memory-report-krill.json` and
`heap-report.json` / `heap-report-krill.json`. Those reports and the build's
1 KiB minimum-slack gate are authoritative; the tables below describe the
latest checked build.

The playable disks are [`quake64.d64`](quake64.d64) (KERNAL `$FFD5`, VICE virtual 1541) and [`quake64-krill.d64`](quake64-krill.d64) (`loadraw`, true drive emulation / real 1541). Both KERNAL-load a split koala cover (`splashc` colour/matrix first, then `splash` bitmap) in VIC bank 1. The Krill disk then installs the resident at `$EE08` before `menu`. The cover uses the menu’s matrix/bitmap (`$5C00` / `$6000`); splashc stages at `$4000` so `MENU` can grow past `$4000` without flashing the picture. `run_menu` switches to hires and wipes it. After the menu, boot stages `tab` into charset tails, then `fnt` / `scr` / `sqt` / `game`.

Caps used by the mesh path: **16 verts**, **32 edges**, **6 unique world X** and **6 unique world Z** (rooms still cook at 4 unique).

## `$0000`–`$BFFF` — CPU, GAME, heap

`$D018` / charsets / LUTs are the bank-3 section below. Heap grows **down** from `$C000`; `heap_alloc` fails when the new top `<= end_game`.

| Address | Size | Use |
| :--- | ---: | :--- |
| `$0000`–`$0001` | 2 | Processor port (`$01` = `BANK_RAM` / `BANK_IO` / `BANK_LOADER`) |
| `$0002`–`$00FF` | 254 | Zero page — [`src/zp.asm`](src/zp.asm) |
| `$0100`–`$01FF` | 256 | Stack |
| `$0200`–`$03FF` | 512 | Mostly free. `MAP_SMC_HI` `$02` is a GAME operand sentinel, not occupancy. Live KERNAL shadows: `$02A1` (CIA2 ICR), `$02A6` (PAL/NTSC), `$0314`/`$0318` (IRQ/NMI vectors, also `$FFFA`) |
| `$0400`–`$051F` | 288 | Map header + SoA pointers (`map_bss.asm`; `bind_map`) |
| `$0524`–`$06F6` | 467 | Play BSS (frame/pose pointers and streamed-SFX state) |
| `$06F7`–`$0875` | 383 | Boot-loaded immutable enemy metadata (`enemydata.prg`) |
| `$0876`–`$0885` | 16 | Streamed AI entry pointers (8 lo + 8 hi) |
| `$0886`–`$0895` | 16 | Fused enemy-bank base pointers (8 lo + 8 hi) |
| `$0896`–`$08F8` | 99 | Free during play |
| `$08F9`–`$08FB` | 3 | `REBOOT_STUB` (`JMP reboot_game`) |
| `$08FC` | 1 | `level_num` |
| `$08FD`–`$08FF` | 3 | `effects_vol` / `game_complete` / `difficulty` (survive GAME load) |
| `$0900`–`$9711` | 36370 | GAME (`end_game` `$9712`). Menu overlay lived here first |
| `$9712`–`$BFFF` | 10478 | Heap (map plus at most two fused AI/pose/SFX banks). Krill GAME is 26 B shorter |

### Play BSS and streamed-bank pointers `$0524+`

| Address | Size | Label |
| :--- | ---: | :--- |
| `$0524`–`$058D` | 106 | `frame13_lo` |
| `$058E`–`$05F7` | 106 | `frame13_hi` |
| `$05F8`–`$0627` | 48 | `enemy_gx/y/z` lo/hi (`ENEMY_PTR_N`=8) |
| `$0628`–`$063F` | 24 | `box_vis_edges` |
| `$0640`–`$064B` | 12 | `box_vis_vert` |
| `$064C`–`$068B` | 64 | `room_pack_edges` |
| `$068C`–`$06AB` | 32 | `room_pack_vert` |
| `$06AC`–`$06B8` | 13 | `pose_gx` |
| `$06B9`–`$06C5` | 13 | `pose_gy` |
| `$06C6`–`$06D2` | 13 | `pose_gz` |
| `$06D3`–`$06DA` | 8 | `pose_map_lo` |
| `$06DB`–`$06E2` | 8 | `pose_map_hi` |
| `$06E3`–`$06F2` | 16 | streamed clip-SFX event pointers |
| `$06F3`–`$06F6` | 4 | clip-SFX animation scratch/latch |
| `$06F7`–`$0875` | 383 | immutable enemy metadata |
| `$0876`–`$0895` | 32 | streamed AI entry and fused-bank pointers |

### GAME `$0900`–`end_game`

Assembled in `!source` order from [`src/quake64.asm`](src/quake64.asm). Bounds
are the zero-byte `mod_*` labels emitted before each source. Krill vs KERNAL
only changes `LoadPrg` inside `loader.asm` (26 B).

| Address | Size | File | Notes |
| :--- | ---: | :--- | :--- |
| `$0900`–`$09CB` | 204 | `quake64.asm` | `start` / `main` |
| `$09CC`–`$0B87` | 444 | `vic.asm` | VIC init, charset clear, `$d018` |
| `$0B88`–`$0EF1` | 874 | `irq.asm` | raster chain, keys |
| `$0EF2`–`$0FCB` | 218 | `profil.asm` | CIA2 cascade (buckets if `PROFILE`) |
| `$0FCC`–`$13D0` | 1029 | `hud.asm` | HUD + pickup strings |
| `$13D1`–`$19D7` | 1543 | `math.asm` | smul / log / persp / `ATAN32` / rnd |
| `$19D8`–`$1CA9` | 722 | `util.asm` | AABB / line-box |
| `$1CAA`–`$26A8` | 2559 | `line.asm` | Bresenham setup + generated unrolled bodies |
| `$26A9`–`$28C8` | 544 | `fx.asm` | explosion particles |
| `$28C9`–`$2EE2` | 1562 | `grenade.asm` | |
| `$2EE3`–`$3138` | 598 | `spit.asm` | |
| `$3139`–`$3376` | 574 | `playsound.asm` | SID mixer |
| `$3377`–`$377A` | 1028 | `pcsounds.asm` | resident PC-speaker envelopes/tables |
| `$377B`–`$387A` | 256 | `pcsfreq.asm` | Fn hi LUT (256) |
| `$387B`–`$404A` | 2000 | `weapon.asm` | |
| `$404B`–`$45FA` | 1456 | `weapon_spr.asm` | packed view-model sprites |
| `$45FB`–`$462E` | 52 | `splat_spr.asm` | |
| `$462F`–`$4676` | 72 | `enemy_muzzle.asm` | |
| `$4677`–`$47BC` | 326 | `process.asm` | door/elev process SoA |
| `$47BD`–`$4998` | 476 | `elevator.asm` | |
| `$4999`–`$4B9B` | 515 | `door.asm` | |
| `$4B9C`–`$5CC7` | 4396 | `world.asm` | move, collision, pickups, triggers |
| `$5CC8`–`$609D` | 982 | `item_mesh.asm` | backpack / door meshes |
| `$609E`–`$6D27` | 3210 | `mesh.asm` | rooms, slopes, world stroke |
| `$6D28`–`$7F2B` | 4612 | `cube.asm` | enemy xform / project / clip / draw |
| `$7F2C`–`$8F28` | 4093 | `enemy.asm` | resident AI core, hitscan, damage |
| `$8F29`–`$9711` | 2025 | `loader.asm` | disk/map load and fused AI/pose/SFX bank relocation |

Largest slices: `cube` 4612, `world` 4396, `enemy` 4093, `mesh` 3210,
`line` 2559, `loader` 2025, `weapon` 2000, `grenade` 1562,
`math` 1543, and `weapon_spr` 1456.

Macros-only (no bytes): `mem.asm`, `zp.asm`, `map_counts.asm`, `mapacc.asm`, `map_bss.asm`, `level_prefix.asm`. `_rotate_body.asm` is inlined in `load_view_trig` (no own label). `overlay.asm` assembles to `overlay.bin` and is prepended to each map.

### Heap `$9712`–`$C000`

Grows down from `SCR_A`. `LoadLevel` one-shots each E1Mn (4-byte header +
PIC overlay + reloc dest words + packed map). `bind_map` copies the 24-byte
header and name, SMC-`jsr`s the overlay (`bind_apply` then `patch_map_smc`),
then `heap_top = map_base` dumps the prefix. At most `ROOM_MAX_TYPES` (2)
fused enemy banks are then resident for the current room. Play peak is packed
map plus the worst room's banks; load peak is packed map plus `LEVEL_PREFIX`.
`tools/checkheap.py` enforces the larger peak and a 1024-byte release floor.
`MAP_MAX_BYTES` 4096 is a packed-map cap; prefix is extra.

Enemy bank bytes (from `enemy_sizes.asm`, including QAI1 header, optional
relocatable behavior code, pose data, SFX, and clip events): grunt 2488,
knight 2369, rott 2384, scrag 2353, ogre 2836, shambler 2526, chthon 2934,
zombie 2936.

Current gate (`game.lbl`, avail 10478, `LEVEL_PREFIX` 2220):

| Level | Map | Worst room poses | Need | Slack |
| :--- | ---: | :--- | ---: | ---: |
| E1M1 | 2332 | 4872 (room 2: grunt, rott) | 7204 | 3274 |
| E1M2 | 3115 | 5324 (room 0: grunt, ogre) | 8439 | 2039 |
| E1M3 | 3555 | 2936 (room 1: zombie) | 6491 | 3987 |
| E1M4 | 2345 | 5205 (room 7: knight, ogre) | 7550 | 2928 |
| E1M5 | 3651 | 5205 (room 3: knight, ogre) | 8856 | 1622 |
| E1M6 | 2234 | 2936 (room 8: zombie) | 5170 | 5308 |

E1M5 is the tightest and remains above the enforced 1024-byte release floor.
Caps: `MAP_MAX_BYTES` 4096, pose payload 4096, fused bank 8192.

## VIC Bank 3 overview

| Address | Size | Use |
| :--- | ---: | :--- |
| `$C000`–`$C3E7` | 1000 | Screen matrix A (HUD + 24×16 viewport tiles) |
| `$C3E8`–`$C3F7` | 16 | Unused (past 40×25 matrix) |
| `$C3F8`–`$C3FF` | 8 | VIC sprite pointers for matrix A |
| `$C400`–`$C7E7` | 1000 | Screen matrix B |
| `$C7E8`–`$C7F7` | 16 | Unused |
| `$C7F8`–`$C7FF` | 8 | VIC sprite pointers for matrix B |
| `$C800`–`$C8FF` | 256 | Weapon body sprites 0–3 (`WPN_RAM`, 4×64) |
| `$C900`–`$C93F` | 64 | Sprite 4 muzzle / spark / nail L (`WPN_FLASH`) |
| `$C940`–`$C97F` | 64 | Sprite 5 nail R (`WPN_FLASH2`) |
| `$C980`–`$C9BF` | 64 | Sprite 6 enemy muzzle (`WPN_EMUZ`) |
| `$C9C0`–`$C9FF` | 64 | Sprite 7 impact splat (`WPN_SPLAT`) |
| `$CA00`–`$CE81` | 642 | Project / clip / game scratch (table below) |
| `$CE82`–`$CFFF` | 382 | Play BSS: enemy state, grenade SoA, hitscan/FX, Scrag spit, movement scratch, and AI-bank relocation scratch through `$CFCB`; remainder free `$CFCC+` before charset A |
| `$D000`–`$D5FF` | 1536 | Charset A top cols 0–23 (viewport) |
| `$D600`–`$D607` | 8 | Char 192 `$FF` margin glyph |
| `$D608`–`$D747` | 320 | `SINTAB` (COSTAB = SINTAB+64 at `$D648`) |
| `$D748`–`$D7FF` | 184 | Unused tail pad |
| `$D800`–`$DDFF` | 1536 | Charset A bottom cols 0–23 |
| `$DE00`–`$DE07` | 8 | Char 192 `$FF` |
| `$DE08`–`$DE87` | 128 | `invzl` |
| `$DE88`–`$DEFF` | 120 | Unused |
| `$DF00`–`$DFFF` | 256 | `ALOGTAB` |
| `$E000`–`$E5FF` | 1536 | Charset B top cols 0–23 |
| `$E600`–`$E607` | 8 | Char 192 `$FF` |
| `$E608`–`$E687` | 128 | `invzh` |
| `$E688`–`$E6FF` | 120 | Unused |
| `$E700`–`$E7FF` | 256 | `ALOGHI` |
| `$E800`–`$EDFF` | 1536 | Charset B bottom cols 0–23 |
| `$EE00`–`$EE07` | 8 | Char 192 `$FF` |
| `$EE08`–`$EEF3` | 236 | Krill `loadraw` on `quake64-krill.d64`; unused hole on the KERNAL disk |
| `$EEF4`–`$EEFF` | 12 | Spare after resident |
| `$EF00`–`$EFFF` | 256 | `LOGTAB` |
| `$F000`–`$F1FF` | 512 | `sqlo` (disk `sqt`) |
| `$F200`–`$F3FF` | 512 | `sqhi` |
| `$F400`–`$F5FF` | 512 | `negsqlo` |
| `$F600`–`$F7FF` | 512 | `negsqhi` |
| `$F800`–`$FFFF` | 2048 | UI charset (`UI_CHARSET`, disk `fnt`). `$FFFA–$FFFF` = NMI/RESET/IRQ (char 255 unused) |

`$D018` pointers: matrix A `$C000` / B `$C400`; viewport charsets `$D000`/`$D800` vs `$E000`/`$E800` (mid-screen split); HUD uses `$F800`. Quarter-square tables (`sqlo` / `sqhi` / `negsqlo` / `negsqhi`) load at `$F000` (disk `sqt`, under KERNAL). GAME / heap / play BSS: section above.

A-side LUTs (`SINTAB`, `invzl`, `ALOGTAB`) sit under I/O; math runs with `$01=$30`.

## `$CA00+` scratch

Vertex tables are 16 slots. Edge clip tables are 32 slots. Unique-X/Z product tables are 6 slots (rooms still cook at 4 unique).

| Address | Size | Label | Notes |
| :--- | ---: | :--- | :--- |
| `$CA00` | 16 | `PROJ_X` | Screen X (lo) |
| `$CA10` | 16 | `PROJ_Y` | Screen Y (lo) |
| `$CA20` | 16 | `PROJ_Z` | View Z (lo) |
| `$CA30` | 16 | `CAM_X` | View X (lo) |
| `$CA40` | 16 | `CAM_Y` | View Y (lo) |
| `$CA50` | 16 | `CAM_Z` | View Z (lo) |
| `$CA60` | 16 | `PROJ_XH` | Screen X (hi) |
| `$CA70` | 16 | `PROJ_YH` | Screen Y (hi) |
| `$CA80` | 16 | `CAM_XH` | View X (hi) |
| `$CA90` | 16 | `CAM_YH` | View Y (hi) |
| `$CAA0` | 16 | `CAM_ZH` | View Z (hi) |
| `$CAB0` | 16 | `PROJ_ZH` | View Z projected (hi) |
| `$CAC0` | 32 | `EDGE_VIS` | 1 = stroke this packed edge |
| `$CAE0` | 32 | `CLIP_X0` | Clipped endpoint X0 |
| `$CB00` | 32 | `CLIP_Y0` | Clipped endpoint Y0 |
| `$CB20` | 32 | `CLIP_X1` | Clipped endpoint X1 |
| `$CB40` | 32 | `CLIP_Y1` | Clipped endpoint Y1 |
| `$CB60` | 4 | `frame_t0` | CIA2 cascade snapshot |
| `$CB64` | 4 | `frame_cy` | Frame period (cascade delta) |
| `$CB68` | 4 | `casc_now` | Last CIA2 read |
| `$CB6C` | 4 | — | Unused |
| `$CB70` | 8 | `PROC_KIND` | Process SoA (`PROC_NUM`=8) |
| `$CB78` | 8 | `PROC_A` | Door / elev id |
| `$CB80` | 8 | `PROC_B` | Dest / next kind |
| `$CB88` | 8 | `PROC_C` | Timer lo |
| `$CB90` | 8 | `PROC_D` | Timer hi |
| `$CB98` | 8 | `PROC_E` | Elev home Y |
| `$CBA0` | 8 | `PROC_L` | Local SoA index |
| `$CBA8` | 1 | `floor_slope` | 1 if this frame's floor is a ramp |
| `$CBA9` | 1 | `trig_inside` | Occupancy bits; Nth same-room trigger |
| `$CBAA` | 2 | `hurt_ms_l/h` | Hurt-trigger cooldown remaining |
| `$CBAC` | 4 | — | Unused |
| `$CBB0` | 4 | `elev_y` | `MAP_NELEVS` ≤ 4 |
| `$CBB4` | 1 | `elev_noise_n` | SID V3 rumble refcount |
| `$CBB5` | 3 | — | Unused |
| `$CBB8` | 6 | `proc_tmp0`…`proc_tmp5` | Process scratch |
| `$CBBE` | 2 | `in_fwd` | Hold ms (IRQ) |
| `$CBC0` | 2 | `in_back` | |
| `$CBC2` | 2 | `in_strafel` | |
| `$CBC4` | 2 | `in_strafer` | |
| `$CBC6` | 2 | `in_turn_l` | |
| `$CBC8` | 2 | `in_turn_r` | |
| `$CBCA` | 2 | `hold_fwd` | Frame snapshot |
| `$CBCC` | 2 | `hold_back` | |
| `$CBCE` | 2 | `hold_strafel` | |
| `$CBD0` | 2 | `hold_strafer` | |
| `$CBD2` | 2 | `hold_turn_l` | |
| `$CBD4` | 2 | `hold_turn_r` | |
| `$CBD6` | 1 | `in_use` | K latch |
| `$CBD7` | 1 | `key_use` | |
| `$CBD8` | 1 | `key_use_was` | Rising-edge debounce |
| `$CBD9` | 1 | `pl_falling` | 0 grounded, 1 airborne |
| `$CBDA` | 1 | `fall_vl` | 8.8 downward vel lo |
| `$CBDB` | 1 | `fall_vh` | 8.8 downward vel hi |
| `$CBDC` | 1 | `fall_y0` | `cam_yh` at fall start |
| `$CBDD` | 1 | `fall_acc` | leftover ms toward `FALL_TICK_MS` |
| `$CBDE` | 6 | `UX` | Unique world X |
| `$CBE4` | 6 | `UZ` | Unique world Z |
| `$CBEA` | 16 | `VY` | Per-vert world Y |
| `$CBFA` | 6 | `XC_L` | UX × cos (lo) |
| `$CC00` | 6 | `XC_H` | UX × cos (hi) |
| `$CC06` | 6 | `XS_L` | UX × sin (lo) |
| `$CC0C` | 6 | `XS_H` | UX × sin (hi) |
| `$CC12` | 6 | `ZC_L` | UZ × cos (lo) |
| `$CC18` | 6 | `ZC_H` | UZ × cos (hi) |
| `$CC1E` | 6 | `ZS_L` | UZ × sin (lo) |
| `$CC24` | 6 | `ZS_H` | UZ × sin (hi) |
| `$CC2A` | 1 | `in_fire` | Weapon BSS |
| `$CC2B` | 4 | `in_wpn_axe`…`in_wpn_gren` | |
| `$CC2F` | 1 | `key_fire` | |
| `$CC30` | 4 | `key_wpn_axe`…`key_wpn_gren` | |
| `$CC34` | 1 | `cur_weapon` | |
| `$CC35` | 1 | `wpn_pose` | |
| `$CC36` | 2 | `fire_rpt_l/h` | |
| `$CC38` | 2 | `flash_ms_l/h` | |
| `$CC3A` | 1 | `flash_phase` | Sprite 4 |
| `$CC3B` | 1 | `mg_frame` | |
| `$CC3C` | 1 | `wpn_x` | |
| `$CC3D` | 1 | `wpn_y` | |
| `$CC3E` | 1 | `spr_en` | |
| `$CC3F` | 1 | `anim_step` | |
| `$CC40` | 2 | `anim_ms_l/h` | |
| `$CC42` | 1 | `wpn_flash_en` | |
| `$CC43` | 1 | `wpn_flash_dy` | |
| `$CC44` | 1 | `wpn_tmp0` | |
| `$CC45` | 2 | `flash5_ms_l/h` | |
| `$CC47` | 1 | `flash5_phase` | Sprite 5 |
| `$CC48` | 2 | `emuz_ms_l/h` | |
| `$CC4A` | 1 | `emuz_on` | |
| `$CC4B` | 1 | `emuz_xmsb` | |
| `$CC4C` | 20 | — | Unused (was 8-slot door view SoA) |
| `$CC60` | 16 | `VOC` | Cohen–Sutherland outcode |
| `$CC70` | 16 | `VBEHIND` | 1 = z < ZCLIP |
| `$CC80` | 16 | `VSX` | Front-vert screen X |
| `$CC90` | 16 | `VSY` | Front-vert screen Y |
| `$CCA0` | 16 | `COL_DONE` | XZ-column project cache |
| `$CCB0` | 16 | `COL_INVL` | |
| `$CCC0` | 16 | `COL_INVH` | |
| `$CCD0` | 16 | `COL_INVK` | |
| `$CCE0` | 16 | `COL_PXL` | |
| `$CCF0` | 16 | `COL_PXH` | |
| `$CD00` | 1 | `ammo_shells` | |
| `$CD01` | 1 | `ammo_nails` | |
| `$CD02` | 1 | `ammo_grenades` | |
| `$CD03` | 1 | `have_wpn` | `HAVE_*` bitfield |
| `$CD04` | 32 | `bp_taken` | `BP_MAX` |
| `$CD24` | 1 | `player_hp` | 0..`PLAYER_HP_MAX` |
| `$CD25` | 1 | `player_armour` | starts 0; no pickups yet |
| `$CD26` | 24 | `en_state` | `ENEMY_MAX` |
| `$CD3E` | 24 | `en_frame` | |
| `$CD56` | 24 | `drop_taken` | |
| `$CD6E` | 24 | `drop_x` | |
| `$CD86` | 24 | `drop_y` | |
| `$CD9E` | 24 | `drop_z` | |
| `$CDB6` | 24 | `drop_room` | |
| `$CDCE` | 24 | `drop_type` | |
| `$CDE6` | 24 | `en_hp` | |
| `$CDFE` | 24 | `en_timer` | |
| `$CE16` | 24 | `en_timer_h` | |
| `$CE2E` | 24 | `en_step` | |
| `$CE46` | 24 | `en_step_h` | |
| `$CE5E` | 24 | `en_dir` | |
| `$CE76` | 1 | `gunshot_wake` | |
| `$CE77` | 5 | `ai_dirtry` | Dodge candidates |
| `$CE7C` | 1 | `ai_turn` | |
| `$CE7D` | 1 | `ai_probe` | |
| `$CE7E` | 1 | `emuz_vx` | Staged sprite 6 |
| `$CE7F` | 1 | `emuz_vy` | |
| `$CE80` | 1 | `emuz_col` | |
| `$CE81` | 1 | `emuz_pending` | |
| `$CE82` | 1 | `fb_probe_y` | floor_below inclusive max walkable Y |
| `$CE83` | 2 | `death_wait_l/h` | Death hold ms |
| `$CE85` | 1 | `col_room` | Collision room for inset/floor/solid |
| `$CE86` | 1 | `splat_xmsb` | |
| `$CE87` | 1 | `splat_vx` | |
| `$CE88` | 1 | `splat_vy` | |
| `$CE89` | 1 | `splat_col` | |
| `$CE8A` | 1 | `trig_seen` | update_triggers: b0 hurt ticked, b1 msg overlap |
| `$CE8B` | 1 | `shot_hit_i` | |
| `$CE8C` | 1 | `shot_hit_z` | |
| `$CE8D` | 1 | `hurt_flash_l` | Remaining red-border ms lo |
| `$CE8E` | 1 | `hurt_flash_h` | Remaining red-border ms hi |
| `$CE8F` | 1 | `bite_splat_i` | |
| `$CE90` | 2 | `status_ms_l/h` | Status HUD remaining ms |
| `$CE92` | 1 | `door_i0` | Room door slice start |
| `$CE93` | 1 | `door_i1` | Exclusive end |
| `$CE94` | 1 | `sw_match` | Cooked door/enable-tag id while unlocking/arming |
| `$CE95` | 24 | `en_pat_n` | `ENEMY_MAX` |
| `$CEAD` | 24 | `en_pain_i` | `ENEMY_MAX` |
| `$CEC5` | 1 | `have_keys` | |
