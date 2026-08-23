; Disk load — Wolf64 KERNAL sequence, Quake $01 = BANK_IO / BANK_RAM.
; Maps + enemy poses pack downward from SCR_A ($C000).
!zone loader

!source "asset_sizes.asm"

level_dos_name
	!text "E1M1"

en_name_len
	!byte 5, 6, 4, 5, 4, 6, 6
en_name_lo
	!byte <en_n0, <en_n1, <en_n2, <en_n3, <en_n4, <en_n5, <en_n6
en_name_hi
	!byte >en_n0, >en_n1, >en_n2, >en_n3, >en_n4, >en_n5, >en_n6
en_n0	!text "GRUNT"
en_n1	!text "KNIGHT"
en_n2	!text "ROTT"
en_n3	!text "SCRAG"
en_n4	!text "OGRE"
en_n5	!text "SHAMBL"
en_n6	!text "CHTHON"

; FormatDosName — E1MN from level_num (1..8); 1541 names are PETSCII A–Z
FormatDosName
	lda #'E'
	sta level_dos_name
	lda #'1'
	sta level_dos_name + 1
	lda #'M'
	sta level_dos_name + 2
	lda level_num
	clc
	adc #'0'
	sta level_dos_name + 3
	rts

; LoadPrg — A=name length, X/Y=name pointer. Dest in load_dest. SA=0.
; KERNAL must already be paged in. C=0 ok, C=1 error.
LoadPrg
	sta load_namelen
	stx load_name_l
	sty load_name_h

	lda load_namelen
	ldx load_name_l
	ldy load_name_h
	jsr $ffbd				; SETNAM
	lda #1
	ldx $ba
	ldy #0					; SA=0 → X/Y dest
	jsr $ffba				; SETLFS
	lda #0
	ldx load_dest
	ldy load_dest+1
	jsr $ffd5				; LOAD
	php
	pha
	lda #1
	jsr $ffc3				; CLOSE
	pla
	plp
	rts

blank_screen
	lda #0
	sta $d015
	sta $d020
	sta $d021
	rts

; IOINIT can leave CIA2 Timer A generating NMIs.
load_cia2_quiet
	lda #0
	sta $dd0e
	sta $dd0f
	sta $02a1
	lda #$7f
	sta $dd0d
	lda $dd0d
	rts

; A=size lo, Y=size hi → load_dest = heap_top = heap_top - size
heap_alloc
	sta bind_n
	sty map_sv_a
	sec
	lda heap_top
	sbc bind_n
	sta load_dest
	lda heap_top+1
	sbc map_sv_a
	sta load_dest+1
	lda load_dest
	sta heap_top
	lda load_dest+1
	sta heap_top+1
	rts

; LoadLevel — IOINIT + blank + map + used enemy poses + bind_map.
; load_in_play=0: cold (DEN off, no CIA2 quiet). =1: in-play (DEN on, quiet).
; C=0 ok, C=1 error. Caller re-inits VIC/IRQ.
LoadLevel
	sei
	lda #BANK_IO
	sta $01
	lda #$7f
	sta $dc0d				; kill CIA1 Timer A
	lda $dc0d
	lda #0
	sta $d01a				; kill raster IRQ
	lda load_in_play
	beq .ll_cold
	jsr $ff84				; reset IEC
	jsr load_cia2_quiet
	jsr init_vic				; DEN on before blank/load
	jmp .ll_common
.ll_cold
	jsr $ff84				; IOINIT
	; Match boot: do not quiesce CIA2. Quiet + DEN=0 stalls KERNAL IEC.
	jsr blank_screen
	lda $d011
	and #%11101111				; DEN off after IOINIT
	sta $d011
	cli
	jmp .ll_dos

.ll_common
	jsr blank_screen
.ll_dos
	lda #BANK_IO
	sta $01
	lda #<SCR_A
	sta heap_top
	lda #>SCR_A
	sta heap_top+1

	jsr FormatDosName
	ldx level_num
	dex					; 0..7
	cpx #MAP_NLEVELS
	bcs .ll_fail
	lda map_size_lo,x
	ora map_size_hi,x
	beq .ll_fail
	lda map_size_lo,x
	ldy map_size_hi,x
	jsr heap_alloc
	lda #4
	ldx #<level_dos_name
	ldy #>level_dos_name
	jsr LoadPrg
	bcs .ll_fail
	lda load_dest
	sta map_base
	lda load_dest+1
	sta map_base+1
	jsr bind_map
	jsr load_map_enemies
	bcs .ll_fail

	; end_game < heap_top
	lda #<end_game
	cmp heap_top
	lda #>end_game
	sbc heap_top+1
	bcs .ll_fail
	clc
	rts
.ll_fail
	sec
	rts

; Load the three type slots; $FF = unused. Patch gx/gy/gz for loaded types.
load_map_enemies
	ldx #0
	txa
.lme_z
	sta enemy_gx_lo,x
	sta enemy_gx_hi,x
	sta enemy_gy_lo,x
	sta enemy_gy_hi,x
	sta enemy_gz_lo,x
	sta enemy_gz_hi,x
	inx
	cpx #ENEMY_NTYPES
	bcc .lme_z

	ldx #0
.lme_lp
	lda map_type0,x
	cmp #$ff
	beq .lme_n
	sta load_type
	stx map_sv_y
	ldy load_type
	lda enemy_size_lo,y
	ora enemy_size_hi,y
	beq .lme_err
	lda enemy_size_lo,y
	pha
	lda enemy_size_hi,y
	tay
	pla
	jsr heap_alloc
	ldy load_type
	lda en_name_len,y
	pha
	lda en_name_lo,y
	tax
	lda en_name_hi,y
	tay
	pla
	jsr LoadPrg
	bcs .lme_err
	jsr patch_enemy_gx
	ldx map_sv_y
.lme_n
	inx
	cpx #MAP_MAX_TYPES
	bcc .lme_lp
	clc
	rts
.lme_err
	sec
	rts

; dest in load_dest; type in load_type. Pose: [nframes][gx…][gy…][gz…]
patch_enemy_gx
	ldy load_type
	clc
	lda load_dest
	adc #1
	sta enemy_gx_lo,y
	lda load_dest+1
	adc #0
	sta enemy_gx_hi,y
	ldx enemy_nframes,y
	clc
	lda enemy_gx_lo,y
	adc frame13_lo,x
	sta enemy_gy_lo,y
	lda enemy_gx_hi,y
	adc frame13_hi,x
	sta enemy_gy_hi,y
	clc
	lda enemy_gy_lo,y
	adc frame13_lo,x
	sta enemy_gz_lo,y
	lda enemy_gy_hi,y
	adc frame13_hi,x
	sta enemy_gz_hi,y
	rts

!macro bind_add .ptr, .n {
	lda bind_cur
	sta .ptr
	lda bind_cur+1
	sta .ptr+1
	clc
	lda bind_cur
	adc .n
	sta bind_cur
	lda bind_cur+1
	adc #0
	sta bind_cur+1
}

; Walk packed SoA at map_base; fill counts, spawn bytes, and field pointers.
bind_map
	lda map_base
	sta src_ptr
	lda map_base+1
	sta src_ptr+1
	ldy #0
.bm_hdr
	lda (src_ptr),y
	sta map_nrooms,y
	iny
	cpy #24
	bne .bm_hdr

	clc
	lda map_base
	adc #24
	sta map_name
	lda map_base+1
	adc #0
	sta map_name+1

	ldy #24
.bm_nm
	lda (src_ptr),y
	beq .bm_nm0
	iny
	bne .bm_nm
.bm_nm0
	iny					; skip NUL
	tya
	clc
	adc map_base
	sta bind_cur
	lda map_base+1
	adc #0
	sta bind_cur+1

	+bind_add room_x, map_nrooms
	+bind_add room_y, map_nrooms
	+bind_add room_z, map_nrooms
	+bind_add room_sx, map_nrooms
	+bind_add room_sy, map_nrooms
	+bind_add room_sz, map_nrooms
	+bind_add room_bg, map_nrooms
	+bind_add room_line, map_nrooms
	+bind_add room_fx, map_nrooms
	+bind_add room_wpn, map_nrooms
	+bind_add room_id, map_nrooms

	lda map_nrooms
	asl
	clc
	adc map_nrooms
	sta bind_n				; nrooms*3
	+bind_add rc_x, bind_n
	+bind_add rc_y, bind_n
	+bind_add rc_z, bind_n
	+bind_add rc_sx, bind_n
	+bind_add rc_sy, bind_n
	+bind_add rc_sz, bind_n

	lda map_nrooms
	asl
	sta bind_n				; nrooms*2
	+bind_add rb_x, bind_n
	+bind_add rb_y, bind_n
	+bind_add rb_z, bind_n
	+bind_add rb_sx, bind_n
	+bind_add rb_sy, bind_n
	+bind_add rb_sz, bind_n

	+bind_add room_nv, map_nrooms
	+bind_add room_ne, map_nrooms
	+bind_add room_vo, map_nrooms
	+bind_add room_eo, map_nrooms
	+bind_add room_nx, map_nrooms
	+bind_add room_nz, map_nrooms
	+bind_add room_uo, map_nrooms
	+bind_add room_zo, map_nrooms
	+bind_add room_ux, map_nux
	+bind_add room_uz, map_nuz
	+bind_add room_vy, map_nvert
	+bind_add room_xid, map_nvert
	+bind_add room_zid, map_nvert
	+bind_add room_col, map_nvert
	+bind_add room_e0, map_nedge
	+bind_add room_e1, map_nedge
	+bind_add room_evert, map_nedge
	+bind_add room_efaces, map_nedge

	+bind_add door_x, map_ndoors
	+bind_add door_y, map_ndoors
	+bind_add door_z, map_ndoors
	+bind_add door_sx, map_ndoors
	+bind_add door_sy, map_ndoors
	+bind_add door_sz, map_ndoors
	+bind_add door_ra, map_ndoors
	+bind_add door_rb, map_ndoors
	+bind_add door_home_y, map_ndoors
	+bind_add door_face, map_ndoors
	+bind_add door_key, map_ndoors
	+bind_add door_id, map_ndoors

	+bind_add crate_x, map_ncrates
	+bind_add crate_y, map_ncrates
	+bind_add crate_z, map_ncrates
	+bind_add crate_sx, map_ncrates
	+bind_add crate_sy, map_ncrates
	+bind_add crate_sz, map_ncrates
	+bind_add crate_room, map_ncrates
	+bind_add crate_id, map_ncrates

	+bind_add slope_x, map_nslopes
	+bind_add slope_y, map_nslopes
	+bind_add slope_z, map_nslopes
	+bind_add slope_sx, map_nslopes
	+bind_add slope_sy, map_nslopes
	+bind_add slope_sz, map_nslopes
	+bind_add slope_axis, map_nslopes
	+bind_add slope_dir, map_nslopes
	+bind_add slope_room, map_nslopes
	+bind_add slope_id, map_nslopes

	+bind_add plat_x, map_nplats
	+bind_add plat_y, map_nplats
	+bind_add plat_z, map_nplats
	+bind_add plat_sx, map_nplats
	+bind_add plat_sz, map_nplats
	+bind_add plat_room, map_nplats
	+bind_add plat_solid, map_nplats
	+bind_add plat_id, map_nplats

	+bind_add elev_x, map_nelevs
	+bind_add elev_y0, map_nelevs
	+bind_add elev_z, map_nelevs
	+bind_add elev_sx, map_nelevs
	+bind_add elev_sy, map_nelevs
	+bind_add elev_sz, map_nelevs
	+bind_add elev_type, map_nelevs
	+bind_add elev_home, map_nelevs
	+bind_add elev_dest, map_nelevs
	+bind_add elev_room, map_nelevs
	+bind_add elev_id, map_nelevs

	+bind_add sw_x, map_nswitches
	+bind_add sw_y, map_nswitches
	+bind_add sw_z, map_nswitches
	+bind_add sw_sx, map_nswitches
	+bind_add sw_sy, map_nswitches
	+bind_add sw_sz, map_nswitches
	+bind_add sw_elev, map_nswitches
	+bind_add sw_room, map_nswitches
	+bind_add sw_face, map_nswitches
	+bind_add sw_id, map_nswitches

	+bind_add en_x, map_nenemies
	+bind_add en_y, map_nenemies
	+bind_add en_z, map_nenemies
	+bind_add en_type, map_nenemies
	+bind_add en_rot, map_nenemies
	+bind_add en_room, map_nenemies
	+bind_add en_patrol, map_nenemies
	+bind_add en_id, map_nenemies

	+bind_add tr_x, map_ntrigs
	+bind_add tr_y, map_ntrigs
	+bind_add tr_z, map_ntrigs
	+bind_add tr_sx, map_ntrigs
	+bind_add tr_sy, map_ntrigs
	+bind_add tr_sz, map_ntrigs
	+bind_add tr_room, map_ntrigs
	+bind_add tr_purpose, map_ntrigs
	+bind_add tr_arg, map_ntrigs
	+bind_add tr_id, map_ntrigs

	+bind_add td_x, map_ndests
	+bind_add td_y, map_ndests
	+bind_add td_z, map_ndests
	+bind_add td_rot, map_ndests
	+bind_add td_room, map_ndests

	+bind_add bp_x, map_nbackpacks
	+bind_add bp_y, map_nbackpacks
	+bind_add bp_z, map_nbackpacks
	+bind_add bp_type, map_nbackpacks
	+bind_add bp_room, map_nbackpacks
	+bind_add bp_id, map_nbackpacks

	lda bind_cur
	sta map_text
	lda bind_cur+1
	sta map_text+1
	rts

; Restore ZP clobbered by KERNAL LOAD (mesh/edge ptrs, key latch).
game_zp_init
	lda #0
	sta keys
	sta anim_acc_l
	sta anim_acc_h
	lda #NVERTS
	sta mesh_nv
	lda #NEDGES
	sta mesh_ne
	lda #<enemy_edges
	sta edge_ptr
	lda #>enemy_edges
	sta edge_ptr+1
	lda #<enemy_edge_vert
	sta edge_vert_ptr
	lda #>enemy_edge_vert
	sta edge_vert_ptr+1
	rts

; In-play reload: keep HP / ammo / weapons. C=0 ok.
restart_level
	lda #1
	sta load_in_play
	jsr LoadLevel
	lda #0
	sta load_in_play
	bcs .rl_fail

	sei
	lda #BANK_IO
	sta $01
	jsr fill_colour
	jsr init_vic
	jsr init_irq
	jsr play_sound_init
	jsr init_weapon_hw
	ldx cur_weapon
	jsr setup_weapon
	lda #BANK_RAM
	sta $01
	jsr game_zp_init
	jsr world_init
	lda #BANK_IO
	sta $01
	jsr init_hud
	jsr hud_ammo
	jsr hud_powerup
	lda #BANK_RAM
	sta $01
	cli
	clc
.rl_fail
	rts

; TRIG_END: next e1mN, or episode done → menu endings.
next_level
	lda level_num
	cmp #MAP_NLEVELS
	bcs episode_done
	inc level_num
	jsr restart_level
	bcs episode_done
	rts

episode_done
	lda #1
	sta game_complete
	jmp REBOOT_STUB

install_reboot_stub
	lda #$4c
	sta REBOOT_STUB
	lda #<reboot_game
	sta REBOOT_STUB+1
	lda #>reboot_game
	sta REBOOT_STUB+2
	rts

; Reload boot (quake64) and re-enter menu.
reboot_game
	sei
	lda #BANK_IO
	sta $01
	ldx #$ff
	txs
	jsr $ff84
	lda $d011
	and #%11101111
	sta $d011
	lda #0
	sta $d015
	sta $d020
	sta $d021
	lda #7
	ldx #< .rg_name
	ldy #> .rg_name
	jsr $ffbd
	lda #1
	ldx $ba
	ldy #1
	jsr $ffba
	lda #0
	jsr $ffd5
	bcs .rg_hang
	jmp $080d
.rg_hang
	jmp .rg_hang
.rg_name
	!text "QUAKE64"

load_fail_hang
	lda #BANK_IO
	sta $01
	jsr init_vic
	lda #2					; red border
	sta $d020
.lfh
	jmp .lfh
