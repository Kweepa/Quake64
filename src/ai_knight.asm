; Streamed Knight attack behavior. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_knight.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_knight_entry
	cmp #AI_CMD_ATTACK_TICK
	bne +
	jmp .tick
+
	cmp #AI_CMD_FIRE
	bne +
	jmp .fire
+
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .attack_end
+
	cmp #AI_CMD_APPROACH_MOVE
	bne +
	jmp .approach_move
+
	cmp #AI_CMD_APPROACH_ATTACK
	bne +
	jmp .approach_attack
+
	cmp #AI_CMD_APPROACH_ENTER
	bne +
	jmp .approach_enter
+
	rts

.approach_move
	jsr enemy_same_floor
	bcc .approach_move_yes
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp enemy_range + ENT_KNIGHT
	beq .approach_stand
	bcc .approach_stand
.approach_move_yes
	ldx enemy_idx
	lda #AI_AP_MOVE
	rts
.approach_stand
	ldx enemy_idx
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	lda #AI_AP_STAND
	rts

.approach_attack
	jsr enemy_same_floor
	bcs +
	rts
+
	lda #0
	jmp enemy_enter_knight_attack

.approach_enter
	ldx enemy_idx
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	jmp select_dodge_dir

.tick
	ldx enemy_idx
	lda en_pain_i,x
	bne .rts			; attackb is planted
	lda en_frame,x
	cmp #KNIGHT_RUNATK_FIRE
	bcs .rts
	clc
	lda en_step,x
	adc dt_ms
	sta en_step,x
	lda en_step_h,x
	adc dt_msh
	sta en_step_h,x
.tick_loop
	lda en_step_h,x
	bne .tick_go
	lda en_step,x
	cmp #ENEMY_STEP_MS
	bcc .rts
.tick_go
	sec
	lda en_step,x
	sbc #ENEMY_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #0
	sta en_step_h,x
	jsr enemy_patrol_step
	ldx enemy_idx
	jmp .tick_loop

.fire
	ldx enemy_idx
	jsr enemy_same_floor
	bcc .rts
	jsr enemy_chebyshev
	cmp enemy_range + ENT_KNIGHT
	beq .slash
	bcc .slash
	rts
.slash
	jsr rnd8
	and #3
	clc
	adc #KNIGHT_SLASH_DMG
	sta rot0
	lda player_hp
	beq .rts
	lda rot0
	jsr take_damage
	lda enemy_idx
	sta bite_splat_i
.rts
	rts

.attack_end
	ldx enemy_idx
	jsr enemy_same_floor
	bcc .approach
	jsr enemy_chebyshev
	cmp enemy_range + ENT_KNIGHT
	beq .again
	bcc .again
.approach
	jmp enemy_enter_approach
.again
	lda #1
	jmp enemy_enter_knight_attack
