; VIC Bank 3, 24×16 unique-char viewport (192×128), double-buffer swap
!zone vic

init_vic
	lda $dd00
	and #%11111100			; VIC bank 3 = $C000–$FFFF
	sta $dd00

	lda #$1b				; DEN, 25 rows, YSCROLL=3, text mode
	sta $d011
	lda #$08				; 40 cols, no MCM
	sta $d016

	lda #D018_A_UI
	sta $d018
	lda #COL_BORDER
	sta $d020
	lda #COL_HUD_BG
	sta $d021

	lda #0
	sta $d015				; sprites off until init_weapon
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

; room_idx → col_bg/line/fx/wpn, viewport colour RAM, live $d021 / weapon if safe
apply_room_palette
	ldx room_idx
	lda room_bg,x
	sta col_bg
	lda room_line,x
	sta col_line
	lda room_fx,x
	sta col_fx
	lda room_wpn,x
	sta col_wpn
	sta $d027
	sta $d028
	sta $d029
	sta $d02a
	jsr fill_viewport_colour
	; irq_phase: 0=HUD band (leave black $d021), 1/2=viewport/below → room bg
	lda irq_phase
	beq .ardone
	lda col_bg
	sta $d021
.ardone
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

; Unique 0–255 char codes in both matrices (top 8 rows + bottom 8 rows)
fill_screens
	lda #<SCR_A
	sta init_ptr
	lda #>SCR_A
	sta init_ptr+1
	jsr .fill_one
	lda #<SCR_B
	sta init_ptr
	lda #>SCR_B
	sta init_ptr+1
.fill_one
	lda #0
	sta init_row				; row 0..24
.sr
	lda init_row
	cmp #25
	bcs .srdone
	ldy #0
	lda #0
.sc
	sta (init_ptr),y
	iny
	cpy #40
	bne .sc
	clc
	lda init_ptr
	adc #40
	sta init_ptr
	bcc +
	inc init_ptr+1
+
	inc init_row
	jmp .sr
.srdone
	rts

; After zero fill, stamp viewport char codes on A and B
stamp_viewport
	lda #<SCR_A
	sta src_ptr
	lda #>SCR_A
	sta src_ptr+1
	jsr .stamp
	lda #<SCR_B
	sta src_ptr
	lda #>SCR_B
	sta src_ptr+1
.stamp
	lda #0
	sta stamp_row
.strow
	lda stamp_row
	cmp #VIEW_H
	bcs .stdone
	; dest = base + VIEW_OFF + stamp_row*40
	lda src_ptr
	sta init_ptr
	lda src_ptr+1
	sta init_ptr+1
	ldx stamp_row
	beq .addcol
.add40
	clc
	lda init_ptr
	adc #40
	sta init_ptr
	bcc +
	inc init_ptr+1
+
	dex
	bne .add40
.addcol
	clc
	lda init_ptr
	adc #<VIEW_OFF
	sta init_ptr
	lda init_ptr+1
	adc #>VIEW_OFF
	sta init_ptr+1
	lda stamp_row
	and #7
	sta stamp_in
	ldy #0
.stcol
	tya
	asl
	asl
	asl
	clc
	adc stamp_in
	sta (init_ptr),y
	iny
	cpy #VIEW_W
	bne .stcol
	inc stamp_row
	jmp .strow
.stdone
	rts

; Viewport rows, cols 0–7 and 32–39: solid MARGIN_CH (black over $d021 brown)
stamp_margins
	lda #<SCR_A
	sta src_ptr
	lda #>SCR_A
	sta src_ptr+1
	jsr .one
	lda #<SCR_B
	sta src_ptr
	lda #>SCR_B
	sta src_ptr+1
.one
	lda #0
	sta stamp_row
.mr
	lda src_ptr
	sta init_ptr
	lda src_ptr+1
	sta init_ptr+1
	lda stamp_row
	clc
	adc #VIEW_ROW
	tax
	beq .cols
.add
	clc
	lda init_ptr
	adc #40
	sta init_ptr
	bcc +
	inc init_ptr+1
+
	dex
	bne .add
.cols
	lda #MARGIN_CH
	ldy #0
-
	sta (init_ptr),y
	iny
	cpy #VIEW_COL
	bne -
	ldy #VIEW_COL + VIEW_W
-
	sta (init_ptr),y
	iny
	cpy #40
	bne -
	inc stamp_row
	lda stamp_row
	cmp #VIEW_H
	bcc .mr
	rts

; $FF in unused col 24 / char 192, all four charset halves. $01=$34.
fill_margin_glyph
	lda #$34
	sta $01
	lda #$ff
	ldx #7
-
	sta CH_A_TOP + 24 * 64,x
	sta CH_A_BOT + 24 * 64,x
	sta CH_B_TOP + 24 * 64,x
	sta CH_B_BOT + 24 * 64,x
	dex
	bpl -
	lda #$35
	sta $01
	rts

clear_charsets
	lda #$34
	sta $01
	lda #0
	sta init_ptr
	lda #>CH_A_TOP
	sta init_ptr+1
	ldx #$20				; 8K = 32 pages
	ldy #0
	tya
.cl
	sta (init_ptr),y
	iny
	bne .cl
	inc init_ptr+1
	dex
	bne .cl
	lda #$35
	sta $01
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

; $01 must be $35. Publish show_buf's $d018 for the current band.
; Wait (IRQs on) until irq_phase is HUD (0) or post mid-split (2) so we never
; mask a split line or tear mid-viewport.
apply_show
-
	lda irq_phase
	beq .do				; 0 = HUD
	cmp #2
	bne -				; 1 = view top — wait
.do
	ldx show_buf
	lda show_bot_tab,x
	sta show_d018_bot
	lda irq_phase
	beq .ui
	; phase 2 — bottom half charset live
	lda show_d018_bot
	sta $d018
	rts
.ui
	lda #D018_A_UI			; HUD always matrix A (viewport still flips)
	sta $d018
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

show_top_tab
	!byte D018_A_TOP, D018_B_TOP
show_bot_tab
	!byte D018_A_BOT, D018_B_BOT
