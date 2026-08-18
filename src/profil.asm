; CIA2 cascade frame timer (Wolf64 / SquareDoom)
; Do not touch $dd00 — VIC bank lives there.
!zone profil

CIA2_TA_LO	= $dd04
CIA2_TA_HI	= $dd05
CIA2_TB_LO	= $dd06
CIA2_TB_HI	= $dd07
CIA2_ICR	= $dd0d
CIA2_CRA	= $dd0e
CIA2_CRB	= $dd0f

prof_init
	lda #$7f
	sta CIA2_ICR
	lda CIA2_ICR
	lda #$ff
	sta CIA2_TA_LO
	sta CIA2_TA_HI
	sta CIA2_TB_LO
	sta CIA2_TB_HI
	lda #$11				; TA start + force load, ϕ2
	sta CIA2_CRA
	lda #$51				; TB start + force load, count TA underflows
	sta CIA2_CRB
	jsr prof_read_casc
	jsr prof_store_t0
	lda #0
	sta frame_cy
	sta frame_cy + 1
	sta frame_cy + 2
	sta frame_cy + 3
	lda #20
	sta dt_ms
	lda #0
	sta dt_msh
	rts

; frame_cy >> 10 → 16-bit dt_ms. 0 → 20; saturate at 65535.
calc_frame_dt
	lda frame_cy + 1
	sta dt_ms
	lda frame_cy + 2
	sta dt_msh
	lda frame_cy + 3
	lsr
	ror dt_msh
	ror dt_ms
	lsr
	ror dt_msh
	ror dt_ms
	cmp #0				; A = cy[3] >> 2
	beq .zchk
	lda #$ff
	sta dt_ms
	sta dt_msh
	rts
.zchk
	lda dt_ms
	ora dt_msh
	bne .ok
	lda #20
	sta dt_ms
.ok
	rts

prof_read_casc
	lda $01
	pha
	lda #$35
	sta $01
.retry
	lda CIA2_TB_HI
	sta casc_now + 3
	lda CIA2_TB_LO
	sta casc_now + 2
	lda CIA2_TA_HI
	sta casc_now + 1
	lda CIA2_TA_LO
	sta casc_now
	lda CIA2_TB_HI
	cmp casc_now + 3
	bne .retry
	lda CIA2_TB_LO
	cmp casc_now + 2
	bne .retry
	pla
	sta $01
	rts

prof_store_t0
	lda casc_now
	sta frame_t0
	lda casc_now + 1
	sta frame_t0 + 1
	lda casc_now + 2
	sta frame_t0 + 2
	lda casc_now + 3
	sta frame_t0 + 3
	rts

; Period since last call → frame_cy (countdown timers: t0 − now)
prof_frame_sample
	jsr prof_read_casc
	sec
	lda frame_t0
	sbc casc_now
	sta frame_cy
	lda frame_t0 + 1
	sbc casc_now + 1
	sta frame_cy + 1
	lda frame_t0 + 2
	sbc casc_now + 2
	sta frame_cy + 2
	lda frame_t0 + 3
	sbc casc_now + 3
	sta frame_cy + 3
	jmp prof_store_t0

PROF_CLEAR	= 0
PROF_ROT	= 1
PROF_PROJ	= 2
PROF_CLIP	= 3
PROF_DRAW	= 4
PROF_NBUCKET	= 5

prof_snap
	jsr prof_read_casc
	lda casc_now
	sta casc_snap
	lda casc_now + 1
	sta casc_snap + 1
	lda casc_now + 2
	sta casc_snap + 2
	lda casc_now + 3
	sta casc_snap + 3
	rts

prof_reset_frame
	ldx #PROF_NBUCKET * 4 - 1
	lda #0
-
	sta prof_cy,x
	dex
	bpl -
	jmp prof_snap

; Y = bucket 0..N-1. Add (casc_snap − now) into prof_cy[Y], then snap.
prof_add_bucket
	jsr prof_read_casc
	tya
	asl
	asl
	tax
	sec
	lda casc_snap
	sbc casc_now
	sta prof_dt + 0
	lda casc_snap + 1
	sbc casc_now + 1
	sta prof_dt + 1
	lda casc_snap + 2
	sbc casc_now + 2
	sta prof_dt + 2
	lda casc_snap + 3
	sbc casc_now + 3
	sta prof_dt + 3
	clc
	lda prof_cy,x
	adc prof_dt + 0
	sta prof_cy,x
	lda prof_cy + 1,x
	adc prof_dt + 1
	sta prof_cy + 1,x
	lda prof_cy + 2,x
	adc prof_dt + 2
	sta prof_cy + 2,x
	lda prof_cy + 3,x
	adc prof_dt + 3
	sta prof_cy + 3,x
	lda casc_now
	sta casc_snap
	lda casc_now + 1
	sta casc_snap + 1
	lda casc_now + 2
	sta casc_snap + 2
	lda casc_now + 3
	sta casc_snap + 3
	rts

