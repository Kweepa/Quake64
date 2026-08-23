; Timed movers — doors (SquareDoom process.asm adapted); elevators in elevator.asm
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
	cpx	map_ndoors
	beq .psw0
	sta door_open,x
	inx
	beq .psw0
	jmp .pd
.psw0
	jsr elev_init
	lda #0
	sta in_use
	sta key_use
	sta key_use_was
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

; proc_tmp0=kind tmp1=A (world id) tmp2=B tmp3=C lo tmp4=D hi
; After success Y=slot; caller stores PROC_L from local SoA index.
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

; Busy if any live thinker references proc_tmp1 as PROC_A (world id)
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
; door_activate — X = door SoA index; C=0 success
; ------------------------------------------------------------------
door_activate
	stx proc_tmp5			; local SoA
	jmp .da_body
.da_fail
	sec
	ldx proc_tmp5
	rts
.da_body
	+lda_mx door_id
	sta proc_tmp1			; world id for busy / PROC_A
	jsr proc_target_busy
	bcc .da_free
	jmp .da_fail
.da_free
	ldx proc_tmp5
	+lda_mx door_key
	beq .da_unlocked
	cmp #DOOR_KEY_GOLD
	beq .da_gold
	lda have_keys
	and #HAVE_SILVER
	beq .da_fail
	bne .da_unlocked
.da_gold
	lda have_keys
	and #HAVE_GOLD
	beq .da_fail
.da_unlocked
	ldx proc_tmp5
	lda door_open,x
	+cmp_mx door_sy
	bcs .da_fail
	jsr proc_count_free
	cmp #2
	bcc .da_fail
	ldx proc_tmp5
	lda #PROC_OPEN_DOOR
	sta proc_tmp0
	+lda_mx door_id
	sta proc_tmp1
	+lda_mx door_sy
	sta proc_tmp2
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .da_fail
	lda proc_tmp5
	sta PROC_L,y
	lda #SOUND_OPENDOOR
	jsr play_sound
	ldx proc_tmp5
	lda #PROC_TIMER
	sta proc_tmp0
	+lda_mx door_id
	sta proc_tmp1
	lda #PROC_LOWER_DOOR
	sta proc_tmp2
	lda #<DOOR_RECLOSE_MS
	sta proc_tmp3
	lda #>DOOR_RECLOSE_MS
	sta proc_tmp4
	jsr proc_alloc
	bcc .da_got
	jmp .da_fail
.da_got
	lda proc_tmp5
	sta PROC_L,y
	clc
	ldx proc_tmp5
	rts

; ------------------------------------------------------------------
; Accumulate motion: add dt once, then try one 64ms step (C=0 if stepped)
; ------------------------------------------------------------------
proc_add_dt
	clc
	lda PROC_C,x
	adc dt_ms
	sta PROC_C,x
	lda PROC_D,x
	adc dt_msh
	sta PROC_D,x
	rts

proc_try_step
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
; Loop / next / work are global so elevator.asm can jmp proc_update_next
proc_update
	ldx #0
proc_update_loop
	lda PROC_KIND,x
	bne proc_update_work
proc_update_next
	inx
	cpx #PROC_NUM
	bcc proc_update_loop
	rts
proc_update_work
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
	jmp elev_pu_le
.pu_n4
	cmp #PROC_RAISE_ELEV
	bne .pu_n5
	jmp elev_pu_re
.pu_n5
	jmp proc_update_next

.pu_timer
	stx proc_tmp5
	sec
	lda PROC_C,x
	sbc dt_ms
	sta PROC_C,x
	lda PROC_D,x
	sbc dt_msh
	sta PROC_D,x
	bcs .pu_tstill
	; fired (went negative) or hit zero
.pu_tfire
	lda PROC_L,x
	pha				; local SoA for successor
	lda PROC_A,x
	sta proc_tmp1			; world id
	lda PROC_B,x
	sta proc_tmp0			; next kind
	lda PROC_E,x
	sta proc_tmp2			; elev home if raise
	lda #PROC_FREE
	sta PROC_KIND,x
	lda proc_tmp0
	cmp #PROC_RAISE_ELEV
	beq .pu_talloc
	cmp #PROC_LOWER_DOOR
	bne .pu_talloc
	lda #SOUND_CLOSEDOOR
	jsr play_sound
	lda #0
	sta proc_tmp2			; LOWER_DOOR dest open=0
.pu_talloc
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .pu_talloc_fail
	pla
	sta PROC_L,y
	lda proc_tmp0
	cmp #PROC_RAISE_ELEV
	bne .pu_talloc_ok
	jsr elev_noise_on
.pu_talloc_ok
	ldx proc_tmp5
	jmp proc_update_next
.pu_talloc_fail
	pla
	ldx proc_tmp5
	jmp proc_update_next
.pu_tstill
	lda PROC_C,x
	ora PROC_D,x
	beq .pu_tfire
	ldx proc_tmp5
	jmp proc_update_next

.pu_rd
	jsr proc_add_dt
.pu_rd_lp
	jsr proc_try_step
	bcc .pu_rd_go
	jmp proc_update_next
.pu_rd_go
	ldy PROC_L,x
	lda door_open,y
	cmp PROC_B,x
	bcs .pu_rd_done
	clc
	adc #1
	sta door_open,y
	jmp .pu_rd_lp
.pu_rd_done
	lda #PROC_FREE
	sta PROC_KIND,x
	jmp proc_update_next

.pu_ld
	; stall if player in door volume
	stx proc_tmp5
	ldy PROC_L,x
	jsr player_in_door_y
	bcs .pu_ld_wait
	jsr proc_add_dt
.pu_ld_lp
	jsr proc_try_step
	bcs .pu_ld_wait
	ldy PROC_L,x
	lda door_open,y
	beq .pu_ld_done
	sec
	sbc #1
	sta door_open,y
	jmp .pu_ld_lp
.pu_ld_wait
	ldx proc_tmp5
	jmp proc_update_next
.pu_ld_done
	lda #PROC_FREE
	sta PROC_KIND,x
	ldx proc_tmp5
	jmp proc_update_next
