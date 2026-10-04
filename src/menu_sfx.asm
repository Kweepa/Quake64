; Menu music + sprite mux. CIA1 Timer A (rate set by the tune's init, 25..48 Hz)
; calls MUSIC_PLAY; the raster IRQ muxes logo/cursor/hint sprites.
; Banks KERNAL out ($01=$35) so $fffe is live; boot restores $36 after menu.
; The menu has no interface sounds: all three SID voices belong to the tune.

!zone menu_sfx

; Needs: music_ok (mus file resident at $9000). Runs with I=1 on exit I=0.
menu_sfx_init
	sei
	lda #$35
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	lda $d019
	sta $d019
	lda #0
	sta music_en
	ldx #$18
.msi_clr
	sta $d400,x
	dex
	bpl .msi_clr
	lda effects_vol
	and #15
	sta $d418
	lda music_ok
	beq .msi_vec
	; Player owns $f0-$f7 only while it runs; MUSIC_INIT programs $dc04/05.
	jsr music_zp_swap
	lda #0
	jsr MUSIC_INIT
	jsr music_zp_swap
	lda #1
	sta music_en
.msi_vec
	lda #<menu_sfx_irq
	sta $fffe
	lda #>menu_sfx_irq
	sta $ffff
	lda #<menu_nmi_stub
	sta $fffa
	sta $0318
	lda #>menu_nmi_stub
	sta $fffb
	sta $0319
	lda $d011
	and #%01111111
	sta $d011
	lda #MUX_LOGO_RASTER
	sta $d012
	lda #0
	sta menu_mux_phase
	lda #1
	sta menu_raster_en
	lda #$81
	sta $dc0d
	lda #$11				; start + force-load latch
	sta $dc0e
	lda #1
	sta $d01a				; raster IRQ
	cli
	rts

; Exchange player ZP state with the menu's $f0-$f7.
music_zp_swap
	ldx #MUSIC_ZP_N - 1
.mzs
	lda MUSIC_ZP,x
	tay
	lda music_zp,x
	sta MUSIC_ZP,x
	tya
	sta music_zp,x
	dex
	bpl .mzs
	rts

; Caller holds I=1. Silence all three voices.
music_stop
	lda #0
	sta music_en
	sta $d404
	sta $d40b
	sta $d412
	sta $d406
	sta $d40d
	sta $d414
	rts

; Stop raster mux and hide sprites; music silenced.
; $d019 raster still latches when $d012 matches even if $d01a=0 — CIA
; ticks would remux unless menu_raster_en is clear first.
menu_raster_off
	sei
	lda #0
	sta menu_raster_en
	sta $d01a
	sta $d015
	sta hint_spr_en
	sta cursor_spr_en
	sta wip_spr_en
	lda $d019
	sta $d019
	jsr music_stop
	cli
	rts

; Leaves the state boot's KERNAL/Krill loads expect: CIA1 masked+stopped,
; raster off, $01=$36, I=0.
menu_sfx_done
	jsr menu_raster_off
	sei
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $dc0e
	lda #$36
	sta $01
	cli
	rts

menu_nmi_stub
	pha
	lda $01
	pha
	lda #$35
	sta $01
	lda $dd0d
	pla
	sta $01
	pla
	rti

menu_sfx_irq
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
	sta $d019
	and #1
	beq .msi_cia
	lda menu_raster_en
	beq .msi_cia
	lda menu_mux_phase
	beq .msi_logo
	cmp #1
	beq .msi_cur
	; phase 2 — hint keys, then wrap
	jsr mux_hint_spr
	lda #0
	sta menu_mux_phase
	lda $d011
	and #%01111111
	sta $d011
	lda #MUX_LOGO_RASTER
	sta $d012
	jmp .msi_cia
.msi_logo
	jsr mux_logo_spr
	lda #1
	sta menu_mux_phase
	lda $d011
	and #%01111111
	sta $d011
	lda #MUX_HINT_RASTER
	sta $d012
	jmp .msi_cia
.msi_cur
	lda cursor_spr_en
	beq .msi_skip_cur
	jsr mux_cursor_spr
	lda #2
	sta menu_mux_phase
	lda $d011
	and #%01111111
	sta $d011
	lda cursor_spr_y
	clc
	adc #21
	sta $d012
	jmp .msi_cia
.msi_skip_cur
	jsr mux_hint_spr
	lda #0
	sta menu_mux_phase
	lda $d011
	and #%01111111
	sta $d011
	lda #MUX_LOGO_RASTER
	sta $d012
.msi_cia
	lda $dc0d
	and #1
	beq .msi_rti
	lda music_en
	beq .msi_rti
	jsr music_zp_swap
	cli					; play ~1.7k cycles; raster mux must preempt
	jsr MUSIC_PLAY
	sei
	jsr music_zp_swap
.msi_rti
	pla
	sta $01
	pla
	tay
	pla
	tax
	pla
	rti
