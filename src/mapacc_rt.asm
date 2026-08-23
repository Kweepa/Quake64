; Patch GAME abs,x/y operands from the reloc overlay (after bind_map).
; Reloc payload: count (word) then count × {operand_addr_lo, addr_hi, field_id}.
!zone mapacc_rt

patch_map_smc
	lda reloc_base
	sta src_ptr
	lda reloc_base+1
	sta src_ptr+1
	ldy #0
	lda (src_ptr),y
	sta nlo
	iny
	lda (src_ptr),y
	sta nhi
	ora nlo
	bne .go
	sec
	rts
.go
	clc
	lda src_ptr
	adc #2
	sta src_ptr
	bcc .ps
	inc src_ptr+1
.ps
	ldy #0
	lda (src_ptr),y
	sta dst_ptr
	iny
	lda (src_ptr),y
	sta dst_ptr+1
	iny
	lda (src_ptr),y
	asl
	bcs .hi
	tay
	lda room_x,y
	sta mp_l
	lda room_x+1,y
	sta mp_h
	jmp .wr
.hi
	tay
	lda room_x + $100,y
	sta mp_l
	lda room_x + $101,y
	sta mp_h
.wr
	ldy #0
	lda mp_l
	sta (dst_ptr),y
	iny
	lda mp_h
	sta (dst_ptr),y
	clc
	lda src_ptr
	adc #3
	sta src_ptr
	bcc .dec
	inc src_ptr+1
.dec
	lda nlo
	bne .d1
	dec nhi
.d1
	dec nlo
	lda nlo
	ora nhi
	bne .ps
	clc
	rts
