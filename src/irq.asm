; Raster chain. No CIA Timer A — keys/SFX once per mid-split (PAL/NTSC sample_ms).
; Phases: 0=HUD→view ($d018+$d021), 1=mid-split ($d018), 2=flyback UI ($d018+$d021).
;
; Right-border split (view + mid):
;   1. IRQ on line L-1 (RASTER_VIEW / RASTER_SPLIT)
;   2. Wait until $d012 == L (start of the real split line)
;   3. Burn IRQ_RBORDER_* into post-viewport / right border
;   4. sta $d018 (and $d021 on view)
; Mid-split then: accum_keys, flush SFX, update_sfx, snapshot holds.
; Flyback stays ASAP on 251.
!zone irq

; After sync to split-line start: 2+N*5-1 = 5N+1 cycles.
; Mid: preload show_d018_bot, then ldx + delay + pla/sta (5N+11 post-wait).
; Wait exits ~cycle 6–12; col 31 ends ~47. N=7 → 46cy window: after col 31,
; still on 186 with sprite 7 DMA (centre splat). N=10 was already end-of-line
; and splat slipped $d018 onto 187. IRQ_DEBUG_SPLIT pokes are 12cy — drop N
; by 2 so the stripe matches shipped timing. View: three pla/sta after delay,
; so N=7 → 36cy + stores still on 122 (N=10 was slipping $d021 onto 123).
!if IRQ_DEBUG_SPLIT = 1 {
IRQ_RBORDER_N	= 5
} else {
IRQ_RBORDER_N	= 7
}
IRQ_RBORDER_VIEW	= 7

nmi_rti
	rti

init_irq
	lda #$7f
	sta $dc0d
	sta $dd0d
	lda $dc0d
	lda $dd0d

	; $01=$30 fetches $FFFA–$FFFF (UI char 255, unused). Also KERNAL $0314/8
	; for $01=$36. Menu sfx owns these until GAME init.
	lda #<nmi_rti
	sta $fffa
	sta $0318
	lda #>nmi_rti
	sta $fffb
	sta $0319
	lda #<reboot_game
	sta $fffc
	lda #>reboot_game
	sta $fffd
	lda #<irq_entry
	sta $fffe
	sta $0314
	lda #>irq_entry
	sta $ffff
	sta $0315

	lda #0
	sta irq_phase
	sta frame_flag
	sta turn_acc_l
	sta turn_acc_h
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh
	sta sfx_q_len
	ldx #11
-
	sta in_fwd,x
	dex
	bpl -

	; PAL/NTSC → sample_ms (KERNAL $02a6: 0=NTSC, 1=PAL)
	lda $01
	pha
	lda #$37
	sta $01
	ldx #SAMPLE_MS_NTSC
	lda $02a6
	beq +
	ldx #SAMPLE_MS_PAL
+
	stx sample_ms
	stx sample_ms_chk
	lda #0
	sta spd_trip
	pla
	sta $01

	lda #RASTER_VIEW
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #1
	sta $d01a
	rts

; A/$01 saved first; VIC stores before any mid-split work.
irq_entry
	pha
	lda $01
	pha
	lda #BANK_IO				; I/O + KERNAL, BASIC out
	sta $01

	lda $d019
	and #1
	bne .do
	pla
	sta $01
	pla
	rti
.do
	sta $d019

	lda irq_phase
	beq .view
	cmp #1
	beq .split
	jmp .top

; Mid-viewport: preload, sync to 186, right-border $d018, then keys/SFX.
; accum_keys adds sample_ms into in_* each video frame; main snapshots.
.split
	txa
	pha
	tya
	pha
	lda show_d018_bot
	pha
	lda $d012
	cmp #RASTER_SPLIT_LINE
	bcs .split_rb
	lda #RASTER_SPLIT_LINE
-
	cmp $d012
	bne -
.split_rb
!if IRQ_DEBUG_SPLIT = 1 {
	lda #COL_WHITE
	sta $d020
}
	ldx #IRQ_RBORDER_N
-
	dex
	bne -
!if IRQ_DEBUG_SPLIT = 1 {
	lda #COL_HURT
	sta $d020
}
	pla
	sta $d018
	lda #RASTER_TOP
	sta $d012
	lda $d011
	and #$7f
	sta $d011
	lda #2
	sta irq_phase
	jsr accum_keys
	jsr flush_sfx
	jsr update_sfx
	jsr irq_elev_noise
	pla
	tay
	pla
	tax
	pla
	sta $01
	pla
	rti

; HUD → viewport: preload, sync to 122, shorter delay (extra stores vs mid).
.view
	txa
	pha
	tya
	pha
	ldx show_buf
	lda col_bg
	pha
	lda show_bot_tab,x
	pha
	lda show_top_tab,x
	pha
	lda $d012
	cmp #RASTER_VIEW_LINE
	bcs .view_rb
	lda #RASTER_VIEW_LINE
-
	cmp $d012
	bne -
.view_rb
	ldx #IRQ_RBORDER_VIEW
-
	dex
	bne -
	pla
	sta $d018
	pla
	sta show_d018_bot
	pla
	sta $d021
	lda #RASTER_SPLIT
	sta $d012
	lda #1
	sta irq_phase
	pla
	tay
	pla
	tax
	pla
	sta $01
	pla
	rti

; Lower flyback: UI charset + black bg — long before badline 51.
.top
	txa
	pha
	tya
	pha
	lda #D018_A_UI
	sta $d018
	lda #COL_HUD_BG
	sta $d021
	lda #RASTER_VIEW
	sta $d012
	lda #0
	sta irq_phase
	inc frame_flag
	jsr prof_read_casc
	lda sample_ms
	cmp sample_ms_chk
	beq .top_ok
	lda sample_ms_chk
	sta sample_ms
	inc spd_trip
	lda #COL_WHITE
	sta vic_border
.top_ok
	jsr irq_publish_vic
	pla
	tay
	pla
	tax
	pla
	sta $01
	pla
	rti

; Y = 0,2,4,… offset from in_fwd; add sample_ms, saturate at 65535
irq_add_ms
	clc
	lda in_fwd,y
	adc sample_ms
	sta in_fwd,y
	lda in_fwd+1,y
	adc #0
	sta in_fwd+1,y
	bcc +
	lda #$ff
	sta in_fwd,y
	sta in_fwd+1,y
+
	rts

accum_keys
	lda #0
	sta keys
	; W/A/S PA1 $FD
	lda #$fd
	sta $dc00
	lda $dc01
	tax
	and #$02
	bne .now
	lda keys
	ora #KEY_W
	sta keys
	ldy #in_fwd - in_fwd
	jsr irq_add_ms
.now
	txa
	and #$04
	bne .noa
	lda keys
	ora #KEY_A
	sta keys
	ldy #in_strafel - in_fwd
	jsr irq_add_ms
.noa
	txa
	and #$20
	bne .nos
	lda keys
	ora #KEY_S
	sta keys
	ldy #in_back - in_fwd
	jsr irq_add_ms
.nos
	txa
	and #$01				; 3 = nailgun
	bne .no3
	lda #1
	sta in_wpn_nail
.no3
	txa
	and #$08				; 4 = grenade launcher
	bne .no4
	lda #1
	sta in_wpn_gren
.no4
	; D PA2 $FB
	lda #$fb
	sta $dc00
	lda $dc01
	and #$04
	bne .nod
	lda keys
	ora #KEY_D
	sta keys
	ldy #in_strafer - in_fwd
	jsr irq_add_ms
.nod
	; J/K share PA4 $EF — J look left, K use (SquareDoom)
	lda #$ef
	sta $dc00
	lda $dc01
	tax
	and #$04
	bne .noj
	lda keys
	ora #KEY_J
	sta keys
	ldy #in_turn_l - in_fwd
	jsr irq_add_ms
.noj
	txa
	and #$20				; K = use
	bne .nok
	lda keys
	ora #KEY_K
	sta keys
	lda #1
	sta in_use
.nok
	; L PA5 $DF
	lda #$df
	sta $dc00
	lda $dc01
	and #$04
	bne .nol
	lda keys
	ora #KEY_L
	sta keys
	ldy #in_turn_r - in_fwd
	jsr irq_add_ms
.nol
	; 1 / 2 / SPACE on PA7 = $7F
	lda #$7f
	sta $dc00
	lda $dc01
	tax
	and #$01				; 1 = axe
	bne .no1
	lda #1
	sta in_wpn_axe
.no1
	txa
	and #$08				; 2 = shotgun
	bne .no2
	lda #1
	sta in_wpn_shot
.no2
	txa
	and #$10				; SPACE
	bne .nospc
	lda #1
	sta in_fire
.nospc
	rts

; Publish in_* → hold_* / key_* then clear (main, once per game frame).
; IRQ only accumulates into in_* each mid-split — do not snapshot there or
; a slow game frame only sees one video tick of hold ms.
; Each 16-bit hold slot is sei-atomic vs irq_add_ms (lost/torn ticks).
snapshot_input
	ldx #0
.si_ms
	php
	sei
	lda in_fwd,x
	sta hold_fwd,x
	lda in_fwd+1,x
	sta hold_fwd+1,x
	lda #0
	sta in_fwd,x
	sta in_fwd+1,x
	plp
	inx
	inx
	cpx #12
	bcc .si_ms
	ldx #3
-
	lda in_wpn_axe,x
	sta key_wpn_axe,x
	lda #0
	sta in_wpn_axe,x
	dex
	bpl -
	lda in_fire
	sta key_fire
	lda #0
	sta in_fire
	lda in_use
	sta key_use
	lda #0
	sta in_use
	rts

; V3 rumble from elev_noise_n (main only touches the counter).
irq_elev_noise
	lda elev_noise_n
	beq .iene_off
	jmp elev_noise_restore
.iene_off
	lda sfx_index+2
	bpl .iene_rts
	lda #0
	sta $d412
.iene_rts
	rts

; Snapshot then build turn + wish from hold_*.
read_input
	jsr snapshot_input
	lda #0
	sta wish_dx
	sta wish_dxh
	sta wish_dz
	sta wish_dzh

	; net turn: right − left (16-bit ms)
	lda hold_turn_r + 1
	cmp hold_turn_l + 1
	bne .tcmp
	lda hold_turn_r
	cmp hold_turn_l
.tcmp
	beq .tnone
	bcs .tright
	sec
	lda hold_turn_l
	sbc hold_turn_r
	sta vel_ms
	lda hold_turn_l + 1
	sbc hold_turn_r + 1
	sta vel_msh
	jsr turn_deliver
	eor #$ff
	clc
	adc #1
	clc
	adc yaw
	sta yaw
	jmp .tnone
.tright
	sec
	lda hold_turn_r
	sbc hold_turn_l
	sta vel_ms
	lda hold_turn_r + 1
	sbc hold_turn_l + 1
	sta vel_msh
	jsr turn_deliver
	clc
	adc yaw
	sta yaw
.tnone
	rts

; turn_acc += vel_ms<<6 (24-bit); A = min(sum>>10, 255); turn_acc &= $03FF
turn_deliver
	lda vel_ms
	sta pp_tmp_l
	lda vel_msh
	sta pp_tmp_h
	lda #0
	sta hud_n
	ldx #6
.tdsh
	asl pp_tmp_l
	rol pp_tmp_h
	rol hud_n
	dex
	bne .tdsh
	clc
	lda turn_acc_l
	adc pp_tmp_l
	sta turn_acc_l
	lda turn_acc_h
	adc pp_tmp_h
	sta pp_tmp_h
	lda hud_n
	adc #0
	sta hud_n
	lda pp_tmp_h
	and #3
	sta turn_acc_h
	lda pp_tmp_h
	lsr
	lsr
	sta pp_tmp_l
	lda hud_n
	asl
	asl
	asl
	asl
	asl
	asl
	ora pp_tmp_l
	ldx hud_n
	cpx #4
	bcc +
	lda #255
+
	rts
