; Enemy AI — room-scoped state machine (idle/patrol/alert/approach/attack/pain/death)
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
	jsr enemy_chebyshev
	cmp #ENEMY_DETECT + 1
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
	jsr enemy_chebyshev
	cmp #ENEMY_DETECT + 1
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
	jsr enemy_chebyshev
	cmp #ENEMY_DETECT + 1
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
	; Rottweiler: stand in melee range; repath when chase timer expires
	lda en_type,x
	beq .eu_ap_acc			; grunt — keep strafing
	jsr enemy_same_floor
	bcs .eu_ap_same
	ldx enemy_idx
	lda en_timer,x
	ora en_timer_h,x
	bne .eu_ap_acc			; retry window — walk even if floors differ
	jmp enemy_dog_wait
.eu_ap_same
	ldx enemy_idx
	jsr enemy_chebyshev
	ldy en_type,x
	cmp enemy_range,y
	beq .eu_ap_stand
	bcc .eu_ap_stand
	lda en_timer,x
	ora en_timer_h,x
	bne .eu_ap_acc
	jsr select_dodge_dir
	ldx enemy_idx
	lda #<DOG_REPATH_MS
	sta en_timer,x
	lda #>DOG_REPATH_MS
	sta en_timer_h,x
	jmp .eu_ap_acc
.eu_ap_stand
	lda #0				; clear repath so resume chases immediately
	sta en_timer,x
	sta en_timer_h,x
	jmp .eu_ap_rng
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
	ldy en_type,x
	cmp enemy_range,y
	beq .eu_ap_atk
	bcc .eu_ap_atk
	jmp eu_next
.eu_ap_atk
	lda en_timer,x
	ora en_timer_h,x
	bne eu_next
	lda en_type,x
	beq .eu_ap_glos
	jsr enemy_same_floor
	bcc eu_next			; dog — no bite through a hole
	jmp .eu_ap_doatk
.eu_ap_glos
	jsr enemy_shot_clear
	bcc eu_next			; corner / hole in the way
.eu_ap_doatk
	ldx enemy_idx
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
.eas_walk
	ldy en_type,x
	inc en_frame,x
	lda en_frame,x
	cmp enemy_walk_len,y
	bcc +
	lda #0
	sta en_frame,x
+
	jmp .eas_n
.eas_oneshot
	ldy en_type,x
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
	; Latch hit if we landed on / skipped past fire frame: old < fire <= new
	lda enemy_fire_frame,y
	bmi .eas_atlen_go			; $ff = none
	cmp rot2
	beq .eas_atlen_go			; already were on fire frame
	bcc .eas_atlen_go			; fire < old → already past
	pla
	pha
	cmp enemy_fire_frame,y
	bcc .eas_atlen_go			; new < fire → not yet
	lda en_type,x
	bne .eas_bite			; Rottweiler — leap bite
	lda enemy_idx
	sta emuz_pending
	jsr enemy_gunshot
	ldx enemy_idx
	ldy en_type,x
	jmp .eas_atlen_go
.eas_bite
	jsr enemy_bite
	ldx enemy_idx
	ldy en_type,x
.eas_atlen_go
	pla
	cmp enemy_attack_len,y
	bcs +
	jmp .eas_n
+
	; Grunt 50% re-shoot; Rott always re-bite if still in range
	ldx enemy_idx
	lda en_type,x
	bne .eas_rng_chk
	jsr rnd8
	bmi .eas_to_ap
.eas_rng_chk
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
	ldx enemy_idx
	lda en_type,x
	bne .eas_dog_again
	jsr enemy_shot_clear
	bcc .eas_to_ap
	jmp .eas_do_again
.eas_dog_again
	jsr enemy_same_floor
	bcc .eas_to_ap
.eas_do_again
	ldx enemy_idx
	lda #EN_ATTACK
	sta en_state,x
	lda #0
	sta en_frame,x
	jsr enemy_face_player
	jmp .eas_n
.eas_die
	inc en_frame,x
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
; Rottweiler: nodir turnaround (may 180°); grunt: forbid reverse while walking
select_dodge_dir
	ldx enemy_idx
	lda en_type,x
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
	bcc .sdd_ord			; |dz| < |dx| — X already major
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
.sdd_ord
	; Grunt too close: prefer away (swap toward↔away, rebuild diag)
	ldx enemy_idx
	lda en_type,x
	bne .sdd_zig
	jsr enemy_chebyshev
	cmp #GRUNT_BACKOFF + 1
	bcs .sdd_zig
	lda ai_dirtry
	ldx ai_dirtry+2
	sta ai_dirtry+2
	stx ai_dirtry
	lda ai_dirtry+1
	ldx ai_dirtry+3
	sta ai_dirtry+3
	stx ai_dirtry+1
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
.sdd_zig
	; diagonal-first + random toward/away shuffle (zigzag)
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
	lda #4				; diagonal first
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

; Enter alert one-shot (Halt / bark).
enemy_enter_alert
	ldx enemy_idx
	lda #EN_ALERT
	sta en_state,x
	lda #0
	sta en_frame,x
	lda en_type,x
	bne .eeal_bark
	lda #SOUND_HALT
	jmp play_sound
.eeal_bark
	lda #SOUND_DOGBARK
	jmp play_sound

; Enter approach: grunt APPROACH_MIN; Rott DOG_REPATH. Zero step; pick dodge.
enemy_enter_approach
	stx enemy_idx
	lda #EN_APPROACH
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_step,x
	sta en_step_h,x
	lda en_type,x
	bne .eea_dog
	lda #<APPROACH_MIN_MS
	sta en_timer,x
	lda #>APPROACH_MIN_MS
	sta en_timer_h,x
	jmp .eea_dodge
.eea_dog
	lda #<DOG_REPATH_MS
	sta en_timer,x
	lda #>DOG_REPATH_MS
	sta en_timer_h,x
.eea_dodge
	jsr select_dodge_dir
	rts

; Rottweiler: stand-idle when player is on another floor piece.
enemy_dog_wait
	ldx enemy_idx
	lda #EN_IDLE
	sta en_state,x
	lda #0
	sta en_frame,x
	lda #<DOG_WAIT_MS
	sta en_timer,x
	lda #>DOG_WAIT_MS
	sta en_timer_h,x
	jmp eu_next

; C=1 |floor_y − en_y| ≤ FALL_LEDGE (same floor piece)
enemy_same_floor
	ldx enemy_idx
	lda floor_y
	cmp en_y,x
	bcs .esf_pl
	lda en_y,x
	sec
	sbc floor_y
	jmp .esf_cmp
.esf_pl
	sec
	sbc en_y,x
.esf_cmp
	cmp #FALL_LEDGE + 1
	bcc .esf_yes
	clc
	rts
.esf_yes
	sec
	rts

; Rottweiler leap hit — recheck range, then rnd>>4 damage (0 = miss).
enemy_bite
	ldx enemy_idx
	jsr enemy_same_floor
	bcc .eb_rts
	jsr enemy_chebyshev
	ldy en_type,x
	cmp enemy_range,y
	beq .eb_roll
	bcc .eb_roll
	rts
.eb_roll
	jsr rnd8
	lsr
	lsr
	lsr
	lsr
	beq .eb_rts
	sta rot0
	lda player_hp
	beq .eb_rts
	lda rot0
	jsr take_damage
	; latch splat for draw (same view-space origin as mesh — not AI re-project)
	lda enemy_idx
	sta bite_splat_i
.eb_rts
	rts

; Grunt fire frame: recheck LOS, distance-scaled hit roll, 8–15 HP.
enemy_gunshot
	jsr enemy_shot_clear	; player may have reached cover mid-anim
	bcc .eg_rts
	ldx enemy_idx
	jsr enemy_chebyshev
	asl
	asl			; miss threshold = dist*4
	bcs .eg_rts		; dist ≥ 64 — out of range safety
	sta rot1
	jsr rnd8
	cmp rot1
	bcc .eg_rts		; miss
	and #7
	clc
	adc #8			; 8–15 HP (player scale is 100; HURT_HP=10)
	jmp take_damage
.eg_rts
	rts

; A = damage — subtract from player_hp (and armour if any); hurt/death SFX; red border flash
take_damage
	sta rot0
	lda player_hp
	beq .td_rts
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
	lda #SOUND_TAKEDAMAGE
	jmp play_sound
.td_death
	lda #SOUND_PLAYERDEATH
	jmp play_sound
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

; One cell along current en_dir. C=1 moved.
enemy_patrol_step
	ldx enemy_idx
	lda en_dir,x
	jsr enemy_probe_dir
	bcc .eps_no
	ldx enemy_idx
	lda col_x
	sta en_x,x
	lda col_z
	sta en_z,x
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
	lda en_patrol,x
	beq .eitp_no
	jsr enemy_patrol_pick
.eitp_no
	jmp eu_next

; First pick: spawn octant (en_dir). Later: random cardinal.
; C ignored — enter EN_PATROL if ≥ PATROL_MIN clear cells.
enemy_patrol_pick
	ldx enemy_idx
	lda en_patrol,x
	bpl .epp_rand
	and #$7f				; consume first-patrol flag
	sta en_patrol,x
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
	lda en_x,x
	sta col_x
	lda en_z,x
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
	lda en_x,x
	sta col_x
	lda en_z,x
	sta col_z
	jsr enemy_cutout_idx
	bcs .ecr_this
	jsr enemy_nearest_cutout
	cpx #$ff
	beq .ecr_ncut
	lda rb_sx,x
	beq .ecr_ncut
.ecr_this
	jsr load_box_rb
	jmp clamp_to_box_inset1
.ecr_ncut
	ldx enemy_idx
	ldy en_room,x
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
	lda en_room,x
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
	lda rb_sx,x
	lsr
	clc
	adc rb_x,x
	ldy enemy_idx
	sec
	sbc en_x,y
	bcs .enc_ax
	eor #$ff
	clc
	adc #1
.enc_ax
	sta proc_tmp3
	lda rb_sz,x
	lsr
	clc
	adc rb_z,x
	sec
	sbc en_z,y
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
	lda en_room,x
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
	lda rc_sx,x
	beq .emr_no
	ldy enemy_idx
	lda rc_y,x
	cmp en_y,y
	beq .emr_ok
	bcs .emr_hi
	lda en_y,y
	sec
	sbc rc_y,x
	jmp .emr_d
.emr_hi
	sec
	sbc en_y,y
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
	lda en_x,x
	cmp rot0
	bcs +
	lda rot0
	sta en_x,x
+
	clc
	lda box_x
	adc box_sx
	sec
	sbc #1
	sta rot1
	lda en_x,x
	cmp rot1
	bcc +
	lda rot1
	sec
	sbc #1
	sta en_x,x
+
	clc
	lda box_z
	adc #1
	sta rot0
	lda en_z,x
	cmp rot0
	bcs +
	lda rot0
	sta en_z,x
+
	clc
	lda box_z
	adc box_sz
	sec
	sbc #1
	sta rot1
	lda en_z,x
	cmp rot1
	bcc .cbi_rts
	lda rot1
	sec
	sbc #1
	sta en_z,x
.cbi_rts
	rts

; col_x/col_z proposed. C=1 ok (inset + solid + same-elevation floor + cutout).
; Uses enemy Y via cam hack for solid_at.
enemy_pos_ok
	ldx enemy_idx
	ldy en_room,x
	jsr room_cols_inset1
	bcc .epo_no
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
	jsr enemy_floor_ok
	bcc .epo_no
	jmp enemy_cutout_ok
.epo_no
	clc
	rts

; Dest lowest rc_y vs en_y. C=1 if |floor − en_y| ≤ FALL_LEDGE.
enemy_floor_ok
	ldx enemy_idx
	ldy en_room,x
	jsr peek_rc_floor
	bcc .efl_no
	ldx enemy_idx
	lda proc_tmp2
	cmp en_y,x
	bcs .efl_pl
	lda en_y,x
	sec
	sbc proc_tmp2
	jmp .efl_cmp
.efl_pl
	sec
	sbc en_y,x
.efl_cmp
	cmp #FALL_LEDGE + 1
	bcc .efl_yes
.efl_no
	clc
	rts
.efl_yes
	sec
	rts

; If the room has a matching-top rb, dest must lie in one (inset 1).
enemy_cutout_ok
	lda col_x
	sta proc_tmp4
	lda col_z
	sta proc_tmp5
	jsr enemy_any_cutout_top
	bcc .eco_free
	ldx enemy_idx
	lda en_room,x
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
	lda en_room,x
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
	lda rb_sx,x
	beq .erto_no
	clc
	lda rb_y,x
	adc rb_sy,x
	ldy enemy_idx
	cmp en_y,y
	beq .erto_yes
	bcs .erto_hi
	sta proc_tmp3
	lda en_y,y
	sec
	sbc proc_tmp3
	jmp .erto_d
.erto_hi
	sec
	sbc en_y,y
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
	lda en_room,x
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
	lda rb_sx,x
	beq .rbi_no
	lda col_x
	cmp rb_x,x
	bcc .rbi_no
	beq .rbi_no
	clc
	lda rb_x,x
	adc rb_sx,x
	sec
	sbc #1
	cmp col_x
	bcc .rbi_no
	beq .rbi_no
	lda col_z
	cmp rb_z,x
	bcc .rbi_no
	beq .rbi_no
	clc
	lda rb_z,x
	adc rb_sz,x
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

; C=1 clear LOS (no 3D hit on room cutout boxes).
enemy_shot_clear
	ldx enemy_idx
	lda en_x,x
	sta ln_ax
	lda en_y,x
	clc
	adc #SHOT_MID_H
	sta ln_ay
	lda en_z,x
	sta ln_az
	lda cam_xh
	sta ln_bx
	lda cam_yh
	sta ln_by
	lda cam_zh
	sta ln_bz
	ldy en_room,x
	jsr line_cutouts_hit
	bcc .esc_clear
	clc
	rts
.esc_clear
	sec
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
	ldy en_type,x
	lda enemy_pain_n,y
	jmp pick_var_n

; X = enemy. Pick en_pain_i = rnd8 % enemy_death_n[type].
pick_death_var
	ldy en_type,x
	lda enemy_death_n,y
	jmp pick_var_n

; ------------------------------------------------------------------
; X = enemy. A = damage. Pain chance if survives.
damage_enemy
	sta rot2
	lda pu_kind
	cmp #BP_QUAD
	bne .de_sub
	asl rot2
	asl rot2
.de_sub
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
	jsr pick_pain_var
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

; ------------------------------------------------------------------
; Super shotgun: screen-aim hit. Mid-body project → |sx−CX|≤SHOT_HIT_X,
; damage = SHOT_DMG_MAX − (z>>2), min 1, for z in 0..SHOT_Z_MAX-1.
; Blood splat on closest hit; col_line wall splat on miss.
shotgun_hitscan
	lda #$ff
	sta shot_hit_i
	sta shot_hit_z
	jsr load_view_trig
	ldx #0
.sh_lp
	cpx #MAP_NENEMIES
	bcc .sh_cont
	jmp .sh_done
.sh_cont
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcc .sh_alive
	jmp .sh_n
.sh_alive
	lda en_room,x
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
	lda en_x,x
	sta ln_bx
	lda en_y,x
	clc
	adc #SHOT_MID_H
	sta ln_by
	lda en_z,x
	sta ln_bz
	ldy en_room,x
	jsr line_cutouts_hit
	bcc .sh_vis
	jmp .sh_n				; cutout solid (L/T/S notch)
.sh_vis
	ldx enemy_idx
	lda en_x,x
	sta ent_wx
	lda en_y,x
	clc
	adc #SHOT_MID_H
	sta ent_wy
	lda en_z,x
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
	; |sx − SCREEN_CX| ≤ SHOT_HIT_X
	sec
	sbc #SCREEN_CX
	bpl .sh_xabs
	eor #$ff
	clc
	adc #1
.sh_xabs
	cmp #SHOT_HIT_X + 1
	bcs .sh_n
	; dmg = SHOT_DMG_MAX − (z >> 2), min 1
	lda gidx
	lsr
	lsr
	eor #$ff
	sec
	adc #SHOT_DMG_MAX
	bne .sh_do
	lda #1
.sh_do
	ldx enemy_idx
	jsr damage_enemy
	ldx enemy_idx
	lda shot_hit_i
	cmp #$ff
	beq .sh_set
	lda gidx
	cmp shot_hit_z
	bcs .sh_n
.sh_set
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
	jsr shotgun_hit_splat
	jmp .sh_out
.sh_miss
	jsr shotgun_miss_splat
.sh_out
	rts

; Mid-body blood splat on shot_hit_i (view trig loaded).
shotgun_hit_splat
	ldx shot_hit_i
	lda en_x,x
	sta ent_wx
	lda en_y,x
	clc
	adc #SHOT_MID_H
	sta ent_wy
	lda en_z,x
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
	jsr splat_aim_jitter			; A/Y = projected ±8/±4
	sta rot2
	lda #COL_SPLAT_HIT
	sta splat_col
	ldx rot0
	lda rot2
	jmp start_splat
.shs_rts
	rts

; Miss splat at nearest cutout hit, else outer-room wall.
; View trig loaded.
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
	clc
	adc cam_xh
	sta ln_bx
	lda rot2
	tay
	lda cs_b
	jsr smul7
	clc
	adc cam_zh
	sta ln_bz
	ldy pitch
	lda SINTAB,y
	sta rot0
	lda cam_yh
	sec
	sbc rot0
	sta ln_by
	ldy room_idx
	jsr line_cutouts_hit
	bcs .sms_proj			; nearest cutout
	ldy room_idx
	jsr load_box_room
	jsr line_hit_box
	bcc .sms_rts
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
	jsr project_cam0_screen
	bcc .sms_rts
	sta rot2				; sx (Y = sy)
	ldx CAM_ZH
	lda col_line
	sta splat_col
	lda rot2
	jmp start_splat
.sms_rts
	rts

; A/Y = base sx/sy → A/Y = base ±8 X / ±4 Y, clamped to viewport.
splat_aim_jitter
	sta rot2
	tya
	pha
	jsr rnd8
	and #15
	sec
	sbc #8
	clc
	adc rot2
	bpl .saj_sx1
	lda #0
	beq .saj_sxok
.saj_sx1
	cmp #192
	bcc .saj_sxok
	lda #191
.saj_sxok
	sta rot2
	pla
	sta rot1
	jsr rnd8
	and #7
	sec
	sbc #4
	clc
	adc rot1
	tay
	bpl .saj_sy1
	ldy #0
	beq .saj_done
.saj_sy1
	cpy #128
	bcc .saj_done
	ldy #127
.saj_done
	lda rot2
	rts
