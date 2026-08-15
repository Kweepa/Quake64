; Rotate / project / z-clip / stroke a unit cube
!zone cube

vx
	!byte -CUBE_H, CUBE_H, CUBE_H,-CUBE_H,-CUBE_H, CUBE_H, CUBE_H,-CUBE_H
vy
	!byte -CUBE_H,-CUBE_H, CUBE_H, CUBE_H,-CUBE_H,-CUBE_H, CUBE_H, CUBE_H
vz
	!byte -CUBE_H,-CUBE_H,-CUBE_H,-CUBE_H, CUBE_H, CUBE_H, CUBE_H, CUBE_H

edges
	!byte 0,1, 1,2, 2,3, 3,0
	!byte 4,5, 5,6, 6,7, 7,4
	!byte 0,4, 1,5, 2,6, 3,7

cube_rotate
	!source "_rotate_body.asm"

; CAM_* + z_bias (camera-space CAMZ after look) → PROJ_X/Y/Z
cube_project
	lda #0
	sta vindex
.pvert
	ldx vindex
	lda CAM_Z,x
	sta rz
	clc
	adc z_bias
	bcc .pzok
	bit rz
	bmi .pzok
	lda #255
.pzok
	sta z_eye
	sta PROJ_Z,x

	lda CAM_X,x
	jsr persp
	sta rot0
	bmi .xneg
	clc
	adc #SCREEN_CX
	bcs .xhi
	cmp #SCREEN_XMAX
	bcc .xstore
.xhi
	lda #191
	jmp .xstore
.xneg
	clc
	adc #SCREEN_CX
	bcs .xstore
	lda #0
.xstore
	ldx vindex
	sta PROJ_X,x

	lda CAM_Y,x
	jsr persp
	sta rot0
	bmi .yneg
	clc
	adc #64
	bcs .yhi
	cmp #128
	bcc .ystore
.yhi
	lda #127
	jmp .ystore
.yneg
	clc
	adc #64
	bcs .ystore
	lda #0
.ystore
	ldx vindex
	sta PROJ_Y,x

	inc vindex
	lda vindex
	cmp #8
	beq +
	jmp .pvert
+
	rts

; Near-plane reject: both endpoints z >= ZCLIP
cube_clip
	lda #0
	sta vindex
.cel
	lda vindex
	asl
	tax
	lda edges,x
	tay
	lda PROJ_Z,y
	cmp #ZCLIP
	bcc .no
	inx
	lda edges,x
	tay
	lda PROJ_Z,y
	cmp #ZCLIP
	bcc .no
	lda #1
	bne .st
.no
	lda #0
.st
	ldx vindex
	sta EDGE_VIS,x
	inc vindex
	lda vindex
	cmp #12
	bne .cel
	rts

cube_draw
	lda #0
	sta vindex
.del
	ldx vindex
	lda EDGE_VIS,x
	beq .skip
	txa
	asl
	tax
	lda edges,x
	tay
	lda PROJ_X,y
	sta x0
	lda PROJ_Y,y
	sta y0
	inx
	lda edges,x
	tay
	lda PROJ_X,y
	sta x1
	lda PROJ_Y,y
	sta y1
	jsr draw_line
.skip
	inc vindex
	lda vindex
	cmp #12
	beq +
	jmp .del
+
	rts
