; Doors — per-room baked face; collision, wish AABB
!zone door

; ------------------------------------------------------------------
; set_room_idx — A = room. Player only. Clears trigger occupancy.
; ------------------------------------------------------------------
set_room_idx
	sta room_idx
	jsr crush_reset
	lda #0
	sta trig_inside
	lda msg_on
	bne .sri_blank
	lda room_idx
	rts
.sri_blank
	lda #0
	sta msg_on
	jsr hud_msg_blank
	lda room_idx
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
	cmp #DOOR_KEY_REMOTE
	beq .du_no
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

; A = cooked tag id. Unlock every remote door with that tag.
door_unlock_tag
	sta sw_match
	ldx #0
.dut
	cpx	map_ndoors
	bcs .dut_done
	+lda_mx door_tag
	cmp sw_match
	bne .dut_n
	+lda_mx door_key
	cmp #DOOR_KEY_REMOTE
	bne .dut_n
	lda #0
	+sta_mx door_key
.dut_n
	inx
	bne .dut
.dut_done
	rts

; ------------------------------------------------------------------
; door_blocks — col_x/col_z vs locked door in this room. C=1 blocked
; door_blocks_y — Y = room
; ------------------------------------------------------------------
door_blocks
	ldy room_idx
door_blocks_y
	+lda_my room_door_o
	sta door_i0
	clc
	+adc_my room_ndoor
	sta door_i1
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
; door_y_ok — X=door; C=1 if feet−door_y in [-DOOR_Y_SLACK, +DOOR_Y_SLACK]
; feet = cam_yh − EYE_HEIGHT. Preserve X.
; ------------------------------------------------------------------
door_y_ok
	lda cam_yh
	sec
	sbc #EYE_HEIGHT			; feet
	sec
	+sbc_mx door_y			; A = feet − door_y ($FF if 1 below)
	cmp #DOOR_Y_SLACK + 1
	bcc .dyo_yes			; 0..slack
	cmp #$100 - DOOR_Y_SLACK
	bcc .dyo_no			; 2..$FE
.dyo_yes
	sec
	rts
.dyo_no
	clc
	rts

; ------------------------------------------------------------------
; try_door_wish — blocked dest-ward wish into a door slab at sill height.
; Save cam, add wish on blocked axes, hit door AABB + door_y_ok.
; Wish on the door axis must point through. Unlocked + other: snap
; into dest inset, C=1. Locked: key HUD, restore, C=0.
; ------------------------------------------------------------------
try_door_wish
	lda door_blk
	beq .tdw_idle
	lda wish_dx
	ora wish_dxh
	ora wish_dz
	ora wish_dzh
	bne .tdw_go
.tdw_idle
	clc
	rts
.tdw_go
	lda cam_xl
	sta save_xl
	lda cam_xh
	sta save_xh
	lda cam_zl
	sta save_zl
	lda cam_zh
	sta save_zh
	lda door_blk
	lsr
	bcc .tdw_z
	clc
	lda cam_xl
	adc wish_dx
	sta cam_xl
	lda cam_xh
	adc wish_dxh
	sta cam_xh
.tdw_z
	lda door_blk
	and #2
	beq .tdw_scan
	clc
	lda cam_zl
	adc wish_dz
	sta cam_zl
	lda cam_zh
	adc wish_dzh
	sta cam_zh
.tdw_scan
	jsr door_slice
	ldx door_i0
.tdw
	cpx door_i1
	bcs .tdw_miss
	+lda_mx door_x
	beq .tdw_x0
	sec
	sbc #1
.tdw_x0
	sta box_x
	clc
	+lda_mx door_sx
	adc #2
	sta box_sx
	+lda_mx door_z
	beq .tdw_z0
	sec
	sbc #1
.tdw_z0
	sta box_z
	clc
	+lda_mx door_sz
	adc #2
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .tdw_n
	jsr door_y_ok
	bcc .tdw_n
	jsr .tdw_thru
	bcc .tdw_n
	jsr door_unlocked
	bcc .tdw_lock
	jsr door_other_room
	cmp #$ff
	beq .tdw_n
	jsr .tdw_snap
	jsr door_other_room
	jsr set_room_idx
	sec
	rts
.tdw_lock
	+lda_mx door_key
	jsr hud_key_req
	jmp .tdw_miss
.tdw_n
	inx
	beq .tdw_miss
	jmp .tdw
.tdw_miss
	lda save_xl
	sta cam_xl
	lda save_xh
	sta cam_xh
	lda save_zl
	sta cam_zl
	lda save_zh
	sta cam_zh
.tdw_no
	clc
	rts

; Dest-ward wish on the door axis. Plus face: hi BMI. Minus: lo|hi != 0, hi BPL.
.tdw_thru
	+lda_mx door_face
	lsr				; C=minus, A=0 Z / 1 X
	bcs .tdw_tm
	cmp #1
	bcs .tdw_tpx
	lda wish_dzh
	bmi .tdw_tyes
	clc
	rts
.tdw_tpx
	lda wish_dxh
	bmi .tdw_tyes
	clc
	rts
.tdw_tm
	cmp #1
	bcs .tdw_tmx
	lda wish_dz
	ora wish_dzh
	beq .tdw_tno
	lda wish_dzh
	bmi .tdw_tno
.tdw_tyes
	sec
	rts
.tdw_tno
	clc
	rts
.tdw_tmx
	lda wish_dx
	ora wish_dxh
	beq .tdw_tno
	lda wish_dxh
	bmi .tdw_tno
	sec
	rts

; Dest inset (PLAYER_R past the slab). Frac 0.
.tdw_snap
	+lda_mx door_face
	lsr				; C=minus, A=0 Z / 1 X
	php
	cmp #1
	bcs .tdw_sx
	+lda_mx door_z
	plp
	bcs .tdw_adz
	sec
	sbc #2
	bcs .tdw_zst
	lda #0
.tdw_zst
	sta cam_zh
	lda #0
	sta cam_zl
	rts
.tdw_adz
	clc
	+adc_mx door_sz
	clc
	adc #1
	jmp .tdw_zst
.tdw_sx
	+lda_mx door_x
	plp
	bcs .tdw_adx
	sec
	sbc #2
	bcs .tdw_xst
	lda #0
.tdw_xst
	sta cam_xh
	lda #0
	sta cam_xl
	rts
.tdw_adx
	clc
	+adc_mx door_sx
	clc
	adc #1
	jmp .tdw_xst
