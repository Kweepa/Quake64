!macro sk_umul .s1l, .s2l, .s1h, .s2h, .lo, .hi {
	sec
	lda (.s1l),y
	sbc (.s2l),y
	sta .lo
	lda (.s1h),y
	sbc (.s2h),y
	sta .hi
}

!macro sk_neg16 .lo, .hi {
	sec
	lda #0
	sbc .lo
	sta .lo
	lda #0
	sbc .hi
	sta .hi
}

; .lo:.hi = .lo:.hi ± nlo:nhi. Adds when N is set on entry.
!macro sk_acc .lo, .hi {
	bmi .add
	sec
	lda .lo
	sbc nlo
	sta .lo
	lda .hi
	sbc nhi
	sta .hi
	jmp .done
.add
	clc
	lda .lo
	adc nlo
	sta .lo
	lda .hi
	adc nhi
	sta .hi
.done
}

; .lo:.hi <<= skel_xl, or >>= skel_xr (arithmetic). Clobbers X.
!macro sk_xshift .lo, .hi {
	ldx skel_xl
	beq .r
.l
	asl .lo
	rol .hi
	dex
	bne .l
	beq .done
.r
	ldx skel_xr
	beq .done
.rl
	lda .hi
	cmp #$80
	ror .hi
	ror .lo
	dex
	bne .rl
.done
}

; x' = lx*cos − lz*sin, z' = lx*sin + lz*cos, then >>2 and <<shift in one
; net shift. Set A holds |cos|, set B |sin|; signs are applied per term.
; Y = gy << (5 + shift). Results land in skel_c*, not $CA00.
; The origin drops by skel_sink (yaw-only view, so world Y = view Y).
skel_rotate
	jsr ent_set_pose
	ldx ent_type
	lda skel_base_lo,x
	sta src_ptr
	lda skel_base_hi,x
	sta src_ptr+1
	ldy #SKEL_PFX_SHIFT
	lda (src_ptr),y
	sta skel_sh
	ldx #0
	stx skel_xl
	stx skel_xr
	stx skel_yl
	stx skel_yr
	sec
	sbc #2
	bcc +
	sta skel_xl
	jmp .sr_ysh
+
	eor #$ff
	adc #1
	sta skel_xr
.sr_ysh
	lda skel_sh
	sec
	sbc #3
	bcc +
	sta skel_yl
	jmp .sr_trig
+
	eor #$ff
	adc #1
	sta skel_yr
.sr_trig
	sec
	lda yaw
	sbc ent_rot
	tay
	lda COSTAB,y
	sta sg_a
	sta skel_cs
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta pa_s1l
	sta pa_s1h
	eor #$ff
	sta pa_s2l
	sta pa_s2h
	lda SINTAB,y
	sta sg_b
	sta skel_ss
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta pb_s1l
	sta pb_s1h
	eor #$ff
	sta pb_s2l
	sta pb_s2h
	lda CAM_X
	sta org_xl
	lda CAM_XH
	sta org_xh
	sec
	lda CAM_Y
	sbc skel_sink
	sta org_yl
	lda CAM_YH
	sbc skel_sinkh
	sta org_yh
	lda CAM_Z
	sta org_zl
	lda CAM_ZH
	sta org_zh
	lda #0
	sta gidx
.srvert
	ldy gidx
	lda (gx_ptr),y
	sta skel_lxs
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta skel_lxa
	lda (gz_ptr),y
	sta skel_lzs
	bpl +
	eor #$ff
	clc
	adc #1
+
	sta skel_lza

	ldy skel_lxa
	+sk_umul pa_s1l, pa_s2l, pa_s1h, pa_s2h, e0x, e0xh
	lda skel_lxs
	eor skel_cs
	bpl +
	+sk_neg16 e0x, e0xh
+
	ldy skel_lza
	+sk_umul pb_s1l, pb_s2l, pb_s1h, pb_s2h, nlo, nhi
	lda skel_lzs
	eor skel_ss
	+sk_acc e0x, e0xh

	ldy skel_lxa
	+sk_umul pb_s1l, pb_s2l, pb_s1h, pb_s2h, e1z, e1zh
	lda skel_lxs
	eor skel_ss
	bpl +
	+sk_neg16 e1z, e1zh
+
	ldy skel_lza
	+sk_umul pa_s1l, pa_s2l, pa_s1h, pa_s2h, nlo, nhi
	lda skel_lzs
	eor skel_cs
	eor #$80
	+sk_acc e1z, e1zh

	+sk_xshift e0x, e0xh
	+sk_xshift e1z, e1zh
	ldx gidx
	clc
	lda org_xl
	adc e0x
	sta skel_cx,x
	lda org_xh
	adc e0xh
	sta skel_cxh,x
	clc
	lda org_zl
	adc e1z
	sta skel_cz,x
	lda org_zh
	adc e1zh
	sta skel_czh,x

	ldy gidx
	lda #0
	sta e0y
	lda (gy_ptr),y
	ldx skel_yr
	beq .sr_yl
.sr_yr
	cmp #$80
	ror
	ror e0y
	dex
	bne .sr_yr
.sr_yl
	ldx skel_yl
	beq .sr_yd
.sr_yll
	asl e0y
	rol
	dex
	bne .sr_yll
.sr_yd
	sta e0yh
	ldx gidx
	clc
	lda org_yl
	adc e0y
	sta skel_cy,x
	lda org_yh
	adc e0yh
	sta skel_cyh,x
	inc gidx
	ldx ent_type
	lda gidx
	cmp skel_nv,x
	beq +
	jmp .srvert
+
	lda skel_nv,x
	sta mesh_nwork
	rts

; Rise/sink depth in world units (8.8 high byte). Alert rises from this far
; below the placed Y, dying sinks back, the dead hold stays at the bottom.
SKEL_RISE = 16
!if SKEL_RISE != 16 {
	!error "skel_sink_calc builds n * SKEL_RISE * 256 with a fixed <<4"
}

; X = obj_i. skel_sink:skel_sinkh = n/(len−1) * SKEL_RISE, 8.8.
; Clobbers rot0..rot2, dlo, nlo, Y.
skel_sink_calc
	lda #0
	sta skel_sink
	sta skel_sinkh
	lda en_state,x
	cmp #EN_ALERT
	beq .ss_alert
	cmp #EN_DYING
	beq .ss_dying
	cmp #EN_DEAD
	bne .ss_rts
	lda #SKEL_RISE
	sta skel_sinkh
.ss_rts
	rts
.ss_alert
	ldy ent_type
	lda enemy_alert_len,y
	sec
	sbc #1
	beq .ss_rts
	sta dlo
	sec
	sbc en_frame,x
	bcs .ss_div
	lda #0
	beq .ss_div
.ss_dying
	lda en_frame,x
	jsr pain_var_off
	sta rot0
	lda enemy_death_len,y
	sec
	sbc #1
	beq .ss_rts
	sta dlo
	lda rot0
	cmp dlo
	bcc .ss_div
	lda dlo
.ss_div
	sta rot2
	asl
	asl
	asl
	asl
	sta rot1
	lsr rot2
	lsr rot2
	lsr rot2
	lsr rot2
	lda #0
	sta rot0
	jsr div24u8
	lda rot0
	sta skel_sink
	lda rot1
	sta skel_sinkh
	rts

; Full project of this type. Baked batches in the prefix drive the resident
; mesh passes directly. No floor clip. Idle stays undrawn.
draw_custom_enemy
	ldx obj_i
	lda en_state,x
	bne +
	rts
+
	jsr skel_sink_calc
	jsr skel_rotate
!if PROFILE = 1 {
	ldy #PROF_ROT
	jsr prof_add_bucket
}
	lda .dce_zv+1
	sta edge_vert_ptr
	lda .dce_zv+2
	sta edge_vert_ptr+1
	lda #<ident_col
	sta col_ptr
	lda #>ident_col
	sta col_ptr+1
	ldx ent_type
	clc
	lda skel_base_lo,x
	adc #SKEL_PFX
	sta skel_bp
	lda skel_base_hi,x
	adc #0
	sta skel_bp+1
	jmp .db_batch
.dce_zv	bit skel_ezrun

; Baked batch: nslot, nedge, slot→vert[nslot], slot pairs[nedge*2].
; Terminated by nslot = 0.
.db_batch
	lda skel_bp
	sta src_ptr
	lda skel_bp+1
	sta src_ptr+1
	ldy #0
	lda (src_ptr),y
	bne +
	jmp .dce_done
+
	sta mesh_nv
	iny
	lda (src_ptr),y
	sta mesh_ne
	ldx #0
.db_slot
	iny
	sty skel_bi
	lda (src_ptr),y
	tay
	lda skel_cx,y
	sta CAM_X,x
	lda skel_cxh,y
	sta CAM_XH,x
	lda skel_cy,y
	sta CAM_Y,x
	lda skel_cyh,y
	sta CAM_YH,x
	lda skel_cz,y
	sta CAM_Z,x
	lda skel_czh,y
	sta CAM_ZH,x
	ldy skel_bi
	inx
	cpx mesh_nv
	bne .db_slot
	iny
	tya
	clc
	adc src_ptr
	sta edge_ptr
	lda src_ptr+1
	adc #0
	sta edge_ptr+1
	lda mesh_ne
	asl
	adc edge_ptr
	sta skel_bp
	lda edge_ptr+1
	adc #0
	sta skel_bp+1
	lda #$ff
	sta mesh_vmask
	jsr mesh_project
!if PROFILE = 1 {
	ldy #PROF_PROJ
	jsr prof_add_bucket
}
	jsr mesh_clip
!if PROFILE = 1 {
	ldy #PROF_CLIP
	jsr prof_add_bucket
}
	jsr mesh_draw
!if PROFILE = 1 {
	ldy #PROF_DRAW
	jsr prof_add_bucket
}
	jmp .db_batch
.dce_done
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


