; Packed-map SoA accessors. Field labels are 16-bit BSS pointers.
; Macros load field id = (label-room_x)/2 and jsr map_* in mapacc_rt.asm.
!zone mapacc

!macro beq_far .t {
	bne @s
	jmp .t
@s
}
!macro bne_far .t {
	beq @s
	jmp .t
@s
}
!macro bcs_far .t {
	bcc @s
	jmp .t
@s
}
!macro bcc_far .t {
	bcs @s
	jmp .t
@s
}

!macro lda_mx .fld {
	lda #(.fld - room_x) / 2
	jsr map_lda_x
}
!macro sta_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_sta_x
}
!macro cmp_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_cmp_x
}
!macro adc_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_adc_x
}
!macro sbc_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_sbc_x
}
!macro ora_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_ora_x
}
!macro and_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_and_x
}
!macro eor_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_eor_x
}
!macro ldy_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_ldy_x
}
!macro ldx_mx .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_ldx_x
}
!macro lda_my .fld {
	lda #(.fld - room_x) / 2
	jsr map_lda_y
}
!macro sta_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_sta_y
}
!macro cmp_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_cmp_y
}
!macro adc_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_adc_y
}
!macro sbc_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_sbc_y
}
!macro ora_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_ora_y
}
!macro and_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_and_y
}
!macro eor_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_eor_y
}
!macro ldx_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_ldx_y
}
!macro ldy_my .fld {
	sta map_sv_a
	lda #(.fld - room_x) / 2
	jsr map_ldy_y
}

