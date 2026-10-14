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
	cmp #AI_CMD_FIRE
	beq .fire
	cmp #AI_CMD_ATTACK_END
	beq .attack_end
	cmp #AI_CMD_APPROACH_MOVE
	beq .approach_move
	cmp #AI_CMD_APPROACH_ATTACK
	beq .approach_attack
	cmp #AI_CMD_APPROACH_ENTER
	beq .approach_enter
	cmp #AI_CMD_ANIM_FIRE
	beq .anim_fire
	cmp #AI_CMD_ATTACK_TICK
	beq +
	rts
+
	jmp .tick

.attack_end
	jmp enemy_enter_approach

.approach_move
	jsr enemy_same_floor
	bcc .approach_move_yes
	jsr enemy_chebyshev
	jsr enemy_cmp_range
	beq .approach_stand
	bcc .approach_stand
.approach_move_yes
	ldx enemy_idx
	lda #AI_AP_MOVE
	rts
.approach_stand
	lda #AI_AP_STAND
	rts

.approach_attack
	jsr enemy_same_floor
	bcc .rts
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R + 1
	bcs .leap
	lda #1				; attacka, variant 1
	jmp enemy_enter_demon_attack
.leap
	jsr enemy_cmp_range
	beq .do_leap
	bcs .rts
.do_leap
	lda #0				; leap, variant 0
	jmp enemy_enter_demon_attack

.approach_enter
	ldx enemy_idx
	lda #<DEMON_ATK_MS
	sta en_timer,x
	lda #>DEMON_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

.fire
	ldx enemy_idx
	jsr enemy_same_floor
	bcc .rts
	jsr enemy_chebyshev
	cmp #DEMON_MELEE_R + 1
	bcs .rts
	lda player_hp
	beq .rts
	jsr rnd8
	and #7
	clc
	adc #DEMON_DMG
	jsr take_damage
	lda enemy_idx
	sta bite_splat_i
.rts
	rts

; Old frame in en_sfx_old, new frame in en_frame. Hit when old < fire <= new.
.anim_fire
	ldx enemy_idx
	lda #DEMON_LEAP_FIRE
	ldy en_pain_i,x
	beq +
	lda #DEMON_MELEE_FIRE
+
	cmp en_sfx_old
	beq .af_own
	bcc .af_own
	cmp en_frame,x
	beq .af_hit
	bcs .af_own
.af_hit
	jsr .fire
.af_own
	lda #0
	rts

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
	sec
	lda en_step,x
	sbc #DEMON_LEAP_STEP_MS
	tay
	lda en_step_h,x
	sbc #0
	bcc .rts			; under one leap cell
	sta en_step_h,x
	tya
	sta en_step,x
	jsr enemy_patrol_step
	ldx enemy_idx
	jmp .tick_loop
