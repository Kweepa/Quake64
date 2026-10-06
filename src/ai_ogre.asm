; Streamed Ogre attack behavior. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_ogre.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_ogre_entry
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
	bne .og_rts
	jmp .anim_fire
.og_rts
	rts

.attack_end
	ldx enemy_idx
	lda en_pain_i,x
	bne .approach			; grenade always returns to chase
	jsr enemy_same_floor
	bcc .approach
	jsr enemy_chebyshev
	cmp #OGRE_MELEE_R + 1
	bcs .approach
	lda #0
	jmp enemy_enter_ogre_attack
.approach
	jmp enemy_enter_approach

; Hold in the grenade band. Chase during APPROACH_MIN_MS would walk
; them into saw range before the first attack is allowed.
.approach_move
	jsr enemy_chebyshev
	cmp #OGRE_MELEE_R + 1
	bcc .ap_chase
	jsr enemy_cmp_range
	beq .ap_band
	bcs .ap_chase
.ap_band
	jsr enemy_shot_clear
	bcc .ap_chase
	ldx enemy_idx
	lda #AI_AP_STAND
	rts
.ap_chase
	ldx enemy_idx
	lda #AI_AP_MOVE
	rts

.approach_attack
	jsr enemy_chebyshev
	cmp #OGRE_MELEE_R + 1
	bcs .approach_grenade
	jsr enemy_same_floor
	bcc .approach_grenade
	lda #0
	jmp enemy_enter_ogre_attack
.approach_grenade
	jsr enemy_shot_clear
	bcs +
	rts
+
	lda #1
	jmp enemy_enter_ogre_attack

.approach_enter
	ldx enemy_idx
	lda #<APPROACH_MIN_MS
	sta en_timer,x
	lda #>APPROACH_MIN_MS
	sta en_timer_h,x
	jmp select_dodge_dir

.fire
	ldx enemy_idx
	lda en_pain_i,x
	bne .grenade
	jsr enemy_same_floor
	bcc .rts
	jsr enemy_chebyshev
	cmp #OGRE_MELEE_R + 1
	bcs .rts
	jsr rnd8
	and #3
	clc
	adc #OGRE_SAW_DMG
	sta rot0
	lda player_hp
	beq .rts
	lda rot0
	jsr take_damage
	lda enemy_idx
	sta bite_splat_i
	rts
.grenade
	lda enemy_idx
	sta emuz_pending
	jmp spawn_ogre_grenade
.rts
	rts

; Shoot keeps A = AI_CMD_ANIM_FIRE so the resident table supplies the frame.
.anim_fire
	ldx enemy_idx
	lda en_pain_i,x
	beq .af_swing
	lda #AI_CMD_ANIM_FIRE
	rts
.af_swing
	lda #OGRE_SWING_FIRE
	jsr .crossed
	bcc .af_own
	jsr .fire
.af_own
	lda #0
	rts

.crossed
	bmi .cr_no
	cmp rot2
	beq .cr_no
	bcc .cr_no
	sta rot1
	ldx enemy_idx
	lda en_frame,x
	cmp rot1
	rts
.cr_no
	clc
	rts
