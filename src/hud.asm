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
	cpx #24
	bne -

!if PROFILE = 1 {
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
}

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

	ldx #23
-
	lda #COL_HUD
	sta $d800 + HUD_OFF,x
	dex
	bpl -
!if PROFILE = 1 {
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF + 4
	sta $d800 + HUD_OFF + 9
	sta $d800 + HUD_OFF + 14
	sta $d800 + HUD_OFF + 19
}
	ldx #0
	lda #HUD_CH_SP
-
	sta SCR_A + HUD_OFF2,x
	sta SCR_B + HUD_OFF2,x
	inx
	cpx #24
	bne -
	ldx #23
-
	lda #COL_HUD
	sta $d800 + HUD_OFF2,x
	dex
	bpl -

!if HUD_POS = 1 {
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
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF2
	sta $d800 + HUD_OFF2 + 5
	sta $d800 + HUD_OFF2 + 10
	sta $d800 + HUD_OFF2 + 15
	sta $d800 + HUD_OFF2 + 19
}

	ldx #0
	lda #HUD_CH_SP
-
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	cpx #24
	bne -
	ldx #23
-
	lda #COL_HUD
	sta $d800 + HUD_OFF3,x
	dex
	bpl -
!if PROFILE = 1 {
	lda #HUD_CH_R
	sta SCR_A + HUD_OFF3
	sta SCR_B + HUD_OFF3
	lda #HUD_CH_P
	sta SCR_A + HUD_OFF3 + 4
	sta SCR_B + HUD_OFF3 + 4
	lda #HUD_CH_K
	sta SCR_A + HUD_OFF3 + 8
	sta SCR_B + HUD_OFF3 + 8
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF3
	sta $d800 + HUD_OFF3 + 4
	sta $d800 + HUD_OFF3 + 8
	lda #HUD_CH_SHELL
	sta SCR_A + HUD_OFF3 + 12
	sta SCR_B + HUD_OFF3 + 12
	lda #HUD_CH_NAIL
	sta SCR_A + HUD_OFF3 + 16
	sta SCR_B + HUD_OFF3 + 16
	lda #HUD_CH_GREN
	sta SCR_A + HUD_OFF3 + 20
	sta SCR_B + HUD_OFF3 + 20
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF3 + 12
	sta $d800 + HUD_OFF3 + 16
	sta $d800 + HUD_OFF3 + 20
} else {
	lda #HUD_CH_SHELL
	sta SCR_A + HUD_OFF3
	sta SCR_B + HUD_OFF3
	lda #HUD_CH_NAIL
	sta SCR_A + HUD_OFF3 + 4
	sta SCR_B + HUD_OFF3 + 4
	lda #HUD_CH_GREN
	sta SCR_A + HUD_OFF3 + 8
	sta SCR_B + HUD_OFF3 + 8
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF3
	sta $d800 + HUD_OFF3 + 4
	sta $d800 + HUD_OFF3 + 8
}

	ldx #0
	lda #HUD_CH_SP
-
	sta SCR_A + HUD_OFF4,x
	sta SCR_B + HUD_OFF4,x
	inx
	cpx #HUD_MSG_W
	bne -
	ldx #23
-
	lda #COL_HUD
	sta $d800 + HUD_OFF4,x
	dex
	bpl -
	rts

; Row 1: frame ms (HUD_FRAME_MS) + R/P/K/D buckets (PROFILE)
; Row 2: X/Y/Z/yaw/pitch (HUD_POS)
; Row 3: vertex counts RNNNPNNNKNNN (PROFILE=1)
hud_print
!if HUD_FRAME_MS = 1 {
	ldx #0
	lda dt_msh
	ldy dt_ms
	jsr .dec4
}
!if PROFILE = 1 {
	ldx #5
	lda prof_cy + PROF_ROT * 4 + 2
	ldy prof_cy + PROF_ROT * 4 + 1
	jsr .ms4
	ldx #10
	lda prof_cy + PROF_PROJ * 4 + 2
	ldy prof_cy + PROF_PROJ * 4 + 1
	jsr .ms4
	ldx #15
	lda prof_cy + PROF_CLIP * 4 + 2
	ldy prof_cy + PROF_CLIP * 4 + 1
	jsr .ms4
	ldx #20
	lda prof_cy + PROF_DRAW * 4 + 2
	ldy prof_cy + PROF_DRAW * 4 + 1
	jsr .ms4

	ldx #1
	lda nv_rot + 1
	ldy nv_rot
	jsr .dec3n
	ldx #5
	lda nv_proj + 1
	ldy nv_proj
	jsr .dec3n
	ldx #9
	lda nv_clip + 1
	ldy nv_clip
	jsr .dec3n
}
!if HUD_POS = 1 {
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
	jsr .s8_3
}
	rts

; Shell/nail/grenade counts at HUD_OFF3: {NNN|NNN}NNN (col 0, or 12 if PROFILE)
; Call on init, after spend, and after backpack grant — not every frame.
hud_ammo
!if PROFILE = 1 {
	ldx #13
} else {
	ldx #1
}
	lda ammo_shells
	jsr .u8_3h
!if PROFILE = 1 {
	ldx #17
} else {
	ldx #5
}
	lda ammo_nails
	jsr .u8_3h
!if PROFILE = 1 {
	ldx #21
} else {
	ldx #9
}
	lda ammo_grenades
	; fall through

; A unsigned → 3 digits at HUD_OFF3+X (pp_col)
.u8_3h
	stx pp_col
	sta pp_tmp_l
	ldx #0
.uh3h
	lda pp_tmp_l
	cmp #100
	bcc .uh3t
	sbc #100
	sta pp_tmp_l
	inx
	bne .uh3h
.uh3t
	stx hud_n
	ldy #0
.uh3tl
	lda pp_tmp_l
	cmp #10
	bcc .uh3o
	sbc #10
	sta pp_tmp_l
	iny
	bne .uh3tl
.uh3o
	lda hud_n
	ora #$30
	sta hud_n
	tya
	ora #$30
	sta pp_tmp_h
	lda pp_tmp_l
	ora #$30
	sta pp_tmp_l
	ldx pp_col
	lda hud_n
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	lda pp_tmp_h
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	rts

!if HUD_POS = 1 {
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
}

!if HUD_FRAME_MS + PROFILE > 0 {
; A:Y = cy[2]:cy[1] → ms (>>2) then 4 digits at HUD_OFF+X
.ms4
	sta pp_tmp_h
	sty pp_tmp_l
	lsr pp_tmp_h
	ror pp_tmp_l
	lsr pp_tmp_h
	ror pp_tmp_l
	lda pp_tmp_h
	ldy pp_tmp_l
	; fall through

; A:Y = 16-bit → 4 ASCII digits at HUD_OFF+X; saturate 9999
.dec4
	stx pp_col
	sta pp_tmp_h
	sty pp_tmp_l
	cmp #>10000
	bcc .d4go
	bne .d4sat
	cpy #<10000
	bcc .d4go
.d4sat
	lda #$39
	sta hud_n
	sta pp_tmp_h
	sta pp_tmp_l
	ldy #$39
	jmp .d4out
.d4go
	ldx #0
.d4thou
	lda pp_tmp_h
	cmp #>1000
	bcc .d4hund
	bne .d4tsub
	lda pp_tmp_l
	cmp #<1000
	bcc .d4hund
.d4tsub
	sec
	lda pp_tmp_l
	sbc #<1000
	sta pp_tmp_l
	lda pp_tmp_h
	sbc #>1000
	sta pp_tmp_h
	inx
	bne .d4thou
.d4hund
	stx hud_n			; thousands 0–9
	ldx #0
.d4hlp
	lda pp_tmp_h
	bne .d4hsub
	lda pp_tmp_l
	cmp #100
	bcc .d4tens
.d4hsub
	sec
	lda pp_tmp_l
	sbc #100
	sta pp_tmp_l
	lda pp_tmp_h
	sbc #0
	sta pp_tmp_h
	inx
	bne .d4hlp
.d4tens
	ldy #0
.d4tlp
	lda pp_tmp_l
	cmp #10
	bcc .d4ones
	sbc #10
	sta pp_tmp_l
	iny
	bne .d4tlp
.d4ones
	txa
	ora #$30
	sta pp_tmp_h			; hundreds ASCII
	tya
	ora #$30
	tay				; tens ASCII
	lda hud_n
	ora #$30
	sta hud_n			; thousands ASCII
	lda pp_tmp_l
	ora #$30
	sta pp_tmp_l			; ones ASCII
.d4out
	ldx pp_col
	lda hud_n
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	lda pp_tmp_h
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	tya
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF,x
	sta SCR_B + HUD_OFF,x
	rts
}

; A:Y = 16-bit → 3 ASCII digits at HUD_OFF3+X; saturate 999
.dec3n
	stx pp_col
	sta pp_tmp_h
	sty pp_tmp_l
	cmp #>1000
	bcc .d3go
	bne .d3sat
	cpy #<1000
	bcc .d3go
.d3sat
	lda #$39
	sta hud_n
	sta pp_tmp_h
	sta pp_tmp_l
	jmp .d3out
.d3go
	ldx #0
.d3hlp
	lda pp_tmp_h
	bne .d3hsub
	lda pp_tmp_l
	cmp #100
	bcc .d3tens
.d3hsub
	sec
	lda pp_tmp_l
	sbc #100
	sta pp_tmp_l
	lda pp_tmp_h
	sbc #0
	sta pp_tmp_h
	inx
	bne .d3hlp
.d3tens
	stx hud_n
	ldy #0
.d3tlp
	lda pp_tmp_l
	cmp #10
	bcc .d3ones
	sbc #10
	sta pp_tmp_l
	iny
	bne .d3tlp
.d3ones
	lda hud_n
	ora #$30
	sta hud_n
	tya
	ora #$30
	sta pp_tmp_h
	lda pp_tmp_l
	ora #$30
	sta pp_tmp_l
.d3out
	ldx pp_col
	lda hud_n
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	lda pp_tmp_h
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF3,x
	sta SCR_B + HUD_OFF3,x
	rts

; Message trigger on HUD_ROW4, centered in the 24-col viewport
hud_message
	lda msg_on
	bne .hm_show
	ldx #0
	lda #HUD_CH_SP
.hm_blank
	sta SCR_A + HUD_OFF4,x
	sta SCR_B + HUD_OFF4,x
	inx
	cpx #HUD_MSG_W
	bne .hm_blank
	rts
.hm_show
	ldx #0
	lda #HUD_CH_SP
.hm_clr
	sta SCR_A + HUD_OFF4,x
	sta SCR_B + HUD_OFF4,x
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
	sta SCR_A + HUD_OFF4,x
	sta SCR_B + HUD_OFF4,x
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
