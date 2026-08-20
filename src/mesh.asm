; World object meshes — AABB / door / switch / slope / plat wireframes
!zone mesh

; Edge list: pairs of corner indices 0..7
box_edges
	!byte 0,1, 1,2, 2,3, 3,0
	!byte 4,5, 5,6, 6,7, 7,4
	!byte 0,4, 1,5, 2,6, 3,7

; Ramp quad, switch triangle, door closed/open (no floor edge)
quad_edges
	!byte 0,1, 1,2, 2,3, 3,0
tri_edges
	!byte 0,1, 1,2, 2,0
tetra_edges
	!byte 0,1, 1,2, 2,0,  3,0, 3,1, 3,2
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
quad_vert
	!byte 0,0,0,0
tri_vert
	!byte 0,0,0
tetra_vert
	!byte 0,0,0, 0,0,0

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
bp_xid
	!byte 0,1,2,2			; b0 b1 b2 apex
bp_zid
	!byte 0,0,1,2
bp_col
	!byte 0,1,2,3
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

; Level-base tetrahedron: base 0-1-2, apex 3
draw_backpack_mesh
	jsr load_view_trig
	jsr fill_backpack_verts
	lda #4
	sta mesh_nv
	lda #6
	sta mesh_ne
	lda #<tetra_edges
	sta edge_ptr
	lda #>tetra_edges
	sta edge_ptr+1
	lda #<tetra_vert
	sta edge_vert_ptr
	lda #>tetra_vert
	sta edge_vert_ptr+1
	jmp stroke_mesh

fill_backpack_verts
	; Level-base tetra: equilateral-ish triangle, apex above centroid
	; b0 (x,z) b1 (x+2,z) b2 (x+1,z+2) apex (x+1,z+1,y+2)
	lda box_x
	sta UX				; 0
	clc
	adc #BP_FOOT_SX
	sta UX+1			; 1 = x+2
	lda box_x
	clc
	adc #1
	sta UX+2			; 2 = x+1 (b2 + apex)
	lda box_z
	sta UZ				; 0
	clc
	adc #BP_FOOT_SZ
	sta UZ+1			; 1 = z+2 (b2)
	lda box_z
	clc
	adc #1
	sta UZ+2			; 2 = z+1 (apex)
	lda #3
	sta mesh_nx
	sta mesh_nz
	lda box_y
	sta VY
	sta VY+1
	sta VY+2
	clc
	adc #BP_FOOT_SY
	sta VY+3
	lda #<bp_col
	sta col_ptr
	lda #>bp_col
	sta col_ptr+1
	lda #<bp_xid
	sta xid_ptr
	lda #>bp_xid
	sta xid_ptr+1
	lda #<bp_zid
	sta zid_ptr
	lda #>bp_zid
	sta zid_ptr+1
	lda #4
	sta mesh_nv
	jmp xform_mesh_xz

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
	; doors: closed 4-vert face; open full-width leaves slide open/2
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
	lda door_vx,x
	sta box_x
	lda door_y,x
	sta box_y
	lda door_vz,x
	sta box_z
	lda door_vsx,x
	sta box_sx
	lda door_sy,x
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
	bcs .dw_pl
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
.dw_pl
	ldx #0
.dw_plat
	cpx #MAP_NPLATS
	bcs .dw_bp
	lda plat_room,x
	cmp room_idx
	bne .dw_pln
	stx obj_i
	lda plat_x,x
	sta box_x
	lda plat_y,x
	sta box_y
	lda plat_z,x
	sta box_z
	lda plat_sx,x
	sta box_sx
	lda #1
	sta box_sy
	lda plat_sz,x
	sta box_sz
	jsr frustum_hits
	bcc .dw_plr
	jsr draw_plat_mesh
.dw_plr
	ldx obj_i
.dw_pln
	inx
	bne .dw_plat
	; backpacks
.dw_bp
	ldx #0
.dw_bpl
	cpx #MAP_NBACKPACKS
	bcs .dw_drops
	lda bp_taken,x
	bne .dw_bpn
	lda bp_room,x
	cmp room_idx
	bne .dw_bpn
	stx obj_i
	lda bp_x,x
	sta box_x
	lda bp_y,x
	sta box_y
	lda bp_z,x
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
	bne .dw_bpl
	; death drops
.dw_drops
	ldx #0
.dw_dpl
	cpx #MAP_NENEMIES
	bcs .dw_rts
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
	jsr draw_backpack_mesh
.dw_dpr
	ldx obj_i
.dw_dpn
	inx
	bne .dw_dpl
.dw_rts
	rts
