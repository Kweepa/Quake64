; Raster chain + CIA1 Timer A key hold (SquareDoom-style)
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

	lda #<irq_entry
	sta $fffe
	sta $0314
	lda #>irq_entry
	sta $ffff
	sta $0315

	lda #0
	sta irq_phase
	sta frame_flag
	sta in_fwd
	sta in_back
	sta in_strafel
	sta in_strafer
	sta in_turn_l
	sta in_turn_r
	sta turn_acc_l
	sta turn_acc_h
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh

	lda #SAMPLE_TA_LO
	sta $dc04
	lda #SAMPLE_TA_HI
	sta $dc05
	lda #$81				; enable CIA1 TA IRQ
	sta $dc0d
	lda #$11				; TA start + force load
	sta $dc0e

	lda #RASTER_SPLIT
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #1
	sta $d01a
	rts

irq_entry
	pha
	txa
	pha
	tya
	pha
	lda $01
	pha
	lda #$35
	sta $01

	lda $d019
	and #1
	beq .cia
	sta $d019
	jsr raster_body
.cia
	lda $dc0d
	and #1
	beq .out
	jsr accum_keys
.out
	pla
	sta $01
	pla
	tay
	pla
	tax
	pla
	rti

raster_body
	lda irq_phase
	beq .split
	cmp #1
	beq .hud

	ldx show_buf
	lda show_top_tab,x
	sta $d018
	lda show_bot_tab,x
	sta show_d018_bot
	lda col_sky
	sta $d021
	lda #RASTER_SPLIT
	sta $d012
	lda #0
	sta irq_phase
	inc frame_flag
	rts

.split
	lda show_d018_bot
	sta $d018
	lda col_floor
	sta $d021
	lda #RASTER_HUD
	sta $d012
	lda #1
	sta irq_phase
	rts

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
	rts

; A = counter → min(A+SAMPLE_MS, 255)
irq_add_ms
	clc
	adc #SAMPLE_MS
	bcc +
	lda #255
+
	rts

accum_keys
	lda #0
	sta keys
	; W/A/S PA1 $FD
	lda #$fd
	sta $dc00
	lda $dc01
	tax
	and #$02
	bne .now
	lda keys
	ora #KEY_W
	sta keys
	lda in_fwd
	jsr irq_add_ms
	sta in_fwd
.now
	txa
	and #$04
	bne .noa
	lda keys
	ora #KEY_A
	sta keys
	lda in_strafel
	jsr irq_add_ms
	sta in_strafel
.noa
	txa
	and #$20
	bne .nos
	lda keys
	ora #KEY_S
	sta keys
	lda in_back
	jsr irq_add_ms
	sta in_back
.nos
	; D PA2 $FB
	lda #$fb
	sta $dc00
	lda $dc01
	and #$04
	bne .nod
	lda keys
	ora #KEY_D
	sta keys
	lda in_strafer
	jsr irq_add_ms
	sta in_strafer
.nod
	; J/K share PA4 $EF — only J is look (yaw)
	lda #$ef
	sta $dc00
	lda $dc01
	and #$04
	bne .noj
	lda keys
	ora #KEY_J
	sta keys
	lda in_turn_l
	jsr irq_add_ms
	sta in_turn_l
.noj
	; L PA5 $DF
	lda #$df
	sta $dc00
	lda $dc01
	and #$04
	bne .nol
	lda keys
	ora #KEY_L
	sta keys
	lda in_turn_r
	jsr irq_add_ms
	sta in_turn_r
.nol
	lda #$7f
	sta $dc00
	rts

; Snapshot IRQ hold ms; build turn + 8.8 wish. Call under I/O mapped.
read_input
	sei
	lda in_fwd
	sta hold_fwd
	lda in_back
	sta hold_back
	lda in_strafel
	sta hold_strafel
	lda in_strafer
	sta hold_strafer
	lda in_turn_l
	sta hold_turn_l
	lda in_turn_r
	sta hold_turn_r
	lda #0
	sta in_fwd
	sta in_back
	sta in_strafel
	sta in_strafer
	sta in_turn_l
	sta in_turn_r
	cli

	lda #0
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh

	; net turn: right − left
	lda hold_turn_r
	cmp hold_turn_l
	beq .tnone
	bcs .tright
	lda hold_turn_l
	sec
	sbc hold_turn_r
	sta vel_ms
	jsr turn_deliver
	eor #$ff
	clc
	adc #1
	clc
	adc yaw
	sta yaw
	jmp .tnone
.tright
	lda hold_turn_r
	sec
	sbc hold_turn_l
	sta vel_ms
	jsr turn_deliver
	clc
	adc yaw
	sta yaw
.tnone
	rts

; turn_acc += vel_ms<<6; A = turn_acc>>10; turn_acc &= $03FF
turn_deliver
	lda vel_ms
	tax
	lsr
	lsr
	sta pp_tmp_h			; hi = vel>>2
	txa
	and #3
	asl
	asl
	asl
	asl
	asl
	asl
	sta pp_tmp_l			; lo = (vel&3)<<6
	clc
	lda turn_acc_l
	adc pp_tmp_l
	sta turn_acc_l
	lda turn_acc_h
	adc pp_tmp_h
	sta turn_acc_h
	tay
	and #3
	sta turn_acc_h
	tya
	lsr
	lsr
	rts
