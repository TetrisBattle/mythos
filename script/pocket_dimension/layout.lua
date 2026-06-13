local constants = require("script.pocket_dimension.constants")

local function orderedSlotKeys()
	local keys = {}
	for _, group in ipairs(constants.DIMENSION_GATE_GROUPS) do
		for _, slotKey in ipairs(group.slots) do
			keys[#keys + 1] = slotKey
		end
	end
	return keys
end

local SLOT_KEYS = orderedSlotKeys()

local function defaultDimensionGatePositions()
	local positions = {}
	for _, slotKey in ipairs(SLOT_KEYS) do
		positions[slotKey] = slotKey
	end
	return positions
end

local function normalizeDimensionGatePositions(gatePositions)
	local valid = {}
	for _, slotKey in ipairs(SLOT_KEYS) do
		valid[slotKey] = true
	end

	local normalized = {}
	local used = {}
	if gatePositions then
		for _, slotKey in ipairs(SLOT_KEYS) do
			local physicalSlotKey = gatePositions[slotKey]
			if valid[physicalSlotKey] and not used[physicalSlotKey] then
				normalized[slotKey] = physicalSlotKey
				used[physicalSlotKey] = true
			end
		end
	end

	local unused = {}
	for _, slotKey in ipairs(SLOT_KEYS) do
		if not used[slotKey] then
			unused[#unused + 1] = slotKey
		end
	end

	local unusedIndex = 1
	for _, slotKey in ipairs(SLOT_KEYS) do
		if not normalized[slotKey] then
			normalized[slotKey] = unused[unusedIndex] or slotKey
			unusedIndex = unusedIndex + 1
		end
	end

	return normalized
end

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
local function computePhysicalDimensionSlotLayout(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	local layout = {}
	local row = 1
	for _, group in ipairs(constants.DIMENSION_GATE_GROUPS) do
		for _, slotKey in ipairs(group.slots) do
			local yc = bounds.y_min + constants.DIM_GATE_FROM_TOP[row]
			layout[slotKey] = {
				pos             = { bounds.x_min - 0.5, yc },
				innerBeltPos    = { bounds.x_min + 0.5, yc },
				labelPos        = { bounds.x_min - 0.45, yc + 0.25 },
				gateOrientation = 0.75,
				physicalSlotKey = slotKey,
			}
			row = row + 1
		end
	end
	return layout
end

-- Computes gate/belt positions for arbitrary floor bounds.
-- The pocket dimension exposes all Mythos ports on the left side wall.
-- innerBeltPos: the tile one step inside the floor where the player places their belt.
local function computeDimensionSlotBeltLayout(bounds, gatePositions)
	local physicalLayout = computePhysicalDimensionSlotLayout(bounds)
	local positions = normalizeDimensionGatePositions(gatePositions)
	local layout = {}

	for _, slotKey in ipairs(SLOT_KEYS) do
		local physicalSlotKey = positions[slotKey]
		local physical = physicalLayout[physicalSlotKey]
		if physical then
			layout[slotKey] = {
				pos             = { physical.pos[1], physical.pos[2] },
				innerBeltPos    = { physical.innerBeltPos[1], physical.innerBeltPos[2] },
				labelPos        = { physical.labelPos[1], physical.labelPos[2] },
				gateOrientation = physical.gateOrientation,
				physicalSlotKey = physicalSlotKey,
			}
		end
	end
	return layout
end

local function computeDimensionGateLabels(bounds, gatePositions)
	local labels = {}
	local layout = computeDimensionSlotBeltLayout(bounds, gatePositions)
	for slotKey, gateLayout in pairs(layout) do
		labels[#labels + 1] = {
			text = slotKey,
			pos  = { gateLayout.labelPos[1], gateLayout.labelPos[2] },
		}
	end
	table.sort(labels, function(a, b)
		if a.pos[2] == b.pos[2] then return a.text < b.text end
		return a.pos[2] < b.pos[2]
	end)
	return labels
end

return {
	slotBeltLayout                 = computeDimensionSlotBeltLayout(constants.DEFAULT_FLOOR_BOUNDS),
	SLOT_KEYS                      = SLOT_KEYS,
	buildMythosSlotLayout          = buildMythosSlotLayout,
	defaultDimensionGatePositions  = defaultDimensionGatePositions,
	normalizeDimensionGatePositions = normalizeDimensionGatePositions,
	computeDimensionSlotBeltLayout = computeDimensionSlotBeltLayout,
	computeDimensionGateLabels     = computeDimensionGateLabels,
}
