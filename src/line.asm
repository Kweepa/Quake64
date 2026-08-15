; Mike's 30k px/s drawer (Denial): 8× unrolled ORA #imm, DEX/BEQ end,
; cached (colptr),Y, always LTR, SMC jump into starting bit.
!zone line

col_lo
	!byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
	!byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
col_hi
	!byte 0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3
	!byte 4,4,4,4,5,5,5,5,6,6,6,6,7,7,7,7

; Preserve X (pixel countdown) and C for the next SBC.
y_cross_down
	stx save_x
	lda tile_half
	bne .ydclamp
	inc tile_half
	clc
	lda colptr+1
	adc #8
	sta colptr+1
	ldy #0
	ldx save_x
	sec
	rts
.ydclamp
	ldy #63
	ldx save_x
	sec
	rts

y_cross_up
	stx save_x
	lda tile_half
	beq .yuclamp
	dec tile_half
	sec
	lda colptr+1
	sbc #8
	sta colptr+1
	ldy #63
	ldx save_x
	sec
	rts
.yuclamp
	ldy #0
	ldx save_x
	sec
	rts

line_setup
	lda x0
	lsr
	lsr
	lsr
	tax
	lda y0
	cmp #64
	bcc .yt
	sbc #64
	tay
	lda #1
	sta tile_half
	lda col_hi,x
	clc
	adc draw_bot_hi
	jmp .p
.yt
	tay
	lda #0
	sta tile_half
	lda col_hi,x
	clc
	adc draw_top_hi
.p
	sta colptr+1
	lda col_lo,x
	sta colptr
	rts

draw_line
	lda x0
	cmp x1
	bcc .ord
	ldx x1
	sta x1
	stx x0
	lda y0
	ldx y1
	sta y1
	stx y0
.ord
	lda x1
	sec
	sbc x0
	sta dx
	lda y1
	sec
	sbc y0
	bcs .yp
	eor #$ff
	clc
	adc #1
	ldx #$ff
	bne .ys
.yp
	ldx #1
.ys
	sta dy
	stx sy

	lda x0
	and #7
	sta bitpos
	jsr line_setup
	ldx bitpos

	lda dx
	cmp dy
	bcc .steep

	lda dx
	lsr
	sta err_l
	lda sy
	bpl .dn
	lda sup_l,x
	sta .ju+1
	lda sup_h,x
	sta .ju+2
	ldx dx
	inx
	sec
.ju	jmp su0
.dn
	lda sdn_l,x
	sta .jd+1
	lda sdn_h,x
	sta .jd+2
	ldx dx
	inx
	sec
.jd	jmp sd0

.steep
	lda dy
	lsr
	sta err_l
	lda sy
	bpl .stdn
	lda stu_l,x
	sta .jt+1
	lda stu_h,x
	sta .jt+2
	ldx dy
	inx
	sec
.jt	jmp tu0
.stdn
	lda std_l,x
	sta .js+1
	lda std_h,x
	sta .js+2
	ldx dy
	inx
	sec
.js	jmp td0

!source "_line_bodies.asm"
