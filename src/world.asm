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
	bcs .uf_e0
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
	bcs .uf_done
	lda slope_room,x
	cmp room_idx
	bne .uf_sn
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
	bcc .uf_sn
	; height = slope_y + (local >> 1)
	lda slope_axis,x
	bne .uf_sz
	; axis X
	sec
	lda cam_xh
	sbc slope_x,x
	sta col_y			; local
	lda slope_dir,x
	bne .uf_sx_p
	; dir -1: local' = sx-1-local
	lda slope_sx,x
	sec
	sbc #1
	sec
	sbc col_y
	sta col_y
.uf_sx_p
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
	sbc #1
	sec
	sbc col_y
	sta col_y
.uf_sz_p
	lsr col_y
	clc
	lda slope_y,x
	adc col_y
	sta floor_y
	jmp .uf_done
.uf_sn
	inx
	bne .uf_s
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
; solid_at — col_x/col_z blocked by crate or closed door in active room?
; C=1 blocked
; ------------------------------------------------------------------
solid_at
	; crates — solid unless standing on/above top
	ldx #0
.sa_c
	cpx #MAP_NCRATES
	bcs .sa_d
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
.sa_d
	; closed / partially open doors overlapping this room
	ldx #0
.sa_door
	cpx #MAP_NDOORS
	bcs .sa_no
	lda door_open,x
	cmp door_sy,x
	bcs .sa_dn			; fully open — not solid
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
; in_room_or_portal — col_x/col_z allowed for room_idx?
; Inside room AABB, or in open door leading to/from this room
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
	; open door volumes
	ldx #0
.irp_d
	cpx #MAP_NDOORS
	bcs .irp_no
	lda door_open,x
	cmp door_sy,x
	bcc .irp_dn
	lda door_ra,x
	cmp room_idx
	beq .irp_dchk
	lda door_rb,x
	cmp room_idx
	bne .irp_dn
.irp_dchk
	lda door_x,x
	sta box_x
	lda door_z,x
	sta box_z
	lda door_sx,x
	sta box_sx
	lda door_sz,x
	sta box_sz
	jsr point_in_box_xz
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
; try_room_switch — if in open door and inside neighbour, switch
; ------------------------------------------------------------------
try_room_switch
	ldx #0
.trs
	cpx #MAP_NDOORS
	bcs .trs_rts
	lda door_open,x
	cmp door_sy,x
	bcc .trs_n
	ldy door_ra,x
	jsr .trs_try
	ldy door_rb,x
	cpy #$ff
	beq .trs_n
	jsr .trs_try
.trs_n
	inx
	bne .trs
.trs_rts
	rts
.trs_try
	cpy room_idx
	beq .trs_tr
	; if player inside room Y
	cpy #$ff
	beq .trs_tr
	lda cam_xh
	cmp room_x,y
	bcc .trs_tr
	clc
	lda room_x,y
	adc room_sx,y
	cmp cam_xh
	bcc .trs_tr
	beq .trs_tr
	lda cam_zh
	cmp room_z,y
	bcc .trs_tr
	clc
	lda room_z,y
	adc room_sz,y
	cmp cam_zh
	bcc .trs_tr
	beq .trs_tr
	sty room_idx
.trs_tr
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
	beq .am_now
	sta vel_ms
	lda rot0
	jsr wish_add_x
	lda rot1
	jsr wish_add_z
.am_now
	lda hold_back
	beq .am_nos
	sta vel_ms
	lda rot0
	jsr neg_a
	jsr wish_add_x
	lda rot1
	jsr neg_a
	jsr wish_add_z
.am_nos
	lda hold_strafer
	beq .am_nod
	sta vel_ms
	lda rot1
	jsr wish_add_x
	lda rot0
	jsr neg_a
	jsr wish_add_z
.am_nod
	lda hold_strafel
	beq .am_noa
	sta vel_ms
	lda rot1
	jsr neg_a
	jsr wish_add_x
	lda rot0
	jsr wish_add_z
.am_noa
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

; A signed, vel_ms → nlo:nhi = (A * vel_ms) >> 7
scale_vel_7
	sta scale_s
	bpl .svabs
	eor #$ff
	clc
	adc #1
.svabs
	tay
	lda vel_ms
	jsr umul8j
	lda prod_h
	ldx #7
.svsh
	lsr
	ror prod_l
	dex
	bne .svsh
	sta nhi
	lda prod_l
	sta nlo
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
	bne .tp_sn
	jsr .prox_switch
	bcc .tp_sn
	ldy sw_elev,x
	tya
	tax
	jsr elev_activate
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

; X=door; C=1 if within PROX_DIST of door AABB (expanded)
.prox_door
	stx obj_i
	lda door_x,x
	sec
	sbc #PROX_DIST
	bcs +
	lda #0
+
	sta box_x
	lda door_z,x
	sec
	sbc #PROX_DIST
	bcs +
	lda #0
+
	sta box_z
	clc
	lda door_sx,x
	adc #PROX_DIST
	adc #PROX_DIST
	sta box_sx
	clc
	lda door_sz,x
	adc #PROX_DIST
	adc #PROX_DIST
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	ldx obj_i
	rts

.prox_switch
	stx obj_i
	lda sw_x,x
	sec
	sbc #PROX_DIST
	bcs +
	lda #0
+
	sta box_x
	lda sw_z,x
	sec
	sbc #PROX_DIST
	bcs +
	lda #0
+
	sta box_z
	clc
	lda sw_sx,x
	adc #PROX_DIST
	adc #PROX_DIST
	sta box_sx
	clc
	lda sw_sz,x
	adc #PROX_DIST
	adc #PROX_DIST
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	ldx obj_i
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
