; F5/F7 quick save. Loaded over screen A ($C000) by poll_quick_keys.
; Not linked into game.prg. Sprites start at $C800 — stay below that.
; Disk and IRQ kill stay in LoadPrg / SavePrg / maybe_stream_room.
; Exit rebuilds the HUD, then copies B's viewport over this image. The
; copy that covers the exit itself runs from the 16-byte pad at $C3E8.
!cpu 6510
!to "qsave.prg", cbm

!source "build_flags.asm"
!source "mem.asm"
!source "zp.asm"
!source "qsyms.asm"

QS_VERSION	= 1
QB_START	= PROC_KIND		; $CB70
QB_END		= CH_A_TOP		; $D000, exclusive
QS_LOAD		= SCR_B			; header lands here; code stays at $C000
QS_ZP_N		= 13
QS_CRUSH_N	= CRUSH_BSS_END - crush_dir

!if QS_CRUSH_N = 0 {
	!error "crush save range is empty"
}
!if QS_CRUSH_N > 128 {
	!error "crush save loop is bpl-sized"
}

*= SCR_A

; qs_cmd = 0 save, 1 load. C=0 ok. C=1 and A=0: state intact.
; C=1 and A=QS_FAIL_SALVAGE: caller should restart_level.
qs_entry
	lda qs_cmd
	beq +
	jmp qs_load
+
!if USE_KRILL = 0 {
	jmp qs_save
} else {
	lda #0
	sec
	jmp qs_exit
}

!if USE_KRILL = 0 {

; Bind the QB name into the image, checksum that image + the map, then write
; QM, the header, and QB. QM/QS saves mutate load_* ; QB is bound again so the
; bytes on disk match the sum.
qs_save
	jsr qs_pack
	lda #<QB_START
	sta load_dest
	lda #>QB_START
	sta load_dest+1
	lda #<QB_END
	sta save_end
	lda #>QB_END
	sta save_end+1
	ldx #<qb_name
	ldy #>qb_name
	jsr save_bind
	jsr qs_checksum
	lda qs_sum
	sta qs_csum
	lda qs_sum+1
	sta qs_csum+1
	lda map_base
	sta load_dest
	lda map_base+1
	sta load_dest+1
	lda #<SCR_A
	sta save_end
	lda #>SCR_A
	sta save_end+1
	ldx #<qm_name
	ldy #>qm_name
	jsr SavePrg
	bcc +
	jmp qs_soft
+
	lda #<qs_hdr
	sta load_dest
	lda #>qs_hdr
	sta load_dest+1
	lda #<qs_hdr_end
	sta save_end
	lda #>qs_hdr_end
	sta save_end+1
	ldx #<qs_name
	ldy #>qs_name
	jsr SavePrg
	bcc +
	jmp qs_soft
+
	lda #<QB_START
	sta load_dest
	lda #>QB_START
	sta load_dest+1
	lda #<QB_END
	sta save_end
	lda #>QB_END
	sta save_end+1
	ldx #<qb_name
	ldy #>qb_name
	jsr SavePrg
	bcc +
	jmp qs_soft
+
	clc
	jmp qs_exit

}

qs_load
	lda #<QS_LOAD
	sta load_dest
	lda #>QS_LOAD
	sta load_dest+1
	ldx #<qs_name
	ldy #>qs_name
	jsr LoadPrg
	bcc +
	jmp qs_soft
+
	jsr qs_verify_hdr
	bcc +
	jmp qs_soft
+
	lda #0
	sta qs_switched
	lda QS_LOAD + (qs_level - qs_hdr)
	cmp level_num
	beq .ql_base
	sta level_num
	lda #1
	sta qs_switched
	sta load_in_play
	jsr LoadLevel
	php
	lda #0
	sta load_in_play
	plp
	bcc .ql_base
	jmp qs_salvage
.ql_base
	lda QS_LOAD + (qs_map - qs_hdr)
	cmp map_base
	bne .ql_miss
	lda QS_LOAD + (qs_map - qs_hdr) + 1
	cmp map_base+1
	beq .ql_files
.ql_miss
	lda qs_switched
	beq +
	jmp qs_salvage
+
	jmp qs_soft
.ql_files
	lda map_base
	sta load_dest
	lda map_base+1
	sta load_dest+1
	ldx #<qm_name
	ldy #>qm_name
	jsr LoadPrg
	bcs qs_salvage
	lda #<QB_START
	sta load_dest
	lda #>QB_START
	sta load_dest+1
	ldx #<qb_name
	ldy #>qb_name
	jsr LoadPrg
	bcs qs_salvage
	jsr qs_checksum
	lda qs_sum
	cmp QS_LOAD + (qs_csum - qs_hdr)
	bne qs_salvage
	lda qs_sum+1
	cmp QS_LOAD + (qs_csum - qs_hdr) + 1
	bne qs_salvage
	jsr qs_unpack
	lda #$ff
	sta stream_room
	sta palette_room
	ldx #0
.ql_gst
	lda gr_on,x
	sta QS_LOAD,x
	inx
	cpx #GREN_MAX
	bcc .ql_gst
	jsr maybe_stream_room
	ldx #0
.ql_grs
	lda QS_LOAD,x
	sta gr_on,x
	inx
	cpx #GREN_MAX
	bcc .ql_grs
	lda #0
	tay
.ql_zin
	sta in_fwd,y
	iny
	cpy #key_use_was - in_fwd + 1
	bcc .ql_zin
	ldy #0
.ql_zw
	sta in_fire,y
	iny
	cpy #key_wpn_gren - in_fire + 1
	bcc .ql_zw
	clc
	jmp qs_exit

qs_soft
	lda #0
	sec
	jmp qs_exit

qs_salvage
	lda #QS_FAIL_SALVAGE
	sec
	jmp qs_exit

; Magic + version at QS_LOAD. C=0 ok.
qs_verify_hdr
	lda QS_LOAD
	cmp #'Q'
	bne .vh_bad
	lda QS_LOAD+1
	cmp #'6'
	bne .vh_bad
	lda QS_LOAD+2
	cmp #'4'
	bne .vh_bad
	lda QS_LOAD+3
	cmp #'S'
	bne .vh_bad
	lda QS_LOAD+4
	cmp #QS_VERSION
	bne .vh_bad
	clc
	rts
.vh_bad
	sec
	rts

; 16-bit sum of QB then the packed map. Map ends at $C000 (this overlay).
qs_checksum
	lda #0
	sta qs_sum
	sta qs_sum+1
	lda #<QB_START
	sta src_ptr
	lda #>QB_START
	sta src_ptr+1
	lda #<QB_END
	sta qs_lim
	lda #>QB_END
	sta qs_lim+1
	jsr qs_sum_span
	lda map_base
	sta src_ptr
	lda map_base+1
	sta src_ptr+1
	lda #<SCR_A
	sta qs_lim
	lda #>SCR_A
	sta qs_lim+1
	jmp qs_sum_span

qs_sum_span
	ldy #0
.ss
	lda src_ptr+1
	cmp qs_lim+1
	bcc .ss_go
	bne .ss_done
	lda src_ptr
	cmp qs_lim
	bcs .ss_done
.ss_go
	lda (src_ptr),y
	clc
	adc qs_sum
	sta qs_sum
	bcc +
	inc qs_sum+1
+
	inc src_ptr
	bne .ss
	inc src_ptr+1
	jmp .ss
.ss_done
	rts

!if USE_KRILL = 0 {

qs_pack
	lda #'Q'
	sta qs_magic
	lda #'6'
	sta qs_magic+1
	lda #'4'
	sta qs_magic+2
	lda #'S'
	sta qs_magic+3
	lda #QS_VERSION
	sta qs_ver
	lda level_num
	sta qs_level
	lda difficulty
	sta qs_diff
	lda map_base
	sta qs_map
	lda map_base+1
	sta qs_map+1
	ldx #0
.pk_lp
	lda qs_zp_lo,x
	sta .pk+1
.pk
	lda $00
	sta qs_zp,x
	inx
	cpx #QS_ZP_N
	bcc .pk_lp
	ldy #QS_CRUSH_N-1
.pk_cr
	lda crush_dir,y
	sta qs_crush,y
	dey
	bpl .pk_cr
	rts

}

; Header at QS_LOAD → ZP, crusher motion, level, difficulty.
qs_unpack
	lda QS_LOAD + (qs_level - qs_hdr)
	sta level_num
	lda QS_LOAD + (qs_diff - qs_hdr)
	sta difficulty
	ldx #0
.up_lp
	lda qs_zp_lo,x
	sta .up+1
	lda QS_LOAD + (qs_zp - qs_hdr),x
.up
	sta $00
	inx
	cpx #QS_ZP_N
	bcc .up_lp
	ldy #QS_CRUSH_N-1
.up_cr
	lda QS_LOAD + (qs_crush - qs_hdr),y
	sta crush_dir,y
	dey
	bpl .up_cr
	rts

qs_zp_lo
	!byte <cam_xl, <cam_xh, <cam_yl, <cam_yh, <cam_zl, <cam_zh
	!byte <yaw, <pitch, <room_idx, <floor_y, <floor_yl, <pl_on_elev, <msg_on

qs_name	!text "QS"
	!byte 0
qb_name	!text "QB"
	!byte 0
qm_name	!text "QM"
	!byte 0

qs_sum	!byte 0, 0
qs_lim	!byte 0, 0
qs_switched	!byte 0

; On disk as QS. qb/qm names and the sum live past qs_hdr_end.
qs_hdr
qs_magic	!byte 0, 0, 0, 0
qs_ver		!byte 0
qs_csum		!byte 0, 0
qs_level	!byte 0
qs_diff		!byte 0
qs_map		!byte 0, 0
qs_zp		!fill QS_ZP_N, 0
qs_crush	!fill QS_CRUSH_N, 0
qs_hdr_end

; Pad at $C3E8 is 16 bytes, then the sprite pointers. Viewport rows end at
; $C3E8. This block sits in the viewport, so the indexed copy stops at qs_exit
; and the pad finishes the job.
QS_TAIL		= $C3E8

!if * < SCR_A + VIEW_ROW * 40 {
	!error "qsave exit is inside the HUD rows init_hud clears"
}
!if * >= QS_TAIL {
	!error "qsave image reaches the tail pad at $", *
}

; C = status, A = fail code. Both are restored after this image is gone.
; I stays 1; poll_quick_keys unlatches.
qs_exit
	php
	pha
	lda #BANK_RAM
	sta $01
	jsr load_view_trig
	jsr mulset_init
	jsr game_zp_init
	lda #BANK_IO
	sta $01
	jsr init_hud
	jsr hud_ammo
	jsr hud_powerup
	jsr setup_weapon
	ldx #0
	lda #WPN_PTR0
.qx_ptr
	sta $c3f8,x
	sta $c7f8,x
	clc
	adc #1
	inx
	cpx #8
	bcc .qx_ptr
	lda #1
	sta den_arm
	lda $d011
	and #%11101111
	sta $d011
	jsr init_irq
	ldx #qs_tail_end - qs_tail_tmpl - 1
.qx_stub
	lda qs_tail_tmpl,x
	sta QS_TAIL,x
	dex
	bpl .qx_stub
	lda #<(SCR_B + VIEW_ROW * 40)
	sta src_ptr
	lda #>(SCR_B + VIEW_ROW * 40)
	sta src_ptr+1
	lda #<(SCR_A + VIEW_ROW * 40)
	sta dst_ptr
	lda #>(SCR_A + VIEW_ROW * 40)
	sta dst_ptr+1
	ldy #0
.qx1
	lda (src_ptr),y
	sta (dst_ptr),y
	inc src_ptr
	bne +
	inc src_ptr+1
+
	inc dst_ptr
	bne +
	inc dst_ptr+1
+
	lda dst_ptr+1
	cmp #>qs_exit
	bcc .qx1
	bne +
	lda dst_ptr
	cmp #<qs_exit
	bcc .qx1
+
	jmp QS_TAIL

; Copied to QS_TAIL before the copies above. Absolute operands, so the
; bytes run unchanged from the pad. Last instruction returns to poll.
qs_tail_tmpl
	ldx #0
.qt
	lda SCR_B + (qs_exit - SCR_A),x
	sta qs_exit,x
	inx
	cpx #qs_tail_end - qs_exit
	bne .qt
	pla
	plp
	rts
qs_tail_end

!if qs_tail_end - qs_tail_tmpl != $10 {
	!error "qs tail must be exactly 16 bytes"
}
!if qs_tail_end - qs_exit > 255 {
	!error "qsave exit is longer than one indexed copy"
}
!if qs_tail_end > QS_TAIL {
	!error "qsave exit overlaps the tail pad at $", qs_tail_end
}
!if qs_hdr_end - qs_hdr >= VIEW_ROW * 40 {
	!error "QS header reaches matrix B viewport"
}
