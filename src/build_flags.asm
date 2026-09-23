; --- build flags (Wolf64-style) -------------------------------------------
PROFILE		= 0				; 1 = R/P/K/D bucket HUD + CIA samples
HUD_FRAME_MS	= 1				; 1 = frame time ms on HUD row 0
HUD_POS		= 0				; 1 = X/Y/Z/yaw/pitch on HUD row 2
INF_AMMO		= 1				; 1 = guns fire without spending ammo
IRQ_DEBUG_SPLIT	= 0				; 1 = $d020 stripe at mid-split (tune 186)

; Stage buckets closed by prof_add_bucket. Same ids in GAME and skel_draw.
PROF_CLEAR	= 0
PROF_ROT	= 1
PROF_PROJ	= 2
PROF_CLIP	= 3
PROF_DRAW	= 4
PROF_NBUCKET	= 5
