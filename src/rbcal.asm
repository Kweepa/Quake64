; Raster-split delay calibration (MENU only; dumped when GAME loads at $0900).
;
; Finds n_line: the largest rb_delay count that still ends on the same raster
; line, then stores the mid-split count (13/16 n_line - 1, NTSC - 2; one more
; from n_line 24 up) in rb_n_lo/hi ($08F5-$08F6) for irq.asm. Factors fitted
; with tools/sim_rbsplit.py.
; n_line < 8 (1 MHz class): the K=RB_K_SPLIT count irq.asm uses.
;
; Each trial is the handler tail, byte for byte: sync to a $d012 edge,
; jsr rb_delay (the macro the game assembles), lda abs (= pla), sta $d018
; (same value), lda $d012. The edge cancels out of the crossing test, so this
; measures CPU cycles per video line for exactly this I/O mix.
;
;   write time W = edge + j + (29 + 5n + 4P)/N     (N = CPU:VIC ratio, P =
;   passes, j = poll phase, 0..6 CPU cycles). The read 4 cycles after W
;   crosses when j + (33 + 5n + 4P)/N >= V (V = 63 PAL, 65 NTSC). A probe
;   "stays" if any of RBC_TRIES phases stays, which measures the j = 0
;   crossing; the game's own j spreads the write over 7/N cycles above that.
;   The scaled count puts the mid split at ~49-55 for N >= 2 PAL or NTSC.
;
; Runs under SEI with $d015 = 0, on lines 0-40 and 252-255: above/below the
; display window's badlines (48-247), no sprite DMA. Pokes no $0314, $dc0d or
; $d01a.

!source "rbdelay.asm"

RBC_LINE_B	= 252		; trials start on any edge in 252..255
RBC_LINE_A	= 41		; ... or 1..41 (not 256+; trial ends <= line 44)
RBC_TRIES	= 6
RBC_START	= 8		; first probe; crossing here = 1 MHz class
RBC_CAP_HI	= 8		; n >= 2048 never crossed: give up (classic)

rb_calibrate
	lda $d015
	sta rbc_spr
	lda #0
	sta $d015
	lda $d018
	sta rbc_d018
	lda #0
	sta rbc_best
	sta rbc_best+1
	sta rbc_u+1
	lda #RBC_START
	sta rbc_u
.rbc_dbl
	jsr rbc_test
	bcc .rbc_cross
	lda rbc_u
	sta rbc_best
	lda rbc_u+1
	sta rbc_best+1
	asl rbc_u
	rol rbc_u+1
	lda rbc_u+1
	cmp #RBC_CAP_HI
	bcc .rbc_dbl
	jmp .rbc_classic
.rbc_cross
	lda rbc_best
	ora rbc_best+1
	bne .rbc_have
	jmp .rbc_classic
.rbc_have
	lda rbc_best+1
	lsr
	sta rbc_step+1
	lda rbc_best
	ror
	sta rbc_step
.rbc_sa
	lda rbc_step
	ora rbc_step+1
	beq .rbc_scale
	clc
	lda rbc_best
	adc rbc_step
	sta rbc_u
	lda rbc_best+1
	adc rbc_step+1
	sta rbc_u+1
	jsr rbc_test
	bcc .rbc_sa_nx
	lda rbc_u
	sta rbc_best
	lda rbc_u+1
	sta rbc_best+1
.rbc_sa_nx
	lsr rbc_step+1
	ror rbc_step
	jmp .rbc_sa
.rbc_scale
	; mid split: best - best>>3 - best>>4 - 1 (PAL) / 2 (NTSC), 1 more at N >= 3
	jsr rbc_u_best
	ldx #3
	jsr rbc_sub_shr
	ldx #4
	jsr rbc_sub_shr
	lda #2
	ldy $02a6				; KERNAL: 1 = PAL, 0 = NTSC
	beq +
	lda #1
+
	ldy rbc_best+1
	bne .rbc_c1				; n_line >= 24 (N >= 3): 1 more, the
	ldy rbc_best				; 5/N-cycle step at 3 MHz is coarse
	cpy #24
	bcc .rbc_c0
.rbc_c1
	clc
	adc #1
.rbc_c0
	jsr rbc_sub_a
	ldx #0
	jsr rbc_put
	jmp .rbc_out
.rbc_classic
	lda #RB_K_SPLIT
	sta rb_n_lo
	lda #1
	sta rb_n_hi
.rbc_out
	lda rbc_spr
	sta $d015
	rts

rbc_u_best
	lda rbc_best
	sta rbc_u
	lda rbc_best+1
	sta rbc_u+1
	rts

; rbc_u -= rbc_best >> X (X >= 1)
rbc_sub_shr
	lda rbc_best
	sta rbc_t
	lda rbc_best+1
	sta rbc_t+1
-
	lsr rbc_t+1
	ror rbc_t
	dex
	bne -
rbc_sub_t
	sec
	lda rbc_u
	sbc rbc_t
	sta rbc_u
	lda rbc_u+1
	sbc rbc_t+1
	sta rbc_u+1
	rts

; rbc_u -= A
rbc_sub_a
	sta rbc_t
	lda #0
	sta rbc_t+1
	beq rbc_sub_t

; rbc_u = n (>= 1) → cell +X (always 0): lo = n & 255 (0 = 256),
; hi = passes = (n >> 8) + 1, less one when lo = 0.
rbc_put
	lda rbc_u
	sta rb_n_lo,x
	lda rbc_u+1
	ldy rbc_u
	beq +
	clc
	adc #1
+
	sta rb_n_hi,x
	rts

; In: rbc_u = n (>= 1). Out: C=1 if any trial ended on its own line.
rbc_test
	ldx #0
	jsr rbc_put
	ldx #RBC_TRIES
.rbt_try
	stx rbc_try
.rbt_w
	ldy $d012
	cpy #RBC_LINE_B
	bcs .rbt_go
	cpy #RBC_LINE_A
	bcs .rbt_w
	lda $d011
	bmi .rbt_w				; lines 256+: $d012 low byte again 0..
.rbt_go
	iny
	sty rbc_line
-
	cpy $d012
	bne -
	jsr rb_delay
	lda rbc_d018				; = pla
	sta $d018
	lda $d012
	cmp rbc_line
	beq .rbt_stay
	ldx rbc_try
	dex
	bne .rbt_try
	clc
	rts
.rbt_stay
	sec
	rts

+rb_delay_body

rbc_spr		!byte 0
rbc_d018	!byte 0
rbc_try		!byte 0
rbc_line	!byte 0
rbc_u		!word 0
rbc_best	!word 0
rbc_step	!word 0
rbc_t		!word 0
