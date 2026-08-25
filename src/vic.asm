; VIC Bank 3, 24×16 unique-char viewport (192×128), double-buffer swap
!zone vic

init_vic
	; Absolute write, upper 6 bits clear. Krill README:251-264 forbids masking
	; a value READ from $dd00: bits 2-5 are inputs while its DDRA is $03, so a
	; read-modify-write latches live pin state and the next load hangs. The
	; read tells you nothing either — it returns $3c whether the latch is
	; poisoned or not. Measured: NOTES.md "PHASE 1 RESULT", variants B vs E.
	lda #$00				; VIC bank 3 = $C000–$FFFF
	sta $dd00

	lda #$1b				; DEN, 25 rows, YSCROLL=3, text mode
	sta $d011
	lda #$08				; 40 cols, no MCM
	sta $d016

	lda #D018_A_UI
	sta $d018
	lda #COL_BORDER
	sta $d020
	sta vic_border
	lda #COL_HUD_BG
	sta $d021

	lda #0
	sta $d015				; sprites off until init_weapon
	sta palette_dirty
	sta draw_buf
	sta show_buf
	lda #D018_A_BOT
	sta show_d018_bot
	jsr set_draw_ptrs
	rts

; Colour RAM: outside = background (invisible), viewport = vector colour
fill_colour
	ldx #0
	lda #COL_OUTSIDE
-
	sta $d800,x
	sta $d900,x
	sta $da00,x
	sta $db00,x
	inx
	bne -

	lda #<($d800 + VIEW_OFF)
	sta init_ptr
	lda #>($d800 + VIEW_OFF)
	sta init_ptr+1
	lda #VIEW_H
	sta init_row
.row
	ldy #0
	lda #COL_LINE
.col
	sta (init_ptr),y
	iny
	cpy #VIEW_W
	bne .col
	clc
	lda init_ptr
	adc #40
	sta init_ptr
	bcc +
	inc init_ptr+1
+
	dec init_row
	bne .row
	rts

; 24×16 viewport only — uses col_line (room palette)
fill_viewport_colour
	lda #<($d800 + VIEW_OFF)
	sta init_ptr
	lda #>($d800 + VIEW_OFF)
	sta init_ptr+1
	lda #VIEW_H
	sta init_row
.vrow
	ldy #0
	lda col_line
.vcol
	sta (init_ptr),y
	iny
	cpy #VIEW_W
	bne .vcol
	clc
	lda init_ptr
	adc #40
	sta init_ptr
	bcc +
	inc init_ptr+1
+
	dec init_row
	bne .vrow
	rts

; room_idx → col_bg/line/fx/wpn; IRQ publishes colour RAM / weapon sprites
apply_room_palette
	ldx room_idx
	+lda_mx room_bg
	sta col_bg
	+lda_mx room_line
	sta col_line
	+lda_mx room_fx
	sta col_fx
	+lda_mx room_wpn
	sta col_wpn
	lda #1
	sta palette_dirty
	lda room_idx
	sta palette_room
	rts

; Call once per frame after movement — skips if room unchanged
maybe_room_palette
	lda room_idx
	cmp palette_room
	beq .mrpdone
	jsr apply_room_palette
.mrpdone
	rts

; Unique viewport codes + HUD spaces live in scr.prg (tools/genscreens.py).

; $FF in unused col 24 / char 192, all four charset halves. Call at $01=$30.
fill_margin_glyph
	lda #$ff
	ldx #7
-
	sta CH_A_TOP + 24 * 64,x
	sta CH_A_BOT + 24 * 64,x
	sta CH_B_TOP + 24 * 64,x
	sta CH_B_BOT + 24 * 64,x
	dex
	bpl -
	rts

clear_charsets
	lda #>CH_A_TOP
	jsr .six
	lda #>CH_A_BOT
	jsr .six
	lda #>CH_B_TOP
	jsr .six
	lda #>CH_B_BOT
.six
	sta init_ptr+1
	lda #0
	sta init_ptr
	tay
	ldx #6				; 24 cols = 6 pages; skip tail LUTs
.cl
	sta (init_ptr),y
	iny
	bne .cl
	inc init_ptr+1
	dex
	bne .cl
	rts

; Wipe 24 live columns (6 pages/half). Skip cols 24–31 (decoration/buffers).
; 12× STA abs,x + INX/BNE ≈ 16640 cycles.
clear_draw
	lda draw_top_hi
	sta .c00+2
	clc
	adc #1
	sta .c01+2
	adc #1
	sta .c02+2
	adc #1
	sta .c03+2
	adc #1
	sta .c04+2
	adc #1
	sta .c05+2
	lda draw_bot_hi
	sta .c06+2
	clc
	adc #1
	sta .c07+2
	adc #1
	sta .c08+2
	adc #1
	sta .c09+2
	adc #1
	sta .c10+2
	adc #1
	sta .c11+2
	lda #0
	tax
.clp
.c00	sta $ff00,x
.c01	sta $ff00,x
.c02	sta $ff00,x
.c03	sta $ff00,x
.c04	sta $ff00,x
.c05	sta $ff00,x
.c06	sta $ff00,x
.c07	sta $ff00,x
.c08	sta $ff00,x
.c09	sta $ff00,x
.c10	sta $ff00,x
.c11	sta $ff00,x
	inx
	bne .clp
	rts

; Publish show_d018_bot for the mid-split IRQ. No $d018 poke (IRQ owns I/O).
apply_show
	ldx show_buf
	lda show_bot_tab,x
	sta show_d018_bot
	rts

set_draw_ptrs
	lda draw_buf
	bne .b
	lda #>CH_A_TOP
	sta draw_top_hi
	lda #>CH_A_BOT
	sta draw_bot_hi
	rts
.b
	lda #>CH_B_TOP
	sta draw_top_hi
	lda #>CH_B_BOT
	sta draw_bot_hi
	rts

; Flyback: border, colour RAM if dirty, sprites. $01 already BANK_IO.
irq_publish_vic
	lda vic_border
	sta $d020
	lda palette_dirty
	beq .ipv_spr
	lda #0
	sta palette_dirty
	jsr fill_viewport_colour
.ipv_spr
	lda col_wpn
	sta $d027
	sta $d028
	sta $d029
	sta $d02a
	lda flash4_col
	sta $d02b
	lda flash5_col
	sta $d02c
	jmp apply_xy

show_top_tab
	!byte D018_A_TOP, D018_B_TOP
show_bot_tab
	!byte D018_A_BOT, D018_B_BOT
