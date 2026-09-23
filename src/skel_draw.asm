!cpu 6510
!to "../enemies/skel_draw.bin", plain
!source "build_flags.asm"
!source "mem.asm"
!source "zp.asm"
!source "map_counts.asm"
!source "mapacc.asm"
!source "map_bss.asm"
!source "enemy_data.asm"
!source "ai_game_syms.asm"

; Custom-skeleton draw. Linked at AI_LINK_BASE and appended after any
; behavior code. Resident play only jsr's skel_draw_entry. Custom poses are
; always baked (genenemies writes no lerp frames), so LERP is a no-op.
!zone skel_draw
*= AI_LINK_BASE

SKEL_CMD_LERP = 1

skel_draw_entry
	cmp #SKEL_CMD_LERP
	beq +
	jmp draw_custom_enemy
+
	rts

!source "_skel_body.asm"

; Data after all code so genaimeta's opcode walk stays aligned.
skel_ezrun	!fill MESH_MAX_EDGES, 0	; per-edge vertical flags, all zero
skel_sh		!byte 0
skel_cs		!byte 0			; raw cos / sin (bit 7 = sign)
skel_ss		!byte 0
skel_lxs	!byte 0			; raw local x / z, then magnitudes
skel_lzs	!byte 0
skel_lxa	!byte 0
skel_lza	!byte 0
skel_xl		!byte 0			; net X/Z shift: left or right count
skel_xr		!byte 0
skel_yl		!byte 0			; net Y shift from gy<<8
skel_yr		!byte 0
skel_sink	!byte 0			; rise/sink drop, 8.8
skel_sinkh	!byte 0
skel_bi		!byte 0			; baked batch read index
skel_bp		!word 0			; next baked batch
; View-space rotated verts, one column per coordinate byte.
skel_cx		!fill SKEL_MAX_VERTS, 0
skel_cxh	!fill SKEL_MAX_VERTS, 0
skel_cy		!fill SKEL_MAX_VERTS, 0
skel_cyh	!fill SKEL_MAX_VERTS, 0
skel_cz		!fill SKEL_MAX_VERTS, 0
skel_czh	!fill SKEL_MAX_VERTS, 0
