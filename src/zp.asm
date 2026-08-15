; Zero page — partitioned so nested routines never share scratch.
!zone zp

; Init-only copy / fill (never live across draw_line / smul7)
src_ptr		= $02			; + $03
dst_ptr		= $04			; + $05
init_ptr	= $06			; + $07  screen/colour/charset fill
init_row	= $3a
stamp_row	= $3b
stamp_in	= $3c			; row-in-half during stamp_viewport

; 8×8 multiply / perspective (math.asm only)
mul_a		= $08
mul_b		= $09
prod_l		= $0a
prod_h		= $0b
mul_sign	= $0c
log_cs		= $0d			; log|trig| per transform
log_sn		= $0e
log_cp		= $0f
log_sp		= $11
sg_cs		= $23			; $00 or $80
sg_sn		= $25
sg_cp		= $26
sg_sp		= $27
log_x		= $1b
log_z		= $1c
log_y		= $1d
sg_x		= $28
sg_z		= $29
sg_y		= $4a
log_rz		= $39
sg_rz		= $3d

; Line endpoints / Bresenham (draw_line inner loop)
x0		= $12
y0		= $13
x1		= $14
y1		= $15
dx		= $16
dy		= $17
sy		= $19
err_l		= $1a
save_x		= $18			; y_cross only (pixel countdown)
bitpos		= $10			; x0&7 for SMC jump
colptr		= $4e			; + $4f  64-byte charset column

; Cube rotate scratch (not used by draw_line)
rot0		= $40
rot1		= $41
rot2		= $42

hud_n		= $43			; hud_print remainder
dt_tmp		= $44			; calc_frame_dt

; Keyboard (filled by raster IRQ, read in main)
key_j		= $45			; 1 = J held (yaw left)
key_l		= $46			; 1 = L held (yaw right)
pp_tmp_l	= $47			; prof_print decimal
pp_tmp_h	= $48
pp_col		= $49

draw_buf	= $1e			; 0 = A, 1 = B
show_buf	= $1f
draw_top_hi	= $21
draw_bot_hi	= $22
tile_half	= $24			; 0 top charset, 1 bottom
show_d018_bot	= $2a
irq_phase	= $2b
frame_flag	= $2c
yaw		= $2d
pitch		= $2e
z_eye		= $2f
rx		= $30
ry		= $31
rz		= $32
cs		= $33			; yaw cos (per transform)
sn		= $34			; yaw sin
cp		= $36			; pitch cos
sp		= $37			; pitch sin
vindex		= $35
dt_ms		= $38
