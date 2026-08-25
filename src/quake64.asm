; Quake64 — portal-room maps + enemy poses loaded from disk
!cpu 6510
!to "game.prg", cbm

; --- build flags (Wolf64-style) -------------------------------------------
PROFILE		= 0				; 1 = R/P/K/D bucket HUD + CIA samples
HUD_FRAME_MS	= 1				; 1 = frame time ms on HUD row 0
HUD_POS		= 0				; 1 = X/Y/Z/yaw/pitch on HUD row 2
INF_AMMO		= 1				; 1 = guns fire without spending ammo
IRQ_DEBUG_SPLIT	= 0				; 1 = $d020 stripe at mid-split (tune 186)

!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"

*= LOCODE_BASE
start
	sei
	cld
	ldx #$ff
	txs
	lda #BANK_IO				; I/O + KERNAL, BASIC out (SEI)
	sta $01

	lda #0
	sta load_in_play
	jsr install_reboot_stub
	lda #1
	sta level_num
	jsr LoadLevel
	bcc .start_ok
	jmp load_fail_hang
.start_ok
	sei
	lda #BANK_IO
	sta $01
	jsr game_zp_init

	jsr fill_colour
	jsr init_vic
	jsr init_irq
	jsr play_sound_init
	jsr init_weapon
	jsr prof_init
	lda #BANK_RAM				; all RAM; I/O only in IRQ
	sta $01
	jsr clear_charsets
	jsr fill_margin_glyph
	lda #BANK_IO				; colour RAM + HUD after charset wipe
	sta $01
	jsr init_hud
	jsr hud_ammo
	jsr hud_powerup
	lda #BANK_RAM
	sta $01
	jsr mulset_init
	jsr world_init
	cli

main
!if PROFILE = 1 {
	jsr prof_reset_frame
} else {
	lda #$ff
	sta mesh_vmask
}
	jsr clear_draw
!if PROFILE = 1 {
	ldy #PROF_CLEAR
	jsr prof_add_bucket
}
	jsr draw_world
	jsr draw_enemies
	jsr draw_grenades
	jsr draw_explosion

	lda draw_buf
	sta show_buf
	jsr apply_show
	jsr prof_frame_sample
	jsr calc_frame_dt
	jsr update_hurt_flash
	jsr update_powerup
	jsr update_item_spin
	jsr hud_print

	lda draw_buf
	eor #1
	sta draw_buf
	jsr set_draw_ptrs
	jsr read_input
	jsr update_weapon
	jsr apply_move_world
	jsr maybe_room_palette
	jsr try_proximity
	jsr proc_update
	jsr update_floor
	jsr update_fall
	jsr update_grenades
	jsr update_status
	jsr update_triggers
	jsr enemies_update
	jmp main

; A = signed 8-bit 8.8 step added to cam_xl/xh
camaddx
	sta rot2
	ldx #0
	cmp #0
	bpl +
	dex
+
	clc
	adc cam_xl
	sta cam_xl
	txa
	adc cam_xh
	sta cam_xh
	rts

camaddy
	sta rot2
	ldx #0
	cmp #0
	bpl +
	dex
+
	clc
	adc cam_yl
	sta cam_yl
	txa
	adc cam_yh
	sta cam_yh
	rts

camaddz
	sta rot2
	ldx #0
	cmp #0
	bpl +
	dex
+
	clc
	adc cam_zl
	sta cam_zl
	txa
	adc cam_zh
	sta cam_zh
	rts

; A = signed 8-bit 8.8 step subtracted from cam
camsbcx
	eor #$ff
	clc
	adc #1
	jmp camaddx

camsbcy
	eor #$ff
	clc
	adc #1
	jmp camaddy

camsbcz
	eor #$ff
	clc
	adc #1
	jmp camaddz

apply_move
	ldy yaw
	lda SINTAB,y
	sta rot0
	ldy yaw
	lda COSTAB,y
	sta rot1

	lda keys
	and #KEY_W
	beq .now
	ldy pitch
	lda COSTAB,y
	tay
	lda rot0
	jsr smul7
	jsr camaddx
	ldy pitch
	lda COSTAB,y
	tay
	lda rot1
	jsr smul7
	jsr camaddz
	ldy pitch
	lda SINTAB,y
	jsr camsbcy
.now
	lda keys
	and #KEY_S
	beq .nos
	ldy pitch
	lda COSTAB,y
	tay
	lda rot0
	jsr smul7
	jsr camsbcx
	ldy pitch
	lda COSTAB,y
	tay
	lda rot1
	jsr smul7
	jsr camsbcz
	ldy pitch
	lda SINTAB,y
	jsr camaddy
.nos
	lda keys
	and #KEY_D
	beq .nod
	lda rot1
	jsr camaddx
	lda rot0
	jsr camsbcz
.nod
	lda keys
	and #KEY_A
	beq .noa
	lda rot1
	jsr camsbcx
	lda rot0
	jsr camaddz
.noa
	rts

!source "vic.asm"
!source "irq.asm"
!source "profil.asm"
!source "hud.asm"
!source "math.asm"
!source "util.asm"
!source "line.asm"
!source "fx.asm"
!source "grenade.asm"
!source "playsound.asm"
!source "pcsounds.asm"
!source "pcsfreq.asm"
!source "weapon.asm"
!source "weapon_spr.asm"
!source "splat_spr.asm"
!source "enemy_muzzle.asm"
!source "process.asm"
!source "elevator.asm"
!source "door.asm"
!source "world.asm"
!source "item_mesh.asm"
!source "mesh.asm"
!source "cube.asm"
!source "enemy.asm"
!source "mapacc_rt.asm"
!source "loader.asm"

!source "map_bss.asm"

!if PROFILE = 1 {
casc_snap
	!fill 4, 0
prof_dt
	!fill 4, 0
prof_cy
	!fill PROF_NBUCKET * 4, 0
; Per-frame vertex totals (R/P/K stages)
nv_cnt
nv_rot
	!fill 2, 0
nv_proj
	!fill 2, 0
nv_clip
	!fill 2, 0
}

end_game = *
!if end_game > SCR_A {
	!error "game overlaps screen A at $C000; end=$", end_game
}
