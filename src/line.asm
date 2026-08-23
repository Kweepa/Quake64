; Mike's 30k px/s drawer (Denial): 8× unrolled ORA #imm, DEX/BEQ end,
; cached (colptr),Y, always LTR, SMC jump into starting bit.
; Same-half and all steep strokes use chained-C bodies (no per-pixel CPY).
; Steep lines that cross y=64 continue via rest_cnt + split_down/up.
; Flat lines that cross y=64 keep the CPY/y_cross bodies.
; dx=0 uses draw_vline (no error term; two runs at the y=64 charset split).
!zone line

col_lo
	!byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
	!byte 0,64,128,192,0,64,128,192,0,64,128,192,0,64,128,192
col_hi
	!byte 0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3
	!byte 4,4,4,4,5,5,5,5,6,6,6,6,7,7,7,7
vbits
	!byte $80,$40,$20,$10,$08,$04,$02,$01

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

; One-shot charset join for steep split. Preserve X (remaining pixel count) and
; leave C=1 for the following SBC. Not used while rest_cnt is still live.
split_down
	inc tile_half
	clc
	lda colptr+1
	adc #8
	sta colptr+1
	ldy #0
	sec
	rts

split_up
	dec tile_half
	sec
	lda colptr+1
	sbc #8
	sta colptr+1
	ldy #63
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

; x0 = sx 0..191, y0 = sy 0..127. ORA one bit into the draw charset.
plot_pixel
	jsr line_setup
	lda x0
	and #7
	tax
	lda (colptr),y
	ora vbits,x
	sta (colptr),y
	rts

draw_line
	lda x0
	cmp #192
	bcc +
	lda #191
	sta x0
+
	lda x1
	cmp #192
	bcc +
	lda #191
	sta x1
+
	lda y0
	cmp #128
	bcc +
	lda #127
	sta y0
+
	lda y1
	cmp #128
	bcc +
	lda #127
	sta y1
+
	lda x0
	cmp x1
	bcc .ord
	beq .ord
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
	bne .notv
	jmp draw_vline
.notv
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
	lda y0
	eor y1
	and #$40
	bne .flat_slow
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

.flat_slow
	lda sy
	bpl .dns
	lda sus_l,x
	sta .jus+1
	lda sus_h,x
	sta .jus+2
	ldx dx
	inx
	sec
.jus	jmp sus0
.dns
	lda sds_l,x
	sta .jds+1
	lda sds_h,x
	sta .jds+2
	ldx dx
	inx
	sec
.jds	jmp sds0

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
	lda y0
	eor y1
	and #$40
	bne .tu_cross
	lda #0
	sta rest_cnt
	ldx dy
	inx
	sec
.jt	jmp tu0
.tu_cross
	lda #64
	sec
	sbc y1
	sta rest_cnt
	lda y0
	sec
	sbc #63
	tax
	sec
	jmp .jt

.stdn
	lda std_l,x
	sta .js+1
	lda std_h,x
	sta .js+2
	lda y0
	eor y1
	and #$40
	bne .td_cross
	lda #0
	sta rest_cnt
	ldx dy
	inx
	sec
.js	jmp td0
.td_cross
	lda y1
	sec
	sbc #63
	sta rest_cnt
	lda #64
	sec
	sbc y0
	tax
	sec
	jmp .js

; dx=0: same column, no Bresenham. At most two runs split at y=64.
draw_vline
	lda y0
	cmp y1
	bcc .ysok
	ldx y1
	sta y1
	stx y0
.ysok
	lda x0
	and #7
	tax
	lda vbits,x
	sta vl_ora+1
	jsr line_setup
	lda y0
	cmp #64
	bcc .fromtop
	lda y1
	sec
	sbc y0
	tax
	inx
	jmp vl_run
.fromtop
	lda y1
	cmp #64
	bcc .onlytop
	lda #64
	sec
	sbc y0
	tax
	jsr vl_run
	jsr y_cross_down
	lda y1
	sec
	sbc #63
	tax
	jmp vl_run
.onlytop
	lda y1
	sec
	sbc y0
	tax
	inx
vl_run
	lda (colptr),y
vl_ora	ora #$00
	sta (colptr),y
	iny
	dex
	bne vl_run
	rts

!source "_line_bodies.asm"
