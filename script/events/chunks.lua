local PocketDimension = require("script.pocket_dimension.init")
local Registry        = require("script.mythos.registry")
local util            = require("script.util")

local Chunks = {}

function Chunks.onChunkGenerated(event)
	local surface = event.surface
	local unit_num = util.parseDimensionUnitNumber(surface)
	if not unit_num then return end

	local state = Registry.get(unit_num)
	local bounds = state and state.floor_bounds
	if not bounds then
		bounds = PocketDimension.inferFloorBounds(surface)
	end

	PocketDimension.voidFillGeneratedChunk(surface, bounds, event.area)
	surface.set_chunk_generated_status(
		event.position,
		defines.chunk_generated_status.entities
	)
end

return Chunks
