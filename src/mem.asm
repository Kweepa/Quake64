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
VIEW_ROW	= 0
VIEW_W		= 24
VIEW_H		= 16
SCREEN_CX	= 96			; 192px viewport centre
SCREEN_XMAX	= 192
MARGIN_CH	= 192			; col 24 row 0 — solid glyph, not cleared

; PAL text starts at raster 51 (YSCROLL=3). Top 8 char rows → last line 114.
; Plan said "line 100"; hardware mid-window is 114/115.
RASTER_SPLIT	= 114
RASTER_HUD	= 179			; 51 + 128
RASTER_TOP	= 50

D018_A_TOP	= $04			; matrix $C000, charset $D000
D018_A_BOT	= $06			; matrix $C000, charset $D800
D018_B_TOP	= $18			; matrix $C400, charset $E000
D018_B_BOT	= $1A			; matrix $C400, charset $E800
D018_A_UI	= $0C			; matrix $C000, UI charset $F000
D018_B_UI	= $1C			; matrix $C400, UI charset $F000

UI_CHARSET	= $F000
UI_FONT_PAGES	= 8			; 256 glyphs, ASCII-indexed from quakefont.png
HUD_ROW		= 18
HUD_ROW2	= 19
HUD_ROW3	= 21
HUD_COL		= 8
HUD_OFF		= HUD_ROW * 40 + HUD_COL
HUD_OFF2	= HUD_ROW2 * 40 + HUD_COL
HUD_OFF3	= HUD_ROW3 * 40 + HUD_COL
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
PROX_DIST	= 3
MOVE_SPEED	= 2			; 8.8 step scale (asl count after wish)
PLAYER_R	= 1			; XZ collision radius

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
in_fwd		= $CB66
in_back		= $CB67
in_strafel	= $CB68
in_strafer	= $CB69
in_turn_l	= $CB6A
in_turn_r	= $CB6B
in_pitch_u	= $CB6C
in_pitch_d	= $CB6D
