; Streamed Scrag attack/death behavior. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_scrag.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_scrag_entry
	cmp #AI_CMD_FIRE
	beq .fire
	cmp #AI_CMD_ATTACK_END
	beq .attack_end
	cmp #AI_CMD_DYING_STEP
	beq .dying_step
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	beq .approach_attack
	cmp #AI_CMD_APPROACH_ENTER
	beq .approach_enter
	cmp #AI_CMD_SCRAG_DODGE
	beq .dodge
	cmp #AI_CMD_DRAW
	bne .rts
	jmp draw_spit

; Hold bubble: C=1 and en_dir set if a side probed clear. C=0 → caller
; falls into the toward-search. Not in the bubble: C=0.
.dodge
	jsr scrag_in_hold
	bcc .rts
	jmp scrag_roll_side

.approach_move
	jsr scrag_in_hold
	bcc +
	jsr scrag_hold_dir
+
	ldx enemy_idx
	lda #AI_AP_MOVE
	rts

.approach_attack
	jsr enemy_shot_clear
	bcc .rts
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #<SCRAG_ATK_MS
	sta en_timer,x
	lda #>SCRAG_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

.fire
	lda spit_on
	bne .rts
	lda enemy_idx
	sta emuz_pending
	jmp spawn_scrag_spit
.attack_end
	ldx enemy_idx
	jmp enemy_enter_approach
.rts
	rts

; Drop (en_y - floor) / frames_left so the final death frame lands.
.dying_step
	ldx enemy_idx
	+lda_mx en_x
	sta col_x
	+lda_mx en_z
	sta col_z
	+lda_mx en_y
	sta fb_probe_y
	+ldy_mx en_room
	jsr floor_below_y
	bcc .rts
	ldx enemy_idx
	+lda_mx en_y
	cmp proc_tmp2
	beq .rts
	bcc .rts
	sec
	sbc proc_tmp2
	pha
	lda en_frame,x
	jsr pain_var_off
	sta rot1
	lda enemy_death_len,y
	sec
	sbc rot1
	bne .have_n
	lda #1
.have_n
	sta dlo
	pla
	sta div_n0
	lda #0
	sta div_n1
	sta div_n2
	jsr div24u8
	ldx enemy_idx
	+lda_mx en_y
	sec
	sbc div_n0
	bcc .clamp
	cmp proc_tmp2
	bcs .store
.clamp
	lda proc_tmp2
.store
	+sta_mx en_y
	rts

; Already on a side: leave it. Otherwise roll. Both blocked: en_dir unchanged.
scrag_hold_dir
	jsr scrag_side_pair
	ldx enemy_idx
	lda en_dir,x
	cmp ai_dirtry
	beq .shd_rts
	cmp ai_dirtry+1
	beq .shd_rts
	jmp scrag_roll_side
.shd_rts
	rts

; Always roll a side into en_dir. C=1 if a probe cleared.
scrag_roll_side
	jsr scrag_side_pair
	jsr rnd8
	bmi .srs_try
	lda ai_dirtry
	ldx ai_dirtry+1
	sta ai_dirtry+1
	stx ai_dirtry
.srs_try
	lda ai_dirtry
	jsr enemy_probe_dir
	bcs .srs_set
	lda ai_dirtry+1
	jsr enemy_probe_dir
	bcc .shd_rts
.srs_set
	ldx enemy_idx
	lda ai_probe
	jsr enemy_set_geom
	sec
	rts

; C=1 if Chebyshev <= SCRAG_HOLD_R and the shot line is clear.
scrag_in_hold
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp #SCRAG_HOLD_R + 1
	bcc .sih_los
	clc
	rts
.sih_los
	jmp enemy_shot_clear

; ai_dirtry / +1 = the two side cardinals. |dx| / |dz| left in dodge_dx / dodge_dz.
scrag_side_pair
	ldx enemy_idx
	lda cam_xh
	sec
	+sbc_mx en_x
	bpl .ssp_dx
	eor #$ff
	clc
	adc #1
.ssp_dx
	sta dodge_dx
	lda cam_zh
	sec
	+sbc_mx en_z
	bpl .ssp_dz
	eor #$ff
	clc
	adc #1
.ssp_dz
	sta dodge_dz
	ldx #0
	cmp dodge_dx
	bcc .ssp_set
	ldx #2
.ssp_set
	stx ai_dirtry
	txa
	ora #4
	sta ai_dirtry+1
	rts

!source "spit.asm"
