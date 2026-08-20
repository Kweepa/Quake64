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
	!byte <0, <600, <100, <900
wpn_fire_ms_hi
	!byte >0, >600, >100, >900

wpn_sound
	!byte 0, SOUND_SHOTGN, SOUND_ATKMACHINEGUN, SOUND_BAREXP

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
	!byte $10, $20			; sprite 4 left, sprite 5 right

emuz_spr_lo
	!byte <spr_emuz_0, <spr_emuz_1, <spr_emuz_2
emuz_spr_hi
	!byte >spr_emuz_0, >spr_emuz_1, >spr_emuz_2
splat_spr_lo
	!byte <spr_splat_0, <spr_splat_1, <spr_splat_2
splat_spr_hi
	!byte >spr_splat_0, >spr_splat_1, >spr_splat_2

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
init_weapon
	lda #0
	sta $d015
	sta spr_en
	sta wpn_flash_en
	sta flash_phase
	sta flash_ms_l
	sta flash_ms_h
	sta flash5_phase
	sta flash5_ms_l
	sta flash5_ms_h
	sta emuz_on
	sta emuz_ms_l
	sta emuz_ms_h
	sta emuz_xmsb
	sta emuz_vx
	sta emuz_vy
	sta emuz_col
	sta emuz_skip
	sta splat_on
	sta splat_ms_l
	sta splat_ms_h
	sta splat_xmsb
	sta splat_vx
	sta splat_vy
	sta splat_col
	sta splat_skip
	lda #$ff
	sta emuz_pending
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

	; nail R bitmap stays in slot 5
	lda #<spr_nail_fr
	ldy #>spr_nail_fr
	jsr blit_flash2

	lda #HAVE_START
	sta have_wpn
	lda #AMMO_SHELLS_START
	sta ammo_shells
	lda #0
	sta ammo_nails
	sta ammo_grenades
	lda #PLAYER_HP_START
	sta player_hp

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
	sta flash_ms_l
	sta flash_ms_h
	sta flash_phase
	sta flash5_phase
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
	jsr blit256
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
	lda #COL_WPN
	sta $d027
	sta $d028
	sta $d029
	sta $d02a
	lda #COL_FLASH_Y
	sta $d02b
	sta $d02c
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	jmp apply_xy

; A = src lo, Y = src hi → WPN_RAM (256)
blit256
	sta .b256 + 1
	sty .b256 + 2
	ldx #0
.b256
	lda $ffff,x
	sta WPN_RAM,x
	inx
	bne .b256
	rts

; A = src lo, Y = src hi → WPN_FLASH (64)
blit_flash
	sta .bf4 + 1
	sty .bf4 + 2
	ldx #0
.bf4
	lda $ffff,x
	sta WPN_FLASH,x
	inx
	cpx #64
	bcc .bf4
	rts

blit_flash2
	sta .bf5 + 1
	sty .bf5 + 2
	ldx #0
.bf5
	lda $ffff,x
	sta WPN_FLASH2,x
	inx
	cpx #64
	bcc .bf5
	rts

; A = src lo, Y = src hi → WPN_EMUZ (64)
blit_emuz
	sta .be6 + 1
	sty .be6 + 2
	ldx #0
.be6
	lda $ffff,x
	sta WPN_EMUZ,x
	inx
	cpx #64
	bcc .be6
	rts

; A = src lo, Y = src hi → WPN_SPLAT (64)
blit_splat
	sta .bs7 + 1
	sty .bs7 + 2
	ldx #0
.bs7
	lda $ffff,x
	sta WPN_SPLAT,x
	inx
	cpx #64
	bcc .bs7
	rts

apply_xy
	lda #0
	sta $d010
	lda wpn_x
	sta $d000
	sta $d004
	clc
	adc #WPN_COL
	sta $d002
	sta $d006
	lda wpn_y
	sta $d001
	sta $d003
	clc
	adc #WPN_ROW
	sta $d005
	sta $d007
	lda cur_weapon
	bne .axy_fl
	lda flash_phase
	bne apply_en			; axe spark keeps spawn Y through red
.axy_fl
	jsr place_flash
apply_en
	lda #$0f
	ldx flash_phase
	beq .ae4
	ora #$10
.ae4
	ldx flash5_phase
	beq .ae5
	ora #$20
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

; A = $10 sprite 4, $20 sprite 5. Other side's fade is left running.
start_flash
	cmp #$20
	beq .sf5
	lda #1
	sta flash_phase
	lda #<FLASH_YEL_MS
	sta flash_ms_l
	lda #>FLASH_YEL_MS
	sta flash_ms_h
	lda #COL_FLASH_Y
	sta $d02b
	ldx cur_weapon
	cpx #WPN_NAIL
	beq .sf_xy
	lda #0
	sta flash5_phase
	jmp .sf_xy
.sf5
	lda #1
	sta flash5_phase
	lda #<FLASH_YEL_MS
	sta flash5_ms_l
	lda #>FLASH_YEL_MS
	sta flash5_ms_h
	lda #COL_FLASH_Y
	sta $d02c
.sf_xy
	jsr place_flash
	jmp apply_en

hide_flash
	lda #0
	sta flash_phase
	sta flash_ms_l
	sta flash_ms_h
	sta flash5_phase
	sta flash5_ms_l
	sta flash5_ms_h
	jmp apply_en

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

	jsr tick_flash
	jsr tick_enemy_muzzle
	jsr tick_splat
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
	lda #$10
	jsr start_flash
	jmp start_recoil

.fs_nail
	lda #POSE_FIRE
	sta wpn_pose
	ldx mg_frame
	lda nail_fr_lo,x
	ldy nail_fr_hi,x
	jsr blit256
	ldx mg_frame
	lda nail_flash_en,x
	jsr start_flash
	lda mg_frame
	eor #1
	sta mg_frame
	jmp apply_xy

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
	jsr blit256
	ldx #WPN_NAIL
	lda wpn_idle_x,x
	sta wpn_x
	lda wpn_idle_y,x
	sta wpn_y
	jmp apply_xy

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
	jsr apply_xy
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
	lda #$10
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
	jsr blit256
	ldx cur_weapon
.ti_xy
	jmp apply_xy

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
	jmp apply_xy

tick_flash
	lda flash_phase
	beq .tf5
	sec
	lda flash_ms_l
	sbc dt_ms
	sta flash_ms_l
	lda flash_ms_h
	sbc dt_msh
	sta flash_ms_h
	bcc .tf4_exp
	ora flash_ms_l
	bne .tf5
.tf4_exp
	jsr flash4_expired
.tf5
	lda flash5_phase
	beq .tf_en
	sec
	lda flash5_ms_l
	sbc dt_ms
	sta flash5_ms_l
	lda flash5_ms_h
	sbc dt_msh
	sta flash5_ms_h
	bcc .tf5_exp
	ora flash5_ms_l
	bne .tf_en
.tf5_exp
	jsr flash5_expired
.tf_en
	jmp apply_en

flash4_expired
	lda flash_phase
	cmp #1
	bne .f4_off
	lda #2
	sta flash_phase
	lda #COL_FLASH_R
	sta $d02b
	lda #<FLASH_RED_MS
	sta flash_ms_l
	lda #>FLASH_RED_MS
	sta flash_ms_h
	rts
.f4_off
	lda #0
	sta flash_phase
	rts

flash5_expired
	lda flash5_phase
	cmp #1
	bne .f5_off
	lda #2
	sta flash5_phase
	lda #COL_FLASH_R
	sta $d02c
	lda #<FLASH_RED_MS
	sta flash5_ms_l
	lda #>FLASH_RED_MS
	sta flash5_ms_h
	rts
.f5_off
	lda #0
	sta flash5_phase
	rts

; A = tip viewport sx, Y = tip viewport sy. Depth = CAM_ZH+12.
; Safe at $01=$34: blit + stage VIC regs (apply_en pokes when I/O is mapped).
; Sprite top-left at tip −12/−10; LOD 0..2 from distance; colour = col_fx.
start_enemy_muzzle
	sta wpn_tmp0			; tip sx
	tya
	pha				; tip sy
	; distance LOD from tip view-z high (0 near … 2 far)
	ldx #0
	lda CAM_ZH+12
	bmi .sem_far
	cmp #EMUZ_Z0
	bcc .sem_lod
	inx
	cmp #EMUZ_Z1
	bcc .sem_lod
.sem_far
	ldx #2
.sem_lod
	lda emuz_spr_lo,x
	ldy emuz_spr_hi,x
	jsr blit_emuz
	; VIC X = sx − 12 + VIEW_SPR_X0 (= sx + 76)
	clc
	lda wpn_tmp0
	adc #VIEW_SPR_X0 - EMUZ_OX
	sta emuz_vx
	lda #0
	bcc .sem_xlo
	lda #EMUZ_MSB
.sem_xlo
	sta emuz_xmsb
	; VIC Y = sy − 10 + VIEW_SPR_Y0 (= sy + 112)
	pla
	clc
	adc #VIEW_SPR_Y0 - EMUZ_OY
	sta emuz_vy
	lda col_fx
	sta emuz_col
	lda emuz_on
	bne .sem_timer			; already up: no re-trigger sound
	lda #SOUND_SHOOT
	jsr play_sound
.sem_timer
	lda #1
	sta emuz_on
	sta emuz_skip			; don't expire on this frame's ~150ms dt
	lda #<EMUZ_MS
	sta emuz_ms_l
	lda #>EMUZ_MS
	sta emuz_ms_h
	rts				; apply_en runs later with I/O on

; Write staged enemy-muzzle VIC regs (call with $01=$35).
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

tick_enemy_muzzle
	lda emuz_on
	beq .tem_rts
	lda emuz_skip
	beq .tem_sub
	lda #0
	sta emuz_skip			; survive spawn frame → next draw
	rts
.tem_sub
	sec
	lda emuz_ms_l
	sbc dt_ms
	sta emuz_ms_l
	lda emuz_ms_h
	sbc dt_msh
	sta emuz_ms_h
	bcc .tem_off
	ora emuz_ms_l
	bne .tem_rts
.tem_off
	lda #0
	sta emuz_on
	sta emuz_ms_l
	sta emuz_ms_h
	sta emuz_xmsb
	sta emuz_skip
	jmp apply_en
.tem_rts
	rts

; A = tip viewport sx, Y = tip viewport sy, X = depth (EMUZ_Z0/Z1 bands).
; Colour in splat_col. Sprite top-left at tip −12/−10.
start_splat
	sta wpn_tmp0			; tip sx
	tya
	pha				; tip sy
	txa					; depth → LOD 0..2 (same thresholds as emuz)
	ldx #0
	cmp #EMUZ_Z0
	bcc .ssp_lod
	inx
	cmp #EMUZ_Z1
	bcc .ssp_lod
	ldx #2
.ssp_lod
	lda splat_spr_lo,x
	ldy splat_spr_hi,x
	jsr blit_splat
	; VIC X = sx − 12 + VIEW_SPR_X0 (= sx + 76)
	clc
	lda wpn_tmp0
	adc #VIEW_SPR_X0 - EMUZ_OX
	sta splat_vx
	lda #0
	bcc .ssp_xlo
	lda #SPLAT_MSB
.ssp_xlo
	sta splat_xmsb
	; VIC Y = sy − 10 + VIEW_SPR_Y0 (= sy + 112)
	pla
	clc
	adc #VIEW_SPR_Y0 - EMUZ_OY
	sta splat_vy
	lda #1
	sta splat_on
	sta splat_skip
	lda #<SPLAT_MS
	sta splat_ms_l
	lda #>SPLAT_MS
	sta splat_ms_h
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

tick_splat
	lda splat_on
	beq .tsp_rts
	lda splat_skip
	beq .tsp_sub
	lda #0
	sta splat_skip
	rts
.tsp_sub
	sec
	lda splat_ms_l
	sbc dt_ms
	sta splat_ms_l
	lda splat_ms_h
	sbc dt_msh
	sta splat_ms_h
	bcc .tsp_off
	ora splat_ms_l
	bne .tsp_rts
.tsp_off
	lda #0
	sta splat_on
	sta splat_ms_l
	sta splat_ms_h
	sta splat_xmsb
	sta splat_skip
	jmp apply_en
.tsp_rts
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
