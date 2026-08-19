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

; gidx = anim_frame * 13 + vindex → Y; also sets for (gx_ptr)
grunt_gindex
	lda anim_frame
	asl
	asl
	asl				; *8
	sta gidx
	lda anim_frame
	asl
	asl				; *4
	clc
	adc gidx			; *12
	adc anim_frame			; *13
	clc
	adc vindex
	sta gidx
	tay
	rts

; Load type pointers for ent_type
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

cube_rotate
	; demo path unused — ent_rotate draws map enemies
	rts

; Rotate one enemy instance at ent_wx/wy/wz, ent_rot, ent_type
; Caller already jsr load_view_trig
; Facing: odd octant uses 45° tables; (rot>>1)&3 picks N/E/S/W
; Editor yaw: x' = x c + z s, z' = -x s + z c  (local +Z → N/E/S/W)
ent_rotate
	jsr ent_set_ptrs
	lda ent_rot
	lsr
	bcc .face_even
	ldx ent_type
	lda enemy_gx45_lo,x
	sta gx_ptr
	lda enemy_gx45_hi,x
	sta gx_ptr+1
	lda enemy_gz45_lo,x
	sta gz_ptr
	lda enemy_gz45_hi,x
	sta gz_ptr+1
.face_even
	lda ent_rot
	lsr
	and #3
	tax
	lda .face_lo,x
	sta .facejsr+1
	lda .face_hi,x
	sta .facejsr+2
	lda #0
	sta vindex
.rvert
	jsr grunt_gindex
.facejsr
	jsr .face_n
	; now e0x/xh = lx', e1z/zh = lz' — add world + cam
	clc
	lda e0xh
	adc ent_wx
	sta e0xh
	sec
	lda e0x
	sbc cam_xl
	sta nlo
	lda e0xh
	sbc cam_xh
	sta nhi
	ldx vindex
	lda nlo
	sta CAM_X,x
	lda nhi
	sta CAM_XH,x
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	clc
	lda e1zh
	adc ent_wz
	sta e1zh
	sec
	lda e1z
	sbc cam_zl
	sta e1z
	lda e1zh
	sbc cam_zh
	sta e1zh
	lda e0x
	sta nlo
	lda e0xh
	sta nhi

	; x1 = dx*cs - dz*sn  (view yaw)
	ldy cs_b
	jsr smul16_7
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	lda e1z
	sta nlo
	lda e1zh
	sta nhi
	ldy sn_b
	jsr smul16_7
	sec
	lda e0x
	sbc nlo
	sta e0x
	lda e0xh
	sbc nhi
	sta e0xh

	ldx vindex
	lda CAM_X,x
	sta nlo
	lda CAM_XH,x
	sta nhi
	ldy sn_b
	jsr smul16_7
	lda nlo
	sta e0y
	lda nhi
	sta e0yh
	lda e1z
	sta nlo
	lda e1zh
	sta nhi
	ldy cs_b
	jsr smul16_7
	clc
	lda e0y
	adc nlo
	sta e0y
	lda e0yh
	adc nhi
	sta e0yh

	ldy gidx
	lda (gy_ptr),y
	jsr scale_s8_88
	clc
	lda nhi
	adc ent_wy
	sta nhi
	sec
	lda nlo
	sbc cam_yl
	sta nlo
	lda nhi
	sbc cam_yh
	sta nhi
	ldx vindex
	lda nlo
	sta CAM_Y,x
	lda nhi
	sta CAM_YH,x
	lda e0y
	sta CAM_Z,x
	lda e0yh
	sta CAM_ZH,x
	lda e0x
	sta CAM_X,x
	lda e0xh
	sta CAM_XH,x

	inc vindex
	lda vindex
	cmp #NVERTS
	beq +
	jmp .rvert
+
	rts

; Y = gidx. Local signed XZ → 8.8 in e0x / e1z. scale_s8_88 preserves Y.
.face_n					; (x, z)  editor +Z
	lda (gx_ptr),y
	jsr scale_s8_88
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	lda (gz_ptr),y
	jsr scale_s8_88
	lda nlo
	sta e1z
	lda nhi
	sta e1zh
	rts

.face_e					; (z, -x)  editor +X
	lda (gz_ptr),y
	jsr scale_s8_88
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	lda (gx_ptr),y
	eor #$ff
	clc
	adc #1
	jsr scale_s8_88
	lda nlo
	sta e1z
	lda nhi
	sta e1zh
	rts

.face_s					; (-x, -z)  editor -Z
	lda (gx_ptr),y
	eor #$ff
	clc
	adc #1
	jsr scale_s8_88
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	lda (gz_ptr),y
	eor #$ff
	clc
	adc #1
	jsr scale_s8_88
	lda nlo
	sta e1z
	lda nhi
	sta e1zh
	rts

.face_w					; (-z, x)  editor -X
	lda (gz_ptr),y
	eor #$ff
	clc
	adc #1
	jsr scale_s8_88
	lda nlo
	sta e0x
	lda nhi
	sta e0xh
	lda (gx_ptr),y
	jsr scale_s8_88
	lda nlo
	sta e1z
	lda nhi
	sta e1zh
	rts

.face_lo	!byte <.face_n, <.face_e, <.face_s, <.face_w
.face_hi	!byte >.face_n, >.face_e, >.face_s, >.face_w

; 8.8 view → unclamped 16-bit screen, then CS. persp88 is far enemies only.
mesh_project
cube_project
	lda #0
	sta vindex
.pvert
	ldx vindex
	lda CAM_Z,x
	sta PROJ_Z,x
	lda CAM_ZH,x
	sta PROJ_ZH,x
	jsr .zbcam
	bcc .pfront
	jsr .offxy
	jmp .pnext
.pfront
	jsr .invz
	ldx vindex
	lda CAM_X,x
	sta nlo
	lda CAM_XH,x
	sta nhi
	jsr .cam_to_proj
	ldx vindex
	lda nlo
	sta PROJ_X,x
	lda nhi
	sta PROJ_XH,x
	ldx vindex
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
.pnext
	inc vindex
	lda vindex
	cmp mesh_nv
	beq +
	jmp .pvert
+
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

.offxy
	ldx vindex
	lda CAM_XH,x
	bmi .offn
	lda #$90
	sta PROJ_X,x
	lda #$01
	sta PROJ_XH,x
	jmp .offy
.offn
	lda #$70
	sta PROJ_X,x
	lda #$fe
	sta PROJ_XH,x
.offy
	lda CAM_YH,x
	bmi .offyn
	lda #$90
	sta PROJ_Y,x
	lda #$01
	sta PROJ_YH,x
	rts
.offyn
	lda #$70
	sta PROJ_Y,x
	lda #$fe
	sta PROJ_YH,x
	rts

; inv = (FOCAL<<16) / (z>>k), k = unsigned 8-bit fit of z_eye (always ≥128 here).
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
	bne .idiv
	lda #$ff
	sta inv_l
	sta inv_h
	rts
.idiv
	lda #0
	sta rot0
	sta rot1
	lda #FOCAL
	sta rot2
	jsr div24u8
	lda rot0
	sta inv_l
	lda rot1
	sta inv_h
	rts

; nlo:nhi * inv >> (16+k) → nlo:nhi. Full coord (no pre-shift) so 8.8 LSBs survive.
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

; Near-plane interpolate, then 16-bit screen Cohen-Sutherland
mesh_clip
cube_clip
	lda #0
	sta vindex
.cel
	lda vindex
	asl
	tay
	lda (edge_ptr),y
	tay
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
	lda PROJ_X,y
	sta ox1l
	lda PROJ_XH,y
	sta ox1h
	lda PROJ_Y,y
	sta oy1l
	lda PROJ_YH,y
	sta oy1h

	ldy vindex
	lda (edge_vert_ptr),y
	bne .clip_v
	jsr .zb0
	bcs .z0b
	jsr .zb1
	bcs .z1b
	jmp .frustum
.z0b
	jsr .zb1
	bcs .reject
	jsr .near0
	jsr .projpair
	jmp .frustum
.z1b
	jsr .near1
	jsr .projpair
.frustum
	jsr .csclip
	bcs .reject
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
	jsr .zb0
	bcs .reject
	jsr .csclip_v
	bcs .reject
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

.zb0
	lda e0zh
	bmi .zby2
	cmp #>ZCLIP
	bcc .zby2
	bne .zbn2
	lda e0z
	cmp #<ZCLIP
	bcc .zby2
.zbn2
	clc
	rts
.zby2
	sec
	rts

.zb1
	lda e1zh
	bmi .zby2
	cmp #>ZCLIP
	bcc .zby2
	bne .zbn2
	lda e1z
	cmp #<ZCLIP
	bcc .zby2
	clc
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

; Vertical edge: L/R trivial reject (same X); top/bottom set Y only
.csclip_v
	lda #16
	sta cs_n
.cvlp
	ldx #0
	jsr .mkoc
	sta oc0
	ldx #1
	jsr .mkoc
	sta oc1
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
	jmp .cvlp
.cv1
	sta oy1l
	sty oy1h
	jmp .cvlp
.cvrej
	sec
	rts

; C=0 accept (ox/oy inside), C=1 reject
.csclip
	lda #16
	sta cs_n
.cslp
	ldx #0
	jsr .mkoc
	sta oc0
	ldx #1
	jsr .mkoc
	sta oc1
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
	jmp .cslp
.csright
	lda #$5f
	sta rot0
	lda #0
	sta rot2
	jsr .csx
	jmp .cslp
.cstop
	lda #$c0
	sta rot0
	lda #$ff
	sta rot2
	jsr .csy
	jmp .cslp
.csbot
	lda #$3f
	sta rot0
	lda #0
	sta rot2
	jsr .csy
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
	bcc +
.sxh
	lda #191
	rts
.sx0
	lda #0
+
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
	bcc +
.syh
	lda #127
	rts
.sy0
	lda #0
+
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

	; z' = dx*sn + dz*cs
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	ldy sn_b
	jsr smul16_7
	lda nlo
	sta rot0
	lda nhi
	sta rot1
	lda e1z
	sta nlo
	lda e1zh
	sta nhi
	ldy cs_b
	jsr smul16_7
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
	ldy cs_b
	jsr smul16_7
	lda nlo
	sta rot0
	lda nhi
	sta rot1
	lda e1z
	sta nlo
	lda e1zh
	sta nhi
	ldy sn_b
	jsr smul16_7
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
	ldy cs_b
	jsr smul16_7
	ldx vindex
	lda nlo
	sta XC_L,x
	lda nhi
	sta XC_H,x
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	ldy sn_b
	jsr smul16_7
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
	ldy cs_b
	jsr smul16_7
	ldx vindex
	lda nlo
	sta ZC_L,x
	lda nhi
	sta ZC_H,x
	lda e0x
	sta nlo
	lda e0xh
	sta nhi
	ldy sn_b
	jsr smul16_7
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
	inc vindex
	lda vindex
	cmp mesh_nv
	bne .xm_vl
	rts

; True-project feet (vert 11); limb PROJ = feet + dCAM * trunc(FOCAL/z) >> 8
ent_far_project
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
	ldy far_scale
	jsr smul16_7
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
	ldy far_scale
	jsr smul16_7
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
	cpx #MAP_NENEMIES
	bcs .de_rts
	lda en_room,x
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
	lda en_x,x
	sta ent_wx
	lda en_y,x
	sta ent_wy
	lda en_z,x
	sta ent_wz
	ldx #0
	jsr xform_world_vert
	jsr enemy_in_view
	bcc .de_one_rts
	ldx obj_i
	lda en_type,x
	sta ent_type
	lda en_rot,x
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
	jsr ent_rotate
	ldy #PROF_ROT
	jsr prof_add_bucket
	ldx ent_type
	lda CAM_ZH+11
	bmi .de_full
	cmp enemy_far_z,x
	bcc .de_full
	jsr ent_far_project
	ldy #PROF_PROJ
	jsr prof_add_bucket
	jmp .de_draw
.de_full
	jsr mesh_project
	ldy #PROF_PROJ
	jsr prof_add_bucket
	jsr mesh_clip
	ldy #PROF_CLIP
	jsr prof_add_bucket
.de_draw
	jsr mesh_draw
	ldy #PROF_DRAW
	jsr prof_add_bucket
.de_one_rts
	ldx obj_i
	rts
