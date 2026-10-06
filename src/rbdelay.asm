; Mid-split delay: one body, assembled into GAME (irq.asm) and MENU (rbcal.asm),
; so the calibrator times the exact bytes and cycle counts the handler runs.
;
; After the $d012 poll exit (cmp $d012 / bne -):
;   jsr rb_delay     (cell rb_n_lo/hi)  then pla / sta $d018
; X = lo (0 = 256), Y = hi = pass count: n = lo + 256*(hi-1) units of dex/bne
; (5 CPU cycles). Y = 0 would run ~64K units; init_irq rejects it.
;
; Write time W, CPU cycles after the start of the poll's read cycle (which is
; the raster edge + jitter 0..6): 30 + (5n + 4*hi - 1). Loop unit cost 5 CPU
; cycles = 5/N video cycles.
; 1 MHz: K=3 -> 48 (window 48..55 after the raster edge).
;
; A branch that crosses a page costs +1 cycle: the 5N-cycle inner loop would
; drift by N. The macro pads to a page start when the bytes would straddle
; one, and errors if they still do.
RB_DELAY_LEN	= 13

!macro rb_delay_body {
	!if (* & $ff) > ($100 - RB_DELAY_LEN) {
		!align $ff, 0, $ea
	}
rb_delay
	ldx rb_n_lo
	ldy rb_n_hi
-	dex
	bne -
	dey
	bne -
	rts
rb_delay_end
	!if rb_delay_end - rb_delay != RB_DELAY_LEN {
		!error "rb_delay length changed; update RB_DELAY_LEN"
	}
	!if (rb_delay >> 8) != ((rb_delay_end - 1) >> 8) {
		!error "rb_delay straddles a page"
	}
}
