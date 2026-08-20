; VIC Bank 3 layout (c64_quake_architecture.md)
; $C000 screen A  $C400 screen B
; $CA00 projected verts / CIA2 profiler (not displayed)
; $D000/$D800 charset A top/bot  $E000/$E800 charset B top/bot
; $F800 log/alog/sin/cos (copied at init). Judd sqlo/sqhi live in the PRG.

COL_BORDER	= 0
COL_BG		= 9			; default viewport background (brown)
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
HUD_CH_SHELL	= $7b			; { → shell icon
HUD_CH_NAIL	= $7c			; | → nail icon
HUD_CH_GREN	= $7d			; } → grenade icon
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
ANIM_MS		= 100			; walk step interval (ms)
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
ENEMY_LOD_Z	= 4			; mid: cheap stick projection (shared)
ENEMY_LOD2_Z	= 40			; far: 8×8 LOD char (shared, grunt ~8px)
ENEMY_MAX		= 16		; MAP_NENEMIES ≤ this
EN_IDLE		= 0
EN_ALERT		= 1
EN_APPROACH		= 2
EN_ATTACK		= 3
EN_PAIN		= 4
EN_DYING		= 5
EN_GONE		= 6
ENEMY_DETECT	= 12		; Chebyshev XZ wake distance
ENEMY_STEP_MS	= 200		; approach cell cadence (dt acc + remainder)
APPROACH_MIN_MS	= 1500		; min time in approach before attack (grunt)
DOG_REPATH_MS	= 1000		; Rottweiler chase repath cadence (~Wolf DOG_REPATH)
GRUNT_BACKOFF	= 8		; Chebyshev ≤ this → weight dodge away from player
AXE_DMG		= 4			; Quake axe 20 ÷ 5
AXE_HIT_R		= 3			; XZ chebyshev radius for axe hit test
SHOT_DMG_MAX	= 11		; Quake SSG 14×4=56 ÷ 5
SHOT_HIT_X	= 20		; |sx − SCREEN_CX| ≤ this (pixels)
SHOT_Z_MAX	= 16		; view-Z high: dmg ∝ (SHOT_Z_MAX − z) / SHOT_Z_MAX (÷16 = lsr×4)
SHOT_MID_H	= 3			; mid-body Y above feet (≈ ENEMY_CULL_H/2)
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
PROC_A		= $CB28			; world object id (door_id / elev_id)
PROC_B		= $CB30			; dest / next kind
PROC_C		= $CB38			; timer/accum lo
PROC_D		= $CB40			; timer/accum hi
PROC_E		= $CB48			; elev home return Y
PROC_L		= $CB50			; local door/elev SoA index

door_open	= $CB58			; MAP_NDOORS (≤8)
elev_y		= $CB60			; MAP_NELEVS (≤4)
elev_noise_n	= $CB64			; refcount: SID V3 rumble while elevs move
proc_tmp0	= $CB68
proc_tmp1	= $CB69
proc_tmp2	= $CB6A
proc_tmp3	= $CB6B
proc_tmp4	= $CB6C
proc_tmp5	= $CB6D
MOTION_STEP_MS	= 64
ELEV_STEP_MS	= 128			; half elevator travel speed vs doors
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
in_fwd		= $CB6E			; 16-bit hold ms (IRQ accum)
in_back		= $CB70
in_strafel	= $CB72
in_strafer	= $CB74
in_turn_l	= $CB76
in_turn_r	= $CB78
hold_fwd	= $CB7A			; 16-bit snapshots (read_input)
hold_back	= $CB7C
hold_strafel	= $CB7E
hold_strafer	= $CB80
hold_turn_l	= $CB82
hold_turn_r	= $CB84
in_use		= $CB86			; IRQ latch: K pressed
key_use		= $CB87			; frame snapshot
key_use_was	= $CB88			; rising-edge debounce
; $CB89–$CB8D free (was sw_latched)

; Unique world X/Z + 8.8 sin/cos products for xform_mesh_xz (cap 4+4, 8 verts)
UX		= $CB8E
UZ		= $CB92
VY		= $CB96
XC_L		= $CB9E
XC_H		= $CBA2
XS_L		= $CBA6
XS_H		= $CBAA
ZC_L		= $CBAE
ZC_H		= $CBB2
ZS_L		= $CBB6
ZS_H		= $CBBA			; 4 bytes → $CBBA–$CBBD

; Hardware sprite view-model (VIC bank 3)
WPN_RAM		= $C800			; 4 body sprites (256 bytes)
WPN_FLASH	= $C900			; sprite 4 generic / spark / nail L
WPN_FLASH2	= $C940			; sprite 5 nail R
WPN_EMUZ	= $C980			; sprite 6 enemy muzzle (one at a time)
WPN_SPLAT	= $C9C0			; sprite 7 impact splat (hit/miss)
WPN_PTR0	= (WPN_RAM - SCR_A) / 64	; $20
WPN_PTR_EMUZ	= (WPN_EMUZ - SCR_A) / 64	; $26
WPN_PTR_SPLAT	= (WPN_SPLAT - SCR_A) / 64	; $27
COL_WPN		= 0 			; default weapon colour (room_wpn / col_wpn)
COL_FLASH_Y	= 1			    ; yellow
COL_FLASH_R	= 2			    ; red
COL_SPLAT_HIT	= 2			; red (blood) (DO NOT CHANGE BACK TO PINK!)
SPLAT_MSB	= $80			; $d010 / $d015 bit for sprite 7
WPN_X0		= 160			; 2×2 top-left, visual centre 184
WPN_Y_FLUSH	= 208			; 42px tall, viewport bottom ~250
WPN_Y_SHOTIDLE	= 218		; shotgun: 10px below WPN_Y_FLUSH
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
SPLAT_MS		= FLASH_YEL_MS + FLASH_RED_MS	; same total as muzzle flash
VIEW_SPR_X0	= 24 + VIEW_COL * 8	; 88 — viewport (0,0) → VIC
VIEW_SPR_Y0	= 50 + VIEW_ROW * 8	; 122
EMUZ_OX		= 12			; tip −12 X (center 24px)
EMUZ_OY		= 10			; tip −10 Y (center 21px)
EMUZ_MS		= 100
EMUZ_MSB	= $40			; $d010 / $d015 bit for sprite 6
EMUZ_Z0		= 8			; tip CAM_ZH LOD bands → spr 0..2
EMUZ_Z1		= 16

; Weapon BSS (after unique-XZ products)
in_fire		= $CBBE
in_wpn_axe	= $CBBF			; 4 bytes: axe shot nail gren
in_wpn_shot	= $CBC0
in_wpn_nail	= $CBC1
in_wpn_gren	= $CBC2
key_fire	= $CBC3
key_wpn_axe	= $CBC4			; 4 bytes
key_wpn_shot	= $CBC5
key_wpn_nail	= $CBC6
key_wpn_gren	= $CBC7
cur_weapon	= $CBC8
wpn_pose	= $CBC9			; POSE_*
fire_rpt_l	= $CBCA
fire_rpt_h	= $CBCB
flash_ms_l	= $CBCC
flash_ms_h	= $CBCD
flash_phase	= $CBCE			; sprite 4: 0 off, 1 yellow, 2 red
mg_frame	= $CBCF
wpn_x		= $CBD0
wpn_y		= $CBD1
spr_en		= $CBD2
anim_step	= $CBD3
anim_ms_l	= $CBD4
anim_ms_h	= $CBD5
wpn_flash_en	= $CBD6
wpn_flash_dy	= $CBD7
wpn_tmp0	= $CBD8
flash5_ms_l	= $CBD9
flash5_ms_h	= $CBDA
flash5_phase	= $CBDB			; sprite 5 (nail right)
emuz_ms_l	= $CBDC			; enemy muzzle remaining ms
emuz_ms_h	= $CBDD
emuz_on		= $CBDE			; 1 = sprite 6 enabled
emuz_xmsb	= $CBDF			; $d010 bit6 when X>=256

; Per-room door view (canonical door_* in map; game uses these at runtime)
door_vx		= $CBE0			; MAP_NDOORS (≤8)
door_vz		= $CBE8
door_vsx	= $CBF0
door_vsz	= $CBF8
door_vface	= $CC00

; Per-vertex clip data hoisted out of mesh_clip (16 slots each)
VOC		= $CC08			; Cohen–Sutherland outcode (front verts)
VBEHIND		= $CC18			; 1 = z < ZCLIP
VSX		= $CC28			; screen X/Y (front verts with outcode 0)
VSY		= $CC38

; Per-XZ-column project cache (verts sharing x,z share z_eye/inv/PROJ_X)
COL_DONE	= $CC48			; 0 = new, 1 = front cached, 2 = behind
COL_INVL	= $CC58
COL_INVH	= $CC68
COL_INVK	= $CC78
COL_PXL		= $CC88
COL_PXH		= $CC98

; Player inventory + backpack taken flags (after project cache)
AMMO_SHELLS_MAX		= 100
AMMO_NAILS_MAX		= 200
AMMO_GRENADES_MAX	= 100
AMMO_SHELLS_BOX		= 20
AMMO_SHELLS_DEATH	= 5			; grunt death backpack
AMMO_NAILS_BOX		= 25
AMMO_GRENADES_BOX	= 5
AMMO_NAILS_GUN		= 30
AMMO_GRENADES_GUN	= 5
AMMO_SHELLS_START	= 25
PLAYER_HP_MAX		= 100
PLAYER_HP_START		= 100
HP_PACK_25		= 25
HP_PACK_50		= 50
BP_FOOT_SX		= 2			; AABB around equilateral-ish base
BP_FOOT_SZ		= 2
BP_FOOT_SY		= 2			; ≈ 1.5 tall (C64 int)
BP_MAX			= 32		; MAP_NBACKPACKS ≤ this

HAVE_AXE	= 1
HAVE_SHOT	= 2
HAVE_NAIL	= 4
HAVE_GREN	= 8
HAVE_START	= HAVE_AXE | HAVE_SHOT

WPN_AXE		= 0
WPN_SHOT	= 1
WPN_NAIL	= 2
WPN_GREN	= 3

ammo_shells	= $CCA8
ammo_nails	= $CCA9
ammo_grenades	= $CCAA
have_wpn	= $CCAB			; bitfield HAVE_*
bp_taken	= $CCAC			; MAP_NBACKPACKS (≤ BP_MAX)
player_hp	= $CCCC			; 0..PLAYER_HP_MAX
en_state	= $CCCE			; ENEMY_MAX: EN_* 
en_frame	= $CCDE			; ENEMY_MAX: local frame in current clip
drop_taken	= $CCEE			; ENEMY_MAX: 1=inactive/taken, 0=active
drop_x		= $CCFE
drop_y		= $CD0E
drop_z		= $CD1E
drop_room	= $CD2E
drop_type	= $CD3E			; BP_* when active
en_hp		= $CD4E			; ENEMY_MAX
en_timer	= $CD5E			; ENEMY_MAX: approach min / dog repath ms lo
en_timer_h	= $CD6E			; ENEMY_MAX: approach min / dog repath ms hi
en_step		= $CD7E			; ENEMY_MAX: walk acc lo
en_step_h	= $CD8E			; ENEMY_MAX: walk acc hi
en_dir		= $CD9E			; ENEMY_MAX: 0..7 dodge facing
gunshot_wake	= $CDAE			; 1 = gun fired this frame (room wake)
ai_dirtry	= $CDAF			; 5 bytes dodge dir candidates
ai_turn		= $CDB4			; turnaround dir or $ff
ai_probe	= $CDB5			; dir under test (probe must not clobber)
emuz_vx		= $CDB6			; VIC X lo staged (poke in apply_en; draw is $01=$34)
emuz_vy		= $CDB7			; VIC Y staged
emuz_col		= $CDB8			; sprite colour staged from col_fx
emuz_pending	= $CDB9			; enemy idx waiting to muzzle, $ff = none
emuz_skip	= $CDBA			; 1 = skip next tick (spawn frame; dt ~150ms > 100ms)
splat_ms_l	= $CDBB			; impact splat remaining ms
splat_ms_h	= $CDBC
splat_on		= $CDBD			; 1 = sprite 7 enabled
splat_xmsb	= $CDBE			; $d010 bit7 when X>=256
splat_vx		= $CDBF
splat_vy		= $CDC0
splat_col	= $CDC1			; COL_SPLAT_HIT or col_line (miss)
splat_skip	= $CDC2			; 1 = skip next tick (spawn frame)
shot_hit_i	= $CDC3			; closest SSG hit enemy, $ff = miss
shot_hit_z	= $CDC4			; CAM_ZH of that hit
bite_splat_i	= $CDC7			; dog idx pending blood splat, $ff = none
