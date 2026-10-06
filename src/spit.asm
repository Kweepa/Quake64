; Scrag spit — 16-unit tracer (env-clamped 8.8 segment), then hitscan.
; Sourced from ai_scrag.asm. Resident play only zeros the BSS slot.

; Launch from wrist; end = 16 toward player midpoint, clamp to cutout/room.
; C=1 spawned.
spawn_scrag_spit
	lda spit_on
	beq .ssp_go
	clc
	rts
.ssp_go
	ldx enemy_idx
	stx spit_owner
	stx obj_i
	+lda_mx en_type
	sta ent_type
	ldy #SPIT_TIP_VERT
	jsr ent_vert_world
	ldx enemy_idx
	+lda_mx en_room
	sta spit_room
	lda org_xl
	sta spit_oxl
	lda org_xh
	sta spit_oxh
	lda org_yl
	sta spit_oyl
	lda org_yh
	sta spit_oyh
	lda org_zl
	sta spit_ozl
	lda org_zh
	sta spit_ozh
	lda cam_xh
	sta spit_hitx
	lda cam_zh
	sta spit_hitz
	; dir hi: player midpoint − wrist
	lda cam_xh
	sec
	sbc spit_oxh
	sta spit_xl
	lda cam_yh
	sec
	sbc #EYE_HEIGHT - 2
	sec
	sbc spit_oyh
	sta spit_yl
	lda cam_zh
	sec
	sbc spit_ozh
	sta spit_zl
	lda spit_xl
	jsr spit_abs
	sta dlo
	lda spit_yl
	jsr spit_abs
	cmp dlo
	bcc +
	sta dlo
+
	lda spit_zl
	jsr spit_abs
	cmp dlo
	bcc +
	sta dlo
+
	lda dlo
	bne .ssp_dir
	lda spit_oxl
	sta spit_xl
	lda spit_oxh
	sta spit_xh
	lda spit_oyl
	sta spit_yl
	lda spit_oyh
	sta spit_yh
	lda spit_ozl
	sta spit_zl
	lda spit_ozh
	sta spit_zh
	jmp .ssp_aim
.ssp_dir
	lda spit_xl
	jsr spit_scale
	clc
	adc spit_oxh
	sta spit_xh
	lda spit_oxl
	sta spit_xl
	lda spit_yl
	jsr spit_scale
	clc
	adc spit_oyh
	sta spit_yh
	lda spit_oyl
	sta spit_yl
	lda spit_zl
	jsr spit_scale
	clc
	adc spit_ozh
	sta spit_zh
	lda spit_ozl
	sta spit_zl
	lda spit_oxh
	sta ln_ax
	lda spit_oyh
	sta ln_ay
	lda spit_ozh
	sta ln_az
	lda spit_xh
	sta ln_bx
	lda spit_yh
	sta ln_by
	lda spit_zh
	sta ln_bz
	ldy spit_room
	jsr line_solids_hit
	bcc .ssp_aim
	lda col_x
	sta spit_xh
	lda col_y
	sta spit_yh
	lda col_z
	sta spit_zh
	lda #0
	sta spit_xl
	sta spit_yl
	sta spit_zl
.ssp_aim
	lda spit_oxh
	sta ln_ax
	lda spit_oyh
	sta ln_ay
	lda spit_ozh
	sta ln_az
	lda cam_xh
	sta ln_bx
	lda cam_yh
	sta ln_by
	lda cam_zh
	sta ln_bz
	ldy spit_room
	jsr line_solids_hit
	lda #1
	bcc .ssp_set
	lda #2
.ssp_set
	sta spit_on
	lda #SPIT_FLASH_N
	sta spit_flash
	sec
	rts

; A = signed Δhi, dlo = Chebyshev. A = Δ * SPIT_LEN / cheb.
spit_scale
	pha
	jsr spit_abs
	sta div_n0
	lda #0
	sta div_n1
	sta div_n2
	asl div_n0
	rol div_n1
	rol div_n2
	asl div_n0
	rol div_n1
	rol div_n2
	asl div_n0
	rol div_n1
	rol div_n2
	asl div_n0
	rol div_n1
	rol div_n2
	jsr div24u8
	pla
	bpl .ss_p
	lda div_n0
	eor #$ff
	clc
	adc #1
	rts
.ss_p
	lda div_n0
	rts

; C=1 hit. Aim cell vs current cam XZ. spit_on = 2 means a solid blocked the aim.
spit_hit_player
	lda spit_on
	cmp #1
	bne .shp_no
	lda spit_room
	cmp room_idx
	bne .shp_no
	lda spit_hitx
	sec
	sbc cam_xh
	jsr spit_abs
	cmp #SPIT_HIT_R + 1
	bcs .shp_no
	lda spit_hitz
	sec
	sbc cam_zh
	jsr spit_abs
	cmp #SPIT_HIT_R + 1
	bcs .shp_no
	lda #SPIT_DMG
	jmp take_damage
.shp_no
	clc
	rts

spit_abs
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts

; X = enemy index (AI_CMD_DRAW). Owner mesh is on screen this frame.
; Stroke while spit_flash counts down; the expiring frame also hits.
draw_spit
	cpx spit_owner
	bne .dsp_leave
	lda spit_flash
	beq .dsp_leave
	dec spit_flash
	jsr spit_stroke
	lda spit_flash
	bne .dsp_leave
	jsr spit_hit_player
	lda #0
	sta spit_on
.dsp_leave
	rts

spit_stroke
	jsr load_view_trig
	lda spit_oxl
	sta org_xl
	lda spit_oxh
	sta org_xh
	lda spit_oyl
	sta org_yl
	lda spit_oyh
	sta org_yh
	lda spit_ozl
	sta org_zl
	lda spit_ozh
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	jsr project_cam0_screen
	bcc .stk_rts
	sta x0
	sty y0
	lda spit_xl
	sta org_xl
	lda spit_xh
	sta org_xh
	lda spit_yl
	sta org_yl
	lda spit_yh
	sta org_yh
	lda spit_zl
	sta org_zl
	lda spit_zh
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	jsr project_cam0_screen
	bcs .stk_end
	lda #0
	sta CAM_Z
	lda #2
	sta CAM_ZH
	jsr project_cam0_screen
	bcc .stk_rts
.stk_end
	sta x1
	sty y1
	jmp draw_line
.stk_rts
	rts
