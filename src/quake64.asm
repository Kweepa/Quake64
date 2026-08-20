; Quake64 — Step 2 portal-room E1M1
!cpu 6510
!to "quake64.prg", cbm

; --- build flags (Wolf64-style) -------------------------------------------
PROFILE		= 0				; 1 = R/P/K/D bucket HUD + CIA samples

!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"

*= $0801
!byte $0b, $08, $0a, $00, $9e, $32, $30, $36, $31, $00, $00, $00	; SYS 2061

*= $080d
start
	sei
	cld
	ldx #$ff
	txs
	lda #$35
	sta $01

	lda #0
	sta keys
	sta anim_frames
	sta anim_frames+1
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

	jsr fill_colour
	jsr init_vic
	jsr fill_screens
	jsr stamp_viewport
	jsr stamp_margins
	jsr clear_charsets
	jsr fill_margin_glyph
	jsr copy_luts
	jsr init_hud
	jsr init_irq
	jsr play_sound_init
	jsr init_weapon
	jsr prof_init
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
	lda #$34
	sta $01
	jsr clear_draw
!if PROFILE = 1 {
	ldy #PROF_CLEAR
	jsr prof_add_bucket
}
	jsr draw_world
	jsr draw_enemies
	lda #$35
	sta $01

	lda draw_buf
	sta show_buf
	jsr apply_show
	jsr prof_frame_sample
	jsr calc_frame_dt
	jsr hud_print
	jsr hud_message

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
	jsr sync_eye
	jsr update_message
	jsr advance_walk
	jmp main

advance_walk
	clc
	lda anim_acc_l
	adc dt_ms
	sta anim_acc_l
	lda anim_acc_h
	adc dt_msh
	sta anim_acc_h
.aw_try
	lda anim_acc_h
	cmp #>ANIM_MS
	bcc .done
	bne .step
	lda anim_acc_l
	cmp #<ANIM_MS
	bcc .done
.step
	sec
	lda anim_acc_l
	sbc #<ANIM_MS
	sta anim_acc_l
	lda anim_acc_h
	sbc #>ANIM_MS
	sta anim_acc_h
	ldx #0
.aw_type
	inc anim_frames,x
	lda anim_frames,x
	cmp enemy_anim_len,x
	bcc +
	lda #0
	sta anim_frames,x
+
	inx
	cpx #ENEMY_NTYPES
	bcc .aw_type
	jmp .aw_try
.done
	rts

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
	lda $01
	pha
	lda #$34
	sta $01
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
	pla
	sta $01
	rts

copy_luts
	lda $01
	pha
	lda #$34
	sta $01
	lda #<lut_src
	sta src_ptr
	lda #>lut_src
	sta src_ptr+1
	lda #<LOGTAB
	sta dst_ptr
	lda #>LOGTAB
	sta dst_ptr+1
	ldx #LUT_PAGES
	ldy #0
.copy
	lda (src_ptr),y
	sta (dst_ptr),y
	iny
	bne .copy
	inc src_ptr+1
	inc dst_ptr+1
	dex
	bne .copy
	pla
	sta $01
	rts

!source "vic.asm"
!source "irq.asm"
!source "profil.asm"
!source "hud.asm"
!source "math.asm"
!source "line.asm"
!source "playsound.asm"
!source "pcsounds.asm"
!source "pcsfreq.asm"
!source "weapon.asm"
!source "weapon_spr.asm"
!source "process.asm"
!source "door.asm"
!source "world.asm"
!source "mesh.asm"
!source "cube.asm"

!source "map_e1m1.asm"

lut_src
	!source "tables.asm"
lut_end
!if lut_end - lut_src != 1280 {
	!error "LUT blob must be 1280 bytes"
}

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
