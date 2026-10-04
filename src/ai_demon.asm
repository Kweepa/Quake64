; Streamed Demon attack behavior. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_demon.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_demon_entry
	cmp #AI_CMD_ATTACK_TICK
	beq .tick
	cmp #AI_CMD_FIRE
	bne +
	jmp .fire
+
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .attack_end
+
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	beq .approach_attack
	cmp #AI_CMD_APPROACH_ENTER
	beq .approach_enter
	rts

.approach_move
	jsr enemy_same_floor
	bcc .approach_move_yes
	ldx enemy_idx
	jsr enemy_chebyshev
	jsr enemy_cmp_range
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
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R + 1
	bcs .leap
	lda #1				; attacka, variant 1
	jmp enemy_enter_demon_attack
.leap
	jsr enemy_cmp_range
	beq .do_leap
	bcc .do_leap
	rts
.do_leap
	lda #0				; leap, variant 0
	jmp enemy_enter_demon_attack

.approach_enter
	ldx enemy_idx
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	jmp select_dodge_dir

; Leap is variant 0. Stop stepping once the claw radius is reached so the lunge doesn't tunnel.
.tick
	ldx enemy_idx
	lda en_pain_i,x
	bne .rts			; attacka is planted
	lda en_frame,x
	cmp #DEMON_LEAP_FIRE
	bcs .rts
	clc
	lda en_step,x
	adc dt_ms
	sta en_step,x
	lda en_step_h,x
	adc dt_msh
	sta en_step_h,x
.tick_loop
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R + 1
	bcc .rts
	ldx enemy_idx
	lda en_step_h,x
	bne .tick_go
	lda en_step,x
	cmp #DEMON_LEAP_STEP_MS
	bcc .rts
.tick_go
	sec
	lda en_step,x
	sbc #DEMON_LEAP_STEP_MS
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
	cmp #DEMON_MELEE_R + 1
	bcs .rts
	jsr rnd8
	and #7
	clc
	adc #DEMON_DMG
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
	cmp #DEMON_MELEE_R + 1
	bcs .maybe_leap
	lda #1				; attacka, variant 1
	jmp enemy_enter_demon_attack
.maybe_leap
	jsr enemy_cmp_range
	beq .leap_again
	bcc .leap_again
.approach
	jmp enemy_enter_approach
.leap_again
	lda #0				; leap, variant 0
	jmp enemy_enter_demon_attack
