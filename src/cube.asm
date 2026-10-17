; v-cam 8.8, yaw rotate, near+frustum clip, stroke enemies / meshes
!zone cube

!source "enemy_data.asm"

; A = signed editor byte → nlo:nhi = A/8 as 8.8 (hi = A>>3 arithmetic, lo = A<<5)
scale_s8_88
	sta nlo
	cmp #$80
	ror
	cmp #$80
	ror
	cmp #$80
	ror
	sta nhi
	lda nlo
	asl
	asl
	asl
	asl
	asl
	sta nlo
	rts

; Local vert gidx (gx/gz_ptr, signed editor bytes) rotated by the facing in
; sg_a/pa_* (cos) and sg_b/pb_* (sin) → e0x:e0xh = x', e1z:e1zh = z' (8.8).
; x' = (lx*cc - lz*ss) >> 2, z' = (lx*ss + lz*cc) >> 2: four unsigned 8x8
; products, signs applied per term, one shift at the end.
!macro rl_umul .s1l, .s2l, .s1h, .s2h, .lo, .hi {
	sec
	lda (.s1l),y
	sbc (.s2l),y
	sta .lo
	lda (.s1h),y
	sbc (.s2h),y
	sta .hi
}
!macro rl_neg .lo, .hi {
	sec
	lda #0
	sbc .lo
	sta .lo
	lda #0
	sbc .hi
	sta .hi
}
ent_rot_local
	ldy gidx
	lda (gx_ptr),y
	sta lx_b
	bpl +
	eor #$ff
	clc
	adc #1
+
	tay
	+rl_umul pa_s1l, pa_s2l, pa_s1h, pa_s2h, e0x, e0xh
	lda lx_b
	eor sg_a
	bpl +
	+rl_neg e0x, e0xh
+
	+rl_umul pb_s1l, pb_s2l, pb_s1h, pb_s2h, e1z, e1zh
	lda lx_b
	eor sg_b
	bpl +
	+rl_neg e1z, e1zh
+
	ldy gidx
	lda (gz_ptr),y
	sta lz_b
	bpl +
	eor #$ff
	clc
	adc #1
+
	tay
	+rl_umul pb_s1l, pb_s2l, pb_s1h, pb_s2h, nlo, nhi
	lda lz_b
	eor sg_b
	bmi .rl_xadd			; lz*ss < 0: x' = e0 + |lz*ss|
	sec
	lda e0x
	sbc nlo
	sta e0x
	lda e0xh
	sbc nhi
	jmp .rl_x2
.rl_xadd
	clc
	lda e0x
	adc nlo
	sta e0x
	lda e0xh
	adc nhi
.rl_x2
	sta e0xh
	+rl_umul pa_s1l, pa_s2l, pa_s1h, pa_s2h, nlo, nhi
	lda lz_b
	eor sg_a
	bpl .rl_zadd			; lz*cc >= 0: z' = e1 + |lz*cc|
	sec
	lda e1z
	sbc nlo
	sta e1z
	lda e1zh
	sbc nhi
	jmp .rl_z2
.rl_zadd
	clc
	lda e1z
	adc nlo
	sta e1z
	lda e1zh
	adc nhi
.rl_z2
	cmp #$80			; z' >>= 2
	ror
	sta e1zh
	ror e1z
	cmp #$80
	ror
	sta e1zh
	ror e1z
	lda e0xh			; x' >>= 2
	cmp #$80
	ror
	sta e0xh
	ror e0x
	cmp #$80
	ror
	sta e0xh
	ror e0x
	rts

load_view_trig
	!source "_rotate_body.asm"
	rts

; Load type base pointers for ent_type (frame 0 of gx/gy/gz).
ent_set_ptrs
	ldx ent_type
	lda enemy_gx_lo,x
	sta gx_ptr
	lda enemy_gx_hi,x
	sta gx_ptr+1
	lda enemy_gy_lo,x
	sta gy_ptr
	lda enemy_gy_hi,x
	sta gy_ptr+1
	lda enemy_gz_lo,x
	sta gz_ptr
	lda enemy_gz_hi,x
	sta gz_ptr+1
	rts

; X = enemy. Y = meta slot 0 or 1. A and X preserved. Does not use rot*.
ldy_slot
	pha
	+lda_mx en_type
	cmp meta_slot_type
	beq .ls0
	ldy #1
	pla
	rts
.ls0	ldy #0
	pla
	rts

; Y = type id. Y := slot. A and X preserved.
slot_of_y
	pha
	tya
	cmp meta_slot_type
	beq .sofy0
	ldy #1
	pla
	rts
.sofy0	ldy #0
	pla
	rts

; X = enemy. A preserved. Y = slot * PAIN_MAX + en_pain_i (pain/death/attack variant)
!if PAIN_MAX != 4 {
	!error "pain_var_off assumes PAIN_MAX=4"
}
pain_var_off
	sta rot0
	jsr ldy_slot
	tya
	asl
	asl
	clc
	adc en_pain_i,x
	tay
	lda rot0
	rts

; X = enemy. A = enemy_class[slot]. Y = type. X preserved.
enemy_get_class
	+ldy_mx en_type
	tya
	pha
	jsr ldy_slot
	lda enemy_class,y
	sta meta_scratch
	pla
	tay
	lda meta_scratch
	rts

; X = enemy. Y = logical timeline frame (clip start + en_frame).
; Pose and clip SFX share this clock. rot0 via pain_var_off; src_ptr preserved.
enemy_logical_frame
	lda en_state,x
	cmp #EN_DYING
	beq .elf_death
	cmp #EN_DEAD
	beq .elf_death
	cmp #EN_PAIN
	beq .elf_pain
	cmp #EN_ATTACK
	beq .elf_atk
	cmp #EN_ALERT
	beq .elf_alert
	cmp #EN_APPROACH
	beq .elf_run
	cmp #EN_PATROL
	beq .elf_walk
	lda en_frame,x
	jsr ldy_slot
	clc
	adc enemy_stand_start,y
	tay
	rts
.elf_run
	lda en_frame,x
	jsr ldy_slot
	clc
	adc enemy_run_start,y
	tay
	rts
.elf_walk
	lda en_frame,x
	jsr ldy_slot
	clc
	adc enemy_walk_start,y
	tay
	rts
.elf_alert
	lda en_frame,x
	jsr ldy_slot
	clc
	adc enemy_alert_start,y
	tay
	rts
.elf_atk
	lda en_frame,x
	jsr pain_var_off
	clc
	adc enemy_attack_start,y
	tay
	rts
.elf_pain
	lda en_frame,x
	jsr pain_var_off
	clc
	adc enemy_pain_start,y
	tay
	rts
.elf_death
	lda en_frame,x
	jsr pain_var_off
	clc
	adc enemy_death_start,y
	tay
	rts

; Point gx/gy/gz at the current pose for ent_type / obj_i.
ent_set_pose
	jsr ent_set_ptrs
	ldx obj_i
	jsr enemy_logical_frame
.esp_off
	; Y = logical global frame. pose_map (heap): packed index or $FF = midpoint lerp.
	ldx ent_type
	lda pose_map_lo,x
	sta rot1
	lda pose_map_hi,x
	sta rot2
	lda (rot1),y
	bpl .esp_stored
	jmp pose_lerp
.esp_stored
	tay
	ldx ent_type
	jsr frame_stride
	clc
	lda gx_ptr
	adc nlo
	sta gx_ptr
	lda gx_ptr+1
	adc nhi
	sta gx_ptr+1
	clc
	lda gy_ptr
	adc nlo
	sta gy_ptr
	lda gy_ptr+1
	adc nhi
	sta gy_ptr+1
	clc
	lda gz_ptr
	adc nlo
	sta gz_ptr
	lda gz_ptr+1
	adc nhi
	sta gz_ptr+1
	rts

; X = type, Y = frame or stored count. nlo:nhi = Y * pose stride.
; No prefix: frame13 (Y*13). Prefix with nv = 0: stride 0. Otherwise nv.
; Preserves X. Destroys Y on the multiply path.
frame_stride
	lda skel_base_hi,x
	beq .fs_f13
	lda skel_nv,x
	bne .fs_nv
	lda #0
	sta nlo
	sta nhi
	rts
.fs_f13
	lda frame13_lo,y
	sta nlo
	lda frame13_hi,y
	sta nhi
	rts
.fs_nv
	sta skel_mul_n
	jmp skel_mul_ya

pose_lerp
	ldx ent_type
	lda skel_entry_hi,x
	beq .pl_res
	lda #SKEL_CMD_LERP
	jmp skel_call
.pl_res
	sty gidx
	dey
	lda (rot1),y
	sta rot0
	ldy gidx
	iny
	lda (rot1),y
	sta gidx
	ldx ent_type
	ldy rot0
	clc
	lda enemy_gx_lo,x
	adc frame13_lo,y
	sta src_ptr
	lda enemy_gx_hi,x
	adc frame13_hi,y
	sta src_ptr+1
	ldy gidx
	clc
	lda enemy_gx_lo,x
	adc frame13_lo,y
	sta dst_ptr
	lda enemy_gx_hi,x
	adc frame13_hi,y
	sta dst_ptr+1
	ldy #0
.plx
	jsr pose_avg_y
	sta pose_gx,y
	iny
	cpy #NVERTS
	bcc .plx
	ldy rot0
	clc
	lda enemy_gy_lo,x
	adc frame13_lo,y
	sta src_ptr
	lda enemy_gy_hi,x
	adc frame13_hi,y
	sta src_ptr+1
	ldy gidx
	clc
	lda enemy_gy_lo,x
	adc frame13_lo,y
	sta dst_ptr
	lda enemy_gy_hi,x
	adc frame13_hi,y
	sta dst_ptr+1
	ldy #0
.ply
	jsr pose_avg_y
	sta pose_gy,y
	iny
	cpy #NVERTS
	bcc .ply
	ldy rot0
	clc
	lda enemy_gz_lo,x
	adc frame13_lo,y
	sta src_ptr
	lda enemy_gz_hi,x
	adc frame13_hi,y
	sta src_ptr+1
	ldy gidx
	clc
	lda enemy_gz_lo,x
	adc frame13_lo,y
	sta dst_ptr
	lda enemy_gz_hi,x
	adc frame13_hi,y
	sta dst_ptr+1
	ldy #0
.plz
	jsr pose_avg_y
	sta pose_gz,y
	iny
	cpy #NVERTS
	bcc .plz
	lda #<pose_gx
	sta gx_ptr
	lda #>pose_gx
	sta gx_ptr+1
	lda #<pose_gy
	sta gy_ptr
	lda #>pose_gy
	sta gy_ptr+1
	lda #<pose_gz
	sta gz_ptr
	lda #>pose_gz
	sta gz_ptr+1
	rts

; Signed (src+dst)>>1. Y = vert. X/Y preserved. nlo/nhi scratch.
pose_avg_y
	lda #0
	sta nhi
	lda (src_ptr),y
	bpl +
	dec nhi
+	clc
	adc (dst_ptr),y
	sta nlo
	lda nhi
	adc #0
	sta nhi
	lda (dst_ptr),y
	bpl +
	dec nhi
+	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	lda nlo
	rts

; Rotate one enemy instance at ent_wx/wy/wz, ent_rot, ent_type.
; Caller already ran load_view_trig + xform_world_vert (CAM[0] = view origin).
; view(v) = R_yaw(world − cam) + R(yaw − facing)(local): the rotated origin
; is hoisted per enemy and facing (8-bit yaw ticks) folds into the trig
; angle — 8-bit local products replace 16-bit smul16_7s.
ent_rotate
	jsr ent_set_pose
	; combined angle a = yaw − ent_rot → fast-mul sets (A=cos, B=sin)
	sec
	lda yaw
	sbc ent_rot
	tay
	lda COSTAB,y
	jsr mulset_a
	lda SINTAB,y
	jsr mulset_b
	; view-space origin from CAM[0] (xform_world_vert output)
	lda CAM_X
	sta org_xl
	lda CAM_XH
	sta org_xh
	lda CAM_Y
	sta org_yl
	lda CAM_YH
	sta org_yh
	lda CAM_Z
	sta org_zl
	lda CAM_ZH
	sta org_zh
	lda #0
	sta gidx
	sta vindex
.rvert
	jsr ent_rot_local
	; CAM[v] = origin + rotated local (y unrotated: yaw-only view)
	ldx vindex
	clc
	lda org_xl
	adc e0x
	sta CAM_X,x
	lda org_xh
	adc e0xh
	sta CAM_XH,x
	clc
	lda org_zl
	adc e1z
	sta CAM_Z,x
	lda org_zh
	adc e1zh
	sta CAM_ZH,x
	ldy gidx
	lda (gy_ptr),y
	jsr scale_s8_88			; nlo:nhi = gy·32 (8.8 of gy/8)
	clc
	lda org_yl
	adc nlo
	sta CAM_Y,x
	lda org_yh
	adc nhi
	sta CAM_YH,x
	inc gidx
	inc vindex
	lda vindex
	cmp #NVERTS
	beq +
	jmp .rvert
+
	lda #NVERTS
	sta mesh_nwork
!if PROFILE = 1 {
	ldx #NV_ROT
	jmp prof_add_nv
} else {
	rts
}

; Y = local vert. obj_i = enemy, ent_type set. org_* = world 8.8 of that bone.
; Facing rotate only (same smul8_88 / scale_s8_88 as ent_rotate).
ent_vert_world
	sty gidx
	jsr ent_set_pose
	ldx obj_i
	+lda_mx en_rot
	eor #$ff			; drawn bones use R(yaw - rot): world offset is R(-rot)
	clc
	adc #1
	tay
	lda COSTAB,y
	jsr mulset_a
	lda SINTAB,y
	jsr mulset_b
	jsr ent_rot_local
	ldx obj_i
	clc
	lda e0x
	sta org_xl
	+lda_mx en_x
	adc e0xh
	sta org_xh
	clc
	lda e1z
	sta org_zl
	+lda_mx en_z
	adc e1zh
	sta org_zh
	ldy gidx
	lda (gy_ptr),y
	jsr scale_s8_88
	clc
	lda nlo
	sta org_yl
	ldx obj_i
	+lda_mx en_y
	adc nhi
	sta org_yh
	rts

; Y = vert index. Branch to .skip if culled by mesh_vmask. 8 cycles at $ff.
!macro vskip_br .skip {
	lda mesh_vmask
	cmp #$ff
	beq +
	and box_vbit,y
	beq .skip
+
}
!macro vskip_jmp .skip {
	lda mesh_vmask
	cmp #$ff
	beq +
	and box_vbit,y
	bne +
	jmp .skip
+
}

; 8.8 view → unclamped 16-bit screen, then CS. persp88 is far enemies only.
; Verts sharing an XZ column (col_ptr table) share z_eye, inv and PROJ_X:
; box corners come in vertical pairs, so half the divides/X-projections.
mesh_project
cube_project
	lda mesh_vmask
	cmp #$ff
	bne .mp_go
	lda mesh_nv
	sta mesh_nwork
.mp_go
!if PROFILE = 1 {
	ldx #NV_PROJ
	jsr prof_add_nv
}
	ldx #15
	lda #0
.mp_clr
	sta COL_DONE,x
	dex
	bpl .mp_clr
	sta vindex
.pvert
	ldy vindex
	+vskip_jmp .pnext
	lda (col_ptr),y
	sta cur_col
	tax
	lda COL_DONE,x
	beq .col_new
	cmp #2
	bne .col_front
	ldx vindex			; column already known behind
	lda #OC_NEAR
	sta VOC,x
	jmp .pnext
.col_new
	jsr .zbcam
	bcc .col_calc
	ldx cur_col			; behind: flag column + vertex
	lda #2
	sta COL_DONE,x
	ldx vindex
	lda #OC_NEAR
	sta VOC,x
	jmp .pnext
.col_calc
	jsr .invz			; z_eye set by .zbcam
	ldx cur_col
	lda inv_l
	sta COL_INVL,x
	lda inv_h
	sta COL_INVH,x
	lda inv_k
	sta COL_INVK,x
	lda #1
	sta COL_DONE,x
	ldx vindex
	lda CAM_X,x
	sta nlo
	lda CAM_XH,x
	sta nhi
	jsr .cam_to_proj
	ldx cur_col
	lda nlo
	sta COL_PXL,x
	lda nhi
	sta COL_PXH,x
	jmp .col_py
.col_front
	ldy cur_col			; reuse cached reciprocal
	lda COL_INVL,y
	sta inv_l
	lda COL_INVH,y
	sta inv_h
	lda COL_INVK,y
	sta inv_k
	lda inv_h
	jsr mulset_au
.col_py
	ldx vindex
	ldy cur_col
	lda COL_PXL,y
	sta PROJ_X,x
	lda COL_PXH,y
	sta PROJ_XH,x
	lda CAM_Y,x
	sta nlo
	lda CAM_YH,x
	sta nhi
	jsr .cam_to_proj_m
	ldx vindex
	lda nlo
	sta PROJ_Y,x
	lda nhi
	sta PROJ_YH,x
	jsr vert_hoist
.pnext
	inc vindex
	lda vindex
	cmp mesh_nv
	beq +
	jmp .pvert
+
	rts

; Per-vertex clip data hoisted out of mesh_clip: outcode from 16-bit PROJ,
; and screen coords when fully inside. Behind verts get OC_NEAR in
; mesh_project instead. Window ox -96..95, oy -64..63; inside needs no clamp.
vert_hoist
	ldx vindex
	ldy #0				; Y = outcode
	lda PROJ_XH,x
	beq .hx0
	bpl .hxr
	cmp #$ff
	bne .hxl
	lda PROJ_X,x
	cmp #$100-SCREEN_CX
	bcs .hy
.hxl
	ldy #OC_LEFT
	bne .hy
.hx0
	lda PROJ_X,x
	cmp #SCREEN_CX
	bcc .hy
.hxr
	ldy #OC_RIGHT
.hy
	lda PROJ_YH,x
	beq .hy0
	bpl .hyb
	cmp #$ff
	bne .hyt
	lda PROJ_Y,x
	cmp #$c0
	bcs .hdone
.hyt
	tya
	ora #OC_TOP
	tay
	bne .hdone
.hy0
	lda PROJ_Y,x
	cmp #64
	bcc .hdone
.hyb
	tya
	ora #OC_BOT
	tay
.hdone
	tya
	sta VOC,x
	bne .vh_rts			; VSX/VSY only read on trivial accept
	lda PROJ_X,x
	clc
	adc #SCREEN_CX
	sta VSX,x
	lda #63
	sec
	sbc PROJ_Y,x
	sta VSY,x
.vh_rts
	rts

; C=1 if this vertex z8.8 < ZCLIP
.zbcam
	ldx vindex
	lda CAM_ZH,x
	bmi .zby
	cmp #>ZCLIP
	bcc .zby
	bne .zbn
	lda CAM_Z,x
	cmp #<ZCLIP
	bcc .zby
.zbn
	jsr .setz
	clc
	rts
.zby
	sec
	rts

.setz
	ldx vindex
	lda CAM_Z,x
	sta z_eye
	lda CAM_ZH,x
	sta z_eye_h
	rts

; inv = (FOCAL<<16) / (z>>k), k = unsigned 8-bit fit of z_eye (always ≥128 here).
; z >= ZCLIP guarantees z_eye_h >= 1, so dlo lands in [128,255] → invzl/h LUT.
proj_invz
.invz
	lda z_eye
	sta dlo
	ldx #0
	lda z_eye_h
	beq .gotk
.fz
	inx
	lsr
	ror dlo
	cmp #0
	bne .fz
.gotk
	stx inv_k
	lda dlo
	and #$7f
	tax
	lda invzl,x
	sta inv_l
	lda invzh,x
	sta inv_h
	rts

; nlo:nhi * inv_h >> (8+k) → nlo:nhi. inv_h is the rounded 8-bit mantissa
; of inv (invzh), so inv_l is not read. Clobbers set A, dlo, X, Y.
proj_cam_to_proj
.cam_to_proj
	lda inv_h
	sta pa_s1l
	sta pa_s1h
	eor #$ff
	sta pa_s2l
	sta pa_s2h
; Same, with set A already holding inv_h.
.cam_to_proj_m
	lda nhi
	sta mul_sign
	bpl +
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
+
	ldy nlo
	sec
	lda (pa_s1l),y
	sbc (pa_s2l),y
	lda (pa_s1h),y
	sbc (pa_s2h),y
	sta dlo
	ldy nhi
	sec
	lda (pa_s1l),y
	sbc (pa_s2l),y
	sta nlo
	lda (pa_s1h),y
	sbc (pa_s2h),y
	tax
	clc
	lda nlo
	adc dlo
	sta nlo
	bcc +
	inx
+
	txa
	ldy inv_k
	beq .csgn
.cls
	lsr
	ror nlo
	dey
	bne .cls
.csgn
	sta nhi
	bit mul_sign
	bpl .cdone
	sec
	lda #0
	sbc nlo
	sta nlo
	lda #0
	sbc nhi
	sta nhi
.cdone
	rts

; Near-plane interpolate, then 16-bit screen Cohen-Sutherland.
; Trivial accept/reject runs on per-vertex VOC/VSX/VSY hoisted into
; mesh_project — no PROJ/CAM reads unless an edge needs real work.
mesh_clip
cube_clip
	lda mesh_ne
	sta mesh_nwork
	sta clip_n
!if PROFILE = 1 {
	ldx #NV_CLIP
	jsr prof_add_nv
}
	lda #0
	sta vindex			; edge byte offset
.cel
	ldy vindex
	lda (edge_ptr),y
	tax
	iny
	lda (edge_ptr),y
	iny
	sty vindex
	tay
	lda VOC,x
	ora VOC,y
	bne .work
	lda VSX,x
	sta x0
	lda VSY,x
	sta y0
	lda VSX,y
	sta x1
	lda VSY,y
	sta y1
	jsr draw_line
.next
	dec clip_n
	bne .cel
	rts

.work
	lda VOC,x
	and VOC,y
	bne .next			; same outside side, or both behind
	stx ei0
	sty ei1
	lda VOC,x
	sta oc0
	lda VOC,y
	sta oc1
	ora oc0
	bmi .near
	lda PROJ_X,x
	sta ox0l
	lda PROJ_XH,x
	sta ox0h
	lda PROJ_Y,x
	sta oy0l
	lda PROJ_YH,x
	sta oy0h
	lda PROJ_X,y
	sta ox1l
	lda PROJ_XH,y
	sta ox1h
	lda PROJ_Y,y
	sta oy1l
	lda PROJ_YH,y
	sta oy1h
.cs
	jsr .csrun
	bcs .next
	jsr .stroke
	jmp .next

!if CAM_Y - CAM_X != $10 {
	!error ".near indexes CAM_Y as CAM_X + $10"
}
!if CAM_YH - CAM_XH != $10 {
	!error ".near indexes CAM_YH as CAM_XH + $10"
}
!if MESH_MAX_VERTS > $10 {
	!error ".near ORs $10 into a vertex index"
}

; One endpoint behind ZCLIP. Lerp it onto the plane and project it at
; ZCLIP; the front one keeps its PROJ and VOC. Both stay in their edge
; slots (CS clips endpoint 0 first). ei0 = behind, ei1 = front from here.
.near
	lda #0
	bit oc0
	bmi .nr0
	stx ei1
	sty ei0
	lda #4
.nr0
	sta nc_s
	eor #4
	tax
	ldy ei1
	lda PROJ_X,y
	sta ox0l,x
	lda PROJ_XH,y
	sta ox0h,x
	lda PROJ_Y,y
	sta oy0l,x
	lda PROJ_YH,y
	sta oy0h,x
	ldx ei0
	sec
	lda #<ZCLIP
	sbc CAM_Z,x
	sta nlo
	lda #>ZCLIP
	sbc CAM_ZH,x
	sta nhi
	sec
	lda CAM_Z,y
	sbc CAM_Z,x
	sta dlo
	lda CAM_ZH,y
	sbc CAM_ZH,x
	sta dhi
	jsr scale_nd
	lda nlo
	sta nc_n
	lda dlo
	sta nc_d
	lda #<ZCLIP
	sta z_eye
	lda #>ZCLIP
	sta z_eye_h
	jsr .invz
	ldx ei0
	ldy ei1
	jsr .nlerp
	jsr .cam_to_proj
	ldx nc_s
	lda nlo
	sta ox0l,x
	lda nhi
	sta ox0h,x
	lda ei0
	ora #CAM_Y - CAM_X
	tax
	lda ei1
	ora #CAM_Y - CAM_X
	tay
	jsr .nlerp
	jsr .cam_to_proj_m
	ldx nc_s
	lda nlo
	sta oy0l,x
	lda nhi
	sta oy0h,x
	jsr .mkoc
	jmp .cs

; X = behind CAM index, Y = front (both + CAM_Y-CAM_X for the Y axis).
; CAM[X] + (CAM[Y] - CAM[X]) * nc_n / nc_d → nlo:nhi.
.nlerp
	stx nc_v
	sec
	lda CAM_X,y
	sbc CAM_X,x
	sta ylo
	lda CAM_XH,y
	sbc CAM_XH,x
	sta yhi
	lda nc_n
	sta nlo
	lda nc_d
	sta dlo
	jsr lerp16
	ldx nc_v
	clc
	adc CAM_X,x
	sta nlo
	lda div_n1
	adc CAM_XH,x
	sta nhi
	rts

; C=0 accept (ox/oy inside), C=1 reject. oc0/oc1 preloaded by caller;
; each iteration recomputes only the endpoint that moved.
.csrun
	lda #16
	sta cs_n
.cslp
	lda oc0
	ora oc1
	bne .csneed
	clc
	rts
.csneed
	lda oc0
	and oc1
	bne .csrej
	dec cs_n
	beq .csrej
	ldx #0
	lda oc0
	bne .csbit
	ldx #4
	lda oc1
.csbit
	ldy #$ff			; Y = lowest set outcode bit: L R T B
-	iny
	lsr
	bcc -
	lda .cs_plane,y
	sta rot0
	asl
	lda #0
	adc #$ff
	eor #$ff
	sta rot2			; sign-extend the plane
	cpy #2
	bcc +
	inx				; T/B clip oy
	inx
+	jsr .csclip
	jsr .mkoc
	jmp .cslp
.csrej
	sec
	rts

.cs_plane
	!byte <CLIP_XMIN, CLIP_XMAX, <CLIP_YMIN, CLIP_YMAX

; X = moved endpoint + clip axis: 0 ox0, 2 oy0, 4 ox1, 6 oy1. rot0:rot2 =
; plane. That axis goes to the plane; the other moves toward the far
; endpoint. Returns X = moved endpoint (0/4).
.csclip
	txa
	eor #4
	tay
	sec
	lda ox0l,y
	sbc ox0l,x
	sta dlo
	lda ox0h,y
	sbc ox0h,x
	sta dhi
	sec
	lda rot0
	sbc ox0l,x
	sta nlo
	lda rot2
	sbc ox0h,x
	sta nhi
	lda rot0
	sta ox0l,x
	lda rot2
	sta ox0h,x
	txa
	eor #2
	tax
	eor #4
	tay
	sec
	lda ox0l,y
	sbc ox0l,x
	sta ylo
	lda ox0h,y
	sbc ox0h,x
	sta yhi
	ora ylo
	beq .ccdone			; other axis level (vertical / horizontal edge)
	txa
	pha
	jsr scale_nd
	jsr lerp16
	pla
	tax
	clc
	lda div_n0
	adc ox0l,x
	sta ox0l,x
	lda div_n1
	adc ox0h,x
	sta ox0h,x
.ccdone
	txa
	and #4
	tax
	rts

; X = endpoint (0/4). Outcode of ox/oy[X] → oc0 / oc1 and A. X kept.
.mkoc
	ldy #0
	lda ox0h,x
	bmi .mkxn
	bne .mkr
	lda ox0l,x
	cmp #CLIP_XMAX+1
	bcc .mky
.mkr
	ldy #OC_RIGHT
	bne .mky
.mkxn
	cmp #$ff
	bne .mkl
	lda ox0l,x
	cmp #<CLIP_XMIN
	bcs .mky
.mkl
	ldy #OC_LEFT
.mky
	lda oy0h,x
	bmi .mkyn
	bne .mkb
	lda oy0l,x
	cmp #CLIP_YMAX+1
	bcc .mkin
.mkb
	tya
	ora #OC_BOT
	bne .mkst
.mkyn
	cmp #$ff
	bne .mkt
	lda oy0l,x
	cmp #<CLIP_YMIN
	bcs .mkin
.mkt
	tya
	ora #OC_TOP
	bne .mkst
.mkin
	tya
.mkst
	cpx #0
	bne .mk1
	sta oc0
	rts
.mk1
	sta oc1
	rts

; ox/oy inside the window (outcodes 0) → x0..y1, stroke.
.stroke
	lda ox0l
	clc
	adc #SCREEN_CX
	sta x0
	lda ox1l
	clc
	adc #SCREEN_CX
	sta x1
	lda #63
	sec
	sbc oy0l
	sta y0
	lda #63
	sec
	sbc oy1l
	sta y1
	jmp draw_line

; A=ox lo Y=ox hi → screen x 0..191
.to_sx
	clc
	adc #SCREEN_CX
	sta nlo
	tya
	adc #0
	bmi .sx0
	bne .sxh
	lda nlo
	cmp #192
	bcc .sxok
.sxh
	lda #191
	rts
.sx0
	lda #0
.sxok
	rts

; A=oy lo Y=oy hi → screen y 0..127 (Y-down: screen = 63 - oy). The clip
; window is oy -64..63; 64 - oy put it on 1..128, so line 0 was never reached
; (one purple scanline above the first drawn line) and oy=-64 clamped to 127.
.to_sy
	eor #$ff
	clc
	adc #1
	sta nlo
	tya
	eor #$ff
	adc #0
	tay
	lda nlo
	clc
	adc #63
	sta nlo
	tya
	adc #0
	bmi .sy0
	bne .syh
	lda nlo
	cmp #128
	bcc .syok
.syh
	lda #127
	rts
.sy0
	lda #0
.syok
	rts

; ox0/oy0 and ox1/oy1 centered 16-bit. Clip to the viewport and stroke.
; C=1 if the segment is fully outside. Clobbers ox/oy, oc0/oc1, rot0, rot2.
clip_draw_xy
	ldx #0
	jsr .mkoc
	ldx #4
	jsr .mkoc
	jsr .csrun
	bcs .cd_no
	jsr .stroke
	clc
.cd_no
	rts

; X = CAM slot; world int ent_wx/wy/wz → view CAM[X]
; Caller must jsr load_view_trig first.
xform_world_vert
	stx vindex
	; dx (kept in e0x until x' overwrites it)
	lda #0
	sec
	sbc cam_xl
	sta e0x
	lda ent_wx
	sbc cam_xh
	sta e0xh
	; dz
	lda #0
	sec
	sbc cam_zl
	sta e1z
	lda ent_wz
	sbc cam_zh
	sta e1zh
	; dy
	lda #0
	sec
	sbc cam_yl
	sta e1x
	lda ent_wy
	sbc cam_yh
	sta e1xh
	jmp xform_view_from_delta

; X = CAM slot; world 8.8 in org_xl/xh, org_yl/yh, org_zl/zh → view CAM[X]
xform_world_vert88
	stx vindex
	lda org_xl
	sec
	sbc cam_xl
	sta e0x
	lda org_xh
	sbc cam_xh
	sta e0xh
	lda org_zl
	sec
	sbc cam_zl
	sta e1z
	lda org_zh
	sbc cam_zh
	sta e1zh
	lda org_yl
	sec
	sbc cam_yl
	sta e1x
	lda org_yh
	sbc cam_yh
	sta e1xh

xform_view_from_delta
	; z' = dx*sn + dz*cs
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_b			; × sin(yaw) via set B
	lda nlo
	sta rot0
	lda nhi
	sta rot1
	lda e1z
	sta nlo
	lda e1zh
	sta nhi
	jsr smul16_a			; × cos(yaw) via set A
	clc
	lda rot0
	adc nlo
	sta e0y
	lda rot1
	adc nhi
	sta e0yh

	; x' = dx*cs - dz*sn
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_a			; × cos(yaw) via set A
	lda nlo
	sta rot0
	lda nhi
	sta rot1
	lda e1z
	sta nlo
	lda e1zh
	sta nhi
	jsr smul16_b			; × sin(yaw) via set B
	sec
	lda rot0
	sbc nlo
	sta e0x
	lda rot1
	sbc nhi
	sta e0xh

	ldx vindex
	lda e1x
	sta CAM_Y,x
	lda e1xh
	sta CAM_YH,x
	lda e0y
	sta CAM_Z,x
	lda e0yh
	sta CAM_ZH,x
	lda e0x
	sta CAM_X,x
	lda e0xh
	sta CAM_XH,x
	rts

; CAM[0] filled. C=1 → A=sx (0..191), Y=sy (0..127). C=0 behind / invalid.
; persp is signed; 8-bit adc+bpl treats sx 128..191 as negative — sign-extend.
project_cam0_screen
	lda CAM_ZH
	bmi .pcs_no
	bne .pcs_zok
	lda CAM_Z
	beq .pcs_no
.pcs_zok
	lda CAM_Z
	sta z_eye
	lda CAM_ZH
	sta z_eye_h
	lda CAM_X
	sta ylo
	lda CAM_XH
	sta yhi
	jsr persp88
	ldx #SCREEN_CX
	stx rot1
	ldx #192
	stx rot2
	jsr .pcs_bias
	sta rot0
	lda CAM_Y
	sta ylo
	lda CAM_YH
	sta yhi
	jsr persp88
	eor #$ff
	clc
	adc #1
	ldx #64
	stx rot1
	ldx #128
	stx rot2
	jsr .pcs_bias
	tay
	lda rot0
	sec
	rts
.pcs_no
	clc
	rts

; A = signed offset + rot1, clamp 0 .. rot2-1.
.pcs_bias
	sta nlo
	lda #0
	bit nlo
	bpl +
	lda #$ff
+
	sta nhi
	clc
	lda nlo
	adc rot1
	sta nlo
	lda nhi
	adc #0
	bmi .pcs_b0
	bne .pcs_bhi
	lda nlo
	cmp rot2
	bcc .pcs_bok
.pcs_bhi
	lda rot2
	sec
	sbc #1
	rts
.pcs_b0
	lda #0
.pcs_bok
	rts

; CAM[0] in front → centered 16-bit ox0/oy0 (mesh PROJ space). C=0 if z<=0.
; z >= ZCLIP is proj_invz. Closer is persp88, sign-extended, not viewport-clamped.
cam0_proj_xy
	lda CAM_ZH
	bmi .cp_no
	bne .cp_far
	lda CAM_Z
	beq .cp_no
	sta z_eye
	lda #0
	sta z_eye_h
	lda CAM_X
	sta ylo
	lda CAM_XH
	sta yhi
	jsr persp88
	jsr .cp_sex
	sta ox0l
	sty ox0h
	lda CAM_Y
	sta ylo
	lda CAM_YH
	sta yhi
	jsr persp88
	jsr .cp_sex
	sta oy0l
	sty oy0h
	sec
	rts
.cp_far
	lda CAM_Z
	sta z_eye
	lda CAM_ZH
	sta z_eye_h
	jsr proj_invz
	lda CAM_X
	sta nlo
	lda CAM_XH
	sta nhi
	jsr proj_cam_to_proj
	lda nlo
	sta ox0l
	lda nhi
	sta ox0h
	lda CAM_Y
	sta nlo
	lda CAM_YH
	sta nhi
	jsr proj_cam_to_proj
	lda nlo
	sta oy0l
	lda nhi
	sta oy0h
	sec
	rts
.cp_no
	clc
	rts
; A signed 8-bit → Y = high byte. A preserved.
.cp_sex
	ldy #0
	ora #0
	bpl +
	ldy #$ff
+
	rts

; Unique UX/UZ * sin/cos, then CAM[v] from (xid,zid,VY[v]).
; Caller sets mesh_nx/nz/nv, UX/UZ/VY, xid_ptr/zid_ptr; jsr load_view_trig.
xform_mesh_xz
	ldx #0
.xm_x
	cpx mesh_nx
	beq .xm_z
	lda #0
	sec
	sbc cam_xl
	sta e0x
	lda UX,x
	sbc cam_xh
	sta e0xh
	stx vindex
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_a			; × cos(yaw) via set A
	ldx vindex
	lda nlo
	sta XC_L,x
	lda nhi
	sta XC_H,x
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_b			; × sin(yaw) via set B
	ldx vindex
	lda nlo
	sta XS_L,x
	lda nhi
	sta XS_H,x
	inx
	jmp .xm_x
.xm_z
	ldx #0
.xm_zl
	cpx mesh_nz
	beq .xm_v
	lda #0
	sec
	sbc cam_zl
	sta e0x
	lda UZ,x
	sbc cam_zh
	sta e0xh
	stx vindex
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_a			; × cos(yaw) via set A
	ldx vindex
	lda nlo
	sta ZC_L,x
	lda nhi
	sta ZC_H,x
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_b			; × sin(yaw) via set B
	ldx vindex
	lda nlo
	sta ZS_L,x
	lda nhi
	sta ZS_H,x
	inx
	jmp .xm_zl
.xm_v
	lda #0
	sta vindex
.xm_vl
	ldy vindex
	+vskip_br .xm_skip
	lda (xid_ptr),y
	tax
	lda (zid_ptr),y
	tay
	lda XC_L,x
	sec
	sbc ZS_L,y
	sta e0x
	lda XC_H,x
	sbc ZS_H,y
	sta e0xh
	lda XS_L,x
	clc
	adc ZC_L,y
	sta e0y
	lda XS_H,x
	adc ZC_H,y
	sta e0yh
	ldx vindex
	lda #0
	sec
	sbc cam_yl
	sta CAM_Y,x
	lda VY,x
	sbc cam_yh
	sta CAM_YH,x
	lda e0x
	sta CAM_X,x
	lda e0xh
	sta CAM_XH,x
	lda e0y
	sta CAM_Z,x
	lda e0yh
	sta CAM_ZH,x
.xm_skip
	inc vindex
	lda vindex
	cmp mesh_nv
	bne .xm_vl
	lda mesh_vmask
	cmp #$ff
	bne .xr
	lda mesh_nv
	sta mesh_nwork
.xr
!if PROFILE = 1 {
	ldx #NV_ROT
	jmp prof_add_nv
} else {
	rts
}

; Local UX/UZ about ent_wx/wy/wz, then R_(yaw+ent_rot). Caller: load_view_trig.
; xform_item_spin: world centre is box+ITEM_BIAS (pickups).
; xform_item_at: caller already set ent_wx/wy/wz (doors).
xform_item_spin
	clc
	lda box_x
	adc #ITEM_BIAS
	sta ent_wx
	lda box_y
	sta ent_wy
	clc
	lda box_z
	adc #ITEM_BIAS
	sta ent_wz
xform_item_at
	ldx #0
	jsr xform_world_vert
	lda CAM_X
	sta org_xl
	lda CAM_XH
	sta org_xh
	lda CAM_Z
	sta org_zl
	lda CAM_ZH
	sta org_zh
	clc
	lda yaw
	adc ent_rot
	tay
	lda COSTAB,y
	jsr mulset_a
	lda SINTAB,y
	jsr mulset_b
	ldx #0
.xi_x
	cpx mesh_nx
	beq .xi_z
	lda #0
	sta nlo
	sta e0x
	lda UX,x
	sta nhi
	sta e0xh
	stx vindex
	jsr smul16_a
	ldx vindex
	lda nlo
	sta XC_L,x
	lda nhi
	sta XC_H,x
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_b
	ldx vindex
	lda nlo
	sta XS_L,x
	lda nhi
	sta XS_H,x
	inx
	jmp .xi_x
.xi_z
	ldx #0
.xi_zl
	cpx mesh_nz
	beq .xi_v
	lda #0
	sta nlo
	sta e0x
	lda UZ,x
	sta nhi
	sta e0xh
	stx vindex
	jsr smul16_a
	ldx vindex
	lda nlo
	sta ZC_L,x
	lda nhi
	sta ZC_H,x
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr smul16_b
	ldx vindex
	lda nlo
	sta ZS_L,x
	lda nhi
	sta ZS_H,x
	inx
	jmp .xi_zl
.xi_v
	lda #0
	sta vindex
.xi_vl
	ldy vindex
	+vskip_br .xi_skip
	lda (xid_ptr),y
	tax
	lda (zid_ptr),y
	tay
	lda XC_L,x
	sec
	sbc ZS_L,y
	sta e0x
	lda XC_H,x
	sbc ZS_H,y
	sta e0xh
	lda XS_L,x
	clc
	adc ZC_L,y
	sta e0y
	lda XS_H,x
	adc ZC_H,y
	sta e0yh
	ldx vindex
	clc
	lda org_xl
	adc e0x
	sta CAM_X,x
	lda org_xh
	adc e0xh
	sta CAM_XH,x
	clc
	lda org_zl
	adc e0y
	sta CAM_Z,x
	lda org_zh
	adc e0yh
	sta CAM_ZH,x
	lda #0
	sec
	sbc cam_yl
	sta CAM_Y,x
	lda VY,x
	sbc cam_yh
	sta CAM_YH,x
.xi_skip
	inc vindex
	lda vindex
	cmp mesh_nv
	bne .xi_vl
	lda mesh_vmask
	cmp #$ff
	bne .xi_r
	lda mesh_nv
	sta mesh_nwork
.xi_r
!if PROFILE = 1 {
	ldx #NV_ROT
	jmp prof_add_nv
} else {
	rts
}

; True-project feet (slot 11); limb PROJ = feet + dCAM * trunc(FOCAL/z) >> 8.
; mesh_nv verts. Fills PROJ_* and per-vert outcodes. Caller runs mesh_clip.
ent_far_project
	lda mesh_nv
	sta mesh_nwork
!if PROFILE = 1 {
	ldx #NV_PROJ
	jsr prof_add_nv
}
	lda CAM_Z+11
	sta z_eye
	lda CAM_ZH+11
	sta z_eye_h
	lda CAM_X+11
	sta ylo
	lda CAM_XH+11
	sta yhi
	jsr persp88
	sta ox0l
	ldy #0
	ora #0
	bpl +
	ldy #$ff
+
	sty ox0h
	lda CAM_Y+11
	sta ylo
	lda CAM_YH+11
	sta yhi
	jsr persp88
	sta oy0l
	ldy #0
	ora #0
	bpl +
	ldy #$ff
+
	sty oy0h
	lda #0
	sta ylo
	lda #1
	sta yhi
	jsr persp88
	sta far_scale
	jsr mulset_a			; per-enemy constant → fast-mul set A
	lda #0
	sta vindex
.far_pv
	ldx vindex
	sec
	lda CAM_X,x
	sbc CAM_X+11
	sta nlo
	lda CAM_XH,x
	sbc CAM_XH+11
	sta nhi
	jsr smul16_a			; × far_scale
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	clc
	lda nlo
	adc ox0l
	sta nlo
	lda nhi
	adc ox0h
	sta nhi
	ldx vindex
	lda nlo
	sta PROJ_X,x
	lda nhi
	sta PROJ_XH,x
	sec
	lda CAM_Y,x
	sbc CAM_Y+11
	sta nlo
	lda CAM_YH,x
	sbc CAM_YH+11
	sta nhi
	jsr smul16_a			; × far_scale
	lda nhi
	cmp #$80
	ror nhi
	ror nlo
	clc
	lda nlo
	adc oy0l
	sta nlo
	lda nhi
	adc oy0h
	sta nhi
	ldx vindex
	lda nlo
	sta PROJ_Y,x
	lda nhi
	sta PROJ_YH,x
	inc vindex
	lda vindex
	cmp mesh_nv
	bne .far_pv

	lda #0
	sta vindex
.far_hoist
	jsr vert_hoist
	inc vindex
	lda vindex
	cmp mesh_nv
	bne .far_hoist
	rts

; CAM[] filled, mesh_nv/mesh_ne and edge pointers set. Slot 11 is the feet.
; Far when that depth reaches the type's lodZ; otherwise a full project.
enemy_project
	lda CAM_ZH+11
	bmi .ep_full
	ldx obj_i
	jsr ldy_slot
	cmp enemy_lod_z,y
	bcc .ep_full
	jsr ent_far_project
	jmp .ep_clip
.ep_full
	jsr mesh_project
.ep_clip
!if PROFILE = 1 {
	ldy #PROF_PROJ
	jsr prof_add_bucket
}
	jsr try_enemy_muzzle
	jsr mesh_clip
!if PROFILE = 1 {
	ldy #PROF_CLIP
	jsr prof_add_bucket
}
	rts

; C=1 if CAM[0] origin is in the view wedge: z>=0, |x|<=z+R, |y|<=z+H
enemy_in_view
	lda CAM_ZH
	bmi .eiv_no
	lda CAM_X
	sta rot0
	lda CAM_XH
	sta rot1
	bpl .eiv_xabs
	sec
	lda #0
	sbc rot0
	sta rot0
	lda #0
	sbc rot1
	sta rot1
.eiv_xabs
	lda #ENEMY_CULL_R
	jsr wedge_le_z
	bcc .eiv_rts
	lda CAM_Y
	sta rot0
	lda CAM_YH
	sta rot1
	bpl .eiv_yabs
	sec
	lda #0
	sbc rot0
	sta rot0
	lda #0
	sbc rot1
	sta rot1
.eiv_yabs
	lda #ENEMY_CULL_H
	jmp wedge_le_z
.eiv_no
	clc
.eiv_rts
	rts

; C=1 if |rot0:rot1| <= CAM_Z:CAM_ZH + A (pad on 8.8 high)
wedge_le_z
	sta rot2
	lda CAM_Z
	sta nlo
	clc
	lda CAM_ZH
	adc rot2
	bcs .wlz_yes
	sta nhi
	lda rot1
	cmp nhi
	bcc .wlz_yes
	bne .wlz_no
	lda rot0
	cmp nlo
	bcc .wlz_yes
	beq .wlz_yes
.wlz_no
	clc
	rts
.wlz_yes
	sec
	rts

draw_enemies
	jsr load_view_trig
	ldx #0
.de
	cpx	map_nenemies
	bcs .de_rts
	lda en_state,x
	cmp #EN_GONE
	beq .de_n
	+lda_mx en_room
	cmp room_idx
	beq .de_in
	lda spit_on
	beq .de_n
	cpx spit_owner
	bne .de_n
	lda #0
	sta spit_on
	sta spit_flash
	jmp .de_n
.de_in
	jsr .de_one
.de_n
	inx
	jmp .de
.de_rts
	rts

.de_one
	stx obj_i
	+lda_mx en_x
	sta ent_wx
	+lda_mx en_y
	sta ent_wy
	+lda_mx en_z
	sta ent_wz
	lda cs_b			; re-prime view sets (prev enemy clobbered)
	jsr mulset_a
	lda sn_b
	jsr mulset_b
	ldx #0
	jsr xform_world_vert
	jsr try_bite_splat			; origin in CAM[0], even if off-screen
	jsr enemy_in_view
	bcs .de_vis
	ldx obj_i
	+ldy_mx en_type
	cpy #ENT_CHTHON
	bne .de_nch
	lda #AI_CMD_DRAW		; electrode bolt does not depend on Chthon being on screen
	jsr ai_invoke
	jmp .de_one_rts
.de_nch
	lda spit_on
	beq .de_cull
	cpx spit_owner
	bne .de_cull
	lda #0
	sta spit_on
	sta spit_flash
.de_cull
	jmp .de_one_rts
.de_vis
	ldx obj_i
	+lda_mx en_type
	sta ent_type
	tay
	+lda_mx en_rot
	sta ent_rot
	lda skel_entry_hi,y
	beq .de_batch
	lda #SKEL_CMD_DRAW
	jsr skel_call
	jmp .de_one_rts
.de_batch
	lda skel_base_hi,y
	beq .de_std
	jsr draw_one_batch
	jmp .de_one_rts
.de_std
	lda #NVERTS
	sta mesh_nv
	lda #NEDGES
	sta mesh_ne
	lda #<enemy_edges
	sta edge_ptr
	lda #>enemy_edges
	sta edge_ptr+1
	lda #<ident_col			; enemy verts: no shared XZ columns
	sta col_ptr
	lda #>ident_col
	sta col_ptr+1
	jsr ent_rotate
!if PROFILE = 1 {
	ldy #PROF_ROT
	jsr prof_add_bucket
}
	jsr enemy_project
.de_draw
	lda ent_type
	cmp #ENT_SHAMBLER
	beq .de_bolt
	cmp #ENT_SCRAG
	bne .de_one_rts
.de_bolt
	tay
	lda #AI_CMD_DRAW
	ldx obj_i
	jsr ai_invoke
.de_one_rts
	ldx obj_i
	rts


SKEL_CMD_DRAW = 0
SKEL_CMD_LERP = 1

; Shift-0 custom mesh, one batch, 12..16 slots. Same rotate as the stick.
; Slot 11 is the feet (pinned at export). Falls into the stick LOD tail.
; ent_type set, CAM[0] is the origin.
draw_one_batch
	jsr ent_set_pose
	sec
	lda yaw
	sbc ent_rot
	tay
	lda COSTAB,y
	jsr mulset_a
	lda SINTAB,y
	jsr mulset_b
	lda CAM_X
	sta org_xl
	lda CAM_XH
	sta org_xh
	lda CAM_Y
	sta org_yl
	lda CAM_YH
	sta org_yh
	lda CAM_Z
	sta org_zl
	lda CAM_ZH
	sta org_zh
	ldx ent_type
	clc
	lda skel_base_lo,x
	adc #SKEL_PFX
	sta src_ptr
	lda skel_base_hi,x
	adc #0
	sta src_ptr+1
	ldy #0
	lda (src_ptr),y
	sta mesh_nv
	iny
	lda (src_ptr),y
	sta mesh_ne
	iny
	lda #0
	sta vindex
.dob_lp
	lda (src_ptr),y
	sta gidx
	tya
	pha
	jsr ent_rot_local
	ldx vindex
	clc
	lda org_xl
	adc e0x
	sta CAM_X,x
	lda org_xh
	adc e0xh
	sta CAM_XH,x
	clc
	lda org_zl
	adc e1z
	sta CAM_Z,x
	lda org_zh
	adc e1zh
	sta CAM_ZH,x
	ldy gidx
	lda (gy_ptr),y
	jsr scale_s8_88
	ldx vindex
	clc
	lda org_yl
	adc nlo
	sta CAM_Y,x
	lda org_yh
	adc nhi
	sta CAM_YH,x
	inc vindex
	pla
	tay
	iny
	lda vindex
	cmp mesh_nv
	bcc .dob_lp
	tya
	clc
	adc src_ptr
	sta edge_ptr
	lda src_ptr+1
	adc #0
	sta edge_ptr+1
!if PROFILE = 1 {
	ldy #PROF_ROT
	jsr prof_add_bucket
}
	lda #<ident_col
	sta col_ptr
	lda #>ident_col
	sta col_ptr+1
	lda #$ff
	sta mesh_vmask
	jmp enemy_project

; A = command. ent_type set. Y preserved. jsr the streamed skeleton entry.
skel_call
	pha
	ldx ent_type
	lda skel_entry_hi,x
	beq .sc_pop
	sta .sc_jsr+2
	lda skel_entry_lo,x
	sta .sc_jsr+1
	pla
.sc_jsr
	jsr $ffff
	rts
.sc_pop
	pla
	rts

; Pending melee splat: half-pixel 48+X×4 / 32−Y×2 via .pcs_bias, then jitter ×2.
try_bite_splat
	lda bite_splat_i
	cmp obj_i
	bne .tbs_rts
	lda CAM_XH
	asl
	asl
	ldx #48
	stx rot1
	ldx #96
	stx rot2
	jsr .pcs_bias
	sta rot0
	lda CAM_YH
	asl
	eor #$ff
	clc
	adc #1
	ldx #32
	stx rot1
	ldx #64
	stx rot2
	jsr .pcs_bias
	tay
	lda rot0
	jsr splat_aim_half
	sta rot2
	lda #COL_SPLAT_HIT
	sta splat_col
	ldx #0
	lda rot2
	jsr start_splat
	lda #$ff
	sta bite_splat_i
.tbs_rts
	rts

; If this enemy is on its ranged fire frame (or latched pending), claim sprite-6 muzzle at tip.
; Grunt: weapon (12). Ogre shoot: Wrist L. Depth in rot1 for start_enemy_muzzle.
try_enemy_muzzle
	jsr enemy_muzzle_want
	bcc .temz_rts
	ldx #12
	cpy #ENT_OGRE
	bne .temz_tip
	ldx #GREN_WRIST_L
.temz_tip
	lda CAM_ZH,x
	bmi .temz_rts
	sta rot1
	lda PROJ_X,x
	ldy PROJ_XH,x
	jsr .to_sx
	sta rot2				; tip sx
	lda PROJ_Y,x
	ldy PROJ_YH,x
	jsr .to_sy
	tay
	lda #$ff
	sta emuz_pending
	lda rot2
	jmp start_enemy_muzzle
.temz_rts
	rts

; C=1 if this enemy should show a muzzle this draw.
enemy_muzzle_want
	ldx obj_i
	lda en_state,x
	cmp #EN_ATTACK
	bne .emw_no
	jsr enemy_get_class
	bne .emw_no			; Rottweiler — leap bite, no muzzle
	cpy #ENT_KNIGHT
	beq .emw_no			; knight slash — no muzzle
	cpy #ENT_DEMON
	beq .emw_no			; claw / leap — no muzzle
	cpy #ENT_OGRE
	bne .emw_ff
	lda en_pain_i,x
	beq .emw_no			; swing — no muzzle
.emw_ff
	jsr ldy_slot
	lda emuz_pending
	cmp obj_i
	beq .emw_yes		; cue-fired shot (fire frame $ff still flashes)
	lda enemy_fire_frame,y
	bmi .emw_no			; $ff = none
	cmp en_frame,x
	bne .emw_no
.emw_yes
	sec
	rts
.emw_no
	clc
	rts

; X = enemy index → EN_DYING, frame 0, death cue
kill_enemy
	+lda_mx en_type
	cmp #ENT_SHAMBLER
	bne .ke_die
	lda #0
	sta sham_arc
.ke_die
	lda #EN_DYING
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_timer,x
	sta en_timer_h,x
	jsr pick_death_var
	stx enemy_idx
	lda spit_on
	beq .ke_cue
	cpx spit_owner
	bne .ke_cue
	lda #0
	sta spit_on
	sta spit_flash
.ke_cue
	lda #CUE_DEATH
	jmp enemy_play_cue
