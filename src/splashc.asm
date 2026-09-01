; splashc.prg — Koala matrix/colour staged at $4000, then do_splash helpers.
; Boot LOADs this, then JSR do_splash: copy matrix → SCREEN ($5C00) and colour
; → $D800, clear bitmap, MCM on, LOAD splash pixels.
; USE_KRILL=1: then LOADER+INSTALL, JSR install. Does not load MENU — that
; would overwrite these helpers (menu grows to $5300).
!cpu 6502
!to "splashc.prg", cbm

!source "mem.asm"

clr_ptr		= $fb

*= SPLASH_MAT
!binary "../tmp/splashc_data.bin"
!if * != do_splash {
	!error "splashc data size mismatch; pc=$", *
}

	jsr copy_splash_mat
	jsr copy_splash_col
	jsr clear_bitmap
	jsr splash_vic			; matrix + colour RAM live; bitmap black

	lda #6
	ldx #<name_splash
	ldy #>name_splash
	jsr load_sa1
	bcs .fail
	jsr splash_vic			; KERNAL LOAD RMW of $dd00; keep bank 1

!if USE_KRILL {
	lda #6
	ldx #<name_loader
	ldy #>name_loader
	jsr load_sa1
	bcs .fail
	jsr splash_vic
	lda #7
	ldx #<name_install
	ldy #>name_install
	jsr load_sa1
	bcs .fail
	jsr splash_vic
	jsr KRILL_INSTALL			; C=1 → no fallback, hang loudly
	bcs .fail
	jsr splash_vic			; Krill DDRA=$03 — absolute $dd00 only
}
	rts
.fail
	lda #BANK_LOADER
	sta $01
.hang
	jmp .hang

; Staging matrix @ $4000 → live SCREEN @ $5C00 (menu $d018).
copy_splash_mat
	ldx #0
.csm
	lda SPLASH_MAT,x
	sta SCREEN,x
	lda SPLASH_MAT + $100,x
	sta SCREEN + $100,x
	lda SPLASH_MAT + $200,x
	sta SCREEN + $200,x
	inx
	bne .csm
	ldx #0
.csm_t
	lda SPLASH_MAT + $300,x
	sta SCREEN + $300,x
	inx
	cpx #KOALA_TAIL
	bne .csm_t
	rts

copy_splash_col
	ldx #0
.csc
	lda SPLASH_COL,x
	sta KOALA_COL_RAM,x
	lda SPLASH_COL + $100,x
	sta KOALA_COL_RAM + $100,x
	lda SPLASH_COL + $200,x
	sta KOALA_COL_RAM + $200,x
	inx
	bne .csc
	ldx #0
.csc_t
	lda SPLASH_COL + $300,x
	sta KOALA_COL_RAM + $300,x
	inx
	cpx #KOALA_TAIL
	bne .csc_t
	lda SPLASH_BG
	sta $d021
	sta $d020
	rts

clear_bitmap
	lda #<BITMAP
	sta clr_ptr
	lda #>BITMAP
	sta clr_ptr + 1
	ldx #32
	lda #0
	tay
.cb
	sta (clr_ptr),y
	iny
	bne .cb
	inc clr_ptr + 1
	dex
	bne .cb
	rts

; VIC bank 1 MCM bitmap. Absolute $dd00 — RMW poisons Krill IEC after install.
; Matrix $5C00 / bitmap $6000 so MENU load can smash $4000 staging.
splash_vic
	lda #%00000010			; VIC bank 1; upper 6 bits 0
	sta $dd00
	lda $d011
	and #%10000111			; clear ECM/BMM/DEN/RSEL
	ora #%00111011			; bitmap + DEN + 25 rows
	sta $d011
	lda $d016
	and #%11100111
	ora #%00011000			; CSEL + MCM
	sta $d016
	lda #%01111000			; matrix $5C00, bitmap $6000
	sta $d018
	lda #0
	sta $d015
	sta $d01a
	lda SPLASH_BG
	sta $d021
	sta $d020
	rts

load_sa1
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #1
	jsr $ffba
	lda #0
	jsr $ffd5
	php
	lda #1
	jsr $ffc3
	plp
	rts

name_splash
	!text "SPLASH"
	!byte 0
!if USE_KRILL {
name_loader
	!text "LOADER"
	!byte 0
name_install
	!text "INSTALL"
	!byte 0
}

end_splashc = *
!if end_splashc > SCREEN {
	!error "splashc helpers overlap live matrix; end=$", end_splashc
}
