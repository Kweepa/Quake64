; Streamed Shambler attack. Linked at AI_LINK_BASE, relocated on load.
; Magic: straight tracer, then a 3-frame XZ-jitter bolt. Melee: smash / claws.
!cpu 6510
!to "../enemies/ai_shambl.bin", plain
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

*= AI_LINK_BASE
ai_shambler_entry
	cmp #AI_CMD_FIRE
	bne .nfire
	jmp .fire
.nfire
	cmp #AI_CMD_ATTACK_END
	bne .nend
	jmp .attack_end
.nend
	cmp #AI_CMD_APPROACH_MOVE
	bne .nmove
	jmp .approach_move
.nmove
	cmp #AI_CMD_APPROACH_ATTACK
	bne .natk
	jmp .approach_attack
.natk
	cmp #AI_CMD_APPROACH_ENTER
	bne .nent
	jmp .approach_enter
.nent
	cmp #AI_CMD_DRAW
	bne .ndraw
	jmp .draw
.ndraw
	cmp #AI_CMD_ANIM_FIRE
	bne .npain
	jmp .anim_fire
.npain
	cmp #AI_CMD_PAIN_TICK
	bne .nask
	jmp .pain_tick
.nask
	cmp #AI_CMD_PAIN_ASK
	bne .entry_rts
	jmp .pain_ask
.entry_rts
	rts

.approach_move
	ldx enemy_idx
	lda #AI_AP_MOVE
	rts

.approach_enter
	ldx enemy_idx
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	jmp select_dodge_dir

.approach_attack
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp #SHAM_MELEE_R + 1
	bcs .ranged
	jsr enemy_same_floor
	bcc .ranged
	jmp .pick_melee
.ranged
	jsr .trace
	bcc .ranged_ok
	rts
.ranged_ok
	lda #SHAM_VAR_MAGIC
	jmp enemy_enter_shambler_attack

.pick_melee
	ldx enemy_idx
	lda en_hp,x
	cmp enemy_hp_init + ENT_SHAMBLER
	beq .smash
	jsr rnd8
	cmp #154			; rnd > 153, or full HP → smash
	bcs .smash
	cmp #77				; else rnd > 76 → swingr, else swingl
	bcs .swingr
	lda #SHAM_VAR_SWINGL
	jmp enemy_enter_shambler_attack
.smash
	lda #SHAM_VAR_SMASH
	jmp enemy_enter_shambler_attack
.swingr
	lda #SHAM_VAR_SWINGR
	jmp enemy_enter_shambler_attack

.attack_end
	ldx enemy_idx
	lda #0
	sta sham_arc
	lda en_pain_i,x
	beq .to_ap			; smash returns to run
	cmp #SHAM_VAR_MAGIC
	beq .to_ap
	jsr enemy_same_floor
	bcc .to_ap
	jsr enemy_chebyshev
	cmp #SHAM_MELEE_R + 1
	bcs .to_ap
	jsr rnd8
	cmp #128			; 50% chain to the other claw
	bcs .to_ap
	ldx enemy_idx
	lda en_pain_i,x
	cmp #SHAM_VAR_SWINGR
	beq .chain_l
	lda #SHAM_VAR_SWINGR
	jmp enemy_enter_shambler_attack
.chain_l
	lda #SHAM_VAR_SWINGL
	jmp enemy_enter_shambler_attack
.to_ap
	jmp enemy_enter_approach

.fire
	ldx enemy_idx
	lda en_pain_i,x
	cmp #SHAM_VAR_MAGIC
	beq .bolt
	jsr enemy_same_floor
	bcs .fire_floor
	rts
.fire_floor
	jsr enemy_chebyshev
	cmp #SHAM_MELEE_R + 1
	bcc .fire_near
	rts
.fire_near
	lda en_pain_i,x
	bne .claw
	lda #7
	jsr .sum3
	bne .fire_hit
	rts
.fire_hit
	jsr take_damage
	jmp .splat
.claw
	lda #3
	jsr .sum3
	bne .claw_hit
	rts
.claw_hit
	jsr take_damage
.splat
	lda enemy_idx
	sta bite_splat_i
	rts

.bolt
	lda sham_arc
	bne .bolt_dmg
	lda #1
	sta sham_arc
.bolt_dmg
	jsr .trace
	bcs .bolt_miss
	lda #SHAM_BOLT_DMG
	jmp take_damage
.bolt_miss
	rts

; A = mask. A = (rnd&mask) three times. 0 is a whiff.
.sum3
	sta sham_pok
	lda #0
	sta rot0
	ldy #3
.s3
	jsr rnd8
	and sham_pok
	clc
	adc rot0
	sta rot0
	dey
	bne .s3
	lda rot0
	rts

; Chest → feet + 2. Room solids via line_solids_hit.
; C=1 blocked (end shortened). C=0 clear. sham_best = $ff when clear.
.trace
	ldx enemy_idx
	+lda_mx en_x
	sta sham_ax
	sta ln_ax
	+lda_mx en_y
	clc
	adc #SHAM_BOLT_H
	sta sham_ay
	sta ln_ay
	+lda_mx en_z
	sta sham_az
	sta ln_az
	lda cam_xh
	sta sham_bx
	sta ln_bx
	lda cam_yh
	sec
	sbc #SHAM_BOLT_DROP
	sta sham_by
	sta ln_by
	lda cam_zh
	sta sham_bz
	sta ln_bz
	lda #$ff
	sta sham_best
	+lda_mx en_room
	tay
	jsr line_solids_hit
	bcc .trace_clear
	lda ln_best
	sta sham_best
	lda col_x
	sta sham_bx
	lda col_y
	sta sham_by
	lda col_z
	sta sham_bz
	sec
	rts
.trace_clear
	clc
	rts

.draw
	lda en_state,x
	cmp #EN_ATTACK
	bne .draw_rts
	lda en_pain_i,x
	cmp #SHAM_VAR_MAGIC
	bne .draw_rts
	lda en_frame,x
	cmp #SHAM_BOLT_HI
	bcc .draw_go
.draw_rts
	rts
.draw_go
	stx enemy_idx
	jsr .trace
	jsr load_view_trig
	ldx enemy_idx
	lda en_frame,x
	cmp #SHAM_BOLT_LO
	bcs .jagged
	lda sham_ax
	sta sham_px
	lda sham_ay
	sta sham_py
	lda sham_az
	sta sham_pz
	lda #0
	sta sham_i
	jsr .project
	bcs .draw_a
	rts
.draw_a
	sta x0
	sty y0
	lda sham_bx
	sta sham_px
	lda sham_by
	sta sham_py
	lda sham_bz
	sta sham_pz
	lda #10
	sta sham_i
	jsr .project
	bcs .draw_b
	rts
.draw_b
	sta x1
	sty y1
	jmp draw_line

.jagged
	lda #0
	sta sham_i
	sta sham_pok
.jlp
	jsr .point
	jsr .project
	bcc .jmiss
	ldx sham_pok
	beq .jarm
	sta x1
	sty y1
	sta sham_psx
	sty sham_psy
	jsr draw_line
	lda sham_psx
	sta x0
	lda sham_psy
	sta y0
	jmp .jnext
.jarm
	sta x0
	sty y0
	lda #1
	sta sham_pok
	jmp .jnext
.jmiss
	lda #0
	sta sham_pok
.jnext
	inc sham_i
	lda sham_i
	cmp #11
	bcc .jlp
	rts

; sham_i → world point. Ends stay on the segment; interior X/Z ±2.
.point
	ldy sham_i
	lda sham_bx
	sec
	sbc sham_ax
	jsr .scale
	clc
	adc sham_ax
	sta sham_px
	ldy sham_i
	lda sham_by
	sec
	sbc sham_ay
	jsr .scale
	clc
	adc sham_ay
	sta sham_py
	ldy sham_i
	lda sham_bz
	sec
	sbc sham_az
	jsr .scale
	clc
	adc sham_az
	sta sham_pz
	lda sham_i
	beq .pt_rts
	cmp #10
	beq .pt_rts
	jsr rnd8
	and #3
	sec
	sbc #2
	clc
	adc sham_px
	sta sham_px
	jsr rnd8
	and #3
	sec
	sbc #2
	clc
	adc sham_pz
	sta sham_pz
.pt_rts
	rts

; Y = 0..10, A = signed delta. A = delta * Y / 10. Clobbers rot0..2, Y, sham_psx.
.scale
	cpy #0
	beq .sc_z
	sta sham_psx
	bpl .sc_abs
	eor #$ff
	clc
	adc #1
.sc_abs
	sta rot2
	lda #0
	sta rot0
	sta rot1
.sc_mul
	clc
	lda rot0
	adc rot2
	sta rot0
	lda rot1
	adc #0
	sta rot1
	dey
	bne .sc_mul
	lda #0
	sta rot2
.sc_div
	lda rot1
	bne .sc_sub
	lda rot0
	cmp #10
	bcc .sc_q
.sc_sub
	sec
	lda rot0
	sbc #10
	sta rot0
	lda rot1
	sbc #0
	sta rot1
	inc rot2
	jmp .sc_div
.sc_q
	lda sham_psx
	bpl .sc_pos
	lda rot2
	eor #$ff
	clc
	adc #1
	rts
.sc_pos
	lda rot2
	rts
.sc_z
	lda #0
	rts

.project
	lda #0
	sta org_xl
	sta org_yl
	sta org_zl
	lda sham_px
	sta org_xh
	lda sham_py
	sta org_yh
	lda sham_pz
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	jsr project_cam0_screen
	bcs .pr_ok
	; Player end sits on the camera, so Z fails. Push it to the near plane
	; and keep the view-space X/Y (feet + 2 is below the eye). Snapping to
	; the view centre drew a second line through the crosshair on top of the bolt.
	lda sham_i
	cmp #10
	bne .pr_no
	lda sham_best
	cmp #$ff
	bne .pr_no
	lda #0
	sta CAM_Z
	lda #2
	sta CAM_ZH
	jsr project_cam0_screen
	bcs .pr_ok
.pr_no
	clc
	rts
.pr_ok
	rts

; Old frame in rot2, new frame in en_frame. A = 0: this bank owns the decision.
.anim_fire
	ldx enemy_idx
	lda en_pain_i,x
	cmp #SHAM_VAR_MAGIC
	bne .af_melee
	lda en_frame,x
	cmp #SHAM_BOLT_LO
	bcc .af_off
	cmp #SHAM_BOLT_HI
	bcs .af_off
	cmp rot2
	beq .af_own
	bcc .af_own
	jsr .fire
	lda #0
	rts
.af_off
	lda #0
	sta sham_arc
.af_own
	lda #0
	rts
.af_melee
	lda en_pain_i,x
	bne .af_claw
	lda #SHAM_SMASH_FIRE
	bne .af_one
.af_claw
	lda #SHAM_CLAW_FIRE
.af_one
	jsr .crossed
	bcc .af_own
	jsr .fire
	lda #0
	rts

; A = fire frame. C=1 if rot2 < frame <= en_frame.
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

.pain_tick
	lda sham_pain_i
	cmp #$ff
	beq .lock_rts
	sec
	lda sham_pain_l
	sbc dt_ms
	sta sham_pain_l
	lda sham_pain_h
	sbc dt_msh
	sta sham_pain_h
	bcs .lock_rts
	lda #$ff
	sta sham_pain_i
	lda #0
	sta sham_pain_l
	sta sham_pain_h
.lock_rts
	rts

; A = 0 enter pain (lock stored). A = 1 no flinch.
.pain_ask
	ldx enemy_idx
	cpx sham_pain_i
	bne .pa_roll
	lda sham_pain_l
	ora sham_pain_h
	bne .pa_no
.pa_roll
	lda hit_dmg
	cmp #SHAM_PAIN_ALWAYS
	bcs .pa_yes
	sta rot0
	asl
	clc
	adc rot0
	sta rot0
	jsr rnd8
	cmp rot0
	bcs .pa_no
.pa_yes
	lda #<SHAM_PAIN_MS
	sta sham_pain_l
	lda #>SHAM_PAIN_MS
	sta sham_pain_h
	stx sham_pain_i
	lda #0
	sta sham_arc
	rts
.pa_no
	lda #1
	rts
