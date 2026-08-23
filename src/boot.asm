; Quake64 disposable boot — fits LOADER_BASE..REBOOT_STUB-1.
; MENU @ $0900 → JSR menu → TAB stage + JSR copy_tab (+3) → file_tab → JMP $0900.
; Per file: SETNAM / SETLFS / LOAD / CLOSE only.
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
	and #%11101111				; DEN off — IOINIT restores bank 0
	sta $d011
	lda #0
	sta $d020				; border shows even with DEN=0
	cli

	; MENU → $0900, run difficulty select
	lda #4
	ldx #<name_menu
	ldy #>name_menu
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #0
	jsr $ffba
	lda #0
	ldx #<LOCODE_BASE
	ldy #>LOCODE_BASE
	jsr $ffd5
	bcs .fail
	lda #1
	jsr $ffc3
	jsr LOCODE_BASE

	; TAB → $8000 (SA=0), copy into charset tails via MENU+3
	lda #3
	ldx #<name_tab
	ldy #>name_tab
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #0
	jsr $ffba
	lda #0
	ldx #<TAB_STAGING
	ldy #>TAB_STAGING
	jsr $ffd5
	bcs .fail
	lda #1
	jsr $ffc3
	jsr MENU_COPY_TAB

	ldx #0
.next
	lda file_tab,x
	beq .done
	sta .len
	inx
	stx .xi
	txa
	clc
	adc #<file_tab
	tax
	lda #>file_tab
	adc #0
	tay
	lda .len
	jsr load_sa1
	bcs .fail
	lda .xi
	clc
	adc .len
	tax
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

.len	!byte 0
.xi	!byte 0

file_tab
	!byte 3
	!text "FNT"
	!byte 3
	!text "SCR"
	!byte 3
	!text "SQT"
	!byte 4
	!text "GAME"
	!byte 0

name_menu
	!text "MENU"
name_tab
	!text "TAB"

end_boot = *
!if end_boot > REBOOT_STUB {
	!error "Boot overlaps REBOOT_STUB; end=$", end_boot
}
