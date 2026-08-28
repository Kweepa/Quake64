; First-person view-model: 2×2 body (sprites 0–3) + 24×21 flash (4 / 5).
; Native size (no XY expand). Body light grey; flash yellow then red.
; Weapon ids WPN_* live in mem.asm
!zone weapon

POSE_IDLE = 0
POSE_FIRE = 1
POSE_RECOIL = 2
POSE_ANIM = 3

AXE_NSTEPS = 5
AXE_F_OOF = $40
AXE_F_HIT = $20
AXE_F_SPARK = $80

RECOIL_NSTEPS = 3

; have_wpn bit per weapon id
wpn_have_bit
	!byte HAVE_AXE, HAVE_SHOT, HAVE_NAIL, HAVE_GREN

wpn_fire_ms_lo
	!byte <0, <600, <100, <1000
wpn_fire_ms_hi
	!byte >0, >600, >100, >1000

wpn_sound
	!byte 0, SOUND_SHOTGN, SOUND_ATKMACHINEGUN, SOUND_SHOOT

wpn_idle_x
	!byte WPN_X0, WPN_X0, WPN_X0, WPN_X0
wpn_idle_y
	!byte WPN_Y_AXEIDLE, WPN_Y_SHOTIDLE, WPN_Y_NAILIDLE, WPN_Y_FLUSH

wpn_body_lo
	!byte <spr_axe_0, <spr_shot2, <spr_nail_0, <spr_rock
wpn_body_hi
	!byte >spr_axe_0, >spr_shot2, >spr_nail_0, >spr_rock

wpn_flash4_lo
	!byte <spr_spark, <spr_muzzle, <spr_nail_fl, <spr_muzzle
wpn_flash4_hi
	!byte >spr_spark, >spr_muzzle, >spr_nail_fl, >spr_muzzle

wpn_flash_x4
	!byte FLASH_X_C, FLASH_X_C, FLASH_X_NL, FLASH_X_C
wpn_flash_x5
	!byte FLASH_X_C, FLASH_X_C, FLASH_X_NR, FLASH_X_C
; added to wpn_y (signed)
wpn_flashdy
	!byte -FLASH_DY, -FLASH_DY_GUN, FLASH_DY_NAIL, -FLASH_DY_GUN

nail_fr_lo
	!byte <spr_nail_1, <spr_nail_2
nail_fr_hi
	!byte >spr_nail_1, >spr_nail_2
nail_flash_en
	!byte FLASH_EN_L, FLASH_EN_R	; sprite 4 left, sprite 5 right

WS_EMUZ		= 0
WS_SPLAT	= 1

; LOD 0..2 per slot (emuz then splat)
ws_spr_lo
	!byte <spr_emuz_0, <spr_emuz_1, <spr_emuz_2
	!byte <spr_splat_0, <spr_splat_1, <spr_splat_2
ws_spr_hi
	!byte >spr_emuz_0, >spr_emuz_1, >spr_emuz_2
	!byte >spr_splat_0, >spr_splat_1, >spr_splat_2
ws_msb
	!byte EMUZ_MSB, SPLAT_MSB
ws_ms_l
	!byte <EMUZ_MS, <SPLAT_MS
ws_ms_h
	!byte >EMUZ_MS, >SPLAT_MS
ws_hdr_lo
	!byte <fxh_emuz, <fxh_splat
ws_hdr_hi
	!byte >fxh_emuz, >fxh_splat
ws_vx_lo
	!byte <emuz_vx, <splat_vx
ws_vx_hi
	!byte >emuz_vx, >splat_vx
ws_vy_lo
	!byte <emuz_vy, <splat_vy
ws_vy_hi
	!byte >emuz_vy, >splat_vy
ws_col_lo
	!byte <emuz_col, <splat_col
ws_col_hi
	!byte >emuz_col, >splat_col
ws_xmsb_lo
	!byte <emuz_xmsb, <splat_xmsb
ws_xmsb_hi
	!byte >emuz_xmsb, >splat_xmsb
ws_snd
	!byte SOUND_SHOOT, 0
ws_colsrc
	!byte 0, 1			; 0 = copy col_fx, 1 = leave splat_col

fxh_lo
	!byte <fxh_flash4, <fxh_flash5, <fxh_emuz, <fxh_splat, <fxh_explode
fxh_hi
	!byte >fxh_flash4, >fxh_flash5, >fxh_emuz, >fxh_splat, >fxh_explode
fx_exp_lo
	!byte <flash4_expired, <flash5_expired, <emuz_expired, <splat_expired, <fx_zero_header
fx_exp_hi
	!byte >flash4_expired, >flash5_expired, >emuz_expired, >splat_expired, >fx_zero_header

; Axe fire keyframes (right prepare → left/down arc). Idle is not in this table.
axe_step_x
	!byte 200, 172, 144, 120, 104
axe_step_y
	!byte WPN_Y_FLUSH, 210, 214, 229, 250
axe_step_ms_lo
	!byte <180, <45, <50, <55, <40
axe_step_ms_hi
	!byte >180, >45, >50, >55, >40
axe_step_flags
	!byte AXE_F_OOF, 0, AXE_F_SPARK | AXE_F_HIT, 0, 0

; Shotgun: snap up for shot, kick down, settle. Grenade: snap down, recover.
recoil_shot_y
	!byte 208, 232, 224
recoil_gren_y
	!byte 232, 224, 216
recoil_step_ms_lo
	!byte 16, 35, 35
recoil_step_ms_hi
	!byte 0, 0, 0

; ------------------------------------------------------------------
; VIC sprite slots / flash state. Does not touch HP, ammo, or weapons.
init_weapon_hw
	lda #0
	sta $d015
	sta spr_en
	sta wpn_flash_en
	ldx #0
.iw_fxh
	lda fxh_lo,x
	sta fx_ptr
	lda fxh_hi,x
	sta fx_ptr+1
	lda #0
	ldy #FXH_ON
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	inx
	cpx #FXH_COUNT
	bcc .iw_fxh
	sta emuz_xmsb
	sta emuz_vx
	sta emuz_vy
	sta emuz_col
	sta splat_xmsb
	sta splat_vx
	sta splat_vy
	sta splat_col
	lda #$ff
	sta emuz_pending
	sta bite_splat_i
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
	sta mg_frame
	sta wpn_pose
	sta anim_step
	sta in_fire
	sta key_fire
	ldx #3
-
	sta in_wpn_axe,x
	sta key_wpn_axe,x
	dex
	bpl -

	lda #0
	sta $d01d
	sta $d017
	sta $d01c
	sta $d010
	sta $d01b

	ldx #0
	lda #WPN_PTR0
.iw_ptr
	sta $c3f8,x
	sta $c7f8,x
	clc
	adc #1
	inx
	cpx #8				; body 0–3, flash 4–5, emuz 6, splat 7
	bcc .iw_ptr

	; nail R bitmap stays in WPN_FLASH2
	lda #<spr_nail_fr
	ldy #>spr_nail_fr
	jsr blit_flash2
	rts

; First start: hardware + starting inventory.
init_weapon
	jsr init_weapon_hw
	jsr init_grenades
	lda #HAVE_START
	sta have_wpn
	lda #AMMO_SHELLS_START
	sta ammo_shells
	lda #0
	sta ammo_nails
	sta ammo_grenades
	lda #PLAYER_HP_START
	sta player_hp
	lda #PLAYER_ARMOUR_START
	sta player_armour
	lda #0
	sta have_keys
	sta pu_kind
	sta pu_ms_l
	sta pu_ms_h

	lda #COL_WPN
	sta col_wpn
	lda #COL_FLASH_Y
	sta flash4_col
	sta flash5_col
	lda #$ff
	sta cur_weapon
	ldx #WPN_SHOT
	jmp switch_weapon

; X = weapon id — refuse if not owned
switch_weapon
	lda wpn_have_bit,x
	and have_wpn
	beq .sw_rts
	cpx cur_weapon
	bne .sw_do
.sw_rts
	rts
.sw_do
	stx cur_weapon
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
	sta flash_phase
	sta flash_skip
	sta flash_ms_l
	sta flash_ms_h
	sta flash5_phase
	sta flash5_skip
	sta flash5_ms_l
	sta flash5_ms_h
	sta wpn_flash_en
	sta mg_frame
	sta wpn_pose
	sta anim_step
	jmp setup_weapon

setup_weapon
	ldx cur_weapon
	lda wpn_body_lo,x
	ldy wpn_body_hi,x
	jsr blit_n
	ldx cur_weapon
	lda wpn_flash4_lo,x
	ldy wpn_flash4_hi,x
	jsr blit_flash
	ldx cur_weapon
	cpx #WPN_NAIL
	bne .su_dx
	lda #<spr_nail_fr
	ldy #>spr_nail_fr
	jsr blit_flash2
	ldx cur_weapon
.su_dx
	lda wpn_flashdy,x
	sta wpn_flash_dy
	lda #COL_FLASH_Y
	sta flash4_col
	sta flash5_col
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	rts

; A = src lo, Y = src hi → WPN_RAM, wpn_body_n[cur_weapon] bytes (0 = 256)
blit_n
	sta .bn + 1
	sty .bn + 2
	ldx cur_weapon
	lda wpn_body_n,x
	sta .bnlim + 1
	ldx #0
.bn
	lda $ffff,x
	sta WPN_RAM,x
	inx
.bnlim
	cpx #0
	bne .bn
	rts

; A = src lo, Y = src hi → unpack zeromask into dest (set by wrappers).
; Packed: 8-byte mask at src+0, nonzero payload at src+8. Y indexes mask only.
unpack_fx
	sta .us + 1
	clc
	adc #8
	sta .us2 + 1
	tya
	sta .us + 2
	adc #0
	sta .us2 + 2
	lda #0
	tax
.uclr
.ud0
	sta $ffff,x
	inx
	cpx #64
	bne .uclr
	ldy #0
	ldx #0
.umask
.us	lda $ffff,y
	iny
	sta wpn_tmp0
	lda #8
.ubit
	lsr wpn_tmp0
	bcc .uz
	pha
.us2	lda $ffff
	inc .us2 + 1
	bne .ud1
	inc .us2 + 2
.ud1	sta $ffff,x
	pla
.uz
	inx
	sec
	sbc #1
	bne .ubit
	cpx #64
	bcc .umask
	rts

set_unpack_dst
	sta .ud0 + 1
	sta .ud1 + 1
	sty .ud0 + 2
	sty .ud1 + 2
	rts

; A = src lo, Y = src hi → WPN_FLASH (64, zeromask)
blit_flash
	pha
	tya
	pha
	lda #<WPN_FLASH
	ldy #>WPN_FLASH
	jsr set_unpack_dst
	pla
	tay
	pla
	jmp unpack_fx

blit_flash2
	pha
	tya
	pha
	lda #<WPN_FLASH2
	ldy #>WPN_FLASH2
	jsr set_unpack_dst
	pla
	tay
	pla
	jmp unpack_fx

wpn_slot_base
	!byte 0, 4, 8, 12

; IRQ (I/O on): weapon/muzzle/splat XY, $d015, $d010.
apply_xy
	lda #0
	sta $d010
	ldy #0				; slot 0..3
.axy_slot
	ldx cur_weapon
	tya
	clc
	adc wpn_slot_base,x
	tax				; dx/dy index
	lda wpn_x
	clc
	adc wpn_dx,x
	pha
	lda wpn_y
	clc
	adc wpn_dy,x
	pha				; Y
	tya
	asl
	tax				; VIC pair (sprites 0–3)
	pla
	sta $d001,x
	pla
	sta $d000,x
	iny
	cpy #4
	bcc .axy_slot
	lda cur_weapon
	bne .axy_fl
	lda flash_phase
	bne apply_en			; axe spark keeps spawn Y through red
.axy_fl
	jsr place_flash
apply_en
	ldx cur_weapon
	lda wpn_body_en,x
	ldx flash_phase
	beq .ae4
	ora #FLASH_EN_L
.ae4
	ldx flash5_phase
	beq .ae5
	ora #FLASH_EN_R
.ae5
	ldx emuz_on
	beq .ae6
	ora #EMUZ_MSB
.ae6
	ldx splat_on
	beq .ae7
	ora #SPLAT_MSB
.ae7
	sta wpn_flash_en
	sta spr_en
	sta $d015
	lda #WPN_PTR_EMUZ
	sta $c3fe
	sta $c7fe
	lda #WPN_PTR_SPLAT
	sta $c3ff
	sta $c7ff
	jsr place_enemy_muzzle
	jsr place_splat
	lda emuz_xmsb
	ora splat_xmsb
	sta $d010
	rts

; Flash X is screen-absolute; Y tracks the weapon.
place_flash
	ldx cur_weapon
	lda wpn_flash_x4,x
	sta $d008
	lda wpn_flash_x5,x
	sta $d00a
	lda wpn_y
	clc
	adc wpn_flash_dy
	sta $d009
	sta $d00b
	rts

; A = FLASH_EN_L sprite 4, FLASH_EN_R sprite 5. Other side's fade is left running.
start_flash
	cmp #FLASH_EN_R
	beq .sf5
	lda #1
	sta flash_phase
	sta flash_skip
	lda #<FLASH_YEL_MS
	sta flash_ms_l
	lda #>FLASH_YEL_MS
	sta flash_ms_h
	lda #COL_FLASH_Y
	sta flash4_col
	ldx cur_weapon
	cpx #WPN_NAIL
	beq .sf_xy
	lda #0
	sta flash5_phase
	sta flash5_skip
	jmp .sf_xy
.sf5
	lda #1
	sta flash5_phase
	sta flash5_skip
	lda #<FLASH_YEL_MS
	sta flash5_ms_l
	lda #>FLASH_YEL_MS
	sta flash5_ms_h
	lda #COL_FLASH_Y
	sta flash5_col
.sf_xy
	rts

hide_flash
	lda #0
	sta flash_phase
	sta flash_skip
	sta flash_ms_l
	sta flash_ms_h
	sta flash5_phase
	sta flash5_skip
	sta flash5_ms_l
	sta flash5_ms_h
	rts

; ------------------------------------------------------------------
update_weapon
	ldy #0
.uw_sw
	lda key_wpn_axe,y
	beq .uw_swn
	tya
	tax
	jsr switch_weapon
.uw_swn
	iny
	cpy #4
	bcc .uw_sw

	jsr tick_all_fx
	jsr tick_anim

	lda fire_rpt_l
	ora fire_rpt_h
	beq .uw_chk
	sec
	lda fire_rpt_l
	sbc dt_ms
	sta fire_rpt_l
	lda fire_rpt_h
	sbc dt_msh
	sta fire_rpt_h
	bcs .uw_chk
	lda #0
	sta fire_rpt_l
	sta fire_rpt_h
.uw_chk
	lda key_fire
	beq .uw_up
	lda fire_rpt_l
	ora fire_rpt_h
	bne .uw_done
	ldx cur_weapon
	cpx #WPN_NAIL
	beq .uw_shot
	lda wpn_pose
	bne .uw_done
.uw_shot
	ldx cur_weapon
	cpx #WPN_AXE
	beq .uw_do_fire
	jsr try_spend_ammo
	bcc .uw_done
	jsr hud_ammo
.uw_do_fire
	jsr fire_shot
	ldx cur_weapon
	lda wpn_fire_ms_lo,x
	sta fire_rpt_l
	lda wpn_fire_ms_hi,x
	sta fire_rpt_h
.uw_done
	rts
.uw_up
	lda cur_weapon
	cmp #WPN_NAIL
	bne .uw_up_rts
	lda wpn_pose
	cmp #POSE_FIRE
	bne .uw_up_rts
	jmp nail_idle
.uw_up_rts
	rts

; Ammo already spent (or axe). X = cur_weapon on entry to fire_shot.
fire_shot
	ldx cur_weapon
	cpx #WPN_AXE
	bne .fs_gun
	jmp start_axe
.fs_gun
	lda #1
	sta gunshot_wake
	lda wpn_sound,x
	jsr play_sound
	ldx cur_weapon
	cpx #WPN_SHOT
	bne .fs_notshot
	jsr shotgun_hitscan
	ldx cur_weapon
.fs_notshot
	cpx #WPN_NAIL
	beq .fs_nail
	cpx #WPN_GREN
	bne .fs_flash
	jsr spawn_player_grenade
.fs_flash
	lda #FLASH_EN_L
	jsr start_flash
	jmp start_recoil

.fs_nail
	jsr nailgun_hitscan
	lda #POSE_FIRE
	sta wpn_pose
	ldx mg_frame
	lda nail_fr_lo,x
	ldy nail_fr_hi,x
	jsr blit_n
	ldx mg_frame
	lda nail_flash_en,x
	jsr start_flash
	lda mg_frame
	eor #1
	sta mg_frame
	rts

; X = cur_weapon; C=1 spent (or free), C=0 cannot fire
try_spend_ammo
!if INF_AMMO = 1 {
	sec
	rts
}
	cpx #WPN_SHOT
	beq .ts_shell
	cpx #WPN_NAIL
	beq .ts_nail
	cpx #WPN_GREN
	beq .ts_gren
	sec
	rts
.ts_shell
	lda ammo_shells
	cmp #2
	bcc .ts_no
	sec
	sbc #2
	sta ammo_shells
	sec
	rts
.ts_nail
	lda ammo_nails
	beq .ts_no
	sec
	sbc #1
	sta ammo_nails
	sec
	rts
.ts_gren
	lda ammo_grenades
	beq .ts_no
	sec
	sbc #1
	sta ammo_grenades
	sec
	rts
.ts_no
	clc
	rts

nail_idle
	lda #POSE_IDLE
	sta wpn_pose
	lda #0
	sta mg_frame
	ldx #WPN_NAIL
	lda wpn_body_lo,x
	ldy wpn_body_hi,x
	jsr blit_n
	ldx #WPN_NAIL
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	rts

start_axe
	lda #POSE_ANIM
	sta wpn_pose
	lda #0
	sta anim_step
	jmp axe_apply_step

axe_apply_step
	ldx anim_step
	cpx #AXE_NSTEPS
	bcc .aas_ok
	jmp wpn_to_idle
.aas_ok
	lda axe_step_x,x
	sta wpn_x
	lda axe_step_y,x
	sta wpn_y
	lda axe_step_ms_lo,x
	sta anim_ms_l
	lda axe_step_ms_hi,x
	sta anim_ms_h
	lda axe_step_flags,x
	sta wpn_tmp0
	lda wpn_tmp0
	and #AXE_F_OOF
	beq .aas_hit
	lda #SOUND_OOF
	jsr play_sound
.aas_hit
	lda wpn_tmp0
	and #AXE_F_HIT
	beq .aas_rts
	jsr axe_try_kill
	bcc .aas_rts
	lda #SOUND_HITENEMY
	jsr play_sound
	lda wpn_tmp0
	and #AXE_F_SPARK
	beq .aas_rts
	lda #FLASH_EN_L
	jsr start_flash
.aas_rts
	rts

wpn_to_idle
	ldx cur_weapon
	lda #POSE_IDLE
	sta wpn_pose
	lda #0
	sta anim_step
	cpx #WPN_AXE
	bne .ti_pos
	jsr hide_flash
	ldx cur_weapon
.ti_pos
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	cpx #WPN_NAIL
	bne .ti_xy
	lda wpn_body_lo,x
	ldy wpn_body_hi,x
	jsr blit_n
	ldx cur_weapon
.ti_xy
	rts

start_recoil
	lda #POSE_RECOIL
	sta wpn_pose
	lda #0
	sta anim_step
	jmp recoil_apply_step

recoil_apply_step
	ldx anim_step
	cpx #RECOIL_NSTEPS
	bcc .ras_ok
	jmp wpn_to_idle
.ras_ok
	lda cur_weapon
	cmp #WPN_SHOT
	bne .ras_gren
	lda recoil_shot_y,x
	jmp .ras_y
.ras_gren
	lda recoil_gren_y,x
.ras_y
	sta wpn_y
	lda recoil_step_ms_lo,x
	sta anim_ms_l
	lda recoil_step_ms_hi,x
	sta anim_ms_h
	rts

; fx_ptr → 4-byte header. C=1 expired this frame (does not clear +0).
tick_fx
	ldy #FXH_ON
	lda (fx_ptr),y
	beq .tf_idle
	ldy #FXH_SKIP
	lda (fx_ptr),y
	beq .tf_sub
	lda #0
	sta (fx_ptr),y
	clc
	rts
.tf_sub
	ldy #FXH_MS_L
	sec
	lda (fx_ptr),y
	sbc dt_ms
	sta (fx_ptr),y
	iny
	lda (fx_ptr),y
	sbc dt_msh
	sta (fx_ptr),y
	bcc .tf_exp
	dey
	ora (fx_ptr),y
	bne .tf_live
.tf_exp
	sec
	rts
.tf_live
	clc
	rts
.tf_idle
	clc
	rts

tick_all_fx
	ldx #0
.ta_lp
	lda fxh_lo,x
	sta fx_ptr
	lda fxh_hi,x
	sta fx_ptr+1
	jsr tick_fx
	bcc .ta_n
	lda fx_exp_lo,x
	sta rot0
	lda fx_exp_hi,x
	sta rot1
	jsr .ta_go
.ta_n
	inx
	cpx #FXH_COUNT
	bcc .ta_lp
	rts
.ta_go
	jmp (rot0)

fx_zero_header
	lda #0
	ldy #FXH_ON
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	rts

flash4_expired
	lda flash_phase
	cmp #1
	bne fx_zero_header
	lda #2
	sta flash_phase
	lda #COL_FLASH_R
	sta flash4_col
	lda #1
	sta flash_skip
	lda #<FLASH_RED_MS
	sta flash_ms_l
	lda #>FLASH_RED_MS
	sta flash_ms_h
	rts

flash5_expired
	lda flash5_phase
	cmp #1
	bne fx_zero_header
	lda #2
	sta flash5_phase
	lda #COL_FLASH_R
	sta flash5_col
	lda #1
	sta flash5_skip
	lda #<FLASH_RED_MS
	sta flash5_ms_l
	lda #>FLASH_RED_MS
	sta flash5_ms_h
	rts

emuz_expired
	jsr fx_zero_header
	lda #0
	sta emuz_xmsb
	rts

splat_expired
	jsr fx_zero_header
	lda #0
	sta splat_xmsb
	rts

; A = value, X = slot. Store via ws_*_lo/hi pointer tables. Clobbers fx_ptr, Y.
!macro ws_sta .lo, .hi {
	pha
	lda .lo,x
	sta fx_ptr
	lda .hi,x
	sta fx_ptr+1
	pla
	ldy #0
	sta (fx_ptr),y
}

; A = src lo, Y = src hi. Dest from ws_slot (WPN_EMUZ / WPN_SPLAT).
blit_world
	pha
	tya
	pha
	ldx ws_slot
	beq .bw_emuz
	lda #<WPN_SPLAT
	ldy #>WPN_SPLAT
	jmp .bw_dst
.bw_emuz
	lda #<WPN_EMUZ
	ldy #>WPN_EMUZ
.bw_dst
	jsr set_unpack_dst
	pla
	tay
	pla
	jmp unpack_fx

; A = tip viewport sx, Y = tip viewport sy. Depth = rot1 (CAM_ZH of tip vert).
start_enemy_muzzle
	pha
	tya
	pha
	lda rot1
	ldx #WS_EMUZ
	jmp start_world_spr

; A = tip viewport sx, Y = tip viewport sy, X = depth (EMUZ_Z0/Z1 bands).
start_splat
	pha
	tya
	pha
	txa
	ldx #WS_SPLAT
start_world_spr
	pha				; z
	stx ws_slot			; X is slot; lod calc reuses X
	txa
	tay				; Y = slot
	pla				; A = z
	cpy #0
	bne .sws_zok
	cmp #0
	bmi .sws_far
.sws_zok
	ldx #0
	cmp #EMUZ_Z0
	bcc .sws_lod
	inx
	cmp #EMUZ_Z1
	bcc .sws_lod
.sws_far
	ldx #2
.sws_lod
	lda ws_slot
	asl
	clc
	adc ws_slot			; slot*3
	sta wpn_tmp0
	txa
	clc
	adc wpn_tmp0			; + lod
	tax
	lda ws_spr_lo,x
	ldy ws_spr_hi,x
	jsr blit_world
	ldx ws_slot
	pla				; sy
	clc
	adc #VIEW_SPR_Y0 - EMUZ_OY
	+ws_sta ws_vy_lo, ws_vy_hi
	pla				; sx
	clc
	adc #VIEW_SPR_X0 - EMUZ_OX
	pha
	lda #0
	bcc .sws_xlo
	lda ws_msb,x
.sws_xlo
	+ws_sta ws_xmsb_lo, ws_xmsb_hi
	pla
	+ws_sta ws_vx_lo, ws_vx_hi
	lda ws_colsrc,x
	bne .sws_nocol
	lda col_fx
	+ws_sta ws_col_lo, ws_col_hi
.sws_nocol
	lda ws_snd,x
	beq .sws_arm
	lda ws_hdr_lo,x
	sta fx_ptr
	lda ws_hdr_hi,x
	sta fx_ptr+1
	ldy #FXH_ON
	lda (fx_ptr),y
	bne .sws_arm
	lda ws_snd,x
	stx wpn_tmp0
	jsr play_sound
	ldx wpn_tmp0
.sws_arm
	lda ws_hdr_lo,x
	sta fx_ptr
	lda ws_hdr_hi,x
	sta fx_ptr+1
	lda #1
	ldy #FXH_ON
	sta (fx_ptr),y
	iny
	sta (fx_ptr),y
	lda ws_ms_l,x
	ldy #FXH_MS_L
	sta (fx_ptr),y
	lda ws_ms_h,x
	iny
	sta (fx_ptr),y
	rts

; Write staged enemy-muzzle VIC regs (IRQ, I/O on). Abs only — no ZP.
place_enemy_muzzle
	lda emuz_on
	beq .pem_rts
	lda emuz_vx
	sta $d00c
	lda emuz_vy
	sta $d00d
	lda emuz_col
	sta $d02d
.pem_rts
	rts

place_splat
	lda splat_on
	beq .psp_rts
	lda splat_vx
	sta $d00e
	lda splat_vy
	sta $d00f
	lda splat_col
	sta $d02e
.psp_rts
	rts

tick_anim
	lda wpn_pose
	cmp #POSE_ANIM
	beq .ta_tick
	cmp #POSE_RECOIL
	beq .ta_tick
	rts
.ta_tick
	sec
	lda anim_ms_l
	sbc dt_ms
	sta anim_ms_l
	lda anim_ms_h
	sbc dt_msh
	sta anim_ms_h
	bcc .ta_next
	ora anim_ms_l
	bne .ta_rts
.ta_next
	inc anim_step
	lda wpn_pose
	cmp #POSE_RECOIL
	beq .ta_rec
	jmp axe_apply_step
.ta_rec
	jmp recoil_apply_step
.ta_rts
	rts
