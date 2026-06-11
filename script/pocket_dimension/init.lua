local constants = require("script.pocket_dimension.constants")
local floor     = require("script.pocket_dimension.floor")
local layout    = require("script.pocket_dimension.layout")
local surface   = require("script.pocket_dimension.surface")

return {
	create                          = surface.create,
	syncRemoteViewInfrastructure    = surface.syncInfrastructure,
	DEFAULT_WIDTH                   = constants.DEFAULT_WIDTH,
	DEFAULT_HEIGHT                  = constants.DEFAULT_HEIGHT,
	DEFAULT_FLOOR_BOUNDS            = constants.DEFAULT_FLOOR_BOUNDS,
	VIEW_X                          = constants.VIEW_X,
	VIEW_Y                          = constants.VIEW_Y,
	GATES_PER_SIDE                  = constants.GATES_PER_SIDE,
	RESIZE_STEP                     = constants.RESIZE_STEP,
	MIN_DIMENSION                   = constants.MIN_DIMENSION,
	snapSizeUpEven                  = floor.snapSizeUpEven,
	slotBeltLayout                  = layout.slotBeltLayout,
	buildMythosSlotLayout           = layout.buildMythosSlotLayout,
	computeDimensionSlotBeltLayout  = layout.computeDimensionSlotBeltLayout,
	inferFloorBounds                = floor.inferFloorBounds,
	expandEdge                      = floor.expandEdge,
	contractEdge                    = floor.contractEdge,
	floorCentre                     = floor.floorCentre,
	ensureRemoteViewReady           = surface.ensureRemoteViewReady,
	voidFillGeneratedChunk          = surface.voidFillGeneratedChunk,
}
