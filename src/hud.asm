; HUD ms readout — Quake 8×8 font in UI charset $F000 (ASCII screen codes)
!zone hud

init_hud
	lda #$35
	sta $01
	lda #<ui_font
	sta src_ptr
	lda #>ui_font
	sta src_ptr+1
	lda #<UI_CHARSET
	sta dst_ptr
	lda #>UI_CHARSET
	sta dst_ptr+1
	ldx #UI_FONT_PAGES
	ldy #0
.copy
	lda (src_ptr),y
	sta (dst_ptr),y
	iny
	bne .copy
	inc src_ptr+1
	inc dst_ptr+1
	dex
	bne .copy

	ldx #0
	lda #HUD_CH_SP
-
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	cpx #23
	bne -

	lda #HUD_CH_R
	sta SCR_A + HUD_OFF + 4
	sta SCR_B + HUD_OFF + 4
	lda #HUD_CH_P
	sta SCR_A + HUD_OFF + 9
	sta SCR_B + HUD_OFF + 9
	lda #HUD_CH_K
	sta SCR_A + HUD_OFF + 14
	sta SCR_B + HUD_OFF + 14
	lda #HUD_CH_D
	sta SCR_A + HUD_OFF + 19
	sta SCR_B + HUD_OFF + 19

	ldx #0
	lda #0
-	sta $da80,x
	inx
	bne -
	ldx #0
-
	sta $db80,x
	inx
	cpx #104
	bne -

	ldx #22
-
	lda #COL_HUD
	sta $d800 + HUD_OFF,x
	dex
	bpl -
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF + 4
	sta $d800 + HUD_OFF + 9
	sta $d800 + HUD_OFF + 14
	sta $d800 + HUD_OFF + 19
	lda #0
	sta $d800 + HUD_OFF + 3
	sta $d800 + HUD_OFF + 8
	sta $d800 + HUD_OFF + 13
	sta $d800 + HUD_OFF + 18

	ldx #0
	lda #HUD_CH_SP
-
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	inx
	cpx #24
	bne -
	lda #HUD_CH_X
	sta SCR_A + HUD_OFF2
	sta SCR_B + HUD_OFF2
	lda #HUD_CH_Y
	sta SCR_A + HUD_OFF2 + 5
	sta SCR_B + HUD_OFF2 + 5
	lda #HUD_CH_Z
	sta SCR_A + HUD_OFF2 + 10
	sta SCR_B + HUD_OFF2 + 10
	lda #HUD_CH_H
	sta SCR_A + HUD_OFF2 + 15
	sta SCR_B + HUD_OFF2 + 15
	lda #HUD_CH_P
	sta SCR_A + HUD_OFF2 + 19
	sta SCR_B + HUD_OFF2 + 19

	ldx #23
-
	lda #COL_HUD
	sta $d800 + HUD_OFF2,x
	dex
	bpl -
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF2
	sta $d800 + HUD_OFF2 + 5
	sta $d800 + HUD_OFF2 + 10
	sta $d800 + HUD_OFF2 + 15
	sta $d800 + HUD_OFF2 + 19

	ldx #0
	lda #HUD_CH_SP
-
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	cpx #HUD_MSG_W
	bne -
	ldx #23
-
	lda #COL_HUD
	sta $d800 + HUD_OFF3,x
	dex
	bpl -
	rts

; F from frame_cy; R P K D from prof_cy (clear still timed, not printed)
hud_print
	ldx #0
	lda frame_cy + 2
	ldy frame_cy + 1
	jsr .ms3
	ldx #5
	lda prof_cy + PROF_ROT * 4 + 2
	ldy prof_cy + PROF_ROT * 4 + 1
	jsr .ms3
	ldx #10
	lda prof_cy + PROF_PROJ * 4 + 2
	ldy prof_cy + PROF_PROJ * 4 + 1
	jsr .ms3
	ldx #15
	lda prof_cy + PROF_CLIP * 4 + 2
	ldy prof_cy + PROF_CLIP * 4 + 1
	jsr .ms3
	ldx #20
	lda prof_cy + PROF_DRAW * 4 + 2
	ldy prof_cy + PROF_DRAW * 4 + 1
	jsr .ms3

	ldx #1
	lda cam_xh
	jsr .s8_3
	ldx #6
	lda cam_yh
	jsr .s8_3
	ldx #11
	lda cam_zh
	jsr .s8_3
	ldx #16
	lda yaw
	jsr .u8_3
	ldx #20
	lda pitch
	jmp .s8_3

; A signed → sign + 3 digits at HUD_OFF2+X (horizon pitch = 0)
.s8_3
	stx pp_col
	cmp #0
	bpl .spos
	ldx pp_col
	pha
	lda #HUD_CH_MINUS
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	pla
	eor #$ff
	clc
	adc #1
	inx
	stx pp_col
	jmp .u8_3
.spos
	ldx pp_col
	pha
	lda #HUD_CH_PLUS
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	pla
	inx
	stx pp_col
	; fall through

; A unsigned 0–255 → 3 ASCII digits at HUD_OFF2+X (also pp_col)
.u8_3
	stx pp_col
	sta pp_tmp_l
	ldx #0
.uhund
	lda pp_tmp_l
	cmp #100
	bcc .utens
	sbc #100
	sta pp_tmp_l
	inx
	bne .uhund
.utens
	ldy #0
.utenlp
	lda pp_tmp_l
	cmp #10
	bcc .uones
	sbc #10
	sta pp_tmp_l
	iny
	bne .utenlp
.uones
	txa
	ora #$30
	ldx pp_col
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	inx
	tya
	ora #$30
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	inx
	lda pp_tmp_l
	ora #$30
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	rts

; A:Y = cy[2]:cy[1] → 3 ASCII digits at HUD_OFF+X
.ms3
	stx pp_col
	sta pp_tmp_h
	sty pp_tmp_l
	lsr pp_tmp_h
	ror pp_tmp_l
	lsr pp_tmp_h
	ror pp_tmp_l
	lda pp_tmp_h
	beq .dec3
	lda #$39
	sta pp_tmp_l
	sta hud_n
	lda #$39
	jmp .out3
.dec3
	ldx #0
.hund
	lda pp_tmp_l
	cmp #100
	bcc .tens
	sbc #100
	sta pp_tmp_l
	inx
	bne .hund
.tens
	ldy #0
.tenlp
	lda pp_tmp_l
	cmp #10
	bcc .ones
	sbc #10
	sta pp_tmp_l
	iny
	bne .tenlp
.ones
	txa
	ora #$30
	ldx pp_col
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	tya
	ora #$30
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	lda pp_tmp_l
	ora #$30
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	rts
.out3
	ldx pp_col
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	lda hud_n
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	rts

; Message trigger on row 21, centered in the 24-col viewport
hud_message
	lda msg_on
	bne .hm_show
	ldx #0
	lda #HUD_CH_SP
.hm_blank
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	cpx #HUD_MSG_W
	bne .hm_blank
	rts
.hm_show
	ldx #0
	lda #HUD_CH_SP
.hm_clr
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	cpx #HUD_MSG_W
	bne .hm_clr
	clc
	lda #<map_text
	adc msg_off
	sta src_ptr
	lda #>map_text
	adc #0
	sta src_ptr+1
	ldy #0
.hm_len
	lda (src_ptr),y
	beq .hm_got
	iny
	cpy #HUD_MSG_W
	bcc .hm_len
.hm_got
	sty hud_n			; length
	lda #HUD_MSG_W
	sec
	sbc hud_n
	lsr
	tax				; dest col = (W - len) / 2
	ldy #0
.hm_cp
	lda (src_ptr),y
	beq .hm_done
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	iny
	cpy #HUD_MSG_W
	bcc .hm_cp
.hm_done
	rts

ui_font
	!source "uifont.asm"
ui_font_end
!if ui_font_end - ui_font != 2048 {
	!error "UI font blob must be 2048 bytes"
}
