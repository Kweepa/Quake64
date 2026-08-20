; Sound effects — PC-speaker envelopes on SID voices 1–3.
; Data: pcsounds.asm + pcsfreq.asm (tools/gensounds.py); sound_voices routes
; each ID to ch0=player V1 pulse, ch1=enemy V2 pulse, ch2=world V3 noise.
; Decimated 3x; stepped once per CIA1 Timer A poll (~50 Hz) from raster IRQ.
; SID Fn lo fixed at $80 (hi LUT only — saves 256 bytes).

!zone playsound

SFX_VOL		= $0f
SFX_NCH		= 3

; Per-channel queue (abs — visible at $01=$34/$35). Index $ff = idle.
sfx_index
	!byte $ff, $ff, $ff
sfx_priority
	!byte 0, 0, 0
sfx_count
	!byte 0, 0, 0
sfx_max
	!byte 0, 0, 0
sfx_ptr_l
	!byte 0, 0, 0
sfx_ptr_h
	!byte 0, 0, 0

; SID Fn-lo offset from $d400 per channel (V1/V2/V3)
sfx_sid_base
	!byte $00, $07, $0e

; Control: pulse+gate vs noise+gate
sfx_wave
	!byte $41, $41, $81

; ------------------------------------------------------------------
; play_sound_init — clear SID; V1/V2 pulse + V3 noise ADSR; volume full
; ------------------------------------------------------------------
play_sound_init
	ldx #SFX_NCH-1
.psi_ch
	lda #$ff
	sta sfx_index,x
	lda #0
	sta sfx_priority,x
	sta sfx_count,x
	sta sfx_max,x
	dex
	bpl .psi_ch
	ldx #$18
	lda #0
.psi_clr
	sta $d400,x
	dex
	bpl .psi_clr
	jsr sfx_voice_adsr_all
	lda #SFX_VOL
	sta $d418
	rts

; Program PW+ADSR for V1/V2 and ADSR for V3 (no PW for noise).
sfx_voice_adsr_all
	lda #$00
	sta $d402				; V1 PW lo — 50%
	sta $d409				; V2 PW lo
	lda #$08
	sta $d403				; V1 PW hi
	sta $d40a				; V2 PW hi
	lda #$00
	sta $d405				; V1 AD
	sta $d40c				; V2 AD
	sta $d413				; V3 AD
	lda #$f0
	sta $d406				; V1 SR
	sta $d40d				; V2 SR
	sta $d414				; V3 SR
	rts

; ------------------------------------------------------------------
; play_sound — A = sound index; higher-or-equal priority preempts
; Queue-only: no SID access (safe at $01=$34); raster Timer A poll
; (update_sfx) does all SID writes, starting on the next tick.
; Preserves X,Y and caller's I flag; A clobbered
; ------------------------------------------------------------------
play_sound
	php
	sei
	stx ps_save_x
	sty ps_save_y
	sta sfx_id				; sound id
	tax
	lda sound_voices,x
	sta sfx_ch				; channel
	tay
	lda sound_priorities,x
	cmp sfx_priority,y
	bcc .ps_skip

	sta sfx_priority,y

	lda sfx_id
	asl
	tax
	lda sound_table,x
	sta sfx_ptr_l,y
	sta sfx_zp_l
	lda sound_table+1,x
	sta sfx_ptr_h,y
	sta sfx_zp_h

	ldy #0
	lda (sfx_zp_l),y
	tay
	iny
	ldx sfx_ch
	tya
	sta sfx_max,x
	lda #0
	sta sfx_count,x
	lda sfx_id
	sta sfx_index,x
.ps_skip
	ldx ps_save_x
	ldy ps_save_y
	plp
	rts

; ------------------------------------------------------------------
; update_sfx — one PC speaker sample per channel (~50 Hz Timer A)
; Scratch ZP: sfx_zp_l/h, sfx_ch, sfx_id.
; ------------------------------------------------------------------
update_sfx
	ldx #0
.us_loop
	stx sfx_ch
	lda sfx_index,x
	bpl .us_active
.us_next
	ldx sfx_ch
	inx
	cpx #SFX_NCH
	bcc .us_loop
	rts

.us_active
	inc sfx_count,x
	lda sfx_count,x
	cmp sfx_max,x
	beq .us_stop
	lda sfx_ptr_l,x
	sta sfx_zp_l
	lda sfx_ptr_h,x
	sta sfx_zp_h
	ldy sfx_count,x
	lda (sfx_zp_l),y
	beq .us_silent
	jsr sfx_write_tone
	jmp .us_next

.us_silent
	jsr sfx_gate_off
	jmp .us_next

.us_stop
	jsr sfx_gate_off
	ldx sfx_ch
	lda #$ff
	sta sfx_index,x
	lda #0
	sta sfx_priority,x
	cpx #2
	bne .us_stop_vol
	jsr elev_noise_restore
.us_stop_vol
	lda #SFX_VOL
	sta $d418
	jmp .us_next

; A = inverse-freq byte; sfx_ch = channel. Writes Fn + ADSR + gate.
sfx_write_tone
	sta sfx_id
	ldx sfx_ch
	lda sfx_sid_base,x
	tay
	lda #$80
	sta $d400,y
	ldx sfx_id
	lda pcsfreq_hi,x
	sta $d401,y
	ldx sfx_ch
	cpx #2
	beq .swt_v3
	lda #$00
	sta $d402,y
	lda #$08
	sta $d403,y
	lda #$00
	sta $d405,y
	lda #$f0
	sta $d406,y
	jmp .swt_gate
.swt_v3
	lda #$00
	sta $d413
	lda #$f0
	sta $d414
.swt_gate
	lda sfx_wave,x
	sta $d404,y
	rts

; sfx_ch = channel → gate off that voice
sfx_gate_off
	ldx sfx_ch
	lda sfx_sid_base,x
	tay
	lda #0
	sta $d404,y
	rts

; ------------------------------------------------------------------
; elev_noise_restore / elev_noise_program — V3 rumble helpers
; restore: only if elevators moving and world channel idle
; program: write V3 noise rumble registers (no refcount)
; ------------------------------------------------------------------
elev_noise_restore
	lda elev_noise_n
	beq .enr_rts
	lda sfx_index+2
	bpl .enr_rts				; world SFX still owns V3
elev_noise_program
	lda #$00
	sta $d40e				; V3 Fn lo
	lda #$02
	sta $d40f				; V3 Fn hi — low rumble
	lda #$00
	sta $d413				; AD
	lda #$f8
	sta $d414				; SR sustain
	lda #$81				; noise + gate
	sta $d412
.enr_rts
	rts
