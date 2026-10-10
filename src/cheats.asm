; Cheat codes — probe only the next expected CIA1 matrix cell (col, row).
; Called from accum_keys (raster mid-split). IRQ latches cheat_req;
; apply_cheats on main does HUD, sound, and restart_level.
; Shared "id" prefix, then god / kfa / mapNN.
!zone cheats

CHEAT_IDLE	= 0
CHEAT_GOT_I	= 1
CHEAT_AFTER_ID	= 2
CHEAT_REQ_GOD	= 1
CHEAT_REQ_KFA	= 2
CHEAT_REQ_MAP	= 3

; god, kfa, map, three keys each. Index is the table offset; base/end
; bound it. Digits are a separate 1..9 pair.
cheat_col	!byte $f7, $ef, $fb			; G O D
		!byte $ef, $fb, $fd			; K F A
		!byte $ef, $fd, $df			; M A P
cheat_row	!byte $04, $40, $04
		!byte $20, $20, $04
		!byte $10, $04, $02
cheat_base	!byte 0, 3, 6
cheat_end	!byte 3, 6, 9
cheat_col_dig	!byte $7f, $7f, $fd, $fd, $fb, $fb, $f7, $f7, $ef
cheat_row_dig	!byte $01, $08, $01, $08, $01, $08, $01, $08, $01

cheat_msg_on	!text "godmode on",0
cheat_msg_off	!text "godmode off",0
cheat_msg_kfa	!text "keys, full ammo",0
cheat_msg_map	!text "change map",0

; ---------------------------------------------------------------------------
cheat_init
	lda #0
	sta god_mode
	sta cheat_req
	sta cheat_ep_latch
	sta cheat_map_latch
	jmp cheat_reset_all

check_cheats
	lda player_hp
	beq .rts
	lda cheat_phase
	beq .idle
	cmp #CHEAT_GOT_I
	beq .got_i
	jmp .after_id

.idle
	lda #$ef				; I
	ldy #$02
	ldx #0
	jsr cheat_rise
	bcc .rts
	lda #CHEAT_GOT_I
	sta cheat_phase
	lda #0
	sta cheat_was
.rts
	rts

.got_i
	lda #$fb				; D
	ldy #$04
	ldx #0
	jsr cheat_rise
	bcc .rts
	jsr cheat_clear_suf
	lda #CHEAT_AFTER_ID
	sta cheat_phase
	rts

.after_id
	lda #$ef				; another I restarts the prefix
	ldy #$02
	ldx #3
	jsr cheat_rise
	bcc .suf
	jsr cheat_clear_suf
	lda #CHEAT_GOT_I
	sta cheat_phase
	rts

.suf
	ldx #0
.suf_lp
	jsr cheat_step
	inx
	cpx #3
	bcc .suf_lp
	rts

; ---------------------------------------------------------------------------
; cheat_rise — A=col Y=row X=slot; C=1 on rising edge
; ---------------------------------------------------------------------------
cheat_rise
	sta cheat_a
	sty cheat_b
	stx cheat_c
	sta $dc00
	lda $dc01
	and cheat_b
	beq .down
	lda #0
	beq .edge
.down
	lda #1
.edge
	ldx cheat_c
	cmp cheat_was,x
	sta cheat_was,x
	beq .no
	cmp #1
	bne .no
	sec
	rts
.no
	clc
	rts

; ---------------------------------------------------------------------------
; cheat_dig_held — A = first held digit 1..9, or 0
; cheat_dig_rise — A = digit on rising edge, else 0
; ---------------------------------------------------------------------------
cheat_dig_held
	ldx #0
.dh_loop
	lda cheat_col_dig,x
	sta $dc00
	lda $dc01
	and cheat_row_dig,x
	beq .dh_hit
	inx
	cpx #9
	bcc .dh_loop
	lda #0
	rts
.dh_hit
	txa
	clc
	adc #1
	rts

cheat_dig_rise
	jsr cheat_dig_held
	cmp cheat_dig_prev
	sta cheat_dig_prev
	beq .dr_no
	cmp #0
	beq .dr_no
	rts				; A = 1..9
.dr_no
	lda #0
	rts

cheat_clear_suf
	ldx #2
.cs_b
	lda cheat_base,x
	sta cheat_god,x
	dex
	bpl .cs_b
	lda #0
	ldx #4				; cheat_was[4] + cheat_dig_prev
.cs_w
	sta cheat_was,x
	dex
	bpl .cs_w
	rts

cheat_reset_all
	jsr cheat_clear_suf
	lda #0
	sta cheat_phase
	rts

; X = suffix 0..2 (also the cheat_was slot). Map takes two digits once
; its index reaches cheat_end.
cheat_step
	cpx #2
	bne .st_let
	lda cheat_map
	cmp cheat_end + 2
	bcs .st_dig
.st_let
	ldy cheat_god,x
	lda cheat_col,y
	pha
	lda cheat_row,y
	tay
	pla
	jsr cheat_rise
	ldx cheat_c
	bcc .st_rts
	inc cheat_god,x
	lda cheat_god,x
	cmp cheat_end,x
	bne .st_rts
	cpx #2
	beq .st_seed
	inx				; req = slot + 1
	pla
	pla				; drop cheat_step, reset rts to the IRQ
	jmp cheat_latch
.st_seed
	jsr cheat_dig_held		; held keys are not a rising edge
	sta cheat_dig_prev
	ldx #2
.st_rts
	rts

.st_dig
	stx cheat_c
	jsr cheat_dig_rise
	beq .std_back
	ldx cheat_map
	cpx cheat_end + 2
	bne .st_mapn
	sta cheat_ep_dig
	inc cheat_map
.std_back
	ldx cheat_c
	rts
.st_mapn
	sta cheat_map_dig
	lda cheat_ep_dig
	sta cheat_ep_latch
	lda cheat_map_dig
	sta cheat_map_latch
	pla
	pla
	ldx #CHEAT_REQ_MAP
	jmp cheat_latch

; X = CHEAT_REQ_*. Ignore it when one is already waiting.
cheat_latch
	lda cheat_req
	beq .lt_set
	jmp cheat_reset_all
.lt_set
	stx cheat_req
	jmp cheat_reset_all

; ---------------------------------------------------------------------------
; Main. cheat_req is IRQ-owned; copy it out under SEI.
; ---------------------------------------------------------------------------
apply_cheats
	php
	sei
	lda cheat_req
	beq .ac_none
	ldx cheat_ep_latch
	ldy cheat_map_latch
	pha
	lda #0
	sta cheat_req
	pla
	plp
	cmp #CHEAT_REQ_GOD
	beq apply_god
	cmp #CHEAT_REQ_KFA
	beq apply_kfa
	cmp #CHEAT_REQ_MAP
	beq apply_map
	rts
.ac_none
	plp
	rts

apply_god
	lda god_mode
	eor #1
	sta god_mode
	beq .ag_off
	lda #<cheat_msg_on
	ldy #>cheat_msg_on
	jmp .ag_msg
.ag_off
	lda #<cheat_msg_off
	ldy #>cheat_msg_off
.ag_msg
	jsr cheat_show
	lda #SOUND_ITEMS_DAMAGE
	jmp play_sound

apply_kfa
	lda #HAVE_AXE | HAVE_SHOT | HAVE_NAIL | HAVE_GREN
	sta have_wpn
	lda #AMMO_SHELLS_MAX
	sta ammo_shells
	lda #AMMO_NAILS_MAX
	sta ammo_nails
	lda #AMMO_GRENADES_MAX
	sta ammo_grenades
	lda #PLAYER_ARMOUR_MAX
	sta player_armour
	lda #HAVE_SILVER | HAVE_GOLD | HAVE_EARTH
	sta have_keys
	jsr hud_ammo
	lda #<cheat_msg_kfa
	ldy #>cheat_msg_kfa
	jsr cheat_show
	lda #SOUND_WEAPONS_PKUP
	jmp play_sound

; X = episode digit, Y = map digit. Message after play_up2 (inside restart).
apply_map
	cpx #1
	bne .am_rts
	cpy #1
	bcc .am_rts
	cpy #MAP_NLEVELS + 1
	bcs .am_rts
	sty level_num
	jsr restart_level
	bcs .am_fail
	lda #<cheat_msg_map
	ldy #>cheat_msg_map
	jmp cheat_show
.am_fail
	jmp episode_done
.am_rts
	rts

; A = lo, Y = hi. Status row, STATUS_MS.
cheat_show
	sta src_ptr
	sty src_ptr+1
	jsr hud_msg_blank
	jsr hud_msg_center
	lda #<STATUS_MS
	sta status_ms_l
	lda #>STATUS_MS
	sta status_ms_h
	rts
