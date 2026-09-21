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
	lda #<SOUND_OGRE_OGDRAG
	jmp play_sound
.grenade
	lda enemy_idx
	sta emuz_pending
	jmp spawn_ogre_grenade
.rts
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
