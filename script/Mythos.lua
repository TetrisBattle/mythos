local PocketDimension = require("script.PocketDimension")

local connectionTypes = {
	["loader"]           = "loader",
	["loader-1x1"]       = "loader",
	["transport-belt"]   = "belt",
	["underground-belt"] = "belt",
	["splitter"]         = "belt",
	["lane-splitter"]    = "belt",
	["pipe"]             = "pipe",
	["pipe-to-ground"]   = "pipe",
	["storage-tank"]     = "pipe",
	["pump"]             = "pipe",
	["offshore-pump"]    = "pipe",
	["generator"]        = "pipe",
	["heat-pipe"]        = "heat-pipe",
	["reactor"]          = "heat-pipe",
	["boiler"]           = "heat-pipe",
}

-- Per-slot geometry relative to the mythos center position.
--   externalX/Y : the tile where the player-placed entity must sit
--   innerX/Y    : the tile inside mythos where the hidden connector goes
--   outwardDir  : direction FROM mythos center TOWARD the external entity
local slotLayout = {
	["left-top"]     = { externalX = -1.5, externalY = -0.5, innerX = -0.5, innerY = -0.5, outwardDir = defines.direction.west  },
	["left-bottom"]  = { externalX = -1.5, externalY =  0.5, innerX = -0.5, innerY =  0.5, outwardDir = defines.direction.west  },
	["right-top"]    = { externalX =  1.5, externalY = -0.5, innerX =  0.5, innerY = -0.5, outwardDir = defines.direction.east  },
	["right-bottom"] = { externalX =  1.5, externalY =  0.5, innerX =  0.5, innerY =  0.5, outwardDir = defines.direction.east  },
	["top-left"]     = { externalX = -0.5, externalY = -1.5, innerX = -0.5, innerY = -0.5, outwardDir = defines.direction.north },
	["top-right"]    = { externalX =  0.5, externalY = -1.5, innerX =  0.5, innerY = -0.5, outwardDir = defines.direction.north },
	["bottom-left"]  = { externalX = -0.5, externalY =  1.5, innerX = -0.5, innerY =  0.5, outwardDir = defines.direction.south },
	["bottom-right"] = { externalX =  0.5, externalY =  1.5, innerX =  0.5, innerY =  0.5, outwardDir = defines.direction.south },
}

local oppositeDir = {
	[defines.direction.north] = defines.direction.south,
	[defines.direction.south] = defines.direction.north,
	[defines.direction.east]  = defines.direction.west,
	[defines.direction.west]  = defines.direction.east,
}

-- Stable string key for a position; works for both integer and .5 values.
local function positionKey(x, y)
	return string.format("%g,%g", x, y)
end

-- ── Mythos ────────────────────────────────────────────────────────────────────
-- Tracks one placed mythos entity: pre-computed slot positions and active
-- connections. Stored in storage.mythoi[unit_number] between ticks.

local Mythos = {}
Mythos.__index = Mythos
Mythos.connectionTypes = connectionTypes  -- exposed so control.lua can use it

-- Builds a new state from a freshly placed mythos entity.
function Mythos.new(mythosEntity)
	local cx = mythosEntity.position.x
	local cy = mythosEntity.position.y

	local slots         = {}  -- slotKey → { external, inner, outwardDir, conn }
	local byExternalPos = {}  -- positionKey(x,y) → slotKey

	for slotKey, layout in pairs(slotLayout) do
		local externalPos = { x = cx + layout.externalX, y = cy + layout.externalY }
		local innerPos    = { x = cx + layout.innerX,    y = cy + layout.innerY    }

		slots[slotKey] = {
			external   = externalPos,
			inner      = innerPos,
			outwardDir = layout.outwardDir,
			conn       = nil,
		}
		byExternalPos[positionKey(externalPos.x, externalPos.y)] = slotKey
	end

	local dim = PocketDimension.create(mythosEntity.unit_number, mythosEntity.force)

	return setmetatable({
		entity        = mythosEntity,
		slots         = slots,
		byExternalPos = byExternalPos,
		inside_surface = dim,
		inside_x       = PocketDimension.VIEW_X,
		inside_y       = PocketDimension.VIEW_Y,
	}, Mythos)
end

-- Returns the slot key for the given world position, or nil.
function Mythos:findSlotAt(pos)
	return self.byExternalPos[positionKey(pos.x, pos.y)]
end

-- Returns true when at least one OTHER slot that shares the same inner position
-- still has an active connection (corner slots share an inner tile).
function Mythos:innerPositionStillNeeded(innerPos)
	local key = positionKey(innerPos.x, innerPos.y)
	for _, slot in pairs(self.slots) do
		if slot.conn and positionKey(slot.inner.x, slot.inner.y) == key then
			return true
		end
	end
	return false
end

-- The invisible prototype entity to place for each connection category that
-- needs a physical in-world connector (pipe/heat-pipe carry fluid/heat).
local hiddenEntityName = {
	["pipe"]      = "mythos-hidden-pipe",
	["heat-pipe"] = "mythos-hidden-heat-pipe",
}

-- Registers a connection between the given entity and the named slot.
-- Places the hidden connector if required. Returns true on success.
function Mythos:connect(slotKey, entity)
	local slot = self.slots[slotKey]
	if not slot or slot.conn then return end

	local connType = connectionTypes[entity.type]
	if not connType then return end

	-- Belts and loaders must point toward or away from mythos, not parallel.
	local ioDirection = nil
	if connType == "belt" or connType == "loader" then
		local inwardDir = oppositeDir[slot.outwardDir]
		if entity.direction ~= slot.outwardDir and entity.direction ~= inwardDir then
			return
		end
		ioDirection = entity.direction == inwardDir and "input" or "output"
	end

	slot.conn = { entity = entity, connType = connType, ioDirection = ioDirection }

	local hiddenName = hiddenEntityName[connType]
	if hiddenName then
		local surface = self.entity.surface
		if not surface.find_entity(hiddenName, slot.inner) then
			surface.create_entity {
				name        = hiddenName,
				position    = slot.inner,
				force       = entity.force,
				raise_built = false,
			}
		end
	end

	return true
end

-- Clears the connection on a slot and destroys its hidden connector when no
-- other slot at the same inner position is still connected.
function Mythos:disconnect(slotKey)
	local slot = self.slots[slotKey]
	if not slot or not slot.conn then return end

	local connType = slot.conn.connType
	local innerPos = slot.inner
	slot.conn = nil

	local hiddenName = hiddenEntityName[connType]
	if hiddenName and not self:innerPositionStillNeeded(innerPos) then
		local hiddenEntity = self.entity.surface.find_entity(hiddenName, innerPos)
		if hiddenEntity and hiddenEntity.valid then
			hiddenEntity.destroy { raise_destroy = false }
		end
	end
end

-- Disconnects all slots (removing hidden connectors) then removes from storage.
function Mythos:destroy()
	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	if self.inside_surface and self.inside_surface.valid then
		game.delete_surface(self.inside_surface)
	end
	storage.mythoi[self.entity.unit_number] = nil
end

-- Scans every slot's external position for already-placed connectable entities
-- and connects them. Called when a mythos is placed into an existing layout.
function Mythos:connectExistingNeighbours()
	local surface = self.entity.surface
	for slotKey, slot in pairs(self.slots) do
		local candidates = surface.find_entities_filtered {
			area = {
				{ slot.external.x - 0.4, slot.external.y - 0.4 },
				{ slot.external.x + 0.4, slot.external.y + 0.4 },
			},
		}
		for _, candidate in pairs(candidates) do
			if candidate.valid and connectionTypes[candidate.type] then
				self:connect(slotKey, candidate)
				break
			end
		end
	end
end

-- Searches all live Mythos instances for one whose slot matches the entity position.
function Mythos.findStateAndSlot(entity)
	for _, state in pairs(storage.mythoi) do
		if state.entity.valid then
			local slotKey = state:findSlotAt(entity.position)
			if slotKey then return state, slotKey end
		end
	end
end

-- Handles any entity being built; registers new mythos instances or connects neighbours.
function Mythos.onEntityBuilt(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	if entity.name == "mythos" then
		local state = Mythos.new(entity)
		storage.mythoi[entity.unit_number] = state
		state:connectExistingNeighbours()
		return
	end

	if not connectionTypes[entity.type] then return end

	local state, slotKey = Mythos.findStateAndSlot(entity)
	if not state then return end

	if state:connect(slotKey, entity) then
		entity.surface.play_sound {
			path     = "entity-close/assembling-machine-3",
			position = entity.position,
		}
	end
end

-- Handles any entity being removed; destroys mythos instances or disconnects neighbours.
function Mythos.onEntityRemoved(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	if entity.name == "mythos" then
		local state = storage.mythoi[entity.unit_number]
		if state then state:destroy() end
		return
	end

	if not connectionTypes[entity.type] then return end

	local state, slotKey = Mythos.findStateAndSlot(entity)
	if state then state:disconnect(slotKey) end
end

return Mythos
