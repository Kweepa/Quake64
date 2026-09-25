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
	rts

.approach_move
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp #SCRAG_HOLD_R + 1
	bcs .approach_move_yes
	jsr enemy_shot_clear
	bcc .approach_move_yes
	ldx enemy_idx
	lda #AI_AP_STAND
	rts
.approach_move_yes
	ldx enemy_idx
	lda #AI_AP_MOVE
	rts

.approach_attack
	jsr enemy_shot_clear
	bcs +
	rts
+
	jmp enemy_enter_attack

.approach_enter
	ldx enemy_idx
	lda #<SCRAG_REFIRE_MS
	sta en_timer,x
	lda #>SCRAG_REFIRE_MS
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
	sta rot0
	lda #0
	sta rot1
	sta rot2
	jsr div24u8
	ldx enemy_idx
	+lda_mx en_y
	sec
	sbc rot0
	bcc .clamp
	cmp proc_tmp2
	bcs .store
.clamp
	lda proc_tmp2
.store
	+sta_mx en_y
	rts
