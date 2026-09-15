; Disk load — maps + enemy poses pack downward from SCR_A ($C000).
; USE_KRILL=1: loadraw, LOAD_TO_API, no IOINIT. Default: KERNAL SETNAM/SETLFS/LOAD.
!zone loader

!source "asset_sizes.asm"
!source "level_prefix.asm"

; Filenames are 0-terminated (Krill README "Basic operation"; KERNAL SETNAM
; takes a length computed at the call).
level_dos_name
	!text "E1M1"
	!byte 0

en_name_lo
	!byte <en_n0, <en_n1, <en_n2, <en_n3, <en_n4, <en_n5, <en_n6, <en_n7
en_name_hi
	!byte >en_n0, >en_n1, >en_n2, >en_n3, >en_n4, >en_n5, >en_n6, >en_n7
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
en_n7	!text "ZOMBIE"
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

!if USE_KRILL {

; LoadPrg — X/Y = 0-terminated name pointer. Dest in load_dest. C=0 ok, C=1 err.
; Krill loadraw with LOAD_TO_API: carry SET on entry takes the destination from
; loadaddrlo/hi instead of the PRG header — which is what this needs, because
; every heap blob (E1M1, GRUNT…) carries header address $0000.
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

} else {

; LoadPrg — X/Y = 0-terminated name. Dest in load_dest (SA=0; heap headers are
; $0000 so SA=1 would load to zero page). Owns the KERNAL prelude: BANK_IO,
; $EA31, IOINIT, $DD00=$38, DEN off. C=0 ok, C=1 err. Leaves I=1, $DD00=$38.
LoadPrg
	stx .lp_lda+1
	sty .lp_lda+2
	sei
	lda #BANK_IO
	sta $01
	ldy #0
.lp_lda
	lda $ffff,y
	beq .lp_got
	iny
	bne .lp_lda
.lp_got
	tya
	ldx .lp_lda+1
	ldy .lp_lda+2
	jsr $ffbd				; SETNAM
	lda #1
	ldx load_device
	ldy #0					; SA=0 → load to X/Y of LOAD
	jsr $ffba				; SETLFS
	; IOINIT restarts CIA1 TA. In-play $0314 is irq_entry (no CIA ack).
	lda $0314
	pha
	lda $0315
	pha
	lda #<$ea31				; KERNAL IRQ
	sta $0314
	lda #>$ea31
	sta $0315
	jsr $ff84				; IOINIT — after $EA31
	lda #$38				; VIC bank 3, IEC idle (IOINIT left bank 0)
	sta $dd00
	lda $d011
	and #%11101111				; DEN off: badlines stall IEC
	sta $d011
	lda #0
	ldx load_dest
	ldy load_dest+1
	cli					; IEC / VICE $FFD5
	jsr $ffd5				; LOAD
	sei					; C intact through lda/sta
	pla
	sta $0315
	pla
	sta $0314
	lda #0
	rol
	pha
	lda #1
	jsr $ffc3				; CLOSE
	jsr load_irq_off
	jsr mulset_init
	lda #$38
	sta $dd00
	pla
	lsr
	rts

; IOINIT can leave CIA2 Timer A generating NMIs. Quiesce CIA2 while
; loading; prof_init restarts both timers afterward for frame timing.
load_cia2_quiet
	lda #0
	sta $dd0e
	sta $dd0f
	sta $02a1				; KERNAL CIA2 ICR shadow; prevent FE88 re-enable
	lda #$7f
	sta $dd0d
	lda $dd0d
	rts

}

; I=1, CIA1 TA off, raster off. $01 = BANK_IO. C and A preserved.
load_irq_off
	sei
	pha
	lda #BANK_IO
	sta $01
	lda #$7f
	sta $dc0d
	lda $dc0d
	lda #0
	sta $d01a
	pla
	rts

blank_screen
	lda #0
	sta $d015
	sta $d020
	sta $d021
	rts

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

; LoadLevel — blank + one E1Mn load (prefix overlay+reloc, then packed map).
; Heap grows down from SCR_A. Prefix is bind/patch overlay + dest words;
; bind_map header/name, SMC-jsr overlay, heap_top = map_base (dump prefix).
; load_in_play=0: cold. =1: in-play. C=0 ok, C=1 error. Caller re-inits VIC/IRQ.
LoadLevel
	sei
	lda #BANK_IO
	sta $01
	lda #$7f
	sta $dc0d				; kill CIA1 Timer A
	lda $dc0d
	lda #0
	sta $d01a				; kill raster IRQ
!if USE_KRILL {
	; NO jsr $ff84. KERNAL IOINIT writes $DD02 = $3F, which is Krill's
	; uninstall signal — the drive-side code tears itself down and the
	; next loadraw hangs forever.
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
} else {
	; LoadPrg owns IOINIT / $EA31 / $DD00 / DEN off.
	jsr blank_screen
}
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
	clc
	adc #<LEVEL_PREFIX
	pha
	lda map_size_hi,x
	adc #>LEVEL_PREFIX
	tay
	pla
	jsr heap_alloc
	bcs .ll_fail
	ldx #<level_dos_name
	ldy #>level_dos_name
	jsr LoadPrg
	bcs .ll_fail
	clc
	lda load_dest
	adc #<LEVEL_PREFIX
	sta map_base
	lda load_dest+1
	adc #>LEVEL_PREFIX
	sta map_base+1
	clc
	lda load_dest
	adc #<RELOC_OFF
	sta reloc_base
	lda load_dest+1
	adc #>RELOC_OFF
	sta reloc_base+1
	jsr bind_map
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
	jsr load_irq_off
	clc
	rts
.ll_fail
	jsr load_irq_off
	sec
	rts

; --- per-room pose streaming ----------------------------------------------
; At most ROOM_MAX_TYPES (2) banks below map_base. Keep types still needed;
; orphans stay loaded when the new room is a subset (AB→A keeps B for a cheap
; double-back). Only dump orphans when a missing type must be loaded (AB→AC
; dumps B). Compacting: dump at heap_top raises it; dump snug with the map
; moves the survivor up. Pose data is draw-only (cube.asm filters en_room).
;
; Bank base for type T = pose_map[T] - 2. First load sits under map_base; the
; second packs below it (heap_top).
; Pose: [n_stored][n_logical][pose_map…][gx…][gy…][gz…]
;       [sfx_count] {id,N,AD,freq,vol}* [evt_count] {logical_frame,id}*

; Distinct types in room_idx → need0/need1 ($FF = empty). Cap 2 by tooling.
collect_room_need
	lda #$ff
	sta need0
	sta need1
	ldx #0
.crn_lp
	cpx map_nenemies
	bcs .crn_rts
	+lda_mx en_room
	cmp room_idx
	bne .crn_n
	+lda_mx en_type
	cmp need0
	beq .crn_n
	cmp need1
	beq .crn_n
	ldy need0
	cpy #$ff
	bne .crn_slot1
	sta need0
	jmp .crn_n
.crn_slot1
	sta need1
.crn_n
	inx
	jmp .crn_lp
.crn_rts
	rts

; C=0 if every needed type is already resident (orphans OK — AB→A is free).
room_need_resident
	ldy need0
	cpy #$ff
	beq .rnr1
	lda pose_map_hi,y
	beq .rnr_no
.rnr1
	ldy need1
	cpy #$ff
	beq .rnr_yes
	lda pose_map_hi,y
	beq .rnr_no
.rnr_yes
	clc
	rts
.rnr_no
	sec
	rts

; Mark every type as not-resident. MUST run before the first residency test of
; a level — otherwise BSS garbage looks like live banks.
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
	sta enemy_sfx_evt_lo,x
	sta enemy_sfx_evt_hi,x
	inx
	cpx #ENEMY_NTYPES
	bcc .cpp
	jsr unbind_streamed_sfx
	rts

; Zero pose ptrs for type A.
clear_one_pose
	tax
	lda #0
	sta enemy_gx_lo,x
	sta enemy_gx_hi,x
	sta enemy_gy_lo,x
	sta enemy_gy_hi,x
	sta enemy_gz_lo,x
	sta enemy_gz_hi,x
	sta pose_map_lo,x
	sta pose_map_hi,x
	sta enemy_sfx_evt_lo,x
	sta enemy_sfx_evt_hi,x
	rts

; src_ptr → dst_ptr, size X=pages Y=frac. dst > src; overlap-safe (high→low).
copy_block_up
	txa
	clc
	adc src_ptr+1
	sta src_ptr+1
	txa
	clc
	adc dst_ptr+1
	sta dst_ptr+1
	cpy #0
	beq .cbu_pages
.cbu_frac
	dey
	lda (src_ptr),y
	sta (dst_ptr),y
	tya
	bne .cbu_frac
.cbu_pages
	cpx #0
	beq .cbu_rts
	dec src_ptr+1
	dec dst_ptr+1
.cbu_page
	dey				; 0 → 255
	lda (src_ptr),y
	sta (dst_ptr),y
	tya
	bne .cbu_page
	dex
	jmp .cbu_pages
.cbu_rts
	rts

; Dump type pose_dump. Compacts if a keeper sits below the dumped bank.
dump_pose_type
	lda #$ff
	sta pose_keep
	ldx #0
.dpt_find
	cpx pose_dump
	beq .dpt_fn
	lda pose_map_hi,x
	beq .dpt_fn
	stx pose_keep
.dpt_fn
	inx
	cpx #ENEMY_NTYPES
	bcc .dpt_find
	lda pose_keep
	cmp #$ff
	bne .dpt_keep
	lda map_base
	sta heap_top
	lda map_base+1
	sta heap_top+1
	lda pose_dump
	jmp clear_one_pose

.dpt_keep
	; dump_base = pose_map[dump]-2 → src_ptr
	ldy pose_dump
	sec
	lda pose_map_lo,y
	sbc #2
	sta src_ptr
	lda pose_map_hi,y
	sbc #0
	sta src_ptr+1
	; keep_base = pose_map[keep]-2 → dst_ptr (scratch)
	ldy pose_keep
	sec
	lda pose_map_lo,y
	sbc #2
	sta dst_ptr
	lda pose_map_hi,y
	sbc #0
	sta dst_ptr+1
	; dump_base < keep_base ⇒ dump is at heap_top
	lda src_ptr
	cmp dst_ptr
	lda src_ptr+1
	sbc dst_ptr+1
	bcc .dpt_lower

	; Dump snug with map: move keep up to map_base - size[keep]
	ldy pose_keep
	lda enemy_size_lo,y
	sta bind_n
	lda enemy_size_hi,y
	sta map_sv_a
	sec
	lda map_base
	sbc bind_n
	sta load_dest
	lda map_base+1
	sbc map_sv_a
	sta load_dest+1
	lda dst_ptr
	sta src_ptr
	lda dst_ptr+1
	sta src_ptr+1
	lda load_dest
	sta dst_ptr
	lda load_dest+1
	sta dst_ptr+1
	ldx map_sv_a			; pages
	ldy bind_n			; frac
	jsr copy_block_up
	ldy pose_keep
	sty load_type
	jsr patch_enemy_gx
	lda load_dest
	sta heap_top
	lda load_dest+1
	sta heap_top+1
	lda pose_dump
	jmp clear_one_pose

.dpt_lower
	; Raise heap_top past the dumped bank
	ldy pose_dump
	clc
	lda src_ptr
	adc enemy_size_lo,y
	sta heap_top
	lda src_ptr+1
	adc enemy_size_hi,y
	sta heap_top+1
	lda pose_dump
	jmp clear_one_pose

; A = type or $FF. Load if absent. C=0 ok, C=1 fail.
load_pose_if_needed
	cmp #$ff
	beq .lpi_ok
	tay
	lda pose_map_hi,y
	bne .lpi_ok
	sty load_type
	lda enemy_size_lo,y
	ora enemy_size_hi,y
	beq .lpi_err
	lda enemy_size_lo,y
	pha
	lda enemy_size_hi,y
	tay
	pla
	jsr heap_alloc
	bcs .lpi_err
	ldy load_type
	lda en_name_lo,y
	tax
	lda en_name_hi,y
	tay
	jsr LoadPrg
	bcs .lpi_err
	jsr patch_enemy_gx
.lpi_ok
	clc
	rts
.lpi_err
	sec
	rts

; Dump orphans then load missing. Only reached when need ⊈ resident, so at
; least one LoadPrg runs. C=0 ok, C=1 out of heap / load fail.
stream_room_enemies
	ldx #0
.sre_dump
	lda pose_map_hi,x
	beq .sre_dn
	txa
	cmp need0
	beq .sre_dn
	cmp need1
	beq .sre_dn
	stx pose_dump
	txa
	pha
	jsr dump_pose_type
	pla
	tax
.sre_dn
	inx
	cpx #ENEMY_NTYPES
	bcc .sre_dump

	lda need0
	jsr load_pose_if_needed
	bcs .sre_err
	lda need1
	jsr load_pose_if_needed
	bcs .sre_err
	jsr rebind_streamed_sfx
	clc
	rts
.sre_err
	sec
	rts

; After movement, before draw_enemies. AB→A keeps orphans and skips the swap.
; In-play LoadPrg (KERNAL $FFD5) CLIs — SEI is not enough. Mask $d01a like
; LoadLevel or a raster IRQ hits $0314 while KERNAL is paged in.
maybe_stream_room
	lda room_idx
	cmp stream_room
	beq .msr_rts
	jsr collect_room_need
	jsr room_need_resident
	bcc .msr_mark
	php
	sei
	lda $01
	pha
	lda #BANK_IO
	sta $01
	lda #0
	sta $d01a
	lda #1
	sta $d019
	lda #0
	sta col_bg
	sta col_line
	jsr fill_viewport_colour
	lda #0
	sta $d021
	lda $d011
	and #%11101111				; DEN off: badlines stall IEC
	sta $d011
	jsr stream_room_enemies
	bcs .msr_fail
	lda $d011
	ora #%00010000
	sta $d011
	jsr apply_room_palette
	jsr fill_viewport_colour
	lda col_bg
	sta $d021
	jsr install_irq_vectors
!if USE_KRILL = 0 {
	jsr prof_init				; IOINIT in LoadPrg reset CIA2 cascade
}
	lda #0
	sta irq_phase
	lda #RASTER_VIEW
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #1
	sta $d019
	sta $d01a
	pla
	sta $01
	plp
.msr_mark
	lda room_idx
	sta stream_room
.msr_rts
	rts
.msr_fail
	jmp load_fail_hang

; dest in load_dest; type in load_type.
; Pose: [n_stored][n_logical][pose_map…][gx…][gy…][gz…] [sfx blob]
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

; Stop streamed SID voices, zero their table slots, bind every resident type.
rebind_streamed_sfx
	jsr stop_streamed_sfx
	jsr unbind_streamed_sfx
	ldx #0
.rsx_lp
	lda pose_map_hi,x
	beq .rsx_n
	txa
	pha
	jsr bind_type_sfx
	pla
	tax
.rsx_n
	inx
	cpx #ENEMY_NTYPES
	bcc .rsx_lp
	rts

; A = type. Walk trailing sfx blob; sound_table[id] → N,AD,freq,vol.
; src_ptr then at evt table → enemy_sfx_evt_*[type].
bind_type_sfx
	sta map_sv_y
	tay
	lda pose_map_hi,y
	bne .bts_go
	rts
.bts_go
	ldx enemy_nframes,y
	clc
	lda enemy_gz_lo,y
	adc frame13_lo,x
	sta src_ptr
	lda enemy_gz_hi,y
	adc frame13_hi,x
	sta src_ptr+1
	ldy #0
	lda (src_ptr),y
	sta bind_n
	inc src_ptr
	bne .bts_lp
	inc src_ptr+1
.bts_lp
	lda bind_n
	bne .bts_one
	ldx map_sv_y
	lda src_ptr
	sta enemy_sfx_evt_lo,x
	lda src_ptr+1
	sta enemy_sfx_evt_hi,x
	rts
.bts_one
	ldy #0
	lda (src_ptr),y
	asl
	tax
	clc
	lda src_ptr
	adc #1
	sta sound_table,x
	lda src_ptr+1
	adc #0
	sta sound_table+1,x
	ldy #1
	lda (src_ptr),y
	sta map_sv_a
	asl
	tax
	lda #0
	rol
	tay
	txa
	clc
	adc #3
	tax
	tya
	adc #0
	tay
	txa
	clc
	adc src_ptr
	sta src_ptr
	tya
	adc src_ptr+1
	sta src_ptr+1
	dec bind_n
	jmp .bts_lp

; Walk packed SoA at map_base; fill counts, spawn bytes, and field pointers.
; Overlay at load_dest+OVERLAY_OFF binds columns then patches SMC operands.
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

	clc
	lda load_dest
	adc #<OVERLAY_OFF
	sta .bm_ov+1
	lda load_dest+1
	adc #>OVERLAY_OFF
	sta .bm_ov+2
	clc
	lda load_dest
	adc #<BIND_TAB_OFF
	pha
	lda load_dest+1
	adc #>BIND_TAB_OFF
	tay
	pla
.bm_ov
	jsr $ffff
	php
	lda bind_cur
	sta map_text
	lda bind_cur+1
	sta map_text+1
	plp
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

; Player died: freeze, wait for scream + 1s, starting loadout, reload this map.
PL_DEATH_WAIT_MS	= 1000

death_restart
	ldx #$ff
	txs
.dw_q
	lda sfx_q_len
	bne .dw_q
.dw_sfx
	lda sfx_index
	bpl .dw_sfx
	lda #0
	sta death_wait_l
	sta death_wait_h
.dw_hold
	lda frame_flag
.dw_hold_f
	cmp frame_flag
	beq .dw_hold_f
	clc
	lda death_wait_l
	adc sample_ms
	sta death_wait_l
	lda death_wait_h
	adc #0
	sta death_wait_h
	cmp #>PL_DEATH_WAIT_MS
	bcc .dw_hold
	bne .dw_go
	lda death_wait_l
	cmp #<PL_DEATH_WAIT_MS
	bcc .dw_hold
.dw_go
	sei
	jsr reset_loadout
	jsr restart_level
	bcc .dw_ok
	jmp load_fail_hang
.dw_ok
	jmp main

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
	jsr game_zp_init
	jsr fill_colour
	jsr init_vic
	jsr init_irq
	jsr prof_init
	jsr play_sound_init
	jsr init_weapon_hw
	ldx cur_weapon
	jsr setup_weapon
	lda #BANK_RAM
	sta $01
	jsr clear_charsets
	jsr fill_margin_glyph
	lda #BANK_IO
	sta $01
	jsr init_hud
	jsr hud_ammo
	jsr hud_powerup
	lda #BANK_RAM
	sta $01
	jsr mulset_init
	jsr world_init
	jsr maybe_stream_room
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
	; DELIBERATE on the Krill disk, and the only surviving IOINIT. $DD02 = $3F
	; uninstalls the drive code and hands the drive back to normal DOS, which
	; is exactly what the KERNAL LOAD below needs. splashc re-installs on the
	; Krill disk; the KERNAL disk never had drive code up.
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
	ldx load_device
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
