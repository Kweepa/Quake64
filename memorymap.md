# Memory map

CPU space (`$0000–$BFFF`) is boot, GAME, and the downward heap. VIC bank 3 (`$C000–$FFFF`) is screens, charsets, sprites, LUTs, and play scratch. Source of truth for abs addresses is [`src/mem.asm`](src/mem.asm); zero page is [`src/zp.asm`](src/zp.asm); map SoA pointers are [`src/map_bss.asm`](src/map_bss.asm). GAME module bounds below are from `game.lbl` (KERNAL assemble). Accessing `$D000–$FFFF` as RAM requires `$01` to unmap I/O and the KERNAL. Colour RAM (`$D800`) is the I/O overlay of charset A bottom.

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
| `$0520`–`$06DE` | 447 | Play BSS (table below). Next free `$06DF` |
| `$06DF`–`$08F8` | 538 | Free during play (boot leftover `$0801`–`$08F8` is overwritten on `reboot_game`) |
| `$08F9`–`$08FB` | 3 | `REBOOT_STUB` (`JMP reboot_game`) |
| `$08FC` | 1 | `level_num` |
| `$08FD`–`$08FF` | 3 | `effects_vol` / `game_complete` / `difficulty` (survive GAME load) |
| `$0900`–`$982E` | 36655 | GAME (`end_game` `$982F`). Menu overlay lived here first |
| `$982F`–`$BFFF` | 10193 | Heap (map, reloc overlay, per-room poses). Krill GAME is 48 B shorter |

### Play BSS `$0520+`

| Address | Size | Label |
| :--- | ---: | :--- |
| `$0520`–`$0589` | 106 | `frame13_lo` |
| `$058A`–`$05F3` | 106 | `frame13_hi` |
| `$05F4`–`$0623` | 48 | `enemy_gx/y/z` lo/hi (`ENEMY_PTR_N`=8) |
| `$0624`–`$063B` | 24 | `box_vis_edges` |
| `$063C`–`$0647` | 12 | `box_vis_vert` |
| `$0648`–`$0687` | 64 | `room_pack_edges` |
| `$0688`–`$06A7` | 32 | `room_pack_vert` |
| `$06A8`–`$06B4` | 13 | `pose_gx` |
| `$06B5`–`$06C1` | 13 | `pose_gy` |
| `$06C2`–`$06CE` | 13 | `pose_gz` |
| `$06CF`–`$06D6` | 8 | `pose_map_lo` |
| `$06D7`–`$06DE` | 8 | `pose_map_hi` |

### GAME `$0900`–`end_game`

Assembled in `!source` order from [`src/quake64.asm`](src/quake64.asm). Bounds are the first emitted label of each file through the next. Nested `!source` is listed on its own row. Krill vs KERNAL only changes `LoadPrg` inside `loader.asm` (48 B).

| Address | Size | File | Notes |
| :--- | ---: | :--- | :--- |
| `$0900`–`$0A92` | 403 | `quake64.asm` | `start` / `main` / cam add |
| `$0A93`–`$0C46` | 436 | `vic.asm` | VIC init, charset clear, `$d018` |
| `$0C47`–`$0F97` | 849 | `irq.asm` | raster chain, keys |
| `$0F98`–`$106B` | 212 | `profil.asm` | CIA2 cascade (buckets if `PROFILE`) |
| `$106C`–`$14B9` | 1102 | `hud.asm` | HUD + pickup strings |
| `$14BA`–`$1ABD` | 1540 | `math.asm` | smul / log / persp / `ATAN32` / rnd |
| `$1ABE`–`$1D67` | 682 | `util.asm` | AABB / line-box |
| `$1D68`–`$1FD0` | 617 | `line.asm` | Bresenham setup, `col_lo/hi` |
| `$1FD1`–`$2766` | 1942 | `_line_bodies.asm` | unrolled plot (from `line.asm`) |
| `$2767`–`$2983` | 541 | `fx.asm` | explosion particles |
| `$2984`–`$2F45` | 1474 | `grenade.asm` | |
| `$2F46`–`$3172` | 557 | `playsound.asm` | SID mixer |
| `$3173`–`$39F2` | 2176 | `pcsounds.asm` | resident PC-speaker envelopes |
| `$39F3`–`$3AF2` | 256 | `pcsfreq.asm` | Fn hi LUT (256) |
| `$3AF3`–`$42BA` | 1992 | `weapon.asm` | |
| `$42BB`–`$486A` | 1456 | `weapon_spr.asm` | packed view-model sprites |
| `$486B`–`$489E` | 52 | `splat_spr.asm` | |
| `$489F`–`$48E6` | 72 | `enemy_muzzle.asm` | |
| `$48E7`–`$4A2A` | 324 | `process.asm` | door/elev process SoA |
| `$4A2B`–`$4BFD` | 467 | `elevator.asm` | |
| `$4BFE`–`$4E19` | 540 | `door.asm` | |
| `$4E1A`–`$5CC3` | 3754 | `world.asm` | move, collision, pickups, triggers |
| `$5CC4`–`$5FD7` | 788 | `item_mesh.asm` | backpack / door meshes |
| `$5FD8`–`$6B73` | 2972 | `mesh.asm` | rooms, slopes, world stroke |
| `$6B74`–`$6CF2` | 383 | `enemy_data.asm` | clip tables / stats (from `cube.asm`) |
| `$6CF3`–`$7EC1` | 4559 | `cube.asm` | enemy xform / project / clip / draw |
| `$7EC2`–`$8E62` | 4001 | `enemy.asm` | AI, hitscan, damage |
| `$8E63`–`$8ED8` | 118 | `mapacc_rt.asm` | reloc patch |
| `$8ED9`–`$8EF8` | 32 | `map_sizes.asm` + `enemy_sizes.asm` | generated payload sizes |
| `$8EF9`–`$982E` | 2358 | `loader.asm` | `LoadPrg`, `LoadLevel`, pose stream, `bind_map` table |

Largest slices: `cube` 4559, `enemy` 4001, `world` 3754, `mesh` 2972, `loader` 2358, `pcsounds` 2176, `weapon` 1992, `_line_bodies` 1942, `math` 1540, `grenade` 1474, `weapon_spr` 1456, `hud` 1102.

Macros-only (no bytes): `mem.asm`, `zp.asm`, `map_counts.asm`, `mapacc.asm`, `map_bss.asm`. `_rotate_body.asm` is inlined in `load_view_trig` (no own label).

### Heap `$982F`–`$C000`

Grows down from `SCR_A`. `LoadLevel`: map, then `RELOC_MAX` (`$0800` / 2048; actual `reloc.prg` is 1388), patch SMC, drop reloc (`heap_top = map_base`), then at most `ROOM_MAX_TYPES` (2) pose banks for the current room. Peak = `map + max(RELOC_MAX, worst-room pose sum)`. `tools/checkheap.py` gates the build on that.

Pose payload bytes (from `enemy_sizes.asm`, includes trailing sfx blob): grunt 2354, knight 1662, rott 2112, scrag 1544, ogre 2523, shambl 2394, chthon 2804, zombie 2804.

Current gate (`game.lbl`, avail 10193):

| Level | Map | Worst room poses | Need | Slack |
| :--- | ---: | :--- | ---: | ---: |
| E1M1 | 2289 | 4466 (room 2: grunt, rott) | 6755 | 3438 |
| E1M2 | 3081 | 4877 (room 0: grunt, ogre) | 7958 | 2235 |
| E1M3 | 3515 | 2804 (room 1: zombie) | 6319 | 3874 |

E1M2 is still the tightest (pose-bound). Caps: `MAP_MAX_BYTES` 4096, `ENEMY_POSE_MAX` 4096.

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
| `$CE82`–`$CFFF` | 382 | Unused (before charset A) |
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
| `$CBA9` | 1 | `trig_inside` | Trigger SoA index or `$ff` |
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
| `$CD26` | 16 | `en_state` | `ENEMY_MAX` |
| `$CD36` | 16 | `en_frame` | |
| `$CD46` | 16 | `drop_taken` | |
| `$CD56` | 16 | `drop_x` | |
| `$CD66` | 16 | `drop_y` | |
| `$CD76` | 16 | `drop_z` | |
| `$CD86` | 16 | `drop_room` | |
| `$CD96` | 16 | `drop_type` | |
| `$CDA6` | 16 | `en_hp` | |
| `$CDB6` | 16 | `en_timer` | |
| `$CDC6` | 16 | `en_timer_h` | |
| `$CDD6` | 16 | `en_step` | |
| `$CDE6` | 16 | `en_step_h` | |
| `$CDF6` | 16 | `en_dir` | |
| `$CE06` | 1 | `gunshot_wake` | |
| `$CE07` | 5 | `ai_dirtry` | Dodge candidates |
| `$CE0C` | 1 | `ai_turn` | |
| `$CE0D` | 1 | `ai_probe` | |
| `$CE0E` | 1 | `emuz_vx` | Staged sprite 6 |
| `$CE0F` | 1 | `emuz_vy` | |
| `$CE10` | 1 | `emuz_col` | |
| `$CE11` | 1 | `emuz_pending` | |
| `$CE12` | 1 | `emuz_skip` | |
| `$CE13` | 2 | `splat_ms_l/h` | |
| `$CE15` | 1 | `splat_on` | |
| `$CE16` | 1 | `splat_xmsb` | |
| `$CE17` | 1 | `splat_vx` | |
| `$CE18` | 1 | `splat_vy` | |
| `$CE19` | 1 | `splat_col` | |
| `$CE1A` | 1 | `splat_skip` | |
| `$CE1B` | 1 | `shot_hit_i` | |
| `$CE1C` | 1 | `shot_hit_z` | |
| `$CE1D` | 1 | `hurt_flash_l` | Remaining red-border ms lo |
| `$CE1E` | 1 | `hurt_flash_h` | Remaining red-border ms hi |
| `$CE1F` | 1 | `bite_splat_i` | |
| `$CE20` | 2 | `status_ms_l/h` | Status HUD remaining ms |
| `$CE22` | 1 | `door_i0` | Room door slice start |
| `$CE23` | 1 | `door_i1` | Exclusive end |
| `$CE24`–`$CE81` | 94 | — | Free (was door runtime SoA) |
