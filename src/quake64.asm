; Quake64 — portal-room maps + enemy poses loaded from disk
!cpu 6510
!to "game.prg", cbm

; --- build flags (Wolf64-style) -------------------------------------------
PROFILE		= 0				; 1 = R/P/K/D bucket HUD + CIA samples
HUD_FRAME_MS	= 0				; 1 = frame time ms on HUD row 0
HUD_POS		= 0				; 1 = X/Y/Z/yaw/pitch on HUD row 2
INF_AMMO		= 1				; 1 = guns fire without spending ammo
IRQ_DEBUG_SPLIT	= 0				; 1 = $d020 stripe at mid-split (tune 186)

!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!if ENEMY_PTR_N != ENEMY_NTYPES {
	!error "mem.asm ENEMY_PTR_N must equal ENEMY_NTYPES"
}

*= LOCODE_BASE
mod_quake64
start
	sei
	cld
	ldx #$ff
	txs
	lda #BANK_IO				; I/O + KERNAL, BASIC out (SEI)
	sta $01

	lda #0
	sta load_in_play
	lda $ba
	bne +
	lda #8
+
	sta load_device
	jsr install_reboot_stub
	lda #START_LEVEL
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
	jsr maybe_stream_room			; room_idx is valid now: pull its poses
	cli

main
	cld
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
	jsr draw_spit
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
	jsr maybe_stream_room			; after movement, before the next draw
	jsr try_proximity
	jsr proc_update
	jsr crush_update
	jsr update_floor
	jsr update_fall
	jsr update_grenades
	jsr update_spit
	jsr update_status
	jsr update_triggers
	jsr enemies_update
	jmp main

mod_vic
!source "vic.asm"
mod_irq
!source "irq.asm"
mod_profil
!source "profil.asm"
mod_hud
!source "hud.asm"
mod_math
!source "math.asm"
mod_util
!source "util.asm"
mod_line
!source "line.asm"
mod_fx
!source "fx.asm"
mod_grenade
!source "grenade.asm"
mod_spit
!source "spit.asm"
mod_playsound
!source "playsound.asm"
mod_pcsounds
!source "pcsounds.asm"
mod_pcsfreq
!source "pcsfreq.asm"
mod_weapon
!source "weapon.asm"
mod_weapon_spr
!source "weapon_spr.asm"
mod_splat_spr
!source "splat_spr.asm"
mod_enemy_muzzle
!source "enemy_muzzle.asm"
mod_process
!source "process.asm"
mod_elevator
!source "elevator.asm"
mod_crusher
!source "crusher.asm"
mod_door
!source "door.asm"
mod_world
!source "world.asm"
mod_item_mesh
!source "item_mesh.asm"
mod_mesh
!source "mesh.asm"
mod_cube
!source "cube.asm"
mod_enemy
!source "enemy.asm"
mod_loader
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
