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
	beq .psw0
	lda elev_y0,x
	sta elev_y,x
	inx
	bne .pe
.psw0
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
	lda door_id,x
	sta proc_tmp1			; world id for busy / PROC_A
	jsr proc_target_busy
	bcs .da_fail
	ldx proc_tmp5
	lda door_open,x
	cmp door_sy,x
	bcs .da_fail
	jsr proc_count_free
	cmp #2
	bcc .da_fail
	ldx proc_tmp5
	lda #PROC_OPEN_DOOR
	sta proc_tmp0
	lda door_id,x
	sta proc_tmp1
	lda door_sy,x
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
	lda door_id,x
	sta proc_tmp1
	lda #PROC_LOWER_DOOR
	sta proc_tmp2
	lda #<DOOR_RECLOSE_MS
	sta proc_tmp3
	lda #>DOOR_RECLOSE_MS
	sta proc_tmp4
	jsr proc_alloc
	bcs .da_fail
	lda proc_tmp5
	sta PROC_L,y
	clc
	ldx proc_tmp5
	rts
.da_fail
	sec
	ldx proc_tmp5
	rts

; ------------------------------------------------------------------
; elev_activate — X = elev SoA index; C=0 success
; toggle: one-shot to the other stop; else lower→wait→raise from home
; ------------------------------------------------------------------
elev_activate
	stx proc_tmp5			; local SoA
	lda elev_id,x
	sta proc_tmp1			; world id for busy / PROC_A
	jsr proc_target_busy
	bcs .ea_fail
	ldx proc_tmp5
	lda elev_type,x
	cmp #ELEV_TYPE_TOGGLE
	beq .ea_toggle
	jsr proc_count_free
	cmp #2
	bcc .ea_fail
	ldx proc_tmp5
	lda elev_y,x
	cmp elev_home,x
	bne .ea_fail			; only start from home (top)
	lda elev_home,x
	pha				; return height
	lda elev_id,x
	sta proc_tmp1
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	lda elev_dest,x
	sta proc_tmp2
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .ea_fail_pl
	lda proc_tmp5
	sta PROC_L,y
	lda #PROC_TIMER
	sta proc_tmp0
	lda #PROC_RAISE_ELEV
	sta proc_tmp2
	lda #<ELEV_WAIT_MS
	sta proc_tmp3
	lda #>ELEV_WAIT_MS
	sta proc_tmp4
	jsr proc_alloc
	bcs .ea_fail_pl
	lda proc_tmp5
	sta PROC_L,y
	pla
	sta PROC_E,y
	jmp .ea_snd
.ea_fail_pl
	pla
.ea_fail
	sec
	ldx proc_tmp5
	rts
.ea_toggle
	jsr proc_count_free
	cmp #1
	bcc .ea_fail
	ldx proc_tmp5
	lda elev_y,x
	cmp elev_home,x
	bne .ea_tog_up
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	lda elev_dest,x
	sta proc_tmp2
	jmp .ea_tog_go
.ea_tog_up
	lda #PROC_RAISE_ELEV
	sta proc_tmp0
	lda elev_home,x
	sta proc_tmp2
.ea_tog_go
	lda elev_id,x
	sta proc_tmp1
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .ea_fail
	lda proc_tmp5
	sta PROC_L,y
.ea_snd
	lda #SOUND_STNMOV
	jsr play_sound
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

; Same as proc_try_step but ELEV_STEP_MS (slower elevators)
proc_try_elev_step
	lda PROC_D,x
	bne .ees_hi
	lda PROC_C,x
	cmp #ELEV_STEP_MS
	bcc .ees_no
.ees_hi
	sec
	lda PROC_C,x
	sbc #ELEV_STEP_MS
	sta PROC_C,x
	lda PROC_D,x
	sbc #0
	sta PROC_D,x
	clc
	rts
.ees_no
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
	beq .pu_tsnd_el
	cmp #PROC_LOWER_DOOR
	bne .pu_talloc
	lda #SOUND_CLOSEDOOR
	jsr play_sound
	lda #0
	sta proc_tmp2			; LOWER_DOOR dest open=0
	jmp .pu_talloc
.pu_tsnd_el
	lda #SOUND_STNMOV
	jsr play_sound
.pu_talloc
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs .pu_talloc_fail
	pla
	sta PROC_L,y
	ldx proc_tmp5
	jmp .pu_next
.pu_talloc_fail
	pla
	ldx proc_tmp5
	jmp .pu_next
.pu_tstill
	lda PROC_C,x
	ora PROC_D,x
	beq .pu_tfire
	ldx proc_tmp5
	jmp .pu_next

.pu_rd
	jsr proc_add_dt
.pu_rd_lp
	jsr proc_try_step
	bcc .pu_rd_go
	jmp .pu_next
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
	jmp .pu_next

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
	jmp .pu_next
.pu_ld_done
	lda #PROC_FREE
	sta PROC_KIND,x
	ldx proc_tmp5
	jmp .pu_next

.pu_le
	jsr proc_add_dt
.pu_le_lp
	jsr proc_try_elev_step
	bcc .pu_le_go
	jmp .pu_next
.pu_le_go
	ldy PROC_L,x
	lda elev_y,y
	cmp PROC_B,x
	beq .pu_le_done
	bcc .pu_le_done
	sec
	sbc #1
	sta elev_y,y
	jmp .pu_le_lp
.pu_le_done
	lda PROC_B,x
	sta elev_y,y
	lda #PROC_FREE
	sta PROC_KIND,x
	jmp .pu_next

.pu_re
	jsr proc_add_dt
.pu_re_lp
	jsr proc_try_elev_step
	bcc .pu_re_go
	jmp .pu_next
.pu_re_go
	ldy PROC_L,x
	lda elev_y,y
	cmp PROC_B,x
	bcs .pu_re_done
	clc
	adc #1
	sta elev_y,y
	jmp .pu_re_lp
.pu_re_done
	lda PROC_B,x
	sta elev_y,y
	lda #PROC_FREE
	sta PROC_KIND,x
	jmp .pu_next
