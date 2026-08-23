; Room physics, proximity triggers, floor / eye sync
!zone world

; ------------------------------------------------------------------
world_init
	lda spawn_room
	jsr set_room_idx
	lda #0
	sta cam_xl
	sta cam_yl
	sta cam_zl
	sta pitch
	sta msg_on
	sta status_ms_l
	sta status_ms_h
	lda #$ff
	sta pl_on_elev
	lda #0
	sta pl_falling
	sta fall_vl
	sta fall_vh
	sta fall_y0
	sta fall_acc
	sta hurt_flash_l
	sta hurt_flash_h
	sta hurt_ms_l
	sta hurt_ms_h
	sta item_spin
	sta item_spin_l
	lda #$ff
	sta trig_inside
	; spawn eye at spawn_x+1 (center-ish), spawn_y+EYE, spawn_z+1
	clc
	lda spawn_x
	adc #1
	sta cam_xh
	clc
	lda spawn_y
	adc #EYE_HEIGHT
	sta cam_yh
	clc
	lda spawn_z
	adc #1
	sta cam_zh
	; yaw from rot octant * 32
	lda spawn_rot
	asl
	asl
	asl
	asl
	asl
	sta yaw
	jsr proc_init
	jsr init_backpacks
	jsr init_enemies
	jsr init_grenades
	jsr init_drops
	lda spawn_y
	sta floor_y
	jsr update_floor
	jsr sync_eye
	lda #$ff
	sta palette_room
	jsr apply_room_palette
	rts

; Clear bp_taken[0..MAP_NBACKPACKS)
init_backpacks
	ldx #0
.ib_lp
	cpx	map_nbackpacks
	bcs .ib_rts
	lda #0
	sta bp_taken,x
	inx
	beq .ib_rts
	jmp .ib_lp
.ib_rts
	rts

; All enemies idle, HP from type, frame 0
init_enemies
	lda #$a5
	sta random8
	lda #0
	sta gunshot_wake
	ldx #0
.ie_lp
	cpx	map_nenemies
	bcs .ie_rts
	lda #EN_IDLE
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_timer,x
	sta en_timer_h,x
	sta en_step,x
	sta en_step_h,x
	sta en_pat_n,x
	sta en_pain_i,x
	+lda_mx en_rot			; map rot = editor octant (0=+Z)
	sta en_dir,x
	asl
	asl
	asl
	asl
	asl
	+sta_mx en_rot
	+lda_mx en_patrol
	and #1
	beq .ie_hp
	ora #$80			; first patrol uses spawn dir
	+sta_mx en_patrol
.ie_hp
	+ldy_mx en_type
	lda enemy_hp_init,y
	sta en_hp,x
	inx
	beq .ie_rts
	jmp .ie_lp
.ie_rts
	rts

; Drop slots inactive (taken=1)
init_drops
	ldx #0
	lda #1
.id_lp
	cpx	map_nenemies
	bcs .id_rts
	sta drop_taken,x
	inx
	beq .id_rts
	jmp .id_lp
.id_rts
	rts

; ------------------------------------------------------------------
; point_in_aabb_xz — col_x/col_z vs box at Y index in tables via box_* zp
; C=1 inside (exclusive max)
; ------------------------------------------------------------------
point_in_box_xz
	lda col_x
	cmp box_x
	bcc .pib_no
	clc
	lda box_x
	adc box_sx
	cmp col_x
	bcc .pib_no
	beq .pib_no
	lda col_z
	cmp box_z
	bcc .pib_no
	clc
	lda box_z
	adc box_sz
	cmp col_z
	bcc .pib_no
	beq .pib_no
	sec
	rts
.pib_no
	clc
	rts

; ------------------------------------------------------------------
; player_overlaps_y — [feet, feet+PLAYER_H) vs [box_y, box_y+box_sy)
; C=1 overlap
; ------------------------------------------------------------------
player_overlaps_y
	clc
	lda box_y
	adc box_sy
	sta col_y			; exclusive max of box
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcs .poy_no			; feet >= y+sy
	clc
	adc #PLAYER_H			; exclusive head
	sta col_y
	lda box_y
	cmp col_y
	bcs .poy_no			; y >= head
	sec
	rts
.poy_no
	clc
	rts

; If col_x/z in collider X, set proc_tmp2 to rc_y (proc_tmp0 = found).
; Several colliders may overlap in XZ when an L/T/S is rotated so one
; arm is vertical (lid over a shaft). The union hull leaves a hole;
; use the lowest floor so you drop, not the lid.
uf_rc_floor
	+lda_mx rc_sx
	beq .urf_rts
	jsr point_in_rc_xz
	bcc .urf_rts
	lda proc_tmp0
	bne .urf_min
	+lda_mx rc_y
	sta proc_tmp2
	lda #1
	sta proc_tmp0
	rts
.urf_min
	+lda_mx rc_y
	cmp proc_tmp2
	bcs .urf_rts
	sta proc_tmp2
.urf_rts
	rts

; Y = room. col_x/col_z set. C=1 found; proc_tmp0=1, proc_tmp2=lowest rc_y.
peek_rc_floor
	tya
	jsr room_mul3
	tax
	lda #0
	sta proc_tmp0
	jsr uf_rc_floor
	inx
	jsr uf_rc_floor
	inx
	jsr uf_rc_floor
	lda proc_tmp0
	beq .prf_no
	sec
	rts
.prf_no
	clc
	rts

; col_x/col_z/room_idx set. rot2 = probe Y inclusive.
; C=1, proc_tmp2 = highest walkable ≤ rot2 (rc floor, crate top, solid plat).
floor_below
	ldy room_idx
	jsr peek_rc_floor
	bcc .fb_surf
	lda proc_tmp2
	cmp rot2
	beq .fb_surf
	bcc .fb_surf
	lda #0
	sta proc_tmp0
.fb_surf
	ldx #0
.fb_c
	cpx	map_ncrates
	bcs .fb_p
	+lda_mx crate_room
	cmp room_idx
	bne .fb_cn
	+lda_mx crate_x
	sta box_x
	+lda_mx crate_z
	sta box_z
	+lda_mx crate_sx
	sta box_sx
	+lda_mx crate_sz
	sta box_sz
	jsr point_in_box_xz
	bcc .fb_cn
	clc
	+lda_mx crate_y
	+adc_mx crate_sy
	jsr .fb_cand
.fb_cn
	inx
	bne .fb_c
.fb_p
	ldx #0
.fb_pl
	cpx	map_nplats
	bcs .fb_done
	+lda_mx plat_solid
	beq .fb_pn
	+lda_mx plat_room
	cmp room_idx
	bne .fb_pn
	+lda_mx plat_x
	sta box_x
	+lda_mx plat_z
	sta box_z
	+lda_mx plat_sx
	sta box_sx
	+lda_mx plat_sz
	sta box_sz
	jsr point_in_box_xz
	bcc .fb_pn
	+lda_mx plat_y
	jsr .fb_cand
.fb_pn
	inx
	bne .fb_pl
.fb_done
	lda proc_tmp0
	beq .fb_no
	sec
	rts
.fb_no
	clc
	rts
.fb_cand
	cmp rot2
	beq .fb_ok
	bcs .fb_skip
.fb_ok
	ldy proc_tmp0
	beq .fb_take
	cmp proc_tmp2
	bcc .fb_skip
	beq .fb_skip
.fb_take
	sta proc_tmp2
	lda #1
	sta proc_tmp0
.fb_skip
	rts

; ------------------------------------------------------------------
update_floor
	lda pl_on_elev
	sta obj_i			; prior elev (rider), before clear
	lda #$ff
	sta pl_on_elev
	lda #0
	sta floor_yl			; integer floors; ramp fills 8.8
	sta floor_slope
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	ldy room_idx
	jsr peek_rc_floor
	bcc .uf_c0
	lda proc_tmp2
	sta floor_y
.uf_c0
	ldx #0
	; crate tops (walkable)
.uf_c
	cpx	map_ncrates
	bcs .uf_p
	+lda_mx crate_room
	cmp room_idx
	bne .uf_cn
	+lda_mx crate_x
	sta box_x
	+lda_mx crate_z
	sta box_z
	+lda_mx crate_sx
	sta box_sx
	+lda_mx crate_sz
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .uf_cn
	clc
	+lda_mx crate_y
	+adc_mx crate_sy
	cmp floor_y
	bcc .uf_cn
	beq .uf_cn
	sta col_y			; crate_top
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcc .uf_cn			; feet < top — overhead
	lda col_y
	sta floor_y
.uf_cn
	inx
	beq .uf_p
	jmp .uf_c
.uf_p
	; platforms (walkable if solid)
	ldx #0
.uf_pl
	cpx	map_nplats
	bcs .uf_plats_done
	+lda_mx plat_solid
	beq .uf_pn
	+lda_mx plat_room
	cmp room_idx
	bne .uf_pn
	+lda_mx plat_x
	sta box_x
	+lda_mx plat_z
	sta box_z
	+lda_mx plat_sx
	sta box_sx
	+lda_mx plat_sz
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .uf_pn
	+lda_mx plat_y
	cmp floor_y
	bcc .uf_pn
	beq .uf_pn
	sta col_y			; plat plane
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp col_y
	bcc .uf_pn			; feet < plane — overhead
	lda col_y
	sta floor_y
.uf_pn
	inx
	beq .uf_plats_done
	jmp .uf_pl
.uf_plats_done
	jsr elev_update_floor
.uf_slope
	ldx #0
.uf_s
	cpx	map_nslopes
	bcc .uf_sgo
	jmp .uf_done
.uf_sgo
	+lda_mx slope_room
	cmp room_idx
	beq .uf_sroom
	jmp .uf_sn
.uf_sroom
	+lda_mx slope_x
	sta box_x
	+lda_mx slope_z
	sta box_z
	+lda_mx slope_sx
	sta box_sx
	+lda_mx slope_sz
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcs .uf_sxz
	jmp .uf_sn
.uf_sxz
	; height = slope_y + (local_8.8 * sy) / run
	+lda_mx slope_axis
	bne .uf_sz
	lda cam_xl
	sta ylo
	sec
	lda cam_xh
	+sbc_mx slope_x
	sta yhi
	+lda_mx slope_dir
	bne .uf_sx_go
	lda #0
	sec
	sbc ylo
	sta ylo
	+lda_mx slope_sx
	sbc yhi
	sta yhi
.uf_sx_go
	+lda_mx slope_sx
	jmp .uf_sinterp
.uf_sz
	lda cam_zl
	sta ylo
	sec
	lda cam_zh
	+sbc_mx slope_z
	sta yhi
	+lda_mx slope_dir
	bne .uf_sz_go
	lda #0
	sec
	sbc ylo
	sta ylo
	+lda_mx slope_sz
	sbc yhi
	sta yhi
.uf_sz_go
	+lda_mx slope_sz
.uf_sinterp
	sta dlo				; run
	beq .uf_sflat
	stx obj_i
	+ldy_mx slope_sy
	lda ylo
	jsr umul8j			; local_l * sy
	lda prod_l
	sta rot0
	lda prod_h
	sta rot1
	lda #0
	sta rot2
	ldx obj_i
	+ldy_mx slope_sy
	lda yhi
	jsr umul8j			; local_h * sy → bits 8–23
	clc
	lda rot1
	adc prod_l
	sta rot1
	lda rot2
	adc prod_h
	sta rot2
	jsr div24u8			; rot0:rot1 = 8.8 rise
	ldx obj_i
	clc
	+lda_mx slope_y
	adc rot1
	sta col_y			; candidate integer; rot0 = fraction
	jmp .uf_scheck
.uf_sflat
	+lda_mx slope_y
	sta col_y
	lda #0
	sta rot0
.uf_scheck
	lda col_y
	cmp floor_y
	bcc .uf_sn			; below current floor
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	sta proc_tmp0
	lda col_y
	cmp proc_tmp0
	beq .uf_sadopt			; same height
	bcc .uf_sadopt			; ramp below — landing / walk down
	sec
	sbc proc_tmp0			; rise
	cmp #STEP_UP + 1
	bcs .uf_sn			; too high — walk under
.uf_sadopt
	lda col_y
	sta floor_y
	lda rot0
	sta floor_yl
	lda proc_tmp0
	cmp col_y
	bcc .uf_done			; step-up — .ufl_up snaps
	sbc col_y			; downward gap (C=1)
	cmp #FALL_LEDGE + 1
	bcs .uf_done			; start fall; .ufl_air lands
	lda #1
	sta floor_slope
	jmp .uf_done
.uf_sn
	inx
	jmp .uf_s
.uf_done
	rts

sync_eye
	clc
	lda floor_y
	adc #EYE_HEIGHT
	sta cam_yh
	lda floor_yl
	sta cam_yl
	rts

; ------------------------------------------------------------------
; update_fall — snap if gap <= FALL_LEDGE; else accelerate down (no WASD).
; Call after update_floor. Landing: snap, maybe take_damage(FALL_DAMAGE).
; Step-up: rise <= STEP_UP snaps (SOUND_OOF at exactly 2, unless elevator).
; ------------------------------------------------------------------
update_fall
	lda pl_falling
	bne .ufl_air
	lda floor_slope
	bne .ufl_sync			; on ramp — snap 8.8, skip gap
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp floor_y
	beq .ufl_sync			; on floor
	bcc .ufl_up			; floor above feet
	sec
	sbc floor_y			; gap
	cmp #FALL_LEDGE + 1
	bcs .ufl_start
.ufl_sync
	jmp sync_eye

.ufl_up
	lda pl_on_elev
	cmp #$ff
	bne .ufl_sync			; elevator — always snap
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	sta proc_tmp0
	lda floor_y
	sec
	sbc proc_tmp0			; rise
	cmp #STEP_UP + 1
	bcc .ufl_riseok
	rts				; too high — pos_ok should have blocked
.ufl_riseok
	cmp #STEP_UP
	bne .ufl_sync			; 1-unit ledge: silent
	lda #SOUND_OOF
	jsr play_sound
	jmp .ufl_sync

.ufl_start
	lda #1
	sta pl_falling
	lda #0
	sta fall_vl
	sta fall_vh
	sta fall_acc
	lda cam_yh
	sta fall_y0

.ufl_air
	; acc16 = fall_acc + dt_ms
	clc
	lda fall_acc
	adc dt_ms
	sta proc_tmp0
	lda #0
	adc dt_msh
	sta proc_tmp1
.ufl_tick
	lda proc_tmp1
	bne .ufl_step
	lda proc_tmp0
	cmp #FALL_TICK_MS
	bcc .ufl_ticks_done
.ufl_step
	sec
	lda proc_tmp0
	sbc #FALL_TICK_MS
	sta proc_tmp0
	lda proc_tmp1
	sbc #0
	sta proc_tmp1
	clc
	lda fall_vl
	adc #<FALL_ACCEL
	sta fall_vl
	lda fall_vh
	adc #>FALL_ACCEL
	sta fall_vh
	sec
	lda cam_yl
	sbc fall_vl
	sta cam_yl
	lda cam_yh
	sbc fall_vh
	sta cam_yh
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	cmp floor_y
	beq .ufl_land
	bcc .ufl_land
	jmp .ufl_tick

.ufl_ticks_done
	lda proc_tmp0
	sta fall_acc
	; overshoot / floor rose to meet us
	sec
	lda cam_yh
	sbc #EYE_HEIGHT
	cmp floor_y
	beq .ufl_land
	bcc .ufl_land
	rts

.ufl_land
	jsr sync_eye
	lda #0
	sta pl_falling
	sta fall_vl
	sta fall_vh
	sta fall_acc
	sec
	lda fall_y0
	sbc cam_yh			; eye drop
	cmp #FALL_SAFE + 1
	bcc .ufl_rts
	lda #FALL_DAMAGE
	jsr take_damage
.ufl_rts
	rts

; ------------------------------------------------------------------
; solid_at — col_x/col_z blocked by crate, solid platform, or closed door?
; C=1 blocked
; ------------------------------------------------------------------
solid_at
	; crates — solid on Y overlap (not when on/above top or under)
	ldx #0
.sa_c
	cpx	map_ncrates
	bcs .sa_p
	+lda_mx crate_room
	cmp room_idx
	bne .sa_cn
	+lda_mx crate_y
	sta box_y
	+lda_mx crate_sy
	sta box_sy
	jsr player_overlaps_y
	bcc .sa_cn
	+lda_mx crate_x
	sta box_x
	+lda_mx crate_z
	sta box_z
	+lda_mx crate_sx
	sta box_sx
	+lda_mx crate_sz
	sta box_sz
	jsr point_in_box_xz
	bcs .sa_yes
.sa_cn
	inx
	beq .sa_p
	jmp .sa_c
.sa_p
	; platforms — solid on Y overlap (plane as sy=0)
	ldx #0
.sa_pl
	cpx	map_nplats
	bcs .sa_d
	+lda_mx plat_solid
	beq .sa_pn
	+lda_mx plat_room
	cmp room_idx
	bne .sa_pn
	+lda_mx plat_y
	sta box_y
	lda #0
	sta box_sy
	jsr player_overlaps_y
	bcc .sa_pn
	+lda_mx plat_x
	sta box_x
	+lda_mx plat_z
	sta box_z
	+lda_mx plat_sx
	sta box_sx
	+lda_mx plat_sz
	sta box_sz
	jsr point_in_box_xz
	bcs .sa_yes
.sa_pn
	inx
	beq .sa_d
	jmp .sa_pl
.sa_d
	jmp door_blocks
.sa_yes
	sec
	rts

; ------------------------------------------------------------------
; point_in_rc_xz — col_x/col_z vs collider X (exclusive max). C=1 inside
; ------------------------------------------------------------------
point_in_rc_xz
	+lda_mx rc_sx
	beq .prc_no
	lda col_x
	+cmp_mx rc_x
	bcc .prc_no
	clc
	+lda_mx rc_x
	+adc_mx rc_sx
	cmp col_x
	bcc .prc_no
	beq .prc_no
	lda col_z
	+cmp_mx rc_z
	bcc .prc_no
	clc
	+lda_mx rc_z
	+adc_mx rc_sz
	cmp col_z
	bcc .prc_no
	beq .prc_no
	sec
	rts
.prc_no
	clc
	rts

; X = collider index. C=1 inside inset by PLAYER_R.
; Faces shared with another collider in this room are not inset, so L/T/S joins stay walkable.
; proc_tmp5 = room*3 (group base).
rc_inset_ok
	+lda_mx rc_sx
	bne .rio_go
	jmp .rio_no
.rio_go
	stx proc_tmp3
	lda col_x
	jsr .rio_join_xmin
	bcs .rio_x0
	sec
	sbc #PLAYER_R
	bcc .rio_no
.rio_x0
	+cmp_mx rc_x
	bcc .rio_no
	clc
	+lda_mx rc_x
	+adc_mx rc_sx
	jsr .rio_join_xmax
	bcs .rio_x1
	sec
	sbc #PLAYER_R
.rio_x1
	cmp col_x
	bcc .rio_no
	beq .rio_no
	lda col_z
	jsr .rio_join_zmin
	bcs .rio_z0
	sec
	sbc #PLAYER_R
	bcc .rio_no
.rio_z0
	+cmp_mx rc_z
	bcc .rio_no
	clc
	+lda_mx rc_z
	+adc_mx rc_sz
	jsr .rio_join_zmax
	bcs .rio_z1
	sec
	sbc #PLAYER_R
.rio_z1
	cmp col_z
	bcc .rio_no
	beq .rio_no
	sec
	rts
.rio_no
	clc
	rts

; C=1 skip inset (shared face with any sibling). A preserved.
.rio_join_xmin
	pha
	ldy proc_tmp5
	jsr .rio_xmin_one
	bcs .rj_xmin_y
	iny
	jsr .rio_xmin_one
	bcs .rj_xmin_y
	iny
	jsr .rio_xmin_one
	bcs .rj_xmin_y
	pla
	clc
	rts
.rj_xmin_y
	pla
	sec
	rts
.rio_xmin_one
	tya
	cmp proc_tmp3
	beq .rio_xmin_n
	+lda_my rc_sx
	beq .rio_xmin_n
	clc
	+lda_my rc_x
	+adc_my rc_sx
	+cmp_mx rc_x
	bne .rio_xmin_n
	jmp .rio_ovz
.rio_xmin_n
	clc
	rts
.rio_join_xmax
	pha
	ldy proc_tmp5
	jsr .rio_xmax_one
	bcs .rj_xmax_y
	iny
	jsr .rio_xmax_one
	bcs .rj_xmax_y
	iny
	jsr .rio_xmax_one
	bcs .rj_xmax_y
	pla
	clc
	rts
.rj_xmax_y
	pla
	sec
	rts
.rio_xmax_one
	tya
	cmp proc_tmp3
	beq .rio_xmax_n
	+lda_my rc_sx
	beq .rio_xmax_n
	clc
	+lda_mx rc_x
	+adc_mx rc_sx
	+cmp_my rc_x
	bne .rio_xmax_n
	jmp .rio_ovz
.rio_xmax_n
	clc
	rts
.rio_join_zmin
	pha
	ldy proc_tmp5
	jsr .rio_zmin_one
	bcs .rj_zmin_y
	iny
	jsr .rio_zmin_one
	bcs .rj_zmin_y
	iny
	jsr .rio_zmin_one
	bcs .rj_zmin_y
	pla
	clc
	rts
.rj_zmin_y
	pla
	sec
	rts
.rio_zmin_one
	tya
	cmp proc_tmp3
	beq .rio_zmin_n
	+lda_my rc_sx
	beq .rio_zmin_n
	clc
	+lda_my rc_z
	+adc_my rc_sz
	+cmp_mx rc_z
	bne .rio_zmin_n
	jmp .rio_ovx
.rio_zmin_n
	clc
	rts
.rio_join_zmax
	pha
	ldy proc_tmp5
	jsr .rio_zmax_one
	bcs .rj_zmax_y
	iny
	jsr .rio_zmax_one
	bcs .rj_zmax_y
	iny
	jsr .rio_zmax_one
	bcs .rj_zmax_y
	pla
	clc
	rts
.rj_zmax_y
	pla
	sec
	rts
.rio_zmax_one
	tya
	cmp proc_tmp3
	beq .rio_zmax_n
	+lda_my rc_sx
	beq .rio_zmax_n
	clc
	+lda_mx rc_z
	+adc_mx rc_sz
	+cmp_my rc_z
	bne .rio_zmax_n
	jmp .rio_ovx
.rio_zmax_n
	clc
	rts

.rio_ovx
	clc
	+lda_my rc_x
	+adc_my rc_sx
	+cmp_mx rc_x
	beq .rovx_no
	bcc .rovx_no
	clc
	+lda_mx rc_x
	+adc_mx rc_sx
	+cmp_my rc_x
	beq .rovx_no
	bcc .rovx_no
	sec
	rts
.rovx_no
	clc
	rts
.rio_ovz
	clc
	+lda_my rc_z
	+adc_my rc_sz
	+cmp_mx rc_z
	beq .rovz_no
	bcc .rovz_no
	clc
	+lda_mx rc_z
	+adc_mx rc_sz
	+cmp_my rc_z
	beq .rovz_no
	bcc .rovz_no
	sec
	rts
.rovz_no
	clc
	rts

; ------------------------------------------------------------------
; col_in_room_y — col_x/col_z inside room Y colliders. C=1 inside
; ------------------------------------------------------------------
col_in_room_y
	cpy #$ff
	beq .cir_no
	stx pv4
	tya
	jsr room_mul3
	tax
	jsr point_in_rc_xz
	bcs .cir_yes
	inx
	jsr point_in_rc_xz
	bcs .cir_yes
	inx
	jsr point_in_rc_xz
.cir_yes
	php
	ldx pv4
	plp
	rts
.cir_no
	clc
	rts

; Y = room. C=1 if col_x/z in a collider inset by 1 (enemy)
room_cols_inset1
	stx pv4
	tya
	jsr room_mul3
	tax
	jsr .rci1
	bcs .rci_yes
	inx
	jsr .rci1
	bcs .rci_yes
	inx
	jsr .rci1
.rci_yes
	php
	ldx pv4
	plp
	rts
.rci1
	+lda_mx rc_sx
	beq .rci_no
	lda col_x
	+cmp_mx rc_x
	bcc .rci_no
	beq .rci_no			; inset lo: >
	clc
	+lda_mx rc_x
	+adc_mx rc_sx
	sec
	sbc #1
	cmp col_x
	bcc .rci_no
	beq .rci_no
	lda col_z
	+cmp_mx rc_z
	bcc .rci_no
	beq .rci_no
	clc
	+lda_mx rc_z
	+adc_mx rc_sz
	sec
	sbc #1
	cmp col_z
	bcc .rci_no
	beq .rci_no
	sec
	rts
.rci_no
	clc
	rts

; ------------------------------------------------------------------
; in_room_or_portal — col_x/col_z allowed for room_idx?
; Inside a collider inset by PLAYER_R (shared faces not inset), or open door hole.
; C=1 allowed
; ------------------------------------------------------------------
in_room_or_portal
	lda room_idx
	jsr room_mul3
	tax
	jsr rc_inset_ok
	bcs .irp_yes
	inx
	jsr rc_inset_ok
	bcs .irp_yes
	inx
	jsr rc_inset_ok
	bcs .irp_yes
	jmp door_portal_ok
.irp_yes
	sec
	rts

; ------------------------------------------------------------------
; pos_ok — cam would be ok at col_x/col_z
; ------------------------------------------------------------------
pos_ok
	jsr in_room_or_portal
	bcc .po_no
	jsr solid_at
	bcs .po_no
	jmp step_up_ok
.po_no
	clc
	rts

; Dest room floor vs feet. C=1 ok (no floor, lower, or rise <= STEP_UP).
step_up_ok
	ldy room_idx
	jsr peek_rc_floor
	bcc .suo_yes			; portal hole / no collider
	sec
	lda cam_yh
	sbc #EYE_HEIGHT			; feet
	sta proc_tmp1
	lda proc_tmp2			; dest floor
	cmp proc_tmp1
	beq .suo_yes
	bcc .suo_yes			; dest lower — fall later
	sec
	sbc proc_tmp1			; rise
	cmp #STEP_UP + 1
	bcc .suo_yes
	clc
	rts
.suo_yes
	sec
	rts

; ------------------------------------------------------------------
; Horizontal move from IRQ hold-ms wish (8 units/s). Slide on X then Z.
; ------------------------------------------------------------------
apply_move_world
	lda pl_falling
	beq .am_go
	rts
.am_go
	ldy yaw
	lda SINTAB,y
	sta rot0
	ldy yaw
	lda COSTAB,y
	sta rot1

	lda hold_fwd
	ora hold_fwd + 1
	beq .am_now
	lda hold_fwd
	sta vel_ms
	lda hold_fwd + 1
	sta vel_msh
	lda rot0
	jsr wish_add_x
	lda rot1
	jsr wish_add_z
.am_now
	lda hold_back
	ora hold_back + 1
	beq .am_nos
	lda hold_back
	sta vel_ms
	lda hold_back + 1
	sta vel_msh
	lda rot0
	jsr neg_a
	jsr wish_add_x
	lda rot1
	jsr neg_a
	jsr wish_add_z
.am_nos
	lda hold_strafer
	ora hold_strafer + 1
	beq .am_nod
	lda hold_strafer
	sta vel_ms
	lda hold_strafer + 1
	sta vel_msh
	lda rot1
	jsr wish_add_x
	lda rot0
	jsr neg_a
	jsr wish_add_z
.am_nod
	lda hold_strafel
	ora hold_strafel + 1
	beq .am_noa
	lda hold_strafel
	sta vel_ms
	lda hold_strafel + 1
	sta vel_msh
	lda rot1
	jsr neg_a
	jsr wish_add_x
	lda rot0
	jsr wish_add_z
.am_noa
	lda cam_xl
	sta rot0			; start 8.8 XZ (HITWALL if fully blocked)
	lda cam_xh
	sta rot1
	lda cam_zl
	sta rot2
	lda cam_zh
	sta dt_tmp
	lda cam_xl
	sta save_xl
	lda cam_xh
	sta save_xh
	lda cam_zl
	sta save_zl
	lda cam_zh
	sta save_zh

	clc
	lda cam_xl
	adc wish_dx
	sta cam_xl
	lda cam_xh
	adc wish_dxh
	sta cam_xh
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr pos_ok
	bcs .am_zx
	lda save_xl
	sta cam_xl
	lda save_xh
	sta cam_xh
.am_zx
	lda cam_xh
	sta save_xh
	lda cam_xl
	sta save_xl
	clc
	lda cam_zl
	adc wish_dz
	sta cam_zl
	lda cam_zh
	adc wish_dzh
	sta cam_zh
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr pos_ok
	bcs .am_done
	lda save_zl
	sta cam_zl
	lda save_zh
	sta cam_zh
.am_done
	lda wish_dx
	ora wish_dxh
	ora wish_dz
	ora wish_dzh
	beq .am_sw
	lda cam_xl
	cmp rot0
	bne .am_sw
	lda cam_xh
	cmp rot1
	bne .am_sw
	lda cam_zl
	cmp rot2
	bne .am_sw
	lda cam_zh
	cmp dt_tmp
	bne .am_sw
	lda #SOUND_HITWALL
	jsr play_sound
.am_sw
	jsr try_room_switch
	rts

; A = signed sintab → add (A * vel_ms)>>6 into wish X 8.8
wish_add_x
	jsr scale_vel_7
	clc
	lda wish_dx
	adc nlo
	sta wish_dx
	lda wish_dxh
	adc nhi
	sta wish_dxh
	rts

wish_add_z
	jsr scale_vel_7
	clc
	lda wish_dz
	adc nlo
	sta wish_dz
	lda wish_dzh
	adc nhi
	sta wish_dzh
	rts

; A signed, vel_ms:vel_msh → nlo:nhi = (A * vel) >> 6  (~8 units/s)
scale_vel_7
	sta scale_s
	bpl .svabs
	eor #$ff
	clc
	adc #1
.svabs
	sta hud_n			; |A|
	tay
	lda vel_ms
	jsr umul8j
	lda prod_l
	sta nlo
	lda prod_h
	sta nhi
	lda vel_msh
	beq .svsh
	ldy hud_n
	jsr umul8j			; |A| * vel_hi
	clc
	lda nhi
	adc prod_l
	sta nhi
	lda prod_h
	adc #0
	sta pp_tmp_h			; product bits 16–23
	ldx #6
.svsh24
	lsr pp_tmp_h
	ror nhi
	ror nlo
	dex
	bne .svsh24
	jmp .svsign
.svsh
	lda nhi
	ldx #6
.svsh16
	lsr
	ror nlo
	dex
	bne .svsh16
	sta nhi
.svsign
	lda scale_s
	bpl .svok
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.svok
	rts

neg_a
	eor #$ff
	clc
	adc #1
	rts

; ------------------------------------------------------------------
; Proximity: doors + switches (K) + automatic elevators
; ------------------------------------------------------------------
SW_USE_RANGE	= 4			; max XZ distance to switch AABB

try_proximity
	jsr try_door_proximity
	; K rising edge — one fire per press
	lda key_use
	bne .tp_kd
	sta key_use_was			; A = 0
	jmp .tp_el
.tp_kd
	lda key_use_was
	bne .tp_el			; still held
	lda #1
	sta key_use_was
	ldx #0
.tp_s
	cpx	map_nswitches
	bcs .tp_el
	stx obj_i
	+lda_mx sw_room
	cmp room_idx
	bne .tp_sn
	jsr .prox_switch
	bcc .tp_sn
	+ldy_mx sw_elev
	tya
	tax
	jsr elev_activate
	bcs .tp_el
	lda #SOUND_SWITCH
	jsr play_sound
	jmp .tp_el			; one switch per press
.tp_sn
	ldx obj_i
	inx
	bne .tp_s
.tp_el
	jsr elev_try_auto
	jsr try_backpack_pickup
.tp_rts
	rts

; Walk-over backpacks: grant if not full / not already owned
try_backpack_pickup
	ldx #0
.tbp_lp
	cpx	map_nbackpacks
	bcs .tbp_rts
	stx obj_i
	lda bp_taken,x
	bne .tbp_n
	+lda_mx bp_room
	cmp room_idx
	bne .tbp_n
	+lda_mx bp_x
	sta box_x
	+lda_mx bp_y
	sta box_y
	+lda_mx bp_z
	sta box_z
	lda #BP_FOOT_SX
	sta box_sx
	lda #BP_FOOT_SY
	sta box_sy
	lda #BP_FOOT_SZ
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .tbp_n
	jsr player_overlaps_y
	bcc .tbp_n
	ldx obj_i
	jsr grant_backpack
	bcc .tbp_n
	jsr hud_ammo
	ldx obj_i
	+lda_mx bp_type
	jsr hud_got
	ldx obj_i
	+lda_mx bp_type
	jsr pickup_sound
	ldx obj_i
	lda #1
	sta bp_taken,x
.tbp_n
	ldx obj_i
	inx
	beq .tbp_rts
	jmp .tbp_lp
.tbp_rts
	; death-drop backpacks
	ldx #0
.tdp_lp
	cpx	map_nenemies
	bcs .tdp_rts
	stx obj_i
	lda drop_taken,x
	bne .tdp_n
	lda drop_room,x
	cmp room_idx
	bne .tdp_n
	lda drop_x,x
	sta box_x
	lda drop_y,x
	sta box_y
	lda drop_z,x
	sta box_z
	lda #BP_FOOT_SX
	sta box_sx
	lda #BP_FOOT_SY
	sta box_sy
	lda #BP_FOOT_SZ
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr point_in_box_xz
	bcc .tdp_n
	jsr player_overlaps_y
	bcc .tdp_n
	ldx obj_i
	lda drop_type,x
	jsr grant_bp_type
	bcc .tdp_n
	jsr hud_ammo
	ldx obj_i
	lda drop_type,x
	jsr hud_got
	ldx obj_i
	lda #1
	sta drop_taken,x
	lda #SOUND_GETAMMO
	jsr play_sound
.tdp_n
	ldx obj_i
	inx
	beq .tdp_rts
	jmp .tdp_lp
.tdp_rts
	rts

; X = backpack index; C=1 granted
grant_backpack
	+lda_mx bp_type
; A = BP_* type; C=1 granted
grant_bp_type
	cmp #BP_NTYPES
	bcc .gb_go
	clc
	rts
.gb_go
	tay
	lda gb_lo,y
	sta rot0
	lda gb_hi,y
	sta rot1
	jmp (rot0)

gb_lo
	!byte <gb_shells, <gb_nailgun, <gb_nails, <gb_grenlaunch
	!byte <gb_grenades, <gb_hp25, <gb_hp50, <gb_shells5, <gb_armour
	!byte <gb_quad, <gb_pent, <gb_ring, <gb_silver, <gb_gold, <gb_rune
gb_hi
	!byte >gb_shells, >gb_nailgun, >gb_nails, >gb_grenlaunch
	!byte >gb_grenades, >gb_hp25, >gb_hp50, >gb_shells5, >gb_armour
	!byte >gb_quad, >gb_pent, >gb_ring, >gb_silver, >gb_gold, >gb_rune

gb_hp25
	lda player_hp
	cmp #PLAYER_HP_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #HP_PACK_25
	jmp gb_hp_clamp
gb_hp50
	lda player_hp
	cmp #PLAYER_HP_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #HP_PACK_50
gb_hp_clamp
	bcs gb_hp_cap
	cmp #PLAYER_HP_MAX
	bcc gb_hp_ok
	beq gb_hp_ok
gb_hp_cap
	lda #PLAYER_HP_MAX
gb_hp_ok
	sta player_hp
	sec
	rts
gb_shells
	lda #AMMO_SHELLS_BOX
	bne gb_add_shells
gb_shells5
	lda #AMMO_SHELLS_DEATH
gb_add_shells
	sta rot2
	lda ammo_shells
	cmp #AMMO_SHELLS_MAX
	bcc +
	jmp gb_no
+
	clc
	adc rot2
	bcs gb_shell_cap
	cmp #AMMO_SHELLS_MAX
	bcc gb_shell_ok
	beq gb_shell_ok
gb_shell_cap
	lda #AMMO_SHELLS_MAX
gb_shell_ok
	sta ammo_shells
	sec
	rts
gb_nails
	lda ammo_nails
	cmp #AMMO_NAILS_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #AMMO_NAILS_BOX
	bcs gb_nail_cap
	cmp #AMMO_NAILS_MAX
	bcc gb_nail_ok
	beq gb_nail_ok
gb_nail_cap
	lda #AMMO_NAILS_MAX
gb_nail_ok
	sta ammo_nails
	sec
	rts
gb_grenades
	lda ammo_grenades
	cmp #AMMO_GRENADES_MAX
	bcc +
	jmp gb_no
+
	clc
	adc #AMMO_GRENADES_BOX
	bcs gb_gren_cap
	cmp #AMMO_GRENADES_MAX
	bcc gb_gren_ok
	beq gb_gren_ok
gb_gren_cap
	lda #AMMO_GRENADES_MAX
gb_gren_ok
	sta ammo_grenades
	sec
	rts
gb_nailgun
	lda have_wpn
	and #HAVE_NAIL
	beq gb_ng_new
	jmp gb_no
gb_ng_new
	lda have_wpn
	ora #HAVE_NAIL
	sta have_wpn
	lda ammo_nails
	clc
	adc #AMMO_NAILS_GUN
	bcs gb_ng_cap
	cmp #AMMO_NAILS_MAX
	bcc gb_ng_ok
	beq gb_ng_ok
gb_ng_cap
	lda #AMMO_NAILS_MAX
gb_ng_ok
	sta ammo_nails
	ldx #WPN_NAIL
	jsr switch_weapon
	sec
	rts
gb_grenlaunch
	lda have_wpn
	and #HAVE_GREN
	beq gb_gl_new
	jmp gb_no
gb_gl_new
	lda have_wpn
	ora #HAVE_GREN
	sta have_wpn
	lda ammo_grenades
	clc
	adc #AMMO_GRENADES_GUN
	bcs gb_gl_cap
	cmp #AMMO_GRENADES_MAX
	bcc gb_gl_ok
	beq gb_gl_ok
gb_gl_cap
	lda #AMMO_GRENADES_MAX
gb_gl_ok
	sta ammo_grenades
	ldx #WPN_GREN
	jsr switch_weapon
	sec
	rts
gb_armour
	lda player_armour
	cmp #PLAYER_ARMOUR_MAX
	bcs gb_no
	lda #PLAYER_ARMOUR_MAX
	sta player_armour
	sec
	rts
gb_quad
	lda #BP_QUAD
	bne gb_pu_set
gb_pent
	lda #BP_PENT
	bne gb_pu_set
gb_ring
	lda #BP_RING
gb_pu_set
	sta pu_kind
	lda #<POWERUP_MS
	sta pu_ms_l
	lda #>POWERUP_MS
	sta pu_ms_h
	jsr hud_powerup
	sec
	rts
gb_silver
	lda have_keys
	and #HAVE_SILVER
	bne gb_no
	lda have_keys
	ora #HAVE_SILVER
	sta have_keys
	sec
	rts
gb_gold
	lda have_keys
	and #HAVE_GOLD
	bne gb_no
	lda have_keys
	ora #HAVE_GOLD
	sta have_keys
	sec
	rts
gb_rune
	lda have_keys
	and #HAVE_EARTH
	bne gb_no
	lda have_keys
	ora #HAVE_EARTH
	sta have_keys
	sec
	rts
gb_no
	clc
	rts

; A = BP_* — health / ammo / bonus / key
pickup_sound
	cmp #BP_HEALTH25
	beq .ps_hp
	cmp #BP_HEALTH50
	beq .ps_hp
	cmp #BP_QUAD
	bcc .ps_ammo
	cmp #BP_SILVER
	bcc .ps_bonus
	lda #SOUND_GETKEY
	jmp play_sound
.ps_bonus
	lda #SOUND_BONUS1
	jmp play_sound
.ps_ammo
	lda #SOUND_GETAMMO
	jmp play_sound
.ps_hp
	cmp #BP_HEALTH50
	beq .ps_hp2
	lda #SOUND_HEALTH1
	jmp play_sound
.ps_hp2
	lda #SOUND_HEALTH2
	jmp play_sound

; X=switch; C=1 if within SW_USE_RANGE of pad XZ, Y overlaps, facing the face
.prox_switch
	stx obj_i
	+lda_mx sw_x
	sta box_x
	+lda_mx sw_z
	sta box_z
	+lda_mx sw_sx
	sta box_sx
	+lda_mx sw_sz
	sta box_sz
	lda cam_xh
	sta col_x
	lda cam_zh
	sta col_z
	jsr near_box_xz
	bcc .ps_no
	ldx obj_i
	+lda_mx sw_y
	sta box_y
	+lda_mx sw_sy
	sta box_sy
	jsr player_overlaps_y
	bcc .ps_no
	ldx obj_i
	jsr .switch_facing
	ldx obj_i
	rts
.ps_no
	clc
	ldx obj_i
	rts

; col_x/col_z within SW_USE_RANGE of [box_x,box_x+sx) × [box_z,box_z+sz)
; Chebyshev: each axis distance to AABB ≤ SW_USE_RANGE. C=1 near.
near_box_xz
	lda col_x
	cmp box_x
	bcc .nb_xlo
	clc
	lda box_x
	adc box_sx
	sta col_y
	lda col_x
	cmp col_y
	bcs .nb_xhi
	lda #0
	beq .nb_xd
.nb_xlo
	lda box_x
	sec
	sbc col_x
	jmp .nb_xd
.nb_xhi
	lda col_x
	sec
	sbc col_y
.nb_xd
	cmp #SW_USE_RANGE + 1
	bcs .nb_no
	lda col_z
	cmp box_z
	bcc .nb_zlo
	clc
	lda box_z
	adc box_sz
	sta col_y
	lda col_z
	cmp col_y
	bcs .nb_zhi
	lda #0
	beq .nb_zd
.nb_zlo
	lda box_z
	sec
	sbc col_z
	jmp .nb_zd
.nb_zhi
	lda col_z
	sec
	sbc col_y
.nb_zd
	cmp #SW_USE_RANGE + 1
	bcs .nb_no
	sec
	rts
.nb_no
	clc
	rts

; X=switch; C=1 if yaw within ±90° of sw_face (0=+Z, 64=+X, 128=-Z, 192=-X)
.switch_facing
	+lda_mx sw_face
	cmp #FACE_PX
	bcs .sf_x
	cmp #FACE_MZ
	beq .sf_mz
	; FACE_PZ: yaw < 64 or >= 192
	lda yaw
	cmp #64
	bcc .sf_yes
	cmp #192
	bcs .sf_yes
	clc
	rts
.sf_mz
	lda yaw
	cmp #64
	bcc .sf_no
	cmp #192
	bcc .sf_yes
.sf_no
	clc
	rts
.sf_x
	cmp #FACE_MX
	beq .sf_mx
	; FACE_PX: 0..127
	lda yaw
	cmp #128
	bcc .sf_yes
	clc
	rts
.sf_mx
	lda yaw
	cmp #128
	bcs .sf_yes
	clc
	rts
.sf_yes
	sec
	rts

; ------------------------------------------------------------------
; update_triggers — first overlapping volume in the active room (XZ).
; Message: HUD while inside. Hurt: 10 HP on enter, then every HURT_MS.
; End of level / teleport / elevator: once on entry until leave.
; ------------------------------------------------------------------
update_triggers
	ldx #0
.ut
	cpx	map_ntrigs
	bcs .ut_miss
	+lda_mx tr_room
	cmp room_idx
	bne .ut_n
	+lda_mx tr_x
	sta box_x
	+lda_mx tr_y
	sta box_y
	+lda_mx tr_z
	sta box_z
	+lda_mx tr_sx
	sta box_sx
	+lda_mx tr_sy
	sta box_sy
	+lda_mx tr_sz
	sta box_sz
	lda cam_xh
	cmp box_x
	bcc .ut_n
	clc
	lda box_x
	adc box_sx
	cmp cam_xh
	bcc .ut_n
	beq .ut_n
	lda cam_zh
	cmp box_z
	bcc .ut_n
	clc
	lda box_z
	adc box_sz
	cmp cam_zh
	bcc .ut_n
	beq .ut_n
	stx pv0				; hit index
	jmp .ut_apply
.ut_n
	inx
	beq .ut_miss
	jmp .ut
.ut_miss
	lda #$ff
	sta pv0
.ut_apply
	lda pv0
	cmp trig_inside
	beq .ut_same
	sta trig_inside
	cmp #$ff
	bne .ut_enter
	lda msg_on
	beq .ut_done
	lda #0
	sta msg_on
	jmp hud_msg_blank
.ut_enter
	ldx pv0
	jmp trig_enter
.ut_same
	lda trig_inside
	cmp #$ff
	beq .ut_done
	tax
	+lda_mx tr_purpose
	cmp #TRIG_MSG
	beq .ut_msghold
	cmp #TRIG_HURT
	beq .ut_hurttick
.ut_done
	rts
.ut_msghold
	lda msg_on
	cmp #1
	bne .ut_msgdraw
	+lda_mx tr_arg
	cmp msg_off
	beq .ut_done
.ut_msgdraw
	lda #1
	sta msg_on
	+lda_mx tr_arg
	sta msg_off
	jmp hud_message
.ut_hurttick
	sec
	lda hurt_ms_l
	sbc dt_ms
	sta hurt_ms_l
	lda hurt_ms_h
	sbc dt_msh
	sta hurt_ms_h
	bcs .ut_done
	lda #<HURT_MS
	sta hurt_ms_l
	lda #>HURT_MS
	sta hurt_ms_h
	lda #HURT_HP
	jmp take_damage

; X = trigger SoA. On-entry dispatch.
trig_enter
	+lda_mx tr_purpose
	cmp #TRIG_MSG
	beq .te_msg
	lda msg_on
	beq .te_act
	lda #0
	sta msg_on
	stx obj_i
	jsr hud_msg_blank
	ldx obj_i
.te_act
	+lda_mx tr_purpose
	cmp #TRIG_HURT
	beq .te_hurt
	cmp #TRIG_TELE
	beq .te_tele
	cmp #TRIG_ELEV
	beq .te_elev
	cmp #TRIG_END
	bne .te_rts
	jmp next_level
.te_rts
	rts
.te_msg
	lda #1
	sta msg_on
	+lda_mx tr_arg
	sta msg_off
	jmp hud_message
.te_hurt
	lda #<HURT_MS
	sta hurt_ms_l
	lda #>HURT_MS
	sta hurt_ms_h
	lda #HURT_HP
	jmp take_damage
.te_elev
	+lda_mx tr_arg
	tax
	jmp elev_activate
.te_tele
	lda map_ndests
	beq .te_tele_rts
	+ldy_mx tr_arg
	lda #0
	sta cam_xl
	sta cam_zl
	sta cam_yl
	+lda_my td_x
	sta cam_xh
	+lda_my td_z
	sta cam_zh
	clc
	+lda_my td_y
	adc #EYE_HEIGHT
	sta cam_yh
	+lda_my td_rot
	asl
	asl
	asl
	asl
	asl
	sta yaw
	+lda_my td_room
	jsr set_room_idx
	lda #$ff
	sta pl_on_elev
	lda #0
	sta pl_falling
	sta fall_vl
	sta fall_vh
	jsr update_floor
	jmp sync_eye
.te_tele_rts
	rts
