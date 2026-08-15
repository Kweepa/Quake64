; Signed (A*Y)>>7 and perspective via log/antilog LUTs ($F800)
!zone math

; A, Y signed. A = (A*Y)/128, clamp ±127. $01=$34 (RAM LUTs).
; idx = log|A|+log|Y|-224 as 8-bit with carry, no 16-bit subtract.
smul7
	sta mul_a
	sty mul_b
	eor mul_b
	sta mul_sign
	lda mul_a
	bpl .ap
	eor #$ff
	clc
	adc #1
.ap
	beq .zero
	tax
	lda mul_b
	bpl .bp
	eor #$ff
	clc
	adc #1
.bp
	beq .zero
	tay
	lda LOGTAB,x
	clc
	adc LOGTAB,y
	bcc .noc
	cmp #224
	bcc .chi
	sbc #224
	tax
	lda ALOGTAB + $100,x
	jmp .got
.chi
	adc #32
	tax
	lda ALOGTAB,x
	jmp .got
.noc
	cmp #224
	bcc .zero
	sbc #224
	tax
	lda ALOGTAB,x
.got
	cmp #128
	bcc .ssgn
	lda #$7f
.ssgn
	bit mul_sign
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts
.zero
	lda #0
	rts

; Signed A → A = LOGTAB[|A|], Y = $00 or $80
signed_log
	ldy #0
	cmp #0
	bpl +
	ldy #$80
	eor #$ff
	clc
	adc #1
+
	tax
	lda LOGTAB,x
	rts

; A = log|u|, Y = log|v|, mul_sign = su eor sv ($00/$80)
; A = (u*v)>>7 via alog(loga+logb-224)
logadd7
	clc
	sty mul_b
	adc mul_b
	bcc .lnoc
	cmp #224
	bcc .lchi
	sbc #224
	tax
	lda ALOGTAB + $100,x
	jmp .lgot
.lchi
	adc #32
	tax
	lda ALOGTAB,x
	jmp .lgot
.lnoc
	cmp #224
	bcc .lzero
	sbc #224
	tax
	lda ALOGTAB,x
.lgot
	cmp #128
	bcc .lsgn
	lda #$7f
.lsgn
	bit mul_sign
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts
.lzero
	lda #0
	rts

; |A| * FOCAL / z_eye → A (signed), clamp PERSP_MAX
persp
	sta mul_sign
	bpl .abs
	eor #$ff
	clc
	adc #1
.abs
	bne +
	rts
+
	ldx z_eye
	bne .pzok
	lda #PERSP_MAX
	jmp .psgn
.pzok
	tax
	lda LOGTAB,x
	clc
	adc #LOG_FOCAL
	sta prod_l
	lda #0
	adc #0
	sta prod_h
	ldx z_eye
	sec
	lda prod_l
	sbc LOGTAB,x
	sta prod_l
	lda prod_h
	sbc #0
	bcc .zres
	sta prod_h
	jsr alog_fetch
	cmp #PERSP_MAX
	bcc .psgn
	lda #PERSP_MAX
	jmp .psgn
.zres
	lda #0
.psgn
	bit mul_sign
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts

; prod_h:prod_l = unsigned idx → A = alog[idx], 255 if idx>=512
alog_fetch
	lda prod_h
	beq .p0
	cmp #1
	beq .p1
	lda #255
	rts
.p1
	ldx prod_l
	lda ALOGTAB + $100,x
	rts
.p0
	ldx prod_l
	lda ALOGTAB,x
	rts
