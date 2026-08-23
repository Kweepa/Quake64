; VIC Bank 3 layout — see memorymap.md
; $C000 screen A  $C400 screen B  $C800 weapon sprites
; $CA00 projected verts / clip / game scratch (not displayed)
; $D000/$D800 charset A top/bot  $E000/$E800 charset B top/bot
; Viewport uses charset cols 0–23; col 24 (char 192) is $FF×8 margins.
; Tails (cols 24–31) hold unique log/sin/invz LUTs — not mirrored.
; $F000 UI charset (disk fnt). Judd sqlo..negsqhi at $F800 (disk sqt).
; Game PRG $0900–<$C000.
;
; Boot $0801, menu overlay then game at $0900. Selectors $08FD–$08FF survive.
; $01: $30 = 64K RAM (game / copy_tab). $36 = I/O + KERNAL, BASIC out (init/IRQ).
; $34 is not I/O — PLA gives RAM at $D000 when LORAM=HIRAM=0.
BANK_RAM	= $30
BANK_IO		= $36

LOADER_BASE	= $0801
LOCODE_BASE	= $0900			; MENU overlay, then game
effects_vol	= $08FD			; menu SFX level 0..15 → SID $d418
game_complete	= $08FE
difficulty	= $08FF			; menu skill 0..3
MENU_COPY_TAB	= LOCODE_BASE + 3

; Menu overlay (VIC bank 1). Unused by the game image.
SCREEN		= $4000
SCREEN_B	= $4400
BITMAP		= $6000
BITMAP_SIZE	= 8000
BITMAP_END	= BITMAP + BITMAP_SIZE

TAB_STAGING	= $8000			; tab.prg load; copy_tab unpacks tails
TAB_ALOG	= TAB_STAGING		; 512
TAB_LOG		= TAB_STAGING + 512	; 256
TAB_SIN		= TAB_STAGING + 768	; 320
TAB_INVZL	= TAB_STAGING + 1088	; 128
TAB_INVZH	= TAB_STAGING + 1216	; 128
TAB_BYTES	= 1344

COL_BORDER	= 0
COL_HURT	= 2			; red $d020 flash on damage
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
; View/split: IRQ on the line *before* the last band line, wait for that line,
; delay into the right border / past col 31, then $d018 (and $d021 at HUD→view).
; UI+$d021 black runs in lower flyback after the last text row.
RASTER_TOP	= 251			; flyback after last text line (row 24 ends ~250)
RASTER_VIEW	= 121			; IRQ here; wait for 122, then right-border write
RASTER_VIEW_LINE	= 122		; last HUD scanline (before badline 123)
RASTER_SPLIT	= 185			; IRQ here; wait for 186, then right-border write
RASTER_SPLIT_LINE	= 186		; last top-half scanline (before badline 187)

D018_A_TOP	= $04			; matrix $C000, charset $D000
D018_A_BOT	= $06			; matrix $C000, charset $D800
D018_B_TOP	= $18			; matrix $C400, charset $E000
D018_B_BOT	= $1A			; matrix $C400, charset $E800
D018_A_UI	= $0C			; matrix $C000, UI charset $F000 (HUD band always this)
D018_B_UI	= $1C			; unused — HUD is not flipped with the viewport

UI_CHARSET	= $F000
UI_FONT_PAGES	= 8			; 256 glyphs, ASCII-indexed from quakefont.png
; 40-col HUD (rows 0–8 above VIEW_ROW):
;  0FFF              Quake64
;  1          The Slipgate Complex
;  2                             
;  3        S000   Health  Armour  PU
;  4        N000                   PU
;  5        G000    100     000  Damage
;  7                  trigger message
HUD_ROW		= 0			; frame ms FFF
HUD_ROW_TITLE	= 0			; "Quake64" (same row as FFF)
HUD_ROW_MAP	= 1			; map display name
HUD_ROW2	= 2			; HUD_POS / PROFILE verts
HUD_ROW_SHELL	= 3
HUD_ROW_NAIL	= 4
HUD_ROW_GREN	= 5			; grenades + health / armour values
HUD_ROW4	= 7			; trigger message
HUD_COL		= 0
HUD_OFF		= HUD_ROW * 40 + HUD_COL
HUD_OFF_TITLE	= HUD_ROW_TITLE * 40 + HUD_COL
HUD_OFF_MAP	= HUD_ROW_MAP * 40 + HUD_COL
HUD_OFF2	= HUD_ROW2 * 40 + HUD_COL
HUD_OFF_SHELL	= HUD_ROW_SHELL * 40 + HUD_COL
HUD_OFF_NAIL	= HUD_ROW_NAIL * 40 + HUD_COL
HUD_OFF_GREN	= HUD_ROW_GREN * 40 + HUD_COL
HUD_OFF3	= HUD_OFF2		; PROFILE vertex counts
HUD_OFF4	= HUD_ROW4 * 40 + HUD_COL
HUD_TITLE_COL	= 16
HUD_AMMO_ICON	= 8
HUD_AMMO_NUM	= 9
HUD_HP_LABEL	= 13
HUD_AR_LABEL	= 21
HUD_HP_NUM	= 15
HUD_AR_NUM	= 22
HUD_PU_LABEL = 26
HUD_PU_COL	= 28
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
HUD_CH_QUAD	= $80			; 2×2 powerup tiles (quad/pent/ring)
HUD_CH_PENT	= $84
HUD_CH_RING	= $88
COL_HUD		= 8			; orange digits
COL_HUD_DIM	= 2			; dark red stage letters

; Judd quarter-square (disk sqt @ $F800, page-aligned; mulset_* stores lo only)
; Under KERNAL — multiply only with $01=$30 (same as A-side LUTs).
sqlo		= $F800
sqhi		= $FA00
negsqlo		= $FC00
negsqhi		= $FE00

; Unique charset-tail LUTs. Char 192 ($x600) is $FF×8 in all four halves.
; ALOG is two pages (ALOGHI replaces ALOGTAB+$100). COSTAB = SINTAB+64.
SINTAB		= $D608			; 320 bytes (extra quadrant for COS)
COSTAB		= SINTAB + 64		; $D648
invzl		= $DE08			; 128
ALOGTAB		= $DF00			; 256
invzh		= $E608			; 128
ALOGHI		= $E700			; 256
LOGTAB		= $EF00			; 256

SCR_A		= $C000
SCR_B		= $C400
CH_A_TOP	= $D000
CH_A_BOT	= $D800
CH_B_TOP	= $E000
CH_B_BOT	= $E800
MARGIN_GLYPH	= CH_A_TOP + 24 * 64	; $D600 — char 192, A top

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
EDGE_VIS	= $CAC0			; 32 edge flags (tetromino rooms ≤28)
CLIP_X0		= $CAE0
CLIP_Y0		= $CB00
CLIP_X1		= $CB20
CLIP_Y1		= $CB40
frame_t0	= $CB60			; 4-byte CIA2 cascade snapshot
frame_cy	= $CB64
casc_now	= $CB68

FOCAL		= 100
LOG_FOCAL	= 213			; round(32*log2(100))
NVERTS		= 13
NEDGES		= 13
MESH_MAX_VERTS	= 16			; CAM/PROJ / VOC / COL_* slot count
MESH_MAX_EDGES	= 32			; EDGE_VIS / CLIP_* slot count
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
FALL_LEDGE	= 1			; start fall if feet-floor > this
STEP_UP		= 2			; max walk-up; 2 units plays SOUND_OOF
FALL_TICK_MS	= 32			; gravity cadence (like MOTION_STEP_MS)
FALL_ACCEL	= $10			; 8.8 added to downward vel per tick
FALL_SAFE	= 8			; no damage if eye-drop <= this
FALL_DAMAGE	= 15			; HP on hard landing
HURT_FLASH_MS	= 300			; red border duration
ENEMY_CULL_R	= 2			; view-space |x| vs z+R (8.8 high)
ENEMY_CULL_H	= 6			; view-space |y| vs z+H (figure height)
ENEMY_LOD_Z	= 4			; mid: cheap stick projection (shared)
ENEMY_LOD2_Z	= 40			; far: 8×8 LOD char (shared, grunt ~8px)
ENEMY_MAX		= 16		; MAP_NENEMIES ≤ this
EN_IDLE		= 0
EN_PATROL		= 1
EN_ALERT		= 2
EN_APPROACH		= 3
EN_ATTACK		= 4
EN_PAIN		= 5
EN_DYING		= 6
EN_DEAD		= 7			; last death frame hold
EN_GONE		= 8
ENEMY_DETECT	= 12		; Chebyshev XZ wake distance
ENEMY_STEP_MS	= 200		; approach cell cadence (dt acc + remainder)
PATROL_STEP_MS	= 400		; patrol cell cadence (2× approach; 16-bit)
APPROACH_MIN_MS	= 1500		; min time in approach before attack (grunt)
DOG_REPATH_MS	= 1000		; Rottweiler chase repath cadence (~Wolf DOG_REPATH)
DOG_WAIT_MS	= 2000		; idle pause when player is on another floor piece
DEATH_HOLD_MS	= 1600		; EN_DEAD last-frame hold before EN_GONE
PATROL_MIN	= 6			; min clear cells along a cardinal before walking
PATROL_SCAN	= 32		; max cells probed when picking a patrol point
PATROL_WAIT_MS	= 1000		; idle after arriving; + rnd*4 → ~1–2s
GRUNT_BACKOFF	= 8		; Chebyshev ≤ this → weight dodge away from player
AXE_DMG		= 4			; Quake axe 20 ÷ 5
AXE_HIT_R		= 3			; XZ chebyshev radius for axe hit test
SHOT_DMG_MAX	= 11		; Quake SSG 14×4=56 ÷ 5
SHOT_HIT_X	= 20		; |sx − SCREEN_CX| ≤ this (pixels)
SHOT_Z_MAX	= 32		; view-Z high max range; dmg = SHOT_DMG_MAX − (z>>2), min 1
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

PROC_KIND	= $CB70
PROC_A		= $CB78			; world object id (door_id / elev_id)
PROC_B		= $CB80			; dest / next kind
PROC_C		= $CB88			; timer/accum lo
PROC_D		= $CB90			; timer/accum hi
PROC_E		= $CB98			; elev home return Y
PROC_L		= $CBA0			; local door/elev SoA index
floor_slope	= $CBA8			; 1 if this frame's floor is a ramp
trig_inside	= $CBA9			; trigger SoA index or $ff
hurt_ms_l	= $CBAA			; hurt-trigger cooldown remaining
hurt_ms_h	= $CBAB
vic_border	= $CBAC			; staged $d020 (IRQ)
palette_dirty	= $CBAD			; 1 = IRQ refill viewport colour RAM
flash4_col	= $CBAE			; staged sprite 4 colour
flash5_col	= $CBAF			; staged sprite 5 colour
HURT_MS		= 2000			; hurt trigger period
HURT_HP		= 10			; 10% of PLAYER_HP_MAX

elev_y		= $CBB0			; MAP_NELEVS (≤4)
elev_noise_n	= $CBB4			; refcount: SID V3 rumble while elevs move
proc_tmp0	= $CBB8
proc_tmp1	= $CBB9
proc_tmp2	= $CBBA
proc_tmp3	= $CBBB
proc_tmp4	= $CBBC
proc_tmp5	= $CBBD
MOTION_STEP_MS	= 64
ELEV_STEP_MS	= 128			; half elevator travel speed vs doors
DOOR_RECLOSE_MS	= 5000
ELEV_WAIT_MS	= 5000
STATUS_MS	= 5000			; backpack / status HUD line

; Box / mesh draw
BOX_NVERTS	= 8
BOX_NEDGES	= 12
HUD_MSG_COL	= 0
HUD_MSG_W	= 40
SAMPLE_MS_PAL	= 20			; ms per mid-split tick (50 Hz)
SAMPLE_MS_NTSC	= 17			; ≈1000/60
in_fwd		= $CBBE			; 16-bit hold ms (IRQ accum)
in_back		= $CBC0
in_strafel	= $CBC2
in_strafer	= $CBC4
in_turn_l	= $CBC6
in_turn_r	= $CBC8
hold_fwd	= $CBCA			; 16-bit snapshots (read_input)
hold_back	= $CBCC
hold_strafel	= $CBCE
hold_strafer	= $CBD0
hold_turn_l	= $CBD2
hold_turn_r	= $CBD4
in_use		= $CBD6			; IRQ latch: K pressed
key_use		= $CBD7			; frame snapshot
key_use_was	= $CBD8			; rising-edge debounce
pl_falling	= $CBD9			; 0 grounded, 1 airborne
fall_vl		= $CBDA			; 8.8 downward vel lo
fall_vh		= $CBDB
fall_y0		= $CBDC			; cam_yh when fall started
fall_acc	= $CBDD			; leftover ms toward FALL_TICK_MS

; Unique world X/Z + 8.8 sin/cos products for xform_mesh_xz (6+6 unique, 16 verts)
UX		= $CBDE			; 6 bytes
UZ		= $CBE4
VY		= $CBEA			; 16 bytes (vert Y)
XC_L		= $CBFA			; 6
XC_H		= $CC00
XS_L		= $CC06
XS_H		= $CC0C
ZC_L		= $CC12
ZC_H		= $CC18
ZS_L		= $CC1E
ZS_H		= $CC24			; last byte $CC29

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
FX_N			= 24			; one explosion, 24 pixels
EXPLODE_MS		= 768			; 3×; elapsed/3 then dir>>5 → ~4 units at end
VIEW_SPR_X0	= 24 + VIEW_COL * 8	; 88 — viewport (0,0) → VIC
VIEW_SPR_Y0	= 50 + VIEW_ROW * 8	; 122
EMUZ_OX		= 12			; tip −12 X (center 24px)
EMUZ_OY		= 10			; tip −10 Y (center 21px)
EMUZ_MS		= 100
EMUZ_MSB	= $40			; $d010 / $d015 bit for sprite 6
EMUZ_Z0		= 8			; tip CAM_ZH LOD bands → spr 0..2
EMUZ_Z1		= 16

; Weapon BSS (after unique-XZ products)
in_fire		= $CC2A
in_wpn_axe	= $CC2B			; 4 bytes: axe shot nail gren
in_wpn_shot	= $CC2C
in_wpn_nail	= $CC2D
in_wpn_gren	= $CC2E
key_fire	= $CC2F
key_wpn_axe	= $CC30			; 4 bytes
key_wpn_shot	= $CC31
key_wpn_nail	= $CC32
key_wpn_gren	= $CC33
cur_weapon	= $CC34
wpn_pose	= $CC35			; POSE_*
fire_rpt_l	= $CC36
fire_rpt_h	= $CC37
flash_ms_l	= $CC38
flash_ms_h	= $CC39
flash_phase	= $CC3A			; sprite 4: 0 off, 1 yellow, 2 red
mg_frame	= $CC3B
wpn_x		= $CC3C
wpn_y		= $CC3D
spr_en		= $CC3E
anim_step	= $CC3F
anim_ms_l	= $CC40
anim_ms_h	= $CC41
wpn_flash_en	= $CC42
wpn_flash_dy	= $CC43
wpn_tmp0	= $CC44
flash5_ms_l	= $CC45
flash5_ms_h	= $CC46
flash5_phase	= $CC47			; sprite 5 (nail right)
emuz_ms_l	= $CC48			; enemy muzzle remaining ms
emuz_ms_h	= $CC49
emuz_on		= $CC4A			; 1 = sprite 6 enabled
emuz_xmsb	= $CC4B			; $d010 bit6 when X>=256
item_spin	= $CC4C			; world powerup yaw (0..255)
item_spin_l	= $CC4D			; 8.8 fraction
; $CC4E–$CC5F unused (door view SoA moved to $CE32, 16 slots)

; Per-vertex clip data hoisted out of mesh_clip (16 slots each)
VOC		= $CC60			; Cohen–Sutherland outcode (front verts)
VBEHIND		= $CC70			; 1 = z < ZCLIP
VSX		= $CC80			; screen X/Y (front verts with outcode 0)
VSY		= $CC90

; Per-XZ-column project cache (verts sharing x,z share z_eye/inv/PROJ_X)
COL_DONE	= $CCA0			; 0 = new, 1 = front cached, 2 = behind
COL_INVL	= $CCB0
COL_INVH	= $CCC0
COL_INVK	= $CCD0
COL_PXL		= $CCE0
COL_PXH		= $CCF0

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
PLAYER_ARMOUR_START	= 0
PLAYER_ARMOUR_MAX	= 100
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

ammo_shells	= $CD00
ammo_nails	= $CD01
ammo_grenades	= $CD02
have_wpn	= $CD03			; bitfield HAVE_*
bp_taken	= $CD04			; MAP_NBACKPACKS (≤ BP_MAX)
player_hp	= $CD24			; 0..PLAYER_HP_MAX
player_armour	= $CD25			; 0..PLAYER_ARMOUR_MAX
en_state	= $CD26			; ENEMY_MAX: EN_* 
en_frame	= $CD36			; ENEMY_MAX: local frame in current clip
drop_taken	= $CD46			; ENEMY_MAX: 1=inactive/taken, 0=active
drop_x		= $CD56
drop_y		= $CD66
drop_z		= $CD76
drop_room	= $CD86
drop_type	= $CD96			; BP_* when active
en_hp		= $CDA6			; ENEMY_MAX
en_timer	= $CDB6			; ENEMY_MAX: approach min / dog repath / death hold ms lo
en_timer_h	= $CDC6			; ENEMY_MAX: approach min / dog repath / death hold ms hi
en_step		= $CDD6			; ENEMY_MAX: walk acc lo
en_step_h	= $CDE6			; ENEMY_MAX: walk acc hi
en_dir		= $CDF6			; ENEMY_MAX: 0..7 dodge facing
gunshot_wake	= $CE06			; 1 = gun fired this frame (room wake)
ai_dirtry	= $CE07			; 5 bytes dodge dir candidates
ai_turn		= $CE0C			; turnaround dir or $ff
ai_probe	= $CE0D			; dir under test (probe must not clobber)
emuz_vx		= $CE0E			; VIC X lo staged (IRQ apply_en)
emuz_vy		= $CE0F			; VIC Y staged
emuz_col		= $CE10			; sprite colour staged from col_fx
emuz_pending	= $CE11			; enemy idx waiting to muzzle, $ff = none
emuz_skip	= $CE12			; 1 = skip next tick (spawn frame; dt ~150ms > 100ms)
splat_ms_l	= $CE13			; impact splat remaining ms
splat_ms_h	= $CE14
splat_on		= $CE15			; 1 = sprite 7 enabled
splat_xmsb	= $CE16			; $d010 bit7 when X>=256
splat_vx		= $CE17
splat_vy		= $CE18
splat_col	= $CE19			; COL_SPLAT_HIT or col_line (miss)
splat_skip	= $CE1A			; 1 = skip next tick (spawn frame)
shot_hit_i	= $CE1B			; closest SSG hit enemy, $ff = miss
shot_hit_z	= $CE1C			; CAM_ZH of that hit
hurt_flash_l	= $CE1D			; remaining red-border ms
hurt_flash_h	= $CE1E
bite_splat_i	= $CE1F			; dog idx pending blood splat, $ff = none
status_ms_l	= $CE20			; status HUD remaining ms
status_ms_h	= $CE21

; Door runtime SoA — 16 slots (map had 11; 8 overflowed into VOC / door 0)
DOOR_MAX	= 16
door_open	= $CE22			; MAP_NDOORS (≤ DOOR_MAX)
door_vx		= $CE32			; oriented AABB (canonical door_* in map)
door_vz		= $CE42
door_vsx	= $CE52
door_vsz	= $CE62
door_vface	= $CE72			; last byte $CE81
en_pat_n	= $CE82			; ENEMY_MAX: patrol remaining cells
have_keys	= $CE92			; HAVE_SILVER / HAVE_GOLD
pu_kind		= $CE93			; 0 or BP_QUAD / BP_PENT / BP_RING
pu_ms_l		= $CE94
pu_ms_h		= $CE95
fx_on		= $CE96			; 1 = explosion live
fx_ms_l		= $CE97			; remaining ms
fx_ms_h		= $CE98
fx_ox		= $CE99			; world origin (int)
fx_oy		= $CE9A
fx_oz		= $CE9B
fx_skip		= $CE9C			; 1 = skip next tick (spawn frame)
en_pain_i	= $CE9D			; ENEMY_MAX: pain/death variant index
HAVE_SILVER	= 1
HAVE_GOLD	= 2
POWERUP_MS	= 30000
