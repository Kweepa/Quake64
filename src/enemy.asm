; Enemy AI — room-scoped state machine (idle/patrol/alert/approach/attack/pain/death)
!zone enemy

; Dir deltas — octants match yaw/32 (0=+Z, 2=+X, 4=-Z, 6=-X)
en_dx
	!byte 0, 1, 1, 1, 0, $ff, $ff, $ff
en_dz
	!byte 1, 1, 0, $ff, $ff, $ff, 0, 1
en_opp
	!byte 4, 5, 6, 7, 0, 1, 2, 3

; This type's CUE_SHOOT id, copied from the cue block while scanning clip events.
cue_shoot_id	!byte $ff

; Facing half-plane for sight. 0=any, 1=need+, $ff=need-
cs_need_dx = en_dx
cs_need_dz = en_dz

enemies_update
	jsr sham_pain_tick
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
	cpx	map_nenemies
	bcc .eu_cont
	jmp .eu_done
.eu_cont
	stx enemy_idx
	lda en_state,x
	cmp #EN_GONE
	beq .eu_skip
	+lda_mx en_room
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
	!byte <eu_idle, <eu_patrol, <eu_alert, <eu_approach, <eu_attack
	!byte <eu_pain, <eu_dying, <eu_dead, <eu_gone
eu_state_hi
	!byte >eu_idle, >eu_patrol, >eu_alert, >eu_approach, >eu_attack
	!byte >eu_pain, >eu_dying, >eu_dead, >eu_gone

eu_gone
	jmp eu_next

; ------------------------------------------------------------------
eu_idle
	ldx enemy_idx
	+ldy_mx en_type
	lda AI_ENTRY_HI,y
	beq .eu_id_own
	lda #AI_CMD_IDLE
	jsr ai_invoke
	cmp #AI_CMD_IDLE		; entry left A alone → not its idle
	beq .eu_id_own
	jmp eu_next
.eu_id_own
	ldx enemy_idx
	lda en_timer,x
	ora en_timer_h,x
	beq .eu_id_sight
	sec
	lda en_timer,x
	sbc dt_ms
	sta en_timer,x
	lda en_timer_h,x
	sbc dt_msh
	sta en_timer_h,x
	bcs .eu_id_held
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	jmp .eu_id_retry
.eu_id_held
	lda gunshot_wake
	bne .eu_id_retry
	jmp eu_next
.eu_id_retry
	ldx enemy_idx
	lda #0
	sta en_timer,x
	sta en_timer_h,x
	lda gunshot_wake
	bne .eu_id_retry_see
	lda pu_kind
	cmp #BP_RING
	bne .eu_id_retry_see
	jmp enemy_idle_try_patrol
.eu_id_retry_see
	jsr enemy_in_wake
	bcc .eu_id_goap
	jmp enemy_idle_try_patrol
.eu_id_goap
	jsr enemy_enter_approach
	jmp eu_next
.eu_id_sight
	lda gunshot_wake
	bne .eu_wake
	lda pu_kind
	cmp #BP_RING
	bne .eu_id_sight2
	jmp enemy_idle_try_patrol
.eu_id_sight2
	jsr enemy_in_wake
	bcc .eu_id_see
	jmp enemy_idle_try_patrol
.eu_id_see
	jsr enemy_facing_ok
	bcs .eu_wake
	jmp enemy_idle_try_patrol
.eu_wake
	jsr enemy_enter_alert
	jmp eu_next

; ------------------------------------------------------------------
; Walk a chosen cardinal until en_pat_n hits 0, then idle 1–2s.
eu_patrol
	ldx enemy_idx
	lda gunshot_wake
	bne .eu_pt_wake
	lda pu_kind
	cmp #BP_RING
	beq .eu_pt_acc
	jsr enemy_in_wake
	bcc .eu_pt_see
	jmp .eu_pt_acc
.eu_pt_see
	jsr enemy_facing_ok
	bcc .eu_pt_acc
.eu_pt_wake
	jsr enemy_enter_alert
	jmp eu_next
.eu_pt_acc
	ldx enemy_idx
	clc
	lda en_step,x
	adc dt_ms
	sta en_step,x
	lda en_step_h,x
	adc dt_msh
	sta en_step_h,x
.eu_pt_slp
	lda en_step_h,x
	cmp #>PATROL_STEP_MS
	bcc .eu_pt_done
	bne .eu_pt_go
	lda en_step,x
	cmp #<PATROL_STEP_MS
	bcc .eu_pt_done
.eu_pt_go
	sec
	lda en_step,x
	sbc #<PATROL_STEP_MS
	sta en_step,x
	lda en_step_h,x
	sbc #>PATROL_STEP_MS
	sta en_step_h,x
	jsr enemy_patrol_step
	bcc .eu_pt_stuck
	ldx enemy_idx
	dec en_pat_n,x
	beq .eu_pt_arrive
	jmp .eu_pt_slp
.eu_pt_stuck
.eu_pt_arrive
	jsr enemy_patrol_pause
.eu_pt_done
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
	+ldy_mx en_type
	lda #AI_CMD_APPROACH_MOVE
	jsr ai_invoke
	cmp #AI_AP_STAND
	beq .eu_ap_rng
	cmp #AI_AP_NEXT
	bne .eu_ap_acc
	jmp eu_next
.eu_ap_acc
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
	jsr enemy_cmp_range
	beq .eu_ap_atk
	bcc .eu_ap_atk
	jmp eu_next
.eu_ap_atk
	lda en_timer,x
	ora en_timer_h,x
	beq .eu_ap_ready
	jmp eu_next
.eu_ap_ready
	+ldy_mx en_type
	lda #AI_CMD_APPROACH_ATTACK
	jsr ai_invoke
	jmp eu_next

; ------------------------------------------------------------------
eu_attack
	ldx enemy_idx
	+ldy_mx en_type
	lda #AI_CMD_ATTACK_TICK
	jsr ai_invoke
	jmp eu_next

; ------------------------------------------------------------------
eu_pain
	jmp eu_next

; ------------------------------------------------------------------
eu_dying
	jmp eu_next

; ------------------------------------------------------------------
; Last death frame: countdown hold, then EN_GONE + drop.
eu_dead
	ldx enemy_idx
	lda en_timer,x
	ora en_timer_h,x
	beq .eu_dead_done
	sec
	lda en_timer,x
	sbc dt_ms
	sta en_timer,x
	lda en_timer_h,x
	sbc dt_msh
	sta en_timer_h,x
	bcs eu_next
	lda #0
	sta en_timer,x
	sta en_timer_h,x
.eu_dead_done
	jsr finish_enemy_death
	jmp eu_next

eu_next
	ldx enemy_idx
	inx
	cpx	map_nenemies
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
	cpx	map_nenemies
	bcc .eas_go
	rts
.eas_go
	stx enemy_idx
	lda #0
	sta en_sfx_armed
	lda en_state,x
	cmp #EN_GONE
	beq .eas_nx
	cmp #EN_DEAD
	beq .eas_nx
	+lda_mx en_room
	cmp room_idx
	bne .eas_nx
	+lda_mx en_type
	cmp #ENT_CHTHON
	bne .eas_hold
	lda ch_anim_phase
	eor #1
	sta ch_anim_phase
	bne .eas_nx			; skip frame, fire, clip end, and clip sfx
	beq .eas_step
.eas_hold
	cmp #ENT_SHAMBLER
	bne .eas_step
	lda en_state,x
	cmp #EN_ALERT
	bne .eas_step
	lda sham_alert_ph
	eor #1
	sta sham_alert_ph
	bne .eas_nx			; hold this smash frame another ANIM_MS
.eas_step
	lda en_frame,x
	sta en_sfx_old
	lda #1
	sta en_sfx_armed
	lda en_state,x
	cmp #EN_IDLE
	bne +
	jmp .eas_loop
+
	cmp #EN_PATROL
	beq .eas_walk_go
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
.eas_walk_go
	jmp .eas_walk
.eas_n
	lda en_sfx_armed
	beq .eas_nx
	jsr enemy_play_clip_sfx
.eas_nx
	ldx enemy_idx
	inx
	jmp .eas_lp

.eas_loop
	jsr ldy_slot
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
	jsr ldy_slot
	inc en_frame,x
	lda en_frame,x
	cmp enemy_run_len,y
	bcc +
	lda #0
	sta en_frame,x
+
	jmp .eas_n
.eas_walk
	jsr ldy_slot
	inc en_frame,x
	lda en_frame,x
	cmp enemy_walk_len,y
	bcc +
	lda #0
	sta en_frame,x
+
	jmp .eas_n
.eas_oneshot
	+ldy_mx en_type
	lda en_frame,x
	sta rot2				; old local frame (detect fire-frame skip)
	inc en_frame,x
	lda en_frame,x
	pha
	lda en_state,x
	cmp #EN_ALERT
	beq .eas_alen
	cmp #EN_ATTACK
	beq .eas_atlen
	pla
	jsr pain_var_off
	cmp enemy_pain_len,y
	bcs +
	jmp .eas_n
+
	+lda_mx en_type
	cmp #ENT_CHTHON
	bne .eas_pain_leave
	lda ch_shock
	beq .eas_pain_leave
	lda #0
	sta en_frame,x
	jmp .eas_n
.eas_pain_leave
	jsr enemy_enter_approach
	jmp .eas_n
.eas_alen
	pla
	ldx enemy_idx
	jsr ldy_slot
	cmp enemy_alert_len,y
	bcs +
	jmp .eas_n
+
	jsr enemy_enter_approach
	jmp .eas_n
.eas_atlen
	; Latch hit if we landed on / skipped past fire frame: old < fire <= new
	cpy #ENT_SHAMBLER
	bne .eas_ff_ogre
	lda en_pain_i,x
	cmp #SHAM_VAR_MAGIC
	bne .eas_sham_melee
	pla
	pha
	cmp #SHAM_BOLT_LO
	bcc .eas_sham_off
	cmp #SHAM_BOLT_HI
	bcs .eas_sham_off
	cmp rot2
	beq .eas_sham_skip
	bcs .eas_sham_fire
.eas_sham_skip
	jmp .eas_atlen_go
.eas_sham_fire
	jmp .eas_ff_go
.eas_sham_off
	lda #0
	sta sham_arc
	jmp .eas_atlen_go
.eas_sham_melee
	lda en_pain_i,x
	bne .eas_sham_claw
	lda #SHAM_SMASH_FIRE
	bne .eas_ff
.eas_sham_claw
	lda #SHAM_CLAW_FIRE
	bne .eas_ff
.eas_ff_ogre
	cpy #ENT_OGRE
	bne .eas_ff_k
	lda en_pain_i,x
	bne .eas_ff_tbl			; shoot uses table
	lda #OGRE_SWING_FIRE
	bne .eas_ff
.eas_ff_k
	cpy #ENT_KNIGHT
	bne .eas_ff_dem
	lda en_pain_i,x
	bne .eas_ff_katkb
	lda #KNIGHT_RUNATK_FIRE
	bne .eas_ff
.eas_ff_katkb
	lda #KNIGHT_ATKB_FIRE
	bne .eas_ff
.eas_ff_dem
	cpy #ENT_DEMON
	bne .eas_ff_tbl
	lda en_pain_i,x
	bne .eas_ff_dclaw
	lda #DEMON_LEAP_FIRE
	bne .eas_ff
.eas_ff_dclaw
	lda #DEMON_MELEE_FIRE
	bne .eas_ff
.eas_ff_tbl
	tya
	pha
	jsr ldy_slot
	lda enemy_fire_frame,y
	sta rot1
	pla
	tay
	lda rot1
	cpy #ENT_CHTHON
	bne .eas_ff
	cmp rot2
	beq .eas_ch_ff2			; already were on frame 5
	bcc .eas_ch_ff2			; frame 5 already past
	sta rot1
	pla
	pha
	cmp rot1
	bcc .eas_ch_ff2			; not on frame 5 yet
	bcs .eas_ff_go
.eas_ch_ff2
	lda #CHTHON_FIRE2
.eas_ff
	bmi .eas_atlen_go			; $ff = none
	cmp rot2
	beq .eas_atlen_go			; already were on fire frame
	bcc .eas_atlen_go			; fire < old → already past
	sta rot1
	pla
	pha
	cmp rot1
	bcc .eas_atlen_go			; new < fire → not yet
.eas_ff_go
	+ldy_mx en_type
	lda #AI_CMD_FIRE
	jsr ai_invoke
	jmp .eas_atk_rest
.eas_atk_rest
	ldx enemy_idx
	+ldy_mx en_type
	jmp .eas_atlen_go
.eas_atlen_go
	pla
	jsr pain_var_off
	cmp enemy_attack_len,y
	bcs +
	jmp .eas_n
+
	ldx enemy_idx
	+ldy_mx en_type
	lda #AI_CMD_ATTACK_END
	jsr ai_invoke
	jmp .eas_n
.eas_die
	inc en_frame,x
	+ldy_mx en_type
	lda AI_ENTRY_HI,y
	beq .eas_die_nsc
	lda #AI_CMD_DYING_STEP
	jsr ai_invoke
	ldx enemy_idx
	+ldy_mx en_type
.eas_die_nsc
	lda en_frame,x
	jsr pain_var_off
	cmp enemy_death_len,y
	bcs +
	jmp .eas_n
+
	; past end → hold last frame in EN_DEAD
	lda enemy_death_len,y
	sec
	sbc #1
	sta en_frame,x
	lda #EN_DEAD
	sta en_state,x
	lda #<DEATH_HOLD_MS
	sta en_timer,x
	lda #>DEATH_HOLD_MS
	sta en_timer_h,x
	jmp .eas_n

; ------------------------------------------------------------------
; C=0 if Chebyshev is inside this enemy's wake distance.
; Shambler acquires at enemy_range (the bolt), not ENEMY_DETECT.
enemy_in_wake
	jsr enemy_chebyshev
	ldx enemy_idx
	+ldy_mx en_type
	cpy #ENT_SHAMBLER
	bne .eiw_det
	jsr enemy_cmp_range
	beq .eiw_yes
	bcc .eiw_yes
	sec
	rts
.eiw_yes
	clc
	rts
.eiw_det
	cmp #ENEMY_DETECT + 1
	rts

; A = Chebyshev |dx|,|dz| max vs player (cam_xh/zh). X = enemy_idx
enemy_chebyshev
	ldx enemy_idx
	+lda_mx en_x
	sec
	sbc cam_xh
	bcs +
	eor #$ff
	clc
	adc #1
+
	sta rot0
	+lda_mx en_z
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

; A = distance, X = enemy. Flags as cmp distance, enemy_range[slot].
; A is the distance again. X preserved. Clobbers meta_scratch, not rot*.
enemy_cmp_range
	sta meta_scratch
	jsr ldy_slot
	lda meta_scratch
	cmp enemy_range,y
	rts

; C=1 player in facing half-plane (or very close)
enemy_facing_ok
	ldx enemy_idx
	jsr enemy_chebyshev
	cmp #2
	bcc .efo_yes			; adjacent — skip facing
	lda cam_xh
	sec
	+sbc_mx en_x
	sta rot0				; dx toward player
	lda cam_zh
	sec
	+sbc_mx en_z
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
; Rottweiler: nodir turnaround (may 180°); grunt: forbid reverse while walking
select_dodge_dir
	ldx enemy_idx
	jsr enemy_get_class
	bne .sdd_nodir
	lda en_dir,x
	tay
	lda en_opp,y
	sta ai_turn
	jmp .sdd_dlt
.sdd_nodir
	lda #$ff
	sta ai_turn
.sdd_dlt
	lda cam_xh
	sec
	+sbc_mx en_x
	sta dodge_dx
	lda cam_zh
	sec
	+sbc_mx en_z
	sta dodge_dz
	lda dodge_dx
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
	lda dodge_dz
	bmi .sdd_nz
	bne .sdd_sz
.sdd_nz
	; dz < 0 → toward -Z (4); A must stay nonzero for bne
	lda #0
	sta ai_dirtry+3
	lda #4
	sta ai_dirtry+1
	bne .sdd_diag
.sdd_sz
	; dz > 0 → toward +Z (0)
	lda #0
	sta ai_dirtry+1
	lda #4
	sta ai_dirtry+3
.sdd_diag
	jsr .sdd_setdiag
	; abs compare for axis swap. Signs are already in ai_dirtry.
	lda dodge_dx
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta dodge_dx
	lda dodge_dz
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta dodge_dz
	cmp dodge_dx
	bcc .sdd_ord			; |dz| < |dx| — X already major
	lda ai_dirtry
	pha
	lda ai_dirtry+1
	sta ai_dirtry
	pla
	sta ai_dirtry+1
	lda ai_dirtry+2
	pha
	lda ai_dirtry+3
	sta ai_dirtry+2
	pla
	sta ai_dirtry+3
.sdd_ord
	; Grunt too close: prefer away (swap toward↔away, rebuild diag)
	ldx enemy_idx
	jsr enemy_get_class
	bne .sdd_zig
	cpy #ENT_OGRE
	beq .sdd_zig			; ogre closes, doesn't back off
	cpy #ENT_SCRAG
	beq .sdd_zig			; scrag closes, doesn't back off
	cpy #ENT_KNIGHT
	beq .sdd_zig			; knight closes, doesn't back off
	cpy #ENT_DEMON
	beq .sdd_zig			; demon closes, doesn't back off
	jsr enemy_chebyshev
	cmp #GRUNT_BACKOFF + 1
	bcs .sdd_zig
	lda ai_dirtry
	pha
	lda ai_dirtry+2
	sta ai_dirtry
	pla
	sta ai_dirtry+2
	lda ai_dirtry+1
	pha
	lda ai_dirtry+3
	sta ai_dirtry+1
	pla
	sta ai_dirtry+3
	jsr .sdd_setdiag
.sdd_zig
	; diagonal-first + random toward/away shuffle (zigzag)
	jsr rnd8
	bmi .sdd_try
	lda ai_dirtry
	pha
	lda ai_dirtry+1
	sta ai_dirtry
	pla
	sta ai_dirtry+1
	lda ai_dirtry+2
	pha
	lda ai_dirtry+3
	sta ai_dirtry+2
	pla
	sta ai_dirtry+3
.sdd_try
	lda #4				; diagonal first
	sta dodge_i
.sdd_lp
	ldx dodge_i
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
	inc dodge_i
	lda dodge_i
	cmp #5
	bne +
	lda #0
	sta dodge_i
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

; ai_dirtry+4 from the toward X/Z pair. Clobbers X.
.sdd_setdiag
	lda ai_dirtry
	and #4
	lsr
	pha
	lda ai_dirtry+1
	lsr
	lsr
	tsx
	ora $0101,x
	tay
	pla
	lda .sdd_diag4,y
	sta ai_dirtry+4
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
	+sta_mx en_rot
	rts

; Face player: analog yaw → en_rot only (leave en_dir for dodge).
enemy_face_player
	ldx enemy_idx
	lda cam_xh
	sec
	+sbc_mx en_x
	sta rot0
	lda cam_zh
	sec
	+sbc_mx en_z
	sta rot1
	jsr atan2_yaw
	ldx enemy_idx
	+sta_mx en_rot
	rts

; Enter alert one-shot (Halt / bark).
enemy_enter_alert
	ldx enemy_idx
	lda #EN_ALERT
	sta en_state,x
	lda #0
	sta en_frame,x
	sta sham_alert_ph
	lda #DBG_ALERT
	jsr dbg_probe
	lda #CUE_SIGHT
	; fall through

; A = CUE_* of enemy_idx's type. Plays it unless the type has none ($FF).
; The cue block heads the type's event table on the pose heap.
; Returns X = enemy_idx. Clobbers A, Y, src_ptr.
enemy_play_cue
	pha
	ldx enemy_idx
	+ldy_mx en_type
	lda enemy_sfx_evt_hi,y
	beq .epq_unbound
	sta src_ptr+1
	lda enemy_sfx_evt_lo,y
	sta src_ptr
	pla
	tay
	lda (src_ptr),y
	cmp #CUE_NONE
	beq .epq_rts
	jsr play_sound
.epq_rts
	ldx enemy_idx
	rts
.epq_unbound
	pla
	rts

; Fire clip events at this logical frame (enter).
enemy_play_clip_sfx_enter
	ldx enemy_idx
	lda #$ff
	sta en_sfx_old
	; fall through

; Events are {logical_frame, id} on the pose heap. Latch old_g < ev <= new_g
; on a forward step; enter (old=$FF) fires ev == new_g. Wrap does not fire.
enemy_play_clip_sfx
	ldx enemy_idx
	+ldy_mx en_type
	lda enemy_sfx_evt_hi,y
	bne +
	rts
+
	sta src_ptr+1
	lda enemy_sfx_evt_lo,y
	sta src_ptr
	ldy #CUE_SHOOT
	lda (src_ptr),y
	sta cue_shoot_id
	jsr enemy_logical_frame
	sty en_sfx_new
	lda en_sfx_old
	cmp #$ff
	beq .epc_scan
	ldx enemy_idx
	cmp en_frame,x
	beq .epc_hold
	bcs .epc_hold
	lda en_frame,x
	sec
	sbc en_sfx_old
	sta en_sfx_old
	lda en_sfx_new
	sec
	sbc en_sfx_old
	sta en_sfx_old
	jmp .epc_scan
.epc_hold
	lda en_sfx_new
	sta en_sfx_old
.epc_scan
	ldy #CUE_N			; event count follows the cue block
	lda (src_ptr),y
	beq .epc_rts
	sta en_sfx_n
	clc
	lda src_ptr
	adc #CUE_N + 1
	sta src_ptr
	bcc .epc_lp
	inc src_ptr+1
.epc_lp
	ldy #0
	lda (src_ptr),y
	ldx en_sfx_old
	cpx #$ff
	bne .epc_step
	cmp en_sfx_new
	bne .epc_skip
	beq .epc_play
.epc_step
	cmp en_sfx_old
	beq .epc_skip
	bcc .epc_skip
	cmp en_sfx_new
	beq .epc_play
	bcs .epc_skip
.epc_play
	iny
	lda (src_ptr),y
	pha
	cmp cue_shoot_id
	bne .epc_noshoot
	cmp #CUE_NONE
	beq .epc_noshoot
	jsr enemy_shoot_cue
.epc_noshoot
	pla
	jsr play_sound
.epc_skip
	clc
	lda src_ptr
	adc #2
	sta src_ptr
	bcc +
	inc src_ptr+1
+
	dec en_sfx_n
	bne .epc_lp
.epc_rts
	ldx enemy_idx
	rts

; A shoot cue just matched. Fire frame $ff means this cue is the shot
; (grunt): AI_CMD_FIRE. A real fire frame stays on the latch. Preserves
; src_ptr for the event scan. Zombie is $ff but has no shoot cue.
enemy_shoot_cue
	ldx enemy_idx
	lda en_state,x
	cmp #EN_ATTACK
	bne .esc_rts
	jsr ldy_slot
	lda enemy_fire_frame,y
	cmp #$ff
	bne .esc_rts
	+ldy_mx en_type
	lda AI_ENTRY_HI,y
	beq .esc_rts
	lda src_ptr
	pha
	lda src_ptr+1
	pha
	lda #AI_CMD_FIRE
	jsr ai_invoke
	pla
	sta src_ptr+1
	pla
	sta src_ptr
	ldx enemy_idx
.esc_rts
	rts

; A = attack variant (0=swing, 1=shoot). Face player; saw rev on swing.
enemy_enter_ogre_attack
	ldx enemy_idx
	sta en_pain_i,x
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr enemy_play_clip_sfx_enter
	ldx enemy_idx
	jmp enemy_face_player

; A = smash / swingr / swingl / magic. Face player.
enemy_enter_shambler_attack
	ldx enemy_idx
	sta en_pain_i,x
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	sta sham_arc
	jsr enemy_play_clip_sfx_enter
	ldx enemy_idx
	jmp enemy_face_player

; A = attack variant (0=leap, 1=claw). MDL order. Zero step so the leap doesn't inherit chase cadence.
enemy_enter_demon_attack
	ldx enemy_idx
	sta en_pain_i,x
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_step,x
	sta en_step_h,x
	jsr enemy_play_clip_sfx_enter
	ldx enemy_idx
	jmp enemy_face_player

; A = attack variant (0=runattack, 1=attackb). Zero step so lunge doesn't inherit chase cadence.
enemy_enter_knight_attack
	ldx enemy_idx
	sta en_pain_i,x
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_step,x
	sta en_step_h,x
	jsr enemy_play_clip_sfx_enter
	ldx enemy_idx
	jmp enemy_face_player

; Generic Grunt-class attack entry. Streamed types call this after policy checks.
enemy_enter_attack
	ldx enemy_idx
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr pick_attack_var
	jmp enemy_face_player

; Enter approach. The type's AI owns the timer and dodge.
enemy_enter_approach
	stx enemy_idx
	lda #EN_APPROACH
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_step,x
	sta en_step_h,x
	+ldy_mx en_type
	lda #AI_CMD_APPROACH_ENTER
	jmp ai_invoke

; C=1 |floor_y − en_y| ≤ FALL_LEDGE (same floor piece)
enemy_same_floor
	ldx enemy_idx
	lda floor_y
	+cmp_mx en_y
	bcs .esf_pl
	+lda_mx en_y
	sec
	sbc floor_y
	jmp .esf_cmp
.esf_pl
	sec
	+sbc_mx en_y
.esf_cmp
	cmp #FALL_LEDGE + 1
	bcc .esf_yes
	clc
	rts
.esf_yes
	sec
	rts

; A = damage — skill scale, then subtract from player_hp (and armour if any);
; hurt/death SFX; red border flash.
; difficulty 0 = x1/2 (min 1), 1 = x1, 2 = x3/2 (cap 255). Before pent/armour.
take_damage
	sta rot0
	lda player_hp
	beq .td_rts
	lda difficulty
	beq .td_half
	cmp #2
	bne .td_live
	lda rot0
	lsr
	clc
	adc rot0
	bcc +
	lda #$ff
+
	sta rot0
	jmp .td_live
.td_half
	lda rot0
	lsr
	bne +
	lda #1
+
	sta rot0
.td_live
	lda pu_kind
	cmp #BP_PENT
	beq .td_flash
	lda player_armour
	beq .td_hp
	lda rot0
	lsr
	sta rot0
	lda player_armour
	sec
	sbc rot0
	bcs +
	lda #0
+
	sta player_armour
.td_hp
	lda player_hp
	sec
	sbc rot0
	bcs +
	lda #0
+
	sta player_hp
.td_flash
	lda #COL_HURT
	sta vic_border
	lda #<HURT_FLASH_MS
	sta hurt_flash_l
	lda #>HURT_FLASH_MS
	sta hurt_flash_h
	jsr hud_ammo
	lda player_hp
	beq .td_death
	lda #SOUND_PLAYER_PAIN1
	jmp play_sound
.td_death
	lda #SOUND_PLAYER_DEATH1
	jsr play_sound
	jmp death_restart
.td_rts
	rts

; Tick red border; IRQ publishes vic_border.
update_hurt_flash
	lda hurt_flash_l
	ora hurt_flash_h
	beq .uhf_rts
	sec
	lda hurt_flash_l
	sbc dt_ms
	sta hurt_flash_l
	lda hurt_flash_h
	sbc dt_msh
	sta hurt_flash_h
	bcs .uhf_rts
	lda #0
	sta hurt_flash_l
	sta hurt_flash_h
	lda #COL_BORDER
	sta vic_border
.uhf_rts
	rts

; Exclusive powerup: one kind, one 30s timer. Underflow clears HUD icon.
update_powerup
	lda pu_kind
	beq .up_rts
	sec
	lda pu_ms_l
	sbc dt_ms
	sta pu_ms_l
	lda pu_ms_h
	sbc dt_msh
	sta pu_ms_h
	bcs .up_rts
	lda #0
	sta pu_kind
	sta pu_ms_l
	sta pu_ms_h
	jmp hud_powerup
.up_rts
	rts

; A = dir to probe. C=1 walkable; ai_probe = dir
enemy_probe_dir
	sta ai_probe
	tay
	ldx enemy_idx
	clc
	+lda_mx en_x
	adc en_dx,y
	sta col_x
	clc
	+lda_mx en_z
	adc en_dz,y
	sta col_z
	jsr enemy_pos_ok
	rts

; Try step in en_dir; repath if blocked. Also clamp.
; Scrag: keep hover Y (do not floor-snap).
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
	+sta_mx en_x
	lda col_z
	+sta_mx en_z
	+ldy_mx en_type
	cpy #ENT_SCRAG
	beq .ets_geom
	lda proc_tmp2
	+sta_mx en_y
.ets_geom
	lda en_dir,x
	jsr enemy_set_geom
	jsr enemy_clamp_room
.ets_rts
	rts

; One cell along current en_dir. C=1 moved.
enemy_patrol_step
	ldx enemy_idx
	lda en_dir,x
	jsr enemy_probe_dir
	bcc .eps_no
	ldx enemy_idx
	lda col_x
	+sta_mx en_x
	lda col_z
	+sta_mx en_z
	+ldy_mx en_type
	cpy #ENT_SCRAG
	beq .eps_geom
	lda proc_tmp2
	+sta_mx en_y
.eps_geom
	lda en_dir,x
	jsr enemy_set_geom
	jsr enemy_clamp_room
	sec
	rts
.eps_no
	clc
	rts

; Idle 1–2s then pick another point (PATROL_WAIT_MS + rnd*4).
enemy_patrol_pause
	ldx enemy_idx
	lda #EN_IDLE
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_pat_n,x
	sta en_step,x
	sta en_step_h,x
	jsr rnd8
	sta rot0
	lda #0
	sta rot1
	asl rot0
	rol rot1
	asl rot0
	rol rot1				; 0..1020
	ldx enemy_idx
	clc
	lda rot0
	adc #<PATROL_WAIT_MS
	sta en_timer,x
	lda rot1
	adc #>PATROL_WAIT_MS
	sta en_timer_h,x
	rts

; If this enemy patrols, try one cardinal this frame.
enemy_idle_try_patrol
	ldx enemy_idx
	+lda_mx en_patrol
	beq .eitp_no
	jsr enemy_patrol_pick
.eitp_no
	jmp eu_next

; First pick: spawn octant (en_dir). Later: random cardinal.
; C ignored — enter EN_PATROL if ≥ PATROL_MIN clear cells.
enemy_patrol_pick
	ldx enemy_idx
	+lda_mx en_patrol
	bpl .epp_rand
	and #$7f				; consume first-patrol flag
	+sta_mx en_patrol
	lda en_dir,x
	and #7
	sta ai_probe
	jmp .epp_have
.epp_rand
	jsr rnd8
	and #3
	asl					; 0,2,4,6
	sta ai_probe
.epp_have
	ldx enemy_idx
	+lda_mx en_x
	sta col_x
	+lda_mx en_z
	sta col_z
	lda #0
	sta rot0				; clear count
.epp_scan
	lda rot0
	cmp #PATROL_SCAN
	bcs .epp_done
	ldy ai_probe
	clc
	lda col_x
	adc en_dx,y
	sta col_x
	clc
	lda col_z
	adc en_dz,y
	sta col_z
	jsr enemy_pos_ok
	bcc .epp_done
	inc rot0
	jmp .epp_scan
.epp_done
	lda rot0
	cmp #PATROL_MIN
	bcc .epp_fail
	jsr rnd8
	lsr
	lsr
	lsr
	lsr					; 0..15
	clc
	adc #PATROL_MIN				; 6..21
	cmp rot0
	bcc .epp_use
	beq .epp_use
	lda rot0
.epp_use
	ldx enemy_idx
	sta en_pat_n,x
	lda #EN_PATROL
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_step,x
	sta en_step_h,x
	sta en_timer,x
	sta en_timer_h,x
	lda ai_probe
	jsr enemy_set_geom
	rts
.epp_fail
	clc
	rts

; Clamp en_x/z: matching-top rb (standing, else nearest), not lid union.
enemy_clamp_room
	ldx enemy_idx
	+lda_mx en_x
	sta col_x
	+lda_mx en_z
	sta col_z
	jsr enemy_cutout_idx
	bcs .ecr_this
	jsr enemy_nearest_cutout
	cpx #$ff
	beq .ecr_ncut
	+lda_mx rb_sx
	beq .ecr_ncut
.ecr_this
	jsr load_box_rb
	jmp clamp_to_box_inset1
.ecr_ncut
	ldx enemy_idx
	+ldy_mx en_room
	jsr room_cols_inset1
	bcs .ecr_rts
	jsr enemy_match_rc
	bcc .ecr_rts
	jsr load_box_rc
	jmp clamp_to_box_inset1
.ecr_rts
	rts

; X = nearest matching-top rb for en_room, or $ff if none.
enemy_nearest_cutout
	lda #$ff
	sta proc_tmp1
	sta proc_tmp2
	ldx enemy_idx
	+lda_mx en_room
	asl
	sta proc_tmp0
	tax
	jsr .enc_cand
	ldx proc_tmp0
	inx
	jsr .enc_cand
	ldx proc_tmp2
	rts
.enc_cand
	jsr enemy_rb_top_ok
	bcc .enc_cno
	jsr .enc_dist
	cmp proc_tmp1
	bcs .enc_cno
	sta proc_tmp1
	stx proc_tmp2
.enc_cno
	rts
.enc_dist
	+lda_mx rb_sx
	lsr
	clc
	+adc_mx rb_x
	ldy enemy_idx
	sec
	+sbc_my en_x
	bcs .enc_ax
	eor #$ff
	clc
	adc #1
.enc_ax
	sta proc_tmp3
	+lda_mx rb_sz
	lsr
	clc
	+adc_mx rb_z
	sec
	+sbc_my en_z
	bcs .enc_az
	eor #$ff
	clc
	adc #1
.enc_az
	clc
	adc proc_tmp3
	rts

; X = matching-Y collider of en_room. C=1 found.
enemy_match_rc
	ldx enemy_idx
	+lda_mx en_room
	jsr room_mul3
	tax
	jsr .emr_one
	bcs .emr_yes
	inx
	jsr .emr_one
	bcs .emr_yes
	inx
	jsr .emr_one
.emr_yes
	rts
.emr_one
	+lda_mx rc_sx
	beq .emr_no
	ldy enemy_idx
	+lda_mx rc_y
	+cmp_my en_y
	beq .emr_ok
	bcs .emr_hi
	+lda_my en_y
	sec
	+sbc_mx rc_y
	jmp .emr_d
.emr_hi
	sec
	+sbc_my en_y
.emr_d
	cmp #FALL_LEDGE + 1
	bcs .emr_no
.emr_ok
	sec
	rts
.emr_no
	clc
	rts

; Clamp enemy_idx pos to box_* inset 1.
clamp_to_box_inset1
	ldx enemy_idx
	clc
	lda box_x
	adc #1
	sta rot0
	+lda_mx en_x
	cmp rot0
	bcs +
	lda rot0
	+sta_mx en_x
+
	clc
	lda box_x
	adc box_sx
	sec
	sbc #1
	sta rot1
	+lda_mx en_x
	cmp rot1
	bcc +
	lda rot1
	sec
	sbc #1
	+sta_mx en_x
+
	clc
	lda box_z
	adc #1
	sta rot0
	+lda_mx en_z
	cmp rot0
	bcs +
	lda rot0
	+sta_mx en_z
+
	clc
	lda box_z
	adc box_sz
	sec
	sbc #1
	sta rot1
	+lda_mx en_z
	cmp rot1
	bcc .cbi_rts
	lda rot1
	sec
	sbc #1
	+sta_mx en_z
.cbi_rts
	rts

; col_x/col_z vs player. C=1 ok, C=0 newly overlapping.
; Enter-only: start en_x/en_z already overlapping → allow. No rot*.
player_blocks_enemy
	ldx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcs .pbe_ok
	+lda_mx en_y
	sta box_y
	lda #ENEMY_CULL_H
	sta box_sy
	jsr player_overlaps_y
	bcc .pbe_ok
	lda col_x
	sta box_x
	lda col_z
	sta box_z
	jsr body_vs_cam
	bcc .pbe_ok
	ldx enemy_idx
	+lda_mx en_x
	sta box_x
	+lda_mx en_z
	sta box_z
	jsr body_vs_cam
	bcs .pbe_ok
	clc
	rts
.pbe_ok
	sec
	rts

; col_x/col_z proposed. C=1 ok (inset + solid + dest floor within STEP_UP + cutout).
; Uses enemy Y via cam hack for solid_at.
enemy_pos_ok
	jsr player_blocks_enemy
	bcc .epo_no
	ldx enemy_idx
	+ldy_mx en_room
	jsr room_cols_inset1
	bcc .epo_no
	lda cam_yh
	pha
	+lda_mx en_y
	clc
	adc #EYE_HEIGHT
	sta cam_yh
	ldy #1
	jsr solid_at
	pla
	sta cam_yh
	bcs .epo_no
	jsr enemy_floor_ok
	bcc .epo_no
	jmp enemy_cutout_ok
.epo_no
	clc
	rts

; Dest walkable ≤ en_y+STEP_UP (rc floor, crate top, solid plat).
; C=1 if |proc_tmp2 − en_y| ≤ STEP_UP. Leaves dest Y in proc_tmp2.
; Scrag: any floor under XZ (hover — ignore STEP_UP delta).
enemy_floor_ok
	ldx enemy_idx
	+ldy_mx en_type
	cpy #ENT_SCRAG
	beq .efl_scrag
	clc
	+lda_mx en_y
	adc #STEP_UP
	sta fb_probe_y
	jsr floor_below
	bcc .efl_no
	ldx enemy_idx
	lda proc_tmp2
	+cmp_mx en_y
	bcs .efl_pl
	+lda_mx en_y
	sec
	sbc proc_tmp2
	jmp .efl_cmp
.efl_pl
	sec
	+sbc_mx en_y
.efl_cmp
	cmp #STEP_UP + 1
	bcc .efl_yes
.efl_no
	clc
	rts
.efl_yes
	sec
	rts
.efl_scrag
	+lda_mx en_y
	sta fb_probe_y
	jmp floor_below

; If the room has a matching-top rb, dest must lie in one (inset 1).
enemy_cutout_ok
	lda col_x
	sta proc_tmp4
	lda col_z
	sta proc_tmp5
	jsr enemy_any_cutout_top
	bcc .eco_free
	ldx enemy_idx
	+lda_mx en_room
	asl
	tax
	jsr .eco_try
	bcs .eco_yes
	inx
	jsr .eco_try
.eco_yes
	rts
.eco_try
	jsr enemy_rb_top_ok
	bcc .eco_no
	lda proc_tmp4
	sta col_x
	lda proc_tmp5
	sta col_z
	jmp rb_inset1
.eco_no
	rts
.eco_free
	lda proc_tmp4
	sta col_x
	lda proc_tmp5
	sta col_z
	sec
	rts

; C=1 if any rb_* for en_room has |top − en_y| ≤ FALL_LEDGE.
enemy_any_cutout_top
	ldx enemy_idx
	+lda_mx en_room
	asl
	tax
	jsr enemy_rb_top_ok
	bcs .eact_yes
	inx
	jmp enemy_rb_top_ok
.eact_yes
	rts

; X = rb_*. C=1 if occupied and |top − en_y| ≤ FALL_LEDGE.
enemy_rb_top_ok
	+lda_mx rb_sx
	beq .erto_no
	clc
	+lda_mx rb_y
	+adc_mx rb_sy
	ldy enemy_idx
	+cmp_my en_y
	beq .erto_yes
	bcs .erto_hi
	sta proc_tmp3
	+lda_my en_y
	sec
	sbc proc_tmp3
	jmp .erto_d
.erto_hi
	sec
	+sbc_my en_y
.erto_d
	cmp #FALL_LEDGE + 1
	bcs .erto_no
.erto_yes
	sec
	rts
.erto_no
	clc
	rts

; Current col_x/z vs en_room rb_*. C=1 and X = rb index if top matches en_y.
enemy_cutout_idx
	ldx enemy_idx
	+lda_mx en_room
	asl
	tax
	jsr .eci_one
	bcs .eci_yes
	inx
	jsr .eci_one
.eci_yes
	rts
.eci_one
	jsr enemy_rb_top_ok
	bcc .eci_no
	jsr load_box_rb
	jmp point_in_box_xz
.eci_no
	rts

; X = rb index. C=1 if col_x/z inside inset 1.
rb_inset1
	+lda_mx rb_sx
	beq .rbi_no
	lda col_x
	+cmp_mx rb_x
	bcc .rbi_no
	beq .rbi_no
	clc
	+lda_mx rb_x
	+adc_mx rb_sx
	sec
	sbc #1
	cmp col_x
	bcc .rbi_no
	beq .rbi_no
	lda col_z
	+cmp_mx rb_z
	bcc .rbi_no
	beq .rbi_no
	clc
	+lda_mx rb_z
	+adc_mx rb_sz
	sec
	sbc #1
	cmp col_z
	bcc .rbi_no
	beq .rbi_no
	sec
	rts
.rbi_no
	clc
	rts

; C=1 clear LOS (no solid on the segment to the player).
enemy_shot_clear
	ldx enemy_idx
	+lda_mx en_x
	sta ln_ax
	+lda_mx en_y
	clc
	adc #SHOT_MID_H
	sta ln_ay
	+lda_mx en_z
	sta ln_az
	lda cam_xh
	sta ln_bx
	lda cam_yh
	sta ln_by
	lda cam_zh
	sta ln_bz
	+ldy_mx en_room
	jsr line_solids_hit
	bcs .esc_block
	sec
	rts
.esc_block
	clc
	rts

; X = enemy. Pick en_pain_i = rnd8 % n. A = n.
pick_var_n
	beq .pvn_one
	cmp #1
	beq .pvn_one
	sta rot1
	jsr rnd8
.pvn_mod
	cmp rot1
	bcc .pvn_store
	sbc rot1
	jmp .pvn_mod
.pvn_store
	sta en_pain_i,x
	rts
.pvn_one
	lda #0
	sta en_pain_i,x
	rts

; X = enemy. Pick en_pain_i = rnd8 % enemy_pain_n[type].
pick_pain_var
	jsr ldy_slot
	lda enemy_pain_n,y
	jmp pick_var_n

; X = enemy. Pick en_pain_i = rnd8 % enemy_death_n[slot].
pick_death_var
	jsr ldy_slot
	lda enemy_death_n,y
	jmp pick_var_n

; X = enemy. Pick en_pain_i = rnd8 % enemy_attack_n[slot].
pick_attack_var
	jsr ldy_slot
	lda enemy_attack_n,y
	jmp pick_var_n

; ------------------------------------------------------------------
; X = enemy. A = damage. Pain chance if survives.
; Quad x4 first. Flesh and Bone (difficulty 0) then x3/2, cap 255.
damage_enemy
	stx enemy_idx
	sta hit_dmg
	lda pu_kind
	cmp #BP_QUAD
	bne .de_skill
	asl hit_dmg
	asl hit_dmg
.de_skill
	lda difficulty
	bne .de_sub
	lda hit_dmg
	lsr
	clc
	adc hit_dmg
	bcc +
	lda #$ff
+
	sta hit_dmg
.de_sub
	lda en_state,x
	cmp #EN_DYING
	bcc .de_hp
	jmp .de_rts
.de_hp
	lda en_hp,x
	sec
	sbc hit_dmg
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
	+ldy_mx en_type
	cpy #ENT_SHAMBLER
	beq .de_sham
	jsr rnd8
	jsr ldy_slot
	cmp enemy_pain_chance,y
	bcs .de_rts
	jmp .de_pain
.de_sham
	cpx sham_pain_i
	bne .de_sham_roll
	lda sham_pain_l
	ora sham_pain_h
	bne .de_rts
.de_sham_roll
	lda hit_dmg
	cmp #SHAM_PAIN_ALWAYS
	bcs .de_sham_yes
	sta rot0
	asl
	clc
	adc rot0			; damage * 3 ≈ 256 * damage / 80
	sta rot0
	jsr rnd8
	cmp rot0
	bcs .de_rts
.de_sham_yes
	lda #<SHAM_PAIN_MS
	sta sham_pain_l
	lda #>SHAM_PAIN_MS
	sta sham_pain_h
	stx sham_pain_i
	lda #0
	sta sham_arc
.de_pain
	lda #EN_PAIN
	sta en_state,x
	lda #0
	sta en_frame,x
	+ldy_mx en_type
	lda #AI_CMD_PAIN
	jsr ai_invoke
	cmp #AI_CMD_PAIN
	bne .de_wince
	ldx enemy_idx
	jsr pick_pain_var
.de_wince
	lda #CUE_WINCE
	jmp enemy_play_cue
.de_kill
	jmp kill_enemy
.de_rts
	rts

; Count down the shambler pain lock. $ff index means idle.
sham_pain_tick
	lda sham_pain_i
	cmp #$ff
	beq .spt_rts
	sec
	lda sham_pain_l
	sbc dt_ms
	sta sham_pain_l
	lda sham_pain_h
	sbc dt_msh
	sta sham_pain_h
	bcs .spt_rts
	lda #$ff
	sta sham_pain_i
	lda #0
	sta sham_pain_l
	sta sham_pain_h
.spt_rts
	rts

; Axe: first hittable enemy in room within AXE_HIT_R. C=1 hit.
axe_try_kill
	ldx #0
.atk_lp
	cpx	map_nenemies
	bcs .atk_no
	lda en_state,x
	cmp #EN_DYING
	bcs .atk_n
	+lda_mx en_room
	cmp room_idx
	bne .atk_n
	+lda_mx en_x
	sec
	sbc cam_xh
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp #AXE_HIT_R + 1
	bcs .atk_n
	+lda_mx en_z
	sec
	sbc cam_zh
	bcs +
	eor #$ff
	clc
	adc #1
+
	cmp #AXE_HIT_R + 1
	bcs .atk_n
	+lda_mx en_y
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
	beq .atk_no
	jmp .atk_lp
.atk_no
	clc
	rts

; A = ceiling (>= 1). Returns A uniform in 1..ceiling. Uses rot1.
; Ceiling 1 stays 1. Remainder matches pick_var_n (0..n−1), then +1.
roll_upto
	cmp #1
	beq .ru_rts
	sta rot1
	jsr rnd8
.ru_mod
	cmp rot1
	bcc .ru_one
	sbc rot1
	jmp .ru_mod
.ru_one
	clc
	adc #1
.ru_rts
	rts

; ------------------------------------------------------------------
; Hitscan: mid-body project → |sx−CX|≤scan_hit_x (no screen-Y gate;
; height auto-aims). Ceiling min 1, then roll_upto → 1..ceiling.
; SSG: ceiling = scan_dmg_max − z, every cone hit.
; Nail: ceiling = scan_dmg_max − (z>>2), closest only.
; z in 0..SHOT_Z_MAX-1. Blood splat on closest hit; wall splat on miss.
shotgun_hitscan
	lda #SHOT_HIT_X
	sta scan_hit_x
	lda #$ff
	sta scan_hit_y
	lda #SHOT_DMG_MAX
	sta scan_dmg_max
	lda #1
	sta scan_dmg_all
	lda #15
	sta scan_jx_mask
	lda #8
	sta scan_jx_bias
	lda #7
	sta scan_jy_mask
	lda #4
	sta scan_jy_bias
	jmp gun_hitscan

nailgun_hitscan
	lda #NAIL_HIT_X
	sta scan_hit_x
	lda #$ff
	sta scan_hit_y
	lda #NAIL_DMG_MAX
	sta scan_dmg_max
	lda #0
	sta scan_dmg_all
	lda #3
	sta scan_jx_mask
	lda #2
	sta scan_jx_bias
	lda #3
	sta scan_jy_mask
	lda #2
	sta scan_jy_bias
	jmp gun_hitscan

gun_hitscan
	lda #$ff
	sta shot_hit_i
	sta shot_hit_z
	jsr load_view_trig
	ldx #0
.sh_lp
	cpx	map_nenemies
	bcc .sh_cont
	jmp .sh_done
.sh_cont
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcc .sh_alive
	jmp .sh_n
.sh_alive
	+lda_mx en_room
	cmp room_idx
	beq .sh_room
	jmp .sh_n
.sh_room
	lda cam_xh
	sta ln_ax
	lda cam_yh
	sta ln_ay
	lda cam_zh
	sta ln_az
	ldx enemy_idx
	+lda_mx en_x
	sta ln_bx
	+lda_mx en_y
	clc
	adc #SHOT_MID_H
	sta ln_by
	+lda_mx en_z
	sta ln_bz
	+ldy_mx en_room
	jsr line_solids_hit
	bcc .sh_vis
	jmp .sh_n				; room solid between camera and enemy
.sh_vis
	ldx enemy_idx
	+lda_mx en_x
	sta ent_wx
	+lda_mx en_y
	clc
	adc #SHOT_MID_H
	sta ent_wy
	+lda_mx en_z
	sta ent_wz
	lda cs_b
	jsr mulset_a
	lda sn_b
	jsr mulset_b
	ldx #0
	jsr xform_world_vert
	ldx enemy_idx
	; z_high in [0, SHOT_Z_MAX)
	lda CAM_ZH
	bpl .sh_zpos
	jmp .sh_n
.sh_zpos
	cmp #SHOT_Z_MAX
	bcc .sh_zok
	jmp .sh_n
.sh_zok
	sta gidx				; CAM_ZH for dmg + closest
	bne .sh_proj
	lda CAM_Z
	bne .sh_proj
	jmp .sh_n				; exactly at camera
.sh_proj
	jsr project_cam0_screen
	bcc .sh_n
	sty rot1				; sy
	; |sx − SCREEN_CX| ≤ scan_hit_x
	sec
	sbc #SCREEN_CX
	bpl .sh_xabs
	eor #$ff
	clc
	adc #1
.sh_xabs
	cmp scan_hit_x
	beq .sh_xok
	bcs .sh_n
.sh_xok
	lda scan_hit_y
	cmp #$ff
	beq .sh_cone
	lda rot1
	sec
	sbc #64
	bpl .sh_yabs
	eor #$ff
	clc
	adc #1
.sh_yabs
	cmp scan_hit_y
	beq .sh_cone
	bcs .sh_n
.sh_cone
	; SSG ceiling = scan_dmg_max − z, min 1, then 1..ceiling
	lda scan_dmg_all
	beq .sh_track
	lda gidx
	eor #$ff
	sec
	adc scan_dmg_max
	beq .sh_one
	bcs .sh_roll
.sh_one
	lda #1
.sh_roll
	jsr roll_upto
	ldx enemy_idx
	jsr damage_enemy
	ldx enemy_idx
.sh_track
	lda shot_hit_i
	cmp #$ff
	beq .sh_set
	lda gidx
	cmp shot_hit_z
	bcs .sh_n
.sh_set
	ldx enemy_idx
	stx shot_hit_i
	lda gidx
	sta shot_hit_z
.sh_n
	ldx enemy_idx
	inx
	jmp .sh_lp
.sh_done
	lda shot_hit_i
	cmp #$ff
	beq .sh_miss
	lda scan_dmg_all
	bne .sh_splat
	lda shot_hit_z
	lsr
	lsr
	eor #$ff
	sec
	adc scan_dmg_max
	beq .sh_none
	bcs .sh_nroll
.sh_none
	lda #1
.sh_nroll
	jsr roll_upto
	ldx shot_hit_i
	stx enemy_idx
	jsr damage_enemy
.sh_splat
	jsr shotgun_hit_splat
	jmp .sh_out
.sh_miss
	jsr shotgun_miss_splat
.sh_out
	rts

; Mid-body blood splat on shot_hit_i (view trig loaded).
shotgun_hit_splat
	ldx shot_hit_i
	+lda_mx en_x
	sta ent_wx
	+lda_mx en_y
	clc
	adc #SHOT_MID_H
	sta ent_wy
	+lda_mx en_z
	sta ent_wz
	lda cs_b
	jsr mulset_a
	lda sn_b
	jsr mulset_b
	ldx #0
	jsr xform_world_vert
	jsr project_cam0_screen
	bcc .shs_rts
	ldx CAM_ZH				; view depth → EMUZ_Z* LOD
	stx rot0
	jsr splat_aim_jitter			; A/Y = projected ±jitter
	sta rot2
	lda #COL_SPLAT_HIT
	sta splat_col
	ldx rot0
	lda rot2
	jmp start_splat
.shs_rts
	rts

; Miss splat at the nearest room solid (cutout, crate, platform, elevator,
; crusher, ramp, or the outer wall). View trig loaded.
shotgun_miss_splat
	lda cam_xh
	sta ln_ax
	lda cam_yh
	sta ln_ay
	lda cam_zh
	sta ln_az
	ldy pitch
	lda COSTAB,y
	sta rot2				; cos pitch
	tay
	lda sn_b
	jsr smul7
	sta ln_bx				; dx
	lda rot2
	tay
	lda cs_b
	jsr smul7
	sta ln_bz				; dz
	ldy pitch
	lda SINTAB,y
	eor #$ff
	clc
	adc #1
	sta ln_by				; dy = −sin pitch
	ldy room_idx
	jsr line_fit_b
	ldy room_idx
	jsr line_solids_hit
	bcs .sms_proj
	rts
.sms_proj
	lda col_x
	sta ent_wx
	lda col_y
	sta ent_wy
	lda col_z
	sta ent_wz
	lda cs_b
	jsr mulset_a
	lda sn_b
	jsr mulset_b
	ldx #0
	jsr xform_world_vert
	ldx CAM_ZH
	bpl .sms_z
	ldx #0
.sms_z
	stx rot0				; view depth → EMUZ_Z* LOD
	lda #SCREEN_CX
	ldy #64				; viewport centre = look
	jsr splat_aim_jitter			; A/Y = centre ±jitter
	sta rot2
	lda col_line
	sta splat_col
	ldx rot0
	lda rot2
	jmp start_splat

; A/Y = base sx/sy → /2, then splat_aim_half.
splat_aim_jitter
	lsr
	sta rot2
	tya
	lsr
	tay
	lda rot2
; A/Y already half-pixel (0..95 / 0..63). Jitter, clamp, ×2.
splat_aim_half
	sta rot2
	tya
	pha
	jsr rnd8
	and #7
	sec
	sbc #4
	clc
	adc rot2
	bpl +
	lda #0
+
	cmp #96
	bcc +
	lda #95
+
	asl
	sta rot2
	pla
	sta rot1
	jsr rnd8
	and #3
	sec
	sbc #2
	clc
	adc rot1
	bpl +
	lda #0
+
	cmp #64
	bcc +
	lda #63
+
	asl
	tay
	lda rot2
	rts
