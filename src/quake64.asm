; Quake64 — Step 1 core line engine (VIC Bank 3, raster split, Grunt walk)
!cpu 6510
!to "quake64.prg", cbm

!source "mem.asm"
!source "zp.asm"

*= $0801
!byte $0b, $08, $0a, $00, $9e, $32, $30, $36, $31, $00, $00, $00	; SYS 2061

*= $080d
start
	sei
	cld
	ldx #$ff
	txs
	lda #$35
	sta $01

	lda #0
	sta yaw
	sta keys
	sta cam_xl
	sta cam_xh
	sta cam_yl
	sta cam_zl
	lda #2				; eye ~ mid-torso (editor y≈16 → 2.0)
	sta cam_yh
	lda #$f8			; -8.0, figure at origin sits in front
	sta cam_zh
	lda #0
	sta pitch
	sta anim_frame
	sta anim_acc_l
	sta anim_acc_h

	jsr fill_colour
	jsr init_vic
	jsr fill_screens
	jsr stamp_viewport
	jsr stamp_margins
	jsr clear_charsets
	jsr fill_margin_glyph
	jsr copy_luts
	jsr init_hud
	jsr init_irq
	jsr prof_init
	cli

main
	jsr prof_reset_frame
	lda #$34
	sta $01
	jsr clear_draw
	ldy #PROF_CLEAR
	jsr prof_add_bucket
	jsr cube_rotate
	ldy #PROF_ROT
	jsr prof_add_bucket
	jsr cube_project
	ldy #PROF_PROJ
	jsr prof_add_bucket
	jsr cube_clip
	ldy #PROF_CLIP
	jsr prof_add_bucket
	jsr cube_draw
	ldy #PROF_DRAW
	jsr prof_add_bucket
	lda #$35
	sta $01

	lda draw_buf
	sta show_buf
	jsr apply_show
	jsr prof_frame_sample
	jsr calc_frame_dt
	jsr hud_print

	lda draw_buf
	eor #1
	sta draw_buf
	jsr set_draw_ptrs
	jsr apply_look
	jsr apply_move
	jsr advance_walk
	jmp main

advance_walk
	clc
	lda anim_acc_l
	adc dt_ms
	sta anim_acc_l
	lda anim_acc_h
	adc #0
	sta anim_acc_h
	lda anim_acc_h
	cmp #>ANIM_MS
	bcc .done
	bne .step
	lda anim_acc_l
	cmp #<ANIM_MS
	bcc .done
.step
	sec
	lda anim_acc_l
	sbc #<ANIM_MS
	sta anim_acc_l
	lda anim_acc_h
	sbc #>ANIM_MS
	sta anim_acc_h
	ldx anim_frame
	inx
	cpx #WALK_FRAMES
	bcc +
	ldx #0
+
	stx anim_frame
.done
	rts

apply_look
	lda keys
	and #KEY_J
	beq .noj
	sec
	lda yaw
	sbc #YAW_STEP
	sta yaw
.noj
	lda keys
	and #KEY_L
	beq .nol
	clc
	lda yaw
	adc #YAW_STEP
	sta yaw
.nol
	lda keys
	and #KEY_I
	beq .noi
	sec
	lda pitch
	sbc #PITCH_STEP
	sta pitch
.noi
	lda keys
	and #KEY_K
	beq .nok
	clc
	lda pitch
	adc #PITCH_STEP
	sta pitch
.nok
	; Keep pitch in signed ±48 (0 = horizon)
	lda pitch
	cmp #PITCH_MAX+1
	bcc .pok
	cmp #PITCH_MIN
	bcs .pok
	cmp #$80
	bcs .plo
	lda #PITCH_MAX
	sta pitch
	rts
.plo
	lda #PITCH_MIN
	sta pitch
.pok
	rts

; A = signed 8-bit 8.8 step added to cam_xl/xh
camaddx
	sta rot2
	ldx #0
	cmp #0
	bpl +
	dex
+
	clc
	adc cam_xl
	sta cam_xl
	txa
	adc cam_xh
	sta cam_xh
	rts

camaddy
	sta rot2
	ldx #0
	cmp #0
	bpl +
	dex
+
	clc
	adc cam_yl
	sta cam_yl
	txa
	adc cam_yh
	sta cam_yh
	rts

camaddz
	sta rot2
	ldx #0
	cmp #0
	bpl +
	dex
+
	clc
	adc cam_zl
	sta cam_zl
	txa
	adc cam_zh
	sta cam_zh
	rts

; A = signed 8-bit 8.8 step subtracted from cam
camsbcx
	eor #$ff
	clc
	adc #1
	jmp camaddx

camsbcy
	eor #$ff
	clc
	adc #1
	jmp camaddy

camsbcz
	eor #$ff
	clc
	adc #1
	jmp camaddz

apply_move
	lda $01
	pha
	lda #$34
	sta $01
	ldy yaw
	lda SINTAB,y
	sta rot0
	ldy yaw
	lda COSTAB,y
	sta rot1

	lda keys
	and #KEY_W
	beq .now
	ldy pitch
	lda COSTAB,y
	tay
	lda rot0
	jsr smul7
	jsr camaddx
	ldy pitch
	lda COSTAB,y
	tay
	lda rot1
	jsr smul7
	jsr camaddz
	ldy pitch
	lda SINTAB,y
	jsr camsbcy
.now
	lda keys
	and #KEY_S
	beq .nos
	ldy pitch
	lda COSTAB,y
	tay
	lda rot0
	jsr smul7
	jsr camsbcx
	ldy pitch
	lda COSTAB,y
	tay
	lda rot1
	jsr smul7
	jsr camsbcz
	ldy pitch
	lda SINTAB,y
	jsr camaddy
.nos
	lda keys
	and #KEY_D
	beq .nod
	lda rot1
	jsr camaddx
	lda rot0
	jsr camsbcz
.nod
	lda keys
	and #KEY_A
	beq .noa
	lda rot1
	jsr camsbcx
	lda rot0
	jsr camaddz
.noa
	pla
	sta $01
	rts

copy_luts
	lda $01
	pha
	lda #$34
	sta $01
	lda #<lut_src
	sta src_ptr
	lda #>lut_src
	sta src_ptr+1
	lda #<LOGTAB
	sta dst_ptr
	lda #>LOGTAB
	sta dst_ptr+1
	ldx #LUT_PAGES
	ldy #0
.copy
	lda (src_ptr),y
	sta (dst_ptr),y
	iny
	bne .copy
	inc src_ptr+1
	inc dst_ptr+1
	dex
	bne .copy
	pla
	sta $01
	rts

!source "vic.asm"
!source "irq.asm"
!source "profil.asm"
!source "hud.asm"
!source "math.asm"
!source "line.asm"
!source "cube.asm"

lut_src
	!source "tables.asm"
lut_end
!if lut_end - lut_src != 1280 {
	!error "LUT blob must be 1280 bytes"
}

casc_snap
	!fill 4, 0
prof_dt
	!fill 4, 0
prof_cy
	!fill PROF_NBUCKET * 4, 0
