; Bouncing grenades: player GL + ogre. Faction owner (contact skips allies;
; splash does not). One explosion at a time via fx_on.
; Compact bounce/splash/view-dart (no wrist, no last-vel).
!zone grenade

init_grenades
	ldx #GREN_MAX - 1
	lda #0
.ig
	sta gr_on,x
	dex
	bpl .ig
	rts

; C=1 X=free slot; C=0 full
gren_alloc
	ldx #0
.ga
	lda gr_on,x
	beq .ga_ok
	inx
	cpx #GREN_MAX
	bcc .ga
	clc
	rts
.ga_ok
	sec
	rts

; A = yaw. X = slot. Horizontal GREN_SPEED, upward GREN_SPEED_Y.
gren_set_vel
	stx obj_i
	sta rot2
	tay
	lda SINTAB,y
	ldy #GREN_SPEED
	jsr smul7
	ldx obj_i
	sta gr_vxh,x
	lda #0
	sta gr_vxl,x
	ldy rot2
	lda COSTAB,y
	ldy #GREN_SPEED
	jsr smul7
	ldx obj_i
	sta gr_vzh,x
	lda #0
	sta gr_vzl,x
	lda #GREN_SPEED_Y
	sta gr_vyh,x
	lda #0
	sta gr_vyl,x
	rts

; X=slot. org_* = pos. rot2 = aim yaw. A = owner.
gren_fill_slot
	sta gr_owner,x
	lda org_xl
	sta gr_xl,x
	lda org_xh
	sta gr_xh,x
	lda org_yl
	sta gr_yl,x
	lda org_yh
	sta gr_yh,x
	lda org_zl
	sta gr_zl,x
	lda org_zh
	sta gr_zh,x
	lda #0
	sta gr_flags,x
	sta gr_acc,x
	sta gr_fuse_l,x
	sta gr_fuse_h,x
	lda #<GREN_LIFE_MS
	sta gr_life_l,x
	lda #>GREN_LIFE_MS
	sta gr_life_h,x
	lda #1
	sta gr_on,x
	lda rot2
	jmp gren_set_vel

; Player center: cam xz, Y = feet + 2 (eye − (EYE_HEIGHT − 2)).
spawn_player_grenade
	jsr gren_alloc
	bcc .spg_rts
	stx obj_i
	lda cam_xl
	sta org_xl
	lda cam_xh
	sta org_xh
	lda cam_zl
	sta org_zl
	lda cam_zh
	sta org_zh
	lda cam_yl
	sta org_yl
	lda cam_yh
	sec
	sbc #EYE_HEIGHT - 2
	sta org_yh
	ldx obj_i
	lda room_idx
	sta gr_room,x
	lda yaw
	sta rot2
	lda #GREN_OWN_PL
	jsr gren_fill_slot
.spg_rts
	rts

spawn_ogre_grenade
	ldx enemy_idx
	lda #0
	sta org_xl
	sta org_yl
	sta org_zl
	+lda_mx en_x
	sta org_xh
	+lda_mx en_y
	sta org_yh
	+lda_mx en_z
	sta org_zh
	jsr gren_alloc
	bcc .sog_rts
	stx obj_i
	ldx enemy_idx
	+lda_mx en_room
	ldx obj_i
	sta gr_room,x
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
	lda #SOUND_SHOOT
	jmp play_sound
.sog_rts
	rts

update_grenades
	ldx #0
.ug
	cpx #GREN_MAX
	bcs .ug_rts
	lda gr_on,x
	beq .ug_n
	jsr gren_tick
	ldx obj_i
.ug_n
	inx
	bne .ug
.ug_rts
	rts

gren_tick
	stx obj_i
	lda room_idx
	sta gren_save_room
	lda gr_room,x
	cmp gren_save_room
	beq .gt_phys
	jsr set_room_idx
	ldx obj_i
.gt_phys
	clc
	lda gr_acc,x
	adc dt_ms
	sta proc_tmp0
	lda #0
	adc dt_msh
	sta proc_tmp1
.gt_tick
	lda proc_tmp1
	bne .gt_step
	lda proc_tmp0
	cmp #GREN_TICK_MS
	bcc .gt_tdone
.gt_step
	sec
	lda proc_tmp0
	sbc #GREN_TICK_MS
	sta proc_tmp0
	lda proc_tmp1
	sbc #0
	sta proc_tmp1
	ldx obj_i
	sec
	lda gr_vyl,x
	sbc #<GREN_GRAV
	sta gr_vyl,x
	lda gr_vyh,x
	sbc #>GREN_GRAV
	sta gr_vyh,x
	jsr gren_move_x
	jsr gren_move_z
	jsr gren_move_y
	jmp .gt_tick
.gt_tdone
	ldx obj_i
	lda proc_tmp0
	sta gr_acc,x
	jsr gren_contact
	ldx obj_i
	lda gr_on,x
	beq .gt_rest
	lda gr_flags,x
	and #GREN_F_PEND
	beq .gt_fuse
	lda fx_on
	bne .gt_life
	jsr gren_explode
	jmp .gt_rest
.gt_fuse
	lda gr_flags,x
	and #GREN_F_BOUNCE
	beq .gt_life
	sec
	lda gr_fuse_l,x
	sbc dt_ms
	sta gr_fuse_l,x
	lda gr_fuse_h,x
	sbc dt_msh
	sta gr_fuse_h,x
	bcs .gt_life
	jsr gren_explode
	jmp .gt_rest
.gt_life
	ldx obj_i
	lda gr_on,x
	beq .gt_rest
	sec
	lda gr_life_l,x
	sbc dt_ms
	sta gr_life_l,x
	lda gr_life_h,x
	sbc dt_msh
	sta gr_life_h,x
	bcs .gt_rest
	jsr gren_explode
.gt_rest
	lda gren_save_room
	cmp room_idx
	beq .gt_rts
	jsr set_room_idx
.gt_rts
	rts

gren_asr_ay
	sta nlo
	sty nhi
gren_asr5
	ldy #5
.ga5
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	dey
	bne .ga5
	rts

; A = <vel_lo, Y = <vel_hi. Negate and asr1.
gren_bounce
	sta .bl+1
	sta .sl+1
	sta .rl+1
	sty .bh+1
	sty .sh+1
	sty .rh+1
	ldx obj_i
	sec
	lda #0
.bl	sbc gr_vxl,x
.sl	sta gr_vxl,x
	lda #0
.bh	sbc gr_vxh,x
.sh	sta gr_vxh,x
	cmp #$80
.rh	ror gr_vxh,x
.rl	ror gr_vxl,x
	ldx obj_i
	lda gr_flags,x
	and #GREN_F_BOUNCE
	bne .gmb_rts
	lda gr_flags,x
	ora #GREN_F_BOUNCE
	sta gr_flags,x
	lda #<GREN_FUSE_MS
	sta gr_fuse_l,x
	lda #>GREN_FUSE_MS
	sta gr_fuse_h,x
.gmb_rts
	rts

gren_move_x
	ldx obj_i
	lda gr_vxl,x
	ldy gr_vxh,x
	jsr gren_asr_ay
	clc
	lda gr_xl,x
	adc nlo
	sta save_xl
	lda gr_xh,x
	adc nhi
	sta save_xh
	sta col_x
	lda gr_zh,x
	sta col_z
	lda #0
	beq gren_xz_done

gren_move_z
	ldx obj_i
	lda gr_vzl,x
	ldy gr_vzh,x
	jsr gren_asr_ay
	clc
	lda gr_zl,x
	adc nlo
	sta save_xl
	lda gr_zh,x
	adc nhi
	sta save_xh
	lda gr_xh,x
	sta col_x
	lda save_xh
	sta col_z
	lda #1
gren_xz_done
	sta pv2
	jsr gren_pos_ok
	bcs .ok
	lda pv2
	bne .bz
	lda #<gr_vxl
	ldy #<gr_vxh
	jmp gren_bounce
.bz
	lda #<gr_vzl
	ldy #<gr_vzh
	jmp gren_bounce
.ok
	ldx obj_i
	lda pv2
	bne .sz
	lda save_xl
	sta gr_xl,x
	lda save_xh
	sta gr_xh,x
	jmp gren_try_room
.sz
	lda save_xl
	sta gr_zl,x
	lda save_xh
	sta gr_zh,x
	jmp gren_try_room

gren_move_y
	ldx obj_i
	lda gr_vyl,x
	ldy gr_vyh,x
	jsr gren_asr_ay
	clc
	lda gr_yl,x
	adc nlo
	sta save_xl
	lda gr_yh,x
	adc nhi
	sta save_xh
	lda gr_vyh,x
	bmi .gmy_down
	ldy gr_room,x
	jsr load_box_room
	clc
	lda box_y
	adc box_sy
	cmp save_xh
	beq .gmy_ceil
	bcc .gmy_ceil
	jmp gren_try_y
.gmy_ceil
	lda #<gr_vyl
	ldy #<gr_vyh
	jmp gren_bounce
.gmy_down
	jsr gren_col_xz
	ldx obj_i
	lda gr_yh,x
	sta rot2
	jsr floor_below
	bcc gren_try_y
	lda proc_tmp2
	cmp save_xh
	beq .gmy_land
	bcc gren_try_y
.gmy_land
	ldx obj_i
	lda #0
	sta gr_yl,x
	lda proc_tmp2
	sta gr_yh,x
	lda #<gr_vyl
	ldy #<gr_vyh
	jmp gren_bounce

gren_try_y
	ldx obj_i
	lda gr_yl,x
	sta pv0
	lda gr_yh,x
	sta pv1
	lda save_xl
	sta gr_yl,x
	lda save_xh
	sta gr_yh,x
	jsr gren_col_xz
	jsr gren_solid_at
	ldx obj_i
	bcc .gty_ok
	lda pv0
	sta gr_yl,x
	lda pv1
	sta gr_yh,x
	lda #<gr_vyl
	ldy #<gr_vyh
	jmp gren_bounce
.gty_ok
	rts

gren_col_xz
	ldx obj_i
	lda gr_xh,x
	sta col_x
	lda gr_zh,x
	sta col_z
	rts

; C=1 allowed
gren_pos_ok
	jsr in_room_or_portal
	bcc .gpo_no
	jsr gren_solid_at
	bcs .gpo_no
	sec
	rts
.gpo_no
	clc
	rts

; Point as player AABB of height PLAYER_H at grenade Y (feet).
gren_solid_at
	lda cam_yh
	pha
	ldx obj_i
	clc
	lda gr_yh,x
	adc #EYE_HEIGHT
	sta cam_yh
	jsr solid_at
	pla
	sta cam_yh
	rts

gren_try_room
	ldx obj_i
	lda cam_xh
	pha
	lda cam_zh
	pha
	lda gr_xh,x
	sta cam_xh
	lda gr_zh,x
	sta cam_zh
	jsr try_room_switch
	ldx obj_i
	lda room_idx
	sta gr_room,x
	pla
	sta cam_zh
	pla
	sta cam_xh
	rts

gren_contact
	ldx obj_i
	lda gr_owner,x
	bne gren_hit_player

gren_hit_enemies
	ldx #0
.ghe
	cpx	map_nenemies
	bcs .ghe_rts
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcs .ghe_n
	+lda_mx en_x
	sta pv0
	+lda_mx en_z
	sta pv1
	jsr gren_near_xz
	bcs .ghe_n
	ldx enemy_idx
	+lda_mx en_y
	sta pv0
	clc
	adc #ENEMY_CULL_H
	sta pv1
	jsr gren_in_y
	bcc .ghe_n
	jmp gren_explode
.ghe_n
	ldx enemy_idx
	inx
	bne .ghe
.ghe_rts
	rts

gren_hit_player
	lda cam_xh
	sta pv0
	lda cam_zh
	sta pv1
	jsr gren_near_xz
	bcs .ghp_rts
	lda cam_yh
	sec
	sbc #EYE_HEIGHT
	sta pv0
	clc
	adc #PLAYER_H
	sta pv1
	jsr gren_in_y
	bcc .ghp_rts
	jmp gren_explode
.ghp_rts
	rts

; pv0/pv1 = other x/z. C=1 miss.
gren_near_xz
	ldx obj_i
	lda gr_xh,x
	sec
	sbc pv0
	jsr gren_abs
	cmp #GREN_HIT_R + 1
	bcs .gnx_no
	lda gr_zh,x
	sec
	sbc pv1
	jsr gren_abs
	cmp #GREN_HIT_R + 1
.gnx_no
	rts

; pv0 inclusive, pv1 exclusive. C=1 inside.
gren_in_y
	ldx obj_i
	lda gr_yh,x
	cmp pv0
	bcc .giy_no
	cmp pv1
	bcs .giy_no
	sec
	rts
.giy_no
	clc
	rts

gren_abs
	bpl +
	eor #$ff
	clc
	adc #1
+
	rts

gren_explode
	ldx obj_i
	lda fx_on
	beq .gex_go
	lda gr_flags,x
	ora #GREN_F_PEND
	sta gr_flags,x
	rts
.gex_go
	lda gr_xh,x
	sta ent_wx
	lda gr_yh,x
	sta ent_wy
	lda gr_zh,x
	sta ent_wz
	jsr gren_splash
	jsr start_explosion
	lda #SOUND_BAREXP
	jsr play_sound
	ldx obj_i
	lda #0
	sta gr_on,x
	rts

; Chebyshev 3D vs blast origin ent_wx/wy/wz. pv0/1/2 = target. nlo = d.
gren_cheby
	lda ent_wx
	sec
	sbc pv0
	jsr gren_abs
	sta nlo
	lda ent_wy
	sec
	sbc pv1
	jsr gren_abs
	cmp nlo
	bcc +
	sta nlo
+
	lda ent_wz
	sec
	sbc pv2
	jsr gren_abs
	cmp nlo
	bcc +
	sta nlo
+
	lda nlo
	rts

gren_splash
	lda cam_xh
	sta pv0
	lda cam_yh
	sta pv1
	lda cam_zh
	sta pv2
	jsr gren_cheby
	cmp #GREN_RAD
	bcs .gsp_en
	jsr gren_falloff
	jsr take_damage
.gsp_en
	ldx #0
.gsp_lp
	cpx	map_nenemies
	bcs .gsp_rts
	stx enemy_idx
	lda en_state,x
	cmp #EN_DYING
	bcs .gsp_n
	+lda_mx en_x
	sta pv0
	+lda_mx en_y
	sta pv1
	+lda_mx en_z
	sta pv2
	jsr gren_cheby
	cmp #GREN_RAD
	bcs .gsp_n
	jsr gren_falloff
	ldx enemy_idx
	jsr damage_enemy
.gsp_n
	ldx enemy_idx
	inx
	bne .gsp_lp
.gsp_rts
	rts

gren_falloff
	sta nlo
	lda #GREN_RAD
	sec
	sbc nlo
	asl
	asl
	rts

draw_grenades
	ldx #0
	stx pv0
.dgr
	cpx #GREN_MAX
	bcs .dgr_rts
	lda gr_on,x
	beq .dgr_n
	lda gr_room,x
	cmp room_idx
	bne .dgr_n
	lda pv0
	bne .dgr_go
	inc pv0
	stx obj_i
	jsr load_view_trig
	ldx obj_i
.dgr_go
	jsr gren_draw_one
	ldx obj_i
.dgr_n
	inx
	bne .dgr
.dgr_rts
	rts

; View-space dart: tail ±GREN_HW in X, tip +GREN_HW in Z.
gren_draw_one
	stx obj_i
	lda gr_xl,x
	sta org_xl
	lda gr_xh,x
	sta org_xh
	lda gr_yl,x
	sta org_yl
	lda gr_yh,x
	sta org_yh
	lda gr_zl,x
	sta org_zl
	lda gr_zh,x
	sta org_zh
	ldx #0
	jsr xform_world_vert88
	ldy #0
.dup
	lda CAM_X,y
	sta CAM_X+1,y
	sta CAM_X+2,y
	cpy #$20
	beq .hi
	tya
	clc
	adc #$10
	tay
	bne .dup
.hi
	ldy #$50
.dup2
	lda CAM_X,y
	sta CAM_X+1,y
	sta CAM_X+2,y
	tya
	clc
	adc #$10
	tay
	cpy #$80
	bcc .dup2
	sec
	lda CAM_X
	sbc #GREN_HW
	sta CAM_X
	lda CAM_XH
	sbc #0
	sta CAM_XH
	clc
	lda CAM_X+1
	adc #GREN_HW
	sta CAM_X+1
	lda CAM_XH+1
	adc #0
	sta CAM_XH+1
	clc
	lda CAM_Z+2
	adc #GREN_HW
	sta CAM_Z+2
	lda CAM_ZH+2
	adc #0
	sta CAM_ZH+2
	jmp stroke_tri

grenade_end = *
