; Axis-aligned box wireframe with Elite face cull
!zone box

; Edge list: pairs of corner indices 0..7
box_edges
	!byte 0,1, 1,2, 2,3, 3,0
	!byte 4,5, 5,6, 6,7, 7,4
	!byte 0,4, 1,5, 2,6, 3,7

; Ramp quad, switch triangle, two door leaves
quad_edges
	!byte 0,1, 1,2, 2,3, 3,0
tri_edges
	!byte 0,1, 1,2, 2,0
door_edges
	!byte 0,1, 1,2, 2,0,  3,4, 4,5, 5,3

; Which faces each edge belongs to (bit0=-X bit1=+X bit2=-Y bit3=+Y bit4=-Z bit5=+Z)
; Edge kept if either face visible. Matches box_fill_verts corners.
box_edge_faces
	!byte $14,$06,$24,$05		; bottom 0-1,1-2,2-3,3-0
	!byte $18,$0a,$28,$09		; top 4-5,5-6,6-7,7-4
	!byte $11,$12,$22,$21		; verts 0-4,1-5,2-6,3-7

box_vis_edges
	!fill 24, 0

; ------------------------------------------------------------------
; draw_box — box_* set, box_inside=0/1 (Elite face cull)
; ------------------------------------------------------------------
draw_box
	jsr load_view_trig
	jsr box_fill_verts
	jsr cull_box_faces
	jsr box_pack_edges
	lda mesh_ne
	bne .db_go
	rts
.db_go
	lda #BOX_NVERTS
	sta mesh_nv
	lda #<box_vis_edges
	sta edge_ptr
	lda #>box_vis_edges
	sta edge_ptr+1
	jmp stroke_mesh

stroke_mesh
	ldy #PROF_ROT
	jsr prof_add_bucket
	jsr mesh_project
	ldy #PROF_PROJ
	jsr prof_add_bucket
	jsr mesh_clip
	ldy #PROF_CLIP
	jsr prof_add_bucket
	jsr mesh_draw
	ldy #PROF_DRAW
	jsr prof_add_bucket
	rts

; Fill CAM[0..7] from box corners (world → view via xform_world_vert)
box_fill_verts
	; 0: x,y,z
	lda box_x
	sta ent_wx
	lda box_y
	sta ent_wy
	lda box_z
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; 1: x+sx,y,z
	clc
	lda box_x
	adc box_sx
	sta ent_wx
	ldx #1
	jsr xform_world_vert
	; 2: x+sx,y,z+sz
	clc
	lda box_z
	adc box_sz
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	; 3: x,y,z+sz
	lda box_x
	sta ent_wx
	ldx #3
	jsr xform_world_vert
	; 4: x,y+sy,z
	lda box_x
	sta ent_wx
	clc
	lda box_y
	adc box_sy
	sta ent_wy
	lda box_z
	sta ent_wz
	ldx #4
	jsr xform_world_vert
	; 5: x+sx,y+sy,z
	clc
	lda box_x
	adc box_sx
	sta ent_wx
	ldx #5
	jsr xform_world_vert
	; 6: x+sx,y+sy,z+sz
	clc
	lda box_z
	adc box_sz
	sta ent_wz
	ldx #6
	jsr xform_world_vert
	; 7: x,y+sy,z+sz
	lda box_x
	sta ent_wx
	ldx #7
	jsr xform_world_vert
	rts

; A = exterior keep 0/1, Y = face bit. XOR box_inside into face_bits.
box_apply_face
	eor box_inside
	beq .baf_rts
	tya
	ora face_bits
	sta face_bits
.baf_rts
	rts

; 8-bit Elite planes → face_bits (interior inverts via XOR)
cull_box_faces
	lda #0
	sta face_bits
	; -X: cam < box_x
	lda #0
	sta rot0
	lda cam_xh
	cmp box_x
	bcs .cf_px
	inc rot0
.cf_px
	lda rot0
	ldy #$01
	jsr box_apply_face
	; +X: cam >= x1 (wrap → exterior never)
	clc
	lda box_x
	adc box_sx
	bcc .cf_x1
	lda #0
	ldy #$02
	jsr box_apply_face
	jmp .cf_y
.cf_x1
	sta rot1
	lda #0
	sta rot0
	lda cam_xh
	cmp rot1
	bcc .cf_pxk
	inc rot0
.cf_pxk
	lda rot0
	ldy #$02
	jsr box_apply_face
.cf_y
	; -Y
	lda #0
	sta rot0
	lda cam_yh
	cmp box_y
	bcs .cf_py
	inc rot0
.cf_py
	lda rot0
	ldy #$04
	jsr box_apply_face
	; +Y
	clc
	lda box_y
	adc box_sy
	bcc .cf_y1
	lda #0
	ldy #$08
	jsr box_apply_face
	jmp .cf_z
.cf_y1
	sta rot1
	lda #0
	sta rot0
	lda cam_yh
	cmp rot1
	bcc .cf_pyk
	inc rot0
.cf_pyk
	lda rot0
	ldy #$08
	jsr box_apply_face
.cf_z
	; -Z
	lda #0
	sta rot0
	lda cam_zh
	cmp box_z
	bcs .cf_pz
	inc rot0
.cf_pz
	lda rot0
	ldy #$10
	jsr box_apply_face
	; +Z
	clc
	lda box_z
	adc box_sz
	bcc .cf_z1
	lda #0
	ldy #$20
	jsr box_apply_face
	rts
.cf_z1
	sta rot1
	lda #0
	sta rot0
	lda cam_zh
	cmp rot1
	bcc .cf_pzk
	inc rot0
.cf_pzk
	lda rot0
	ldy #$20
	jsr box_apply_face
	rts

; Pack edges with a visible face into box_vis_edges; mesh_ne = count
box_pack_edges
	ldx #0
	ldy #0
.pe
	lda box_edge_faces,x
	and face_bits
	beq .pe_n
	txa
	sta rot0
	asl
	tax
	lda box_edges,x
	sta box_vis_edges,y
	iny
	lda box_edges+1,x
	sta box_vis_edges,y
	iny
	ldx rot0
.pe_n
	inx
	cpx #BOX_NEDGES
	bne .pe
	tya
	lsr
	sta mesh_ne
	rts

; Lookahead square in XZ: origin fr_x,fr_z, side MAP_FRUSTUM
update_frustum
	ldy yaw
	lda SINTAB,y
	ldy #MAP_FRUSTUM_HALF
	jsr smul7
	ldx cam_xh
	jsr .look_axis
	sta fr_x
	ldy yaw
	lda COSTAB,y
	ldy #MAP_FRUSTUM_HALF
	jsr smul7
	ldx cam_zh
	jsr .look_axis
	sta fr_z
	rts

; A = signed lookahead offset, X = cam integer → A = square origin
.look_axis
	sta rot2
	stx rot0
	lda rot2
	bpl .fwd
	eor #$ff
	clc
	adc #1
	sta rot2
	lda rot0
	sec
	sbc rot2
	bcs .have
	lda #0
	jmp .have
.fwd
	clc
	adc rot0
	bcc .have
	lda #255
.have
	sec
	sbc #MAP_FRUSTUM_HALF
	bcs .orig
	lda #0
.orig
	cmp #(256-MAP_FRUSTUM)
	bcc .ok
	lda #(256-MAP_FRUSTUM)
.ok
	rts

; C=1 if box_x/z/sx/sz overlaps frustum square (exclusive max)
frustum_hits
	clc
	lda fr_x
	adc #MAP_FRUSTUM
	bcc .fh_xmax
	jmp .fh_x2			; exclusive max 256
.fh_xmax
	sta rot0
	lda box_x
	cmp rot0
	bcs .fh_no
.fh_x2
	clc
	lda box_x
	adc box_sx
	bcc .fh_x1
	jmp .fh_z			; box extends to 256
.fh_x1
	sta rot1
	lda fr_x
	cmp rot1
	bcs .fh_no
.fh_z
	clc
	lda fr_z
	adc #MAP_FRUSTUM
	bcc .fh_zmax
	jmp .fh_z2
.fh_zmax
	sta rot0
	lda box_z
	cmp rot0
	bcs .fh_no
.fh_z2
	clc
	lda box_z
	adc box_sz
	bcc .fh_z1
	sec
	rts
.fh_z1
	sta rot1
	lda fr_z
	cmp rot1
	bcs .fh_no
	sec
	rts
.fh_no
	clc
	rts

; A = base, pv3 = amount → A = base-pv3 clamped 0
coord_sub
	sec
	sbc pv3
	bcs .csok
	lda #0
.csok
	rts

; A = base, pv3 = amount → A = base+pv3 clamped 255
coord_add
	clc
	adc pv3
	bcc .caok
	lda #255
.caok
	rts

; ------------------------------------------------------------------
draw_door_mesh
	jsr load_view_trig
	jsr fill_door_verts
	lda #6
	sta mesh_nv
	lda #6
	sta mesh_ne
	lda #<door_edges
	sta edge_ptr
	lda #>door_edges
	sta edge_ptr+1
	jmp stroke_mesh

draw_switch_mesh
	jsr load_view_trig
	jsr fill_switch_verts
	lda #3
	sta mesh_nv
	lda #3
	sta mesh_ne
	lda #<tri_edges
	sta edge_ptr
	lda #>tri_edges
	sta edge_ptr+1
	jmp stroke_mesh

draw_slope_mesh
	jsr load_view_trig
	jsr fill_slope_verts
	lda #4
	sta mesh_nv
	lda #4
	sta mesh_ne
	lda #<quad_edges
	sta edge_ptr
	lda #>quad_edges
	sta edge_ptr+1
	jmp stroke_mesh

; Two face triangles; open slides them apart on the face width axis
fill_door_verts
	ldx obj_i
	lda door_open,x
	sta pv3
	lda box_y
	sta pv1				; y0
	clc
	adc box_sy
	sta pv2				; y1
	lda door_face,x
	cmp #FACE_PX
	bcc .fdz
	jmp .fdx
.fdz
	cmp #FACE_MZ
	beq .fdmz
	clc
	lda box_z
	adc box_sz
	jmp .fdzp
.fdmz
	lda box_z
.fdzp
	sta pv4				; plane z
	lda box_x
	jsr coord_sub
	sta pv0				; xL
	; v0 BL left
	sta ent_wx
	lda pv1
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; v1 TR left
	clc
	lda pv0
	adc box_sx
	bcc .fdl1
	lda #255
.fdl1
	sta ent_wx
	lda pv2
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #1
	jsr xform_world_vert
	; v2 TL left
	lda pv0
	sta ent_wx
	lda pv2
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	; right leaf
	lda box_x
	jsr coord_add
	sta pv0				; xR
	; v3 BL right
	sta ent_wx
	lda pv1
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #3
	jsr xform_world_vert
	; v4 BR right
	clc
	lda pv0
	adc box_sx
	bcc .fdr1
	lda #255
.fdr1
	sta ent_wx
	lda pv1
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #4
	jsr xform_world_vert
	; v5 TR right
	clc
	lda pv0
	adc box_sx
	bcc .fdr2
	lda #255
.fdr2
	sta ent_wx
	lda pv2
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #5
	jsr xform_world_vert
	rts
.fdx
	ldx obj_i
	cmp #FACE_MX
	beq .fdmx
	clc
	lda box_x
	adc box_sx
	jmp .fdxp
.fdmx
	lda box_x
.fdxp
	sta pv4				; plane x
	lda box_z
	jsr coord_sub
	sta pv0				; zL
	; v0 BL left
	lda pv4
	sta ent_wx
	lda pv1
	sta ent_wy
	lda pv0
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; v1 TR left
	lda pv4
	sta ent_wx
	lda pv2
	sta ent_wy
	clc
	lda pv0
	adc box_sz
	bcc .fdzl1
	lda #255
.fdzl1
	sta ent_wz
	ldx #1
	jsr xform_world_vert
	; v2 TL left
	lda pv4
	sta ent_wx
	lda pv2
	sta ent_wy
	lda pv0
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	lda box_z
	jsr coord_add
	sta pv0				; zR
	; v3 BL right
	lda pv4
	sta ent_wx
	lda pv1
	sta ent_wy
	lda pv0
	sta ent_wz
	ldx #3
	jsr xform_world_vert
	; v4 BR right
	lda pv4
	sta ent_wx
	lda pv1
	sta ent_wy
	clc
	lda pv0
	adc box_sz
	bcc .fdzr1
	lda #255
.fdzr1
	sta ent_wz
	ldx #4
	jsr xform_world_vert
	; v5 TR right
	lda pv4
	sta ent_wx
	lda pv2
	sta ent_wy
	clc
	lda pv0
	adc box_sz
	bcc .fdzr2
	lda #255
.fdzr2
	sta ent_wz
	ldx #5
	jsr xform_world_vert
	rts

; Up-pointing triangle on the switch face
fill_switch_verts
	ldx obj_i
	lda sw_face,x
	cmp #FACE_PX
	bcc .fsz
	jmp .fsx
.fsz
	cmp #FACE_MZ
	beq .fsmz
	clc
	lda box_z
	adc box_sz
	jmp .fszp
.fsmz
	lda box_z
.fszp
	sta pv4
	; apex: x+sx/2, y+sy, plane
	lda box_sx
	lsr
	clc
	adc box_x
	sta ent_wx
	clc
	lda box_y
	adc box_sy
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; left: x, y+sy/2, plane
	lda box_x
	sta ent_wx
	lda box_sy
	lsr
	clc
	adc box_y
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #1
	jsr xform_world_vert
	; right: x+sx, y+sy/2, plane
	clc
	lda box_x
	adc box_sx
	sta ent_wx
	lda box_sy
	lsr
	clc
	adc box_y
	sta ent_wy
	lda pv4
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	rts
.fsx
	cmp #FACE_MX
	beq .fsmx
	clc
	lda box_x
	adc box_sx
	jmp .fsxp
.fsmx
	lda box_x
.fsxp
	sta pv4
	; apex: plane, y+sy, z+sz/2
	lda pv4
	sta ent_wx
	clc
	lda box_y
	adc box_sy
	sta ent_wy
	lda box_sz
	lsr
	clc
	adc box_z
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; left: plane, y+sy/2, z
	lda pv4
	sta ent_wx
	lda box_sy
	lsr
	clc
	adc box_y
	sta ent_wy
	lda box_z
	sta ent_wz
	ldx #1
	jsr xform_world_vert
	; right: plane, y+sy/2, z+sz
	lda pv4
	sta ent_wx
	lda box_sy
	lsr
	clc
	adc box_y
	sta ent_wy
	clc
	lda box_z
	adc box_sz
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	rts

; Four sloped ramp edges (no AABB)
fill_slope_verts
	ldx obj_i
	lda slope_axis,x
	bne .slz
	lda slope_dir,x
	beq .slxn
	lda box_x
	sta pv0
	clc
	adc box_sx
	sta pv1
	jmp .slxgo
.slxn
	clc
	lda box_x
	adc box_sx
	sta pv0
	lda box_x
	sta pv1
.slxgo
	lda box_y
	sta pv2
	clc
	adc box_sy
	sta pv3
	; p0 xlow,ylow,z
	lda pv0
	sta ent_wx
	lda pv2
	sta ent_wy
	lda box_z
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; p1 xlow,ylow,z+sz
	lda pv0
	sta ent_wx
	lda pv2
	sta ent_wy
	clc
	lda box_z
	adc box_sz
	sta ent_wz
	ldx #1
	jsr xform_world_vert
	; p2 xhigh,yhigh,z+sz
	lda pv1
	sta ent_wx
	lda pv3
	sta ent_wy
	clc
	lda box_z
	adc box_sz
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	; p3 xhigh,yhigh,z
	lda pv1
	sta ent_wx
	lda pv3
	sta ent_wy
	lda box_z
	sta ent_wz
	ldx #3
	jsr xform_world_vert
	rts
.slz
	ldx obj_i
	lda slope_dir,x
	beq .slzn
	lda box_z
	sta pv0
	clc
	adc box_sz
	sta pv1
	jmp .slzgo
.slzn
	clc
	lda box_z
	adc box_sz
	sta pv0
	lda box_z
	sta pv1
.slzgo
	lda box_y
	sta pv2
	clc
	adc box_sy
	sta pv3
	; p0 x,ylow,zlow
	lda box_x
	sta ent_wx
	lda pv2
	sta ent_wy
	lda pv0
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	; p1 x+sx,ylow,zlow
	clc
	lda box_x
	adc box_sx
	sta ent_wx
	lda pv2
	sta ent_wy
	lda pv0
	sta ent_wz
	ldx #1
	jsr xform_world_vert
	; p2 x+sx,yhigh,zhigh
	clc
	lda box_x
	adc box_sx
	sta ent_wx
	lda pv3
	sta ent_wy
	lda pv1
	sta ent_wz
	ldx #2
	jsr xform_world_vert
	; p3 x,yhigh,zhigh
	lda box_x
	sta ent_wx
	lda pv3
	sta ent_wy
	lda pv1
	sta ent_wz
	ldx #3
	jsr xform_world_vert
	rts

; ------------------------------------------------------------------
draw_world
	jsr update_frustum
	; active room (inside cull) — not frustum-culled
	ldx room_idx
	lda room_x,x
	sta box_x
	lda room_y,x
	sta box_y
	lda room_z,x
	sta box_z
	lda room_sx,x
	sta box_sx
	lda room_sy,x
	sta box_sy
	lda room_sz,x
	sta box_sz
	lda #1
	sta box_inside
	jsr draw_box
	; crates
	ldx #0
.dw_c
	cpx #MAP_NCRATES
	bcs .dw_d
	lda crate_room,x
	cmp room_idx
	bne .dw_cn
	stx obj_i
	lda crate_x,x
	sta box_x
	lda crate_y,x
	sta box_y
	lda crate_z,x
	sta box_z
	lda crate_sx,x
	sta box_sx
	lda crate_sy,x
	sta box_sy
	lda crate_sz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_cr
	lda #0
	sta box_inside
	jsr draw_box
.dw_cr
	ldx obj_i
.dw_cn
	inx
	bne .dw_c
.dw_d
	; doors: two face triangles, slide apart by door_open
	ldx #0
.dw_door
	cpx #MAP_NDOORS
	bcs .dw_sw
	lda door_ra,x
	cmp room_idx
	beq .dw_doku
	lda door_rb,x
	cmp room_idx
	bne .dw_dn
.dw_doku
	stx obj_i
	lda door_x,x
	sta box_x
	lda door_y,x
	sta box_y
	lda door_z,x
	sta box_z
	lda door_sx,x
	sta box_sx
	lda door_sy,x
	sta box_sy
	lda door_sz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_dn0
	jsr draw_door_mesh
.dw_dn0
	ldx obj_i
.dw_dn
	inx
	bne .dw_door
.dw_sw
	ldx #0
.dw_s
	cpx #MAP_NSWITCHES
	bcs .dw_e
	lda sw_room,x
	cmp room_idx
	bne .dw_sn
	stx obj_i
	lda sw_x,x
	sta box_x
	lda sw_y,x
	sta box_y
	lda sw_z,x
	sta box_z
	lda sw_sx,x
	sta box_sx
	lda sw_sy,x
	sta box_sy
	lda sw_sz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_sr
	jsr draw_switch_mesh
.dw_sr
	ldx obj_i
.dw_sn
	inx
	bne .dw_s
.dw_e
	ldx #0
.dw_el
	cpx #MAP_NELEVS
	bcs .dw_sl
	lda elev_room,x
	cmp room_idx
	bne .dw_eln
	stx obj_i
	lda elev_x,x
	sta box_x
	lda elev_y,x
	sta box_y
	lda elev_z,x
	sta box_z
	lda elev_sx,x
	sta box_sx
	lda elev_sy,x
	sta box_sy
	lda elev_sz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_er
	lda #0
	sta box_inside
	jsr draw_box
.dw_er
	ldx obj_i
.dw_eln
	inx
	bne .dw_el
.dw_sl
	ldx #0
.dw_slope
	cpx #MAP_NSLOPES
	bcs .dw_rts
	lda slope_room,x
	cmp room_idx
	bne .dw_sln
	stx obj_i
	lda slope_x,x
	sta box_x
	lda slope_y,x
	sta box_y
	lda slope_z,x
	sta box_z
	lda slope_sx,x
	sta box_sx
	lda slope_sy,x
	sta box_sy
	lda slope_sz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_slr
	jsr draw_slope_mesh
.dw_slr
	ldx obj_i
.dw_sln
	inx
	bne .dw_slope
.dw_rts
	rts
