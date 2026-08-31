; Runtime map header + SoA pointers (filled by bind_map).
; Labels are RAM at $0400 (not emitted in GAME). From room_x through slope_flags
; they are pointers into the packed map — columns only via +lda_mx / +sta_mx /
; +cmp_mx / *_my (mapacc.asm). Never lda en_x,x (that loads the pointer word).
!zone map_bss

; Packed header bytes 0..23 — must stay contiguous (bind_map copies 24 bytes).
map_nrooms	= $0400
map_ndoors	= $0401
map_ncrates	= $0402
map_nslopes	= $0403
map_nplats	= $0404
map_nswitches	= $0405
map_nelevs	= $0406
map_nenemies	= $0407
map_ntrigs	= $0408
map_ndests	= $0409
map_nbackpacks	= $040A
map_type0	= $040B
map_type1	= $040C
map_type2	= $040D
map_nux	= $040E
map_nuz	= $040F
map_nvert	= $0410
map_nedge	= $0411

spawn_x	= $0412
spawn_y	= $0413
spawn_z	= $0414
spawn_rot	= $0415
spawn_room	= $0416
spawn_id	= $0417
!if spawn_id - map_nrooms != 23 {
	!error "map header BSS is not 24 packed bytes"
}

; 16-bit pointers into the packed map blob
room_x	= $0418
room_y	= $041A
room_z	= $041C
room_sx	= $041E
room_sy	= $0420
room_sz	= $0422
room_bg	= $0424
room_line	= $0426
room_fx	= $0428
room_wpn	= $042A
room_id	= $042C
rc_x	= $042E
rc_y	= $0430
rc_z	= $0432
rc_sx	= $0434
rc_sy	= $0436
rc_sz	= $0438
rb_x	= $043A
rb_y	= $043C
rb_z	= $043E
rb_sx	= $0440
rb_sy	= $0442
rb_sz	= $0444
room_nv	= $0446
room_ne	= $0448
room_vo	= $044A
room_eo	= $044C
room_nx	= $044E
room_nz	= $0450
room_uo	= $0452
room_zo	= $0454
room_door_o	= $0456
room_ndoor	= $0458
room_ux	= $045A
room_uz	= $045C
room_vy	= $045E
room_xid	= $0460
room_zid	= $0462
room_col	= $0464
room_e0	= $0466
room_e1	= $0468
room_evert	= $046A
room_efaces	= $046C
door_x	= $046E
door_y	= $0470
door_z	= $0472
door_sx	= $0474
door_sy	= $0476
door_sz	= $0478
door_face	= $047A
door_key	= $047C
door_type	= $047E
door_id	= $0480
door_other	= $0482
crate_x	= $0484
crate_y	= $0486
crate_z	= $0488
crate_sx	= $048A
crate_sy	= $048C
crate_sz	= $048E
crate_room	= $0490
crate_id	= $0492
slope_x	= $0494
slope_y	= $0496
slope_z	= $0498
slope_sx	= $049A
slope_sy	= $049C
slope_sz	= $049E
slope_axis	= $04A0
slope_dir	= $04A2
slope_room	= $04A4
slope_id	= $04A6
plat_x	= $04A8
plat_y	= $04AA
plat_z	= $04AC
plat_sx	= $04AE
plat_sz	= $04B0
plat_room	= $04B2
plat_solid	= $04B4
plat_id	= $04B6
elev_x	= $04B8
elev_y0	= $04BA
elev_z	= $04BC
elev_sx	= $04BE
elev_sy	= $04C0
elev_sz	= $04C2
elev_home	= $04C4
elev_dest	= $04C6
elev_room	= $04C8
elev_id	= $04CA
sw_x	= $04CC
sw_y	= $04CE
sw_z	= $04D0
sw_sx	= $04D2
sw_sy	= $04D4
sw_sz	= $04D6
sw_elev	= $04D8
sw_room	= $04DA
sw_face	= $04DC
sw_id	= $04DE
en_x	= $04E0
en_y	= $04E2
en_z	= $04E4
en_type	= $04E6
en_rot	= $04E8
en_room	= $04EA
en_patrol	= $04EC
en_id	= $04EE
tr_x	= $04F0
tr_y	= $04F2
tr_z	= $04F4
tr_sx	= $04F6
tr_sy	= $04F8
tr_sz	= $04FA
tr_room	= $04FC
tr_purpose	= $04FE
tr_arg	= $0500
tr_id	= $0502
td_x	= $0504
td_y	= $0506
td_z	= $0508
td_rot	= $050A
td_room	= $050C
bp_x	= $050E
bp_y	= $0510
bp_z	= $0512
bp_type	= $0514
bp_room	= $0516
bp_id	= $0518
map_name	= $051A
map_text	= $051C
slope_flags	= $051E
!if (slope_flags - room_x) & 1 {
	!error "map pointer table is not aligned words"
}
!if (slope_flags - room_x) / 2 > 255 {
	!error "map pointer table exceeds 256 fields"
}
; MAP_BSS_END = $0520  size=288
