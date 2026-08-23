; Packed-map SoA accessors.
;
; Field labels in map_bss.asm are 16-bit *pointers* (filled by bind_map),
; not the columns themselves. Never `lda en_x,x` / `sta room_bg,y` — that
; reads the pointer word in GAME BSS. Always these macros, or an explicit
; `lda (ptr),y` after setting a pointer from the bound table.
;
; Macros emit `lda $02id,x` (etc.): operand lo = field id = (.fld-room_x)/2,
; hi = MAP_SMC_HI sentinel. tools/mkreloc.py scans game.prg for those
; abs,x / abs,y ops and writes reloc.prg. LoadLevel patches the two operand
; bytes to the bound column address after bind_map. Do not execute these
; until after that patch.
;
; After GAME assemble, mkreloc.py must run before mkdisk.py (see build.bat).
!zone mapacc

!macro lda_mx .fld {
	lda MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro sta_mx .fld {
	sta MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro cmp_mx .fld {
	cmp MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro adc_mx .fld {
	adc MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro sbc_mx .fld {
	sbc MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro ora_mx .fld {
	ora MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro and_mx .fld {
	and MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro eor_mx .fld {
	eor MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro ldy_mx .fld {
	ldy MAP_SMC_BASE + ((.fld - room_x) / 2),x
}
!macro ldx_mx .fld {
	lda MAP_SMC_BASE + ((.fld - room_x) / 2),x
	tax
}
!macro lda_my .fld {
	lda MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro sta_my .fld {
	sta MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro cmp_my .fld {
	cmp MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro adc_my .fld {
	adc MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro sbc_my .fld {
	sbc MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro ora_my .fld {
	ora MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro and_my .fld {
	and MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro eor_my .fld {
	eor MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro ldx_my .fld {
	ldx MAP_SMC_BASE + ((.fld - room_x) / 2),y
}
!macro ldy_my .fld {
	lda MAP_SMC_BASE + ((.fld - room_x) / 2),y
	tay
}
