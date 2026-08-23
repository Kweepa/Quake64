; v-cam 8.8, yaw rotate, near+frustum clip, stroke enemies / meshes
!zone cube

!source "enemy_data.asm"

; A = signed editor byte → nlo:nhi = A/8 as 8.8 (ASL×5)
scale_s8_88
	sta nlo
	lda #0
	bit nlo
	bpl +
	lda #$ff
+
	sta nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
	asl nlo
	rol nhi
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

; X = enemy. A preserved. Y = type * PAIN_MAX + en_pain_i (pain or death variant)
!if PAIN_MAX != 4 {
	!error "pain_var_off assumes PAIN_MAX=4"
}
pain_var_off
	sta rot0
	+lda_mx en_type
	asl
	asl
	clc
	adc en_pain_i,x
	tay
	lda rot0
	rts

; X = enemy. A = enemy_class[type]. Y = type. X preserved.
enemy_get_class
	+ldy_mx en_type
	lda enemy_class,y
	rts

; Point gx/gy/gz at the current pose for ent_type / obj_i.
; Clip from en_state + en_frame[obj_i]
ent_set_pose
	jsr ent_set_ptrs
	ldx obj_i
	lda en_state,x
	cmp #EN_DYING
	beq .esp_death
	cmp #EN_DEAD
	beq .esp_death
	cmp #EN_PAIN
	beq .esp_pain
	cmp #EN_ATTACK
	beq .esp_atk
	cmp #EN_ALERT
	beq .esp_alert
	cmp #EN_APPROACH
	beq .esp_run
	cmp #EN_PATROL
	beq .esp_walk
	; idle (and fallback)
	jmp .esp_idle
.esp_idle
	ldx obj_i
	lda en_frame,x
	ldx ent_type
	clc
	adc enemy_stand_start,x
	tay
	jmp .esp_off
.esp_run
	lda en_frame,x
	ldx ent_type
	clc
	adc enemy_run_start,x
	tay
	jmp .esp_off
.esp_walk
	lda en_frame,x
	ldx ent_type
	clc
	adc enemy_walk_start,x
	tay
	jmp .esp_off
.esp_alert
	lda en_frame,x
	ldx ent_type
	clc
	adc enemy_alert_start,x
	tay
	jmp .esp_off
.esp_atk
	lda en_frame,x
	ldx ent_type
	clc
	adc enemy_attack_start,x
	tay
	jmp .esp_off
.esp_pain
	lda en_frame,x
	jsr pain_var_off
	clc
	adc enemy_pain_start,y
	tay
	jmp .esp_off
.esp_death
	lda en_frame,x
	jsr pain_var_off
	clc
	adc enemy_death_start,y
	tay
.esp_off
	clc
	lda gx_ptr
	adc frame13_lo,y
	sta gx_ptr
	lda gx_ptr+1
	adc frame13_hi,y
	sta gx_ptr+1
	clc
	lda gy_ptr
	adc frame13_lo,y
	sta gy_ptr
	lda gy_ptr+1
	adc frame13_hi,y
	sta gy_ptr+1
	clc
	lda gz_ptr
	adc frame13_lo,y
	sta gz_ptr
	lda gz_ptr+1
	adc frame13_hi,y
	sta gz_ptr+1
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
	ldy gidx
	lda (gx_ptr),y
	sta lx_b
	lda (gz_ptr),y
	sta lz_b
	; x' = (lx*cc − lz*ss) >> 2
	lda lx_b
	jsr smul8_88a
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	lda lz_b
	jsr smul8_88b
	sec
	lda e0x
	sbc nlo
	sta e0x
	lda e0xh
	sbc nhi
	sta e0xh
	; z' = (lx*ss + lz*cc) >> 2
	lda lx_b
	jsr smul8_88b
	lda nlo
	sta e1z
	lda nhi
	sta e1zh
	lda lz_b
	jsr smul8_88a
	clc
	lda e1z
	adc nlo
	sta e1z
	lda e1zh
	adc nhi
	sta e1zh
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

; Y = vert index. C=1 if culled by mesh_vmask (skip transform/project).
.vert_skip
	lda mesh_vmask
	cmp #$ff
	beq .vs_ok
	and box_vbit,y
	beq .vs_skip
.vs_ok
	clc
	rts
.vs_skip
	sec
	rts

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
	jsr .vert_skip
	bcc .pgo
	jmp .pnext
.pgo
	lda (col_ptr),y
	sta cur_col
	tax
	lda COL_DONE,x
	beq .col_new
	cmp #2
	bne .col_front
	ldx vindex			; column already known behind
	lda #1
	sta VBEHIND,x
	jmp .pnext
.col_new
	jsr .zbcam
	bcc .col_calc
	ldx cur_col			; behind: flag column + vertex
	lda #2
	sta COL_DONE,x
	ldx vindex
	lda #1
	sta VBEHIND,x
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
	jsr .cam_to_proj
	ldx vindex
	lda nlo
	sta PROJ_Y,x
	lda nhi
	sta PROJ_YH,x
	jsr .vhoist
.pnext
	inc vindex
	lda vindex
	cmp mesh_nv
	beq +
	jmp .pvert
+
	rts

; Per-vertex clip data hoisted out of mesh_clip: behind flag (0 here),
; outcode from 16-bit PROJ, and screen coords when fully inside.
.vhoist
	ldx vindex
	lda #0
	sta VBEHIND,x
	lda PROJ_X,x
	sta ox0l
	lda PROJ_XH,x
	sta ox0h
	lda PROJ_Y,x
	sta oy0l
	lda PROJ_YH,x
	sta oy0h
	ldx #0
	jsr .mkoc
	ldx vindex
	sta VOC,x
	cmp #0
	bne .vh_rts			; VSX/VSY only read on trivial accept
	lda ox0l
	ldy ox0h
	jsr .to_sx
	ldx vindex
	sta VSX,x
	lda oy0l
	ldy oy0h
	jsr .to_sy
	ldx vindex
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
	lda z_eye_h
	sta dhi
	lda #0
	sta inv_k
.fz
	lda dhi
	beq .gotz
	lsr dhi
	ror dlo
	inc inv_k
	jmp .fz
.gotz
	lda dlo
	and #$7f
	tax
	lda invzl,x
	sta inv_l
	lda invzh,x
	sta inv_h
	rts

; nlo:nhi * inv >> (16+k) → nlo:nhi. Full coord (no pre-shift) so 8.8 LSBs survive.
proj_cam_to_proj
.cam_to_proj
	lda inv_l
	sta ylo
	lda inv_h
	sta yhi
	jsr smul16u16h
	ldx inv_k
	beq .csgn
.cls
	lsr nhi
	ror nlo
	dex
	bne .cls
.csgn
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
; Trivial accept/reject runs on per-vertex VOC/VBEHIND/VSX/VSY hoisted
; into mesh_project — no CAM/PROJ copies unless an edge needs real work.
mesh_clip
cube_clip
	lda mesh_ne
	sta mesh_nwork
!if PROFILE = 1 {
	ldx #NV_CLIP
	jsr prof_add_nv
}
	lda #0
	sta vindex
.cel
	lda vindex
	asl
	tay
	lda (edge_ptr),y
	sta ei0
	iny
	lda (edge_ptr),y
	sta ei1
	ldy vindex
	lda (edge_vert_ptr),y
	beq .cgen
	jmp .clip_v
.cgen
	ldy ei0
	lda VBEHIND,y
	beq .b0f
	ldy ei1
	lda VBEHIND,y
	beq .n0
	jmp .reject			; both behind near plane
.n0
	jsr .load_cam
	jsr .near0
	jmp .near_oc
.b0f
	ldy ei1
	lda VBEHIND,y
	beq .bothf
	jsr .load_cam
	jsr .near1
.near_oc
	jsr .projpair
	ldx #0
	jsr .mkoc
	sta oc0
	ldx #1
	jsr .mkoc
	sta oc1
	jsr .csrun
	bcc .clip_out
	jmp .reject
.bothf
	ldy ei0
	lda VOC,y
	sta oc0
	ldy ei1
	lda VOC,y
	sta oc1
	ora oc0
	beq .accept
	lda oc0
	and oc1
	beq .cswk
	jmp .reject
.cswk
	jsr .load_proj
	jsr .csrun
	bcc .clip_out
	jmp .reject
.accept
	ldx vindex
	ldy ei0
	lda VSX,y
	sta CLIP_X0,x
	lda VSY,y
	sta CLIP_Y0,x
	ldy ei1
	lda VSX,y
	sta CLIP_X1,x
	lda VSY,y
	sta CLIP_Y1,x
	lda #1
	sta EDGE_VIS,x
	jmp .next
.clip_out
	ldx vindex
	lda ox0l
	ldy ox0h
	jsr .to_sx
	sta CLIP_X0,x
	lda oy0l
	ldy oy0h
	jsr .to_sy
	sta CLIP_Y0,x
	lda ox1l
	ldy ox1h
	jsr .to_sx
	sta CLIP_X1,x
	lda oy1l
	ldy oy1h
	jsr .to_sy
	sta CLIP_Y1,x
	ldx vindex
	lda #1
	sta EDGE_VIS,x
	jmp .next
.clip_v
	ldy ei0
	lda VBEHIND,y			; vertical edge shares z — one check
	bne .reject
	lda VOC,y
	sta oc0
	ldy ei1
	lda VOC,y
	sta oc1
	ora oc0
	beq .accept2
	lda oc0
	and oc1
	bne .reject
	jsr .load_proj
	jsr .csrun_v
	bcc .clip_out2
	jmp .reject
.accept2
	jmp .accept
.clip_out2
	jmp .clip_out
.reject
	ldx vindex
	lda #0
	sta EDGE_VIS,x
.next
	inc vindex
	lda vindex
	cmp mesh_ne
	beq +
	jmp .cel
+
	rts

; CAM endpoints → e0*/e1* (near-clip path only)
.load_cam
	ldy ei0
	lda CAM_X,y
	sta e0x
	lda CAM_XH,y
	sta e0xh
	lda CAM_Y,y
	sta e0y
	lda CAM_YH,y
	sta e0yh
	lda CAM_Z,y
	sta e0z
	lda CAM_ZH,y
	sta e0zh
	ldy ei1
	lda CAM_X,y
	sta e1x
	lda CAM_XH,y
	sta e1xh
	lda CAM_Y,y
	sta e1y
	lda CAM_YH,y
	sta e1yh
	lda CAM_Z,y
	sta e1z
	lda CAM_ZH,y
	sta e1zh
	rts

; PROJ endpoints → ox/oy (screen-clip path only)
.load_proj
	ldy ei0
	lda PROJ_X,y
	sta ox0l
	lda PROJ_XH,y
	sta ox0h
	lda PROJ_Y,y
	sta oy0l
	lda PROJ_YH,y
	sta oy0h
	ldy ei1
	lda PROJ_X,y
	sta ox1l
	lda PROJ_XH,y
	sta ox1h
	lda PROJ_Y,y
	sta oy1l
	lda PROJ_YH,y
	sta oy1h
	rts

.near0
	jsr .nd01
	lda nlo
	pha
	lda nhi
	pha
	lda dlo
	pha
	lda dhi
	pha
	jsr .nlx0
	pla
	sta dhi
	pla
	sta dlo
	pla
	sta nhi
	pla
	sta nlo
	jsr .nly0
	lda #<ZCLIP
	sta e0z
	lda #>ZCLIP
	sta e0zh
	rts

.near1
	jsr .nd10
	lda nlo
	pha
	lda nhi
	pha
	lda dlo
	pha
	lda dhi
	pha
	jsr .nlx1
	pla
	sta dhi
	pla
	sta dlo
	pla
	sta nhi
	pla
	sta nlo
	jsr .nly1
	lda #<ZCLIP
	sta e1z
	lda #>ZCLIP
	sta e1zh
	rts

.nlx0
	sec
	lda e1x
	sbc e0x
	sta ylo
	lda e1xh
	sbc e0xh
	sta yhi
	jsr .nlrun
	clc
	adc e0x
	sta e0x
	lda rot1
	adc e0xh
	sta e0xh
	rts

.nly0
	sec
	lda e1y
	sbc e0y
	sta ylo
	lda e1yh
	sbc e0yh
	sta yhi
	jsr .nlrun
	clc
	adc e0y
	sta e0y
	lda rot1
	adc e0yh
	sta e0yh
	rts

.nlx1
	sec
	lda e0x
	sbc e1x
	sta ylo
	lda e0xh
	sbc e1xh
	sta yhi
	jsr .nlrun
	clc
	adc e1x
	sta e1x
	lda rot1
	adc e1xh
	sta e1xh
	rts

.nly1
	sec
	lda e0y
	sbc e1y
	sta ylo
	lda e0yh
	sbc e1yh
	sta yhi
	jsr .nlrun
	clc
	adc e1y
	sta e1y
	lda rot1
	adc e1yh
	sta e1yh
	rts

.nd01
	sec
	lda e1z
	sbc e0z
	sta dlo
	lda e1zh
	sbc e0zh
	sta dhi
	sec
	lda #<ZCLIP
	sbc e0z
	sta nlo
	lda #>ZCLIP
	sbc e0zh
	sta nhi
	rts

.nd10
	sec
	lda e0z
	sbc e1z
	sta dlo
	lda e0zh
	sbc e1zh
	sta dhi
	sec
	lda #<ZCLIP
	sbc e1z
	sta nlo
	lda #>ZCLIP
	sbc e1zh
	sta nhi
	rts

.nlrun
	jsr scale_nd
	lda dlo
	ora dhi
	bne +
	lda #0
	sta rot0
	sta rot1
	rts
+
	jmp lerp16			; rot0:rot1 = (ylo:yhi * n) / d; A=rot0

.projpair
	lda e0z
	sta z_eye
	lda e0zh
	sta z_eye_h
	jsr .invz
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	jsr .cam_to_proj
	lda nlo
	sta ox0l
	lda nhi
	sta ox0h
	lda e0y
	sta nlo
	lda e0yh
	sta nhi
	jsr .cam_to_proj
	lda nlo
	sta oy0l
	lda nhi
	sta oy0h
	lda e1z
	sta z_eye
	lda e1zh
	sta z_eye_h
	jsr .invz
	lda e1x
	sta nlo
	lda e1xh
	sta nhi
	jsr .cam_to_proj
	lda nlo
	sta ox1l
	lda nhi
	sta ox1h
	lda e1y
	sta nlo
	lda e1yh
	sta nhi
	jsr .cam_to_proj
	lda nlo
	sta oy1l
	lda nhi
	sta oy1h
	rts

; Vertical edge: L/R trivial reject (same X); top/bottom set Y only.
; oc0/oc1 preloaded; only the moved endpoint's outcode is recomputed.
.csrun_v
	lda #16
	sta cs_n
.cvlp
	lda oc0
	ora oc1
	bne .cvneed
	clc
	rts
.cvneed
	lda oc0
	and oc1
	beq .cvwork
	sec
	rts
.cvwork
	dec cs_n
	bne +
	sec
	rts
+
	lda oc0
	bne .cvp0
	lda oc1
	ldx #1
	bne .cvbit
.cvp0
	ldx #0
.cvbit
	lsr
	bcs .cvrej
	lsr
	bcs .cvrej
	lsr
	bcs .cvtop
	lda #$3f
	ldy #0
	jmp .cvsety
.cvtop
	lda #$c0
	ldy #$ff
.cvsety
	cpx #0
	bne .cv1
	sta oy0l
	sty oy0h
	jsr .mkoc
	sta oc0
	jmp .cvlp
.cv1
	sta oy1l
	sty oy1h
	jsr .mkoc
	sta oc1
	jmp .cvlp
.cvrej
	sec
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
	beq .cswork
	sec
	rts
.cswork
	dec cs_n
	bne +
	sec
	rts
+
	lda oc0
	bne .csp0
	lda oc1
	ldx #1
	bne .csbit
.csp0
	ldx #0
.csbit
	lsr
	bcs .csleft
	lsr
	bcs .csright
	lsr
	bcs .cstop
	jmp .csbot

.csleft
	lda #$a0
	sta rot0
	lda #$ff
	sta rot2
	jsr .csx
	jmp .csupd
.csright
	lda #$5f
	sta rot0
	lda #0
	sta rot2
	jsr .csx
	jmp .csupd
.cstop
	lda #$c0
	sta rot0
	lda #$ff
	sta rot2
	jsr .csy
	jmp .csupd
.csbot
	lda #$3f
	sta rot0
	lda #0
	sta rot2
	jsr .csy
.csupd
	jsr .mkoc			; X = moved endpoint (preserved by .csx/.csy)
	cpx #0
	bne .csu1
	sta oc0
	jmp .cslp
.csu1
	sta oc1
	jmp .cslp

; rot0:rot2 = 16-bit plane, X = 0 (p0) or 1 (p1)
; lerp16 clobbers rot0/1/2 — save plane and endpoint index
.csx
	txa
	pha
	lda rot0
	pha
	lda rot2
	pha
	jsr .ylerp
	pla
	sta rot2
	pla
	sta rot0
	pla
	tax
	cpx #0
	bne .csx1
	lda rot0
	sta ox0l
	lda rot2
	sta ox0h
	rts
.csx1
	lda rot0
	sta ox1l
	lda rot2
	sta ox1h
	rts

.csy
	txa
	pha
	lda rot0
	pha
	lda rot2
	pha
	jsr .xlerp
	pla
	sta rot2
	pla
	sta rot0
	pla
	tax
	cpx #0
	bne .csy1
	lda rot0
	sta oy0l
	lda rot2
	sta oy0h
	rts
.csy1
	lda rot0
	sta oy1l
	lda rot2
	sta oy1h
	rts

.ylerp
	cpx #0
	bne .yl1
	sec
	lda ox1l
	sbc ox0l
	sta dlo
	lda ox1h
	sbc ox0h
	sta dhi
	sec
	lda rot0
	sbc ox0l
	sta nlo
	lda rot2
	sbc ox0h
	sta nhi
	sec
	lda oy1l
	sbc oy0l
	sta ylo
	lda oy1h
	sbc oy0h
	sta yhi
	jsr .nlrun
	jmp .addoy0
.yl1
	sec
	lda ox0l
	sbc ox1l
	sta dlo
	lda ox0h
	sbc ox1h
	sta dhi
	sec
	lda rot0
	sbc ox1l
	sta nlo
	lda rot2
	sbc ox1h
	sta nhi
	sec
	lda oy0l
	sbc oy1l
	sta ylo
	lda oy0h
	sbc oy1h
	sta yhi
	jsr .nlrun
	jmp .addoy1

.xlerp
	cpx #0
	bne .xl1
	sec
	lda oy1l
	sbc oy0l
	sta dlo
	lda oy1h
	sbc oy0h
	sta dhi
	sec
	lda rot0
	sbc oy0l
	sta nlo
	lda rot2
	sbc oy0h
	sta nhi
	sec
	lda ox1l
	sbc ox0l
	sta ylo
	lda ox1h
	sbc ox0h
	sta yhi
	jsr .nlrun
	jmp .addox0
.xl1
	sec
	lda oy0l
	sbc oy1l
	sta dlo
	lda oy0h
	sbc oy1h
	sta dhi
	sec
	lda rot0
	sbc oy1l
	sta nlo
	lda rot2
	sbc oy1h
	sta nhi
	sec
	lda ox0l
	sbc ox1l
	sta ylo
	lda ox0h
	sbc ox1h
	sta yhi
	jsr .nlrun
	jmp .addox1

.addoy0
	clc
	lda oy0l
	adc rot0
	sta oy0l
	lda oy0h
	adc rot1
	sta oy0h
	rts
.addoy1
	clc
	lda oy1l
	adc rot0
	sta oy1l
	lda oy1h
	adc rot1
	sta oy1h
	rts
.addox0
	clc
	lda ox0l
	adc rot0
	sta ox0l
	lda ox0h
	adc rot1
	sta ox0h
	rts
.addox1
	clc
	lda ox1l
	adc rot0
	sta ox1l
	lda ox1h
	adc rot1
	sta ox1h
	rts

; X=0 p0, X=1 p1. e0x/e0y = ox, e1x/e1y = oy
.mkoc
	cpx #1
	beq .m1
	lda ox0l
	sta e0x
	lda ox0h
	sta e0y
	lda oy0l
	sta e1x
	lda oy0h
	sta e1y
	jmp .md
.m1
	lda ox1l
	sta e0x
	lda ox1h
	sta e0y
	lda oy1l
	sta e1x
	lda oy1h
	sta e1y
.md
	lda #0
	sta oc_tmp
	lda e0y
	cmp #$ff
	bne .lhi
	lda e0x
	cmp #$a0
	bcc .left
	jmp .nl
.lhi
	bmi .left
	jmp .nl
.left
	lda #OC_LEFT
	sta oc_tmp
.nl
	lda e0y
	bne .rhi
	lda e0x
	cmp #$60
	bcs .right
	jmp .nr
.rhi
	bmi .nr
.right
	lda oc_tmp
	ora #OC_RIGHT
	sta oc_tmp
.nr
	lda e1y
	cmp #$ff
	bne .thi
	lda e1x
	cmp #$c0
	bcc .top
	jmp .nt
.thi
	bmi .top
	jmp .nt
.top
	lda oc_tmp
	ora #OC_TOP
	sta oc_tmp
.nt
	lda e1y
	bne .bhi
	lda e1x
	cmp #$40
	bcs .bot
	jmp .nb
.bhi
	bmi .nb
.bot
	lda oc_tmp
	ora #OC_BOT
	sta oc_tmp
.nb
	lda oc_tmp
	rts

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

; A=oy lo Y=oy hi → screen y 0..127 (Y-down: screen = 64 - oy)
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
	adc #64
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

mesh_draw
cube_draw
	lda #0
	sta vindex
.del
	ldx vindex
	lda EDGE_VIS,x
	beq .skip
	lda CLIP_X0,x
	sta x0
	lda CLIP_Y0,x
	sta y0
	lda CLIP_X1,x
	sta x1
	lda CLIP_Y1,x
	sta y1
	jsr draw_line
.skip
	inc vindex
	lda vindex
	cmp mesh_ne
	beq +
	jmp .del
+
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
	clc
	adc #SCREEN_CX
	bpl .pcs_xp
	lda #0
	beq .pcs_xs
.pcs_xp
	cmp #192
	bcc .pcs_xs
	lda #191
.pcs_xs
	sta rot0
	lda CAM_Y
	sta ylo
	lda CAM_YH
	sta yhi
	jsr persp88
	eor #$ff
	clc
	adc #1
	clc
	adc #64
	tay
	bpl .pcs_yp
	ldy #0
	beq .pcs_ok
.pcs_yp
	cpy #128
	bcc .pcs_ok
	ldy #127
.pcs_ok
	lda rot0
	sec
	rts
.pcs_no
	clc
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
	jsr .vert_skip
	bcs .xm_skip
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

; Local UX/UZ about box+ITEM_BIAS, then R_(yaw+ent_rot). Caller: load_view_trig.
; Quad/pent/ring pass item_spin in ent_rot; other pickups pass 0.
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
	jsr .vert_skip
	bcs .xi_skip
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

; True-project feet (vert 11); limb PROJ = feet + dCAM * trunc(FOCAL/z) >> 8
ent_far_project
	lda #NVERTS
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
	cmp #NVERTS
	bne .far_pv

	lda #0
	sta vindex
.far_ed
	lda vindex
	asl
	tay
	lda (edge_ptr),y
	tay
	lda PROJ_X,y
	sta ox0l
	lda PROJ_XH,y
	sta ox0h
	lda PROJ_Y,y
	sta oy0l
	lda PROJ_YH,y
	sta oy0h
	lda vindex
	asl
	tay
	iny
	lda (edge_ptr),y
	tay
	lda PROJ_X,y
	sta ox1l
	lda PROJ_XH,y
	sta ox1h
	lda PROJ_Y,y
	sta oy1l
	lda PROJ_YH,y
	sta oy1h
	ldx vindex
	lda ox0l
	ldy ox0h
	jsr .to_sx
	sta CLIP_X0,x
	lda oy0l
	ldy oy0h
	jsr .to_sy
	sta CLIP_Y0,x
	lda ox1l
	ldy ox1h
	jsr .to_sx
	sta CLIP_X1,x
	lda oy1l
	ldy oy1h
	jsr .to_sy
	sta CLIP_Y1,x
	ldx vindex
	lda #1
	sta EDGE_VIS,x
	inc vindex
	lda vindex
	cmp mesh_ne
	beq +
	jmp .far_ed
+
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
	bne .de_n
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
	jsr enemy_in_view
	bcc .de_one_rts
	jsr try_bite_splat			; CAM[0] still feet origin
	ldx obj_i
	+lda_mx en_type
	sta ent_type
	+lda_mx en_rot
	sta ent_rot
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
	lda #<ident_col			; enemy verts: no shared XZ columns
	sta col_ptr
	lda #>ident_col
	sta col_ptr+1
	jsr ent_rotate
!if PROFILE = 1 {
	ldy #PROF_ROT
	jsr prof_add_bucket
}
	lda CAM_ZH+11
	bmi .de_full
	cmp #ENEMY_LOD_Z
	bcc .de_full
	jsr ent_far_project
!if PROFILE = 1 {
	ldy #PROF_PROJ
	jsr prof_add_bucket
}
	jmp .de_draw
.de_full
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
.de_draw
	jsr try_enemy_muzzle
	jsr mesh_draw
!if PROFILE = 1 {
	ldy #PROF_DRAW
	jsr prof_add_bucket
}
.de_one_rts
	ldx obj_i
	rts

; Pending dog bite splat: CAM[0] = feet origin; +3 Y, jitter, start_splat.
try_bite_splat
	lda bite_splat_i
	cmp obj_i
	bne .tbs_rts
	lda CAM_Y
	pha
	lda CAM_YH
	pha
	clc
	adc #3
	sta CAM_YH
	jsr project_cam0_screen
	bcc .tbs_rest
	ldx CAM_ZH
	stx rot0
	jsr splat_aim_jitter
	sta rot2
	lda #COL_SPLAT_HIT
	sta splat_col
	ldx rot0
	lda rot2
	jsr start_splat
.tbs_rest
	pla
	sta CAM_YH
	pla
	sta CAM_Y
	lda #$ff
	sta bite_splat_i
.tbs_rts
	rts

; If this enemy is on its ranged fire frame (or latched pending), claim sprite-6 muzzle at tip.
try_enemy_muzzle
	jsr enemy_muzzle_want
	bcc .temz_rts
	lda CAM_ZH+12
	bmi .temz_rts
	lda PROJ_X+12
	ldy PROJ_XH+12
	jsr .to_sx
	sta rot2				; tip sx
	lda PROJ_Y+12
	ldy PROJ_YH+12
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
	lda enemy_fire_frame,y
	bmi .emw_no			; $ff = none
	lda emuz_pending
	cmp obj_i
	beq .emw_yes
	lda enemy_fire_frame,y
	cmp en_frame,x
	bne .emw_no
.emw_yes
	sec
	rts
.emw_no
	clc
	rts

; X = enemy index → EN_DYING, frame 0, death SFX
kill_enemy
	lda #EN_DYING
	sta en_state,x
	lda #0
	sta en_frame,x
	sta en_timer,x
	sta en_timer_h,x
	jsr pick_death_var
	jsr enemy_get_class
	bne .ke_dog
	lda #SOUND_DEATHSCREAM1
	jmp play_sound
.ke_dog
	lda #SOUND_DOGDEATH
	jmp play_sound

; X = enemy finishing death → EN_GONE + optional drop (preserves X)
finish_enemy_death
	stx obj_i
	lda #EN_GONE
	sta en_state,x
	+lda_mx en_type
	tay
	lda enemy_drop_type,y
	cmp #$ff
	bne .fed_drop
	rts
.fed_drop
	sta rot2			; BP_* type
	ldx #0
.fed_slot
	cpx	map_nenemies
	bcs .fed_rts
	lda drop_taken,x
	beq .fed_n
	; free slot (taken=1 inactive)
	ldy obj_i
	+lda_my en_x
	sta drop_x,x
	+lda_my en_y
	sta drop_y,x
	+lda_my en_z
	sta drop_z,x
	+lda_my en_room
	sta drop_room,x
	lda rot2
	sta drop_type,x
	lda #0
	sta drop_taken,x
	jmp .fed_rts
.fed_n
	inx
	bne .fed_slot
.fed_rts
	ldx obj_i
	rts
