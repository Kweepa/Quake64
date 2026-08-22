; Doors — room-relative orientation, collision, portals, proximity
!zone door

!if MAP_NDOORS > DOOR_MAX {
	!error "MAP_NDOORS exceeds DOOR_MAX"
}

; ------------------------------------------------------------------
; set_room_idx — A = room; orients connected doors toward this room
; ------------------------------------------------------------------
set_room_idx
	sta room_idx
orient_doors_for_room
	ldx #0
.odf
	cpx #MAP_NDOORS
	bcs .odf_rts
	jsr orient_one_door
	inx
	bne .odf
.odf_rts
	rts

; X = door index; copy canonical AABB, face = nearer plane to room_idx
orient_one_door
	lda door_x,x
	sta door_vx,x
	lda door_z,x
	sta door_vz,x
	lda door_sx,x
	sta door_vsx,x
	lda door_sz,x
	sta door_vsz,x
	lda door_face,x
	sta door_vface,x
	lda door_ra,x
	cmp room_idx
	beq .oo_go
	lda door_rb,x
	cmp room_idx
	beq .oo_go
	rts
.oo_go
	lda door_sz,x
	cmp door_sx,x
	bcc .oo_z			; sz < sx → Z slab
	beq .oo_z
	jmp .oo_x
.oo_z
	lda room_idx
	jsr room_mul3
	tay
	jsr .oo_pickz
	lda rc_sz,y
	lsr
	clc
	adc rc_z,y
	sta pv0				; collider Z centre
	lda pv0
	sec
	sbc door_z,x
	jsr .oo_abs
	sta pv1				; dist to z0
	clc
	lda door_z,x
	adc door_sz,x
	sta pv2				; z1
	lda pv0
	sec
	sbc pv2
	jsr .oo_abs
	cmp pv1
	bcc .oo_pz			; dist1 < dist0
	lda #FACE_MZ
	sta door_vface,x
	rts
.oo_pz
	lda #FACE_PZ
	sta door_vface,x
	rts
.oo_x
	lda room_idx
	jsr room_mul3
	tay
	jsr .oo_pickx
	lda rc_sx,y
	lsr
	clc
	adc rc_x,y
	sta pv0
	lda pv0
	sec
	sbc door_x,x
	jsr .oo_abs
	sta pv1
	clc
	lda door_x,x
	adc door_sx,x
	sta pv2
	lda pv0
	sec
	sbc pv2
	jsr .oo_abs
	cmp pv1
	bcc .oo_px
	lda #FACE_MX
	sta door_vface,x
	rts
.oo_px
	lda #FACE_PX
	sta door_vface,x
.oo_rts
	rts

; A = signed difference (C from SBC); |A|
.oo_abs
	bcs .oo_ap
	eor #$ff
	clc
	adc #1
.oo_ap
	rts

; Y = collider 0. Prefer overlap, else first non-empty. Y = chosen.
.oo_pickz
	jsr .oo_tryz
	bcs .oo_pr
	jmp .oo_first
.oo_pickx
	jsr .oo_tryx
	bcs .oo_pr
.oo_first
	ldy proc_tmp5
	lda rc_sx,y
	bne .oo_pr
	iny
	lda rc_sx,y
	bne .oo_pr
	iny
.oo_pr
	rts

.oo_tryz
	ldy proc_tmp5
	jsr .oo_z1
	bcs .oo_th
	iny
	jsr .oo_z1
	bcs .oo_th
	iny
.oo_z1
	lda rc_sx,y
	beq .oo_tn
	jsr .oo_ovx
	rts
.oo_tryx
	ldy proc_tmp5
	jsr .oo_x1
	bcs .oo_th
	iny
	jsr .oo_x1
	bcs .oo_th
	iny
.oo_x1
	lda rc_sx,y
	beq .oo_tn
	jsr .oo_ovz
	rts
.oo_tn
	clc
.oo_th
	rts

; C=1 door X overlaps collider Y
.oo_ovx
	clc
	lda rc_x,y
	adc rc_sx,y
	cmp door_x,x
	beq .oo_ov_no
	bcc .oo_ov_no
	clc
	lda door_x,x
	adc door_sx,x
	cmp rc_x,y
	beq .oo_ov_no
	bcc .oo_ov_no
	sec
	rts
.oo_ovz
	clc
	lda rc_z,y
	adc rc_sz,y
	cmp door_z,x
	beq .oo_ov_no
	bcc .oo_ov_no
	clc
	lda door_z,x
	adc door_sz,x
	cmp rc_z,y
	beq .oo_ov_no
	bcc .oo_ov_no
	sec
	rts
.oo_ov_no
	clc
	rts

; ------------------------------------------------------------------
; player_in_door_y — Y=door index; C=1 if player XZ in door AABB
; ------------------------------------------------------------------
player_in_door_y
	lda cam_xh
	cmp door_vx,y
	bcc .pid_no
	clc
	lda door_vx,y
	adc door_vsx,y
	cmp cam_xh
	bcc .pid_no
	beq .pid_no
	lda cam_zh
	cmp door_vz,y
	bcc .pid_no
	clc
	lda door_vz,y
	adc door_vsz,y
	cmp cam_zh
	bcc .pid_no
	beq .pid_no
	sec
	rts
.pid_no
	clc
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
; door_front — X=door; C=1 if camera is in front of (or on) the door plane
; ------------------------------------------------------------------
door_front
	lda door_vface,x
	cmp #FACE_PX
	bcs .df_x
	cmp #FACE_MZ
	beq .df_mz
	; FACE_PZ: plane at vz+vsz; front if cam_zh >= plane
	clc
	lda door_vz,x
	adc door_vsz,x
	sta pv0
	lda cam_zh
	cmp pv0
	rts
.df_mz
	; FACE_MZ: plane at vz; front if cam_zh <= plane
	lda door_vz,x
	cmp cam_zh
	rts
.df_x
	cmp #FACE_MX
	beq .df_mx
	; FACE_PX: plane at vx+vsx; front if cam_xh >= plane
	clc
	lda door_vx,x
	adc door_vsx,x
	sta pv0
	lda cam_xh
	cmp pv0
	rts
.df_mx
	; FACE_MX: plane at vx; front if cam_xh <= plane
	lda door_vx,x
	cmp cam_xh
	rts

; ------------------------------------------------------------------
; door_blocks — col_x/col_z vs closed door in this room. C=1 blocked
; ------------------------------------------------------------------
door_blocks
	ldx #0
.db
	cpx #MAP_NDOORS
	bcs .db_no
	lda door_open,x
	bne .db_n			; any open — not solid
	lda door_ra,x
	cmp room_idx
	beq .db_chk
	lda door_rb,x
	cmp room_idx
	bne .db_n
.db_chk
	lda door_vx,x
	sta box_x
	lda door_vz,x
	sta box_z
	lda door_vsx,x
	sta box_sx
	lda door_vsz,x
	sta box_sz
	jsr point_in_box_xz
	bcs .db_yes
.db_n
	inx
	bne .db
.db_no
	clc
	rts
.db_yes
	sec
	rts

; ------------------------------------------------------------------
; door_hole_hit — X=door; col_x/col_z in wide opening, thin axis ±1
; C=1 inside hole (exclusive max)
; ------------------------------------------------------------------
door_hole_hit
	lda door_vface,x
	cmp #FACE_PX
	bcs .dhh_x
	; Z-facing: wide=X unexpanded, thin=Z ±1
	lda door_vx,x
	sta box_x
	lda door_vsx,x
	sta box_sx
	lda door_vz,x
	beq .dhh_z0
	sec
	sbc #1
	sta box_z
	clc
	lda door_vsz,x
	adc #2
	sta box_sz
	jmp point_in_box_xz
.dhh_z0
	lda door_vz,x
	sta box_z
	clc
	lda door_vsz,x
	adc #1
	sta box_sz
	jmp point_in_box_xz
.dhh_x
	lda door_vz,x
	sta box_z
	lda door_vsz,x
	sta box_sz
	lda door_vx,x
	beq .dhh_x0
	sec
	sbc #1
	sta box_x
	clc
	lda door_vsx,x
	adc #2
	sta box_sx
	jmp point_in_box_xz
.dhh_x0
	lda door_vx,x
	sta box_x
	clc
	lda door_vsx,x
	adc #1
	sta box_sx
	jmp point_in_box_xz

; ------------------------------------------------------------------
; door_portal_ok — col_x/col_z in an open door hole of room_idx? C=1 yes
; ------------------------------------------------------------------
door_portal_ok
	ldx #0
.dpo
	cpx #MAP_NDOORS
	bcs .dpo_no
	lda door_open,x
	beq .dpo_n
	lda door_ra,x
	cmp room_idx
	beq .dpo_chk
	lda door_rb,x
	cmp room_idx
	bne .dpo_n
.dpo_chk
	jsr door_hole_hit
	bcs .dpo_yes
.dpo_n
	inx
	bne .dpo
.dpo_no
	clc
	rts
.dpo_yes
	sec
	rts

; ------------------------------------------------------------------
; try_room_switch — if an open door's other room contains the player, switch
; ------------------------------------------------------------------
try_room_switch
	ldx #0
.trs
	cpx #MAP_NDOORS
	bcs .trs_rts
	lda door_open,x
	beq .trs_n
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
	tya
	jsr set_room_idx
	sec
	rts
.trs_no
	clc
	rts

; ------------------------------------------------------------------
; try_door_proximity — auto-open if in front trigger box
; ------------------------------------------------------------------
try_door_proximity
	ldx #0
.tdp
	cpx #MAP_NDOORS
	bcs .tdp_rts
	lda door_ra,x
	cmp room_idx
	beq .tdp_near
	lda door_rb,x
	cmp room_idx
	bne .tdp_n
.tdp_near
	jsr prox_door
	bcc .tdp_n
	jsr door_activate
	ldx obj_i
.tdp_n
	inx
	bne .tdp
.tdp_rts
	rts

; X=door; C=1 if in front trigger box (door width × DOOR_PROX deep) and Y overlaps
prox_door
	stx obj_i
	lda door_vface,x
	cmp #FACE_PX
	bcs .pd_x
	cmp #FACE_MZ
	beq .pd_mz
	; FACE_PZ: wide=X, front extends +Z from door face
	lda door_vx,x
	sta box_x
	lda door_vsx,x
	sta box_sx
	lda door_vz,x
	clc
	adc door_vsz,x
	sta box_z
	lda #DOOR_PROX
	sta box_sz
	jmp .pd_xz
.pd_mz
	; FACE_MZ: wide=X, front extends -Z from door face
	lda door_vx,x
	sta box_x
	lda door_vsx,x
	sta box_sx
	lda door_vz,x
	sec
	sbc #DOOR_PROX
	bcs +
	lda #0
+
	sta box_z
	lda #DOOR_PROX
	sta box_sz
	jmp .pd_xz
.pd_x
	cmp #FACE_MX
	beq .pd_mx
	; FACE_PX: wide=Z, front extends +X from door face
	lda door_vz,x
	sta box_z
	lda door_vsz,x
	sta box_sz
	lda door_vx,x
	clc
	adc door_vsx,x
	sta box_x
	lda #DOOR_PROX
	sta box_sx
	jmp .pd_xz
.pd_mx
	; FACE_MX: wide=Z, front extends -X from door face
	lda door_vz,x
	sta box_z
	lda door_vsz,x
	sta box_sz
	lda door_vx,x
	sec
	sbc #DOOR_PROX
	bcs +
	lda #0
+
	sta box_x
	lda #DOOR_PROX
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
