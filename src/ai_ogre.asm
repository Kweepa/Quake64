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
	jmp enemy_enter_approach

; Own the cell step at half cadence. STAND skips the shared 200ms stepper.
; The run clip still advances from EN_APPROACH.
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
	cmp #>OGRE_STEP_MS
	bcc .done
	bne .go
	lda en_step,x
	cmp #<OGRE_STEP_MS
	bcc .done
.go
	sec
	lda en_step,x
	sbc #<OGRE_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #>OGRE_STEP_MS
	sta en_step_h,x
	jsr enemy_try_step
	ldx enemy_idx
	jmp .slp
.done
	ldx enemy_idx
	lda #AI_AP_STAND
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
	jmp .ap_gren

.approach_enter
	ldx enemy_idx
	lda #<OGRE_ATK_MS
	sta en_timer,x
	lda #>OGRE_ATK_MS
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
	jsr ogre_grenade_live
	bcs .rts
	lda enemy_idx
	sta emuz_pending
	jmp spawn_ogre_grenade
.rts
	rts

; Past .fire so the entry beq stays in range.
.ap_gren
	jsr ogre_grenade_live
	bcs .rts
	jsr enemy_shot_clear
	bcc .rts
	lda #1
	jmp enemy_enter_ogre_attack

; C=1 if an ogre grenade (not flesh, not lava) is already live.
ogre_grenade_live
	ldx #0
.ogl
	lda gr_on,x
	beq .ogl_n
	lda gr_owner,x
	cmp #GREN_OWN_EN
	bne .ogl_n
	lda gr_flags,x
	and #GREN_F_FLESH | GREN_F_LAVA
	bne .ogl_n
	sec
	rts
.ogl_n
	inx
	cpx #GREN_MAX
	bcc .ogl
	clc
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
	cmp en_sfx_old
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
