; Raster chain: charset split, HUD background, frame top
!zone irq

nmi_rti
	rti

init_irq
	lda #$7f
	sta $dc0d
	sta $dd0d
	lda $dc0d
	lda $dd0d

	lda #<nmi_rti
	sta $fffa
	sta $0318
	lda #>nmi_rti
	sta $fffb
	sta $0319

	lda #<raster_irq
	sta $fffe
	sta $0314
	lda #>raster_irq
	sta $ffff
	sta $0315

	lda #0
	sta irq_phase
	sta frame_flag
	lda #RASTER_SPLIT
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #1
	sta $d01a
	rts

raster_irq
	pha
	txa
	pha
	tya
	pha
	lda $01
	pha
	lda #$35
	sta $01
	lda #$ff
	sta $d019

	lda irq_phase
	beq .split
	cmp #1
	beq .hud

	; phase 2: top of frame — restore viewport $d018 after HUD split
	ldx show_buf
	lda show_top_tab,x
	sta $d018
	lda show_bot_tab,x
	sta show_d018_bot
	lda #COL_BG
	sta $d021
	lda #RASTER_SPLIT
	sta $d012
	lda #0
	sta irq_phase
	inc frame_flag
	jsr scan_keys
	jmp .out

.split
	lda show_d018_bot
	sta $d018
	lda #RASTER_HUD
	sta $d012
	lda #1
	sta irq_phase
	jmp .out

.hud
	ldx show_buf
	lda show_ui_tab,x
	sta $d018
	lda #COL_HUD_BG
	sta $d021
	lda #RASTER_TOP
	sta $d012
	lda #2
	sta irq_phase

.out
	pla
	sta $01
	pla
	tay
	pla
	tax
	pla
	rti

; Wolf64 CIA1 matrix: J = PA4/$EF bit 2, L = PA5/$DF bit 2.
scan_keys
	lda #0
	sta key_j
	sta key_l
	lda #$ef
	sta $dc00
	lda $dc01
	and #$04
	bne +
	inc key_j
+
	lda #$df
	sta $dc00
	lda $dc01
	and #$04
	bne +
	inc key_l
+
	lda #$7f
	sta $dc00
	rts
