; Room physics, proximity triggers, floor / eye sync
!zone world

; ------------------------------------------------------------------
world_init
	lda spawn_room
	jsr set_room_idx
	lda #0
	sta cam_xl
	sta cam_yl
	sta cam_zl
	sta pitch
	sta msg_on
	lda #$ff
	sta pl_on_elev
	; spawn eye at spawn_x+1 (center-ish), spawn_y+EYE, spawn_z+1
	clc
	lda spawn_x
	adc #1
	sta cam_xh
	clc
	lda spawn_y
	adc #EYE_HEIGHT
	sta cam_yh
	clc
	lda spawn_z
	adc #1
	sta cam_zh
	; yaw from rot octant * 32
	lda spawn_rot
	asl
	asl
	asl
	asl
	asl
	sta yaw
	jsr proc_init
	jsr init_backpacks
	jsr init_enemies
	jsr init_drops
	jsr update_floor
	jsr sync_eye
	lda #$ff
	sta palette_room
	jsr apply_room_palette
	rts

; Clear bp_taken[0..MAP_NBACKPACKS)
init_backpacks
	ldx #0
.ib_lp
	cpx #MAP_NBACKPACKS
	bcs .ib_rts
	lda #0
	sta bp_taken,x
	inx
	bne .ib_lp
.ib_rts
	rts

; All enemies idle, HP from type, frame 0
init_enemies
	lda #$a5
	sta random8
	lda #0
	sta gunshot_wake
!if DOG_AI_DEBUG = 1 {
	lda #$ff
	sta dog_dbg_slot
	sta dog_dbg_dir
}
	ldx #0
.ie_lp
	cpx #MAP_NENEMIES
	bcs .ie_rts
	lda #EN_IDLE
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_timer,x
	sta en_timer_h,x
	sta en_step,x
	sta en_step_h,x
	lda en_rot,x			; map rot = editor octant (0=+Z)
	sta en_dir,x
	asl
	asl
	asl
	asl
	asl
	sta en_rot,x
	ldy en_type,x
	lda enemy_hp_init,y
	sta en_hp,x
	inx
	bne .ie_lp
.ie_rts
	rts

; Drop slots inactive (taken=1)
init_drops
	ldx #0
	lda #1
.id_lp
	cpx #MAP_NENEMIES
	bcs .id_rts
	sta drop_taken,x
	inx
	bne .id_lp
.id_rts
	rts

; ------------------------------------------------------------------
; point_in_aabb_xz — col_x/col_z vs box at Y index in tables via box_* zp
; C=1 inside (exclusive max)
; ------------------------------------------------------------------
point_in_box_xz
	lda col_x
	cmp box_x
	bcc .pib_no
	clc
	lda box_x
	adc box_sx
	cmp col_x
	bcc .pib_no
	beq .pib_no
	lda col_z
	cmp box_z
	bcc .pib_no
	clc
	lda box_z
	adc box_sz
	cmp col_z
	bcc .pib_no
	beq .pib_no
	sec
	rts
.pib_no
	clc
	rts

; ------------------------------------------------------------------
; player_overlaps_y — [feet, feet+PLAYER_H) vs [box_y, box_y+box_sy)
; C=1 overlap
; ------------------------------------------------------------------
player_overlaps_y
	clc
	lda box_y
	adc box_sy
	sta col_y			; exclusive max of box
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcs .poy_no			; feet >= y+sy
	clc
	adc #PLAYER_H			; exclusive head
	sta col_y
	lda box_y
	cmp col_y
	bcs .poy_no			; y >= head
	sec
	rts
.poy_no
	clc
	rts

; ------------------------------------------------------------------
update_floor
	lda pl_on_elev
	sta obj_i			; prior elev (rider), before clear
	lda #$ff
	sta pl_on_elev
	ldx room_idx
	lda room_y,x
	sta floor_y
	; crate tops (walkable)
	ldx #0
.uf_c
	cpx #MAP_NCRATES
	bcs .uf_p
	lda crate_room,x
	cmp room_idx
	bne .uf_cn
	lda crate_x,x
	sta box_x
	lda crate_z,x
	sta box_z
	lda crate_sx,x
	sta box_sx
	lda crate_sz,x
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .uf_cn
	clc
	lda crate_y,x
	adc crate_sy,x
	cmp floor_y
	bcc .uf_cn
	beq .uf_cn
	sta col_y			; crate_top
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcc .uf_cn			; feet < top — overhead
	lda col_y
	sta floor_y
.uf_cn
	inx
	bne .uf_c
.uf_p
	; platforms (walkable if solid)
	ldx #0
.uf_pl
	cpx #MAP_NPLATS
	bcs .uf_plats_done
	lda plat_solid,x
	beq .uf_pn
	lda plat_room,x
	cmp room_idx
	bne .uf_pn
	lda plat_x,x
	sta box_x
	lda plat_z,x
	sta box_z
	lda plat_sx,x
	sta box_sx
	lda plat_sz,x
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .uf_pn
	lda plat_y,x
	cmp floor_y
	bcc .uf_pn
	beq .uf_pn
	sta col_y			; plat plane
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcc .uf_pn			; feet < plane — overhead
	lda col_y
	sta floor_y
.uf_pn
	inx
	bne .uf_pl
.uf_plats_done
	jsr elev_update_floor
.uf_slope
	ldx #0
.uf_s
	cpx #MAP_NSLOPES
	bcc .uf_sgo
	jmp .uf_done
.uf_sgo
	lda slope_room,x
	cmp room_idx
	beq .uf_sroom
	jmp .uf_sn
.uf_sroom
	lda slope_x,x
	sta box_x
	lda slope_z,x
	sta box_z
	lda slope_sx,x
	sta box_sx
	lda slope_sz,x
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcs .uf_sxz
	jmp .uf_sn
.uf_sxz
	; height = slope_y + (high face of cell >> 1)
	lda slope_axis,x
	bne .uf_sz
	; axis X
	sec
	lda cam_xh
	sbc slope_x,x
	sta col_y			; local
	lda slope_dir,x
	bne .uf_sx_p
	; dir -1: local' = sx-local
	lda slope_sx,x
	sec
	sbc col_y
	sta col_y
	jmp .uf_sx_lsr
.uf_sx_p
	inc col_y			; dir +: sample high face
.uf_sx_lsr
	lsr col_y
	clc
	lda slope_y,x
	adc col_y
	sta floor_y
	jmp .uf_done
.uf_sz
	sec
	lda cam_zh
	sbc slope_z,x
	sta col_y
	lda slope_dir,x
	bne .uf_sz_p
	lda slope_sz,x
	sec
	sbc col_y
	sta col_y
	jmp .uf_sz_lsr
.uf_sz_p
	inc col_y
.uf_sz_lsr
	lsr col_y
	clc
	lda slope_y,x
	adc col_y
	sta floor_y
	jmp .uf_done
.uf_sn
	inx
	jmp .uf_s
.uf_done
	rts

sync_eye
	clc
	lda floor_y
	adc #EYE_HEIGHT
	sta cam_yh
	lda #0
	sta cam_yl
	rts

; ------------------------------------------------------------------
; solid_at — col_x/col_z blocked by crate, solid platform, or closed door?
; C=1 blocked
; ------------------------------------------------------------------
solid_at
	; crates — solid on Y overlap (not when on/above top or under)
	ldx #0
.sa_c
	cpx #MAP_NCRATES
	bcs .sa_p
	lda crate_room,x
	cmp room_idx
	bne .sa_cn
	lda crate_y,x
	sta box_y
	lda crate_sy,x
	sta box_sy
	jsr player_overlaps_y
	bcc .sa_cn
	lda crate_x,x
	sta box_x
	lda crate_z,x
	sta box_z
	lda crate_sx,x
	sta box_sx
	lda crate_sz,x
	sta box_sz
	jsr point_in_box_xz
	bcs .sa_yes
.sa_cn
	inx
	bne .sa_c
.sa_p
	; platforms — solid on Y overlap (plane as sy=0)
	ldx #0
.sa_pl
	cpx #MAP_NPLATS
	bcs .sa_d
	lda plat_solid,x
	beq .sa_pn
	lda plat_room,x
	cmp room_idx
	bne .sa_pn
	lda plat_y,x
	sta box_y
	lda #0
	sta box_sy
	jsr player_overlaps_y
	bcc .sa_pn
	lda plat_x,x
	sta box_x
	lda plat_z,x
	sta box_z
	lda plat_sx,x
	sta box_sx
	lda plat_sz,x
	sta box_sz
	jsr point_in_box_xz
	bcs .sa_yes
.sa_pn
	inx
	bne .sa_pl
.sa_d
	jmp door_blocks
.sa_yes
	sec
	rts

; ------------------------------------------------------------------
; col_in_room_y — col_x/col_z inside room Y (exclusive max). C=1 inside
; ------------------------------------------------------------------
col_in_room_y
	cpy #$ff
	beq .cir_no
	lda col_x
	cmp room_x,y
	bcc .cir_no
	clc
	lda room_x,y
	adc room_sx,y
	cmp col_x
	bcc .cir_no
	beq .cir_no
	lda col_z
	cmp room_z,y
	bcc .cir_no
	clc
	lda room_z,y
	adc room_sz,y
	cmp col_z
	bcc .cir_no
	beq .cir_no
	sec
	rts
.cir_no
	clc
	rts

; ------------------------------------------------------------------
; in_room_or_portal — col_x/col_z allowed for room_idx?
; Inside room AABB inset by PLAYER_R, or open door wall-hole (thin ±1).
; C=1 allowed
; ------------------------------------------------------------------
in_room_or_portal
	ldx room_idx
	lda col_x
	sec
	sbc #PLAYER_R
	bcc .irp_door
	cmp room_x,x
	bcc .irp_door
	clc
	lda room_x,x
	adc room_sx,x
	sec
	sbc #PLAYER_R
	cmp col_x
	bcc .irp_door
	beq .irp_door
	lda col_z
	sec
	sbc #PLAYER_R
	bcc .irp_door
	cmp room_z,x
	bcc .irp_door
	clc
	lda room_z,x
	adc room_sz,x
	sec
	sbc #PLAYER_R
	cmp col_z
	bcc .irp_door
	beq .irp_door
	sec
	rts
.irp_door
	jmp door_portal_ok

; ------------------------------------------------------------------
; pos_ok — cam would be ok at col_x/col_z
; ------------------------------------------------------------------
pos_ok
	jsr in_room_or_portal
	bcc .po_no
	jsr solid_at
	bcs .po_no
	sec
	rts
.po_no
	clc
	rts

; ------------------------------------------------------------------
; Horizontal move from IRQ hold-ms wish (8 units/s). Slide on X then Z.
; ------------------------------------------------------------------
apply_move_world
	lda $01
	pha
	lda #$34
	sta $01
	ldy yaw
	lda SINTAB,y
	sta rot0
	ldy yaw
	lda COSTAB,y
	sta rot1

	lda hold_fwd
	ora hold_fwd + 1
	beq .am_now
	lda hold_fwd
	sta vel_ms
	lda hold_fwd + 1
	sta vel_msh
	lda rot0
	jsr wish_add_x
	lda rot1
	jsr wish_add_z
.am_now
	lda hold_back
	ora hold_back + 1
	beq .am_nos
	lda hold_back
	sta vel_ms
	lda hold_back + 1
	sta vel_msh
	lda rot0
	jsr neg_a
	jsr wish_add_x
	lda rot1
	jsr neg_a
	jsr wish_add_z
.am_nos
	lda hold_strafer
	ora hold_strafer + 1
	beq .am_nod
	lda hold_strafer
	sta vel_ms
	lda hold_strafer + 1
	sta vel_msh
	lda rot1
	jsr wish_add_x
	lda rot0
	jsr neg_a
	jsr wish_add_z
.am_nod
	lda hold_strafel
	ora hold_strafel + 1
	beq .am_noa
	lda hold_strafel
	sta vel_ms
	lda hold_strafel + 1
	sta vel_msh
	lda rot1
	jsr neg_a
	jsr wish_add_x
	lda rot0
	jsr wish_add_z
.am_noa
	lda cam_xl
	sta rot0			; start 8.8 XZ (HITWALL if fully blocked)
	lda cam_xh
	sta rot1
	lda cam_zl
	sta rot2
	lda cam_zh
	sta dt_tmp
	lda cam_xl
	sta save_xl
	lda cam_xh
	sta save_xh
	lda cam_zl
	sta save_zl
	lda cam_zh
	sta save_zh

	clc
	lda cam_xl
	adc wish_dx
	sta cam_xl
	lda cam_xh
	adc wish_dxh
	sta cam_xh
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr pos_ok
	bcs .am_zx
	lda save_xl
	sta cam_xl
	lda save_xh
	sta cam_xh
.am_zx
	lda cam_xh
	sta save_xh
	lda cam_xl
	sta save_xl
	clc
	lda cam_zl
	adc wish_dz
	sta cam_zl
	lda cam_zh
	adc wish_dzh
	sta cam_zh
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr pos_ok
	bcs .am_done
	lda save_zl
	sta cam_zl
	lda save_zh
	sta cam_zh
.am_done
	pla
	sta $01
	lda wish_dx
	ora wish_dxh
	ora wish_dz
	ora wish_dzh
	beq .am_sw
	lda cam_xl
	cmp rot0
	bne .am_sw
	lda cam_xh
	cmp rot1
	bne .am_sw
	lda cam_zl
	cmp rot2
	bne .am_sw
	lda cam_zh
	cmp dt_tmp
	bne .am_sw
	lda #SOUND_HITWALL
	jsr play_sound
.am_sw
	jsr try_room_switch
	rts

; A = signed sintab → add (A * vel_ms)>>6 into wish X 8.8
wish_add_x
	jsr scale_vel_7
	clc
	lda wish_dx
	adc nlo
	sta wish_dx
	lda wish_dxh
	adc nhi
	sta wish_dxh
	rts

wish_add_z
	jsr scale_vel_7
	clc
	lda wish_dz
	adc nlo
	sta wish_dz
	lda wish_dzh
	adc nhi
	sta wish_dzh
	rts

; A signed, vel_ms:vel_msh → nlo:nhi = (A * vel) >> 6  (~8 units/s)
scale_vel_7
	sta scale_s
	bpl .svabs
	eor #$ff
	clc
	adc #1
.svabs
	sta hud_n			; |A|
	tay
	lda vel_ms
	jsr umul8j
	lda prod_l
	sta nlo
	lda prod_h
	sta nhi
	lda vel_msh
	beq .svsh
	ldy hud_n
	jsr umul8j			; |A| * vel_hi
	clc
	lda nhi
	adc prod_l
	sta nhi
	lda prod_h
	adc #0
	sta pp_tmp_h			; product bits 16–23
	ldx #6
.svsh24
	lsr pp_tmp_h
	ror nhi
	ror nlo
	dex
	bne .svsh24
	jmp .svsign
.svsh
	lda nhi
	ldx #6
.svsh16
	lsr
	ror nlo
	dex
	bne .svsh16
	sta nhi
.svsign
	lda scale_s
	bpl .svok
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.svok
	rts

neg_a
	eor #$ff
	clc
	adc #1
	rts

; ------------------------------------------------------------------
; Proximity: doors + switches (K) + automatic elevators
; ------------------------------------------------------------------
SW_USE_RANGE	= 4			; max XZ distance to switch AABB

try_proximity
	jsr try_door_proximity
	; K rising edge — one fire per press
	lda key_use
	bne .tp_kd
	sta key_use_was			; A = 0
	jmp .tp_el
.tp_kd
	lda key_use_was
	bne .tp_el			; still held
	lda #1
	sta key_use_was
	ldx #0
.tp_s
	cpx #MAP_NSWITCHES
	bcs .tp_el
	stx obj_i
	lda sw_room,x
	cmp room_idx
	bne .tp_sn
	jsr .prox_switch
	bcc .tp_sn
	ldy sw_elev,x
	tya
	tax
	jsr elev_activate
	bcs .tp_el
	lda #SOUND_SWITCH
	jsr play_sound
	jmp .tp_el			; one switch per press
.tp_sn
	ldx obj_i
	inx
	bne .tp_s
.tp_el
	jsr elev_try_auto
	jsr try_backpack_pickup
.tp_rts
	rts

; Walk-over backpacks: grant if not full / not already owned
try_backpack_pickup
	ldx #0
.tbp_lp
	cpx #MAP_NBACKPACKS
	bcs .tbp_rts
	stx obj_i
	lda bp_taken,x
	bne .tbp_n
	lda bp_room,x
	cmp room_idx
	bne .tbp_n
	lda bp_x,x
	sta box_x
	lda bp_y,x
	sta box_y
	lda bp_z,x
	sta box_z
	lda #BP_FOOT_SX
	sta box_sx
	lda #BP_FOOT_SY
	sta box_sy
	lda #BP_FOOT_SZ
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .tbp_n
	jsr player_overlaps_y
	bcc .tbp_n
	ldx obj_i
	jsr grant_backpack
	bcc .tbp_n
	ldx obj_i
	lda bp_type,x
	cmp #BP_HEALTH25
	beq .tbp_hp
	cmp #BP_HEALTH50
	beq .tbp_hp
	jsr hud_ammo
	lda #SOUND_GETAMMO
	bne .tbp_snd
.tbp_hp
	cmp #BP_HEALTH50
	beq .tbp_hp2
	lda #SOUND_HEALTH1
	bne .tbp_snd
.tbp_hp2
	lda #SOUND_HEALTH2
.tbp_snd
	ldx obj_i
	pha
	lda #1
	sta bp_taken,x
	pla
	jsr play_sound
.tbp_n
	ldx obj_i
	inx
	bne .tbp_lp
.tbp_rts
	; death-drop backpacks
	ldx #0
.tdp_lp
	cpx #MAP_NENEMIES
	bcs .tdp_rts
	stx obj_i
	lda drop_taken,x
	bne .tdp_n
	lda drop_room,x
	cmp room_idx
	bne .tdp_n
	lda drop_x,x
	sta box_x
	lda drop_y,x
	sta box_y
	lda drop_z,x
	sta box_z
	lda #BP_FOOT_SX
	sta box_sx
	lda #BP_FOOT_SY
	sta box_sy
	lda #BP_FOOT_SZ
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .tdp_n
	jsr player_overlaps_y
	bcc .tdp_n
	ldx obj_i
	lda drop_type,x
	jsr grant_bp_type
	bcc .tdp_n
	jsr hud_ammo
	ldx obj_i
	lda #1
	sta drop_taken,x
	lda #SOUND_GETAMMO
	jsr play_sound
.tdp_n
	ldx obj_i
	inx
	bne .tdp_lp
.tdp_rts
	rts

; X = backpack index; C=1 granted
grant_backpack
	lda bp_type,x
; A = BP_* type; C=1 granted
grant_bp_type
	cmp #BP_NTYPES
	bcc .gb_go
	clc
	rts
.gb_go
	tay
	lda gb_lo,y
	sta rot0
	lda gb_hi,y
	sta rot1
	jmp (rot0)

gb_lo
	!byte <gb_shells, <gb_nailgun, <gb_nails, <gb_grenlaunch
	!byte <gb_grenades, <gb_hp25, <gb_hp50, <gb_shells5
gb_hi
	!byte >gb_shells, >gb_nailgun, >gb_nails, >gb_grenlaunch
	!byte >gb_grenades, >gb_hp25, >gb_hp50, >gb_shells5

gb_hp25
	lda player_hp
	cmp #PLAYER_HP_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #HP_PACK_25
	jmp gb_hp_clamp
gb_hp50
	lda player_hp
	cmp #PLAYER_HP_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #HP_PACK_50
gb_hp_clamp
	bcs gb_hp_cap
	cmp #PLAYER_HP_MAX
	bcc gb_hp_ok
	beq gb_hp_ok
gb_hp_cap
	lda #PLAYER_HP_MAX
gb_hp_ok
	sta player_hp
	sec
	rts
gb_shells
	lda #AMMO_SHELLS_BOX
	bne gb_add_shells
gb_shells5
	lda #AMMO_SHELLS_DEATH
gb_add_shells
	sta rot2
	lda ammo_shells
	cmp #AMMO_SHELLS_MAX
	bcc +
	jmp gb_no
+
	clc
	adc rot2
	bcs gb_shell_cap
	cmp #AMMO_SHELLS_MAX
	bcc gb_shell_ok
	beq gb_shell_ok
gb_shell_cap
	lda #AMMO_SHELLS_MAX
gb_shell_ok
	sta ammo_shells
	sec
	rts
gb_nails
	lda ammo_nails
	cmp #AMMO_NAILS_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #AMMO_NAILS_BOX
	bcs gb_nail_cap
	cmp #AMMO_NAILS_MAX
	bcc gb_nail_ok
	beq gb_nail_ok
gb_nail_cap
	lda #AMMO_NAILS_MAX
gb_nail_ok
	sta ammo_nails
	sec
	rts
gb_grenades
	lda ammo_grenades
	cmp #AMMO_GRENADES_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #AMMO_GRENADES_BOX
	bcs gb_gren_cap
	cmp #AMMO_GRENADES_MAX
	bcc gb_gren_ok
	beq gb_gren_ok
gb_gren_cap
	lda #AMMO_GRENADES_MAX
gb_gren_ok
	sta ammo_grenades
	sec
	rts
gb_nailgun
	lda have_wpn
	and #HAVE_NAIL
	beq gb_ng_new
	jmp gb_no
gb_ng_new
	lda have_wpn
	ora #HAVE_NAIL
	sta have_wpn
	lda ammo_nails
	clc
	adc #AMMO_NAILS_GUN
	bcs gb_ng_cap
	cmp #AMMO_NAILS_MAX
	bcc gb_ng_ok
	beq gb_ng_ok
gb_ng_cap
	lda #AMMO_NAILS_MAX
gb_ng_ok
	sta ammo_nails
	ldx #WPN_NAIL
	jsr switch_weapon
	sec
	rts
gb_grenlaunch
	lda have_wpn
	and #HAVE_GREN
	beq gb_gl_new
	jmp gb_no
gb_gl_new
	lda have_wpn
	ora #HAVE_GREN
	sta have_wpn
	lda ammo_grenades
	clc
	adc #AMMO_GRENADES_GUN
	bcs gb_gl_cap
	cmp #AMMO_GRENADES_MAX
	bcc gb_gl_ok
	beq gb_gl_ok
gb_gl_cap
	lda #AMMO_GRENADES_MAX
gb_gl_ok
	sta ammo_grenades
	ldx #WPN_GREN
	jsr switch_weapon
	sec
	rts
gb_no
	clc
	rts

; X=switch; C=1 if within SW_USE_RANGE of pad XZ, Y overlaps, facing the face
.prox_switch
	stx obj_i
	lda sw_x,x
	sta box_x
	lda sw_z,x
	sta box_z
	lda sw_sx,x
	sta box_sx
	lda sw_sz,x
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr near_box_xz
	bcc .ps_no
	ldx obj_i
	lda sw_y,x
	sta box_y
	lda sw_sy,x
	sta box_sy
	jsr player_overlaps_y
	bcc .ps_no
	ldx obj_i
	jsr .switch_facing
	ldx obj_i
	rts
.ps_no
	clc
	ldx obj_i
	rts

; col_x/col_z within SW_USE_RANGE of [box_x,box_x+sx) × [box_z,box_z+sz)
; Chebyshev: each axis distance to AABB ≤ SW_USE_RANGE. C=1 near.
near_box_xz
	lda col_x
	cmp box_x
	bcc .nb_xlo
	clc
	lda box_x
	adc box_sx
	sta col_y
	lda col_x
	cmp col_y
	bcs .nb_xhi
	lda #0
	beq .nb_xd
.nb_xlo
	lda box_x
	sec
	sbc col_x
	jmp .nb_xd
.nb_xhi
	lda col_x
	sec
	sbc col_y
.nb_xd
	cmp #SW_USE_RANGE + 1
	bcs .nb_no
	lda col_z
	cmp box_z
	bcc .nb_zlo
	clc
	lda box_z
	adc box_sz
	sta col_y
	lda col_z
	cmp col_y
	bcs .nb_zhi
	lda #0
	beq .nb_zd
.nb_zlo
	lda box_z
	sec
	sbc col_z
	jmp .nb_zd
.nb_zhi
	lda col_z
	sec
	sbc col_y
.nb_zd
	cmp #SW_USE_RANGE + 1
	bcs .nb_no
	sec
	rts
.nb_no
	clc
	rts

; X=switch; C=1 if yaw within ±90° of sw_face (0=+Z, 64=+X, 128=-Z, 192=-X)
.switch_facing
	lda sw_face,x
	cmp #FACE_PX
	bcs .sf_x
	cmp #FACE_MZ
	beq .sf_mz
	; FACE_PZ: yaw < 64 or >= 192
	lda yaw
	cmp #64
	bcc .sf_yes
	cmp #192
	bcs .sf_yes
	clc
	rts
.sf_mz
	lda yaw
	cmp #64
	bcc .sf_no
	cmp #192
	bcc .sf_yes
.sf_no
	clc
	rts
.sf_x
	cmp #FACE_MX
	beq .sf_mx
	; FACE_PX: 0..127
	lda yaw
	cmp #128
	bcc .sf_yes
	clc
	rts
.sf_mx
	lda yaw
	cmp #128
	bcs .sf_yes
	clc
	rts
.sf_yes
	sec
	rts

; ------------------------------------------------------------------
update_message
	lda #0
	sta msg_on
	ldx #0
.um
	cpx #MAP_NTRIGS
	bcs .um_rts
	lda tr_room,x
	cmp room_idx
	bne .um_n
	lda tr_x,x
	sta box_x
	lda tr_y,x
	sta box_y
	lda tr_z,x
	sta box_z
	lda tr_sx,x
	sta box_sx
	lda tr_sy,x
	sta box_sy
	lda tr_sz,x
	sta box_sz
	lda cam_xh
	cmp box_x
	bcc .um_n
	clc
	lda box_x
	adc box_sx
	cmp cam_xh
	bcc .um_n
	beq .um_n
	lda cam_zh
	cmp box_z
	bcc .um_n
	clc
	lda box_z
	adc box_sz
	cmp cam_zh
	bcc .um_n
	beq .um_n
	lda #1
	sta msg_on
	lda tr_text_off,x
	sta msg_off
	rts
.um_n
	inx
	bne .um
.um_rts
	rts
