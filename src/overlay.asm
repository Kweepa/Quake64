; LoadLevel overlay — PIC (relative branches only; abs to ZP / BSS / GAME).
; Assembled at *$0000, prepended to each map, dumped after bind+patch.
; Entry: AY = bind_tab address. Falls through bind_apply into patch_map_smc.
!cpu 6510
!to "overlay.bin", plain

!source "mem.asm"
!source "zp.asm"
!source "map_bss.asm"

*= 0
overlay_entry
bind_apply
	sta src_ptr
	sty src_ptr+1
.ba_lp
	ldy #0
	lda (src_ptr),y
	sta dst_ptr
	iny
	lda (src_ptr),y
	sta dst_ptr+1
	ora dst_ptr
	beq patch_map_smc
	lda dst_ptr+1
	bne .ba_fld
	lda dst_ptr
	cmp #1
	beq .ba_n3
	cmp #2
	beq .ba_n2
.ba_fld
	ldy #0
	lda bind_cur
	sta (dst_ptr),y
	iny
	lda bind_cur+1
	sta (dst_ptr),y
	ldy #2
	lda (src_ptr),y
	sta dst_ptr
	iny
	lda (src_ptr),y
	sta dst_ptr+1
	clc
	ldy #0
	lda bind_cur
	adc (dst_ptr),y
	sta bind_cur
	bcc .ba_nxt
	inc bind_cur+1
.ba_nxt
	clc
	lda src_ptr
	adc #4
	sta src_ptr
	bcc .ba_lp
	inc src_ptr+1
	bcs .ba_lp
.ba_n3
	lda map_nrooms
	asl
	clc
	adc map_nrooms
	sta bind_n
	clc
	bcc .ba_nxt
.ba_n2
	lda map_nrooms
	asl
	sta bind_n
	clc
	bcc .ba_nxt

; Reloc: count word, then count × (dest word, field id byte).
patch_map_smc
	lda reloc_base
	sta src_ptr
	lda reloc_base+1
	sta src_ptr+1
	ldy #0
	lda (src_ptr),y
	sta nlo
	iny
	lda (src_ptr),y
	sta nhi
	ora nlo
	bne .go
	sec
	rts
.go
	clc
	lda src_ptr
	adc #2
	sta src_ptr
	bcc .ps
	inc src_ptr+1
.ps
	ldy #0
	lda (src_ptr),y
	sta dst_ptr
	iny
	lda (src_ptr),y
	sta dst_ptr+1
	iny
	lda (src_ptr),y
	asl
	bcs .hi
	tay
	lda room_x,y
	sta mp_l
	lda room_x+1,y
	sta mp_h
	clc
	bcc .wr
.hi
	tay
	lda room_x + $100,y
	sta mp_l
	lda room_x + $101,y
	sta mp_h
.wr
	ldy #0
	lda mp_l
	sta (dst_ptr),y
	iny
	lda mp_h
	sta (dst_ptr),y
	clc
	lda src_ptr
	adc #3
	sta src_ptr
	bcc .dec
	inc src_ptr+1
.dec
	lda nlo
	bne .d1
	dec nhi
.d1
	dec nlo
	lda nlo
	ora nhi
	bne .ps
	clc
	rts

; +bind_add lines: tools/perroom.py replays packed order from this table.
!macro bind_add .ptr, .n {
	!word .ptr
	!word .n
}
!macro bind_set_n3 {
	!word 1
	!word 0
}
!macro bind_set_n2 {
	!word 2
	!word 0
}

bind_tab
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
	+bind_set_n3
	+bind_add rc_x, bind_n
	+bind_add rc_y, bind_n
	+bind_add rc_z, bind_n
	+bind_add rc_sx, bind_n
	+bind_add rc_sy, bind_n
	+bind_add rc_sz, bind_n
	+bind_set_n2
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
	+bind_add room_door_o, map_nrooms
	+bind_add room_ndoor, map_nrooms
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
	+bind_add door_face, map_ndoors
	+bind_add door_key, map_ndoors
	+bind_add door_type, map_ndoors
	+bind_add door_id, map_ndoors
	+bind_add door_other, map_ndoors
	+bind_add door_tag, map_ndoors
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
	+bind_add slope_flags, map_nslopes
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
	+bind_add sw_kind, map_nswitches
	+bind_add sw_tag, map_nswitches
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
	!word 0, 0
