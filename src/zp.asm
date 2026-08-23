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
keys		= $45			; KEY_* bits (W A S D I J K L)
cam_xl		= $46			; camera 8.8 world X
cam_zl		= $4b
cam_yl		= $4c
pp_tmp_l	= $47			; prof_print decimal
pp_tmp_h	= $48
pp_col		= $49

draw_buf	= $1e			; 0 = A, 1 = B
show_buf	= $1f
mp_l		= $20			; packed-map field pointer; (mp_l),y uses $20/$21
mp_h		= $21
draw_top_hi	= $3f
draw_bot_hi	= $22
tile_half	= $24			; 0 top charset, 1 bottom
show_d018_bot	= $2a
irq_phase	= $2b
frame_flag	= $2c
yaw		= $2d
pitch		= $2e
z_eye		= $2f
z_eye_h		= $72			; 8.8 z high for persp88
rx		= $30
ry		= $31
rz		= $32
cs_b		= $33			; cos(yaw)  signed 8-bit
sn_b		= $34			; sin(yaw)
cp_b		= $36			; cos(pitch)
sp_b		= $37			; sin(pitch)
vindex		= $35
dt_ms		= $38			; frame dt milliseconds (lo)
div_c		= $3e			; signed denom for lerpdv
nlo		= $5e			; 16-bit lerp num / den / dy
nhi		= $5f
dlo		= $60
dhi		= $61
ylo		= $62
yhi		= $63
e0x		= $50			; per-edge camera / clip scratch
e0y		= $51
e0z		= $52
e1x		= $53
e1y		= $54
e1z		= $55
ox0l		= $56			; signed 16-bit screen offsets
ox0h		= $57
oy0l		= $58
oy0h		= $59
ox1l		= $5a
ox1h		= $5b
oy1l		= $5c
oy1h		= $5d
oc0		= $64
oc1		= $65
oc_tmp		= $66
cs_n		= $67			; Cohen–Sutherland iteration cap
e0xh		= $68
e0yh		= $69
e0zh		= $6a
e1xh		= $6b
e1yh		= $6c
e1zh		= $6d
cam_xh		= $6e			; camera 8.8 integer
cam_zh		= $6f
cam_yh		= $70
mul_y		= $71			; smul16_7 saved |Y|
mul_c		= $73			; 16×8 addend high
anim_acc_l	= $74			; ms accumulator toward ANIM_MS
anim_acc_h	= $75
gidx		= $76			; vert index within current pose (0..12)
enemy_idx	= $77			; current enemy in enemies_update

; World / map (Step 2)
room_idx	= $78
floor_y		= $79			; floor integer (8.8 with floor_yl)
ent_wx		= $7a			; entity world X (int)
ent_wy		= $7b
ent_wz		= $7c
ent_rot		= $7d			; facing yaw 0..255 (0=+Z)
ent_type	= $7e
mesh_nv		= $7f
mesh_ne		= $80
box_inside	= $81			; 1 = room (interior cull)
msg_on		= $82
wish_dx		= $83			; signed move intent X
wish_dz		= $84
save_xh		= $85
save_zh		= $86
col_x		= $87			; collision test point
col_z		= $88
col_y		= $89
obj_i		= $8a
face_bits	= $8b			; which box faces visible
edge_ptr	= $8c			; + $8d → edge table
gx_ptr		= $8e			; + $8f
gy_ptr		= $90			; + $91
gz_ptr		= $92			; + $93
box_x		= $94
box_y		= $95
box_z		= $96
box_sx		= $97
box_sy		= $98
box_sz		= $99
ent_yaw		= $9a			; unused (was rot<<5 for model facing)
pl_on_elev	= $9b			; $ff none, else elev index
msg_off		= $9c			; offset into map_text
wish_dxh	= $9d			; wish 8.8 high
wish_dzh	= $9e
vel_ms		= $9f			; hold duration ms (lo)
turn_acc_l	= $a0
turn_acc_h	= $a1
pitch_acc_l	= $a2
pitch_acc_h	= $a3
save_xl		= $a4
save_zl		= $a5
dt_msh		= $a6			; frame dt milliseconds (hi)
vel_msh		= $a7			; hold duration ms (hi)
; $a8–$ad were 8-bit hold snapshots
inv_l		= $a8			; (FOCAL<<16)/(z>>k) lo, mesh project
inv_h		= $a9
inv_k		= $aa			; unsigned 8-bit fit shift of z
mesh_vmask	= $ab			; $ff = all mesh_nv slots; else 8-bit box corner mask
mesh_nwork	= $ac			; verts/edges counted this stage
random8		= $ad			; rnd8 LCG state (Wolf Deathchase)
scale_s		= $ae			; scale_vel sign
fn_lx		= $af			; frustum inward normals (XZ)
fn_lz		= $b0
pv0		= $b1			; glyph / ramp / door fill
pv1		= $b2
pv2		= $b3
pv3		= $b4
pv4		= $b5
col_bg		= $b6			; active room background → $d021 viewport
col_fx		= $b7			; active room FX (enemy muzzle, etc.)
col_line	= $b8			; active room lines → viewport colour RAM
palette_room	= $b9			; last room_idx palette applied ($ff = none)
far_scale	= $ba			; FOCAL/z integer, far enemy project

; SFX (playsound.asm) — channel queues in abs; ZP scratch only
sfx_zp_l	= $bb			; (ptr),y while arming / stepping
sfx_zp_h	= $bc
sfx_ch		= $bd			; current channel 0..2
sfx_id		= $be			; sound id / freq scratch
col_wpn		= $bf			; active room weapon sprite colour → $d027–$d02a
sample_ms	= $c0			; PAL 20 / NTSC 17 — set at init
ps_save_x	= $c1
ps_save_y	= $c2
sfx_q_len	= $da			; staged play_sound queue depth 0..4
fn_rx		= $c3
fn_rz		= $c4
fn_fx		= $c5			; near/forward
fn_fz		= $c6

; Unique X/Z mesh rotate (xform_mesh_xz)
mesh_nx		= $c7			; unique X count
mesh_nz		= $c8
xid_ptr		= $c9			; + $ca → per-vert X slot
zid_ptr		= $cb			; + $cc → per-vert Z slot
edge_vert_ptr	= $cd			; + $ce → per-edge vertical flags

; Clip / project / enemy-rotate hoist scratch
ei0		= $cf			; mesh_clip edge endpoint indices
ei1		= $d0
cur_col		= $d1			; mesh_project XZ column index
col_ptr		= $d2			; + $d3 → per-vert column id table
org_xl		= $d4			; enemy view-space origin (8.8)
org_xh		= $d5
org_yl		= $d6
org_yh		= $d7
org_zl		= $d8
org_zh		= $d9
floor_yl	= $db			; floor 8.8 fraction (ramps); 0 on flats
lx_b		= $dc			; enemy local vert scratch
lz_b		= $dd

; Quarter-square fast-multiply pointer sets (tables page-aligned; hi bytes
; fixed by mulset_init, mulset_a/b store lo bytes = multiplier per frame/
; enemy/column). a*m = (pa_s1),a − (pa_s2),a.
pa_s1l		= $de			; + $df → sqlo + m
pa_s1h		= $e0			; + $e1 → sqhi + m
pa_s2l		= $e2			; + $e3 → negsqlo + (255-m)
pa_s2h		= $e4			; + $e5 → negsqhi + (255-m)
sg_a		= $e6			; raw multiplier (bit7 = sign)
pb_s1l		= $e7			; + $e8
pb_s1h		= $e9			; + $ea
pb_s2l		= $eb			; + $ec
pb_s2h		= $ed			; + $ee
sg_b		= $ef

; Line-vs-AABB (util.asm). Live during AI / hitscan, not mesh stroke.
ln_ax		= $f0
ln_ay		= $f1
ln_az		= $f2
ln_bx		= $f3
ln_by		= $f4
ln_bz		= $f5
ln_t0		= $f6			; clip enter Q7 (0..127)
ln_t1		= $f7			; clip exit Q7
ln_best		= $f8			; nearest hit t
ln_oc0		= $f9
ln_oc1		= $fa
ln_mx		= $fb			; box exclusive max X/Y/Z
ln_my		= $fc
ln_mz		= $fd
ln_face		= $fe			; current face bit / axis scratch

