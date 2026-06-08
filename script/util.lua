local Util = {}

-- Stable string key for a {x, y} position.
-- Works correctly for both integer and .5-fractional tile coordinates.
function Util.positionKey(x, y)
	return string.format("%g,%g", x, y)
end

function Util.floorWidth(bounds)
	return bounds.x_max - bounds.x_min + 1
end

function Util.floorHeight(bounds)
	return bounds.y_max - bounds.y_min + 1
end

function Util.copyBounds(bounds)
	return {
		x_min = bounds.x_min,
		x_max = bounds.x_max,
		y_min = bounds.y_min,
		y_max = bounds.y_max,
	}
end

function Util.parseDimensionUnitNumber(surfaceOrName)
	local name = type(surfaceOrName) == "string" and surfaceOrName or surfaceOrName.name
	return tonumber(name:match("^mythos%-dimension%-(%d+)$"))
end

function Util.buildInnerPosToSlot(layout)
	local byPosition = {}
	for slotKey, beltLayout in pairs(layout) do
		local pos = beltLayout.innerBeltPos
		byPosition[Util.positionKey(pos[1], pos[2])] = slotKey
	end
	return byPosition
end

function Util.edgeSlotKeys(edge, count)
	local keys = {}
	for i = 1, count do
		keys[i] = edge .. "-" .. i
	end
	return keys
end

local CONTENT_ITEM_NAMES = {
	mythos = true,
	["mythos-with-contents"] = true,
	["virtual-chest"] = true,
}

function Util.isStoredChestItem(stack)
	return stack.valid_for_read and not CONTENT_ITEM_NAMES[stack.name]
end

Util.INFRASTRUCTURE_ENTITY_NAMES = {
	["mythos-hidden-radar"]     = true,
	["mythos-power-hub-pole"]   = true,
	["mythos-power-link-inner"] = true,
	["mythos-hidden-pipe"]      = true,
	["mythos-hidden-heat-pipe"] = true,
}

Util.REMOTE_VIEW_ENTITY_NAMES = {
	["mythos-hidden-radar"]     = true,
	["mythos-power-hub-pole"]   = true,
	["mythos-power-link-inner"] = true,
}

function Util.isInfrastructureEntityName(name)
	return Util.INFRASTRUCTURE_ENTITY_NAMES[name] == true
end

return Util
