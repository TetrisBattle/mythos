local constants = require("script.pocket_dimension.constants")

-- Maps each mythos slot key to the external connector position and inward proxy
-- position around the mythos entity.
local function buildMythosSlotLayout()
	local layout = {}
	for i = 1, constants.GATES_PER_SIDE do
		local off = constants.GATE_OFFSETS[i]
		layout["L" .. i] = { externalX = -2.5, externalY = off,  innerX = -1.5, innerY = off,  outwardDir = defines.direction.west  }
		layout["R" .. i] = { externalX =  2.5, externalY = off,  innerX =  1.5, innerY = off,  outwardDir = defines.direction.east  }
		layout["T" .. i] = { externalX = off,  externalY = -2.5, innerX = off,  innerY = -1.5, outwardDir = defines.direction.north }
		layout["B" .. i] = { externalX = off,  externalY =  2.5, innerX = off,  innerY =  1.5, outwardDir = defines.direction.south }
	end
	return layout
end

-- Computes gate/belt positions for arbitrary floor bounds.
-- The pocket dimension exposes all Mythos ports on the left side wall.
-- innerBeltPos: the tile one step inside the floor where the player places their belt.
local function computeDimensionSlotBeltLayout(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	local layout = {}
	local row = 1
	for _, group in ipairs(constants.DIMENSION_GATE_GROUPS) do
		for _, slotKey in ipairs(group.slots) do
			local yc = bounds.y_min + constants.DIM_GATE_FROM_TOP[row]
			layout[slotKey] = {
				pos             = { bounds.x_min - 0.5, yc },
				innerBeltPos    = { bounds.x_min + 0.5, yc },
				gateOrientation = 0.75,
			}
			row = row + 1
		end
	end
	return layout
end

local function computeDimensionGateLabels(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	local labels = {}
	local row = 1
	for _, group in ipairs(constants.DIMENSION_GATE_GROUPS) do
		for _, slotKey in ipairs(group.slots) do
			labels[#labels + 1] = {
				text = slotKey,
				pos  = { bounds.x_min - 1.25, bounds.y_min + constants.DIM_GATE_FROM_TOP[row] },
			}
			row = row + 1
		end
	end
	return labels
end

return {
	slotBeltLayout                 = computeDimensionSlotBeltLayout(constants.DEFAULT_FLOOR_BOUNDS),
	buildMythosSlotLayout          = buildMythosSlotLayout,
	computeDimensionSlotBeltLayout = computeDimensionSlotBeltLayout,
	computeDimensionGateLabels     = computeDimensionGateLabels,
}
