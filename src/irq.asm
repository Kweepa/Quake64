; Raster chain. CIA1 Timer A runs for key hold + SFX but IRQs stay masked —
; poll $dc0d from raster_body after $d018 so keys/SFX never delay a split.
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
	sta turn_acc_l
	sta turn_acc_h
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh
	ldx #11
-
	sta in_fwd,x
	dex
	bpl -

	lda #SAMPLE_TA_LO
	sta $dc04
	lda #SAMPLE_TA_HI
	sta $dc05
	lda #$11				; TA start + force load (IRQ stays masked; poll $dc0d)
	sta $dc0e

	lda #RASTER_VIEW
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
	beq .out
	sta $d019
	jsr raster_body
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
	beq .view
	cmp #1
	beq .split

	ldx show_buf
	lda show_ui_tab,x
	sta $d018
	lda #COL_HUD_BG
	sta $d021
	lda #RASTER_VIEW
	sta $d012
	lda #0
	sta irq_phase
	inc frame_flag
	jmp poll_keys

.view
	ldx show_buf
	lda show_top_tab,x
	sta $d018
	lda show_bot_tab,x
	sta show_d018_bot
	lda col_sky
	sta $d021
	lda #RASTER_SPLIT
	sta $d012
	lda #1
	sta irq_phase
	jmp poll_keys

.split
	lda show_d018_bot
	sta $d018
	lda col_floor
	sta $d021
	lda #RASTER_TOP
	sta $d012
	lda #2
	sta irq_phase
poll_keys
	lda $dc0d
	and #1
	beq .nokeys
	jsr accum_keys
	jsr update_sfx
.nokeys
	rts

; Y = 0,2,4,… offset from in_fwd; add SAMPLE_MS, saturate at 65535
irq_add_ms
	clc
	lda in_fwd,y
	adc #SAMPLE_MS
	sta in_fwd,y
	lda in_fwd+1,y
	adc #0
	sta in_fwd+1,y
	bcc +
	lda #$ff
	sta in_fwd,y
	sta in_fwd+1,y
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
	ldy #in_fwd - in_fwd
	jsr irq_add_ms
.now
	txa
	and #$04
	bne .noa
	lda keys
	ora #KEY_A
	sta keys
	ldy #in_strafel - in_fwd
	jsr irq_add_ms
.noa
	txa
	and #$20
	bne .nos
	lda keys
	ora #KEY_S
	sta keys
	ldy #in_back - in_fwd
	jsr irq_add_ms
.nos
	txa
	and #$01				; 3 = nailgun
	bne .no3
	lda #1
	sta in_wpn_nail
.no3
	txa
	and #$08				; 4 = grenade launcher
	bne .no4
	lda #1
	sta in_wpn_rock
.no4
	; D PA2 $FB
	lda #$fb
	sta $dc00
	lda $dc01
	and #$04
	bne .nod
	lda keys
	ora #KEY_D
	sta keys
	ldy #in_strafer - in_fwd
	jsr irq_add_ms
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
	ldy #in_turn_l - in_fwd
	jsr irq_add_ms
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
	ldy #in_turn_r - in_fwd
	jsr irq_add_ms
.nol
	; 1 / 2 / SPACE on PA7 = $7F
	lda #$7f
	sta $dc00
	lda $dc01
	tax
	and #$01				; 1 = axe
	bne .no1
	lda #1
	sta in_wpn_axe
.no1
	txa
	and #$08				; 2 = shotgun
	bne .no2
	lda #1
	sta in_wpn_shot
.no2
	txa
	and #$10				; SPACE
	bne .nospc
	lda #1
	sta in_fire
.nospc
	rts

; Snapshot IRQ hold ms; build turn + 8.8 wish. Call under I/O mapped.
read_input
	sei
	ldx #11
-
	lda in_fwd,x
	sta hold_fwd,x
	lda #0
	sta in_fwd,x
	dex
	bpl -
	ldx #3
-
	lda in_wpn_axe,x
	sta key_wpn_axe,x
	lda #0
	sta in_wpn_axe,x
	dex
	bpl -
	lda in_fire
	sta key_fire
	lda #0
	sta in_fire
	cli

	lda #0
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh

	; net turn: right − left (16-bit ms)
	lda hold_turn_r + 1
	cmp hold_turn_l + 1
	bne .tcmp
	lda hold_turn_r
	cmp hold_turn_l
.tcmp
	beq .tnone
	bcs .tright
	sec
	lda hold_turn_l
	sbc hold_turn_r
	sta vel_ms
	lda hold_turn_l + 1
	sbc hold_turn_r + 1
	sta vel_msh
	jsr turn_deliver
	eor #$ff
	clc
	adc #1
	clc
	adc yaw
	sta yaw
	jmp .tnone
.tright
	sec
	lda hold_turn_r
	sbc hold_turn_l
	sta vel_ms
	lda hold_turn_r + 1
	sbc hold_turn_l + 1
	sta vel_msh
	jsr turn_deliver
	clc
	adc yaw
	sta yaw
.tnone
	rts

; turn_acc += vel_ms<<6 (24-bit); A = min(sum>>10, 255); turn_acc &= $03FF
turn_deliver
	lda vel_ms
	sta pp_tmp_l
	lda vel_msh
	sta pp_tmp_h
	lda #0
	sta hud_n
	ldx #6
.tdsh
	asl pp_tmp_l
	rol pp_tmp_h
	rol hud_n
	dex
	bne .tdsh
	clc
	lda turn_acc_l
	adc pp_tmp_l
	sta turn_acc_l
	lda turn_acc_h
	adc pp_tmp_h
	sta pp_tmp_h
	lda hud_n
	adc #0
	sta hud_n
	lda pp_tmp_h
	and #3
	sta turn_acc_h
	lda pp_tmp_h
	lsr
	lsr
	sta pp_tmp_l
	lda hud_n
	asl
	asl
	asl
	asl
	asl
	asl
	ora pp_tmp_l
	ldx hud_n
	cpx #4
	bcc +
	lda #255
+
	rts
