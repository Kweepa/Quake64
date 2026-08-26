; Doors — room-relative orientation, collision, portals, proximity
!zone door

; ------------------------------------------------------------------
; set_room_idx — A = room; orients connected doors toward this room
; ------------------------------------------------------------------
set_room_idx
	sta room_idx
orient_doors_for_room
	ldx #0
.odf
	cpx	map_ndoors
	bcs .odf_rts
	jsr orient_one_door
	inx
	beq .odf_rts
	jmp .odf
.odf_rts
	rts

; X = door index; copy canonical AABB, face = nearer plane to room_idx
orient_one_door
	+lda_mx door_x
	sta door_vx,x
	+lda_mx door_z
	sta door_vz,x
	+lda_mx door_sx
	sta door_vsx,x
	+lda_mx door_sz
	sta door_vsz,x
	+lda_mx door_face
	sta door_vface,x
	+lda_mx door_ra
	cmp room_idx
	beq .oo_go
	+lda_mx door_rb
	cmp room_idx
	beq .oo_go
	rts
.oo_go
	+lda_mx door_sz
	+cmp_mx door_sx
	bcc .oo_z			; sz < sx → Z slab
	beq .oo_z
	jmp .oo_x
.oo_z
	lda room_idx
	jsr room_mul3
	tay
	jsr .oo_pickz
	+lda_my rc_sz
	lsr
	clc
	+adc_my rc_z
	sta pv0				; collider Z centre
	lda pv0
	sec
	+sbc_mx door_z
	jsr .oo_abs
	sta pv1				; dist to z0
	clc
	+lda_mx door_z
	+adc_mx door_sz
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
	+lda_my rc_sx
	lsr
	clc
	+adc_my rc_x
	sta pv0
	lda pv0
	sec
	+sbc_mx door_x
	jsr .oo_abs
	sta pv1
	clc
	+lda_mx door_x
	+adc_mx door_sx
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
	+lda_my rc_sx
	bne .oo_pr
	iny
	+lda_my rc_sx
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
	+lda_my rc_sx
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
	+lda_my rc_sx
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
	+lda_my rc_x
	+adc_my rc_sx
	+cmp_mx door_x
	beq .oo_ovx_no
	bcc .oo_ovx_no
	clc
	+lda_mx door_x
	+adc_mx door_sx
	+cmp_my rc_x
	beq .oo_ovx_no
	bcc .oo_ovx_no
	sec
	rts
.oo_ovx_no
	clc
	rts
.oo_ovz
	clc
	+lda_my rc_z
	+adc_my rc_sz
	+cmp_mx door_z
	beq .oo_ovz_no
	bcc .oo_ovz_no
	clc
	+lda_mx door_z
	+adc_mx door_sz
	+cmp_my rc_z
	beq .oo_ovz_no
	bcc .oo_ovz_no
	sec
	rts
.oo_ovz_no
	clc
	rts

; ------------------------------------------------------------------
; door_other_room — X=door; A=linked room that isn't room_idx ($ff none)
; ------------------------------------------------------------------
door_other_room
	+lda_mx door_ra
	cmp room_idx
	bne .dor_a
	+lda_mx door_rb
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
; door_unlocked — X=door; C=1 if no key or player has the key
; ------------------------------------------------------------------
door_unlocked
	+lda_mx door_key
	beq .du_yes
	cmp #DOOR_KEY_GOLD
	beq .du_gold
	lda have_keys
	and #HAVE_SILVER
	beq .du_no
	bne .du_yes
.du_gold
	lda have_keys
	and #HAVE_GOLD
	beq .du_no
.du_yes
	sec
	rts
.du_no
	clc
	rts

; ------------------------------------------------------------------
; door_blocks — col_x/col_z vs locked door in this room. C=1 blocked
; ------------------------------------------------------------------
door_blocks
	ldx #0
.db
	cpx	map_ndoors
	bcs .db_no
	jsr door_unlocked
	bcs .db_n			; unlocked / have key — not solid
	+lda_mx door_ra
	cmp room_idx
	beq .db_chk
	+lda_mx door_rb
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
; door_portal_ok — col_x/col_z in an unlocked door hole of room_idx? C=1 yes
; ------------------------------------------------------------------
door_portal_ok
	ldx #0
.dpo
	cpx	map_ndoors
	bcs .dpo_no
	jsr door_unlocked
	bcc .dpo_n
	+lda_mx door_ra
	cmp room_idx
	beq .dpo_chk
	+lda_mx door_rb
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
; try_room_switch — cross an unlocked door hole of room_idx into the other
; room (XZ left current, inside other). Never probes unrelated rooms.
; C=1 if room_idx changed
; ------------------------------------------------------------------
try_room_switch
	ldx #0
.trs
	cpx	map_ndoors
	bcs .trs_no
	jsr door_unlocked
	bcc .trs_n
	+lda_mx door_ra
	cmp room_idx
	beq .trs_chk
	+lda_mx door_rb
	cmp room_idx
	bne .trs_n
.trs_chk
	jsr door_hole_hit
	bcc .trs_n
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	ldy room_idx
	jsr col_in_room_y
	bcs .trs_n			; still in visible room
	jsr door_other_room
	tay
	jsr col_in_room_y
	bcc .trs_n
	tya
	jsr set_room_idx
	sec
	rts
.trs_n
	inx
	beq .trs_no
	jmp .trs
.trs_no
	clc
	rts

; ------------------------------------------------------------------
; try_door_proximity — locked door without key → "key required" HUD
; ------------------------------------------------------------------
try_door_proximity
	ldx #0
.tdp
	cpx	map_ndoors
	bcs .tdp_rts
	+lda_mx door_ra
	cmp room_idx
	beq .tdp_near
	+lda_mx door_rb
	cmp room_idx
	bne .tdp_n
.tdp_near
	jsr door_unlocked
	bcs .tdp_n
	jsr prox_door
	bcc .tdp_n
	ldx obj_i
	+lda_mx door_key
	jsr hud_key_req
	ldx obj_i
.tdp_n
	inx
	beq .tdp_rts
	jmp .tdp
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
	+lda_mx door_y
	sta box_y
	+lda_mx door_sy
	sta box_sy
	jsr player_overlaps_y
	ldx obj_i
	rts
.pd_no
	clc
	ldx obj_i
	rts
