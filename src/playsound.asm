; Sound effects — PC-speaker envelopes on SID voices 1–3 (pulse 50%).
; Data: pcsounds.asm + pcsfreq.asm (tools/gensounds.py); sound_voices is a
; mixer (ch0=player V1, ch1=enemy V2, ch2=world V3). Enemy envelopes ride
; pose PRGs; sound_table hi=0 until rebind_streamed_sfx.
; Layout: N, AD, freq[0..N-1], vol[0..N-1] (same Y). AD written on commit.
; Stepped once per mid-split raster (~50/60 Hz).
; SID Fn lo fixed at $80 (hi LUT only — saves 256 bytes).

!zone playsound

SFX_VOL		= $0f
SFX_NCH		= 3
SFX_QMAX	= 4

; Per-channel queue (abs — RAM). Index $ff = idle.
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
sfx_vol_l
	!byte 0, 0, 0
sfx_vol_h
	!byte 0, 0, 0
sfx_sr
	!byte 0				; AD / SR nibble scratch (IRQ)

; Main stages here; mid-split IRQ flushes via play_sound_commit.
sfx_q
	!byte 0, 0, 0, 0
fs_save_x
	!byte 0				; flush_sfx loop index (IRQ-private; not ZP)

; SID Fn-lo offset from $d400 per channel (V1/V2/V3)
sfx_sid_base
	!byte $00, $07, $0e

; ------------------------------------------------------------------
; play_sound_init — clear SID; PW+ADSR defaults; volume full
; ------------------------------------------------------------------
play_sound_init
	lda #0
	sta sfx_q_len
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
	lda effects_vol
	and #SFX_VOL
	sta $d418
	rts

; Default PW 50% + ADSR on all voices (per-sound AD on commit).
sfx_voice_adsr_all
	lda #$00
	sta $d402				; V1 PW lo — 50%
	sta $d409				; V2 PW lo
	sta $d410				; V3 PW lo
	lda #$08
	sta $d403				; V1 PW hi
	sta $d40a				; V2 PW hi
	sta $d411				; V3 PW hi
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
; play_sound — A = sound index; stage for mid-split IRQ.
; Queue length update is sei-atomic vs flush_sfx. Preserves X,Y; A clobbered.
; ------------------------------------------------------------------
play_sound
	stx ps_save_x
	php
	sei
	ldx sfx_q_len
	cpx #SFX_QMAX
	bcs .ps_full
	sta sfx_q,x
	inx
	stx sfx_q_len
.ps_full
	plp
	ldx ps_save_x
	rts

; Mid-split IRQ: commit staged IDs into channel queues.
flush_sfx
	ldx #0
.fs_loop
	cpx sfx_q_len
	bcs .fs_done
	lda sfx_q,x
	stx fs_save_x
	jsr play_sound_commit
	ldx fs_save_x
	inx
	bne .fs_loop
.fs_done
	lda #0
	sta sfx_q_len
	rts

; A = sound index; higher-or-equal priority preempts (IRQ / flush only).
; Streamed IDs have sound_table hi=0 until the pose bank is bound.
play_sound_commit
	sta sfx_id
	asl
	tax
	lda sound_table+1,x
	beq .psc_skip
	ldx sfx_id
	lda sound_voices,x
	sta sfx_ch
	tay
	lda sound_priorities,x
	cmp sfx_priority,y
	bcc .psc_skip

	sta sfx_priority,y

	lda sfx_id
	asl
	tax
	lda sound_table,x
	sta sfx_zp_l
	lda sound_table+1,x
	sta sfx_zp_h

	ldy #0
	lda (sfx_zp_l),y			; N
	ldx sfx_ch
	sta sfx_max,x

	ldy #1
	lda (sfx_zp_l),y			; AD (attack<<4, decay 0)
	sta sfx_sr
	lda sfx_sid_base,x
	tay
	lda #0
	sta $d404,y				; gate off so attack sees 0→1
	lda sfx_sr
	sta $d405,y

	clc
	lda sfx_zp_l
	adc #2
	sta sfx_ptr_l,x
	lda sfx_zp_h
	adc #0
	sta sfx_ptr_h,x

	clc
	lda sfx_ptr_l,x
	adc sfx_max,x
	sta sfx_vol_l,x
	lda sfx_ptr_h,x
	adc #0
	sta sfx_vol_h,x

	lda #$ff
	sta sfx_count,x
	lda sfx_id
	sta sfx_index,x
.psc_skip
	rts

; Gate off any channel whose current id is a streamed (heap) effect.
stop_streamed_sfx
	ldx #SFX_NCH-1
.sss_lp
	lda sfx_index,x
	bmi .sss_n
	tay
	lda sound_streamed,y
	beq .sss_n
	stx sfx_ch
	jsr sfx_gate_off
	ldx sfx_ch
	lda #$ff
	sta sfx_index,x
	lda #0
	sta sfx_priority,x
	cpx #2
	bne .sss_n
	jsr elev_noise_restore
.sss_n
	dex
	bpl .sss_lp
	rts

; Zero sound_table slots for streamed ids (resident pc_* words stay).
unbind_streamed_sfx
	ldx #0
.uss_lp
	cpx #SOUND_COUNT
	bcs .uss_rts
	lda sound_streamed,x
	beq .uss_n
	txa
	asl
	tay
	lda #0
	sta sound_table,y
	sta sound_table+1,y
.uss_n
	inx
	bne .uss_lp
.uss_rts
	rts

; ------------------------------------------------------------------
; update_sfx — one PC speaker sample per channel (once per mid-split)
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
	sta sfx_id
	lda sfx_vol_l,x
	sta sfx_zp_l
	lda sfx_vol_h,x
	sta sfx_zp_h
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
	lda effects_vol
	and #SFX_VOL
	sta $d418
	jmp .us_next

; A = vol 1..15; sfx_id = inverse-freq byte; sfx_ch = channel.
; AD was set on commit; rewrite SR + pulse+gate each tick (gate stays on).
sfx_write_tone
	asl
	asl
	asl
	asl					; sustain nibble, release 0
	sta sfx_sr
	ldx sfx_ch
	lda sfx_sid_base,x
	tay
	lda #$80
	sta $d400,y
	ldx sfx_id
	lda pcsfreq_hi,x
	sta $d401,y
	lda #$00
	sta $d402,y				; 50% PW
	lda #$08
	sta $d403,y
	lda sfx_sr
	sta $d406,y
	lda #$41				; pulse + gate
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
