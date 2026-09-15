; Scrag spit — single no-gravity missile. No overwrite while live.
; Cheap: ≤1 physics step/frame, inset+ceil/floor only (no solid_at),
; draw = one xform + project_cam0_screen + plot_pixel (no stroke_mesh).
!zone spit

init_spit
	lda #0
	sta spit_on
	rts

; X = Scrag enemy_idx. Clears live spit owned by X.
clear_spit_if_owner
	lda spit_on
	beq .cso_rts
	cpx spit_owner
	bne .cso_rts
	lda #0
	sta spit_on
.cso_rts
	rts

; enemy_idx = Scrag. Spawns from tip vert, aims at player.
; No-op if a spit is already live (C=0). C=1 spawned.
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
	sta spit_xl
	lda org_xh
	sta spit_xh
	lda org_yl
	sta spit_yl
	lda org_yh
	sta spit_yh
	lda org_zl
	sta spit_zl
	lda org_zh
	sta spit_zh
	lda cam_xh
	sec
	sbc org_xh
	sta rot0
	lda cam_zh
	sec
	sbc org_zh
	sta rot1
	jsr atan2_yaw
	sta rot2
	tay
	lda SINTAB,y
	ldy #SPIT_SPEED
	jsr smul7
	sta spit_vxh
	lda #0
	sta spit_vxl
	ldy rot2
	lda COSTAB,y
	ldy #SPIT_SPEED
	jsr smul7
	sta spit_vzh
	lda #0
	sta spit_vzl
	; vy toward player eye (signed dy << 1 so ASR5 tracks)
	lda cam_yh
	sec
	sbc spit_yh
	asl
	sta spit_vyh
	lda #0
	sta spit_vyl
	sta spit_acc
	lda #<SPIT_LIFE_MS
	sta spit_life_l
	lda #>SPIT_LIFE_MS
	sta spit_life_h
	lda #1
	sta spit_on
	sec
	rts

update_spit
	lda spit_on
	bne .usp_go
	rts
.usp_go
	lda room_idx
	sta gren_save_room
	lda spit_room
	cmp gren_save_room
	beq .usp_phys
	jsr set_room_idx
.usp_phys
	; At most one 32ms step per frame — never spiral under load.
	clc
	lda spit_acc
	adc dt_ms
	sta spit_acc
	cmp #SPIT_TICK_MS
	bcc .usp_hit
	sbc #SPIT_TICK_MS
	sta spit_acc
	jsr spit_step
	bcc .usp_die
.usp_hit
	jsr spit_hit_player
	bcs .usp_die
	sec
	lda spit_life_l
	sbc dt_ms
	sta spit_life_l
	lda spit_life_h
	sbc dt_msh
	sta spit_life_h
	bcs .usp_rest
.usp_die
	lda #0
	sta spit_on
.usp_rest
	lda gren_save_room
	cmp room_idx
	beq .usp_rts
	jsr set_room_idx
.usp_rts
	rts

; One ASR5 integrate on X/Z/Y. C=1 still live; C=0 hit wall/floor/ceil.
spit_step
	lda spit_vxl
	ldy spit_vxh
	jsr spit_asr_ay
	clc
	lda spit_xl
	adc nlo
	sta spit_xl
	lda spit_xh
	adc nhi
	sta spit_xh
	lda spit_vzl
	ldy spit_vzh
	jsr spit_asr_ay
	clc
	lda spit_zl
	adc nlo
	sta spit_zl
	lda spit_zh
	adc nhi
	sta spit_zh
	lda spit_xh
	sta col_x
	lda spit_zh
	sta col_z
	jsr in_room_inset
	bcc .sst_no
	lda spit_vyl
	ldy spit_vyh
	jsr spit_asr_ay
	clc
	lda spit_yl
	adc nlo
	sta spit_yl
	lda spit_yh
	adc nhi
	sta spit_yh
	ldy spit_room
	jsr load_box_room
	clc
	lda box_y
	adc box_sy
	cmp spit_yh
	beq .sst_no
	bcc .sst_no
	lda spit_xh
	sta col_x
	lda spit_zh
	sta col_z
	lda spit_yh
	sta fb_probe_y
	jsr floor_below
	bcc .sst_ok
	lda proc_tmp2
	cmp spit_yh
	beq .sst_no
	bcs .sst_no
.sst_ok
	sec
	rts
.sst_no
	clc
	rts

spit_asr_ay
	sta nlo
	sty nhi
	ldy #5
.sa5
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	dey
	bne .sa5
	rts

; C=1 hit
spit_hit_player
	lda spit_xh
	sec
	sbc cam_xh
	jsr spit_abs
	cmp #SPIT_HIT_R + 1
	bcs .shp_no
	lda spit_zh
	sec
	sbc cam_zh
	jsr spit_abs
	cmp #SPIT_HIT_R + 1
	bcs .shp_no
	lda cam_yh
	sec
	sbc #EYE_HEIGHT
	sta pv0
	clc
	adc #PLAYER_H
	sta pv1
	lda spit_yh
	cmp pv0
	bcc .shp_no
	cmp pv1
	bcs .shp_no
	lda #SPIT_DMG
	jsr take_damage
	sec
	rts
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

; View trig already loaded by draw_enemies / draw_grenades.
; Short line: tip at spit, tail one vel-step back; both projected.
draw_spit
	lda spit_on
	bne .dsp_go
	rts
.dsp_go
	lda spit_room
	cmp room_idx
	beq .dsp_draw
	rts
.dsp_draw
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
	bcc .dsp_rts
	sta x0
	sty y0
	; tail = tip − (vel >> SPIT_DRAW_ASR)
	lda spit_vxl
	ldy spit_vxh
	jsr spit_asr_draw
	sec
	lda spit_xl
	sbc nlo
	sta org_xl
	lda spit_xh
	sbc nhi
	sta org_xh
	lda spit_vyl
	ldy spit_vyh
	jsr spit_asr_draw
	sec
	lda spit_yl
	sbc nlo
	sta org_yl
	lda spit_yh
	sbc nhi
	sta org_yh
	lda spit_vzl
	ldy spit_vzh
	jsr spit_asr_draw
	sec
	lda spit_zl
	sbc nlo
	sta org_zl
	lda spit_zh
	sbc nhi
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	jsr project_cam0_screen
	bcc .dsp_rts
	sta x1
	sty y1
	jmp draw_line
.dsp_rts
	rts

; Slightly longer than physics ASR5 so the stub reads at range.
spit_asr_draw
	sta nlo
	sty nhi
	ldy #SPIT_DRAW_ASR
.sad
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	dey
	bne .sad
	rts

spit_end = *
