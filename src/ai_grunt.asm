; Streamed Grunt approach / reattack / gunshot. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_grunt.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_grunt_entry
	cmp #AI_CMD_DEATH
	bne +
	jmp .death
+
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
	rts

.approach_move
	lda #AI_AP_MOVE
	rts

.approach_attack
	jsr enemy_shot_clear
	bcs .attack_go
	rts
.attack_go
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #<GRUNT_ATK_MS
	sta en_timer,x
	lda #>GRUNT_ATK_MS
	sta en_timer_h,x
	jmp select_dodge_dir

; LOS, then miss if rnd8 < dist*4. Hit is 8–15. Muzzle is this same call.
.fire
	lda enemy_idx
	sta emuz_pending
	jsr enemy_shot_clear
	bcc .fire_rts
	ldx enemy_idx
	jsr enemy_chebyshev
	asl
	asl
	bcs .fire_rts		; dist ≥ 64
	sta rot1
	jsr rnd8
	cmp rot1
	bcc .fire_rts
	and #7
	clc
	adc #8
	jmp take_damage
.fire_rts
	rts

.attack_end
	jmp enemy_enter_approach

.death
	lda #BP_SHELLS5
	jmp spawn_death_drop
