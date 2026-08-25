; Disk load — Krill fastloader (loadraw, LOAD_TO_API), $01 = BANK_LOADER
; during the call, BANK_IO otherwise. Was a Wolf64-style KERNAL sequence.
; Maps + enemy poses pack downward from SCR_A ($C000).
!zone loader

!source "asset_sizes.asm"

; Krill filenames are 0-terminated (README "Basic operation"); the KERNAL took
; an explicit length instead, so every name below gained a terminator and the
; en_name_len table went away.
level_dos_name
	!text "E1M1"
	!byte 0
reloc_dos_name
	!text "RELOC"
	!byte 0

en_name_lo
	!byte <en_n0, <en_n1, <en_n2, <en_n3, <en_n4, <en_n5, <en_n6
en_name_hi
	!byte >en_n0, >en_n1, >en_n2, >en_n3, >en_n4, >en_n5, >en_n6
en_n0	!text "GRUNT"
	!byte 0
en_n1	!text "KNIGHT"
	!byte 0
en_n2	!text "ROTT"
	!byte 0
en_n3	!text "SCRAG"
	!byte 0
en_n4	!text "OGRE"
	!byte 0
en_n5	!text "SHAMBL"
	!byte 0
en_n6	!text "CHTHON"
	!byte 0

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

; LoadPrg — X/Y = 0-terminated name pointer. Dest in load_dest. C=0 ok, C=1 err.
; Krill loadraw with LOAD_TO_API: carry SET on entry takes the destination from
; loadaddrlo/hi instead of the PRG header — which is what this needs, because
; every heap blob (E1M1, RELOC, GRUNT…) carries header address $0000.
; A is ignored; callers no longer pass a length.
; Returns with interrupts DISABLED (see the sei below); callers already sei.
LoadPrg
	stx load_name_l
	sty load_name_h
	lda load_dest
	sta loadaddrlo
	lda load_dest+1
	sta loadaddrhi
	sei					; BANK_LOADER unmaps the KERNAL, so the
						; IRQ vector would come from RAM at $fffe
	lda #BANK_LOADER
	sta $01
	ldx load_name_l
	ldy load_name_h
	sec					; carry SET → use loadaddrlo/hi
	jsr loadraw
	php
	lda #BANK_IO
	sta $01
	plp
	rts

blank_screen
	lda #0
	sta $d015
	sta $d020
	sta $d021
	rts

; load_cia2_quiet removed with the jsr $ff84 calls: it existed only because
; KERNAL IOINIT could leave CIA2 Timer A generating NMIs. Krill touches CIA2
; PRA/DDRA only, and never enables its timers.

; Fill frame13_lo/hi[i] = i*13 (pose gx/gy/gz stride). Called each LoadLevel.
init_frame13
	ldx #0
	lda #0
	sta nlo
	sta nhi
.f13
	lda nlo
	sta frame13_lo,x
	lda nhi
	sta frame13_hi,x
	clc
	lda nlo
	adc #13
	sta nlo
	lda nhi
	adc #0
	sta nhi
	inx
	cpx #FRAME13_N
	bcc .f13
	rts

; A=size lo, Y=size hi → load_dest = heap_top = heap_top - size.
; C=0 ok; C=1 would overlap GAME (new top <= end_game). heap_top unchanged on fail.
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
	lda #<end_game
	cmp load_dest
	lda #>end_game
	sbc load_dest+1
	bcs .ha_fail				; end_game >= new top
	lda load_dest
	sta heap_top
	lda load_dest+1
	sta heap_top+1
	clc
	rts
.ha_fail
	sec
	rts

; LoadLevel — blank + map + reloc overlay + enemies, all via Krill.
; Heap grows down from SCR_A: map first, then RELOC below it, bind_map on
; map_base only, patch SMC operands, heap_top = map_base (drop reloc),
; then the reloc bytes are reclaimed as the per-room pose sub-heap.
; load_in_play=0: cold (DEN off). =1: in-play (init_vic, DEN on).
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
	; NO jsr $ff84 on either path. KERNAL IOINIT writes $DD02 = $3F, which is
	; Krill's uninstall signal — the drive-side code tears itself down and the
	; next loadraw hangs forever. Measured on VICE with true drive emulation:
	; NOTES.md "PHASE 1 RESULT", variants C and D. IOINIT was only ever here
	; to serve KERNAL LOAD, which this no longer uses.
	; Interrupts stay off for the whole load: LoadPrg banks the KERNAL out.
	lda load_in_play
	beq .ll_cold
	jsr init_vic				; DEN on before blank/load
	jmp .ll_common
.ll_cold
	jsr blank_screen
	lda $d011
	and #%11101111				; DEN off
	sta $d011
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
	jsr init_frame13

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
	bcs .ll_fail
	ldx #<level_dos_name
	ldy #>level_dos_name
	jsr LoadPrg
	bcs .ll_fail
	lda load_dest
	sta map_base
	lda load_dest+1
	sta map_base+1
	jsr bind_map

	lda #<RELOC_MAX
	ldy #>RELOC_MAX
	jsr heap_alloc
	bcs .ll_fail
	lda load_dest
	sta reloc_base
	lda load_dest+1
	sta reloc_base+1
	ldx #<reloc_dos_name
	ldy #>reloc_dos_name
	jsr LoadPrg
	bcs .ll_fail
	jsr patch_map_smc
	bcs .ll_fail
	lda map_base
	sta heap_top
	lda map_base+1
	sta heap_top+1

	; No level-wide enemy load any more: maybe_stream_room pulls the current
	; room's types once world_init has set room_idx. Establish "nothing
	; resident" for real -- the flags live in BSS and are not zero on entry.
	jsr clear_pose_ptrs
	lda #$ff
	sta stream_room

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

; --- per-room pose streaming ----------------------------------------------
; Load only the pose banks the CURRENT room needs, instead of every type the
; level uses. The budget stops being "all types in this level" and becomes
; "the types in one room", which is what buys the headroom.
;
; This is safe because pose data is read ONLY by the draw path (cube.asm),
; which already filters on en_room == room_idx. enemy.asm's update path never
; touches it, so enemies left behind in other rooms keep ticking their state
; machines normally and simply never look at the banks we swapped out. They do
; NOT need killing off.
;
; The pose region is a clean sub-heap: LoadLevel leaves heap_top = map_base and
; these pack downward from there, so reclaiming is just resetting heap_top.
;
; DELIBERATELY NOT DONE: keeping the old room resident while the new one loads.
; That needs heap for both at once, which defeats the whole point. A room swap
; is a full swap. The cost is a ~0.5 s stall on a door crossing, which is a
; level-design problem -- a short enemy-free corridor between heavy rooms hides
; it completely, and is Kweepa's call to make, not ours.

; C=0 if every type this room needs is already resident, so the swap can be
; skipped entirely. Makes doubling back through a door free, and makes rooms
; that add no new types cost nothing.
room_types_resident
	ldx #0
.rtr_lp
	cpx map_nenemies
	bcs .rtr_yes
	+lda_mx en_room
	cmp room_idx
	bne .rtr_n
	+ldy_mx en_type
	lda pose_map_hi,y			; 0 = not loaded (heap never reaches page 0)
	beq .rtr_no
.rtr_n
	inx
	jmp .rtr_lp
.rtr_yes
	clc
	rts
.rtr_no
	sec
	rts

; Mark every type as not-resident. room_types_resident uses pose_map_hi as the
; "is it loaded" flag, so this MUST run before the first residency test of a
; level -- otherwise it reads whatever was left in BSS, concludes the types are
; already present, and the enemies draw through junk pointers.
clear_pose_ptrs
	ldx #0
	txa
.cpp
	sta enemy_gx_lo,x
	sta enemy_gx_hi,x
	sta enemy_gy_lo,x
	sta enemy_gy_hi,x
	sta enemy_gz_lo,x
	sta enemy_gz_hi,x
	sta pose_map_lo,x
	sta pose_map_hi,x
	inx
	cpx #ENEMY_NTYPES
	bcc .cpp
	rts

; Reclaim the pose sub-heap and load every distinct type in room_idx.
; C=0 ok, C=1 out of heap.
stream_room_enemies
	jsr clear_pose_ptrs
	lda map_base				; reclaim everything below the map
	sta heap_top
	lda map_base+1
	sta heap_top+1

	ldx #0
.sre_lp
	cpx map_nenemies
	bcs .sre_ok
	+lda_mx en_room
	cmp room_idx
	bne .sre_n
	+ldy_mx en_type
	lda pose_map_hi,y
	bne .sre_n				; already loaded this pass
	sty load_type
	stx map_sv_y
	lda enemy_size_lo,y
	ora enemy_size_hi,y
	beq .sre_err
	lda enemy_size_lo,y
	pha
	lda enemy_size_hi,y
	tay
	pla
	jsr heap_alloc
	bcs .sre_err
	ldy load_type
	lda en_name_lo,y
	tax
	lda en_name_hi,y
	tay
	jsr LoadPrg
	bcs .sre_err
	jsr patch_enemy_gx
	ldx map_sv_y
.sre_n
	inx
	jmp .sre_lp
.sre_ok
	clc
	rts
.sre_err
	sec
	rts

; Call once per frame after movement, exactly like maybe_room_palette.
; Placed after it in the main loop so the swap completes before the next
; frame's draw_enemies runs against the new room_idx.
maybe_stream_room
	lda room_idx
	cmp stream_room
	beq .msr_rts
	jsr room_types_resident
	bcc .msr_mark
	php					; the load banks $01 and sets I
	lda $01
	pha
	lda #BANK_IO
	sta $01
	jsr stream_room_enemies
	bcs .msr_fail
	pla
	sta $01
	plp
.msr_mark
	lda room_idx
	sta stream_room
.msr_rts
	rts
.msr_fail
	jmp load_fail_hang			; standing rule: crash, never degrade

; dest in load_dest; type in load_type.
; Pose: [n_stored][n_logical][pose_map…][gx…][gy…][gz…]
patch_enemy_gx
	lda load_dest
	sta src_ptr
	lda load_dest+1
	sta src_ptr+1
	ldy load_type
	clc
	lda load_dest
	adc #2
	sta pose_map_lo,y
	lda load_dest+1
	adc #0
	sta pose_map_hi,y
	ldy #1
	lda (src_ptr),y			; n_logical
	ldy load_type
	clc
	adc pose_map_lo,y		; gx = dest+2+n_logical
	sta enemy_gx_lo,y
	lda pose_map_hi,y
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
	jsr maybe_stream_room
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
	; DELIBERATE, and the only surviving IOINIT. $DD02 = $3F uninstalls the
	; Krill drive code and hands the drive back to normal DOS, which is
	; exactly what the KERNAL LOAD below needs. boot re-installs on entry.
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
