; 3D line-vs-AABB: hit solid boxes / room cutouts. RAM LUTs ($01=$30).
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
	+lda_mx rc_x
	sta box_x
	+lda_mx rc_y
	sta box_y
	+lda_mx rc_z
	sta box_z
	+lda_mx rc_sx
	sta box_sx
	+lda_mx rc_sy
	sta box_sy
	+lda_mx rc_sz
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
	+lda_my room_x
	sta box_x
	+lda_my room_y
	sta box_y
	+lda_my room_z
	sta box_z
	+lda_my room_sx
	sta box_sx
	+lda_my room_sy
	sta box_sy
	+lda_my room_sz
	sta box_sz
	rts

; X = rb_* index. Copy cutout solid into box_*.
load_box_rb
	+lda_mx rb_x
	sta box_x
	+lda_mx rb_y
	sta box_y
	+lda_mx rb_z
	sta box_z
	+lda_mx rb_sx
	sta box_sx
	+lda_mx rb_sy
	sta box_sy
	+lda_mx rb_sz
	sta box_sz
	rts

; Y = room. ln_a* = origin, ln_b* = signed dir.
; B = origin except on the dominant look axis, where B sits just outside
; the room AABB (min−1 or exclusive max). ln_r0/1/2 temps. X clobbered.
line_fit_b
	jsr load_box_room
	jsr line_box_max
	lda ln_bx
	jsr .lfb_abs
	sta ln_r0				; best |d|
	ldx #0
	stx ln_r1				; best axis
	lda ln_bx
	sta ln_r2				; signed d on best
	lda ln_by
	jsr .lfb_abs
	cmp ln_r0
	bcc .lfb_ny
	sta ln_r0
	ldx #1
	stx ln_r1
	lda ln_by
	sta ln_r2
.lfb_ny
	lda ln_bz
	jsr .lfb_abs
	cmp ln_r0
	bcc .lfb_nz
	ldx #2
	stx ln_r1
	lda ln_bz
	sta ln_r2
.lfb_nz
	lda ln_ax
	sta ln_bx
	lda ln_ay
	sta ln_by
	lda ln_az
	sta ln_bz
	lda ln_r2
	beq .lfb_rts
	ldx ln_r1
	lda ln_r2
	bpl .lfb_pos
	lda box_x,x
	beq .lfb_st
	sec
	sbc #1
	jmp .lfb_st
.lfb_pos
	lda ln_mx,x
.lfb_st
	sta ln_bx,x
.lfb_rts
	rts

.lfb_abs
	bpl .lfb_ap
	eor #$ff
	clc
	adc #1
.lfb_ap
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
	sta ln_r0				; min
	lda ln_ax,x
	sta ln_r1				; max
	jmp .lao_chk
.lao_a
	sta ln_r0
	lda ln_bx,x
	sta ln_r1
.lao_chk
	lda ln_r1
	cmp box_x,x
	bcc .lao_no
	lda ln_r0
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
	sta ln_r2
	lda ln_ax,y
	cmp box_x
	bcs .loc_px
	lda #1
	sta ln_r2
.loc_px
	lda ln_ax,y
	cmp ln_mx
	bcc .loc_y
	lda ln_r2
	ora #2
	sta ln_r2
.loc_y
	lda ln_ay,y
	cmp box_y
	bcs .loc_py
	lda ln_r2
	ora #4
	sta ln_r2
.loc_py
	lda ln_ay,y
	cmp ln_my
	bcc .loc_z
	lda ln_r2
	ora #8
	sta ln_r2
.loc_z
	lda ln_az,y
	cmp box_z
	bcs .loc_pz
	lda ln_r2
	ora #$10
	sta ln_r2
.loc_pz
	lda ln_az,y
	cmp ln_mz
	bcc .loc_done
	lda ln_r2
	ora #$20
	sta ln_r2
.loc_done
	lda ln_r2
	rts

; t Q7 = (plane − A) * 127 / (B − A). Axis X in ln_face (0..2). Plane in ln_r0.
; C=1 t in ln_best (clobbers). Parallel → C=0.
line_t_plane
	ldx ln_face
	lda ln_bx,x
	sec
	sbc ln_ax,x
	sta div_c
	beq .ltp_no
	lda ln_r0
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

; Hit other-axis in face rect? Axis ln_face, t in ln_r1, plane in ln_r0.
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
	lda ln_r1
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
	lda ln_r0
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

; Try face bit ln_face. Plane → ln_r0, axis → ln_face 0..2 temporarily.
.lhb_try
	lda ln_face
	sta ln_r2				; save bit
	ldx #0
	cmp #4
	bcc .lhb_ax
	inx
	cmp #16
	bcc .lhb_ax
	inx
.lhb_ax
	stx ln_face				; 0..2
	lda ln_r2
	and #$2a				; +X/+Y/+Z bits
	beq .lhb_min
	lda ln_mx,x
	jmp .lhb_pl
.lhb_min
	lda box_x,x
.lhb_pl
	sta ln_r0
	jsr line_t_plane
	bcc .lhb_tr
	lda ln_best
	beq .lhb_tr				; t=0 skip
	bmi .lhb_tr
	cmp proc_tmp0
	bcs .lhb_tr				; not strictly nearer (unsigned; $ff = none)
	sta ln_r1
	jsr line_face_hit
	bcc .lhb_tr
	lda ln_r1
	sta proc_tmp0
.lhb_tr
	lda ln_r2
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
	+lda_mx rb_sx
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

; Y = room. Segment ln_a→ln_b.
; C=1 nearest solid (cutout, crate, platform, elevator, crusher, ramp, shell).
; ln_best / col_* = hit. C=0 clear. Running best in proc_tmp1–4.
; Room in proc_tmp5. Does not use rot*. line_hit_box clobbers X.
line_solids_hit
	sty proc_tmp5
	jsr line_cutouts_hit
	ldx #0
.lsh_crate
	cpx map_ncrates
	bcs .lsh_plats
	+lda_mx crate_room
	cmp proc_tmp5
	bne .lsh_cn
	+lda_mx crate_sx
	beq .lsh_cn
	sta box_sx
	+lda_mx crate_x
	sta box_x
	+lda_mx crate_y
	sta box_y
	+lda_mx crate_z
	sta box_z
	+lda_mx crate_sy
	sta box_sy
	+lda_mx crate_sz
	sta box_sz
	txa
	pha
	jsr line_hit_box
	pla
	tax
	bcc .lsh_cn
	jsr .lsh_near
.lsh_cn
	inx
	bne .lsh_crate
.lsh_plats
	ldx #0
.lsh_pl
	cpx map_nplats
	bcs .lsh_elevs
	+lda_mx plat_solid
	beq .lsh_pn
	+lda_mx plat_room
	cmp proc_tmp5
	bne .lsh_pn
	+lda_mx plat_x
	sta box_x
	+lda_mx plat_y
	sta box_y
	lda #0
	sta box_sy
	+lda_mx plat_z
	sta box_z
	+lda_mx plat_sx
	sta box_sx
	+lda_mx plat_sz
	sta box_sz
	txa
	pha
	jsr line_hit_box
	pla
	tax
	bcc .lsh_pn
	jsr .lsh_near
.lsh_pn
	inx
	bne .lsh_pl
.lsh_elevs
	ldx #0
.lsh_ev
	cpx map_nelevs
	bcs .lsh_crush
	+lda_mx elev_room
	cmp proc_tmp5
	bne .lsh_en
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
	txa
	pha
	jsr line_hit_box
	pla
	tax
	bcc .lsh_en
	jsr .lsh_near
.lsh_en
	inx
	bne .lsh_ev
.lsh_crush
	ldy #0
.lsh_cu
	cpy map_ncrush
	bcs .lsh_slopes
	ldx #crush_room - crush_x
	jsr crush_lda
	cmp proc_tmp5
	bne .lsh_cun
	jsr crush_load_box
	tya
	pha
	jsr line_hit_box
	pla
	tay
	bcc .lsh_cun
	jsr .lsh_near
.lsh_cun
	iny
	bne .lsh_cu
.lsh_slopes
	ldx #0
.lsh_sl
	cpx map_nslopes
	bcs .lsh_shell
	+lda_mx slope_room
	cmp proc_tmp5
	bne .lsh_sn
	txa
	pha
	jsr .slope_one
	pla
	tax
	bcc .lsh_sn
	jsr .lsh_near
.lsh_sn
	inx
	bne .lsh_sl
.lsh_shell
	ldy proc_tmp5
	jsr load_box_room
	jsr line_hit_box
	bcc .lsh_pub
	jsr .lsh_near
.lsh_pub
	lda proc_tmp1
	cmp #$ff
	beq .lsh_miss
	sta ln_best
	lda proc_tmp2
	sta col_x
	lda proc_tmp3
	sta col_y
	lda proc_tmp4
	sta col_z
	sec
	rts
.lsh_miss
	clc
	rts

; ln_best vs proc_tmp1. Smaller t wins. Preserves X/Y.
.lsh_near
	lda ln_best
	cmp proc_tmp1
	bcs .lsh_nr
	sta proc_tmp1
	lda col_x
	sta proc_tmp2
	lda col_y
	sta proc_tmp3
	lda col_z
	sta proc_tmp4
.lsh_nr
	rts

; X = slope index, box not loaded. C=1 and ln_best/col_* set when the
; segment crosses the slope face, from above or from the underside.
; The footprint sides are open: Y between the base and the face is air.
.slope_one
	+lda_mx slope_sx
	bne .sl_go
	jmp .sl_no
.sl_go
	sta box_sx
	+lda_mx slope_x
	sta box_x
	+lda_mx slope_z
	sta box_z
	+lda_mx slope_sz
	sta box_sz
	lda #0
	sta box_y
	sta box_sy
	txa
	pha
	jsr .xz_clip
	bcs .sl_clipped
	jmp .sl_pop
.sl_clipped
	lda ln_t0
	ldx #0
	jsr .pt_at
	jsr .clamp_ax
	sta col_x
	lda ln_t0
	ldx #2
	jsr .pt_at
	jsr .clamp_ax
	sta col_z
	lda #0
	sta ylo
	pla
	tax
	pha
	jsr slope_height
	lda col_y
	sta proc_tmp0		; h0
	lda ln_t1
	ldx #0
	jsr .pt_at
	jsr .clamp_ax
	sta col_x
	lda ln_t1
	ldx #2
	jsr .pt_at
	jsr .clamp_ax
	sta col_z
	lda #0
	sta ylo
	pla
	tax
	pha
	jsr slope_height
	lda col_y
	pha			; h1
	lda ln_t0
	ldx #1
	jsr .pt_at
	sta ln_r0		; y0
	lda ln_t1
	ldx #1
	jsr .pt_at
	sta ln_r1		; y1
	pla
	sta ln_r2		; h1
	pla			; slope index
	lda ln_r0
	sec
	sbc proc_tmp0
	sta div_n1		; rel0 = y0-h0
	lda ln_r1
	sec
	sbc ln_r2
	sta div_n2		; rel1 = y1-h1
	lda div_n1
	beq .sl_on0		; on the face at entry
	lda div_n2
	beq .sl_on1		; on the face at exit
	eor div_n1
	bpl .sl_no		; same side of the face
	lda div_n1
	sec
	sbc div_n2
	sta div_c
	lda div_n1
	ldy #127
	jsr lerpdv		; s = rel0*127/(rel0-rel1)
	beq .sl_no
	bmi .sl_no
	jmp .sl_pick
.sl_on0
	lda #0
	jmp .sl_pick
.sl_on1
	lda #127
.sl_pick
	sta ln_r0		; s along the clipped span
	lda ln_t1
	sec
	sbc ln_t0
	ldy ln_r0
	pha
	lda #127
	sta div_c
	pla
	jsr lerpdv
	clc
	adc ln_t0
.sl_commit
	beq .sl_no
	bmi .sl_no
	sta ln_best
	sta ln_r2
	ldx #0
	lda ln_r2
	jsr .pt_at
	sta col_x
	ldx #2
	lda ln_r2
	jsr .pt_at
	sta col_z
	ldx #1
	lda ln_r2
	jsr .pt_at
	sta col_y
	sec
	rts
.sl_pop
	pla
.sl_no
	clc
	rts

; box XZ → ln_t0/ln_t1 clip of ln_a→ln_b. C=1 if the segment meets the rect.
.xz_clip
	lda #0
	sta ln_t0
	lda #127
	sta ln_t1
	jsr line_box_max
	ldx #0
	jsr .xz_axis
	bcc .xz_no
	ldx #2
	jsr .xz_axis
.xz_no
	rts

.xz_axis
	lda ln_bx,x
	sec
	sbc ln_ax,x
	beq .xz_par
	sta ln_r2
	php
	lda box_x,x
	jsr .xz_t
	plp
	php
	bpl .xz_lo_in
	jsr .xz_lower
	jmp .xz_hi
.xz_lo_in
	jsr .xz_raise
.xz_hi
	lda ln_mx,x
	jsr .xz_t
	plp
	bmi .xz_hi_in
	jsr .xz_lower
	jmp .xz_span
.xz_hi_in
	jsr .xz_raise
.xz_span
	lda ln_t0
	cmp ln_t1
	bcc .xz_yes
	beq .xz_yes
	clc
	rts
.xz_yes
	sec
	rts
.xz_par
	lda ln_ax,x
	cmp box_x,x
	bcc .xz_out
	cmp ln_mx,x
	bcs .xz_out
	sec
	rts
.xz_out
	clc
	rts

; A = plane. ln_r2 = dx. X = axis. A = signed t. X preserved.
.xz_t
	sec
	sbc ln_ax,x
	stx ln_r0
	sta ln_r1
	lda ln_r2
	sta div_c
	lda ln_r1
	ldy #127
	jsr lerpdv
	ldx ln_r0
	rts

; A = signed t. Raise ln_t0. X preserved.
.xz_raise
	bmi .xz_rr
	cmp ln_t0
	bcc .xz_rr
	sta ln_t0
.xz_rr
	rts

; A = signed t. Lower ln_t1. Negative t misses the slab.
.xz_lower
	bpl .xz_lp
	lda #1
	sta ln_t0
	lda #0
	sta ln_t1
	rts
.xz_lp
	cmp ln_t1
	bcs .xz_lr
	sta ln_t1
.xz_lr
	rts

; A = t. X = axis. A = point on ln_a→ln_b. X preserved. Uses ln_r0/ln_r1.
.pt_at
	sta ln_r1
	lda ln_bx,x
	sec
	sbc ln_ax,x
	stx ln_r0
	ldy ln_r1
	pha
	lda #127
	sta div_c
	pla
	jsr lerpdv
	ldx ln_r0
	clc
	adc ln_ax,x
	rts

; A = coord, X = 0 or 2. Clamp into [box_x, ln_mx).
.clamp_ax
	cmp box_x,x
	bcs .cl_hi
	lda box_x,x
	rts
.cl_hi
	cmp ln_mx,x
	bcc .cl_ok
	lda ln_mx,x
	beq .cl_ok
	sec
	sbc #1
.cl_ok
	rts
