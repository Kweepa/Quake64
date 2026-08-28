; One-at-a-time billboard explosion: 24 charset pixels, no gravity.
; Spawn stores view-local vx/vy (s8). Draw: t8=elapsed>>4, 16-bit invz
; project root + offsets (same as mesh, not 8-bit trunc(FOCAL/z)).
!zone fx


start_explosion
	lda #1
	sta fx_on
	sta fx_skip

	; countdown starts late so elapsed opens at FX_START_MS, then advances
	lda #<(EXPLODE_MS - FX_START_MS)
	sta fx_ms_l
	lda #>(EXPLODE_MS - FX_START_MS)
	sta fx_ms_h

	jsr load_view_trig
	jsr fx_load_org
	ldx #0
	jsr xform_world_vert88
	lda #0
	sta e0x
	lda CAM_YH
	bpl .sx_prox
	eor #$ff
	clc
	adc #1
	lsr
	sta e0x
.sx_prox
	lda CAM_ZH
	bmi .sx_bias
	cmp #32
	bcc +
	lda #32
+
	sta e0z
	lda #32
	sec
	sbc e0z
	clc
	adc e0x
	sta e0x
.sx_bias
	lda e0x
	cmp #65
	bcc +
	lda #64
+
	sta e1x
	ldx #0
.sx_lp
	stx enemy_idx
	jsr rnd8
	and #$3f
	sta e0z
	tay
	lda SINTAB,y
	sta e0xh
	lda COSTAB,y
	sta e1xh
	jsr rnd8
	tay
	lda COSTAB,y
	sta rot0
	lda SINTAB,y
	sta rot1
	lda e0xh
	ldy rot0
	jsr smul7
	sta e0x
	lda e0xh
	ldy rot1
	jsr smul7
	sta e0z
	lda e0z
	bpl +
	eor #$ff
	clc
	adc #1
+
	ldy e1x
	beq .sx_nob
	jsr smul7
	sta rot2
	lda e1xh
	sec
	sbc rot2
	sta e1xh
.sx_nob
	lda e0x
	ldy #FX_VEL_SPEED
	jsr smul7
	ldx enemy_idx
	sta fx_vx,x
	lda e1xh
	ldy #FX_VEL_SPEED
	jsr smul7
	ldx enemy_idx
	sta fx_vy,x
	inx
	cpx #FX_N
	beq .sx_rts
	jmp .sx_lp
.sx_rts
	rts

draw_explosion
	lda fx_on
	bne .de_go
	rts
.de_go
	jsr load_view_trig
	jsr fx_load_org
	ldx #0
	jsr xform_world_vert88
	lda CAM_ZH
	bpl +
	jmp .de_rts
+
	bne .de_zok
	lda CAM_Z
	bne .de_zok
	jmp .de_rts
.de_zok
	lda CAM_Z
	sta z_eye
	lda CAM_ZH
	sta z_eye_h
	bne .de_inv
	; z<1: LUT needs z_h>=1. inv = persp(1)<<8 → *inv>>16 == *scale>>8
	lda #0
	sta ylo
	lda #1
	sta yhi
	jsr persp88
	bne +
	lda #1
+
	sta inv_h
	lda #0
	sta inv_l
	sta inv_k
	jmp .de_root
.de_inv
	jsr proj_invz
.de_root
	lda CAM_X
	sta nlo
	lda CAM_XH
	sta nhi
	jsr proj_cam_to_proj
	clc
	lda nlo
	adc #SCREEN_CX
	sta ox0l
	lda nhi
	adc #0
	sta ox0h
	lda CAM_Y
	sta nlo
	lda CAM_YH
	sta nhi
	jsr proj_cam_to_proj
	sec
	lda #64
	sbc nlo
	sta oy0l
	lda #0
	sbc nhi
	sta oy0h
	sec
	lda #<EXPLODE_MS
	sbc fx_ms_l
	sta dlo
	lda #>EXPLODE_MS
	sbc fx_ms_h
	sta dhi

	; t8 = elapsed >> 4 (max 48); (v*t8) == (v*elapsed)>>4
	lsr dhi
	ror dlo
	lsr dhi
	ror dlo
	lsr dhi
	ror dlo
	lsr dhi
	ror dlo
	lda dlo
	sta gidx
	lda #0
	sta oc_tmp
	ldx #0
.de_lp
	stx enemy_idx
	lda fx_vx,x
	jsr fx_vel_t8
	jsr proj_cam_to_proj
	clc
	lda nlo
	adc ox0l
	sta nlo
	lda nhi
	adc ox0h
	sta nhi
	jsr fx_clip_x
	bcc .de_n
	sta x0
	ldx enemy_idx
	lda fx_vy,x
	jsr fx_vel_t8
	jsr proj_cam_to_proj
	sec
	lda oy0l
	sbc nlo
	sta nlo
	lda oy0h
	sbc nhi
	sta nhi
	jsr fx_clip_y
	bcc .de_n
	sta y0
	jsr plot_pixel
	inc oc_tmp
.de_n
	ldx enemy_idx
	inx
	cpx #FX_N
	beq .de_rts
	jmp .de_lp
.de_rts
	rts

; nlo:nhi signed screen X → A = 0..191, C=1 ok / C=0 skip.
; nhi=0, nlo=128..191 is the right half of the viewport — not negative.
fx_clip_x
	lda nhi
	bne .cx_no
	lda nlo
	cmp #192
	bcs .cx_no
	sec
	rts
.cx_no
	clc
	rts

; nlo:nhi signed screen Y → A = 0..127, C=1 ok / C=0 skip.
fx_clip_y
	lda nhi
	bne .cy_no
	lda nlo
	cmp #128
	bcs .cy_no
	sec
	rts
.cy_no
	clc
	rts

fx_load_org
	lda fx_oxl
	sta org_xl
	lda fx_ox
	sta org_xh
	lda fx_oyl
	sta org_yl
	lda fx_oy
	sta org_yh
	lda fx_ozl
	sta org_zl
	lda fx_oz
	sta org_zh
	rts

; A = signed vel s8, gidx = t8 → nlo:nhi view 8.8 = v * t8.
fx_vel_t8
	sta e1z
	bpl .vt_abs
	eor #$ff
	clc
	adc #1
.vt_abs
	ldy gidx
	jsr umul8j
	lda prod_l
	sta nlo
	lda prod_h
	sta nhi
	bit e1z
	bpl .vt_pos
	lda nlo
	eor #$ff
	clc
	adc #1
	sta nlo
	lda nhi
	eor #$ff
	adc #0
	sta nhi
.vt_pos
	rts
