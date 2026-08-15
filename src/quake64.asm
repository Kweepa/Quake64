; Quake64 — Step 1 core line engine (VIC Bank 3, raster split, Bresenham cube)
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
	sta cam_x
	sta cam_y
	sta cam_z
	sta pitch

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
	jmp main

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

; A = signed trig / 32 (~3 world units at full amplitude)
scale_move
	cmp #$80
	ror
	cmp #$80
	ror
	cmp #$80
	ror
	cmp #$80
	ror
	cmp #$80
	ror
	rts

apply_move
	lda $01
	pha
	lda #$34
	sta $01
	ldy yaw
	lda SINTAB,y
	jsr scale_move
	sta rot0
	ldy yaw
	lda COSTAB,y
	jsr scale_move
	sta rot1
	ldy pitch
	lda SINTAB,y
	jsr scale_move
	sta rot2

	lda keys
	and #KEY_W
	beq .now
	ldy pitch
	lda COSTAB,y
	tay
	lda rot0
	jsr smul7
	clc
	adc cam_x
	sta cam_x
	ldy pitch
	lda COSTAB,y
	tay
	lda rot1
	jsr smul7
	clc
	adc cam_z
	sta cam_z
	sec
	lda cam_y
	sbc rot2
	sta cam_y
.now
	lda keys
	and #KEY_S
	beq .nos
	ldy pitch
	lda COSTAB,y
	tay
	lda rot0
	jsr smul7
	sta mul_a
	sec
	lda cam_x
	sbc mul_a
	sta cam_x
	ldy pitch
	lda COSTAB,y
	tay
	lda rot1
	jsr smul7
	sta mul_a
	sec
	lda cam_z
	sbc mul_a
	sta cam_z
	clc
	lda cam_y
	adc rot2
	sta cam_y
.nos
	lda keys
	and #KEY_D
	beq .nod
	clc
	lda cam_x
	adc rot1
	sta cam_x
	sec
	lda cam_z
	sbc rot0
	sta cam_z
.nod
	lda keys
	and #KEY_A
	beq .noa
	sec
	lda cam_x
	sbc rot1
	sta cam_x
	clc
	lda cam_z
	adc rot0
	sta cam_z
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
