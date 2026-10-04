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
	cmp #AI_CMD_PAIN
	beq .pain
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
	lda #<APPROACH_MIN_MS
	sta en_timer,x
	lda #>APPROACH_MIN_MS
	sta en_timer_h,x
	jmp select_dodge_dir

; Variant 0 is pain, 1 is painb. Under two clips, main rolls as usual.
.pain
	jsr slot_of_y
	lda enemy_pain_n,y
	cmp #2
	bcs .pain_pick
	lda #AI_CMD_PAIN
	rts
.pain_pick
	lda hit_dmg
	cmp #GRUNT_PAINB
	lda #0
	bcc .pain_set
	lda #1
.pain_set
	ldx enemy_idx
	sta en_pain_i,x
	lda #0
	rts

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

; Random back to approach, or another shot if still in range with LOS.
.attack_end
	jsr rnd8
	bmi .to_approach
	ldx enemy_idx
	jsr enemy_chebyshev
	jsr enemy_cmp_range
	beq .again
	bcc .again
.to_approach
	jmp enemy_enter_approach
.again
	ldx enemy_idx
	jsr enemy_shot_clear
	bcc .to_approach
	ldx enemy_idx
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr pick_attack_var
	jmp enemy_face_player
