; Elevators — activate (toggle), motion, floor boarding, move noise
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
	beq .ei_rts
	+lda_mx elev_y0
	sta elev_y,x
	inx
	beq .ei_rts
	jmp .ei
.ei_rts
	rts

; ------------------------------------------------------------------
; elev_activate — X = elev SoA index; C=0 success
; one-shot to the other stop (home ↔ dest)
; ------------------------------------------------------------------
elev_activate
	jsr elev_prep
	bcs .ea_rts
	lda elev_y,x
	+cmp_mx elev_home
	bne .ea_up
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	+lda_mx elev_dest
	sta proc_tmp2
	jmp elev_start_motion
.ea_up
	lda #PROC_RAISE_ELEV
	sta proc_tmp0
	+lda_mx elev_home
	sta proc_tmp2
	jmp elev_start_motion
.ea_rts
	rts

; ------------------------------------------------------------------
; elev_summon — X = elev SoA index; C=0 if a thinker was started
; idle car → stop nearer player feet (tie → home)
; ------------------------------------------------------------------
elev_summon
	jsr elev_prep
	bcs .es_rts
	sec
	lda cam_yh
	sbc #EYE_HEIGHT
	sta proc_tmp3			; feet
	+lda_mx elev_dest
	jsr elev_u8abs
	sta proc_tmp4			; |feet-dest|
	+lda_mx elev_home
	jsr elev_u8abs			; |feet-home|
	cmp proc_tmp4
	bcc .es_home
	beq .es_home
	+lda_mx elev_dest
	jmp .es_tgt
.es_home
	+lda_mx elev_home
.es_tgt
	sta proc_tmp2
	ldx proc_tmp5
	lda elev_y,x
	cmp proc_tmp2
	beq .es_rts			; already there (C=1)
	bcc .es_raise
	lda #PROC_LOWER_ELEV
	sta proc_tmp0
	jmp elev_start_motion
.es_raise
	lda #PROC_RAISE_ELEV
	sta proc_tmp0
	jmp elev_start_motion
.es_rts
	rts

; busy + free slot; X restored to SoA. C=1 fail
elev_prep
	stx proc_tmp5
	+lda_mx elev_id
	sta proc_tmp1
	jsr proc_target_busy
	bcs .ep_fail
	jsr proc_count_free
	cmp #1
	bcc .ep_fail
	ldx proc_tmp5
	clc
	rts
.ep_fail
	sec
	ldx proc_tmp5
	rts

; A vs proc_tmp3 → |A - proc_tmp3|
elev_u8abs
	cmp proc_tmp3
	bcs .eu_ge
	eor #$ff
	sec
	adc proc_tmp3
	rts
.eu_ge
	sec
	sbc proc_tmp3
	rts

; proc_tmp0=kind tmp2=target Y tmp5=SoA. C=0 success
elev_start_motion
	ldx proc_tmp5
	+lda_mx elev_id
	sta proc_tmp1
	lda #0
	sta proc_tmp3
	sta proc_tmp4
	jsr proc_alloc
	bcs elev_act_fail
	lda proc_tmp5
	sta PROC_L,y
	jsr elev_noise_on
	clc
	ldx proc_tmp5
	rts
elev_act_fail
	sec
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
	bne .euf_n
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
	jsr point_in_floor_xz
	bcc .euf_n
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
