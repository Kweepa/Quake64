; Scrag spit — 16-unit tracer (env-clamped 8.8 segment), then hitscan.
!zone spit

init_spit
	lda #0
	sta spit_on
	sta spit_flash
	rts

; X = Scrag enemy_idx. Clears live spit owned by X.
clear_spit_if_owner
	lda spit_on
	beq .cso_rts
	cpx spit_owner
	bne .cso_rts
	lda #0
	sta spit_on
	sta spit_flash
.cso_rts
	rts

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
	jmp .ssp_on
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
	jsr line_cutouts_hit
	bcs .ssp_clamp
	ldy spit_room
	jsr load_box_room
	jsr line_hit_box
	bcc .ssp_on
.ssp_clamp
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
.ssp_on
	lda #SPIT_FLASH_N
	sta spit_flash
	lda #1
	sta spit_on
	sec
	rts

; A = signed Δhi, dlo = Chebyshev. A = Δ * SPIT_LEN / cheb.
spit_scale
	pha
	jsr spit_abs
	sta rot0
	lda #0
	sta rot1
	sta rot2
	asl rot0
	rol rot1
	rol rot2
	asl rot0
	rol rot1
	rol rot2
	asl rot0
	rol rot1
	rol rot2
	asl rot0
	rol rot1
	rol rot2
	jsr div24u8
	pla
	bpl .ss_p
	lda rot0
	eor #$ff
	clc
	adc #1
	rts
.ss_p
	lda rot0
	rts

; After the tracer, hit if the player is still on the aim cell.
update_spit
	lda spit_on
	beq .usp_rts
	lda spit_flash
	bne .usp_rts
	jsr spit_hit_player
	lda #0
	sta spit_on
.usp_rts
	rts

; C=1 hit. Aim cell vs current cam XZ.
spit_hit_player
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

; Frozen 8.8 segment. draw_enemies leaves mulset as last mesh facing.
draw_spit
	lda spit_flash
	beq .dsp_rts
	dec spit_flash
	lda spit_room
	cmp room_idx
	bne .dsp_rts
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
	bcc .dsp_rts
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
	bcs .dsp_end
	lda #0
	sta CAM_Z
	lda #2
	sta CAM_ZH
	jsr project_cam0_screen
	bcc .dsp_rts
.dsp_end
	sta x1
	sty y1
	jmp draw_line
.dsp_rts
	rts

spit_end = *
