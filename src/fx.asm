; One-at-a-time half-dome explosion: 24 charset pixels, no gravity.
; 6 unique +X+Z dirs × 90° Y rotates (C4, not XZ mirrors). Parametric:
; origin + dir * elapsed (dir=127 → ~4 units). Yaw then permute view XZ
; (Y-rots commute). Still 24 project/plot.
!zone fx

; Open quadrant (dx>0, dz>0, dy>=0), lengths ~40–100% of radius.
fx_dx
	!byte 37,91,30,42,77,56
fx_dy
	!byte 8,36,54,54,20,75
fx_dz
	!byte 48,33,95,36,49,80

; ent_wx/wy/wz already set. Restarts if one is already live.
; Grenade launcher will call this at the blast origin.
start_explosion
	lda ent_wx
	sta fx_ox
	lda ent_wy
	sta fx_oy
	lda ent_wz
	sta fx_oz
	lda #1
	sta fx_on
	sta fx_skip
	lda #<EXPLODE_MS
	sta fx_ms_l
	lda #>EXPLODE_MS
	sta fx_ms_h
	rts

tick_explosion
	lda fx_on
	beq .te_rts
	lda fx_skip
	beq .te_sub
	lda #0
	sta fx_skip
	rts
.te_sub
	sec
	lda fx_ms_l
	sbc dt_ms
	sta fx_ms_l
	lda fx_ms_h
	sbc dt_msh
	sta fx_ms_h
	bcc .te_off
	ora fx_ms_l
	bne .te_rts
.te_off
	lda #0
	sta fx_on
	sta fx_ms_l
	sta fx_ms_h
	sta fx_skip
.te_rts
	rts

draw_explosion
	lda fx_on
	bne .de_go
	rts
.de_go
	jsr load_view_trig
	lda fx_ox
	sta ent_wx
	lda fx_oy
	sta ent_wy
	lda fx_oz
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	lda CAM_X
	sta ox0l
	lda CAM_XH
	sta ox0h
	lda CAM_Y
	sta oy0l
	lda CAM_YH
	sta oy0h
	lda CAM_Z
	sta ox1l
	lda CAM_ZH
	sta ox1h
	; elapsed = EXPLODE_MS - remaining; gidx ≈ elapsed/3 (0..255)
	sec
	lda #<EXPLODE_MS
	sbc fx_ms_l
	sta dlo
	lda #>EXPLODE_MS
	sbc fx_ms_h
	sta dhi
	ldy #85
	lda dlo
	jsr umul8j			; lo * 85
	lda prod_h
	sta gidx			; (lo*85)>>8
	lda dhi
	beq .de_el
	ldy #85
	jsr umul8j			; hi * 85
	clc
	lda gidx
	adc prod_l
	bcc .de_el2
	lda #255
.de_el2
	sta gidx
.de_el
	ldx #0
.de_lp
	stx enemy_idx
	; x' = dx*cs − dz*sn (mulset still yaw from load_view_trig)
	lda fx_dx,x
	jsr fx_mul_a
	sta e0x
	ldx enemy_idx
	lda fx_dz,x
	jsr fx_mul_b
	sta e1x
	sec
	lda e0x
	sbc e1x
	jsr fx_sclamp
	jsr fx_scale
	lda nlo
	sta e0z
	lda nhi
	sta e0zh
	; z' = dx*sn + dz*cs
	ldx enemy_idx
	lda fx_dx,x
	jsr fx_mul_b
	sta e0x
	ldx enemy_idx
	lda fx_dz,x
	jsr fx_mul_a
	sta e1x
	clc
	lda e0x
	adc e1x
	jsr fx_sclamp
	jsr fx_scale
	lda nlo
	sta e1y
	lda nhi
	sta e1yh
	ldx enemy_idx
	lda fx_dy,x
	jsr fx_scale
	clc
	lda nlo
	adc oy0l
	sta CAM_Y
	lda nhi
	adc oy0h
	sta CAM_YH
	jsr fx_emit_quad
	ldx enemy_idx
	inx
	cpx #6
	beq .de_rts
	jmp .de_lp
.de_rts
	rts

; e0z:e0zh = x', e1y:e1yh = z' (8.8). CAM_Y already origin+scaled dy.
; 0:(x',z')  90:(−z',x')  180:(−x',−z')  270:(z',−x')
fx_emit_quad
	clc
	lda e0z
	adc ox0l
	sta CAM_X
	lda e0zh
	adc ox0h
	sta CAM_XH
	clc
	lda e1y
	adc ox1l
	sta CAM_Z
	lda e1yh
	adc ox1h
	sta CAM_ZH
	jsr fx_plot
	sec
	lda ox0l
	sbc e0z
	sta CAM_X
	lda ox0h
	sbc e0zh
	sta CAM_XH
	sec
	lda ox1l
	sbc e1y
	sta CAM_Z
	lda ox1h
	sbc e1yh
	sta CAM_ZH
	jsr fx_plot
	sec
	lda ox0l
	sbc e1y
	sta CAM_X
	lda ox0h
	sbc e1yh
	sta CAM_XH
	clc
	lda e0z
	adc ox1l
	sta CAM_Z
	lda e0zh
	adc ox1h
	sta CAM_ZH
	jsr fx_plot
	clc
	lda e1y
	adc ox0l
	sta CAM_X
	lda e1yh
	adc ox0h
	sta CAM_XH
	sec
	lda ox1l
	sbc e0z
	sta CAM_Z
	lda ox1h
	sbc e0zh
	sta CAM_ZH
	jsr fx_plot
	rts

fx_plot
	jsr fx_project
	bcc .pl_n
	sta x0
	sty y0
	jsr plot_pixel
.pl_n
	rts

; A = signed 8-bit adc/sbc result. If V set, clamp to ±127.
fx_sclamp
	bvc .cl_ok
	bmi .cl_pos
	lda #$80
	rts
.cl_pos
	lda #$7f
.cl_ok
	rts

; A signed × set-A >> 7 → A signed. umul8a (mulset A = |cos|).
fx_mul_a
	sta mul_a
	bpl .ma_p
	eor #$ff
	clc
	adc #1
.ma_p
	tay
	lda mul_a
	eor sg_a
	sta mul_sign
	jsr umul8a
	asl prod_l
	lda prod_h
	rol
	bit mul_sign
	bpl .ma_s
	eor #$ff
	clc
	adc #1
.ma_s
	rts

; A signed × set-B >> 7 → A signed. umul8b (mulset B = |sin|).
fx_mul_b
	sta mul_a
	bpl .mb_p
	eor #$ff
	clc
	adc #1
.mb_p
	tay
	lda mul_a
	eor sg_b
	sta mul_sign
	jsr umul8b
	asl prod_l
	lda prod_h
	rol
	bit mul_sign
	bpl .mb_s
	eor #$ff
	clc
	adc #1
.mb_s
	rts

; A = signed dir. gidx = elapsed 0..255.
; nlo:nhi = (A * elapsed) >> 5 as signed 8.8. Clobbers X.
fx_scale
	sta mul_sign
	bpl .sc_abs
	eor #$ff
	clc
	adc #1
.sc_abs
	ldy gidx
	jsr umul8j
	lda prod_h
	lsr
	ror prod_l
	lsr
	ror prod_l
	lsr
	ror prod_l
	lsr
	ror prod_l
	sta nhi
	lda prod_l
	sta nlo
	bit mul_sign
	bpl .sc_pos
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.sc_pos
	rts

; CAM[0] filled. C=1 → A=sx (0..191), Y=sy (0..127). C=0 behind / off-view.
; Per-particle 1/z from view-Z high (FOCAL/z LUT) × 8.8 via 16×8.
fx_project
	lda CAM_ZH
	bmi .fp_no
	bne .fp_zok
	jmp .fp_no
.fp_zok
	cmp #101
	bcs .fp_no				; focz = 0
	tax
	lda fx_focz,x
	beq .fp_no
	sta mul_y
	lda CAM_X
	sta nlo
	lda CAM_XH
	sta nhi
	jsr fx_mul88
	clc
	lda nlo
	adc #SCREEN_CX
	sta rot0
	lda nhi
	adc #0
	bmi .fp_no
	bne .fp_no
	lda rot0
	cmp #192
	bcs .fp_no
	lda CAM_Y
	sta nlo
	lda CAM_YH
	sta nhi
	jsr fx_mul88
	sec
	lda #64
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	bmi .fp_no
	bne .fp_no
	lda nlo
	cmp #128
	bcs .fp_no
	tay
	lda rot0
	sec
	rts
.fp_no
	clc
	rts

; nlo:nhi signed 8.8 × mul_y unsigned >> 8 → nlo:nhi signed. Clobbers X.
fx_mul88
	lda #0
	sta mul_sign
	lda nhi
	bpl .m8_p
	lda #$80
	sta mul_sign
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.m8_p
	lda nlo
	ora nhi
	bne .m8_nz
	rts
.m8_nz
	lda nlo
	ldy mul_y
	jsr umul8j
	lda prod_h
	sta dlo
	lda nhi
	ldy mul_y
	jsr umul8j
	clc
	lda prod_l
	adc dlo
	sta nlo
	lda prod_h
	adc #0
	sta nhi
	bit mul_sign
	bpl .m8_s
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.m8_s
	rts

; FOCAL/z for z = 0..127 (0 → skip).
fx_focz
	!byte 0,100,50,33,25,20,16,14,12,11,10,9,8,7,7,6
	!byte 6,5,5,5,5,4,4,4,4,4,3,3,3,3,3,3
	!byte 3,3,2,2,2,2,2,2,2,2,2,2,2,2,2,2
	!byte 2,2,2,1,1,1,1,1,1,1,1,1,1,1,1,1
	!byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
	!byte 1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1
	!byte 1,1,1,1,1,0,0,0,0,0,0,0,0,0,0,0
	!byte 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
