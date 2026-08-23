; World object meshes — AABB / door / switch / slope / plat wireframes
!zone mesh

; Edge list: pairs of corner indices 0..7
box_edges
	!byte 0,1, 1,2, 2,3, 3,0
	!byte 4,5, 5,6, 6,7, 7,4
	!byte 0,4, 1,5, 2,6, 3,7

; Ramp hypotenuses (no top/bottom — room/platform already draw those)
ramp_side_edges
	!byte 1,2, 3,0
; Platform quad, switch triangle, door closed/open (no floor edge)
quad_edges
	!byte 0,1, 1,2, 2,3, 3,0
tri_edges
	!byte 0,1, 1,2, 2,0
; Closed: BL-TL, TL-TR, TR-BL, TR-BR. Open: left 0-1-4, right 2-5 + 2-3.
door_closed_edges
	!byte 0,1, 1,2, 2,0,  2,3
door_open_edges
	!byte 0,1, 1,4, 4,0,  2,5, 2,3

; World-vertical edges (same xid/zid, different Y) — 1 = Y-only clip
box_edge_vert
	!byte 0,0,0,0, 0,0,0,0, 1,1,1,1
door_closed_vert
	!byte 1,0,0,1
door_open_vert
	!byte 1,0,0,0,1
ramp_side_vert
	!byte 0,0
quad_vert
	!byte 0,0,0,0
tri_vert
	!byte 0,0,0

; Per-vert XZ column ids for mesh_project (verts sharing x,z share a column).
; box_col doubles as identity for ≤4-vert meshes with distinct columns.
box_col
	!byte 0,1,2,3, 0,1,2,3
door_closed_col
	!byte 0,0,1,1
door_open_col
	!byte 0,0,1,1, 2,3
ident_col
	!byte 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15

; Per-vert slots into UX[] / UZ[] (sharing across the mesh)
box_xid
	!byte 0,1,1,0, 0,1,1,0
box_zid
	!byte 0,0,1,1, 0,0,1,1
door_closed_z_xid
	!byte 0,0,1,1
door_closed_z_zid
	!byte 0,0,0,0
door_closed_x_xid
	!byte 0,0,0,0
door_closed_x_zid
	!byte 0,0,1,1
door_open_z_xid
	!byte 0,0,3,3,1,2
door_open_z_zid
	!byte 0,0,0,0,0,0
door_open_x_xid
	!byte 0,0,0,0,0,0
door_open_x_zid
	!byte 0,0,3,3,1,2
sw_z_xid
	!byte 1,0,2
sw_z_zid
	!byte 0,0,0
sw_x_xid
	!byte 0,0,0
sw_x_zid
	!byte 1,0,2
slope_x_xid
	!byte 0,0,1,1
slope_x_zid
	!byte 0,1,1,0

; Which faces each edge belongs to (bit0=-X bit1=+X bit2=-Y bit3=+Y bit4=-Z bit5=+Z)
; Edge kept if either face visible. Matches box_fill_verts corners.
box_edge_faces
	!byte $14,$06,$24,$05		; bottom 0-1,1-2,2-3,3-0
	!byte $18,$0a,$28,$09		; top 4-5,5-6,6-7,7-4
	!byte $11,$12,$22,$21		; verts 0-4,1-5,2-6,3-7

box_vis_edges
	!fill 24, 0
box_vis_vert
	!fill 12, 0
room_pack_edges
	!fill 64, 0
room_pack_vert
	!fill 32, 0
box_vbit
	!byte $01,$02,$04,$08,$10,$20,$40,$80

; ------------------------------------------------------------------
; draw_box — box_* set, box_inside=0/1 (back-face cull)
; ------------------------------------------------------------------
draw_box
	jsr load_view_trig
	jsr cull_box_faces
	jsr box_pack_edges
	lda mesh_ne
	bne .db_go
	rts
.db_go
	jsr box_build_vert_mask
	jsr box_fill_verts
	lda #BOX_NVERTS
	sta mesh_nv
	lda #<box_vis_edges
	sta edge_ptr
	lda #>box_vis_edges
	sta edge_ptr+1
	lda #<box_vis_vert
	sta edge_vert_ptr
	lda #>box_vis_vert
	sta edge_vert_ptr+1
	jmp stroke_mesh

stroke_mesh
!if PROFILE = 1 {
	ldy #PROF_ROT
	jsr prof_add_bucket
}
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
	lda #$ff
	sta mesh_vmask
	rts

; Fill CAM[0..7] from box corners via unique X/Z products
box_fill_verts
	jsr aabb_uxuz
	lda box_y
	sta VY
	sta VY+1
	sta VY+2
	sta VY+3
	clc
	adc box_sy
	sta VY+4
	sta VY+5
	sta VY+6
	sta VY+7
	lda #BOX_NVERTS
	sta mesh_nv
	jsr set_box_xzid
	jmp xform_mesh_xz

aabb_uxuz
	lda box_x
	sta UX
	clc
	adc box_sx
	sta UX+1
	lda box_z
	sta UZ
	clc
	adc box_sz
	sta UZ+1
	lda #2
	sta mesh_nx
	sta mesh_nz
	rts

set_box_xzid
	lda #<box_xid
	sta xid_ptr
	lda #>box_xid
	sta xid_ptr+1
	lda #<box_zid
	sta zid_ptr
	lda #>box_zid
	sta zid_ptr+1
	lda #<box_col
	sta col_ptr
	lda #>box_col
	sta col_ptr+1
	rts

set_door_closed_col
	lda #<door_closed_col
	sta col_ptr
	lda #>door_closed_col
	sta col_ptr+1
	rts

set_door_open_col
	lda #<door_open_col
	sta col_ptr
	lda #>door_open_col
	sta col_ptr+1
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

; 8-bit back-face planes → face_bits (interior inverts via XOR)
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
	lda #0
	sta rot1
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
	lda box_edge_vert,x
	ldx rot1
	sta box_vis_vert,x
	inc rot1
	ldx rot0
.pe_n
	inx
	cpx #BOX_NEDGES
	bne .pe
	tya
	lsr
	sta mesh_ne
	rts

; Visible edge list → corner mask + mesh_nwork (1–8 for crates)
box_build_vert_mask
	lda #0
	sta mesh_vmask
	ldx #0
.bvm
	cpx mesh_ne
	beq .bvm_pop
	txa
	asl
	tay
	lda box_vis_edges,y
	tay
	lda mesh_vmask
	ora box_vbit,y
	sta mesh_vmask
	txa
	asl
	tay
	iny
	lda box_vis_edges,y
	tay
	lda mesh_vmask
	ora box_vbit,y
	sta mesh_vmask
	inx
	jmp .bvm
.bvm_pop
	lda #0
	sta mesh_nwork
	ldx #8
	lda mesh_vmask
.bvm_cnt
	asl
	bcc .bvm_c0
	inc mesh_nwork
.bvm_c0
	dex
	bne .bvm_cnt
	rts

; Inward XZ frustum normals: left/right edges at yaw±FOV_HALF, 90° swap-flip
update_frustum
	ldy yaw
	lda SINTAB,y
	sta fn_fx
	lda COSTAB,y
	sta fn_fz
	clc
	lda yaw
	adc #FOV_HALF
	tay
	lda COSTAB,y
	eor #$ff
	clc
	adc #1
	sta fn_lx			; left N = (-Ez, Ex)
	lda SINTAB,y
	sta fn_lz
	sec
	lda yaw
	sbc #FOV_HALF
	tay
	lda COSTAB,y
	sta fn_rx			; right N = (Ez, -Ex)
	lda SINTAB,y
	eor #$ff
	clc
	adc #1
	sta fn_rz
	rts

; C=1 if box is not fully outside the view (Y Chebyshev, then XZ planes)
frustum_hits
	jsr frustum_y
	bcc .fh_no
	lda fn_lx
	sta rot0
	lda fn_lz
	sta rot1
	jsr plane_pvert
	bcc .fh_no
	lda fn_rx
	sta rot0
	lda fn_rz
	sta rot1
	jsr plane_pvert
	bcc .fh_no
	lda fn_fx
	sta rot0
	lda fn_fz
	sta rot1
	jmp plane_pvert
.fh_no
	clc
	rts

; C=1 unless the whole box is above/below a 45° Y cone (Chebyshev XZ + pad)
frustum_y
	jsr box_xz_cheby
	clc
	adc #ITEM_CULL_Y
	bcs .fy_yes
	sta nhi
	sec
	lda box_y
	sbc cam_yh
	sta nlo
	clc
	adc box_sy
	sta rot0
	lda nlo
	bmi .fy_lo_neg
	cmp nhi
	beq .fy_yes
	bcc .fy_yes
	clc
	rts
.fy_lo_neg
	lda rot0
	bpl .fy_yes
	lda #0
	sec
	sbc rot0
	cmp nhi
	beq .fy_yes
	bcc .fy_yes
	clc
	rts
.fy_yes
	sec
	rts

; A = max |box XZ corner − cam| (Chebyshev of the four edges)
box_xz_cheby
	lda #0
	sta rot1
	lda cam_xh
	sta rot2
	lda box_x
	jsr .absmax
	clc
	lda box_x
	adc box_sx
	bcc +
	lda #255
+
	jsr .absmax
	lda cam_zh
	sta rot2
	lda box_z
	jsr .absmax
	clc
	lda box_z
	adc box_sz
	bcc +
	lda #255
+
	jsr .absmax
	lda rot1
	rts
.absmax
	sec
	sbc rot2
	bcs .pos
	eor #$ff
	clc
	adc #1
.pos
	cmp rot1
	bcc .ret
	sta rot1
.ret
	rts

; rot0=Nx rot1=Nz. C=1 if N·(p-vertex − cam) >= 0
plane_pvert
	lda rot0
	bmi .pp_minx
	clc
	lda box_x
	adc box_sx
	bcc .pp_x
	lda #255
	jmp .pp_x
.pp_minx
	lda box_x
.pp_x
	sec
	sbc cam_xh
	sta nlo
	lda #0
	sbc #0
	sta nhi
	ldy rot0
	jsr smul16_7
	lda nlo
	sta pv0
	lda nhi
	sta pv1
	lda rot1
	bmi .pp_minz
	clc
	lda box_z
	adc box_sz
	bcc .pp_z
	lda #255
	jmp .pp_z
.pp_minz
	lda box_z
.pp_z
	sec
	sbc cam_zh
	sta nlo
	lda #0
	sbc #0
	sta nhi
	ldy rot1
	jsr smul16_7
	clc
	lda nlo
	adc pv0
	lda nhi
	adc pv1
	bmi .pp_out
	sec
	rts
.pp_out
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
	ldx obj_i
	lda door_open,x
	bne .dd_open
	lda #4
	sta mesh_nv
	sta mesh_ne
	lda #<door_closed_edges
	sta edge_ptr
	lda #>door_closed_edges
	sta edge_ptr+1
	lda #<door_closed_vert
	sta edge_vert_ptr
	lda #>door_closed_vert
	sta edge_vert_ptr+1
	jmp stroke_mesh
.dd_open
	lda #6
	sta mesh_nv
	lda #5
	sta mesh_ne
	lda #<door_open_edges
	sta edge_ptr
	lda #>door_open_edges
	sta edge_ptr+1
	lda #<door_open_vert
	sta edge_vert_ptr
	lda #>door_open_vert
	sta edge_vert_ptr+1
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
	lda #<tri_vert
	sta edge_vert_ptr
	lda #>tri_vert
	sta edge_vert_ptr+1
	jmp stroke_mesh

draw_slope_mesh
	jsr load_view_trig
	jsr fill_slope_verts
	lda #4
	sta mesh_nv
	lda #2
	sta mesh_ne
	lda #<ramp_side_edges
	sta edge_ptr
	lda #>ramp_side_edges
	sta edge_ptr+1
	lda #<ramp_side_vert
	sta edge_vert_ptr
	lda #>ramp_side_vert
	sta edge_vert_ptr+1
	jmp stroke_mesh

draw_plat_mesh
	jsr load_view_trig
	jsr fill_plat_verts
	lda #4
	sta mesh_nv
	lda #4
	sta mesh_ne
	lda #<quad_edges
	sta edge_ptr
	lda #>quad_edges
	sta edge_ptr+1
	lda #<quad_vert
	sta edge_vert_ptr
	lda #>quad_vert
	sta edge_vert_ptr+1
	jmp stroke_mesh

; Pickup mesh: type in A (BP_*). nv=0 → backpack fallback slot BP_NTYPES.
draw_backpack_mesh
	ldx obj_i
	+lda_mx bp_type
draw_pickup_mesh
	pha
	jsr load_view_trig
	pla
	jsr fill_item_verts
	jmp stroke_mesh

fill_item_verts
	cmp #BP_NTYPES
	bcc +
	lda #0
+
	tay
	lda item_nv,y
	bne +
	ldy #BP_NTYPES
+
	lda item_nv,y
	sta mesh_nv
	lda item_ne,y
	sta mesh_ne
	lda item_nx,y
	sta mesh_nx
	lda item_nz,y
	sta mesh_nz
	sty rot0				; slot
	; UX/UZ stay local (editor 0 = spin centre). World centre is box+ITEM_BIAS.
	clc
	lda #<item_ux
	adc item_uo,y
	sta src_ptr
	lda #>item_ux
	adc #0
	sta src_ptr+1
	ldy #0
.fi_ux
	cpy mesh_nx
	bcs .fi_uz
	lda (src_ptr),y
	sta UX,y
	iny
	bne .fi_ux
.fi_uz
	ldy rot0
	clc
	lda #<item_uz
	adc item_zo,y
	sta src_ptr
	lda #>item_uz
	adc #0
	sta src_ptr+1
	ldy #0
.fi_uzl
	cpy mesh_nz
	bcs .fi_vy
	lda (src_ptr),y
	sta UZ,y
	iny
	bne .fi_uzl
.fi_vy
	ldy rot0
	clc
	lda #<item_vy
	adc item_vo,y
	sta src_ptr
	lda #>item_vy
	adc #0
	sta src_ptr+1
	ldy #0
.fi_vyl
	cpy mesh_nv
	bcs .fi_ptr
	clc
	lda (src_ptr),y
	adc box_y
	sta VY,y
	iny
	bne .fi_vyl
.fi_ptr
	ldy rot0
	clc
	lda #<item_xid
	adc item_vo,y
	sta xid_ptr
	lda #>item_xid
	adc #0
	sta xid_ptr+1
	clc
	lda #<item_zid
	adc item_vo,y
	sta zid_ptr
	lda #>item_zid
	adc #0
	sta zid_ptr+1
	clc
	lda #<item_col
	adc item_vo,y
	sta col_ptr
	lda #>item_col
	adc #0
	sta col_ptr+1
	clc
	lda #<item_edges
	adc item_eo,y
	sta edge_ptr
	lda #>item_edges
	adc #0
	sta edge_ptr+1
	lda item_eo,y
	lsr
	clc
	adc #<item_evert
	sta edge_vert_ptr
	lda #>item_evert
	adc #0
	sta edge_vert_ptr+1
	; Quad / pent / ring yaw-spin; other pickups use angle 0 (still origin-centred).
	lda #0
	cpy #BP_QUAD
	bcc +
	cpy #BP_SILVER
	bcs +
	lda item_spin
+
	sta ent_rot
	jmp xform_item_spin

; dt<<4 as 8.8 → ~1 rev / 4s
update_item_spin
	lda dt_ms
	sta nlo
	lda dt_msh
	sta nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
	clc
	lda item_spin_l
	adc nlo
	sta item_spin_l
	lda item_spin
	adc nhi
	sta item_spin
	rts

fill_plat_verts
	jsr aabb_uxuz
	lda box_y
	sta VY
	sta VY+1
	sta VY+2
	sta VY+3
	lda #4
	sta mesh_nv
	jsr set_box_xzid
	jmp xform_mesh_xz

; Closed: 4 corners of the face. Open: two full-width leaves, each slides open/2.
fill_door_verts
	ldx obj_i
	lda door_open,x
	lsr
	sta pv3				; slide
	lda box_y
	sta pv1				; y0
	clc
	adc box_sy
	sta pv2				; y1
	lda door_vface,x
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
	sta UZ
	lda #1
	sta mesh_nz
	ldx obj_i
	lda door_open,x
	bne .fdz_op
	lda box_x
	sta UX
	clc
	adc box_sx
	bcc .fdz_c2
	lda #255
.fdz_c2
	sta UX+1
	lda #2
	sta mesh_nx
	lda pv1
	sta VY
	lda pv2
	sta VY+1
	sta VY+2
	lda pv1
	sta VY+3
	lda #<door_closed_z_xid
	sta xid_ptr
	lda #>door_closed_z_xid
	sta xid_ptr+1
	lda #<door_closed_z_zid
	sta zid_ptr
	lda #>door_closed_z_zid
	sta zid_ptr+1
	jsr set_door_closed_col
	lda #4
	sta mesh_nv
	jmp xform_mesh_xz
.fdz_op
	lda box_x
	jsr coord_sub
	sta UX				; xL
	clc
	adc box_sx
	bcc .fdl1
	lda #255
.fdl1
	sta UX+1			; xL+sx
	lda box_x
	jsr coord_add
	sta UX+2			; xR
	clc
	adc box_sx
	bcc .fdr1
	lda #255
.fdr1
	sta UX+3			; xR+sx
	lda #4
	sta mesh_nx
	lda pv1
	sta VY
	lda pv2
	sta VY+1
	sta VY+2
	lda pv1
	sta VY+3
	lda pv2
	sta VY+4
	lda pv1
	sta VY+5
	lda #<door_open_z_xid
	sta xid_ptr
	lda #>door_open_z_xid
	sta xid_ptr+1
	lda #<door_open_z_zid
	sta zid_ptr
	lda #>door_open_z_zid
	sta zid_ptr+1
	jsr set_door_open_col
	lda #6
	sta mesh_nv
	jmp xform_mesh_xz
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
	sta UX
	lda #1
	sta mesh_nx
	ldx obj_i
	lda door_open,x
	bne .fdx_op
	lda box_z
	sta UZ
	clc
	adc box_sz
	bcc .fdx_c2
	lda #255
.fdx_c2
	sta UZ+1
	lda #2
	sta mesh_nz
	lda pv1
	sta VY
	lda pv2
	sta VY+1
	sta VY+2
	lda pv1
	sta VY+3
	lda #<door_closed_x_xid
	sta xid_ptr
	lda #>door_closed_x_xid
	sta xid_ptr+1
	lda #<door_closed_x_zid
	sta zid_ptr
	lda #>door_closed_x_zid
	sta zid_ptr+1
	jsr set_door_closed_col
	lda #4
	sta mesh_nv
	jmp xform_mesh_xz
.fdx_op
	lda box_z
	jsr coord_sub
	sta UZ				; zL
	clc
	adc box_sz
	bcc .fdzl1
	lda #255
.fdzl1
	sta UZ+1			; zL+sz
	lda box_z
	jsr coord_add
	sta UZ+2			; zR
	clc
	adc box_sz
	bcc .fdzr1
	lda #255
.fdzr1
	sta UZ+3			; zR+sz
	lda #4
	sta mesh_nz
	lda pv1
	sta VY
	lda pv2
	sta VY+1
	sta VY+2
	lda pv1
	sta VY+3
	lda pv2
	sta VY+4
	lda pv1
	sta VY+5
	lda #<door_open_x_xid
	sta xid_ptr
	lda #>door_open_x_xid
	sta xid_ptr+1
	lda #<door_open_x_zid
	sta zid_ptr
	lda #>door_open_x_zid
	sta zid_ptr+1
	jsr set_door_open_col
	lda #6
	sta mesh_nv
	jmp xform_mesh_xz

; Up-pointing triangle on the switch face
fill_switch_verts
	lda #<box_col			; 3 distinct columns → identity
	sta col_ptr
	lda #>box_col
	sta col_ptr+1
	ldx obj_i
	+lda_mx sw_face
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
	sta UZ
	lda #1
	sta mesh_nz
	lda box_x
	sta UX
	lda box_sx
	lsr
	clc
	adc box_x
	sta UX+1
	clc
	lda box_x
	adc box_sx
	sta UX+2
	lda #3
	sta mesh_nx
	clc
	lda box_y
	adc box_sy
	sta VY
	lda box_sy
	lsr
	clc
	adc box_y
	sta VY+1
	sta VY+2
	lda #<sw_z_xid
	sta xid_ptr
	lda #>sw_z_xid
	sta xid_ptr+1
	lda #<sw_z_zid
	sta zid_ptr
	lda #>sw_z_zid
	sta zid_ptr+1
	lda #3
	sta mesh_nv
	jmp xform_mesh_xz
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
	sta UX
	lda #1
	sta mesh_nx
	lda box_z
	sta UZ
	lda box_sz
	lsr
	clc
	adc box_z
	sta UZ+1
	clc
	lda box_z
	adc box_sz
	sta UZ+2
	lda #3
	sta mesh_nz
	clc
	lda box_y
	adc box_sy
	sta VY
	lda box_sy
	lsr
	clc
	adc box_y
	sta VY+1
	sta VY+2
	lda #<sw_x_xid
	sta xid_ptr
	lda #>sw_x_xid
	sta xid_ptr+1
	lda #<sw_x_zid
	sta zid_ptr
	lda #>sw_x_zid
	sta zid_ptr+1
	lda #3
	sta mesh_nv
	jmp xform_mesh_xz

; Four ramp corners; stroke uses the two hypotenuses only
fill_slope_verts
	ldx obj_i
	+lda_mx slope_axis
	bne .slz
	+lda_mx slope_dir
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
	lda pv0
	sta UX
	lda pv1
	sta UX+1
	lda box_z
	sta UZ
	clc
	adc box_sz
	sta UZ+1
	lda #<slope_x_xid
	sta xid_ptr
	lda #>slope_x_xid
	sta xid_ptr+1
	lda #<slope_x_zid
	sta zid_ptr
	lda #>slope_x_zid
	sta zid_ptr+1
	jmp .sl_emit
.slz
	ldx obj_i
	+lda_mx slope_dir
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
	lda box_x
	sta UX
	clc
	adc box_sx
	sta UX+1
	lda pv0
	sta UZ
	lda pv1
	sta UZ+1
	jsr set_box_xzid
.sl_emit
	lda #<box_col			; 4 distinct columns → identity
	sta col_ptr
	lda #>box_col
	sta col_ptr+1
	lda #2
	sta mesh_nx
	sta mesh_nz
	lda pv2
	sta VY
	sta VY+1
	lda pv3
	sta VY+2
	sta VY+3
	lda #4
	sta mesh_nv
	jmp xform_mesh_xz

; ------------------------------------------------------------------
; Tetromino hull: unique UX/UZ * sin/cos, then verts by xid/zid/VY.
; Packed vis edges stroke in one pass (EDGE_VIS/CLIP_* are 32-wide).
; ------------------------------------------------------------------
draw_room_mesh
	jsr load_view_trig
	lda #$ff
	sta mesh_vmask
	ldx room_idx
	+lda_mx room_x
	sta box_x
	+lda_mx room_y
	sta box_y
	+lda_mx room_z
	sta box_z
	+lda_mx room_sx
	sta box_sx
	+lda_mx room_sy
	sta box_sy
	+lda_mx room_sz
	sta box_sz
	lda #1
	sta box_inside
	jsr cull_box_faces
	ldx room_idx
	+lda_mx room_ne
	sta pv0
	+lda_mx room_eo
	sta pv1
	lda #0
	sta pv2
	sta pv3
.drm_pk
	lda pv0
	beq .drm_pkd
	ldx pv1
	+lda_mx room_efaces
	beq .drm_keep
	and face_bits
	beq .drm_pkn
.drm_keep
	ldy pv2
	+lda_mx room_e0
	sta room_pack_edges,y
	iny
	+lda_mx room_e1
	sta room_pack_edges,y
	iny
	sty pv2
	ldy pv3
	+lda_mx room_evert
	sta room_pack_vert,y
	inc pv3
.drm_pkn
	inc pv1
	dec pv0
	bne .drm_pk
.drm_pkd
	lda pv3
	bne .drm_xf
	rts
.drm_xf
	ldx room_idx
	+lda_mx room_nv
	sta mesh_nv
	+lda_mx room_nx
	sta mesh_nx
	+lda_mx room_nz
	sta mesh_nz
	+lda_mx room_uo
	sta pv0
	+lda_mx room_zo
	sta pv1
	+lda_mx room_vo
	sta pv2
	ldy #0
.drm_ux
	cpy mesh_nx
	beq .drm_uz
	tya
	clc
	adc pv0
	tax
	+lda_mx room_ux
	sta UX,y
	iny
	bne .drm_ux
.drm_uz
	ldy #0
.drm_uzl
	cpy mesh_nz
	beq .drm_vy
	tya
	clc
	adc pv1
	tax
	+lda_mx room_uz
	sta UZ,y
	iny
	bne .drm_uzl
.drm_vy
	ldy #0
.drm_vyl
	cpy mesh_nv
	beq .drm_ptr
	tya
	clc
	adc pv2
	tax
	+lda_mx room_vy
	sta VY,y
	iny
	bne .drm_vyl
.drm_ptr
	clc
	lda	room_xid
	adc pv2
	sta xid_ptr
	lda	room_xid+1
	adc #0
	sta xid_ptr+1
	clc
	lda	room_zid
	adc pv2
	sta zid_ptr
	lda	room_zid+1
	adc #0
	sta zid_ptr+1
	clc
	lda	room_col
	adc pv2
	sta col_ptr
	lda	room_col+1
	adc #0
	sta col_ptr+1
	jsr xform_mesh_xz
	lda #<room_pack_edges
	sta edge_ptr
	lda #>room_pack_edges
	sta edge_ptr+1
	lda #<room_pack_vert
	sta edge_vert_ptr
	lda #>room_pack_vert
	sta edge_vert_ptr+1
	lda pv3
	sta mesh_ne
	jmp stroke_mesh

; ------------------------------------------------------------------
draw_world
	jsr update_frustum
	ldx room_idx
	+lda_mx room_nv
	beq .dw_box
	jsr draw_room_mesh
	jmp .dw_items
.dw_box
	; active room (inside cull) — not frustum-culled
	ldx room_idx
	+lda_mx room_x
	sta box_x
	+lda_mx room_y
	sta box_y
	+lda_mx room_z
	sta box_z
	+lda_mx room_sx
	sta box_sx
	+lda_mx room_sy
	sta box_sy
	+lda_mx room_sz
	sta box_sz
	lda #1
	sta box_inside
	jsr draw_box
	; crates
.dw_items
	ldx #0
.dw_c
	cpx	map_ncrates
	+bcs_far .dw_d
	+lda_mx crate_room
	cmp room_idx
	bne .dw_cn
	stx obj_i
	+lda_mx crate_x
	sta box_x
	+lda_mx crate_y
	sta box_y
	+lda_mx crate_z
	sta box_z
	+lda_mx crate_sx
	sta box_sx
	+lda_mx crate_sy
	sta box_sy
	+lda_mx crate_sz
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
	beq .dw_d
	jmp .dw_c
.dw_d
	; doors: closed 4-vert face; open full-width leaves slide open/2
	ldx #0
.dw_door
	cpx	map_ndoors
	+bcs_far .dw_sw
	+lda_mx door_ra
	cmp room_idx
	beq .dw_doku
	+lda_mx door_rb
	cmp room_idx
	bne .dw_dn
.dw_doku
	stx obj_i
	jsr door_front
	bcc .dw_dn0
	lda door_vx,x
	sta box_x
	+lda_mx door_y
	sta box_y
	lda door_vz,x
	sta box_z
	lda door_vsx,x
	sta box_sx
	+lda_mx door_sy
	sta box_sy
	lda door_vsz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_dn0
	jsr draw_door_mesh
.dw_dn0
	ldx obj_i
.dw_dn
	inx
	beq .dw_sw
	jmp .dw_door
.dw_sw
	ldx #0
.dw_s
	cpx	map_nswitches
	+bcs_far .dw_e
	+lda_mx sw_room
	cmp room_idx
	bne .dw_sn
	stx obj_i
	+lda_mx sw_x
	sta box_x
	+lda_mx sw_y
	sta box_y
	+lda_mx sw_z
	sta box_z
	+lda_mx sw_sx
	sta box_sx
	+lda_mx sw_sy
	sta box_sy
	+lda_mx sw_sz
	sta box_sz
	jsr frustum_hits
	bcc .dw_sr
	jsr draw_switch_mesh
.dw_sr
	ldx obj_i
.dw_sn
	inx
	beq .dw_e
	jmp .dw_s
.dw_e
	ldx #0
.dw_el
	cpx	map_nelevs
	+bcs_far .dw_sl
	+lda_mx elev_room
	cmp room_idx
	bne .dw_eln
	stx obj_i
	+lda_mx elev_x
	sta box_x
	lda elev_y,x
	sta box_y
	+lda_mx elev_z
	sta box_z
	+lda_mx elev_sx
	sta box_sx
	+lda_mx elev_sy
	sta box_sy
	+lda_mx elev_sz
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
	beq .dw_sl
	jmp .dw_el
.dw_sl
	ldx #0
.dw_slope
	cpx	map_nslopes
	+bcs_far .dw_pl
	+lda_mx slope_room
	cmp room_idx
	bne .dw_sln
	stx obj_i
	+lda_mx slope_x
	sta box_x
	+lda_mx slope_y
	sta box_y
	+lda_mx slope_z
	sta box_z
	+lda_mx slope_sx
	sta box_sx
	+lda_mx slope_sy
	sta box_sy
	+lda_mx slope_sz
	sta box_sz
	jsr frustum_hits
	bcc .dw_slr
	jsr draw_slope_mesh
.dw_slr
	ldx obj_i
.dw_sln
	inx
	beq .dw_pl
	jmp .dw_slope
.dw_pl
	ldx #0
.dw_plat
	cpx	map_nplats
	+bcs_far .dw_bp
	+lda_mx plat_room
	cmp room_idx
	bne .dw_pln
	stx obj_i
	+lda_mx plat_x
	sta box_x
	+lda_mx plat_y
	sta box_y
	+lda_mx plat_z
	sta box_z
	+lda_mx plat_sx
	sta box_sx
	lda #1
	sta box_sy
	+lda_mx plat_sz
	sta box_sz
	jsr frustum_hits
	bcc .dw_plr
	jsr draw_plat_mesh
.dw_plr
	ldx obj_i
.dw_pln
	inx
	beq .dw_bp
	jmp .dw_plat
	; backpacks
.dw_bp
	ldx #0
.dw_bpl
	cpx	map_nbackpacks
	+bcs_far .dw_drops
	lda bp_taken,x
	bne .dw_bpn
	+lda_mx bp_room
	cmp room_idx
	bne .dw_bpn
	stx obj_i
	+lda_mx bp_x
	sta box_x
	+lda_mx bp_y
	sta box_y
	+lda_mx bp_z
	sta box_z
	lda #BP_FOOT_SX
	sta box_sx
	lda #BP_FOOT_SY
	sta box_sy
	lda #BP_FOOT_SZ
	sta box_sz
	jsr frustum_hits
	bcc .dw_bpr
	jsr draw_backpack_mesh
.dw_bpr
	ldx obj_i
.dw_bpn
	inx
	beq .dw_drops
	jmp .dw_bpl
	; death drops
.dw_drops
	ldx #0
.dw_dpl
	cpx	map_nenemies
	+bcs_far .dw_rts
	lda drop_taken,x
	bne .dw_dpn
	lda drop_room,x
	cmp room_idx
	bne .dw_dpn
	stx obj_i
	lda drop_x,x
	sta box_x
	lda drop_y,x
	sta box_y
	lda drop_z,x
	sta box_z
	lda #BP_FOOT_SX
	sta box_sx
	lda #BP_FOOT_SY
	sta box_sy
	lda #BP_FOOT_SZ
	sta box_sz
	jsr frustum_hits
	bcc .dw_dpr
	ldx obj_i
	lda drop_type,x
	jsr draw_pickup_mesh
.dw_dpr
	ldx obj_i
.dw_dpn
	inx
	beq .dw_rts
	jmp .dw_dpl
.dw_rts
	rts
