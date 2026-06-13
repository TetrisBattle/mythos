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

local function physicalGateKey(row)
	return "G" .. row
end

local function physicalGateRow(key)
	if type(key) ~= "string" then return nil end
	local row = tonumber(key:match("^G(%d+)$"))
	if row and row >= 1 and row % 1 == 0 then return row end
end

local function floorHeight(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	return bounds.y_max - bounds.y_min + 1
end

local function legacyPhysicalGateKey(slotKey)
	for i, key in ipairs(SLOT_KEYS) do
		if key == slotKey then return physicalGateKey(i) end
	end
end

local function validPhysicalGateKey(key, bounds)
	local row = physicalGateRow(key)
	if not row then
		key = legacyPhysicalGateKey(key)
		row = physicalGateRow(key)
	end
	if not row then return nil end
	if bounds and row > floorHeight(bounds) then return nil end
	return physicalGateKey(row)
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
		layout["L" .. i] = { externalX = -2.5, externalY = off,  innerX = -1.5, innerY = off,  outwardDir = defines.direction.west  }
		layout["R" .. i] = { externalX =  2.5, externalY = off,  innerX =  1.5, innerY = off,  outwardDir = defines.direction.east  }
		layout["T" .. i] = { externalX = off,  externalY = -2.5, innerX = off,  innerY = -1.5, outwardDir = defines.direction.north }
		layout["B" .. i] = { externalX = off,  externalY =  2.5, innerX = off,  innerY =  1.5, outwardDir = defines.direction.south }
	end
	return layout
end

local function computeDimensionPhysicalGateLayout(bounds)
	bounds = bounds or constants.DEFAULT_FLOOR_BOUNDS
	local layout = {}
	for row = 1, floorHeight(bounds) do
		local key = physicalGateKey(row)
		local yc = bounds.y_min + row - 0.5
		layout[key] = {
			pos             = { bounds.x_min - 0.5, yc },
			innerBeltPos    = { bounds.x_min + 0.5, yc },
			gateOrientation = 0.75,
			physicalGateKey = key,
		}
	end
	return layout
end

-- Computes gate/belt positions for arbitrary floor bounds.
-- The pocket dimension exposes all Mythos ports on the left side wall.
-- innerBeltPos: the tile one step inside the floor where the player places their belt.
local function computeDimensionSlotBeltLayout(bounds, gatePositions)
	local physicalLayout = computeDimensionPhysicalGateLayout(bounds)
	local positions = normalizeDimensionGatePositions(gatePositions, bounds)
	local layout = {}

	for _, slotKey in ipairs(SLOT_KEYS) do
		local physicalGate = positions[slotKey]
		local physical = physicalLayout[physicalGate]
		if physical then
			layout[slotKey] = {
				pos             = { physical.pos[1], physical.pos[2] },
				innerBeltPos    = { physical.innerBeltPos[1], physical.innerBeltPos[2] },
				gateOrientation = physical.gateOrientation,
				physicalGateKey = physicalGate,
			}
		end
	end
	return layout
end

return {
	slotBeltLayout                 = computeDimensionSlotBeltLayout(constants.DEFAULT_FLOOR_BOUNDS),
	SLOT_KEYS                      = SLOT_KEYS,
	buildMythosSlotLayout          = buildMythosSlotLayout,
	defaultDimensionGatePositions  = defaultDimensionGatePositions,
	normalizeDimensionGatePositions = normalizeDimensionGatePositions,
	computeDimensionPhysicalGateLayout = computeDimensionPhysicalGateLayout,
	computeDimensionSlotBeltLayout = computeDimensionSlotBeltLayout,
}
