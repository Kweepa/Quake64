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

; nlo:nhi * Y (signed) >> 7 → nlo:nhi. Judd 8×8 twice, then >>7.
smul16_7
	sty mul_y
	lda nhi
	eor mul_y
	sta mul_sign
	lda nhi
	bpl .nabs
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.nabs
	lda mul_y
	bpl .yabs
	eor #$ff
	clc
	adc #1
	sta mul_y
.yabs
	lda nlo
	ora nhi
	beq .z16
	lda mul_y
	beq .z16
	lda nlo
	ldy mul_y
	jsr umul8j
	lda prod_l
	sta dlo
	lda prod_h
	sta dhi
	lda nhi
	ldy mul_y
	jsr umul8j
	clc
	lda dhi
	adc prod_l
	sta dhi
	lda prod_h
	adc #0
	sta ylo
	ldx #7
.sh7
	lsr ylo
	ror dhi
	ror dlo
	dex
	bne .sh7
	lda dlo
	sta nlo
	lda dhi
	sta nhi
	bit mul_sign
	bpl +
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
+
	rts
.z16
	lda #0
	sta nlo
	sta nhi
	rts

; nlo:nhi (signed) * ylo:yhi (unsigned) >> 16 → nlo:nhi unsigned abs.
; mul_sign = $80 if coord was negative. Four umul8j plus add. Clobbers dlo/dhi/rot2.
smul16u16h
	lda #0
	sta mul_sign
	lda nhi
	bpl .su_p
	lda #$80
	sta mul_sign
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.su_p
	lda nlo
	ora nhi
	beq .su_z
	lda ylo
	ora yhi
	beq .su_z
	lda nlo
	ldy ylo
	jsr umul8j			; bits 0–15; keep hi for carry
	lda prod_h
	sta dlo
	lda nlo
	ldy yhi
	jsr umul8j			; bits 8–23
	clc
	lda dlo
	adc prod_l
	sta dlo
	lda prod_h
	adc #0
	sta dhi
	lda #0
	adc #0
	sta rot2
	lda nhi
	ldy ylo
	jsr umul8j			; bits 8–23
	clc
	lda dlo
	adc prod_l
	sta dlo
	lda dhi
	adc prod_h
	sta dhi
	lda rot2
	adc #0
	sta rot2
	lda nhi
	ldy yhi
	jsr umul8j			; bits 16–31
	clc
	lda dhi
	adc prod_l
	sta nlo
	lda rot2
	adc prod_h
	sta nhi
	rts
.su_z
	lda #0
	sta nlo
	sta nhi
	rts

; Unsigned A*Y → prod_l:prod_h. sq[a+b] - sq[|a-b|], tables (i*i)/4.
umul8j
	sta mul_a
	sty mul_b
	clc
	adc mul_b
	bcc .s0
	tax
	lda sqlo+$100,x
	sta prod_l
	lda sqhi+$100,x
	sta prod_h
	jmp .dif
.s0
	tax
	lda sqlo,x
	sta prod_l
	lda sqhi,x
	sta prod_h
.dif
	lda mul_a
	sec
	sbc mul_b
	bcs .dpos
	eor #$ff
	adc #1
.dpos
	tay
	sec
	lda prod_l
	sbc sqlo,y
	sta prod_l
	lda prod_h
	sbc sqhi,y
	sta prod_h
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

; A = (A * Y) / div_c, all signed. Clamp ±127. $01=$34.
lerpdv
	sta mul_a
	sty mul_b
	eor mul_b
	eor div_c
	sta mul_sign
	lda mul_a
	bpl .la
	eor #$ff
	clc
	adc #1
.la
	beq .lzero2
	sta mul_a
	lda mul_b
	bpl .lb
	eor #$ff
	clc
	adc #1
.lb
	beq .lzero2
	sta mul_b
	lda div_c
	bpl .lc
	eor #$ff
	clc
	adc #1
.lc
	beq .lzero2
	tax
	lda mul_a
	tay
	lda LOGTAB,y
	clc
	ldy mul_b
	adc LOGTAB,y
	sta prod_l
	lda #0
	adc #0
	sta prod_h
	sec
	lda prod_l
	sbc LOGTAB,x
	sta prod_l
	lda prod_h
	sbc #0
	bcc .lzero2
	sta prod_h
	jsr alog_fetch
	cmp #128
	bcc .lsgn2
	lda #$7f
.lsgn2
	bit mul_sign
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts
.lzero2
	lda #0
	rts

; A=p1 Y=p0 → prod = p1-p0 as signed 16-bit
ssub16
	sta mul_b
	sty mul_a
	lda #0
	sta prod_h
	lda mul_b
	bpl +
	dec prod_h
+
	lda #0
	sta mul_sign
	lda mul_a
	bpl +
	dec mul_sign
+
	sec
	lda mul_b
	sbc mul_a
	sta prod_l
	lda prod_h
	sbc mul_sign
	sta prod_h
	rts

; ASR n/d/y 16-bit until each fits signed 8-bit
scale3
	lda #8
	sta mul_a
.s3
	jsr .fitn
	bcc .do
	jsr .fitd
	bcc .do
	jsr .fity
	bcc .do
	rts
.do
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	lda dhi
	cmp #$80
	ror dhi
	ror dlo
	lda yhi
	cmp #$80
	ror yhi
	ror ylo
	dec mul_a
	bne .s3
	rts
.fitn
	lda nhi
	ldy nlo
	jmp .fit
.fitd
	lda dhi
	ldy dlo
	jmp .fit
.fity
	lda yhi
	ldy ylo
.fit
	tax
	beq .fz
	cmp #$ff
	bne .fn
	tya
	bmi .fy
.fn
	clc
	rts
.fz
	tya
	bmi .fn
.fy
	sec
	rts

; ASR n/d only until each fits signed 8-bit (keep y 16-bit)
scale_nd
	lda #8
	sta mul_a
.snd
	jsr .nd_fitn
	bcc .sdo
	jsr .nd_fitd
	bcc .sdo
	rts
.sdo
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	lda dhi
	cmp #$80
	ror dhi
	ror dlo
	dec mul_a
	bne .snd
	rts
.nd_fitn
	lda nhi
	ldy nlo
	jmp .nd_fit
.nd_fitd
	lda dhi
	ldy dlo
.nd_fit
	tax
	beq .nd_fz
	cmp #$ff
	bne .nd_fn
	tya
	bmi .nd_fy
.nd_fn
	clc
	rts
.nd_fz
	tya
	bmi .nd_fn
.nd_fy
	sec
	rts

; rot0:rot1 = (ylo:yhi * nlo) / dlo after scale_nd; A = rot0. Signed, no ±127 clamp.
lerp16
	lda #0
	sta mul_sign
	lda yhi
	bpl .yp
	lda #$80
	sta mul_sign
	sec
	lda #0
	sbc ylo
	sta ylo
	lda #0
	sbc yhi
	sta yhi
.yp
	lda nlo
	bpl .np
	lda mul_sign
	eor #$80
	sta mul_sign
	lda nlo
	eor #$ff
	clc
	adc #1
	sta nlo
.np
	lda dlo
	bpl .dp
	lda mul_sign
	eor #$80
	sta mul_sign
	lda dlo
	eor #$ff
	clc
	adc #1
	sta dlo
.dp
	lda dlo
	bne .mul
	lda #0
	sta rot0
	sta rot1
	rts
.mul
	lda ylo
	ldy nlo
	jsr umul8j
	lda prod_l
	sta rot0
	lda prod_h
	sta rot1
	lda yhi
	ldy nlo
	jsr umul8j
	clc
	lda rot1
	adc prod_l
	sta rot1
	lda prod_h
	adc #0
	sta rot2
	jsr div24u8
	bit mul_sign
	bpl .ok
	sec
	lda #0
	sbc rot0
	sta rot0
	lda #0
	sbc rot1
	sta rot1
.ok
	lda rot0
	rts

; unsigned 24-bit rot0:rot1:rot2 / dlo → 16-bit quot rot0:rot1 (sat $ffff)
div24u8
	lda #0
	sta nlo				; remainder
	ldx #24
.d24
	asl rot0
	rol rot1
	rol rot2
	rol nlo
	lda nlo
	bcs .dsub
	cmp dlo
	bcc .dnext
.dsub
	sbc dlo
	sta nlo
	inc rot0
.dnext
	dex
	bne .d24
	lda rot2
	beq .d16
	lda #$ff
	sta rot0
	sta rot1
.d16
	rts

; Unsigned nlo:nhi → prod = 32*log2(n). Clobbers nlo/nhi, mul_a, mul_b.
log16
	lda #0
	sta mul_a
	lda nlo
	ora nhi
	bne .lp
.lz
	sta prod_l
	sta prod_h
	rts
.lp
	lda nhi
	bmi .mant
	asl nlo
	rol nhi
	inc mul_a
	lda mul_a
	cmp #16
	bcc .lp
.mant
	ldx nhi
	beq .lz
	lda LOGTAB,x
	sta prod_l
	lda #0
	sta prod_h
	lda #8
	sec
	sbc mul_a
	sta mul_b
	lda #0
	sta mul_a
	lda mul_b
	bpl +
	dec mul_a
+
	ldx #5
.s5
	asl mul_b
	rol mul_a
	dex
	bne .s5
	clc
	lda prod_l
	adc mul_b
	sta prod_l
	lda prod_h
	adc mul_a
	sta prod_h
	rts

; ylo:yhi * FOCAL / z_eye:z_eye_h → A signed, clamp PERSP_MAX
persp88
	lda yhi
	sta mul_sign
	bpl .px
	sec
	lda #0
	sbc ylo
	sta nlo
	lda #0
	sbc yhi
	sta nhi
	jmp .gx
.px
	lda ylo
	sta nlo
	lda yhi
	sta nhi
.gx
	lda nlo
	ora nhi
	bne +
	rts
+
	jsr log16
	lda prod_l
	sta dlo
	lda prod_h
	sta dhi
	lda z_eye
	sta nlo
	lda z_eye_h
	sta nhi
	ora nlo
	bne +
	lda #PERSP_MAX
	jmp .s88
+
	jsr log16
	clc
	lda dlo
	adc #LOG_FOCAL
	sta dlo
	lda dhi
	adc #0
	sta dhi
	sec
	lda dlo
	sbc prod_l
	sta prod_l
	lda dhi
	sbc prod_h
	bcc .z88
	sta prod_h
	jsr alog_fetch
	cmp #PERSP_MAX
	bcc .s88
	lda #PERSP_MAX
.s88
	bit mul_sign
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts
.z88
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

!source "sqtab.asm"
