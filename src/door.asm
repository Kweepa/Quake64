; Doors — room-relative orientation, collision, portals, proximity
!zone door

; ------------------------------------------------------------------
; set_room_idx — A = room; orients connected doors inward, flush to wall
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

; X = door index; copy canonical, then snap to active room wall if linked
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
	bne .oo_rts
.oo_go
	ldy room_idx
	; +Z wall: door flush on room max Z → face inward (-Z)
	lda room_z,y
	clc
	adc room_sz,y
	cmp door_z,x
	bne .oo_mz
	lda #FACE_MZ
	sta door_vface,x
	jmp .oo_rts
.oo_mz
	; -Z wall: door flush before room min Z → face inward (+Z)
	lda door_z,x
	clc
	adc door_sz,x
	cmp room_z,y
	bne .oo_px
	lda room_z,y
	sec
	sbc door_sz,x
	sta door_vz,x
	lda #FACE_PZ
	sta door_vface,x
	jmp .oo_rts
.oo_px
	; +X wall: door flush on room max X → face inward (-X)
	lda room_x,y
	clc
	adc room_sx,y
	cmp door_x,x
	bne .oo_mx
	lda #FACE_MX
	sta door_vface,x
	jmp .oo_rts
.oo_mx
	; -X wall: door flush before room min X → face inward (+X)
	lda door_x,x
	clc
	adc door_sx,x
	cmp room_x,y
	bne .oo_rts
	lda room_x,y
	sec
	sbc door_sx,x
	sta door_vx,x
	lda #FACE_PX
	sta door_vface,x
.oo_rts
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
	tya
	jsr set_room_idx
	sec
	rts
.trs_no
	clc
	rts

; X=door, player in its AABB. Place PLAYER_R inside the other room.
door_push_through
	jsr door_other_room
	cmp #$ff
	beq .dpt_rts
	sta proc_tmp0
	lda door_vface,x
	cmp #FACE_PX
	bcs .dpt_x
	ldy proc_tmp0
	lda room_z,y
	ldy room_idx
	cmp room_z,y
	bcc .dpt_zd
	ldy proc_tmp0
	clc
	lda room_z,y
	adc #PLAYER_R
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
	sbc #PLAYER_R
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
	clc
	lda room_x,y
	adc #PLAYER_R
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
	sbc #PLAYER_R
	sta cam_xh
	lda #0
	sta cam_xl
.dpt_sw
	lda proc_tmp0
	jsr set_room_idx
.dpt_rts
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
