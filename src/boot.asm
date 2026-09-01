; Quake64 disposable boot — fits LOADER_BASE..REBOOT_STUB-1.
; LOAD splashc @ $4000 → JSR do_splash (koala colour then pixels; Krill install
; if USE_KRILL) → MENU @ $0900 → JSR menu → TAB + JSR copy_tab (+3) → file_tab
; → JMP $0900.
; USE_KRILL=1: loadraw after splashc installed Krill. Default: KERNAL $FFD5.
; File-table index in .xi (KERNAL LOAD clobbers ZP — do not keep ptr in $ae/$af).
!cpu 6502
!to "boot.prg", cbm

!source "mem.asm"

*= LOADER_BASE
!byte $0b, $08, $0a, $00, $9e, $32, $30, $36, $31, $00, $00, $00	; SYS 2061

*= $080d
boot_start
	lda #$36
	sta $01
	jsr $ff84				; IOINIT
	lda $d011
	and #%11101111				; DEN off until colour is in
	sta $d011
	lda #0
	sta $d020				; border shows even with DEN=0
	cli

	lda #7
	ldx #<name_splashc
	ldy #>name_splashc
	jsr load_sa1
	bcs .fail
	jsr do_splash

	; MENU → $0900 (header address), run difficulty select
	ldx #<name_menu
	ldy #>name_menu
	jsr load_file
	bcs .fail
	lda #%00000010			; LOAD RMW of $dd00; keep bank 1
	sta $dd00
	jsr LOCODE_BASE

	; TAB → $8000 (header address), copy into charset tails via MENU+3
	ldx #<name_tab
	ldy #>name_tab
	jsr load_file
	bcs .fail
	jsr MENU_COPY_TAB

	; Walk the 0-terminated name list; an empty name ends it.
	ldx #0
.next
	lda file_tab,x
	beq .done
	stx .xi
	txa
	clc
	adc #<file_tab
	tax
	lda #>file_tab
	adc #0
	tay
	jsr load_file
	bcs .fail
	ldx .xi
.skip
	inx
	lda file_tab,x
	bne .skip
	inx					; step past the terminator
	jmp .next

.done
	ldx #$ff
	txs
	jmp LOCODE_BASE

.fail
	lda #$35
	sta $01
.hang
	jmp .hang

; KERNAL LOAD, SA=1 (address from the PRG header). A=len, X/Y=name.
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

; X/Y = 0-terminated name. Dest from PRG header.
load_file
!if USE_KRILL {
	sei
	lda #BANK_LOADER
	sta $01
	clc
	jsr loadraw
	php
	lda #$36
	sta $01
	plp
	cli
	rts
} else {
	stx .lf_lda+1
	sty .lf_lda+2
	ldy #0
.lf_lda
	lda $ffff,y
	beq .lf_got
	iny
	bne .lf_lda
.lf_got
	tya
	ldx .lf_lda+1
	ldy .lf_lda+2
	jmp load_sa1
}

.xi	!byte 0

file_tab
	!text "FNT"
	!byte 0
	!text "SCR"
	!byte 0
	!text "SQT"
	!byte 0
	!text "GAME"
	!byte 0
	!byte 0					; end of list

name_menu
	!text "MENU"
	!byte 0
name_tab
	!text "TAB"
	!byte 0
name_splashc
	!text "SPLASHC"

end_boot = *
!if end_boot > REBOOT_STUB {
	!error "Boot overlaps REBOOT_STUB; end=$", end_boot
}
