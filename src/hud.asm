; 40-col HUD — Quake 8×8 font in UI charset $F000 (ASCII screen codes)
; Single-buffered in matrix A. Raster HUD / flyback always D018_A_UI; the
; viewport still flips A/B. Colour RAM is shared.
!zone hud

init_hud
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

	; rows 0–8 (360 bytes): spaces + orange colour (matrix A only)
	ldx #0
	lda #HUD_CH_SP
-	sta SCR_A,x
	inx
	bne -
	ldx #0
-	sta SCR_A + 256,x
	inx
	cpx #104
	bne -
	ldx #0
	lda #COL_HUD
-	sta $d800,x
	inx
	bne -
	ldx #0
-	sta $d800 + 256,x
	inx
	cpx #104
	bne -

	ldx #0
-	lda hud_str_title,x
	beq +
	sta SCR_A + HUD_OFF_TITLE + HUD_TITLE_COL,x
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF_TITLE + HUD_TITLE_COL,x
	inx
	bne -
+
	ldy #0
-	lda map_name,y
	beq +
	iny
	cpy #HUD_MSG_W
	bcc -
+	sty hud_n
	lda #HUD_MSG_W
	sec
	sbc hud_n
	lsr
	tax
	ldy #0
.imap
	lda map_name,y
	beq .imap_done
	sta SCR_A + HUD_OFF_MAP,x
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF_MAP,x
	inx
	iny
	cpy #HUD_MSG_W
	bcc .imap
.imap_done

	lda #HUD_CH_SHELL
	sta SCR_A + HUD_OFF_SHELL + HUD_AMMO_ICON
	lda #HUD_CH_NAIL
	sta SCR_A + HUD_OFF_NAIL + HUD_AMMO_ICON
	lda #HUD_CH_GREN
	sta SCR_A + HUD_OFF_GREN + HUD_AMMO_ICON
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF_SHELL + HUD_AMMO_ICON
	sta $d800 + HUD_OFF_NAIL + HUD_AMMO_ICON
	sta $d800 + HUD_OFF_GREN + HUD_AMMO_ICON

	ldx #0
-	lda hud_str_health,x
	beq +
	sta SCR_A + HUD_OFF_SHELL + HUD_HP_LABEL,x
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF_SHELL + HUD_HP_LABEL,x
	inx
	bne -
+
	ldx #0
-	lda hud_str_armour,x
	beq +
	sta SCR_A + HUD_OFF_SHELL + HUD_AR_LABEL,x
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF_SHELL + HUD_AR_LABEL,x
	inx
	bne -
+
	lda #COL_HUD_DIM
	ldx #5
-	sta $d800 + HUD_OFF_GREN + HUD_PU_LABEL,x
	dex
	bpl -

!if PROFILE = 1 {
	lda #HUD_CH_R
	sta SCR_A + HUD_OFF + 4
	lda #HUD_CH_P
	sta SCR_A + HUD_OFF + 9
	lda #HUD_CH_K
	sta SCR_A + HUD_OFF + 14
	lda #HUD_CH_D
	sta SCR_A + HUD_OFF + 19
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF + 4
	sta $d800 + HUD_OFF + 9
	sta $d800 + HUD_OFF + 14
	sta $d800 + HUD_OFF + 19
	lda #HUD_CH_R
	sta SCR_A + HUD_OFF2
	lda #HUD_CH_P
	sta SCR_A + HUD_OFF2 + 4
	lda #HUD_CH_K
	sta SCR_A + HUD_OFF2 + 8
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF2
	sta $d800 + HUD_OFF2 + 4
	sta $d800 + HUD_OFF2 + 8
}

!if HUD_POS = 1 {
	lda #HUD_CH_X
	sta SCR_A + HUD_OFF2
	lda #HUD_CH_Y
	sta SCR_A + HUD_OFF2 + 5
	lda #HUD_CH_Z
	sta SCR_A + HUD_OFF2 + 10
	lda #HUD_CH_H
	sta SCR_A + HUD_OFF2 + 15
	lda #HUD_CH_P
	sta SCR_A + HUD_OFF2 + 19
	lda #COL_HUD_DIM
	sta $d800 + HUD_OFF2
	sta $d800 + HUD_OFF2 + 5
	sta $d800 + HUD_OFF2 + 10
	sta $d800 + HUD_OFF2 + 15
	sta $d800 + HUD_OFF2 + 19
}
	jmp hud_powerup

; Row 0: frame ms FFF (HUD_FRAME_MS) + R/P/K/D buckets (PROFILE)
; Row 3: X/Y/Z/yaw/pitch (HUD_POS) or vertex counts (PROFILE)
hud_print
!if HUD_FRAME_MS = 1 {
	ldx #0
	lda dt_msh
	ldy dt_ms
	jsr .dec3
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

; Ammo + health + armour. Call on init, spend, backpack, damage — not every frame.
hud_ammo
	lda #<SCR_A + HUD_OFF_SHELL
	sta dst_ptr
	lda #>SCR_A + HUD_OFF_SHELL
	sta dst_ptr+1
	ldx #HUD_AMMO_NUM
	lda ammo_shells
	jsr .u8_3at
	lda #<SCR_A + HUD_OFF_NAIL
	sta dst_ptr
	lda #>SCR_A + HUD_OFF_NAIL
	sta dst_ptr+1
	ldx #HUD_AMMO_NUM
	lda ammo_nails
	jsr .u8_3at
	lda #<SCR_A + HUD_OFF_GREN
	sta dst_ptr
	lda #>SCR_A + HUD_OFF_GREN
	sta dst_ptr+1
	ldx #HUD_AMMO_NUM
	lda ammo_grenades
	jsr .u8_3at
	ldx #HUD_HP_NUM
	lda player_hp
	jsr .u8_3at
	ldx #HUD_AR_NUM
	lda player_armour
	; fall through

; A unsigned -> 3 digits at (dst_ptr)+X, matrix A
.u8_3at
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
	tya
	ora #$30
	sta pp_tmp_h
	lda hud_n
	ora #$30
	ldy pp_col
	sta (dst_ptr),y
	iny
	lda pp_tmp_h
	sta (dst_ptr),y
	iny
	lda pp_tmp_l
	ora #$30
	sta (dst_ptr),y
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
	inx
	tya
	ora #$30
	sta SCR_A + HUD_OFF2,x
	inx
	lda pp_tmp_l
	ora #$30
	sta SCR_A + HUD_OFF2,x
	rts
}

!if PROFILE = 1 {
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
	inx
	lda pp_tmp_h
	sta SCR_A + HUD_OFF,x
	inx
	tya
	sta SCR_A + HUD_OFF,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF,x
	rts
}

; A:Y = 16-bit → 3 ASCII digits; saturate 999. .dec3 → HUD_OFF, .dec3n → HUD_OFF3
!if HUD_FRAME_MS = 1 {
.dec3
	stx pp_col
	jsr .d3conv
	ldx pp_col
	lda hud_n
	sta SCR_A + HUD_OFF,x
	inx
	lda pp_tmp_h
	sta SCR_A + HUD_OFF,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF,x
	rts
}
!if PROFILE = 1 {
.dec3n
	stx pp_col
	jsr .d3conv
	ldx pp_col
	lda hud_n
	sta SCR_A + HUD_OFF3,x
	inx
	lda pp_tmp_h
	sta SCR_A + HUD_OFF3,x
	inx
	lda pp_tmp_l
	sta SCR_A + HUD_OFF3,x
	rts
}
!if HUD_FRAME_MS + PROFILE > 0 {
.d3conv
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
	rts
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
	rts
}

; Message trigger on HUD_ROW4, centered. Call on enter/leave only.
hud_message
	lda #0
	sta status_ms_l
	sta status_ms_h
	lda msg_on
	bne .hm_show
	jmp hud_msg_blank
.hm_show
	jsr hud_msg_blank
	clc
	lda #<map_text
	adc msg_off
	sta src_ptr
	lda #>map_text
	adc #0
	sta src_ptr+1
	jmp hud_msg_center

hud_msg_blank
	ldx #0
	lda #HUD_CH_SP
.hmb
	sta SCR_A + HUD_OFF4,x
	inx
	cpx #HUD_MSG_W
	bne .hmb
	rts

; src_ptr → NUL string, already blanked, centered on HUD_OFF4
hud_msg_center
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
	inx
	iny
	cpy #HUD_MSG_W
	bcc .hm_cp
.hm_done
	rts

; Name at HUD_OFF_GREN + HUD_PU_LABEL (row below 2×2 icon on SHELL/NAIL).
hud_powerup
	lda pu_kind
	cmp #BP_QUAD
	beq .hpu_quad
	cmp #BP_PENT
	beq .hpu_pent
	cmp #BP_RING
	beq .hpu_ring
	lda #HUD_CH_SP
	ldx #5
.hpu_clab
	sta SCR_A + HUD_OFF_GREN + HUD_PU_LABEL,x
	dex
	bpl .hpu_clab
	sta SCR_A + HUD_OFF_SHELL + HUD_PU_COL
	sta SCR_A + HUD_OFF_SHELL + HUD_PU_COL + 1
	sta SCR_A + HUD_OFF_NAIL + HUD_PU_COL
	sta SCR_A + HUD_OFF_NAIL + HUD_PU_COL + 1
	rts
.hpu_quad
	ldx #0
	lda #HUD_CH_QUAD
	bne .hpu_draw
.hpu_pent
	ldx #6
	lda #HUD_CH_PENT
	bne .hpu_draw
.hpu_ring
	ldx #12
	lda #HUD_CH_RING
.hpu_draw
	sta SCR_A + HUD_OFF_SHELL + HUD_PU_COL
	clc
	adc #1
	sta SCR_A + HUD_OFF_SHELL + HUD_PU_COL + 1
	adc #1
	sta SCR_A + HUD_OFF_NAIL + HUD_PU_COL
	adc #1
	sta SCR_A + HUD_OFF_NAIL + HUD_PU_COL + 1
	ldy #0
.hpu_lab
	lda hud_str_pu,x
	sta SCR_A + HUD_OFF_GREN + HUD_PU_LABEL,y
	inx
	iny
	cpy #6
	bne .hpu_lab
	rts

; A = BP_* type. "Got the <name>" for 5s on HUD_ROW4.
; Quad/pent/ring: name only (no prefix).
hud_got
	cmp #BP_NTYPES
	bcc .hg_ok
	rts
.hg_ok
	sta rot2
	tay
	lda bp_name_lo,y
	sta src_ptr
	lda bp_name_hi,y
	sta src_ptr+1
	jsr hud_msg_blank
	lda rot2
	cmp #BP_QUAD
	bcc .hg_got
	cmp #BP_SILVER
	bcc .hg_nameonly
.hg_got
	ldy #0
.hg_nl
	lda (src_ptr),y
	beq .hg_nlen
	iny
	cpy #HUD_MSG_W
	bcc .hg_nl
.hg_nlen
	tya
	clc
	adc #HUD_GOT_LEN
	sta hud_n
	lda #HUD_MSG_W
	sec
	sbc hud_n
	lsr
	tax
	ldy #0
.hg_pre
	lda hud_str_got,y
	beq .hg_name
	sta SCR_A + HUD_OFF4,x
	inx
	iny
	bne .hg_pre
.hg_name
	ldy #0
.hg_cp
	lda (src_ptr),y
	beq .hg_arm
	sta SCR_A + HUD_OFF4,x
	inx
	iny
	bne .hg_cp
.hg_arm
	lda #<STATUS_MS
	sta status_ms_l
	lda #>STATUS_MS
	sta status_ms_h
	rts
.hg_nameonly
	jsr hud_msg_center
	jmp .hg_arm

; Tick status line; blank and clear msg_on when the timer expires.
update_status
	lda status_ms_l
	ora status_ms_h
	beq .us_rts
	sec
	lda status_ms_l
	sbc dt_ms
	sta status_ms_l
	lda status_ms_h
	sbc dt_msh
	sta status_ms_h
	bcs .us_rts
	lda #0
	sta status_ms_l
	sta status_ms_h
	sta msg_on
	jmp hud_msg_blank
.us_rts
	rts

HUD_GOT_LEN	= 8			; "Got the "
hud_str_got	!byte 71,111,116,32,116,104,101,32,0	; Got the
bpn_shells	!byte 115,104,101,108,108,115,0		; shells
bpn_nailgun	!byte 110,97,105,108,103,117,110,0	; nailgun
bpn_nails	!byte 110,97,105,108,115,0		; nails
bpn_gl		!byte 103,114,101,110,97,100,101,32,108,97,117,110,99,104,101,114,0	; grenade launcher
bpn_grenades	!byte 103,114,101,110,97,100,101,115,0	; grenades
bpn_health	!byte 104,101,97,108,116,104,0		; health
bpn_armour	!byte 97,114,109,111,117,114,0		; armour
bpn_quad	!byte 113,117,97,100,32,100,97,109,97,103,101,0	; quad damage
bpn_pent	!byte 112,101,110,116,97,103,114,97,109,32,111,102,32,112,114,111,116,101,99,116,105,111,110,0	; pentagram of protection
bpn_ring	!byte 114,105,110,103,32,111,102,32,115,104,97,100,111,119,115,0	; ring of shadows
bpn_silver	!byte 115,105,108,118,101,114,32,107,101,121,0	; silver key
bpn_gold	!byte 103,111,108,100,32,107,101,121,0		; gold key
bp_name_lo
	!byte <bpn_shells, <bpn_nailgun, <bpn_nails, <bpn_gl
	!byte <bpn_grenades, <bpn_health, <bpn_health, <bpn_shells, <bpn_armour
	!byte <bpn_quad, <bpn_pent, <bpn_ring, <bpn_silver, <bpn_gold
bp_name_hi
	!byte >bpn_shells, >bpn_nailgun, >bpn_nails, >bpn_gl
	!byte >bpn_grenades, >bpn_health, >bpn_health, >bpn_shells, >bpn_armour
	!byte >bpn_quad, >bpn_pent, >bpn_ring, >bpn_silver, >bpn_gold

; ASCII (UI charset), not PETSCII
hud_str_title	!byte 81,117,97,107,101,54,52,0	; Quake64
hud_str_health	!byte 72,101,97,108,116,104,0		; Health
hud_str_armour	!byte 65,114,109,111,117,114,0		; Armour
hud_str_pu	!byte 68,97,109,97,103,101			; Damage
		!byte 83,104,105,101,108,100			; Shield
		!byte 83,104,97,100,111,119			; Shadow

ui_font
	!source "uifont.asm"
ui_font_end
!if ui_font_end - ui_font != 2048 {
	!error "UI font blob must be 2048 bytes"
}
