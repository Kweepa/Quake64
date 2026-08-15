; VIC Bank 3 layout (c64_quake_architecture.md)
; $C000 screen A  $C400 screen B
; $CA00 projected verts / CIA2 profiler (not displayed)
; $D000/$D800 charset A top/bot  $E000/$E800 charset B top/bot
; $F800 log / alog / sin / cos LUTs (copied at init)

COL_BORDER	= 0
COL_BG		= 9			; brown sandbox
COL_HUD_BG	= 0
COL_LINE	= 7			; orange vectors
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
HUD_COL		= 8
HUD_OFF		= HUD_ROW * 40 + HUD_COL
HUD_CH_SP	= $20			; ASCII space / digits / letters in UI charset
HUD_CH_C	= $43
HUD_CH_R	= $52
HUD_CH_P	= $50
HUD_CH_K	= $4b
HUD_CH_D	= $44
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

PROJ_X		= $CA00
PROJ_Y		= $CA08
PROJ_Z		= $CA20			; per-vertex z_eye
frame_t0	= $CA10			; 4-byte CIA2 cascade snapshot
frame_cy	= $CA14
casc_now	= $CA18
CAM_X		= $CA28			; camera-space after rotate
CAM_Y		= $CA30
CAM_Z		= $CA38
EDGE_VIS	= $CA40			; 12 bytes, 1 = both endpoints passed ZCLIP

FOCAL		= 100
LOG_FOCAL	= 213			; round(32*log2(100))
CAMZ		= 160
CUBE_H		= 32
YAW_STEP	= 3
PERSP_MAX	= 80
ZCLIP		= 72
