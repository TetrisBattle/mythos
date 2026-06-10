local constants = require("script.pocket_dimension.constants")

-- Maps each mythos slot key to the external connector position and inward proxy
-- position around the mythos entity.
local function buildMythosSlotLayout()
	local layout = {}
	for i = 1, constants.GATES_PER_SIDE do
		local off = constants.GATE_OFFSETS[i]
		layout["left-" .. i]   = { externalX = -2.5, externalY = off,  innerX = -1.5, innerY = off,  outwardDir = defines.direction.west  }
		layout["right-" .. i]  = { externalX =  2.5, externalY = off,  innerX =  1.5, innerY = off,  outwardDir = defines.direction.east  }
		layout["top-" .. i]    = { externalX = off,  externalY = -2.5, innerX = off,  innerY = -1.5, outwardDir = defines.direction.north }
		layout["bottom-" .. i] = { externalX = off,  externalY =  2.5, innerX = off,  innerY =  1.5, outwardDir = defines.direction.south }
	end
	return layout
end

-- Computes gate/belt positions for arbitrary floor bounds.
-- The pocket dimension exposes all Mythos ports on left/right side walls only.
-- innerBeltPos: the tile one step inside the floor where the player places their belt.
local function computeDimensionSlotBeltLayout(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	local layout = {}
	for i, slotKey in ipairs(constants.LEFT_DIMENSION_SLOTS) do
		local yc = bounds.y_min + constants.DIM_GATE_FROM_TOP[i]
		layout[slotKey] = {
			pos             = { bounds.x_min - 0.5, yc },
			innerBeltPos    = { bounds.x_min + 0.5, yc },
			gateOrientation = 0.75,
		}
	end
	for i, slotKey in ipairs(constants.RIGHT_DIMENSION_SLOTS) do
		local yc = bounds.y_min + constants.DIM_GATE_FROM_TOP[i]
		layout[slotKey] = {
			pos             = { bounds.x_max + 1.5, yc },
			innerBeltPos    = { bounds.x_max + 0.5, yc },
			gateOrientation = 0.25,
		}
	end
	return layout
end

return {
	slotBeltLayout                 = computeDimensionSlotBeltLayout(constants.DEFAULT_FLOOR_BOUNDS),
	buildMythosSlotLayout          = buildMythosSlotLayout,
	computeDimensionSlotBeltLayout = computeDimensionSlotBeltLayout,
}
