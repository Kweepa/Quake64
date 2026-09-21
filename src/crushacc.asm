; Crusher packed-column accessors. Pointers live at crush_* ($0896+).
; Y = SoA index. Uses mp_l/mp_h (free during play; overlay bind only at load).
!macro lda_cy .fld {
	lda .fld
	sta mp_l
	lda .fld+1
	sta mp_h
	lda (mp_l),y
}
!macro sta_cy .fld {
	sta crush_st
	lda .fld
	sta mp_l
	lda .fld+1
	sta mp_h
	lda crush_st
	sta (mp_l),y
}
