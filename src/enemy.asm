; Enemy AI — room-scoped state machine (idle/alert/approach/attack/pain/death)
!zone enemy

; Dir deltas — octants match yaw/32 (0=+Z, 2=+X, 4=-Z, 6=-X)
en_dx
	!byte 0, 1, 1, 1, 0, $ff, $ff, $ff
en_dz
	!byte 1, 1, 0, $ff, $ff, $ff, 0, 1
en_opp
	!byte 4, 5, 6, 7, 0, 1, 2, 3

; Facing half-plane for sight. 0=any, 1=need+, $ff=need-
cs_need_dx
	!byte 0, 1, 1, 1, 0, $ff, $ff, $ff
cs_need_dz
	!byte 1, 1, 0, $ff, $ff, $ff, 0, 1

enemies_update
	; tick anim accumulator → advance frames / one-shot transitions
	clc
	lda anim_acc_l
	adc dt_ms
	sta anim_acc_l
	lda anim_acc_h
	adc dt_msh
	sta anim_acc_h
.eu_anim
	lda anim_acc_h
	cmp #>ANIM_MS
	bcc .eu_think
	bne .eu_astep
	lda anim_acc_l
	cmp #<ANIM_MS
	bcc .eu_think
.eu_astep
	sec
	lda anim_acc_l
	sbc #<ANIM_MS
	sta anim_acc_l
	lda anim_acc_h
	sbc #>ANIM_MS
	sta anim_acc_h
	jsr enemy_anim_step
	jmp .eu_anim

.eu_think
	ldx #0
.eu_lp
	cpx #MAP_NENEMIES
	bcc .eu_cont
	jmp .eu_done
.eu_cont
	stx enemy_idx
	lda en_state,x
	cmp #EN_GONE
	beq .eu_skip
	cmp #EN_PAIN
	bcs .eu_do			; pain/dying always tick
	lda en_room,x
	cmp room_idx
	bne .eu_skip
.eu_do
	lda en_state,x
	tay
	lda eu_state_lo,y
	sta rot0
	lda eu_state_hi,y
	sta rot1
	jmp (rot0)
.eu_skip
	jmp eu_next

eu_state_lo
	!byte <eu_idle, <eu_alert, <eu_approach, <eu_attack
	!byte <eu_pain, <eu_dying, <eu_gone
eu_state_hi
	!byte >eu_idle, >eu_alert, >eu_approach, >eu_attack
	!byte >eu_pain, >eu_dying, >eu_gone

eu_gone
	jmp eu_next

; ------------------------------------------------------------------
eu_idle
	ldx enemy_idx
	lda gunshot_wake
	bne .eu_wake
	jsr enemy_chebyshev
	cmp #ENEMY_DETECT + 1
	bcc .eu_id_see
	jmp eu_next
.eu_id_see
	jsr enemy_facing_ok
	bcs .eu_wake
	jmp eu_next
.eu_wake
	ldx enemy_idx
	lda #EN_ALERT
	sta en_state,x
	lda #0
	sta en_frame,x
	lda en_type,x
	bne .eu_bark
	lda #SOUND_HALT
	jsr play_sound
	jmp eu_next
.eu_bark
	lda #SOUND_DOGBARK
	jsr play_sound
	jmp eu_next

; ------------------------------------------------------------------
eu_alert
	jmp eu_next

; ------------------------------------------------------------------
eu_approach
	ldx enemy_idx
	lda en_timer,x
	ora en_timer_h,x
	beq .eu_ap_step
	sec
	lda en_timer,x
	sbc dt_ms
	sta en_timer,x
	lda en_timer_h,x
	sbc dt_msh
	sta en_timer_h,x
	bcs .eu_ap_step
	lda #0
	sta en_timer,x
	sta en_timer_h,x
.eu_ap_step
	clc
	lda en_step,x
	adc dt_ms
	sta en_step,x
	lda en_step_h,x
	adc dt_msh
	sta en_step_h,x
.eu_ap_slp
	lda en_step_h,x
	bne .eu_ap_go
	lda en_step,x
	cmp #ENEMY_STEP_MS
	bcc .eu_ap_rng
.eu_ap_go
	sec
	lda en_step,x
	sbc #ENEMY_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #0
	sta en_step_h,x
	jsr enemy_try_step
	ldx enemy_idx
	jmp .eu_ap_slp
.eu_ap_rng
	jsr enemy_chebyshev
	ldy en_type,x
	cmp enemy_range,y
	beq .eu_ap_atk
	bcc .eu_ap_atk
	jmp eu_next
.eu_ap_atk
	lda en_timer,x
	ora en_timer_h,x
	bne eu_next
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr enemy_face_player
	jmp eu_next

; ------------------------------------------------------------------
eu_attack
	jmp eu_next

; ------------------------------------------------------------------
eu_pain
	jmp eu_next

; ------------------------------------------------------------------
eu_dying
	jmp eu_next

eu_next
	ldx enemy_idx
	inx
	cpx #MAP_NENEMIES
	bcs .eu_done
	jmp .eu_lp
.eu_done
	lda #0
	sta gunshot_wake
	rts

; ------------------------------------------------------------------
; Advance one anim frame for all non-gone enemies; handle one-shot ends.
enemy_anim_step
	ldx #0
.eas_lp
	cpx #MAP_NENEMIES
	bcc .eas_go
	rts
.eas_go
	stx enemy_idx
	lda en_state,x
	cmp #EN_GONE
	beq .eas_n
	cmp #EN_IDLE
	bne +
	jmp .eas_loop
+
	cmp #EN_APPROACH
	bne +
	jmp .eas_run
+
	cmp #EN_ALERT
	beq .eas_oneshot
	cmp #EN_ATTACK
	beq .eas_oneshot
	cmp #EN_PAIN
	beq .eas_oneshot
	cmp #EN_DYING
	bne .eas_n
	jmp .eas_die
.eas_n
	ldx enemy_idx
	inx
	jmp .eas_lp

.eas_loop
	ldy en_type,x
	inc en_frame,x
	lda en_frame,x
	cmp enemy_stand_len,y
	bcs +
	jmp .eas_n
+
	lda #0
	sta en_frame,x
	jmp .eas_n
.eas_run
	ldy en_type,x
	inc en_frame,x
	lda en_frame,x
	cmp enemy_run_len,y
	bcc +
	lda #0
	sta en_frame,x
+
	jmp .eas_n
.eas_oneshot
	ldy en_type,x
	inc en_frame,x
	lda en_frame,x
	pha
	lda en_state,x
	cmp #EN_ALERT
	beq .eas_alen
	cmp #EN_ATTACK
	beq .eas_atlen
	pla
	cmp enemy_pain_len,y
	bcs +
	jmp .eas_n
+
	jsr enemy_enter_approach
	jmp .eas_n
.eas_alen
	pla
	cmp enemy_alert_len,y
	bcs +
	jmp .eas_n
+
	jsr enemy_enter_approach
	jmp .eas_n
.eas_atlen
	pla
	cmp enemy_attack_len,y
	bcs +
	jmp .eas_n
+
	; 50%: shoot again if still in range, else approach
	jsr rnd8
	bmi .eas_to_ap
	ldx enemy_idx
	jsr enemy_chebyshev
	ldy en_type,x
	cmp enemy_range,y
	beq .eas_again
	bcc .eas_again
.eas_to_ap
	jsr enemy_enter_approach
	jmp .eas_n
.eas_again
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr enemy_face_player
	jmp .eas_n
.eas_die
	inc en_frame,x
	lda en_frame,x
	ldy en_type,x
	cmp enemy_death_len,y
	bcs +
	jmp .eas_n
+
	jsr finish_enemy_death
	jmp .eas_n

; ------------------------------------------------------------------
; A = Chebyshev |dx|,|dz| max vs player (cam_xh/zh). X = enemy_idx
enemy_chebyshev
	ldx enemy_idx
	lda en_x,x
	sec
	sbc cam_xh
	bcs +
	eor #$ff
	clc
	adc #1
+
	sta rot0
	lda en_z,x
	sec
	sbc cam_zh
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp rot0
	bcs +
	lda rot0
+
	rts

; C=1 player in facing half-plane (or very close)
enemy_facing_ok
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp #2
	bcc .efo_yes			; adjacent — skip facing
	lda cam_xh
	sec
	sbc en_x,x
	sta rot0				; dx toward player
	lda cam_zh
	sec
	sbc en_z,x
	sta rot1				; dz
	ldy en_dir,x
	lda cs_need_dx,y
	beq .efo_z
	bmi .efo_ndx
	lda rot0
	beq .efo_z
	bpl .efo_z
	clc
	rts
.efo_ndx
	lda rot0
	beq .efo_z
	bmi .efo_z
	clc
	rts
.efo_z
	lda cs_need_dz,y
	beq .efo_yes
	bmi .efo_ndz
	lda rot1
	beq .efo_yes
	bpl .efo_yes
	clc
	rts
.efo_ndz
	lda rot1
	beq .efo_yes
	bmi .efo_yes
	clc
	rts
.efo_yes
	sec
	rts

; ------------------------------------------------------------------
; Wolf-style dodge: pick en_dir toward player (diagonal first)
select_dodge_dir
	ldx enemy_idx
	lda en_dir,x
	tay
	lda en_opp,y
	sta ai_turn
	lda cam_xh
	sec
	sbc en_x,x
	sta rot0				; dx
	lda cam_zh
	sec
	sbc en_z,x
	sta rot1				; dz
	lda rot0
	bmi .sdd_wx
	bne .sdd_ex
.sdd_wx
	lda #6
	sta ai_dirtry
	lda #2
	sta ai_dirtry+2
	bne .sdd_y
.sdd_ex
	lda #2
	sta ai_dirtry
	lda #6
	sta ai_dirtry+2
.sdd_y
	lda rot1
	bmi .sdd_nz
	bne .sdd_sz
.sdd_nz
	; dz < 0 → toward -Z (4)
	lda #4
	sta ai_dirtry+1
	lda #0
	sta ai_dirtry+3
	bne .sdd_diag
.sdd_sz
	; dz > 0 → toward +Z (0)
	lda #0
	sta ai_dirtry+1
	lda #4
	sta ai_dirtry+3
.sdd_diag
	lda ai_dirtry
	and #4
	lsr
	sta rot2
	lda ai_dirtry+1
	lsr
	lsr
	ora rot2
	tay
	lda .sdd_diag4,y
	sta ai_dirtry+4
	; abs compare for axis swap
	lda rot0
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta rot2
	lda rot1
	bpl +
	eor #$ff
	clc
	adc #1
+
	cmp rot2
	bcc .sdd_rnd
	lda ai_dirtry
	sta rot2
	lda ai_dirtry+1
	sta ai_dirtry
	lda rot2
	sta ai_dirtry+1
	lda ai_dirtry+2
	sta rot2
	lda ai_dirtry+3
	sta ai_dirtry+2
	lda rot2
	sta ai_dirtry+3
.sdd_rnd
	jsr rnd8
	bmi .sdd_try
	lda ai_dirtry
	sta rot2
	lda ai_dirtry+1
	sta ai_dirtry
	lda rot2
	sta ai_dirtry+1
	lda ai_dirtry+2
	sta rot2
	lda ai_dirtry+3
	sta ai_dirtry+2
	lda rot2
	sta ai_dirtry+3
.sdd_try
	lda #4
	sta rot2
.sdd_lp
	ldx rot2
	lda ai_dirtry,x
	cmp ai_turn
	beq .sdd_n
	jsr enemy_probe_dir
	bcc .sdd_n
	ldx enemy_idx
	lda ai_probe
	jsr enemy_set_geom
	rts
.sdd_n
	inc rot2
	lda rot2
	cmp #5
	bne +
	lda #0
	sta rot2
+
	cmp #4
	bne .sdd_lp
	lda ai_turn
	cmp #$ff
	beq .sdd_rts
	jsr enemy_probe_dir
	bcc .sdd_rts
	ldx enemy_idx
	lda ai_probe
	jsr enemy_set_geom
.sdd_rts
	rts
.sdd_diag4
	!byte 1, 3, 7, 5

; A = geometric octant (0=+Z N .. 2=+X E). Mesh yaw = octant*32.
enemy_set_geom
	sta en_dir,x
	asl
	asl
	asl
	asl
	asl
	sta en_rot,x
	rts

; Face player: analog yaw → en_rot only (leave en_dir for dodge).
enemy_face_player
	ldx enemy_idx
	lda cam_xh
	sec
	sbc en_x,x
	sta rot0
	lda cam_zh
	sec
	sbc en_z,x
	sta rot1
	jsr atan2_yaw
	ldx enemy_idx
	sta en_rot,x
	rts

; Enter approach: 1.5s min, zero step remainder, pick dodge octant.
enemy_enter_approach
	stx enemy_idx
	lda #EN_APPROACH
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_step,x
	sta en_step_h,x
	lda #<APPROACH_MIN_MS
	sta en_timer,x
	lda #>APPROACH_MIN_MS
	sta en_timer_h,x
	jsr select_dodge_dir
	rts

; A = dir to probe. C=1 walkable; ai_probe = dir
enemy_probe_dir
	sta ai_probe
	tay
	ldx enemy_idx
	clc
	lda en_x,x
	adc en_dx,y
	sta col_x
	clc
	lda en_z,x
	adc en_dz,y
	sta col_z
	jsr enemy_pos_ok
	rts

; Try step in en_dir; repath if blocked. Also clamp.
enemy_try_step
	ldx enemy_idx
	lda en_dir,x
	jsr enemy_probe_dir
	bcs .ets_ok
	jsr select_dodge_dir
	ldx enemy_idx
	lda en_dir,x
	jsr enemy_probe_dir
	bcc .ets_rts
.ets_ok
	ldx enemy_idx
	lda col_x
	sta en_x,x
	lda col_z
	sta en_z,x
	lda en_dir,x
	jsr enemy_set_geom
	jsr enemy_clamp_room
.ets_rts
	rts

; Clamp en_x/z to room inset 1 for en_room
enemy_clamp_room
	ldx enemy_idx
	ldy en_room,x
	; x lo = room_x+1
	clc
	lda room_x,y
	adc #1
	sta rot0
	lda en_x,x
	cmp rot0
	bcs +
	lda rot0
	sta en_x,x
+
	; x hi exclusive = room_x+sx-1 → last = room_x+sx-2
	clc
	lda room_x,y
	adc room_sx,y
	sec
	sbc #1
	sta rot1				; exclusive max of inset
	lda en_x,x
	cmp rot1
	bcc +
	lda rot1
	sec
	sbc #1
	sta en_x,x
+
	clc
	lda room_z,y
	adc #1
	sta rot0
	lda en_z,x
	cmp rot0
	bcs +
	lda rot0
	sta en_z,x
+
	clc
	lda room_z,y
	adc room_sz,y
	sec
	sbc #1
	sta rot1
	lda en_z,x
	cmp rot1
	bcc +
	lda rot1
	sec
	sbc #1
	sta en_z,x
+
	rts

; col_x/col_z proposed. C=1 ok (inset + solid). Uses enemy Y via cam hack.
enemy_pos_ok
	ldx enemy_idx
	ldy en_room,x
	clc
	lda room_x,y
	adc #1
	sta rot0
	lda col_x
	cmp rot0
	bcc .epo_no
	clc
	lda room_x,y
	adc room_sx,y
	sec
	sbc #1
	sta rot0
	lda col_x
	cmp rot0
	bcs .epo_no
	clc
	lda room_z,y
	adc #1
	sta rot0
	lda col_z
	cmp rot0
	bcc .epo_no
	clc
	lda room_z,y
	adc room_sz,y
	sec
	sbc #1
	sta rot0
	lda col_z
	cmp rot0
	bcs .epo_no
	lda cam_yh
	pha
	lda en_y,x
	clc
	adc #EYE_HEIGHT
	sta cam_yh
	jsr solid_at
	pla
	sta cam_yh
	bcs .epo_no
	sec
	rts
.epo_no
	clc
	rts

; ------------------------------------------------------------------
; X = enemy. A = damage. Pain chance if survives.
damage_enemy
	sta rot2
	lda en_state,x
	cmp #EN_DYING
	bcs .de_rts
	lda en_hp,x
	sec
	sbc rot2
	sta en_hp,x
	beq .de_kill
	bcc .de_kill
	; wake idle/alert into combat after hit
	lda en_state,x
	cmp #EN_APPROACH
	bcs .de_roll
	jsr enemy_enter_approach
	ldx enemy_idx
.de_roll
	jsr rnd8
	ldy en_type,x
	cmp enemy_pain_chance,y
	bcs .de_rts
	lda #EN_PAIN
	sta en_state,x
	lda #0
	sta en_frame,x
	lda en_type,x
	bne .de_dpain
	lda #SOUND_POPAIN
	jmp play_sound
.de_dpain
	lda #SOUND_DMPAIN
	jmp play_sound
.de_kill
	jmp kill_enemy
.de_rts
	rts

; Axe: first hittable enemy in room within AXE_HIT_R. C=1 hit.
axe_try_kill
	ldx #0
.atk_lp
	cpx #MAP_NENEMIES
	bcs .atk_no
	lda en_state,x
	cmp #EN_DYING
	bcs .atk_n
	lda en_room,x
	cmp room_idx
	bne .atk_n
	lda en_x,x
	sec
	sbc cam_xh
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp #AXE_HIT_R + 1
	bcs .atk_n
	lda en_z,x
	sec
	sbc cam_zh
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp #AXE_HIT_R + 1
	bcs .atk_n
	lda en_y,x
	sta box_y
	lda #ENEMY_CULL_H
	sta box_sy
	stx obj_i
	jsr player_overlaps_y
	ldx obj_i
	bcc .atk_n
	lda #AXE_DMG
	jsr damage_enemy
	sec
	rts
.atk_n
	inx
	bne .atk_lp
.atk_no
	clc
	rts
