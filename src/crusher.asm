; Crushers — GAME-resident bind/reset/solid/draw. Motion is streamed (ai_crush).
; No count cap: live pos is packed x/z, snap-to-home on enter (unlike elev_y).
!zone crusher

; X = crush_* - crush_x. Y = SoA index. A = column byte.
crush_lda
	lda crush_x,x
	sta mp_l
	lda crush_x+1,x
	sta mp_h
	lda (mp_l),y
	rts

crush_sta
	sta crush_st
	lda crush_x,x
	sta mp_l
	lda crush_x+1,x
	sta mp_h
	lda crush_st
	sta (mp_l),y
	rts

; crush_init — acc / skip / entry (entry also cleared by clear_pose_ptrs).
; crush_need is set by crush_reset (set_room_idx), not here — proc_init
; runs after the first reset.
crush_init
	lda #0
	sta crush_acc_l
	sta crush_acc_h
	sta crush_entry_lo
	sta crush_entry_hi
	lda #$ff
	sta crush_skip
	lda crush_need
	beq .ci_rts
	jsr elev_noise_on		; elev_init just zeroed the rumble ref
.ci_rts
	rts

; Snap every crusher in room_idx to home + authored dir. Sets crush_need.
; Holds one elev_noise_n ref while this room has a crusher (ping-pong).
crush_reset
	lda crush_need
	beq .cr_clr
	jsr elev_noise_off
.cr_clr
	lda #0
	sta crush_acc_l
	sta crush_acc_h
	sta crush_need
	ldy #0
.cr_lp
	cpy map_ncrush
	bcs .cr_done
	ldx #crush_room - crush_x
	jsr crush_lda
	cmp room_idx
	bne .cr_n
	lda #1
	sta crush_need
	ldx #crush_face - crush_x
	jsr crush_lda
	and #1
	beq .cr_plus
	lda #$ff
	!byte $2c			; BIT abs: skip lda #1
.cr_plus
	lda #1
	ldx #crush_dir - crush_x
	jsr crush_sta
	ldx #crush_home - crush_x
	jsr crush_lda
	jsr crush_set_pos
.cr_n
	iny
	bne .cr_lp
.cr_done
	lda crush_need
	beq .cr_rts
	jsr elev_noise_on
.cr_rts
	rts

; A = travel-axis origin. Y = index. Face chooses x vs z.
crush_set_pos
	sta crush_st
	ldx #crush_face - crush_x
	jsr crush_lda
	cmp #FACE_PX
	lda crush_st
	ldx #0				; crush_x
	bcs .csp_x
	ldx #crush_z - crush_x
.csp_x
	jmp crush_sta

; Y = index. box_* from packed columns (live x/z). Preserves Y, clobbers X.
crush_load_box
	ldx #0
.clb
	lda crush_x,x
	sta mp_l
	lda crush_x+1,x
	sta mp_h
	lda (mp_l),y
	sta crush_st
	txa
	lsr
	tax
	lda crush_st
	sta box_x,x
	txa
	asl
	tax
	inx
	inx
	cpx #12
	bcc .clb
	rts

; Called from solid_at_col. col_room / col_x/z set. Y = crate step-up (ignored). C=1 blocked.
crush_solid
	sty crush_i			; preserve solid_at Y (step-up flag)
	ldy #0
.cs_lp
	cpy map_ncrush
	bcs .cs_no
	cpy crush_skip
	beq .cs_n
	ldx #crush_room - crush_x
	jsr crush_lda
	cmp col_room
	bne .cs_n
	jsr crush_load_box
	jsr player_overlaps_y
	bcc .cs_n
	jsr point_in_box_xz
	bcs .cs_yes
.cs_n
	iny
	bne .cs_lp
.cs_no
	ldy crush_i
	clc
	rts
.cs_yes
	ldy crush_i
	sec
	rts

crush_update
	lda crush_entry_hi
	beq .cu_rts
	sta .cu_j+2
	lda crush_entry_lo
	sta .cu_j+1
.cu_j
	jmp $ffff
.cu_rts
	rts

; Overlay kill — address is before loader so Krill vs KERNAL LoadPrg size
; does not shift the streamed operand.
crush_kill
	jmp death_restart

crush_draw
	ldy #0
.cd_lp
	cpy map_ncrush
	bcs .cd_rts
	ldx #crush_room - crush_x
	jsr crush_lda
	cmp room_idx
	bne .cd_n
	sty crush_i
	jsr crush_load_box
	jsr frustum_hits
	bcc .cd_r
	lda #0
	sta box_inside
	jsr draw_box
.cd_r
	ldy crush_i
.cd_n
	iny
	bne .cd_lp
.cd_rts
	rts
