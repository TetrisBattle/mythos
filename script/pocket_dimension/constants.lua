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
	{ slots = { "T1", "T2", "T3", "T4" } },
	{ slots = { "L1", "L2", "L3", "L4" } },
	{ slots = { "R1", "R2", "R3", "R4" } },
	{ slots = { "B1", "B2", "B3", "B4" } },
}

local CHUNK_SIZE   = 32
local CHUNK_MARGIN = 2

local FLOOR_TILE = "mythos-dimension-floor"

-- Arrow buttons resize in 10-tile steps; typed sizes are accepted per tile.
local RESIZE_STEP   = 10
local MIN_DIMENSION_WIDTH  = 10
local MIN_DIMENSION_HEIGHT = 10

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
	CHUNK_SIZE            = CHUNK_SIZE,
	CHUNK_MARGIN          = CHUNK_MARGIN,
	FLOOR_TILE            = FLOOR_TILE,
	RESIZE_STEP           = RESIZE_STEP,
	MIN_DIMENSION         = MIN_DIMENSION_WIDTH,
	MIN_DIMENSION_WIDTH   = MIN_DIMENSION_WIDTH,
	MIN_DIMENSION_HEIGHT  = MIN_DIMENSION_HEIGHT,
}
