; Streamed crusher motion. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_crush.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "map_bss.asm"
!source "crushacc.asm"
!source "ai_game_syms.asm"

!zone crush_ai
*= AI_LINK_BASE
ai_crush_entry
	cmp #CRUSH_CMD_SOLID
	beq crush_solid
	cmp #CRUSH_CMD_DRAW
	beq crush_draw
	jmp crush_tick

; Called from solid_at_col. col_room / col_x/z set. Y = crate step-up (ignored). C=1 blocked.
crush_solid
	sty crush_i			; preserve solid_at Y (step-up flag)
	ldy #0
.cs_lp
	cpy map_ncrush
	bcs .cs_no
	cpy crush_skip
	beq .cs_n
	+lda_cy crush_room
	cmp col_room
	bne .cs_n
	jsr crush_load_box
	jsr player_overlaps_y
	bcc .cs_n
	jsr point_in_box_xz
	bcs .cs_yes
.cs_n
	iny
	bne .cs_lp
.cs_no
	ldy crush_i
	clc
	rts
.cs_yes
	ldy crush_i
	sec
	rts

crush_draw
	ldy #0
.cd_lp
	cpy map_ncrush
	bcs .cd_rts
	+lda_cy crush_room
	cmp room_idx
	bne .cd_n
	sty crush_i
	jsr crush_load_box
	jsr frustum_hits
	bcc .cd_r
	lda #0
	sta box_inside
	jsr draw_box
.cd_r
	ldy crush_i
.cd_n
	iny
	bne .cd_lp
.cd_rts
	rts

crush_tick
	clc
	lda crush_acc_l
	adc dt_ms
	sta crush_acc_l
	lda crush_acc_h
	adc dt_msh
	sta crush_acc_h
.tick
	jsr crush_try_step
	bcc .go
	rts
.go
	jsr crush_step_all
	jmp .tick

crush_try_step
	lda crush_acc_h
	cmp #>CRUSH_STEP_MS
	bcc .no
	bne .hi
	lda crush_acc_l
	cmp #<CRUSH_STEP_MS
	bcc .no
.hi
	sec
	lda crush_acc_l
	sbc #<CRUSH_STEP_MS
	sta crush_acc_l
	lda crush_acc_h
	sbc #>CRUSH_STEP_MS
	sta crush_acc_h
	clc
	rts
.no
	sec
	rts

crush_step_all
	ldy #0
.lp
	cpy map_ncrush
	bcs .rts
	+lda_cy crush_room
	cmp room_idx
	bne .n
	jsr crush_step_one
.n
	iny
	bne .lp
.rts
	rts

; Y = index. Ping-pong, push player or kill.
crush_step_one
	sty crush_i
	+lda_cy crush_home
	sta crush_lo
	+lda_cy crush_dest
	cmp crush_lo
	bcs +
	ldx crush_lo
	sta crush_lo
	stx crush_hi
	jmp ++
+
	sta crush_hi
++
	lda crush_lo
	cmp crush_hi
	bne +
	rts				; no travel
+
	jsr crush_get_pos
	sta crush_st
	+lda_cy crush_dir
	bmi .neg
	clc
	lda crush_st
	adc #1
	bcc .have
	lda #$ff
	bne .have
.neg
	lda crush_st
	beq .have
	sec
	sbc #1
.have
	sta crush_st
	+lda_cy crush_dir
	bmi .lo
	lda crush_st
	cmp crush_hi
	bcc .store
	lda crush_hi
	sta crush_st
	jsr crush_set_travel
	lda #$ff
	+sta_cy crush_dir
	jmp .moved
.lo
	lda crush_st
	cmp crush_lo
	bcs .store
	lda crush_lo
	sta crush_st
	jsr crush_set_travel
	lda #1
	+sta_cy crush_dir
	jmp .moved
.store
	lda crush_st
	jsr crush_set_travel
.moved
	ldy crush_i
	jsr crush_load_box
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr player_overlaps_y
	bcc .done
	jsr point_in_box_xz
	bcc .done
	; overlap — push or die
	lda crush_i
	sta crush_skip
	+lda_cy crush_dir
	sta crush_st
	+lda_cy crush_face
	cmp #FACE_PX
	bcc .push_z
	clc
	lda cam_xh
	adc crush_st			; $01 add, $ff = -1
	sta cam_xh
	jmp .try
.push_z
	clc
	lda cam_zh
	adc crush_st
	sta cam_zh
.try
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr pos_ok
	php
	lda #$ff
	sta crush_skip
	plp
	bcs .done			; pushed
	jmp crush_kill
.done
	ldy crush_i
	rts

crush_get_pos
	+lda_cy crush_face
	cmp #FACE_PX
	bcc .gp_z
	+lda_cy crush_x
	rts
.gp_z
	+lda_cy crush_z
	rts

crush_set_travel
	sta crush_st
	+lda_cy crush_face
	cmp #FACE_PX
	lda crush_st
	bcc .st_z
	+sta_cy crush_x
	rts
.st_z
	+sta_cy crush_z
	rts
