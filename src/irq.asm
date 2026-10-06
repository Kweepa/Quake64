; Raster chain. No CIA Timer A — keys/SFX once per mid-split (PAL/NTSC sample_ms).
; Phases: 0=HUD→view ($d018+$d021), 1=mid-split ($d018), 2=flyback UI ($d018+$d021).
;
; Mid split (right border, timed):
;   1. IRQ on line L-2 = 184. The handler prologue is ~60 cycles, so the poll
;      below always runs, at 1 MHz and at turbo.
;   2. Poll $d012 until == L = 186 (the raster edge anchors the write, not IRQ
;      latency)
;   3. jsr rb_delay (rbdelay.asm): menu-calibrated count in rb_n_* ($08F5-6),
;      or the 1 MHz count. It tracks the CPU:VIC ratio, so a turbo C64 lands
;      at the same video cycle as 1 MHz.
;   4. pla / sta $d018
; Target: write on L at cycle 48..55 after the edge. Col 31's g-access ends at
; 47, and sprite 0-2 DMA stalls the CPU from 55. A later write meets sprite
; 6/7 BA (cycle 4 of 187) or the badline BA (cycle 12) and slips a whole line.
; tools/sim_rbsplit.py runs these bytes against a raster model at 1-64x.
; HUD→view is untimed (see .view).
; Entered at/after L (stalled IRQ, sei tail): write immediately, no poll/burn.
; Mid-split then: accum_keys, flush SFX, update_sfx, snapshot holds.
; Flyback stays ASAP on 251.
!zone irq
!source "rbdelay.asm"

nmi_rti
	rti

; $FFFA–$FFFF (RAM under KERNAL / UI char 255) and KERNAL $0314/8.
; Call with I/O in so $Dxxx is VIC; $E000+ writes still hit RAM.
; Writes $0314=irq_entry. CIA1 TA must already be off (load_irq_off / init_irq).
install_irq_vectors
	lda #<nmi_rti
	sta $fffa
	sta $0318
	lda #>nmi_rti
	sta $fffb
	sta $0319
	lda #<reboot_game
	sta $fffc
	lda #>reboot_game
	sta $fffd
	lda #<irq_entry
	sta $fffe
	sta $0314
	lda #>irq_entry
	sta $ffff
	sta $0315
	rts

init_irq
	lda #$7f
	sta $dc0d
	sta $dd0d
	lda $dc0d
	lda $dd0d

	; $01=$30 fetches $FFFA–$FFFF (UI char 255, unused). Also KERNAL $0314/8
	; for $01=$36. Menu sfx owns these until GAME init.
	jsr install_irq_vectors

	lda #0
	sta irq_phase
	sta frame_flag
	sta turn_acc_l
	sta turn_acc_h
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh
	sta sfx_q_len
	ldx #11
-
	sta in_fwd,x
	dex
	bpl -

	; PAL/NTSC → sample_ms (KERNAL $02a6: 0=NTSC, 1=PAL)
	lda $01
	pha
	lda #$37
	sta $01
	ldx #SAMPLE_MS_NTSC
	lda $02a6
	beq +
	ldx #SAMPLE_MS_PAL
+
	stx sample_ms
	stx sample_ms_chk
	lda #0
	sta spd_trip
	pla
	sta $01

	lda #RASTER_VIEW
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #1
	sta $d01a

	; Mid-split delay cell: menu-calibrated; hi 0 / above RB_HI_LIM (cold
	; start, no menu) → the 1 MHz count.
	lda rb_n_hi
	beq .rbi_dflt
	cmp #RB_HI_LIM + 1
	bcc .rbi_ok
.rbi_dflt
	lda #1
	sta rb_n_hi
	lda #RB_K_SPLIT
	sta rb_n_lo
.rbi_ok
	rts

+rb_delay_body

; A/$01 saved first; VIC stores before any mid-split work.
irq_entry
	pha
	lda $01
	pha
	lda #BANK_IO				; I/O + KERNAL, BASIC out
	sta $01

	lda $d019
	and #1
	bne .do
	; Not raster: RTI, no CIA1 ack. CIA1 TA + this vector = IRQ storm.
	; Loaders: jsr load_irq_off. Never $0314=irq_entry while CIA1 TA lives.
	pla
	sta $01
	pla
	rti
.do
	sta $d019

	lda irq_phase
	beq .view
	cmp #1
	beq .split
	jmp .top

; Mid-viewport: preload, poll to 186, delay, right-border $d018, then keys/SFX.
; accum_keys adds sample_ms into in_* each video frame; main snapshots.
; IRQ_DEBUG_SPLIT: border white from the prologue, red right after the $d018
; store (nothing added before it). Red lands at write+6 cycles on line 186; the
; right border (cycles ~56-62) shows white→red when the write is in [50,56].
.split
	txa
	pha
	tya
	pha
	lda show_d018_bot
	pha
!if IRQ_DEBUG_SPLIT = 1 {
	lda #COL_WHITE
	sta $d020
}
	lda $d012
	cmp #RASTER_SPLIT_LINE
	bcs .split_w
	lda #RASTER_SPLIT_LINE
-
	cmp $d012
	bne -
	jsr rb_delay
.split_w
	pla
	sta $d018
!if IRQ_DEBUG_SPLIT = 1 {
	lda #COL_HURT
	sta $d020
}
	lda #RASTER_TOP
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #2
	sta irq_phase
	jsr accum_keys
	jsr flush_sfx
	jsr update_sfx
	jsr irq_elev_noise
	pla
	tay
	pla
	tax
	pla
	sta $01
	pla
	rti

; HUD → viewport: untimed. HUD row 8 (lines 115-122) is $c0 (solid glyph) on
; black colour RAM, and its c-access ran on 115. The IRQ is on 118; both stores
; land on 119-120, so lines 119-122 render the viewport charset's solid glyph:
; black whatever $d021 is. Nothing depends on the store cycle, the CPU:VIC
; ratio, or sprite DMA (an enemy-muzzle / splat sprite on 123 stalls reads
; from cycle 4 to 55, which used to push a timed $d021 a line late). Only
; badline 123's c-access (cycle 12) has to come after them.
.view
	txa
	pha
	tya
	pha
	ldx show_buf
	lda show_top_tab,x
	sta $d018
	lda col_bg
	sta $d021
	lda show_bot_tab,x
	sta show_d018_bot
	lda #RASTER_SPLIT
	sta $d012
	lda #1
	sta irq_phase
	lda den_arm
	cmp #2
	bne .view_pop
	lda #0
	sta den_arm
	lda $d011
	ora #%00010000				; DEN on after viewport charset
	sta $d011
.view_pop
	pla
	tay
	pla
	tax
	pla
	sta $01
	pla
	rti

; Lower flyback: UI charset + black bg — long before badline 51.
.top
	txa
	pha
	tya
	pha
	lda #D018_A_UI
	sta $d018
	lda #COL_HUD_BG
	sta $d021
	lda #RASTER_VIEW
	sta $d012
	lda #0
	sta irq_phase
	inc frame_flag
	jsr prof_read_casc
	lda sample_ms
	cmp sample_ms_chk
	beq .top_ok
	lda sample_ms_chk
	sta sample_ms
	inc spd_trip
	lda #COL_WHITE
	sta vic_border
.top_ok
	jsr irq_publish_vic
	pla
	tay
	pla
	tax
	pla
	sta $01
	pla
	rti

; Y = 0,2,4,… offset from in_fwd; add sample_ms, saturate at 65535
irq_add_ms
	clc
	lda in_fwd,y
	adc sample_ms
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
	sta in_wpn_gren
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
	; J/K share PA4 $EF — J look left, K use (SquareDoom)
	lda #$ef
	sta $dc00
	lda $dc01
	tax
	and #$04
	bne .noj
	lda keys
	ora #KEY_J
	sta keys
	ldy #in_turn_l - in_fwd
	jsr irq_add_ms
.noj
	txa
	and #$20				; K = use
	bne .nok
	lda keys
	ora #KEY_K
	sta keys
	lda #1
	sta in_use
.nok
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

; Publish in_* → hold_* / key_* then clear (main, once per game frame).
; IRQ only accumulates into in_* each mid-split — do not snapshot there or
; a slow game frame only sees one video tick of hold ms.
; Each 16-bit hold slot is sei-atomic vs irq_add_ms (lost/torn ticks).
snapshot_input
	ldx #0
.si_ms
	php
	sei
	lda in_fwd,x
	sta hold_fwd,x
	lda in_fwd+1,x
	sta hold_fwd+1,x
	lda #0
	sta in_fwd,x
	sta in_fwd+1,x
	plp
	inx
	inx
	cpx #12
	bcc .si_ms
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
	lda in_use
	sta key_use
	lda #0
	sta in_use
	rts

; V3 rumble from elev_noise_n. Bolt crackle takes the voice while ch_bolt is live.
irq_elev_noise
	lda ch_bolt_l
	ora ch_bolt_h
	ora sham_arc
	beq .iene_elev
	lda sfx_index+2
	bpl .iene_rts
	jsr rnd8
	and #$3f
	clc
	adc #$20
	sta $d40f
	jmp enp_rest
.iene_elev
	lda elev_noise_n
	beq .iene_off
	jmp elev_noise_restore
.iene_off
	lda sfx_index+2
	bpl .iene_rts
	lda #0
	sta $d412
.iene_rts
	rts

; Snapshot then build turn + wish from hold_*.
read_input
	jsr snapshot_input
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
