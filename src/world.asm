; Room physics, proximity triggers, floor / eye sync
!zone world

; ------------------------------------------------------------------
world_init
	lda spawn_room
	sta room_idx
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
	jsr update_floor
	jsr sync_eye
	lda #$ff
	sta palette_room
	jsr apply_room_palette
	rts

; ------------------------------------------------------------------
; player_in_door_y — Y=door index; C=1 if player XZ (and approx Y) in door AABB
; ------------------------------------------------------------------
player_in_door_y
	lda cam_xh
	cmp door_x,y
	bcc .pid_no
	clc
	lda door_x,y
	adc door_sx,y
	cmp cam_xh
	bcc .pid_no
	beq .pid_no
	lda cam_zh
	cmp door_z,y
	bcc .pid_no
	clc
	lda door_z,y
	adc door_sz,y
	cmp cam_zh
	bcc .pid_no
	beq .pid_no
	sec
	rts
.pid_no
	clc
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
; player_overlaps_y — [feet, eye] vs [box_y, box_y+box_sy); C=1 overlap
; ------------------------------------------------------------------
player_overlaps_y
	clc
	lda box_y
	adc box_sy
	sta col_y			; exclusive max
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcs .poy_no			; feet >= y+sy
	lda box_y
	cmp cam_yh
	bcs .poy_no			; y >= eye
	sec
	rts
.poy_no
	clc
	rts

; ------------------------------------------------------------------
update_floor
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
	sta floor_y
.uf_cn
	inx
	bne .uf_c
.uf_p
	; platforms (walkable if solid)
	ldx #0
.uf_pl
	cpx #MAP_NPLATS
	bcs .uf_e0
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
	sta floor_y
.uf_pn
	inx
	bne .uf_pl
.uf_e0
	; elevators in this room
	ldx #0
.uf_e
	cpx #MAP_NELEVS
	bcs .uf_slope
	lda elev_room,x
	cmp room_idx
	bne .uf_en
	lda elev_x,x
	sta box_x
	lda elev_z,x
	sta box_z
	lda elev_sx,x
	sta box_sx
	lda elev_sz,x
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .uf_en
	; on elevator footprint — floor = elev_y + sy
	clc
	lda elev_y,x
	adc elev_sy,x
	sta floor_y
	stx pl_on_elev
.uf_en
	inx
	bne .uf_e
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
	; crates — solid unless standing on/above top
	ldx #0
.sa_c
	cpx #MAP_NCRATES
	bcs .sa_p
	lda crate_room,x
	cmp room_idx
	bne .sa_cn
	sec
	lda cam_yh
	sbc #EYE_HEIGHT
	sta col_y			; feet y
	clc
	lda crate_y,x
	adc crate_sy,x
	cmp col_y
	beq .sa_cn			; feet at top — walkable
	bcc .sa_cn			; feet above top
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
	; platforms — solid unless standing on/above plane
	ldx #0
.sa_pl
	cpx #MAP_NPLATS
	bcs .sa_d
	lda plat_solid,x
	beq .sa_pn
	lda plat_room,x
	cmp room_idx
	bne .sa_pn
	sec
	lda cam_yh
	sbc #EYE_HEIGHT
	sta col_y			; feet y
	lda plat_y,x
	cmp col_y
	beq .sa_pn			; feet at plane — walkable
	bcc .sa_pn			; feet above
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
	; closed doors overlapping this room (open != 0 is a hole)
	ldx #0
.sa_door
	cpx #MAP_NDOORS
	bcs .sa_no
	lda door_open,x
	bne .sa_dn			; any open — not solid
	lda door_ra,x
	cmp room_idx
	beq .sa_dchk
	lda door_rb,x
	cmp room_idx
	bne .sa_dn
.sa_dchk
	lda door_x,x
	sta box_x
	lda door_z,x
	sta box_z
	lda door_sx,x
	sta box_sx
	lda door_sz,x
	sta box_sz
	jsr point_in_box_xz
	bcs .sa_yes
.sa_dn
	inx
	bne .sa_door
.sa_no
	clc
	rts
.sa_yes
	sec
	rts

; ------------------------------------------------------------------
; door_other_room — X=door; A=linked room that isn't room_idx ($ff none)
; ------------------------------------------------------------------
door_other_room
	lda door_ra,x
	cmp room_idx
	bne .dor_a
	lda door_rb,x
	rts
.dor_a
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
; door_hole_hit — X=door; col_x/col_z in wide opening, thin axis ±1
; C=1 inside hole (exclusive max)
; ------------------------------------------------------------------
door_hole_hit
	lda door_face,x
	cmp #FACE_PX
	bcs .dhh_x
	; Z-facing: wide=X unexpanded, thin=Z ±1
	lda door_x,x
	sta box_x
	lda door_sx,x
	sta box_sx
	lda door_z,x
	beq .dhh_z0
	sec
	sbc #1
	sta box_z
	clc
	lda door_sz,x
	adc #2
	sta box_sz
	jmp point_in_box_xz
.dhh_z0
	sta box_z
	clc
	lda door_sz,x
	adc #1
	sta box_sz
	jmp point_in_box_xz
.dhh_x
	lda door_z,x
	sta box_z
	lda door_sz,x
	sta box_sz
	lda door_x,x
	beq .dhh_x0
	sec
	sbc #1
	sta box_x
	clc
	lda door_sx,x
	adc #2
	sta box_sx
	jmp point_in_box_xz
.dhh_x0
	sta box_x
	clc
	lda door_sx,x
	adc #1
	sta box_sx
	jmp point_in_box_xz

; ------------------------------------------------------------------
; in_room_or_portal — col_x/col_z allowed for room_idx?
; Inside room AABB, or in an open door wall-hole (wide axes, thin ±1).
; C=1 allowed
; ------------------------------------------------------------------
in_room_or_portal
	ldx room_idx
	lda col_x
	cmp room_x,x
	bcc .irp_door
	clc
	lda room_x,x
	adc room_sx,x
	cmp col_x
	bcc .irp_door
	beq .irp_door
	lda col_z
	cmp room_z,x
	bcc .irp_door
	clc
	lda room_z,x
	adc room_sz,x
	cmp col_z
	bcc .irp_door
	beq .irp_door
	sec
	rts
.irp_door
	ldx #0
.irp_d
	cpx #MAP_NDOORS
	bcs .irp_no
	lda door_open,x
	beq .irp_dn
	lda door_ra,x
	cmp room_idx
	beq .irp_dchk
	lda door_rb,x
	cmp room_idx
	bne .irp_dn
.irp_dchk
	jsr door_hole_hit
	bcs .irp_yes
.irp_dn
	inx
	bne .irp_d
.irp_no
	clc
	rts
.irp_yes
	sec
	rts

; ------------------------------------------------------------------
; try_room_switch — in an open door AABB: snap 1 unit into the other
; room and switch. Else switch if already inside a neighbour room.
; ------------------------------------------------------------------
try_room_switch
	ldx #0
.trs
	cpx #MAP_NDOORS
	bcs .trs_rts
	lda door_open,x
	beq .trs_n
	txa
	tay
	jsr player_in_door_y
	bcc .trs_nb
	jsr door_push_through
	rts
.trs_nb
	ldy door_ra,x
	jsr .trs_inside
	bcs .trs_rts
	ldy door_rb,x
	jsr .trs_inside
	bcs .trs_rts
.trs_n
	inx
	bne .trs
.trs_rts
	rts
.trs_inside
	cpy room_idx
	beq .trs_no
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr col_in_room_y
	bcc .trs_no
	sty room_idx
	sec
	rts
.trs_no
	clc
	rts

; X=door, player in its AABB. Place 1 unit inside the other room.
door_push_through
	jsr door_other_room
	cmp #$ff
	beq .dpt_rts
	sta proc_tmp0
	lda door_face,x
	cmp #FACE_PX
	bcs .dpt_x
	ldy proc_tmp0
	lda room_z,y
	ldy room_idx
	cmp room_z,y
	bcc .dpt_zd
	ldy proc_tmp0
	lda room_z,y
	sta cam_zh
	lda #0
	sta cam_zl
	jmp .dpt_sw
.dpt_zd
	ldy proc_tmp0
	clc
	lda room_z,y
	adc room_sz,y
	sec
	sbc #1
	sta cam_zh
	lda #0
	sta cam_zl
	jmp .dpt_sw
.dpt_x
	ldy proc_tmp0
	lda room_x,y
	ldy room_idx
	cmp room_x,y
	bcc .dpt_xd
	ldy proc_tmp0
	lda room_x,y
	sta cam_xh
	lda #0
	sta cam_xl
	jmp .dpt_sw
.dpt_xd
	ldy proc_tmp0
	clc
	lda room_x,y
	adc room_sx,y
	sec
	sbc #1
	sta cam_xh
	lda #0
	sta cam_xl
.dpt_sw
	lda proc_tmp0
	sta room_idx
.dpt_rts
	rts

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
; Horizontal move from IRQ hold-ms wish (4 units/s). Slide on X then Z.
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

; A = signed sintab → add (A * vel_ms)>>7 into wish X 8.8
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

; A signed, vel_ms:vel_msh → nlo:nhi = (A * vel) >> 7
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
	ldx #7
.svsh24
	lsr pp_tmp_h
	ror nhi
	ror nlo
	dex
	bne .svsh24
	jmp .svsign
.svsh
	lda nhi
	ldx #7
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
; Proximity: doors + switches + automatic elevators
; ------------------------------------------------------------------
try_proximity
	; doors
	ldx #0
.tp_d
	cpx #MAP_NDOORS
	bcs .tp_sw
	lda door_ra,x
	cmp room_idx
	beq .tp_dnear
	lda door_rb,x
	cmp room_idx
	bne .tp_dn
.tp_dnear
	jsr .prox_door
	bcc .tp_dn
	jsr door_activate
	ldx obj_i
.tp_dn
	inx
	bne .tp_d
.tp_sw
	ldx #0
.tp_s
	cpx #MAP_NSWITCHES
	bcs .tp_el
	stx obj_i
	lda sw_room,x
	cmp room_idx
	bne .tp_sleave
	jsr .prox_switch
	bcc .tp_sleave
	lda sw_latched,x
	bne .tp_sn			; still held — one fire per press
	lda #1
	sta sw_latched,x
	ldy sw_elev,x
	tya
	tax
	jsr elev_activate
	bcs .tp_sn
	lda #SOUND_SWITCH
	jsr play_sound
	jmp .tp_sn
.tp_sleave
	ldx obj_i
	lda #0
	sta sw_latched,x
.tp_sn
	ldx obj_i
	inx
	bne .tp_s
.tp_el
	; automatic elevators
	ldx #0
.tp_e
	cpx #MAP_NELEVS
	bcs .tp_rts
	lda elev_type,x
	cmp #ELEV_TYPE_AUTO
	bne .tp_en
	lda elev_room,x
	cmp room_idx
	bne .tp_en
	cpx pl_on_elev
	bne .tp_en
	jsr elev_activate
.tp_en
	inx
	bne .tp_e
.tp_rts
	rts

; X=door; C=1 if in doorway width, thin axis ±DOOR_PROX, and Y overlaps
.prox_door
	stx obj_i
	lda door_face,x
	cmp #FACE_PX
	bcs .pd_x
	; Z-facing: wide=X unexpanded, thin=Z ±DOOR_PROX
	lda door_x,x
	sta box_x
	lda door_sx,x
	sta box_sx
	lda door_z,x
	sec
	sbc #DOOR_PROX
	bcs +
	lda #0
+
	sta box_z
	clc
	lda door_sz,x
	adc #DOOR_PROX
	adc #DOOR_PROX
	sta box_sz
	jmp .pd_xz
.pd_x
	lda door_z,x
	sta box_z
	lda door_sz,x
	sta box_sz
	lda door_x,x
	sec
	sbc #DOOR_PROX
	bcs +
	lda #0
+
	sta box_x
	clc
	lda door_sx,x
	adc #DOOR_PROX
	adc #DOOR_PROX
	sta box_sx
.pd_xz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .pd_no
	ldx obj_i
	lda door_y,x
	sta box_y
	lda door_sy,x
	sta box_sy
	jsr player_overlaps_y
	ldx obj_i
	rts
.pd_no
	clc
	ldx obj_i
	rts

; X=switch; C=1 if in pad XZ, Y overlaps, facing the face, wish into it
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
	jsr point_in_box_xz
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
	bcc .ps_no
	jsr .switch_push
	ldx obj_i
	rts
.ps_no
	clc
	ldx obj_i
	rts

; X=switch; C=1 if yaw within ±45° of sw_face (0=+Z, 64=+X, 128=-Z, 192=-X)
.switch_facing
	lda sw_face,x
	cmp #FACE_PX
	bcs .sf_x
	cmp #FACE_MZ
	beq .sf_mz
	; FACE_PZ: yaw < 32 or >= 224
	lda yaw
	cmp #32
	bcc .sf_yes
	cmp #224
	bcs .sf_yes
	clc
	rts
.sf_mz
	lda yaw
	cmp #96
	bcc .sf_no
	cmp #160
	bcc .sf_yes
.sf_no
	clc
	rts
.sf_x
	cmp #FACE_MX
	beq .sf_mx
	; FACE_PX: 32..95
	lda yaw
	cmp #32
	bcc .sf_no
	cmp #96
	bcc .sf_yes
	clc
	rts
.sf_mx
	lda yaw
	cmp #160
	bcc .sf_no
	cmp #224
	bcc .sf_yes
	clc
	rts
.sf_yes
	sec
	rts

; X=switch; C=1 if this frame's wish points into the switch face
.switch_push
	lda sw_face,x
	cmp #FACE_PX
	bcs .sp_x
	cmp #FACE_MZ
	beq .sp_mz
	; FACE_PZ: +Z
	lda wish_dzh
	bmi .sp_no
	ora wish_dz
	beq .sp_no
	sec
	rts
.sp_mz
	lda wish_dzh
	bmi .sp_yes
.sp_no
	clc
	rts
.sp_yes
	sec
	rts
.sp_x
	cmp #FACE_MX
	beq .sp_mx
	; FACE_PX: +X
	lda wish_dxh
	bmi .sp_no
	ora wish_dx
	beq .sp_no
	sec
	rts
.sp_mx
	lda wish_dxh
	bmi .sp_yes
	clc
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
