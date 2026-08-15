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
	sta key_j
	sta key_l
	lda #24
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
	jsr apply_turn
	jmp main

apply_turn
	lda key_j
	beq .nol
	sec
	lda yaw
	sbc #YAW_STEP
	sta yaw
.nol
	lda key_l
	beq .done
	clc
	lda yaw
	adc #YAW_STEP
	sta yaw
.done
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
