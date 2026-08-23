; Elevators — activate, motion, floor boarding, auto stand-on, move noise
!zone elevator

; ------------------------------------------------------------------
; elev_init — elev_y0 → elev_y; silence move rumble
; ------------------------------------------------------------------
elev_init
	ldx #0
	lda #0
	sta elev_noise_n
.ei
	cpx	map_nelevs
	+beq_far .ei_rts
	+lda_mx elev_y0
	sta elev_y,x
	inx
	beq .ei_rts
	jmp .ei
.ei_rts
	rts

; ------------------------------------------------------------------
; elev_activate — X = elev SoA index; C=0 success
; toggle: one-shot to the other stop; else lower→wait→raise from home
; ------------------------------------------------------------------
elev_activate
	stx proc_tmp5			; local SoA
	jmp .ea_body
.ea_fail_pl
	pla
.ea_fail
	sec
	ldx proc_tmp5
	rts
.ea_body
	+lda_mx elev_id
	sta proc_tmp1			; world id for busy / PROC_A
	jsr proc_target_busy
	+bcs_far .ea_fail
	ldx proc_tmp5
	+lda_mx elev_type
	cmp #ELEV_TYPE_TOGGLE
	bne .ea_not_tog
	jmp .ea_toggle
.ea_not_tog
	jsr proc_count_free
	cmp #2
	+bcc_far .ea_fail
	ldx proc_tmp5
	lda elev_y,x
	+cmp_mx elev_home
	+bne_far .ea_fail			; only start from home (top)
	+lda_mx elev_home
	pha				; return height
	+lda_mx elev_id
	sta proc_tmp1
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	+lda_mx elev_dest
	sta proc_tmp2
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	+bcs_far .ea_fail_pl
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
	+bcs_far .ea_fail_pl
	lda proc_tmp5
	sta PROC_L,y
	pla
	sta PROC_E,y
	jmp .ea_snd
.ea_toggle
	jsr proc_count_free
	cmp #1
	+bcc_far .ea_fail
	ldx proc_tmp5
	lda elev_y,x
	+cmp_mx elev_home
	bne .ea_tog_up
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	+lda_mx elev_dest
	sta proc_tmp2
	jmp .ea_tog_go
.ea_tog_up
	lda #PROC_RAISE_ELEV
	sta proc_tmp0
	+lda_mx elev_home
	sta proc_tmp2
.ea_tog_go
	+lda_mx elev_id
	sta proc_tmp1
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	+bcs_far .ea_fail
	lda proc_tmp5
	sta PROC_L,y
.ea_snd
	jsr elev_noise_on
	clc
	ldx proc_tmp5
	rts

; ------------------------------------------------------------------
; elev_try_step — like proc_try_step but ELEV_STEP_MS (C=0 if stepped)
; ------------------------------------------------------------------
elev_try_step
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
; elev_pu_le / elev_pu_re — proc_update handlers (X = slot)
; jmp proc_update_next when done for this slot
; ------------------------------------------------------------------
elev_pu_le
	jsr proc_add_dt
.eple_lp
	jsr elev_try_step
	bcc .eple_go
	jmp proc_update_next
.eple_go
	ldy PROC_L,x
	lda elev_y,y
	cmp PROC_B,x
	beq .eple_done
	bcc .eple_done
	sec
	sbc #1
	sta elev_y,y
	jmp .eple_lp
.eple_done
	lda PROC_B,x
	sta elev_y,y
	lda #PROC_FREE
	sta PROC_KIND,x
	jsr elev_noise_off
	jmp proc_update_next

elev_pu_re
	jsr proc_add_dt
.epre_lp
	jsr elev_try_step
	bcc .epre_go
	jmp proc_update_next
.epre_go
	ldy PROC_L,x
	lda elev_y,y
	cmp PROC_B,x
	bcs .epre_done
	clc
	adc #1
	sta elev_y,y
	jmp .epre_lp
.epre_done
	lda PROC_B,x
	sta elev_y,y
	lda #PROC_FREE
	sta PROC_KIND,x
	jsr elev_noise_off
	jmp proc_update_next

; ------------------------------------------------------------------
; elev_update_floor — board elev top in active room (obj_i = prior rider)
; ------------------------------------------------------------------
elev_update_floor
	ldx #0
.euf
	cpx	map_nelevs
	bcc .euf_go
	jmp .euf_rts
.euf_go
	+lda_mx elev_room
	cmp room_idx
	+bne_far .euf_n
	+lda_mx elev_x
	sta box_x
	+lda_mx elev_z
	sta box_z
	+lda_mx elev_sx
	sta box_sx
	+lda_mx elev_sz
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	+bcc_far .euf_n
	; on elevator footprint — floor = elev_y + sy
	; reject only if under the car (feet < elev_y); top is sy above elev_y
	; so feet>=top would block boarding from a flush room floor
	clc
	lda elev_y,x
	+adc_mx elev_sy
	cmp floor_y
	bcc .euf_n			; below current floor
	sta col_y			; elev_top
	cpx obj_i
	beq .euf_on			; already riding — feet lag while elev moves
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp elev_y,x
	bcc .euf_n			; feet < elev_y — walking under
.euf_on
	lda col_y
	sta floor_y
	stx pl_on_elev
.euf_n
	inx
	beq .euf_rts
	jmp .euf
.euf_rts
	rts

; ------------------------------------------------------------------
; elev_try_auto — stand-on automatic elevators in this room
; ------------------------------------------------------------------
elev_try_auto
	ldx #0
.eta
	cpx	map_nelevs
	+bcs_far .eta_rts
	+lda_mx elev_type
	cmp #ELEV_TYPE_AUTO
	bne .eta_n
	+lda_mx elev_room
	cmp room_idx
	bne .eta_n
	cpx pl_on_elev
	bne .eta_n
	jsr elev_activate
.eta_n
	inx
	beq .eta_rts
	jmp .eta
.eta_rts
	rts

; ------------------------------------------------------------------
; elev_noise_on / elev_noise_off — refcount only. IRQ programs SID V3.
elev_noise_on
	inc elev_noise_n
	rts

elev_noise_off
	lda elev_noise_n
	beq .enoff_rts
	dec elev_noise_n
.enoff_rts
	rts
