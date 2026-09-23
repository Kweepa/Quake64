; VIC Bank 3 layout — see memorymap.md
; $C000 screen A  $C400 screen B  $C800 weapon sprites
; $CA00 projected verts / clip / game scratch (not displayed)
; $D000/$D800 charset A top/bot  $E000/$E800 charset B top/bot
; Viewport uses charset cols 0–23; col 24 (char 192) is $FF×8 margins.
; Tails (cols 24–31) hold unique log/sin/invz LUTs — not mirrored.
; $F000 Judd sqlo..negsqhi (disk sqt). $F800 UI charset (disk fnt).
; Game PRG $0900–<$C000. Heap grows down from $C000 (map with bind/reloc prefix, poses).
; $FFFA–$FFFF overlay unused UI char 255 (init_irq).
;
; Boot $0801: koala cover (splashc/splash), then menu overlay, then game at $0900.
; Survives GAME load: reboot stub $08F9, level_num $08FC, selectors $08FD–$08FF.
; $01: $30 = 64K RAM (game / copy_tab). $36 = I/O + KERNAL, BASIC out (init/IRQ).
; $34 is not I/O — PLA gives RAM at $D000 when LORAM=HIRAM=0.
BANK_RAM	= $30
BANK_IO		= $36
; $35 = I/O in, KERNAL ROM out. Needed to execute the Krill resident, which
; lives at $EE08 under the KERNAL. BASIC comes in at $A000 as a side effect;
; harmless, the loader only writes to the destination. MUST be entered under
; SEI — with the KERNAL out the IRQ vector comes from RAM at $FFFE.
BANK_LOADER	= $35

; --- Krill fastloader (v194, LOAD_TO_API=1, UNINSTALL_API=0) ---------------
; Resident lives in the 248-byte gap between the charset B bottom margin glyph
; ($EE00-$EE07, written by copy_tab) and LOGTAB ($EF00). 236 B, 12 B spare.
; -DUSE_KRILL=1: loadraw at $EE08. Default 0: KERNAL LOAD ($FFD5).
; Play BSS is $CD00–$CFBA. Do not park Krill there; resident is $EE08.
; see mem.asm's own "$CFBB+ free" below.
!ifndef USE_KRILL {
	USE_KRILL = 0
}
KRILL_RESIDENT	= $EE08
KRILL_INSTALL	= $2000			; transient; MENU/GAME overwrite it after use
!if USE_KRILL {
	!source "../krill/loadersymbols-c64.inc"
	!if loadraw != KRILL_RESIDENT {
		!error "Krill loadraw is not KRILL_RESIDENT $EE08"
	}
} else {
	; Hole reserved on the KERNAL disk; do not alias loadraw.
	loadaddrlo	= $60
	loadaddrhi	= $61
}
; Krill's zeropage. $60/$61 double as dlo/dhi (line-draw scratch, dead across a
; load); $60-$64 must not be written while a load is in flight.

LOADER_BASE	= $0801
LOCODE_BASE	= $0900			; MENU overlay, then game
REBOOT_STUB	= $08F9			; 3-byte JMP reboot_game (installed at start)
level_num	= $08FC			; 1..8 → e1m1..e1m8
effects_vol	= $08FD			; menu SFX level 0..15 → SID $d418
game_complete	= $08FE
difficulty	= $08FF			; menu skill 0..3
MENU_COPY_TAB	= LOCODE_BASE + 3

; Menu overlay (VIC bank 1). Unused by the game image.
; Matrix + sprites pack under bitmap so menu PRG can grow past $4000.
VIC_BANK1	= $4000
SCREEN		= $5C00			; colour matrix (was $4000)
BITMAP		= $6000
BITMAP_SIZE	= 8000
BITMAP_END	= BITMAP + BITMAP_SIZE
; Boot splash: koala split. splashc stages matrix+colour at $4000; do_splash
; copies matrix → SCREEN and colour → $D800 so MENU can grow past $4000
; without flashing the cover. Bitmap $6000, same as menu.
SPLASH_MAT	= VIC_BANK1		; $4000 staging
SPLASH_COL	= SPLASH_MAT + 1000	; $43E8
SPLASH_COL_SIZE	= 1000
SPLASH_BG	= SPLASH_COL + SPLASH_COL_SIZE	; $47D0
do_splash	= SPLASH_BG + 1		; $47D1 — helpers ride on splashc.prg tail
KOALA_COL_RAM	= $d800
KOALA_TAIL	= 1000 - 768		; 232
!if SPLASH_BG + 1 > BITMAP {
	!error "splash colour staging overlaps bitmap; bg=$", SPLASH_BG
}

TAB_STAGING	= $8000			; tab.prg load; copy_tab unpacks tails
TAB_ALOG	= TAB_STAGING		; 512
TAB_LOG		= TAB_STAGING + 512	; 256
TAB_SIN		= TAB_STAGING + 768	; 320
TAB_INVZL	= TAB_STAGING + 1088	; 128
TAB_INVZH	= TAB_STAGING + 1216	; 128
TAB_BYTES	= 1344

COL_BORDER	= 0
COL_WHITE	= 1			; sample_ms tripwire latch
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
D018_A_UI	= $0E			; matrix $C000, UI charset $F800 (HUD band always this)
D018_B_UI	= $1E			; unused — HUD is not flipped with the viewport

UI_CHARSET	= $F800
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
HUD_CH_QUAD	= $00			; 2×2 powerup tiles in $00–$1E (quad/pent/ring)
HUD_CH_PENT	= $04
HUD_CH_RING	= $08
COL_HUD		= 8			; orange digits
COL_HUD_DIM	= 2			; dark red stage letters

; Judd quarter-square (disk sqt @ $F000, page-aligned; mulset_* stores lo only)
; Under KERNAL — multiply only with $01=$30 (same as A-side LUTs).
sqlo		= $F000
sqhi		= $F200
negsqlo		= $F400
negsqhi		= $F600

; SMC map accessors: macros emit abs,x/y with this operand hi until LoadLevel
; patches from the map-file reloc prefix. Must not collide with a real GAME abs.
MAP_SMC_HI	= $02
MAP_SMC_BASE	= $0200
!if (>MAP_SMC_BASE) != MAP_SMC_HI {
	!error "MAP_SMC_BASE hi must equal MAP_SMC_HI"
}

; Play BSS: default VIC matrix / leftover boot. VIC matrix in play is $C000.
; map_bss.asm occupies $0400–$0523. $08F9–$08FF is reboot stub + selectors.
FRAME13_N	= 106			; offsets 0..105
ENEMY_PTR_N	= 8			; must == ENEMY_NTYPES (quake64.asm asserts)
frame13_lo	= $0524
frame13_hi	= $058E
enemy_gx_lo	= $05F8
enemy_gx_hi	= enemy_gx_lo + ENEMY_PTR_N
enemy_gy_lo	= enemy_gx_hi + ENEMY_PTR_N
enemy_gy_hi	= enemy_gy_lo + ENEMY_PTR_N
enemy_gz_lo	= enemy_gy_hi + ENEMY_PTR_N
enemy_gz_hi	= enemy_gz_lo + ENEMY_PTR_N
box_vis_edges	= enemy_gz_hi + ENEMY_PTR_N	; 24
box_vis_vert	= box_vis_edges + 24		; 12
room_pack_edges	= box_vis_vert + 12		; 64
room_pack_vert	= room_pack_edges + 64		; 32
pose_gx		= room_pack_vert + 32		; 13 — lerp scratch (ent_set_pose)
pose_gy		= pose_gx + 13
pose_gz		= pose_gy + 13
pose_map_lo	= pose_gz + 13			; patched at pose load (logical → packed)
pose_map_hi	= pose_map_lo + ENEMY_PTR_N
enemy_sfx_evt_lo	= pose_map_hi + ENEMY_PTR_N	; clip event table on pose heap
enemy_sfx_evt_hi	= enemy_sfx_evt_lo + ENEMY_PTR_N
en_sfx_old	= enemy_sfx_evt_hi + ENEMY_PTR_N	; local frame before this anim step
en_sfx_new	= en_sfx_old + 1		; logical frame after the step
en_sfx_n	= en_sfx_new + 1		; remaining events while scanning
en_sfx_armed	= en_sfx_n + 1			; 1 = frame changed this anim step
; next free en_sfx_armed + 1  ($06F7)
ENEMY_DATA_BASE	= $06F7			; boot-loaded immutable enemy_data_blob.asm
!if ENEMY_DATA_BASE <= en_sfx_armed {
	!error "Enemy metadata overlaps play BSS"
}
AI_ENTRY_LO	= $0876			; streamed AI entry pointer per enemy type
AI_ENTRY_HI	= $087E
ENEMY_DATA_LIMIT	= AI_ENTRY_LO
AI_BANK_LO	= $0886			; base of complete fused bank per type
AI_BANK_HI	= $088E
AI_LOW_END	= $0896
; Crusher SoA pointers + tiny play scratch. Not in $0400 — that table
; ends at frame13_lo. Access via lda_cy/sta_cy (mp_l),y.
crush_x		= AI_LOW_END
crush_y		= crush_x + 2
crush_z		= crush_y + 2
crush_sx	= crush_z + 2
crush_sy	= crush_sx + 2
crush_sz	= crush_sy + 2
crush_home	= crush_sz + 2
crush_dest	= crush_home + 2
crush_face	= crush_dest + 2
crush_dir	= crush_face + 2		; live sign $01 / $FF
crush_room	= crush_dir + 2
crush_entry_lo	= crush_room + 2
crush_entry_hi	= crush_entry_lo + 1
crush_need	= crush_entry_hi + 1	; 1 = current room owns a crusher
crush_skip	= crush_need + 1	; $ff none, else SoA index for pos_ok
crush_st	= crush_skip + 1	; sta_cy scratch
crush_acc_l	= crush_st + 1
crush_acc_h	= crush_acc_l + 1
crush_i		= crush_acc_h + 1
crush_lo	= crush_i + 1		; min(home,dest) while stepping
crush_hi	= crush_lo + 1
CRUSH_BSS_END	= crush_hi + 1
; Custom-skeleton runtime. skel_base = 0 means the shared 13-vert stick.
; A bound prefix with skel_nv = 0 is an empty graph and draws nothing.
skel_nv		= CRUSH_BSS_END			; ENEMY_PTR_N
skel_ne		= skel_nv + ENEMY_PTR_N
skel_base_lo	= skel_ne + ENEMY_PTR_N		; pose prefix in the bank
skel_base_hi	= skel_base_lo + ENEMY_PTR_N
skel_mul_n	= skel_base_hi + ENEMY_PTR_N
skel_entry_lo	= skel_mul_n + 1		; streamed draw/lerp entry
skel_entry_hi	= skel_entry_lo + ENEMY_PTR_N
SKEL_BSS_END	= skel_entry_hi + ENEMY_PTR_N
!if CRUSH_BSS_END > REBOOT_STUB {
	!error "crusher BSS overlaps reboot stub"
}
!if SKEL_BSS_END > REBOOT_STUB {
	!error "skeleton BSS overlaps reboot stub"
}

SKEL_MAX_VERTS	= 48
SKEL_MAX_EDGES	= 64
SKEL_PFX	= 7			; size.w, nv, ne, entry.w, shift; baked batches follow
SKEL_PFX_SHIFT	= 6			; pose coords stored as v >> shift

AI_BANK_MAGIC0	= 'Q'
AI_BANK_MAGIC1	= 'A'
AI_BANK_MAGIC2	= 'I'
AI_BANK_MAGIC3	= '1'
AIH_CODE_SIZE	= 4
AIH_RELOC_N	= 6
AIH_MAP_N	= 8
AIH_ENTRY	= 10
AIH_POSE_OFF	= 12
AIH_FLAGS	= 14
AIH_SIZE	= 15
AI_LINK_BASE	= $A000
AI_CMD_ATTACK_TICK	= 0
AI_CMD_FIRE		= 1
AI_CMD_ATTACK_END	= 2
AI_CMD_DYING_STEP	= 3
AI_CMD_APPROACH_MOVE	= 4
AI_CMD_APPROACH_ATTACK	= 5
AI_CMD_APPROACH_ENTER	= 6
AI_CMD_IDLE		= 7
CRUSH_CMD_TICK		= 0
CRUSH_CMD_SOLID		= 1
CRUSH_CMD_DRAW		= 2
AI_AP_MOVE		= 0
AI_AP_STAND		= 1
AI_AP_NEXT		= 2

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
DOOR_Y_SLACK	= 1			; |feet − door_y| to fire a wish-through
MOVE_SPEED	= 2			; 8.8 step scale (asl count after wish)
PLAYER_R	= 1			; XZ collision radius
ENEMY_BLOCK_R	= 1			; XZ Chebyshev vs player (same cell + neighbors)
FALL_LEDGE	= 1			; start fall if feet-floor > this
STEP_UP		= 2			; max walk-up; 2 units plays SOUND_PLAYER_LAND
FALL_TICK_MS	= 32			; gravity cadence (like MOTION_STEP_MS)
FALL_ACCEL	= $10			; 8.8 added to downward vel per tick
FALL_SAFE	= 8			; no damage if eye-drop <= this
FALL_DAMAGE	= 15			; HP on hard landing
HURT_FLASH_MS	= 300			; red border duration
ENEMY_CULL_R	= 2			; view-space |x| vs z+R (8.8 high)
ENEMY_CULL_H	= 6			; view-space |y| vs z+H (figure height)
ENEMY_MAX		= 24		; MAP_NENEMIES ≤ this
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
SCRAG_HOLD_R	= 12		; Chebyshev ≤ this + LOS → stop closing, spit
SCRAG_REFIRE_MS	= 2000		; Q1 wiz_fast14 SUB_AttackFinished(2)
OGRE_MELEE_R	= 6		; chainsaw Chebyshev; grenade uses enemy_range
OGRE_SWING_FIRE	= 4		; clip-local hit; shoot uses enemy_fire_frame
OGRE_SAW_DMG	= 6		; 6–9 with rnd&3
KNIGHT_SLASH_DMG	= 4		; 4–7 with rnd&3 (Quake ai_melee *3 vs ogre *4)
KNIGHT_RUNATK_FIRE	= 5		; runattack clip-local hit (0-indexed)
KNIGHT_ATKB_FIRE	= 7		; attackb clip-local hit (0-indexed)
ZOMBIE_STEP_MS	= 400		; slow walk; 2× grunt approach cadence
ZOMBIE_HOLD_FRAME	= 10		; paine local frame held while down
ZOMBIE_DOWN_BASE	= 50		; anim ticks at 10 before get-up (~5s)
FLESH_DMG		= 10		; Quake zombie missile 10 (player HP 100)
AXE_DMG		= 4			; Quake axe 20 ÷ 5
AXE_HIT_R		= 3			; XZ chebyshev radius for axe hit test
SHOT_DMG_MAX	= 11		; Quake SSG 14×4=56 ÷ 5
SHOT_HIT_X	= 20		; |sx − SCREEN_CX| ≤ this (pixels)
SHOT_Z_MAX	= 32		; view-Z high max range; dmg = SHOT_DMG_MAX − (z>>2), min 1
SHOT_MID_H	= 3			; mid-body Y above feet (≈ ENEMY_CULL_H/2)
NAIL_DMG_MAX	= 2			; Quake nail 9 ÷ 5
NAIL_HIT_X	= 6			; |sx − SCREEN_CX| ≤ this (pixels)

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
trig_inside	= $CBA9			; occupancy bits, Nth same-room trigger
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
CRUSH_STEP_MS	= 512			; 1/4 elevator travel (4× ELEV_STEP_MS)
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
WPN_PTR_FLASH	= (WPN_FLASH - SCR_A) / 64	; $24
WPN_PTR_FLASH2	= (WPN_FLASH2 - SCR_A) / 64	; $25
WPN_PTR_EMUZ	= (WPN_EMUZ - SCR_A) / 64	; $26
WPN_PTR_SPLAT	= (WPN_SPLAT - SCR_A) / 64	; $27
FLASH_EN_L	= $10			; $d015 sprite 4
FLASH_EN_R	= $20			; $d015 sprite 5
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
EXPLODE_MS		= 768			; ~3× frame budget for particle expand
FX_START_MS		= 100			; spawn elapsed head-start (skip origin speck)
FX_VEL_SPEED		= 32			; (dir*speed)>>7 → ~±31 into 8.8
GREN_MAX		= 4
GREN_OWN_PL		= 0
GREN_OWN_EN		= 1
GREN_F_BOUNCE		= 1			; fuse running
GREN_F_PEND		= 2			; waiting on fx_on
GREN_F_FLESH		= 4			; zombie chunk: no bounce/explode
GREN_F_LAVA		= 8			; straight flight, burst on contact
GREN_TICK_MS		= 32
GREN_FLOOR_XZ_ASR	= 1			; /2 XZ per floor hop
GREN_GRAV		= $01EC			; 60 u/s² × 32ms as 8.8
GREN_SPEED		= 30			; horizontal
GREN_SPEED_Y		= 10		; upward (was 20; ~22° not 45°)
GREN_FUSE_MS		= 2000
GREN_LIFE_MS		= 5000
GREN_DMG_MAX		= 24		; Quake 120 ÷ 5
GREN_RAD		= 6
GREN_HIT_R		= 1
GREN_WRIST_L		= 5			; skeleton "Wrist L"
GREN_HW			= $40			; tail half-width 0.25
GREN_VEL_ASR		= 5			; tip = view-vel >> 5
; Scrag spit — tracer + delayed hitscan
SPIT_DMG		= 9			; Quake wizard spike (unscaled; player HP is 100)
SPIT_HIT_R		= 1
SPIT_TIP_VERT		= 12			; muzzle tip bone
SPIT_LEN		= 16			; tracer Chebyshev length toward player
SPIT_FLASH_N		= 2			; draw frames of frozen segment
VIEW_SPR_X0	= 24 + VIEW_COL * 8	; 88 — viewport (0,0) → VIC
VIEW_SPR_Y0	= 50 + VIEW_ROW * 8	; 122
SPLAT_INSET_X	= 24		; melee cue never on viewport edge (0..191)
SPLAT_INSET_Y	= 16		; 0..127
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
; $CC38–$CC3A free (was flash4 timer)
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
ws_slot		= $CC45			; WS_EMUZ / WS_SPLAT during start_world_spr
; Pose stream scratch (was flash5 timer + emuz on/ms)
need0		= $CC46			; type id or $FF
need1		= $CC47			; type id or $FF
pose_dump	= $CC48			; type being dumped
pose_keep	= $CC49			; surviving type while dumping ($FF = none)
load_device	= $CC4A			; IEC device (KERNAL $ba is not ours during play)
emuz_xmsb	= $CC4B			; $d010 bit6 when X>=256
item_spin	= $CC4C			; world pickup yaw (0..255)
item_spin_l	= $CC4D			; 8.8 fraction
map_sv_a	= $CC4E			; heap_alloc size hi scratch
map_sv_y	= $CC4F			; enemy slot / keep type scratch
bind_cur	= $CC50			; word: bind_map cursor
heap_top	= $CC52			; word: next LOAD dest (grows down from SCR_A)
map_base	= $CC54			; word: packed map payload
load_dest	= $CC56			; word: current LOAD dest
load_in_play	= $CC58
load_namelen	= $CC59
load_name_l	= $CC5A
load_name_h	= $CC5B
load_type	= $CC5C
bind_n		= $CC5D
reloc_base	= $CC5E			; word: reloc dest words in the map prefix

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
en_frame	= $CD3E			; ENEMY_MAX: local frame in current clip
drop_taken	= $CD56			; ENEMY_MAX: 1=inactive/taken, 0=active
drop_x		= $CD6E
drop_y		= $CD86
drop_z		= $CD9E
drop_room	= $CDB6
drop_type	= $CDCE			; BP_* when active
en_hp		= $CDE6			; ENEMY_MAX
en_timer	= $CDFE			; ENEMY_MAX: approach min / dog repath / death hold ms lo
en_timer_h	= $CE16			; ENEMY_MAX: approach min / dog repath / death hold ms hi
en_step		= $CE2E			; ENEMY_MAX: walk acc lo
en_step_h	= $CE46			; ENEMY_MAX: walk acc hi
en_dir		= $CE5E			; ENEMY_MAX: 0..7 dodge facing
gunshot_wake	= $CE76			; 1 = gun fired this frame (room wake)
ai_dirtry	= $CE77			; 5 bytes dodge dir candidates
ai_turn		= $CE7C			; turnaround dir or $ff
ai_probe	= $CE7D			; dir under test (probe must not clobber)
emuz_vx		= $CE7E			; VIC X lo staged (IRQ apply_en)
emuz_vy		= $CE7F			; VIC Y staged
emuz_col		= $CE80			; sprite colour staged from col_fx
emuz_pending	= $CE81			; enemy idx waiting to muzzle, $ff = none
fb_probe_y	= $CE82			; floor_below: inclusive max walkable Y
death_wait_l	= $CE83			; death hold ms acc
death_wait_h	= $CE84
col_room	= $CE85			; collision room for inset/floor/solid
splat_xmsb	= $CE86			; $d010 bit7 when X>=256
splat_vx		= $CE87
splat_vy		= $CE88
splat_col	= $CE89			; COL_SPLAT_HIT or col_line (miss)
trig_seen	= $CE8A			; update_triggers: b0=hurt ticked, b1=msg overlap
shot_hit_i	= $CE8B			; closest hitscan enemy, $ff = miss
shot_hit_z	= $CE8C			; CAM_ZH of that hit
hurt_flash_l	= $CE8D			; remaining red-border ms
hurt_flash_h	= $CE8E
bite_splat_i	= $CE8F			; dog idx pending blood splat, $ff = none
status_ms_l	= $CE90			; status HUD remaining ms
status_ms_h	= $CE91
door_i0		= $CE92			; room door slice start
door_i1		= $CE93			; exclusive end
sw_match	= $CE94			; cooked door/enable-tag id while unlocking/arming
en_pat_n	= $CE95			; ENEMY_MAX: patrol remaining cells
en_pain_i	= $CEAD			; ENEMY_MAX: pain/death/attack variant index
have_keys	= $CEC5			; HAVE_SILVER / HAVE_GOLD / HAVE_EARTH
pu_kind		= $CEC6			; 0 or BP_QUAD / BP_PENT / BP_RING
pu_ms_l		= $CEC7
pu_ms_h		= $CEC8
fx_oxl		= $CEC9			; world origin 8.8 (same as grenade)
fx_oyl		= $CECA
fx_ozl		= $CECB
fx_ox		= $CECC
fx_oy		= $CECD
fx_oz		= $CECE
sample_ms_chk	= $CECF			; shadow of sample_ms (init_irq); tripwire restore
spd_trip	= $CED0			; sample_ms corruption count (IRQ .top)
; Grenade SoA — 4 slots × 20 bytes, $CED1–$CF20
gr_on		= $CED1
gr_owner	= $CED5
gr_flags	= $CED9
gr_acc		= $CEDD
gr_xl		= $CEE1
gr_xh		= $CEE5
gr_yl		= $CEE9
gr_yh		= $CEED
gr_zl		= $CEF1
gr_zh		= $CEF5
gr_vxl		= $CEF9
gr_vxh		= $CEFD
gr_vyl		= $CF01
gr_vyh		= $CF05
gr_vzl		= $CF09
gr_vzh		= $CF0D
gr_fuse_l	= $CF11
gr_fuse_h	= $CF15
gr_life_l	= $CF19
gr_life_h	= $CF1D
; $CF21–$CF25 free (was gr_room, then gren_save_room)
; Hitscan params (live during gun_hitscan / splat_aim_jitter)
scan_hit_x	= $CF26			; |sx−CX| max (inclusive)
scan_hit_y	= $CF27			; |sy−64| max, $ff = no Y gate (both guns)
scan_dmg_max	= $CF28			; dmg = this − (z>>2), min 1
scan_dmg_all	= $CF29			; 1 = damage every cone hit (SSG)
scan_jx_mask	= $CF2A			; splat rnd X mask
scan_jx_bias	= $CF2B
scan_jy_mask	= $CF2C
scan_jy_bias	= $CF2D
; Timed FX headers: +0 on/phase, +1 skip, +2 ms_l, +3 ms_h
FXH_ON		= 0
FXH_SKIP	= 1
FXH_MS_L	= 2
FXH_MS_H	= 3
FXH_COUNT	= 5
fxh_flash4	= $CF2E
flash_phase	= fxh_flash4 + FXH_ON	; sprite 4: 0 off, 1 yellow, 2 red
flash_skip	= fxh_flash4 + FXH_SKIP
flash_ms_l	= fxh_flash4 + FXH_MS_L
flash_ms_h	= fxh_flash4 + FXH_MS_H
fxh_flash5	= $CF32
flash5_phase	= fxh_flash5 + FXH_ON	; sprite 5 (nail right)
flash5_skip	= fxh_flash5 + FXH_SKIP
flash5_ms_l	= fxh_flash5 + FXH_MS_L
flash5_ms_h	= fxh_flash5 + FXH_MS_H
fxh_emuz	= $CF36
emuz_on		= fxh_emuz + FXH_ON	; 1 = sprite 6 enabled
emuz_skip	= fxh_emuz + FXH_SKIP
emuz_ms_l	= fxh_emuz + FXH_MS_L
emuz_ms_h	= fxh_emuz + FXH_MS_H
fxh_splat	= $CF3A
splat_on	= fxh_splat + FXH_ON	; 1 = sprite 7 enabled
splat_skip	= fxh_splat + FXH_SKIP
splat_ms_l	= fxh_splat + FXH_MS_L
splat_ms_h	= fxh_splat + FXH_MS_H
fxh_explode	= $CF3E
fx_on		= fxh_explode + FXH_ON	; 1 = explosion live
fx_skip		= fxh_explode + FXH_SKIP
fx_ms_l		= fxh_explode + FXH_MS_L
fx_ms_h		= fxh_explode + FXH_MS_H
; Room whose pose banks are currently resident; $ff = none yet.
stream_room	= $CF42
; Explosion particle vel — FX_N × vx/vy s8 (integrated at draw)
fx_vx		= $CF43			; 24
fx_vy		= $CF5B			; 24
; Scrag spit — control + hitscan + tracer 8.8 start/end (12 bytes)
spit_on		= $CF73
spit_room	= $CF74
spit_owner	= $CF75			; enemy index
spit_flash	= $CF76			; 0 = tracer done, hitscan next update
spit_hitx	= $CF77			; player XZ at fire
spit_hitz	= $CF78
spit_oxl	= $CF79			; start 8.8
spit_oxh	= $CF7A
spit_oyl	= $CF7B
spit_oyh	= $CF7C
spit_ozl	= $CF7D
spit_ozh	= $CF7E
spit_xl		= $CF7F			; end 8.8
spit_xh		= $CF80
spit_yl		= $CF81
spit_yh		= $CF82
spit_zl		= $CF83
spit_zh		= $CF84
; Evicted from KERNAL ZP ($90–$bf / SETNAM $b7–$bc). Abs OK — not (ptr),y.
wish_dx		= $CF85			; signed move intent X
wish_dz		= $CF86
wish_dxh	= $CF87			; wish 8.8 high
wish_dzh	= $CF88
save_xh		= $CF89
save_zh		= $CF8A
save_xl		= $CF8B
save_zl		= $CF8C
col_x		= $CF8D			; collision test point
col_z		= $CF8E
col_y		= $CF8F
obj_i		= $CF90
face_bits	= $CF91			; which box faces visible
box_x		= $CF92			; AABB scratch (util indexes box_*,x)
box_y		= $CF93
box_z		= $CF94
box_sx		= $CF95
box_sy		= $CF96
box_sz		= $CF97
msg_off		= $CF98			; offset into map_text
vel_ms		= $CF99			; hold duration ms (lo)
vel_msh		= $CF9A
turn_acc_l	= $CF9B
turn_acc_h	= $CF9C
dt_msh		= $CF9D			; frame dt milliseconds (hi)
inv_l		= $CF9E			; (FOCAL<<16)/(z>>k) lo, mesh project
inv_h		= $CF9F
inv_k		= $CFA0
mesh_vmask	= $CFA1
mesh_nwork	= $CFA2
random8		= $CFA3
scale_s		= $CFA4
fn_lx		= $CFA5			; frustum inward normals (XZ)
fn_lz		= $CFA6
fn_rx		= $CFA7
fn_rz		= $CFA8
fn_fx		= $CFA9
fn_fz		= $CFAA
pv0		= $CFAB			; glyph / ramp / door fill
pv1		= $CFAC
pv2		= $CFAD
pv3		= $CFAE
pv4		= $CFAF
col_bg		= $CFB0			; active room background → $d021
col_fx		= $CFB1			; active room FX
col_line	= $CFB2			; active room lines → colour RAM
palette_room	= $CFB3			; last room_idx palette ($ff = none)
far_scale	= $CFB4			; FOCAL/z integer, far enemy project
col_wpn		= $CFB5			; weapon sprite colour → $d027–$d02a
sfx_ch		= $CFB6			; current channel 0..2
sfx_id		= $CFB7			; sound id / freq scratch
sample_ms	= $CFB8			; PAL 20 / NTSC 17 — set at init
ps_save_x	= $CFB9
ps_save_y	= $CFBA
door_blk	= $CFBB			; bit0 X slide blocked, bit1 Z
mv0_xl		= $CFBC			; cam 8.8 at start of apply_move_world
mv0_xh		= $CFBD
mv0_zl		= $CFBE
mv0_zh		= $CFBF
; $CFC0+ free
ai_code_lo	= $CFC0			; runtime code base while patching a bank
ai_code_hi	= $CFC1
ai_delta_lo	= $CFC2			; runtime code base - AI_LINK_BASE
ai_delta_hi	= $CFC3
ai_reloc_nlo	= $CFC4
ai_reloc_nhi	= $CFC5
ai_map_nlo	= $CFC6
ai_map_nhi	= $CFC7
ai_pose_lo	= $CFC8
ai_pose_hi	= $CFC9
ai_cmd		= $CFCA
ai_field	= $CFCB
; $CFCC+ free
HAVE_SILVER	= 1
HAVE_GOLD	= 2
HAVE_EARTH	= 4
POWERUP_MS	= 30000
