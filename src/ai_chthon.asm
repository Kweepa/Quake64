; Chthon. Linked at AI_LINK_BASE. No walking: face the player, rise once, then loop attack.
; Idle is undrawn. Lava is a grenade with GREN_F_LAVA (no gravity, burst on contact).
!cpu 6510
!to "../enemies/ai_chthon.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

CHTHON_LAVA_VERT = 14		; arm tip (edge 4-14) on fire frame 5
CHTHON_LAVA_VERT2 = 13		; other arm tip (edge 12-13) on fire frame 17
CHTHON_FIRE1 = 5		; first throw; keep in sync with genenemies FIRE_FRAME[Chthon]
CHTHON_LAVA_SPEED = 32		; units/s

*= AI_LINK_BASE
ai_chthon_entry
	cmp #AI_CMD_IDLE
	beq .ch_idle
	cmp #AI_CMD_FIRE
	bne +
	jmp .ch_fire
+
	cmp #AI_CMD_ATTACK_TICK
	bne +
	jmp .ch_tick
+
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .ch_end
+
	cmp #AI_CMD_APPROACH_MOVE
	beq .ch_move
	cmp #AI_CMD_APPROACH_ENTER
	beq .ch_enter
	cmp #AI_CMD_DRAW
	bne +
	jmp .ch_draw
+
	cmp #AI_CMD_ELEC
	bne +
	jmp ch_elec
+
	cmp #AI_CMD_ANIM_FIRE
	bne +
	jmp .ch_anim_fire
+
	rts

; en_pat_n = 0 until the rise has been started.
; Rise waits on the rune of earth magic so the pickup and the boss are not drawn together.
.ch_idle
	jsr .ch_service
	ldx enemy_idx
	lda en_state,x
	cmp #EN_PAIN
	beq .ch_idle_out
	jsr .ch_rune_taken
	bcc .ch_idle_out
	ldx enemy_idx
	lda #1
	sta en_pat_n,x
	jsr enemy_face_player
	jsr enemy_enter_alert
.ch_idle_out
	lda #0
	rts

.ch_enter
	jsr .ch_service
	ldx enemy_idx
	lda en_state,x
	cmp #EN_PAIN
	bne +
	lda #0
	rts
+
	ldx enemy_idx
	lda en_pat_n,x
	bne .ch_risen
	jsr .ch_rune_taken
	bcs .ch_start
	ldx enemy_idx
	lda #EN_IDLE
	sta en_state,x
	lda #0
	rts
.ch_start
	ldx enemy_idx
	lda #1
	sta en_pat_n,x
	jsr enemy_face_player
	jmp enemy_enter_alert
.ch_risen
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	rts

; C=1 once the rune of earth magic has been picked up.
; bp_type's field id is $80; the AI map patch drops that high bit, so this is a fixed byte.
.ch_rune_taken
	lda rune_taken
	cmp #1
	rts

; Rise is over. Start the attack loop and skip the chase step.
.ch_move
	jsr .ch_service
	ldx enemy_idx
	lda en_state,x
	cmp #EN_PAIN
	beq .ch_move_out
	jsr enemy_enter_attack
	lda #AI_AP_NEXT
	rts
.ch_move_out
	lda #AI_AP_NEXT
	rts

.ch_tick
	jsr .ch_service
	ldx enemy_idx
	lda en_state,x
	cmp #EN_PAIN
	beq .ch_tick_out
	jsr enemy_face_player
.ch_tick_out
	lda #0
	rts

.ch_end
	ldx enemy_idx
	jmp enemy_enter_attack

.ch_fire
	ldx enemy_idx
	stx obj_i
	+lda_mx en_type
	sta ent_type
	ldy #CHTHON_LAVA_VERT
	lda en_frame,x
	cmp #CHTHON_FIRE2
	bcc .ch_fire_v
	ldy #CHTHON_LAVA_VERT2
.ch_fire_v
	jsr ent_vert_world
	jsr .ch_unshift
	jsr gren_alloc
	bcc .ch_fire_rts
	stx obj_i
	; rot2 is any index: .ch_aim overwrites every velocity byte
	ldx obj_i
	lda #GREN_OWN_EN
	jsr gren_fill_slot
	ldx obj_i
	lda #GREN_F_LAVA
	sta gr_flags,x
	jmp .ch_aim
.ch_fire_rts
	rts

; ent_vert_world reads packed coords (v >> shift). Scale the bone offset from
; the origin back up so the throw point sits on the drawn body.
.ch_unshift
	ldx ent_type
	lda skel_base_hi,x
	beq .chu_rts
	sta src_ptr+1
	lda skel_base_lo,x
	sta src_ptr
	ldy #SKEL_PFX_SHIFT
	lda (src_ptr),y
	beq .chu_rts
	sta rot2
	ldx enemy_idx
	lda org_xh
	sec
	+sbc_mx en_x
	sta org_xh
	lda org_yh
	sec
	+sbc_mx en_y
	sta org_yh
	lda org_zh
	sec
	+sbc_mx en_z
	sta org_zh
	ldy rot2
.chu_sh
	asl org_xl
	rol org_xh
	asl org_yl
	rol org_yh
	asl org_zl
	rol org_zh
	dey
	bne .chu_sh
	clc
	lda org_xh
	+adc_mx en_x
	sta org_xh
	clc
	lda org_yh
	+adc_mx en_y
	sta org_yh
	clc
	lda org_zh
	+adc_mx en_z
	sta org_zh
.chu_rts
	rts

; Straight line to the chest at CHTHON_LAVA_SPEED (8.8 per tick = speed<<8 * a / L).
; d = chest - slot; L ~ max + 3/8 (sum - max). Velocity bytes are 4 apart per
; slot, axes 8 apart: gr_vxl/vxh, gr_vyl/vyh, gr_vzl/vzh.
!if CHTHON_LAVA_SPEED != 32 {
	!error "numerator below is a << 13"
}
!if (gr_vxh != gr_vxl + 4) | (gr_vyl != gr_vxl + 8) | (gr_vzl != gr_vxl + 16) | (gr_vzh != gr_vxl + 20) {
	!error "gr_v* layout"
}
.ch_aim
	ldx obj_i
	lda cam_xh
	sec
	sbc gr_xh,x
	sta ch_sg
	lda cam_yh
	clc
	sbc gr_yh,x			; cam_yh - gr_yh - 1: chest
	sta ch_sg+1
	lda cam_zh
	sec
	sbc gr_zh,x
	sta ch_sg+2
	ldy #2
.cha_abs
	lda ch_sg,y
	jsr .ch_abs
	sta ch_ad,y
	dey
	bpl .cha_abs
	lda ch_ad
	clc
	adc ch_ad+1
	adc ch_ad+2
	sta ch_t			; sum
	lda ch_ad
	cmp ch_ad+1
	bcs +
	lda ch_ad+1
+
	cmp ch_ad+2
	bcs +
	lda ch_ad+2
+
	sta ch_mx
	lda ch_t
	sec
	sbc ch_mx
	lsr
	lsr
	sta ch_t			; (sum-max)/4
	lsr
	clc
	adc ch_t
	clc
	adc ch_mx
	bne +
	lda #1
+
	sta dlo
	ldy #0
.cha_ax
	lda #0
	sta div_n0
	sta div_n1
	lda ch_ad,y
	lsr
	ror div_n1
	lsr
	ror div_n1
	lsr
	ror div_n1
	sta div_n2
	jsr div24u8			; keeps Y
	lda ch_sg,y
	bpl .cha_pos
	sec
	lda #0
	sbc div_n0
	sta div_n0
	lda #0
	sbc div_n1
	sta div_n1
.cha_pos
	tya
	asl
	asl
	asl
	clc
	adc obj_i
	tax
	lda div_n0
	sta gr_vxl,x
	lda div_n1
	sta gr_vxh,x
	iny
	cpy #3
	bne .cha_ax
	rts

.ch_abs
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts

; Cache the two crates in Chthon's room, then consume a pending electrode request.
.ch_service
	lda ch_enemy
	cmp #$ff
	bne .chs_req
	jsr .ch_cache
	lda ch_enemy
	cmp #$ff
	bne .chs_req
	rts
.chs_req
	lda ch_req
	cmp #CH_REQ_LOWER
	beq .chs_lower
	cmp #CH_REQ_FIRE
	bne +
	jmp .chs_fire
+
	rts

.ch_cache
	ldx enemy_idx
	+lda_mx en_room
	sta ch_pok
	ldy #0
	ldx #0
.chc_lp
	cpx	map_ncrates
	bcs .chc_done
	+lda_mx crate_room
	cmp ch_pok
	bne .chc_n
	cpy #2
	bcs .chc_n
	txa
	sta ch_crate,y
	+lda_mx crate_y
	sta ch_home,y
	lda #CH_PHASE_UP
	sta ch_phase,y
	lda #0
	sta ch_acc_l,y
	sta ch_acc_h,y
	iny
.chc_n
	inx
	bne .chc_lp
.chc_done
	cpy #2
	bcc .chc_rts
	ldx enemy_idx
	stx ch_enemy
.chc_rts
	rts

.chs_eat
	lda #0
	sta ch_req
	rts

.chs_lower
	lda ch_bolt_l
	ora ch_bolt_h
	bne .chs_eat
	ldx ch_trig
	+lda_mx tr_z
	sta ch_psy
	ldx #0
	jsr .ch_zdist
	sta ch_dist
	ldx #1
	jsr .ch_zdist
	ldx #0
	cmp ch_dist
	bcs +
	ldx #1
+
	jsr .ch_raised
	bcc .chs_eat
	lda #CH_PHASE_DOWN
	sta ch_phase,x
	lda #0
	sta ch_acc_l,x
	sta ch_acc_h,x
	jsr elev_noise_on
	jmp .chs_eat

; C=1 if slot X is fully raised.
.ch_raised
	lda ch_phase,x
	bne .chr_no
	ldy ch_crate,x
	+lda_my crate_y
	cmp ch_home,x
	bne .chr_no
	sec
	rts
.chr_no
	clc
	rts

; A = |crate_z - ch_psy| for slot X.
.ch_zdist
	ldy ch_crate,x
	+lda_my crate_z
	sec
	sbc ch_psy
	bcs +
	eor #$ff
	adc #1
+
	rts

.chs_fire
	lda ch_bolt_l
	ora ch_bolt_h
	bne .chs_fire_no
	lda ch_phase
	cmp ch_phase+1
	bne .chs_fire_no
	cmp #CH_PHASE_UP
	beq .chs_fys
	cmp #CH_PHASE_HOLD
	beq .chs_fys
.chs_fire_no
	jmp .chs_eat
.chs_fys
	ldy ch_crate
	+lda_my crate_y
	sta ch_pok
	ldy ch_crate+1
	+lda_my crate_y
	cmp ch_pok
	bne .chs_fire_no
	lda #<CH_BOLT_MS
	sta ch_bolt_l
	lda #>CH_BOLT_MS
	sta ch_bolt_h
	lda ch_phase
	cmp #CH_PHASE_HOLD
	bne .chs_fire_no
	ldx enemy_idx
	lda en_state,x
	beq .chs_fire_no
	cmp #EN_DYING
	bcs .chs_fire_no
	lda #0
	sta en_frame,x
	sta en_pain_i,x
	lda #EN_PAIN
	sta en_state,x
	lda #1
	sta ch_shock
	lda #CUE_WINCE
	jsr enemy_play_cue
	jmp .chs_eat

; 10 segments, same X, spaced along Z, Y jittered off the straight line.
.ch_draw
	lda ch_bolt_l
	ora ch_bolt_h
	beq .chd_out
	lda ch_enemy
	cmp #$ff
	bne +
.chd_out
	rts
+
	ldx #0
	jsr .ch_center
	ldx #1
	jsr .ch_center
	lda ch_az
	cmp ch_bz
	bcc .chd_ord
	beq .chd_ord
	ldy ch_bz
	sta ch_bz
	sty ch_az
	lda ch_ay
	ldy ch_by
	sta ch_by
	sty ch_ay
.chd_ord
	lda #0
	sta ch_i
	sta ch_pok
	jsr .ch_point
	jsr .ch_project
	bcc .chd_loop
	lda ox0l
	pha
	lda ox0h
	pha
	lda oy0l
	pha
	lda oy0h
	pha
	lda #1
	sta ch_pok
.chd_loop
	inc ch_i
	lda ch_i
	cmp #11
	bcs .chd_pop
	jsr .ch_point
	jsr .ch_project
	bcc .chd_miss
	lda ox0l
	sta ch_best
	lda ox0h
	sta ch_dist
	lda oy0l
	sta ch_prod
	lda oy0h
	sta ch_prod_h
	lda ch_pok
	beq .chd_arm
	pla
	sta oy0h
	pla
	sta oy0l
	pla
	sta ox0h
	pla
	sta ox0l
	lda ch_best
	sta ox1l
	lda ch_dist
	sta ox1h
	lda ch_prod
	sta oy1l
	lda ch_prod_h
	sta oy1h
	jsr clip_draw_xy
.chd_arm
	lda ch_best
	pha
	lda ch_dist
	pha
	lda ch_prod
	pha
	lda ch_prod_h
	pha
	lda #1
	sta ch_pok
	jmp .chd_loop
.chd_miss
	lda ch_pok
	beq .chd_loop
	pla
	pla
	pla
	pla
	lda #0
	sta ch_pok
	jmp .chd_loop
.chd_pop
	lda ch_pok
	beq .chd_rts
	pla
	pla
	pla
	pla
.chd_rts
	rts

; Slot X → centre. Slot 0 fills ch_ax/ay/az. Slot 1 fills ch_by/bz (X stays ch_ax).
.ch_center
	ldy ch_crate,x
	+lda_my crate_sy
	lsr
	sta ch_pok
	+lda_my crate_y
	clc
	adc ch_pok
	cpx #0
	bne .chc_y1
	sta ch_ay
	jmp .chc_z
.chc_y1
	sta ch_by
.chc_z
	+lda_my crate_sz
	lsr
	sta ch_pok
	+lda_my crate_z
	clc
	adc ch_pok
	cpx #0
	bne .chc_z1
	sta ch_az
	+lda_my crate_sx
	lsr
	sta ch_pok
	+lda_my crate_x
	clc
	adc ch_pok
	sta ch_ax
	rts
.chc_z1
	sta ch_bz
	rts

; ch_i → world Y/Z in ch_psy/ch_psx. Ends stay on the straight line.
.ch_point
	ldy ch_i
	lda ch_bz
	sec
	sbc ch_az
	jsr .ch_span
	clc
	adc ch_az
	sta ch_psx
	lda ch_by
	sec
	sbc ch_ay
	bcs .chp_pos
	eor #$ff
	adc #1
	ldy ch_i
	jsr .ch_span
	sta ch_dist
	lda ch_ay
	sec
	sbc ch_dist
	sta ch_psy
	jmp .chp_jit
.chp_pos
	ldy ch_i
	jsr .ch_span
	clc
	adc ch_ay
	sta ch_psy
.chp_jit
	lda ch_i
	beq .chp_rts
	cmp #10
	beq .chp_rts
	jsr rnd8
	and #7
	sec
	sbc #4
	clc
	adc ch_psy
	sta ch_psy
.chp_rts
	rts

; A = delta * Y / 10. Y is consumed.
.ch_span
	sta ch_dist
	cpy #0
	beq .chsp0
	lda #0
	sta ch_prod
	sta ch_prod_h
.chsp_mul
	clc
	lda ch_prod
	adc ch_dist
	sta ch_prod
	lda ch_prod_h
	adc #0
	sta ch_prod_h
	dey
	bne .chsp_mul
	lda #0
	sta ch_best
.chsp_div
	lda ch_prod_h
	bne .chsp_sub
	lda ch_prod
	cmp #10
	bcc .chsp_q
.chsp_sub
	sec
	lda ch_prod
	sbc #10
	sta ch_prod
	lda ch_prod_h
	sbc #0
	sta ch_prod_h
	inc ch_best
	jmp .chsp_div
.chsp_q
	lda ch_best
	rts
.chsp0
	lda #0
	rts

.ch_project
	jsr load_view_trig		; proj_cam_to_proj overwrites set A (cos)
	lda #0
	sta org_xl
	sta org_yl
	sta org_zl
	lda ch_ax
	sta org_xh
	lda ch_psy
	sta org_yh
	lda ch_psx
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	jmp cam0_proj_xy

; Frame 5 comes from enemy_fire_frame. Frame 17 is the second throw.
; A = 0: this bank owns both, so the resident table must not also fire.
.ch_anim_fire
	lda #CHTHON_FIRE1		; enemy_fire_frame is meta-slot indexed, not by type
	jsr .ch_crossed
	bcs .ch_af_go
	lda #CHTHON_FIRE2
	jsr .ch_crossed
	bcc .ch_af_own
.ch_af_go
	jsr .ch_fire
.ch_af_own
	lda #0
	rts

.ch_crossed
	bmi .chcr_no
	cmp en_sfx_old
	beq .chcr_no
	bcc .chcr_no
	sta rot1
	ldx enemy_idx
	lda en_frame,x
	cmp rot1
	rts
.chcr_no
	clc
	rts

; Electrode crates. Armed by .ch_service; stepped every frame from the resident stub.
ch_elec
	lda ch_bolt_l
	ora ch_bolt_h
	beq .el_step
	sec
	lda ch_bolt_l
	sbc dt_ms
	sta ch_bolt_l
	lda ch_bolt_h
	sbc dt_msh
	sta ch_bolt_h
	bcs .el_frozen
	jmp .el_bolt_end
.el_frozen
	rts
.el_step
	ldx #0
	jsr .el_crate
	ldx #1
	jmp .el_crate

.el_bolt_end
	lda #0
	sta ch_bolt_l
	sta ch_bolt_h
	ldx #0
	jsr .el_up
	ldx #1
	jsr .el_up
	jsr .el_step
	lda ch_shock
	bne .el_shock
	rts
.el_shock
	lda #0
	sta ch_shock
	ldx ch_enemy
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcc .el_dmg
	rts
.el_dmg
	lda en_hp,x
	cmp #CH_SHOCK_DMG
	bcc .el_kill
	beq .el_kill
	sec
	sbc #CH_SHOCK_DMG
	sta en_hp,x
	jmp enemy_enter_attack
.el_kill
	jmp kill_enemy

; Leave a crate that is already up or rising. Otherwise start the slow rise.
.el_up
	lda ch_phase,x
	beq .el_up_rts
	cmp #CH_PHASE_RISE
	beq .el_up_rts
	cmp #CH_PHASE_HOLD
	bne .el_up_go
	jsr elev_noise_on
.el_up_go
	lda #CH_PHASE_RISE
	sta ch_phase,x
	lda #0
	sta ch_acc_l,x
	sta ch_acc_h,x
.el_up_rts
	rts

.el_crate
	lda ch_phase,x
	beq .elc_rts
	cmp #CH_PHASE_DOWN
	beq .elc_down
	cmp #CH_PHASE_HOLD
	bne .elc_rise_go
	jmp .elc_hold
.elc_rise_go
	jmp .elc_rise
.elc_rts
	rts

.elc_add
	clc
	lda ch_acc_l,x
	adc dt_ms
	sta ch_acc_l,x
	lda ch_acc_h,x
	adc dt_msh
	sta ch_acc_h,x
	rts

.elc_down
	jsr .elc_add
.elc_dlp
	lda ch_acc_h,x
	bne .elc_dstep
	rts
.elc_dstep
	dec ch_acc_h,x
	lda ch_home,x
	sec
	sbc #CH_DROP
	sta ch_psy
	ldy ch_crate,x
	+lda_my crate_y
	sec
	sbc #1
	sta ch_pok
	cmp ch_psy
	bcc .elc_dhit
	beq .elc_dhit
	+sta_my crate_y
	jmp .elc_dlp
.elc_dhit
	lda ch_psy
	+sta_my crate_y
	lda #CH_PHASE_HOLD
	sta ch_phase,x
	jsr elev_noise_off
	lda #<CH_HOLD_MS
	sta ch_acc_l,x
	lda #>CH_HOLD_MS
	sta ch_acc_h,x
	rts

.elc_hold
	sec
	lda ch_acc_l,x
	sbc dt_ms
	sta ch_acc_l,x
	lda ch_acc_h,x
	sbc dt_msh
	sta ch_acc_h,x
	bcc .elc_hold_up
	rts
.elc_hold_up
	jsr elev_noise_on
	lda #CH_PHASE_RISE
	sta ch_phase,x
	lda #0
	sta ch_acc_l,x
	sta ch_acc_h,x
	rts

.elc_rise
	jsr .elc_add
.elc_rlp
	lda ch_acc_h,x
	bne .elc_rstep
	rts
.elc_rstep
	dec ch_acc_h,x
	ldy ch_crate,x
	+lda_my crate_y
	clc
	adc #1
	sta ch_pok
	cmp ch_home,x
	bcs .elc_rtop
	+sta_my crate_y
	jmp .elc_rlp
.elc_rtop
	lda ch_home,x
	+sta_my crate_y
	lda #CH_PHASE_UP
	sta ch_phase,x
	jsr elev_noise_off
	lda #0
	sta ch_acc_l,x
	sta ch_acc_h,x
	rts

; Data after all code so genaimeta's opcode walk stays aligned.
ch_sg	!byte 0, 0, 0		; signed dx, dy, dz
ch_ad	!byte 0, 0, 0		; magnitudes
ch_t	!byte 0
ch_mx	!byte 0