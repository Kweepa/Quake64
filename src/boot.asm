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

	; --- bring up the Krill fastloader ---------------------------------
	; These two are the LAST KERNAL loads. LOADER carries its own address
	; ($EE08, under the KERNAL — LOAD writes go to RAM there); INSTALL sits
	; at $2000 and is transient, overwritten by MENU and GAME afterwards.
	lda #6
	ldx #<name_loader
	ldy #>name_loader
	jsr load_sa1
	bcs .fail
	lda #7
	ldx #<name_install
	ldy #>name_install
	jsr load_sa1
	bcs .fail
	jsr KRILL_INSTALL			; C=1 → no fallback, hang loudly
	bcs .fail

	; MENU → $0900 (header address), run difficulty select
	ldx #<name_menu
	ldy #>name_menu
	jsr krill_load
	bcs .fail
	jsr LOCODE_BASE

	; TAB → $8000 (header address), copy into charset tails via MENU+3
	ldx #<name_tab
	ldy #>name_tab
	jsr krill_load
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
	jsr krill_load
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
; Only used for LOADER and INSTALL, before Krill is up.
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

; Krill loadraw, X/Y = 0-terminated name. Carry CLEAR on entry, so the
; destination comes from the PRG header — every file here carries its own.
; BANK_LOADER unmaps the KERNAL, so this must run under SEI: the IRQ vector
; would otherwise be read from RAM at $fffe, which is uninitialised until FNT
; lands. C=0 ok, C=1 error.
krill_load
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
name_loader
	!text "LOADER"
	!byte 0
name_install
	!text "INSTALL"
	!byte 0

end_boot = *
!if end_boot > REBOOT_STUB {
	!error "Boot overlaps REBOOT_STUB; end=$", end_boot
}
