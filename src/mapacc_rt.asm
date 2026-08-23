; Shared packed-map SoA accessors. A = field index (room_x=0).
; Pointer table is the consecutive !word block starting at room_x.
!zone mapacc_rt

map_set_mp
	asl
	bcs .hi
	tay
	lda room_x,y
	sta mp_l
	lda room_x+1,y
	sta mp_h
	rts
.hi
	tay
	lda room_x + $100,y
	sta mp_l
	lda room_x + $101,y
	sta mp_h
	rts

map_lda_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_sta_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda map_sv_a
	sta (mp_l),y
	ldy map_sv_y
	rts

map_cmp_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda map_sv_a
	cmp (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_adc_x
	php
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	plp
	lda map_sv_a
	adc (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_sbc_x
	php
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	plp
	lda map_sv_a
	sbc (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_ora_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda map_sv_a
	ora (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_and_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda map_sv_a
	and (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_eor_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda map_sv_a
	eor (mp_l),y
	php
	ldy map_sv_y
	plp
	rts

map_ldy_x
	jsr map_set_mp
	txa
	tay
	lda (mp_l),y
	tay
	lda map_sv_a
	rts

map_ldx_x
	sty map_sv_y
	jsr map_set_mp
	txa
	tay
	lda (mp_l),y
	tax
	ldy map_sv_y
	lda map_sv_a
	rts

map_lda_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda (mp_l),y
	rts

map_sta_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda map_sv_a
	sta (mp_l),y
	rts

map_cmp_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda map_sv_a
	cmp (mp_l),y
	rts

map_adc_y
	php
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	plp
	lda map_sv_a
	adc (mp_l),y
	rts

map_sbc_y
	php
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	plp
	lda map_sv_a
	sbc (mp_l),y
	rts

map_ora_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda map_sv_a
	ora (mp_l),y
	rts

map_and_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda map_sv_a
	and (mp_l),y
	rts

map_eor_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda map_sv_a
	eor (mp_l),y
	rts

map_ldx_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda (mp_l),y
	tax
	lda map_sv_a
	rts

map_ldy_y
	sty map_sv_y
	jsr map_set_mp
	ldy map_sv_y
	lda (mp_l),y
	tay
	lda map_sv_a
	rts

