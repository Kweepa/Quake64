; Timed movers — doors + elevators (SquareDoom process.asm adapted)
!zone process

proc_init
	ldx #0
	lda #PROC_FREE
.pi
	sta PROC_KIND,x
	inx
	cpx #PROC_NUM
	bne .pi
	ldx #0
	lda #0
.pd
	cpx #MAP_NDOORS
	beq .pe0
	sta door_open,x
	inx
	bne .pd
.pe0
	ldx #0
.pe
	cpx #MAP_NELEVS
	beq .pdone
	lda elev_y0,x
	sta elev_y,x
	inx
	bne .pe
.pdone
	rts

proc_find_free
	ldy #0
.pff
	lda PROC_KIND,y
	beq .pff_ok
	iny
	cpy #PROC_NUM
	bne .pff
	sec
	rts
.pff_ok
	clc
	rts

; proc_tmp0=kind tmp1=A tmp2=B tmp3=C lo tmp4=D hi
proc_alloc
	jsr proc_find_free
	bcs .pa_fail
	lda proc_tmp0
	sta PROC_KIND,y
	lda proc_tmp1
	sta PROC_A,y
	lda proc_tmp2
	sta PROC_B,y
	lda proc_tmp3
	sta PROC_C,y
	lda proc_tmp4
	sta PROC_D,y
	lda #0
	sta PROC_E,y
	clc
.pa_fail
	rts

; Busy if any live thinker references proc_tmp1 as PROC_A
proc_target_busy
	ldx #0
.psb
	lda PROC_KIND,x
	beq .psb_n
	lda PROC_A,x
	cmp proc_tmp1
	bne .psb_n
	sec
	rts
.psb_n
	inx
	cpx #PROC_NUM
	bne .psb
	clc
	rts

proc_count_free
	ldx #0
	ldy #0
.pcf
	lda PROC_KIND,x
	bne .pcf_n
	iny
.pcf_n
	inx
	cpx #PROC_NUM
	bne .pcf
	tya
	rts

; ------------------------------------------------------------------
; door_activate — X = door index
; ------------------------------------------------------------------
door_activate
	stx proc_tmp1
	jsr proc_target_busy
	bcs .da_rts
	ldx proc_tmp1
	lda door_open,x
	cmp door_sy,x
	bcs .da_rts
	jsr proc_count_free
	cmp #2
	bcc .da_rts
	ldx proc_tmp1
	lda #PROC_OPEN_DOOR
	sta proc_tmp0
	lda door_sy,x
	sta proc_tmp2
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .da_rts
	ldx proc_tmp1
	lda #PROC_TIMER
	sta proc_tmp0
	lda #PROC_LOWER_DOOR
	sta proc_tmp2
	lda #<DOOR_RECLOSE_MS
	sta proc_tmp3
	lda #>DOOR_RECLOSE_MS
	sta proc_tmp4
	jsr proc_alloc
.da_rts
	ldx proc_tmp1
	rts

; ------------------------------------------------------------------
; elev_activate — X = elev index
; ------------------------------------------------------------------
elev_activate
	stx proc_tmp1
	jsr proc_target_busy
	bcs .ea_rts
	jsr proc_count_free
	cmp #2
	bcc .ea_rts
	ldx proc_tmp1
	lda elev_y,x
	cmp elev_home,x
	bne .ea_rts			; only start from home (top)
	lda elev_home,x
	sta proc_tmp5			; return height
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	lda elev_dest,x
	sta proc_tmp2
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .ea_rts
	lda #PROC_TIMER
	sta proc_tmp0
	lda #PROC_RAISE_ELEV
	sta proc_tmp2
	lda #<ELEV_WAIT_MS
	sta proc_tmp3
	lda #>ELEV_WAIT_MS
	sta proc_tmp4
	jsr proc_alloc
	bcs .ea_rts
	lda proc_tmp5
	sta PROC_E,y
.ea_rts
	ldx proc_tmp1
	rts

; ------------------------------------------------------------------
; Accumulate motion: add dt to C:D; if >= MOTION_STEP_MS, subtract and C=0 (step)
; ------------------------------------------------------------------
proc_accum
	clc
	lda PROC_C,x
	adc dt_ms
	sta PROC_C,x
	lda PROC_D,x
	adc #0
	sta PROC_D,x
	lda PROC_D,x
	bne .acc_hi
	lda PROC_C,x
	cmp #MOTION_STEP_MS
	bcc .acc_no
.acc_hi
	sec
	lda PROC_C,x
	sbc #MOTION_STEP_MS
	sta PROC_C,x
	lda PROC_D,x
	sbc #0
	sta PROC_D,x
	clc				; step
	rts
.acc_no
	sec
	rts

; ------------------------------------------------------------------
proc_update
	ldx #0
.pu_loop
	lda PROC_KIND,x
	bne .pu_work
.pu_next
	inx
	cpx #PROC_NUM
	bcc .pu_loop
	rts
.pu_work
	cmp #PROC_TIMER
	bne .pu_n1
	jmp .pu_timer
.pu_n1
	cmp #PROC_OPEN_DOOR
	bne .pu_n2
	jmp .pu_rd
.pu_n2
	cmp #PROC_LOWER_DOOR
	bne .pu_n3
	jmp .pu_ld
.pu_n3
	cmp #PROC_LOWER_ELEV
	bne .pu_n4
	jmp .pu_le
.pu_n4
	cmp #PROC_RAISE_ELEV
	bne .pu_n5
	jmp .pu_re
.pu_n5
	jmp .pu_next

.pu_timer
	stx proc_tmp5
	sec
	lda PROC_C,x
	sbc dt_ms
	sta PROC_C,x
	lda PROC_D,x
	sbc #0
	sta PROC_D,x
	bcs .pu_tstill
	; fired (went negative) or hit zero
.pu_tfire
	lda PROC_A,x
	sta proc_tmp1
	lda PROC_B,x
	sta proc_tmp0			; next kind
	lda PROC_E,x
	sta proc_tmp2			; elev home if raise
	lda #PROC_FREE
	sta PROC_KIND,x
	lda proc_tmp0
	cmp #PROC_RAISE_ELEV
	beq .pu_talloc
	lda #0
	sta proc_tmp2			; LOWER_DOOR dest open=0
.pu_talloc
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	ldx proc_tmp5
	jmp .pu_next
.pu_tstill
	lda PROC_C,x
	ora PROC_D,x
	beq .pu_tfire
	ldx proc_tmp5
	jmp .pu_next

.pu_rd
	jsr proc_accum
	bcc .pu_rd_go
	jmp .pu_next
.pu_rd_go
	ldy PROC_A,x
	lda door_open,y
	cmp PROC_B,x
	bcs .pu_rd_done
	clc
	adc #1
	sta door_open,y
	jmp .pu_next
.pu_rd_done
	lda #PROC_FREE
	sta PROC_KIND,x
	jmp .pu_next

.pu_ld
	; stall if player in door volume
	stx proc_tmp5
	ldy PROC_A,x
	jsr player_in_door_y
	bcs .pu_ld_wait
	jsr proc_accum
	bcs .pu_ld_wait
	ldy PROC_A,x
	lda door_open,y
	beq .pu_ld_done
	sec
	sbc #1
	sta door_open,y
.pu_ld_wait
	ldx proc_tmp5
	jmp .pu_next
.pu_ld_done
	lda #PROC_FREE
	sta PROC_KIND,x
	ldx proc_tmp5
	jmp .pu_next

.pu_le
	jsr proc_accum
	bcc .pu_le_go
	jmp .pu_next
.pu_le_go
	ldy PROC_A,x
	lda elev_y,y
	cmp PROC_B,x
	beq .pu_le_done
	bcc .pu_le_done
	sec
	sbc #1
	sta elev_y,y
	jmp .pu_next
.pu_le_done
	lda PROC_B,x
	sta elev_y,y
	lda #PROC_FREE
	sta PROC_KIND,x
	jmp .pu_next

.pu_re
	jsr proc_accum
	bcc .pu_re_go
	jmp .pu_next
.pu_re_go
	ldy PROC_A,x
	lda elev_y,y
	cmp PROC_B,x
	bcs .pu_re_done
	clc
	adc #1
	sta elev_y,y
	jmp .pu_next
.pu_re_done
	lda PROC_B,x
	sta elev_y,y
	lda #PROC_FREE
	sta PROC_KIND,x
	jmp .pu_next
