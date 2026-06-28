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

local function floorHeight(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	return bounds.y_max - bounds.y_min + 1
end

local function floorWidth(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	return bounds.x_max - bounds.x_min + 1
end

local function topGatePosition(bounds, index)
	local x = bounds.x_min + index - 0.5
	return { x, bounds.y_min - 0.5 }, { x, bounds.y_min + 0.5 }
end

local function rightGatePosition(bounds, index)
	local y = bounds.y_min + index - 0.5
	return { bounds.x_max + 1.5, y }, { bounds.x_max + 0.5, y }
end

local function bottomGatePosition(bounds, index)
	local x = bounds.x_min + index - 0.5
	return { x, bounds.y_max + 1.5 }, { x, bounds.y_max + 0.5 }
end

local function leftGatePosition(bounds, index)
	local y = bounds.y_min + index - 0.5
	return { bounds.x_min - 0.5, y }, { bounds.x_min + 0.5, y }
end

local PHYSICAL_GATE_SIDES = {
	{
		edge = "top",
		prefix = "PT",
		orientation = 0,
		count = floorWidth,
		position = topGatePosition,
	},
	{
		edge = "right",
		prefix = "PR",
		orientation = 0.25,
		count = floorHeight,
		position = rightGatePosition,
	},
	{
		edge = "bottom",
		prefix = "PB",
		orientation = 0.5,
		count = floorWidth,
		position = bottomGatePosition,
	},
	{
		edge = "left",
		prefix = "PL",
		orientation = 0.75,
		count = floorHeight,
		position = leftGatePosition,
		labelXOffset = 0.05,
	},
}

local PHYSICAL_GATE_SIDE_BY_PREFIX = {}
for _, side in ipairs(PHYSICAL_GATE_SIDES) do
	PHYSICAL_GATE_SIDE_BY_PREFIX[side.prefix] = side
end

local function physicalGateKey(side, index)
	return side.prefix .. index
end

local function physicalGateParts(key)
	if type(key) ~= "string" then
		return nil
	end
	local prefix, index = key:match("^(P[TRBL])(%d+)$")
	index = tonumber(index)
	local side = PHYSICAL_GATE_SIDE_BY_PREFIX[prefix]
	if side and index and index >= 1 and index % 1 == 0 then
		return side, index
	end
end

local function physicalGateCount(side, bounds)
	return math.max(side.count(bounds), 0)
end

local function validPhysicalGateKey(key, bounds)
	local side, index = physicalGateParts(key)
	if not side then
		return nil
	end
	if index > physicalGateCount(side, bounds) then
		return nil
	end
	return physicalGateKey(side, index)
end

local function defaultDimensionGatePositions()
	return {}
end

local function normalizeDimensionGatePositions(gatePositions, bounds)
	local normalized = {}
	local used = {}
	if gatePositions then
		for _, slotKey in ipairs(SLOT_KEYS) do
			local physicalGate = validPhysicalGateKey(gatePositions[slotKey], bounds)
			if physicalGate and not used[physicalGate] then
				normalized[slotKey] = physicalGate
				used[physicalGate] = true
			end
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
		layout["L" .. i] =
			{ externalX = -2.5, externalY = off, innerX = -1.5, innerY = off, outwardDir = defines.direction.west }
		layout["R" .. i] =
			{ externalX = 2.5, externalY = off, innerX = 1.5, innerY = off, outwardDir = defines.direction.east }
		layout["T" .. i] =
			{ externalX = off, externalY = -2.5, innerX = off, innerY = -1.5, outwardDir = defines.direction.north }
		layout["B" .. i] =
			{ externalX = off, externalY = 2.5, innerX = off, innerY = 1.5, outwardDir = defines.direction.south }
	end
	return layout
end

local function computeDimensionPhysicalGateLayout(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	local layout = {}
	for _, side in ipairs(PHYSICAL_GATE_SIDES) do
		for index = 1, physicalGateCount(side, bounds) do
			local key = physicalGateKey(side, index)
			local pos, innerBeltPos = side.position(bounds, index)
			local labelXOffset = side.labelXOffset or 0
			layout[key] = {
				pos = pos,
				innerBeltPos = innerBeltPos,
				labelPos = { pos[1] + labelXOffset, pos[2] + 0.25 },
				gateOrientation = side.orientation,
				physicalGateKey = key,
				edge = side.edge,
			}
		end
	end
	return layout
end

-- Computes logical-slot gate/belt positions for arbitrary floor bounds.
-- innerBeltPos is the tile one step inside the selected physical gate.
local function computeDimensionSlotBeltLayout(bounds, gatePositions)
	local physicalLayout = computeDimensionPhysicalGateLayout(bounds)
	local positions = normalizeDimensionGatePositions(gatePositions, bounds)
	local layout = {}

	for _, slotKey in ipairs(SLOT_KEYS) do
		local physicalGate = positions[slotKey]
		local physical = physicalLayout[physicalGate]
		if physical then
			layout[slotKey] = {
				pos = { physical.pos[1], physical.pos[2] },
				innerBeltPos = { physical.innerBeltPos[1], physical.innerBeltPos[2] },
				labelPos = { physical.labelPos[1], physical.labelPos[2] },
				gateOrientation = physical.gateOrientation,
				physicalGateKey = physicalGate,
				edge = physical.edge,
			}
		end
	end
	return layout
end

return {
	slotBeltLayout = computeDimensionSlotBeltLayout(constants.DEFAULT_FLOOR_BOUNDS),
	SLOT_KEYS = SLOT_KEYS,
	buildMythosSlotLayout = buildMythosSlotLayout,
	defaultDimensionGatePositions = defaultDimensionGatePositions,
	normalizeDimensionGatePositions = normalizeDimensionGatePositions,
	computeDimensionPhysicalGateLayout = computeDimensionPhysicalGateLayout,
	computeDimensionSlotBeltLayout = computeDimensionSlotBeltLayout,
}
