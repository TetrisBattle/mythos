local DEFAULT_WIDTH  = 20
local DEFAULT_HEIGHT = 20
local DEFAULT_Y_MIN  = 0
local DEFAULT_Y_MAX  = DEFAULT_Y_MIN + DEFAULT_HEIGHT - 1

local DEFAULT_FLOOR_BOUNDS = {
	x_min = 0,
	x_max = DEFAULT_WIDTH - 1,
	y_min = DEFAULT_Y_MIN,
	y_max = DEFAULT_Y_MAX,
}

local GATES_PER_SIDE = 4

-- Tile offsets along each 4x4 mythos face (1 = top / left).
local GATE_OFFSETS = { -1.5, -0.5, 0.5, 1.5 }

local DIMENSION_GATE_GROUPS = {
	{ label = "TOP",    slots = { "top-1",    "top-2",    "top-3",    "top-4"    } },
	{ label = "LEFT",   slots = { "left-1",   "left-2",   "left-3",   "left-4"   } },
	{ label = "RIGHT",  slots = { "right-1",  "right-2",  "right-3",  "right-4"  } },
	{ label = "BOTTOM", slots = { "bottom-1", "bottom-2", "bottom-3", "bottom-4" } },
}

-- Left-wall rows from the floor's northern edge, with one tile gap between
-- Mythos-side groups.
local DIM_GATE_FROM_TOP = {
	0.5, 1.5, 2.5, 3.5,
	5.5, 6.5, 7.5, 8.5,
	10.5, 11.5, 12.5, 13.5,
	15.5, 16.5, 17.5, 18.5,
}

local CHUNK_SIZE   = 32
local CHUNK_MARGIN = 2

local FLOOR_TILE = "mythos-dimension-floor"

-- Arrow buttons resize in 8-tile steps; typed sizes snap to 2-tile (even) accuracy.
local RESIZE_STEP   = 10
local FLOOR_SNAP    = 2
local MIN_DIMENSION_WIDTH  = 20
local MIN_DIMENSION_HEIGHT = 20

return {
	DEFAULT_WIDTH         = DEFAULT_WIDTH,
	DEFAULT_HEIGHT        = DEFAULT_HEIGHT,
	DEFAULT_Y_MIN         = DEFAULT_Y_MIN,
	DEFAULT_Y_MAX         = DEFAULT_Y_MAX,
	DEFAULT_FLOOR_BOUNDS  = DEFAULT_FLOOR_BOUNDS,
	VIEW_X                = DEFAULT_WIDTH / 2,
	VIEW_Y                = (DEFAULT_Y_MIN + DEFAULT_Y_MAX) / 2,
	GATES_PER_SIDE        = GATES_PER_SIDE,
	GATE_OFFSETS          = GATE_OFFSETS,
	DIMENSION_GATE_GROUPS = DIMENSION_GATE_GROUPS,
	DIM_GATE_FROM_TOP     = DIM_GATE_FROM_TOP,
	CHUNK_SIZE            = CHUNK_SIZE,
	CHUNK_MARGIN          = CHUNK_MARGIN,
	FLOOR_TILE            = FLOOR_TILE,
	RESIZE_STEP           = RESIZE_STEP,
	FLOOR_SNAP            = FLOOR_SNAP,
	MIN_DIMENSION         = MIN_DIMENSION_WIDTH,
	MIN_DIMENSION_WIDTH   = MIN_DIMENSION_WIDTH,
	MIN_DIMENSION_HEIGHT  = MIN_DIMENSION_HEIGHT,
}
