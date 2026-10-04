; Menu music loader + Jukebox switch. MUS1..MUS5 (tools/genmusic.py) load at
; MUSIC_BASE ($9000) from disk. Krill vs KERNAL is chosen at assemble time
; (build.bat assembles menu.asm once per disk).

!zone menu_music

; run_menu entry: KERNAL IRQ alive, $01=$36, I=0 (same state boot loads in).
music_pick_load
	lda $a2					; jiffy clock lo
	eor $dc04				; free-running KERNAL timer A lo
.mpl_mod
	cmp #5
	bcc .mpl_ok
	sbc #5
	bcs .mpl_mod
.mpl_ok
	sta music_track
	; fall through

; A = track 0..4 → MUSn at $9000. Needs I=0 and $01=$36 on entry (see
; menu_sfx_done). Leaves $01=$36, I=0. music_ok = 1 when the file loaded.
music_load
	clc
	adc #'1'
	sta music_name + 3
	lda #0
	sta music_ok
!if USE_KRILL {
	ldx #<music_name
	ldy #>music_name
	sei
	lda #BANK_LOADER
	sta $01
	clc					; address from the PRG header
	jsr loadraw
	php
	lda #BANK_IO
	sta $01
	plp
	cli
} else {
	lda #4
	ldx #<music_name
	ldy #>music_name
	jsr $ffbd				; SETNAM
	lda #1
	ldx $ba
	ldy #1					; SA=1 → PRG header address
	jsr $ffba				; SETLFS
	lda #0
	jsr $ffd5				; LOAD
	php
	lda #1
	jsr $ffc3				; CLOSE
	plp
}
	bcs .ml_rts
	inc music_ok
.ml_rts
	lda #%00000010				; LOAD RMW of $dd00; keep VIC bank 1
	sta $dd00
	rts

; A = track 0..4, menu IRQs live. Silences, reloads, restarts, repaints.
jukebox_select
	sta music_track
	lda wip_spr_en
	pha
	jsr menu_sfx_done			; raster+CIA off, music silent, $01=$36, I=0
	jsr menu_blank				; no sprite DMA during the transfer
	lda music_track
	jsr music_load
	pla
	sta wip_spr_en
	jsr menu_sfx_init			; MUSIC_INIT + timers + raster mux
	jsr sync_juke_title
	jmp draw_menu

; "Now playing: Track N" heading of the Jukebox menu.
sync_juke_title
	lda music_track
	clc
	adc #'1'
	sta str_sec_juke + 19
	rts

music_name	!text "MUS1", 0
