# VIC Bank 3 memory map

Source of truth for addresses is [`src/mem.asm`](src/mem.asm). Engine code is the `game` PRG (load `$0900`); this bank is screens, charsets, sprites, LUTs, and game scratch. Accessing `$D000–$FFFF` as RAM requires `$01` to unmap I/O and the KERNAL. Colour RAM (`$D800`) is the I/O overlay of charset A bottom.

The playable disk is [`quake64.d64`](quake64.d64): boot loads `menu`, stages `tab` into charset tails, then `fnt` / `scr` / `sqt` / `game`.

Caps used by the mesh path: **16 verts**, **32 edges**, **6 unique world X** and **6 unique world Z** (rooms still cook at 4 unique).

## Bank overview

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
| `$EE08`–`$EEFF` | 248 | Unused |
| `$EF00`–`$EFFF` | 256 | `LOGTAB` |
| `$F000`–`$F7FF` | 2048 | UI charset (`UI_CHARSET`, disk `fnt`) |
| `$F800`–`$F9FF` | 512 | `sqlo` (disk `sqt`) |
| `$FA00`–`$FBFF` | 512 | `sqhi` |
| `$FC00`–`$FDFF` | 512 | `negsqlo` |
| `$FE00`–`$FFFF` | 512 | `negsqhi` |

`$D018` pointers: matrix A `$C000` / B `$C400`; viewport charsets `$D000`/`$D800` vs `$E000`/`$E800` (mid-screen split); HUD uses `$F000`. Quarter-square tables (`sqlo` / `sqhi` / `negsqlo` / `negsqhi`) load at `$F800` (disk `sqt`, under KERNAL). Game PRG is `$0900`–`< $C000`. `$B000–$BFFF` is free. Boot is `$0801`; menu overlay is overwritten by game. Selectors `effects_vol` / `game_complete` / `difficulty` sit at `$08FD–$08FF`.

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
| `$CE22` | 16 | `door_open` | `MAP_NDOORS` ≤ `DOOR_MAX` (16) |
| `$CE32` | 16 | `door_vx` | Oriented door SoA |
| `$CE42` | 16 | `door_vz` | |
| `$CE52` | 16 | `door_vsx` | |
| `$CE62` | 16 | `door_vsz` | |
| `$CE72` | 16 | `door_vface` | Last used scratch byte `$CE81` |
