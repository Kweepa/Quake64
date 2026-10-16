; Scrag spit — 16-unit tracer along the 8.8 wrist→player ray, then hitscan.
; Sourced from ai_scrag.asm. Resident play only zeros the BSS slot.
; Each axis is player lo/hi then wrist lo/hi (see spit_axes).

; Push spit_prod hi first, so lo sits at the lowest stack address.
!macro spit_push4 {
	ldx #3
-	lda spit_prod,x
	pha
	dex
	bpl -
}

; Launch from wrist. C=1 spawned.
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
	ldx #4
.ssp_wr
	txa
	asl
	tay
	lda org_xl,x
	sta spit_oxl,y
	lda org_xh,x
	sta spit_oxh,y
	dex
	dex
	bpl .ssp_wr
	lda cam_xl
	sta spit_xl
	lda cam_xh
	sta spit_xh
	sta ln_bx
	lda cam_zl
	sta spit_zl
	lda cam_zh
	sta spit_zh
	sta ln_bz
	lda cam_yl
	sta spit_yl
	lda cam_yh
	sta ln_by
	sec
	sbc #EYE_HEIGHT - 2
	sta spit_yh
	jsr spit_line
	lda #1
	adc #0
	sta spit_on
	lda #SPIT_FLIGHT_MS
	sta spit_flash
	sec
	rts

; ln_a* = wrist, ln_b* set by the caller. C=1 blocked.
spit_line
	lda spit_oxh
	sta ln_ax
	lda spit_oyh
	sta ln_ay
	lda spit_ozh
	sta ln_az
	ldy spit_room
	jmp line_solids_hit

; Y = axis (0, 4, 8). Signed player−wrist in div_n0:div_n1. Y kept.
spit_delta
	sec
	lda spit_axes,y
	sbc spit_axes+2,y
	sta div_n0
	lda spit_axes+1,y
	sbc spit_axes+3,y
	sta div_n1
	rts

; X = ZP pair. abs / negate in place. Y kept.
spit_absdiv
	ldx #div_n0
spit_abs_x
	lda 1,x
	bpl .ab_rts
spit_neg_x
	sec
	lda #0
	sbc 0,x
	sta 0,x
	lda #0
	sbc 1,x
	sta 1,x
.ab_rts
	rts

; div_n0:div_n1 = signed 8.8, dlo = cheb (>0, kept). Y kept.
; div_n0:div_n1 = delta * SPIT_LEN / cheb. SPIT_LEN is 16.
spit_scale16
	lda div_n1
	pha
	jsr spit_absdiv
	lda #0
	sta div_n2
	ldx #4
.sc_x16
	asl div_n0
	rol div_n1
	rol div_n2
	dex
	bne .sc_x16
	jsr div24u8
	pla
	bpl .ab_rts
	ldx #div_n0
	bne spit_neg_x

; org_* = SPIT_LEN along wrist→player. Cheb starts at 1, so a zero delta
; lands on the wrist, which is then the player.
spit_build_end
	lda #1
	sta dlo
	ldy #8
.be_cheb
	jsr spit_delta
	lda div_n1
	bpl .be_pos
	eor #$ff
	clc
	adc #1
.be_pos
	cmp dlo
	bcc .be_next
	sta dlo
.be_next
	dey
	dey
	dey
	dey
	bpl .be_cheb
	ldy #8
.be_ax
	jsr spit_delta
	jsr spit_scale16
	tya
	lsr
	tax
	clc
	lda div_n0
	adc spit_oxl,y
	sta org_xl,x
	lda div_n1
	adc spit_oxh,y
	sta org_xh,x
	dey
	dey
	dey
	dey
	bpl .be_ax
	rts

; C=1 hit. d = player at fire − wrist, m = player now − player at fire, 8.8 XZ.
; cross = dx*mz−dz*mx, then >>8. Miss when that square > dx²+dz².
; Equal still hits, so d = 0 hits. spit_on = 2 is a blocked aim.
spit_hit_player
	lda spit_on
	cmp #1
	bne .shp_no
	lda spit_room
	cmp room_idx
	beq .shp_go
.shp_no
	clc
	rts
.shp_go
	ldy #0
	jsr spit_sqaxis
	+spit_push4
	ldy #8
	jsr spit_sqaxis
	jsr spit_acc_add
	sec
	lda cam_zl
	sbc spit_zl
	sta nlo
	lda cam_zh
	sbc spit_zh
	sta nhi
	ldy #0
	jsr spit_delta
	jsr spit_smul16
	+spit_push4
	sec
	lda cam_xl
	sbc spit_xl
	sta nlo
	lda cam_xh
	sbc spit_xh
	sta nhi
	ldy #8
	jsr spit_delta
	jsr spit_smul16
	jsr spit_acc_sub
	pla
	pla
	pla
	pla
	lda spit_prod+2
	asl
	lda spit_prod+3
	adc #0
	bne .shp_far
	lda spit_prod+1
	sta div_n0
	lda spit_prod+2
	sta div_n1
	jsr spit_sqdiv
	jsr spit_acc_sub
	bcs .shp_drop
.shp_far
	clc
.shp_drop
	pla
	pla
	pla
	pla
	bcc .shp_rts
	lda #SPIT_DMG
	jmp take_damage
.shp_rts
	rts

; Stack acc (4 bytes under the return address, lo first) += spit_prod.
spit_acc_add
	tsx
	txa
	tay
	ldx #$fc
	clc
.aa_lp
	lda $0103,y
	adc spit_prod-$fc,x
	sta $0103,y
	iny
	inx
	bne .aa_lp
	rts

; spit_prod = stack acc − spit_prod. C=1 when acc >= spit_prod.
spit_acc_sub
	tsx
	txa
	tay
	ldx #$fc
	sec
.as_lp
	lda $0103,y
	sbc spit_prod-$fc,x
	sta spit_prod-$fc,x
	iny
	inx
	bne .as_lp
	rts

; Y = axis. |delta|² in spit_prod.
spit_sqaxis
	jsr spit_delta
; |div_n0:div_n1|² in spit_prod.
spit_sqdiv
	jsr spit_absdiv
	lda div_n0
	sta nlo
	lda div_n1
	sta nhi
; Unsigned div_n0:div_n1 * nlo:nhi → spit_prod. div_n0:div_n1 consumed.
spit_umul16
	lda #0
	sta spit_prod
	sta spit_prod+1
	sta spit_prod+2
	sta spit_prod+3
	ldx #16
.u16_lp
	lsr div_n1
	ror div_n0
	bcc .u16_sh
	clc
	lda spit_prod+2
	adc nlo
	sta spit_prod+2
	lda spit_prod+3
	adc nhi
	sta spit_prod+3
.u16_sh
	ror spit_prod+3
	ror spit_prod+2
	ror spit_prod+1
	ror spit_prod
	dex
	bne .u16_lp
	rts

; div_n0:div_n1 and nlo:nhi signed. Product in spit_prod.
spit_smul16
	lda div_n1
	eor nhi
	pha
	jsr spit_absdiv
	ldx #nlo
	jsr spit_abs_x
	jsr spit_umul16
	pla
	bpl .sm_rts
	ldx #$fc
	sec
.sm_neg
	lda #0
	sbc spit_prod-$fc,x
	sta spit_prod-$fc,x
	inx
	bne .sm_neg
.sm_rts
	rts

; X = enemy index (AI_CMD_DRAW). Owner mesh is on screen this frame.
; Stroke while spit_flash counts down in ms; the expiring frame also hits.
draw_spit
	cpx spit_owner
	bne .dsp_leave
	lda spit_flash
	beq .dsp_leave
	jsr spit_stroke
	lda dt_msh
	bne .dsp_expire
	sec
	lda spit_flash
	sbc dt_ms
	bcc .dsp_expire
	beq .dsp_expire
	sta spit_flash
	rts
.dsp_expire
	lda #0
	sta spit_flash
	jsr spit_hit_player
	lda #0
	sta spit_on
.dsp_leave
	rts

; End first (near-clamped), parked in ox1/oy1, then the wrist into ox0/oy0.
spit_stroke
	jsr spit_build_end
	lda org_xh
	sta ln_bx
	lda org_yh
	sta ln_by
	lda org_zh
	sta ln_bz
	jsr spit_line
	bcc .stk_end
	lda col_x
	sta org_xh
	lda col_y
	sta org_yh
	lda col_z
	sta org_zh
	lda #0
	sta org_xl
	sta org_yl
	sta org_zl
.stk_end
	jsr load_view_trig
	ldx #0
	jsr xform_world_vert88
	jsr cam0_proj_xy
	bcs .stk_keep
	lda #0
	sta CAM_Z
	lda #2
	sta CAM_ZH
	jsr cam0_proj_xy
	bcc .stk_rts
.stk_keep
	ldx #3
.stk_cp
	lda ox0l,x
	sta ox1l,x
	dex
	bpl .stk_cp
	jsr load_view_trig
	ldx #4
.stk_wr
	txa
	asl
	tay
	lda spit_oxl,y
	sta org_xl,x
	lda spit_oxh,y
	sta org_xh,x
	dex
	dex
	bpl .stk_wr
	ldx #0
	jsr xform_world_vert88
	jsr cam0_proj_xy
	bcc .stk_rts
	jmp clip_draw_xy
.stk_rts
	rts
