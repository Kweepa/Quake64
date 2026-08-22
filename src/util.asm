; 3D line-vs-AABB: hit solid boxes / room cutouts. $01=$34 (lerpdv).
!zone util

; Exclusive max of box_* → ln_mx/my/mz
line_box_max
	clc
	lda box_x
	adc box_sx
	sta ln_mx
	clc
	lda box_y
	adc box_sy
	sta ln_my
	clc
	lda box_z
	adc box_sz
	sta ln_mz
	rts

; X = rc_* index. Copy collider into box_*.
load_box_rc
	lda rc_x,x
	sta box_x
	lda rc_y,x
	sta box_y
	lda rc_z,x
	sta box_z
	lda rc_sx,x
	sta box_sx
	lda rc_sy,x
	sta box_sy
	lda rc_sz,x
	sta box_sz
	rts

; A = room index → A/proc_tmp5 = A*3 (rc_* group base). Does not touch X.
room_mul3
	sta proc_tmp5
	asl
	clc
	adc proc_tmp5
	sta proc_tmp5
	rts

; Y = room. Outer AABB → box_*.
load_box_room
	lda room_x,y
	sta box_x
	lda room_y,y
	sta box_y
	lda room_z,y
	sta box_z
	lda room_sx,y
	sta box_sx
	lda room_sy,y
	sta box_sy
	lda room_sz,y
	sta box_sz
	rts

; X = rb_* index. Copy cutout solid into box_*.
load_box_rb
	lda rb_x,x
	sta box_x
	lda rb_y,x
	sta box_y
	lda rb_z,x
	sta box_z
	lda rb_sx,x
	sta box_sx
	lda rb_sy,x
	sta box_sy
	lda rb_sz,x
	sta box_sz
	rts

; Line AABB vs box_*. C=1 overlap.
line_aabb_overlap
	jsr line_box_max
	ldx #0
	jsr .lao_axis
	bcc .lao_no
	ldx #1
	jsr .lao_axis
	bcc .lao_no
	ldx #2
	jmp .lao_axis

.lao_axis
	lda ln_ax,x
	cmp ln_bx,x
	bcc .lao_a
	lda ln_bx,x
	sta rot0				; min
	lda ln_ax,x
	sta rot1				; max
	jmp .lao_chk
.lao_a
	sta rot0
	lda ln_bx,x
	sta rot1
.lao_chk
	lda rot1
	cmp box_x,x
	bcc .lao_no
	lda rot0
	cmp ln_mx,x
	bcs .lao_no
	sec
	rts
.lao_no
	clc
	rts

; Y = 0 (A) or 3 (B). Outcode in A. Uses ln_mx/my/mz.
line_outcode
	lda #0
	sta rot2
	lda ln_ax,y
	cmp box_x
	bcs .loc_px
	lda #1
	sta rot2
.loc_px
	lda ln_ax,y
	cmp ln_mx
	bcc .loc_y
	lda rot2
	ora #2
	sta rot2
.loc_y
	lda ln_ay,y
	cmp box_y
	bcs .loc_py
	lda rot2
	ora #4
	sta rot2
.loc_py
	lda ln_ay,y
	cmp ln_my
	bcc .loc_z
	lda rot2
	ora #8
	sta rot2
.loc_z
	lda ln_az,y
	cmp box_z
	bcs .loc_pz
	lda rot2
	ora #$10
	sta rot2
.loc_pz
	lda ln_az,y
	cmp ln_mz
	bcc .loc_done
	lda rot2
	ora #$20
	sta rot2
.loc_done
	lda rot2
	rts

; t Q7 = (plane − A) * 127 / (B − A). Axis X in ln_face (0..2). Plane in rot0.
; C=1 t in ln_best (clobbers). Parallel → C=0.
line_t_plane
	ldx ln_face
	lda ln_bx,x
	sec
	sbc ln_ax,x
	sta div_c
	beq .ltp_no
	lda rot0
	sec
	sbc ln_ax,x
	ldy #127
	jsr lerpdv
	sta ln_best
	sec
	rts
.ltp_no
	clc
	rts

; Hit other-axis in face rect? Axis ln_face, t in rot1, plane in rot0.
; C=1 inside. Hit in e0x/e0y/e0z then col_x/y/z.
line_face_hit
	ldx #0
.lfh_lp
	cpx ln_face
	beq .lfh_plane
	lda ln_bx,x
	sec
	sbc ln_ax,x
	tay
	stx ln_t0				; smul7 clobbers X
	lda rot1
	jsr smul7
	ldx ln_t0
	clc
	adc ln_ax,x
	sta e0x,x
	cmp box_x,x
	bcc .lfh_no
	cmp ln_mx,x
	bcs .lfh_no
	jmp .lfh_n
.lfh_plane
	lda rot0
	sta e0x,x
.lfh_n
	inx
	cpx #3
	bne .lfh_lp
	jsr line_hit_to_col
	sec
	rts
.lfh_no
	clc
	rts

line_hit_to_col
	lda e0x
	sta col_x
	lda e0y
	sta col_y
	lda e0z
	sta col_z
	rts

; Segment vs solid box_*. C=1 hit; nearest t in ln_best, xyz in col_*.
line_hit_box
	jsr line_aabb_overlap
	bcc .lhb_no
	ldy #0
	jsr line_outcode
	sta ln_oc0
	ldy #3
	jsr line_outcode
	sta ln_oc1
	and ln_oc0
	bne .lhb_no			; same side
	lda #$ff
	sta proc_tmp0			; best t (none)
	lda #1
	sta ln_face
.lhb_faces
	lda ln_oc0
	eor ln_oc1
	and ln_face
	beq .lhb_nf
	jsr .lhb_try
.lhb_nf
	asl ln_face
	lda ln_face
	cmp #$40
	bne .lhb_faces
	lda proc_tmp0
	cmp #$ff
	beq .lhb_no
	sta ln_best
	sec
	rts
.lhb_no
	clc
	rts

; Try face bit ln_face. Plane → rot0, axis → ln_face 0..2 temporarily.
.lhb_try
	lda ln_face
	sta rot2				; save bit
	ldx #0
	cmp #4
	bcc .lhb_ax
	inx
	cmp #16
	bcc .lhb_ax
	inx
.lhb_ax
	stx ln_face				; 0..2
	lda rot2
	and #$2a				; +X/+Y/+Z bits
	beq .lhb_min
	lda ln_mx,x
	jmp .lhb_pl
.lhb_min
	lda box_x,x
.lhb_pl
	sta rot0
	jsr line_t_plane
	bcc .lhb_tr
	lda ln_best
	beq .lhb_tr				; t=0 skip
	bmi .lhb_tr
	cmp proc_tmp0
	bcs .lhb_tr				; not strictly nearer (unsigned; $ff = none)
	sta rot1
	jsr line_face_hit
	bcc .lhb_tr
	lda rot1
	sta proc_tmp0
.lhb_tr
	lda rot2
	sta ln_face
	rts

; Y = room. 3D hit vs rb0/rb1 (sx=0 empty). Nearest t in ln_best / col_*.
; C=1 if either hit.
line_cutouts_hit
	lda #$ff
	sta proc_tmp1
	tya
	asl
	tax
	jsr .lch_slot
	inx
	jsr .lch_slot
	lda proc_tmp1
	cmp #$ff
	beq .lch_miss
	sta ln_best
	lda proc_tmp2
	sta col_x
	lda proc_tmp3
	sta col_y
	lda proc_tmp4
	sta col_z
	sec
	rts
.lch_miss
	clc
	rts

.lch_slot
	lda rb_sx,x
	beq .lch_skip
	txa
	pha
	jsr load_box_rb
	jsr line_hit_box
	bcc .lch_pop
	lda ln_best
	cmp proc_tmp1
	bcs .lch_pop
	sta proc_tmp1
	lda col_x
	sta proc_tmp2
	lda col_y
	sta proc_tmp3
	lda col_z
	sta proc_tmp4
.lch_pop
	pla
	tax
.lch_skip
	rts
