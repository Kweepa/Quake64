; VIC Bank 3 layout (c64_quake_architecture.md)
; $C000 screen A  $C400 screen B
; $CA00 projected verts / CIA2 profiler (not displayed)
; $D000/$D800 charset A top/bot  $E000/$E800 charset B top/bot
; $F800 log/alog/sin/cos (copied at init). Judd sqlo/sqhi live in the PRG.

COL_BORDER	= 0
COL_BG		= 9			; default sky (brown)
COL_FLOOR	= 8			; default floor (orange)
COL_HUD_BG	= 0
COL_LINE	= 7			; default vectors (yellow)
COL_OUTSIDE	= 0			; black frame (not $d021 brown)

VIEW_COL	= 8
VIEW_ROW	= 9			; HUD occupies rows 0–8
VIEW_W		= 24
VIEW_H		= 16
VIEW_OFF	= VIEW_ROW * 40 + VIEW_COL
SCREEN_CX	= 96			; 192px viewport centre
SCREEN_XMAX	= 192
MARGIN_CH	= 192			; col 24 row 0 — solid glyph, not cleared

; PAL text starts at raster 51 (YSCROLL=3). HUD 9 rows, then 16-row viewport.
; Fire the line before each band's badline (raster&7 == 3) so $d018 is latched
; before VIC fetches that character row. IRQ on the badline itself is too late:
; the CPU is stunned, and the row stays on the previous charset (HUD glyphs in view).
RASTER_TOP	= 50			; line before first HUD badline (51)
RASTER_VIEW	= 121			; two lines before viewport badline 123
RASTER_SPLIT	= 186			; last line of viewport top half — before 187

D018_A_TOP	= $04			; matrix $C000, charset $D000
D018_A_BOT	= $06			; matrix $C000, charset $D800
D018_B_TOP	= $18			; matrix $C400, charset $E000
D018_B_BOT	= $1A			; matrix $C400, charset $E800
D018_A_UI	= $0C			; matrix $C000, UI charset $F000
D018_B_UI	= $1C			; matrix $C400, UI charset $F000

UI_CHARSET	= $F000
UI_FONT_PAGES	= 8			; 256 glyphs, ASCII-indexed from quakefont.png
HUD_ROW		= 2
HUD_ROW2	= 3
HUD_ROW3	= 4			; vertex counts R/P/K
HUD_ROW4	= 5			; trigger message
HUD_COL		= 8
HUD_OFF		= HUD_ROW * 40 + HUD_COL
HUD_OFF2	= HUD_ROW2 * 40 + HUD_COL
HUD_OFF3	= HUD_ROW3 * 40 + HUD_COL
HUD_OFF4	= HUD_ROW4 * 40 + HUD_COL
HUD_CH_SP	= $20			; ASCII space / digits / letters in UI charset
HUD_CH_PLUS	= $2b
HUD_CH_MINUS	= $2d
HUD_CH_C	= $43
HUD_CH_R	= $52
HUD_CH_P	= $50
HUD_CH_K	= $4b
HUD_CH_D	= $44
HUD_CH_H	= $48
HUD_CH_X	= $58
HUD_CH_Y	= $59
HUD_CH_Z	= $5a
COL_HUD		= 8			; orange digits
COL_HUD_DIM	= 2			; dark red stage letters

LOGTAB		= $F800
ALOGTAB		= $F900			; 512 bytes
SINTAB		= $FB00
COSTAB		= $FC00
LUT_PAGES	= 5			; 1280 bytes

SCR_A		= $C000
SCR_B		= $C400
CH_A_TOP	= $D000
CH_A_BOT	= $D800
CH_B_TOP	= $E000
CH_B_BOT	= $E800

PROJ_X		= $CA00			; 16 view/proj slots (NVERTS=13 used)
PROJ_Y		= $CA10
PROJ_Z		= $CA20
CAM_X		= $CA30
CAM_Y		= $CA40
CAM_Z		= $CA50
PROJ_XH		= $CA60
PROJ_YH		= $CA70
CAM_XH		= $CA80
CAM_YH		= $CA90
CAM_ZH		= $CAA0
PROJ_ZH		= $CAB0
EDGE_VIS	= $CAC0			; 16 edge flags
CLIP_X0		= $CAD0
CLIP_Y0		= $CAE0
CLIP_X1		= $CAF0
CLIP_Y1		= $CB00
frame_t0	= $CB10			; 4-byte CIA2 cascade snapshot
frame_cy	= $CB14
casc_now	= $CB18

FOCAL		= 100
LOG_FOCAL	= 213			; round(32*log2(100))
NVERTS		= 13
NEDGES		= 13
WALK_FRAMES	= 4
ANIM_MS		= 200			; walk step interval (ms)
ZCLIP		= $0100			; 1.0 near plane (8.8)
YAW_STEP	= 3
PITCH_STEP	= 2
PITCH_MIN	= $d0			; -48, signed about horizon 0
PITCH_MAX	= 48
KEY_W		= 1
KEY_A		= 2
KEY_S		= 4
KEY_D		= 8
KEY_I		= 16
KEY_J		= 32
KEY_K		= 64
KEY_L		= 128
PERSP_MAX	= 127
CLIP_XMIN	= -96			; signed offset: x 0..191
CLIP_XMAX	= 95
CLIP_YMIN	= -64			; y 0..127
CLIP_YMAX	= 63
OC_LEFT		= 1
OC_RIGHT	= 2
OC_TOP		= 4
OC_BOT		= 8

; Player / world
EYE_HEIGHT	= 3
PLAYER_H	= 4			; Y collision height [feet, feet+PLAYER_H)
DOOR_PROX	= 3			; open trigger: depth in front of door face
MOVE_SPEED	= 2			; 8.8 step scale (asl count after wish)
PLAYER_R	= 1			; XZ collision radius
ENEMY_CULL_R	= 2			; view-space |x| vs z+R (8.8 high)
ENEMY_CULL_H	= 6			; view-space |y| vs z+H (figure height)
ITEM_CULL_Y	= 2			; AABB |y| vs Chebyshev XZ + pad
FOV_HALF	= 31			; yaw ticks ≈ atan(SCREEN_CX/FOCAL)

; Process SoA + mutable map state in VIC-bank scratch past profiler
PROC_NUM	= 8
PROC_FREE	= 0
PROC_TIMER	= 1
PROC_OPEN_DOOR	= 2
PROC_LOWER_DOOR	= 3
PROC_LOWER_ELEV	= 4
PROC_RAISE_ELEV	= 5

PROC_KIND	= $CB20
PROC_A		= $CB28			; door/elev index
PROC_B		= $CB30			; dest / next kind
PROC_C		= $CB38			; timer/accum lo
PROC_D		= $CB40			; timer/accum hi
PROC_E		= $CB48			; elev home return Y

door_open	= $CB50			; MAP_NDOORS (≤8)
elev_y		= $CB58			; MAP_NELEVS (≤4)
proc_tmp0	= $CB60
proc_tmp1	= $CB61
proc_tmp2	= $CB62
proc_tmp3	= $CB63
proc_tmp4	= $CB64
proc_tmp5	= $CB65
MOTION_STEP_MS	= 64
DOOR_RECLOSE_MS	= 5000
ELEV_WAIT_MS	= 5000

; Box / mesh draw
BOX_NVERTS	= 8
BOX_NEDGES	= 12
HUD_MSG_COL	= 8
HUD_MSG_W	= 24
SAMPLE_MS	= 20
SAMPLE_TA_LO	= $ff			; 20ms * 1024 - 1 = $4FFF
SAMPLE_TA_HI	= $4f
in_fwd		= $CB66			; 16-bit hold ms (IRQ accum)
in_back		= $CB68
in_strafel	= $CB6A
in_strafer	= $CB6C
in_turn_l	= $CB6E
in_turn_r	= $CB70
hold_fwd	= $CB72			; 16-bit snapshots (read_input)
hold_back	= $CB74
hold_strafel	= $CB76
hold_strafer	= $CB78
hold_turn_l	= $CB7A
hold_turn_r	= $CB7C
sw_latched	= $CB7E			; MAP_NSWITCHES (≤8); 1 while held

; Unique world X/Z + 8.8 sin/cos products for xform_mesh_xz (cap 4+4, 8 verts)
UX		= $CB86
UZ		= $CB8A
VY		= $CB8E
XC_L		= $CB96
XC_H		= $CB9A
XS_L		= $CB9E
XS_H		= $CBA2
ZC_L		= $CBA6
ZC_H		= $CBAA
ZS_L		= $CBAE
ZS_H		= $CBB2			; 4 bytes → $CBB2–$CBB5

; Hardware sprite view-model (VIC bank 3)
WPN_RAM		= $C800			; 4 body sprites (256 bytes)
WPN_FLASH	= $C900			; sprite 4 generic / spark / nail L
WPN_FLASH2	= $C940			; sprite 5 nail R
WPN_PTR0	= (WPN_RAM - SCR_A) / 64	; $20
COL_WPN		= 0 			; 
COL_FLASH_Y	= 1			    ; yellow
COL_FLASH_R	= 2			    ; red
WPN_X0		= 160			; 2×2 top-left, visual centre 184
WPN_Y_FLUSH	= 208			; 42px tall, viewport bottom ~250
WPN_Y_AXEIDLE	= 229		; half off: top pair only
WPN_Y_NAILIDLE	= 214
WPN_COL		= 24			; native sprite width
WPN_ROW		= 21			; native sprite height
FLASH_X_C	= 172			; 24px flash centred on visual 184
FLASH_X_NL	= 160			; nail left
FLASH_X_NR	= 184			; nail right
FLASH_DY	= 10			; axe spark vs body top
FLASH_DY_GUN	= 20			; shotgun / grenade muzzle
FLASH_DY_NAIL	= -15			; nail vs weapon top
FLASH_YEL_MS	= 60
FLASH_RED_MS	= 60

; Weapon BSS (after unique-XZ products)
in_fire		= $CBB6
in_wpn_axe	= $CBB7			; 4 bytes: axe shot nail rock
in_wpn_shot	= $CBB8
in_wpn_nail	= $CBB9
in_wpn_rock	= $CBBA
key_fire	= $CBBB
key_wpn_axe	= $CBBC			; 4 bytes
key_wpn_shot	= $CBBD
key_wpn_nail	= $CBBE
key_wpn_rock	= $CBBF
cur_weapon	= $CBC0
wpn_pose	= $CBC1			; POSE_*
fire_rpt_l	= $CBC2
fire_rpt_h	= $CBC3
flash_ms_l	= $CBC4
flash_ms_h	= $CBC5
flash_phase	= $CBC6			; sprite 4: 0 off, 1 yellow, 2 red
mg_frame	= $CBC7
wpn_x		= $CBC8
wpn_y		= $CBC9
spr_en		= $CBCA
anim_step	= $CBCB
anim_ms_l	= $CBCC
anim_ms_h	= $CBCD
wpn_flash_en	= $CBCE
wpn_flash_dy	= $CBCF
wpn_tmp0	= $CBD0
flash5_ms_l	= $CBD1
flash5_ms_h	= $CBD2
flash5_phase	= $CBD3			; sprite 5 (nail right)

; Per-room door view (canonical door_* in map; game uses these at runtime)
door_vx		= $CBD4			; MAP_NDOORS (≤8)
door_vz		= $CBDC
door_vsx	= $CBE4
door_vsz	= $CBEC
door_vface	= $CBF4

; Per-vertex clip data hoisted out of mesh_clip (16 slots each)
VOC		= $CC00			; Cohen–Sutherland outcode (front verts)
VBEHIND		= $CC10			; 1 = z < ZCLIP
VSX		= $CC20			; screen X/Y (front verts with outcode 0)
VSY		= $CC30

; Per-XZ-column project cache (verts sharing x,z share z_eye/inv/PROJ_X)
COL_DONE	= $CC40			; 0 = new, 1 = front cached, 2 = behind
COL_INVL	= $CC50
COL_INVH	= $CC60
COL_INVK	= $CC70
COL_PXL		= $CC80
COL_PXH		= $CC90
