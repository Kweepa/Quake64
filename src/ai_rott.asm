; Streamed Rottweiler attack behavior. Linked at AI_LINK_BASE, relocated on load.
!cpu 6510
!to "../enemies/ai_rott.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_rott_entry
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
	bcs .approach_same
	ldx enemy_idx
	lda en_timer,x
	ora en_timer_h,x
	bne .approach_move_yes
	lda #EN_IDLE
	sta en_state,x
	lda #0
	sta en_frame,x
	lda #<DOG_WAIT_MS
	sta en_timer,x
	lda #>DOG_WAIT_MS
	sta en_timer_h,x
	lda #AI_AP_NEXT
	rts
.approach_same
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp enemy_range + ENT_ROTT
	beq .approach_stand
	bcc .approach_stand
	ldx enemy_idx
	lda en_timer,x
	ora en_timer_h,x
	bne .approach_move_yes
	jsr select_dodge_dir
	ldx enemy_idx
	lda #<DOG_REPATH_MS
	sta en_timer,x
	lda #>DOG_REPATH_MS
	sta en_timer_h,x
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
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #<DOG_REPATH_MS
	sta en_timer,x
	lda #>DOG_REPATH_MS
	sta en_timer_h,x
	jmp select_dodge_dir

.fire
	ldx enemy_idx
	jsr enemy_same_floor
	bcc .rts
	jsr enemy_chebyshev
	cmp enemy_range + ENT_ROTT
	beq .roll
	bcc .roll
.rts
	rts
.roll
	jsr rnd8
	lsr
	lsr
	lsr
	lsr
	beq .rts
	sta rot0
	lda player_hp
	beq .rts
	lda rot0
	jsr take_damage
	lda enemy_idx
	sta bite_splat_i
	rts

.attack_end
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp enemy_range + ENT_ROTT
	beq .same
	bcc .same
	jmp enemy_enter_approach
.same
	jsr enemy_same_floor
	bcc .approach
	ldx enemy_idx
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr pick_attack_var
	jmp enemy_face_player
.approach
	jmp enemy_enter_approach
