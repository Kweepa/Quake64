; Streamed Zombie chase / flesh-throw / knockdown. Linked at AI_LINK_BASE.
!cpu 6510
!to "../enemies/ai_zombie.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_zombie_entry
	cmp #AI_CMD_ATTACK_TICK
	beq .tick
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .attack_end
+
	cmp #AI_CMD_DYING_STEP
	bne +
	jmp .dying_step
+
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	beq .approach_attack
	cmp #AI_CMD_APPROACH_ENTER
	beq .approach_enter
	rts

.tick
	ldx enemy_idx
	lda en_frame,x
	jsr pain_var_off
	lda enemy_attack_len,y
	sec
	sbc #1
	ldx enemy_idx
	cmp en_frame,x
	beq .fire
	rts

.approach_move
	ldx enemy_idx
	clc
	lda en_step,x
	adc dt_ms
	sta en_step,x
	lda en_step_h,x
	adc dt_msh
	sta en_step_h,x
.slp
	lda en_step_h,x
	cmp #>ZOMBIE_STEP_MS
	bcc .done
	bne .go
	lda en_step,x
	cmp #<ZOMBIE_STEP_MS
	bcc .done
.go
	sec
	lda en_step,x
	sbc #<ZOMBIE_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #>ZOMBIE_STEP_MS
	sta en_step_h,x
	jsr enemy_try_step
	ldx enemy_idx
	jmp .slp
.done
	ldx enemy_idx
	lda #AI_AP_STAND
	rts

.approach_attack
	jsr .flesh_live
	bcs .aa_rts
	jsr .throw_busy
	bcs .aa_rts
	jsr enemy_shot_clear
	bcs +
.aa_rts
	rts
+
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	jmp select_dodge_dir

.fire
	jsr .flesh_live
	bcc +
	rts
+
	ldx enemy_idx
	stx obj_i
	+lda_mx en_type
	sta ent_type
	ldy #GREN_WRIST_L
	jsr ent_vert_world
	jsr gren_alloc
	bcc .fire_rts
	stx obj_i
	lda cam_xh
	sec
	sbc org_xh
	sta rot0
	lda cam_zh
	sec
	sbc org_zh
	sta rot1
	jsr atan2_yaw
	sta rot2
	ldx obj_i
	lda #GREN_OWN_EN
	jsr gren_fill_slot
	ldx obj_i
	lda #GREN_F_FLESH
	sta gr_flags,x
	asl gr_vxh,x
	asl gr_vzh,x
.fire_rts
	rts

.flesh_live
	ldx #0
.fl
	lda gr_on,x
	beq .fl_n
	lda gr_flags,x
	and #GREN_F_FLESH
	beq .fl_n
	sec
	rts
.fl_n
	inx
	cpx #GREN_MAX
	bcc .fl
	clc
	rts

; C=1 if another zombie in this room is already in EN_ATTACK.
.throw_busy
	ldx #0
.tb
	cpx map_nenemies
	bcs .tb_no
	cpx enemy_idx
	beq .tb_n
	lda en_state,x
	cmp #EN_ATTACK
	bne .tb_n
	+lda_mx en_room
	cmp room_idx
	bne .tb_n
	+lda_mx en_type
	cmp #ENT_ZOMBIE
	beq .tb_yes
.tb_n
	inx
	bne .tb
.tb_no
	clc
	rts
.tb_yes
	sec
	rts

.attack_end
	ldx enemy_idx
	jmp enemy_enter_approach

.dying_step
	ldx enemy_idx
	lda en_frame,x
	cmp #1
	bne .not_first
	lda #0
	sta en_step,x
	sta en_step_h,x
	rts
.not_first
	cmp #ZOMBIE_HOLD_FRAME + 1
	bcc .rts
	beq .hold
	jsr pain_var_off
	cmp enemy_death_len,y
	bcc .rts
	ldx enemy_idx
	+ldy_mx en_type
	lda enemy_hp_init,y
	sta en_hp,x
	jmp enemy_enter_approach
.hold
	lda en_step,x
	bne .counting
	jsr rnd8
	and #63
	clc
	adc #ZOMBIE_DOWN_BASE
	ldx enemy_idx
	sta en_step,x
	lda #ZOMBIE_HOLD_FRAME
	sta en_frame,x
	rts
.counting
	dec en_step,x
	beq .rts
	lda #ZOMBIE_HOLD_FRAME
	sta en_frame,x
.rts
	rts
