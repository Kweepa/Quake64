; Chthon. Linked at AI_LINK_BASE. No walking: face the player, rise once, then loop attack.
; Idle is undrawn. Lava is a grenade with GREN_F_LAVA (no gravity, burst on contact).
!cpu 6510
!to "../enemies/ai_chthon.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

CHTHON_LAVA_VERT = 25		; high forward bone on the throw frame

*= AI_LINK_BASE
ai_chthon_entry
	cmp #AI_CMD_IDLE
	bne +
	jmp .ch_idle
+
	cmp #AI_CMD_FIRE
	bne +
	jmp .ch_fire
+
	cmp #AI_CMD_ATTACK_TICK
	bne +
	jmp .ch_tick
+
	cmp #AI_CMD_ATTACK_END
	bne +
	jmp .ch_end
+
	cmp #AI_CMD_APPROACH_MOVE
	bne +
	jmp .ch_move
+
	cmp #AI_CMD_APPROACH_ENTER
	bne +
	jmp .ch_enter
+
	rts

; en_pat_n = 0 until the rise has been started.
; Rise waits on the rune of earth magic so the pickup and the boss are not drawn together.
.ch_idle
	jsr .ch_rune_taken
	bcc .ch_idle_out
	ldx enemy_idx
	lda #1
	sta en_pat_n,x
	jsr enemy_face_player
	jsr enemy_enter_alert
.ch_idle_out
	lda #0
	rts

.ch_enter
	ldx enemy_idx
	lda en_pat_n,x
	bne .ch_risen
	jsr .ch_rune_taken
	bcs .ch_start
	ldx enemy_idx
	lda #EN_IDLE
	sta en_state,x
	lda #0
	rts
.ch_start
	ldx enemy_idx
	lda #1
	sta en_pat_n,x
	jsr enemy_face_player
	jmp enemy_enter_alert
.ch_risen
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	rts

; C=1 once the rune of earth magic has been picked up.
; bp_type's field id is $80; the AI map patch drops that high bit, so this is a fixed byte.
.ch_rune_taken
	lda rune_taken
	cmp #1
	rts

; Rise is over. Start the attack loop and skip the chase step.
.ch_move
	jsr enemy_enter_attack
	lda #AI_AP_NEXT
	rts

.ch_tick
	jsr enemy_face_player
	lda #0
	rts

.ch_end
	ldx enemy_idx
	jmp enemy_enter_attack

.ch_fire
	ldx enemy_idx
	stx obj_i
	+lda_mx en_type
	sta ent_type
	ldy #CHTHON_LAVA_VERT
	jsr ent_vert_world
	jsr .ch_unshift
	jsr gren_alloc
	bcc .ch_fire_rts
	stx obj_i
	lda cam_xh
	sec
	sbc org_xh
	sta rot0
	lda cam_zh
	sec
	sbc org_zh
	sta rot1
	jsr atan2_yaw
	sta rot2
	ldx obj_i
	lda #GREN_OWN_EN
	jsr gren_fill_slot
	ldx obj_i
	lda #GREN_F_LAVA
	sta gr_flags,x
	jsr .ch_aim
	lda #<SOUND_WEAPONS_GRENADE
	jmp play_sound
.ch_fire_rts
	rts

; ent_vert_world reads packed coords (v >> shift). Scale the bone offset from
; the origin back up so the throw point sits on the drawn body.
.ch_unshift
	ldx ent_type
	lda skel_base_hi,x
	beq .chu_rts
	sta src_ptr+1
	lda skel_base_lo,x
	sta src_ptr
	ldy #SKEL_PFX_SHIFT
	lda (src_ptr),y
	beq .chu_rts
	sta rot2
	ldx enemy_idx
	lda org_xh
	sec
	+sbc_mx en_x
	sta org_xh
	lda org_yh
	sec
	+sbc_mx en_y
	sta org_yh
	lda org_zh
	sec
	+sbc_mx en_z
	sta org_zh
	ldy rot2
.chu_sh
	asl org_xl
	rol org_xh
	asl org_yl
	rol org_yh
	asl org_zl
	rol org_zh
	dey
	bne .chu_sh
	clc
	lda org_xh
	+adc_mx en_x
	sta org_xh
	clc
	lda org_yh
	+adc_mx en_y
	sta org_yh
	clc
	lda org_zh
	+adc_mx en_z
	sta org_zh
.chu_rts
	rts

; Replace the lob with vy aimed at the chest. Same speed scale as GREN_SPEED.
.ch_aim
	ldx obj_i
	lda cam_yh
	sec
	sbc #1
	sbc gr_yh,x
	sta rot2			; signed dy
	lda cam_xh
	sec
	sbc gr_xh,x
	jsr .ch_abs
	sta rot0
	ldx obj_i
	lda cam_zh
	sec
	sbc gr_zh,x
	jsr .ch_abs
	cmp rot0
	bcs +
	lda rot0
+
	bne +
	lda #1
+
	sta dlo
	lda rot2
	php
	jsr .ch_abs
	sta rot0
	lda #0
	sta rot1
	jsr .ch_mul30
	lda #0
	sta rot2
	jsr div24u8
	plp
	php
	ldx obj_i
	lda rot1
	beq +
	lda #$7f
	sta rot0
+
	plp
	bpl +
	lda rot0
	eor #$ff
	clc
	adc #1
	sta rot0
+
	lda rot0
	sta gr_vyh,x
	lda #0
	sta gr_vyl,x
	rts

; rot0:rot1 = rot0 * 30. rot1 enters 0.
.ch_mul30
	lda rot0
	asl
	sta nlo
	lda #0
	rol
	sta nhi
	ldy #5
.ch_m
	asl rot0
	rol rot1
	dey
	bne .ch_m
	sec
	lda rot0
	sbc nlo
	sta rot0
	lda rot1
	sbc nhi
	sta rot1
	rts

.ch_abs
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts
