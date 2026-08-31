; Doors — per-room baked face; collision, portals, proximity
!zone door

; ------------------------------------------------------------------
; set_room_idx — A = room
; ------------------------------------------------------------------
set_room_idx
	sta room_idx
	rts

; door_slice — door_i0..door_i1 (exclusive) = this room's baked doors
door_slice
	ldy room_idx
	+lda_my room_door_o
	sta door_i0
	clc
	+adc_my room_ndoor
	sta door_i1
	rts

; ------------------------------------------------------------------
; door_other_room — X=door; A=linked room ($ff none)
; ------------------------------------------------------------------
door_other_room
	+lda_mx door_other
	rts

; ------------------------------------------------------------------
; door_front — X=door; C=1 if camera is in front of (or on) the door plane
; ------------------------------------------------------------------
door_front
	+lda_mx door_face
	cmp #FACE_PX
	bcs .df_x
	cmp #FACE_MZ
	beq .df_mz
	; FACE_PZ: plane at z+sz; front if cam_zh >= plane
	clc
	+lda_mx door_z
	+adc_mx door_sz
	sta pv0
	lda cam_zh
	cmp pv0
	rts
.df_mz
	; FACE_MZ: plane at z; front if cam_zh <= plane
	+lda_mx door_z
	cmp cam_zh
	rts
.df_x
	cmp #FACE_MX
	beq .df_mx
	; FACE_PX: plane at x+sx; front if cam_xh >= plane
	clc
	+lda_mx door_x
	+adc_mx door_sx
	sta pv0
	lda cam_xh
	cmp pv0
	rts
.df_mx
	; FACE_MX: plane at x; front if cam_xh <= plane
	+lda_mx door_x
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
	jsr door_slice
	ldx door_i0
.db
	cpx door_i1
	bcs .db_no
	jsr door_unlocked
	bcs .db_n			; unlocked / have key — not solid
	+lda_mx door_x
	sta box_x
	+lda_mx door_z
	sta box_z
	+lda_mx door_sx
	sta box_sx
	+lda_mx door_sz
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
	+lda_mx door_face
	cmp #FACE_PX
	bcs .dhh_x
	; Z-facing: wide=X unexpanded, thin=Z ±1
	+lda_mx door_x
	sta box_x
	+lda_mx door_sx
	sta box_sx
	+lda_mx door_z
	beq .dhh_z0
	sec
	sbc #1
	sta box_z
	clc
	+lda_mx door_sz
	adc #2
	sta box_sz
	jmp point_in_box_xz
.dhh_z0
	+lda_mx door_z
	sta box_z
	clc
	+lda_mx door_sz
	adc #1
	sta box_sz
	jmp point_in_box_xz
.dhh_x
	+lda_mx door_z
	sta box_z
	+lda_mx door_sz
	sta box_sz
	+lda_mx door_x
	beq .dhh_x0
	sec
	sbc #1
	sta box_x
	clc
	+lda_mx door_sx
	adc #2
	sta box_sx
	jmp point_in_box_xz
.dhh_x0
	+lda_mx door_x
	sta box_x
	clc
	+lda_mx door_sx
	adc #1
	sta box_sx
	jmp point_in_box_xz

; ------------------------------------------------------------------
; door_portal_ok — col_x/col_z in an unlocked door hole of room_idx? C=1 yes
; ------------------------------------------------------------------
door_portal_ok
	jsr door_slice
	ldx door_i0
.dpo
	cpx door_i1
	bcs .dpo_no
	jsr door_unlocked
	bcc .dpo_n
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
	jsr door_slice
	ldx door_i0
.trs
	cpx door_i1
	bcs .trs_no
	jsr door_unlocked
	bcc .trs_n
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
	jsr door_slice
	ldx door_i0
.tdp
	cpx door_i1
	bcs .tdp_rts
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
	+lda_mx door_face
	cmp #FACE_PX
	bcs .pd_x
	cmp #FACE_MZ
	beq .pd_mz
	; FACE_PZ: wide=X, front extends +Z from door face
	+lda_mx door_x
	sta box_x
	+lda_mx door_sx
	sta box_sx
	clc
	+lda_mx door_z
	+adc_mx door_sz
	sta box_z
	lda #DOOR_PROX
	sta box_sz
	jmp .pd_xz
.pd_mz
	; FACE_MZ: wide=X, front extends -Z from door face
	+lda_mx door_x
	sta box_x
	+lda_mx door_sx
	sta box_sx
	+lda_mx door_z
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
	+lda_mx door_z
	sta box_z
	+lda_mx door_sz
	sta box_sz
	clc
	+lda_mx door_x
	+adc_mx door_sx
	sta box_x
	lda #DOOR_PROX
	sta box_sx
	jmp .pd_xz
.pd_mx
	; FACE_MX: wide=Z, front extends -X from door face
	+lda_mx door_z
	sta box_z
	+lda_mx door_sz
	sta box_sz
	+lda_mx door_x
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
