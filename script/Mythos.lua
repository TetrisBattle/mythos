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

-- Module-level constant: pocket-dimension inner belt position → slot key.
-- Identical for every mythos instance, so it is never stored in storage.
local innerPosToSlot = (function()
	local t = {}
	for slotKey, beltLayout in pairs(PocketDimension.slotBeltLayout) do
		local ip = beltLayout.innerBeltPos
		t[positionKey(ip[1], ip[2])] = slotKey
	end
	return t
end)()

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
	mythosEntity.request_from_buffers = true

	-- Draw permanent gate sprites at every connection point inside the pocket dimension.
	-- These are always visible regardless of whether a belt is connected.
	for slotKey, beltLayout in pairs(PocketDimension.slotBeltLayout) do
		if slots[slotKey] then
			slots[slotKey].gateRender = rendering.draw_sprite{
				sprite      = "mythos-gate",
				target      = beltLayout.pos,
				surface     = dim,
				orientation = beltLayout.gateOrientation,
				y_scale     = 0.75,
			}
		end
	end

	-- Reverse-lookup: pocket-dimension inner belt position → slot key.
	-- (module-level constant; not stored per-state)

	return setmetatable({
		entity         = mythosEntity,
		slots          = slots,
		byExternalPos  = byExternalPos,
		inside_surface = dim,
		inside_x       = PocketDimension.VIEW_X,
		inside_y       = PocketDimension.VIEW_Y,
	}, Mythos)
end

-- Returns the slot key for the given world position, or nil.
function Mythos:findSlotAt(pos)
	return self.byExternalPos[positionKey(pos.x, pos.y)]
end

-- Returns the slot key if pos matches a pocket-dimension inner belt position.
function Mythos:findInnerSlotAt(pos)
	return innerPosToSlot[positionKey(pos.x, pos.y)]
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

	-- Belt connections require a player-placed inner belt at the designated slot
	-- position inside the pocket dimension facing the same direction.
	if connType == "belt" then
		local beltLayout = PocketDimension.slotBeltLayout[slotKey]
		if not beltLayout then slot.conn = nil; return end
		local ip = beltLayout.innerBeltPos
		local innerBelt
		for _, e in pairs(self.inside_surface.find_entities_filtered{
			area = { {ip[1] - 0.4, ip[2] - 0.4}, {ip[1] + 0.4, ip[2] + 0.4} },
		}) do
			if e.valid and connectionTypes[e.type] == "belt" and e.direction == entity.direction then
				innerBelt = e
				break
			end
		end
		if not innerBelt then slot.conn = nil; return end
		slot.conn.innerBelt = innerBelt
	end

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

	local conn     = slot.conn
	local connType = conn.connType
	local innerPos = slot.inner
	slot.conn = nil  -- innerBelt is player-placed; it stays in the world.

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

-- Called when a belt is placed inside the pocket dimension at an innerBeltPos.
-- Searches for a matching external belt and establishes the connection if directions
-- agree (both must face the same cardinal direction). Returns true on success.
function Mythos:connectFromInner(slotKey, innerEntity)
	local slot = self.slots[slotKey]
	if not slot or slot.conn then return end

	local externalBelt
	for _, e in pairs(self.entity.surface.find_entities_filtered{
		area = {
			{ slot.external.x - 0.4, slot.external.y - 0.4 },
			{ slot.external.x + 0.4, slot.external.y + 0.4 },
		},
	}) do
		if e.valid and connectionTypes[e.type] == "belt" then
			externalBelt = e
			break
		end
	end
	if not externalBelt then return end

	local inwardDir = oppositeDir[slot.outwardDir]
	if externalBelt.direction ~= slot.outwardDir and externalBelt.direction ~= inwardDir then return end
	if innerEntity.direction ~= externalBelt.direction then return end

	local ioDirection = externalBelt.direction == inwardDir and "input" or "output"
	slot.conn = {
		entity      = externalBelt,
		connType    = "belt",
		ioDirection = ioDirection,
		innerBelt   = innerEntity,
	}
	return true
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

-- Moves all items from every lane of `from` into the matching lane of `to`.
-- Any items that do not fit are returned to `from`.
local function transferBeltLines(from, to)
	for lane = 1, 2 do
		local fromLine = from.get_transport_line(lane)
		local toLine   = to.get_transport_line(lane)
		if not toLine.can_insert_at_back() then goto continue end
		for _, stack in pairs(fromLine.get_contents()) do
			local taken = fromLine.remove_item({ name = stack.name, quality = stack.quality, count = stack.count })
			if taken > 0 then
				local inserted = toLine.insert_at_back({ name = stack.name, quality = stack.quality, count = taken })
				if not inserted then
					fromLine.insert_at_back({ name = stack.name, quality = stack.quality, count = taken })
					goto continue
				end
			end
		end
		::continue::
	end
end

-- Called every 6 ticks to push items across all active belt connections,
-- then attempts to revive ghost entities using items from the chest inventory.
function Mythos.onNthTick()
	for _, state in pairs(storage.mythoi) do
		if not state.entity.valid then goto continue end
		for _, slot in pairs(state.slots) do
			local conn = slot.conn
			if conn and conn.connType == "belt"
					and conn.entity.valid
					and conn.innerBelt and conn.innerBelt.valid then
				if conn.ioDirection == "input" then
					transferBeltLines(conn.entity, conn.innerBelt)
				else
					transferBeltLines(conn.innerBelt, conn.entity)
				end
			end
		end
		state:buildGhosts()
		::continue::
	end
end

-- Scans ghost entities in the pocket dimension and updates the requester chest's
-- logistic sections so the logistic network delivers the required items.
-- Also trashes chest items that are no longer needed (trash-unrequested behaviour).
-- Called every ~60 ticks (roughly once per second).
function Mythos:updateRequests()
	if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

	-- Accumulate one item-stack per ghost (first entry of items_to_place_this).
	local needed = {}
	local ghosts = self.inside_surface.find_entities_filtered{ type = "entity-ghost" }
	for _, ghost in pairs(ghosts) do
		if ghost.valid then
			local proto  = ghost.ghost_prototype
			local stacks = proto and proto.items_to_place_this
			local stack  = stacks and stacks[1]
			if stack then
				needed[stack.name] = (needed[stack.name] or 0) + stack.count
			end
		end
	end

	-- Update the chest's logistic section.
	local sections = self.entity.get_logistic_sections()
	if not sections then return end

	local section = sections.get_section(1) or sections.add_section()
	if not section then return end

	local filters = {}

	-- Request exactly the needed amount; setting max = min returns any excess to the network.
	for itemName, count in pairs(needed) do
		filters[#filters + 1] = {
			value = { type = "item", name = itemName, quality = "normal" },
			min   = count,
			max   = count,
		}
	end

	-- Explicitly trash items already in the chest that are no longer needed.
	local inv = self.entity.get_inventory(defines.inventory.chest)
	if inv then
		local trashed = {}
		for i = 1, #inv do
			local slot = inv[i]
			if slot.valid_for_read then
				local name = slot.name
				if not needed[name] and not trashed[name] then
					trashed[name] = true
					filters[#filters + 1] = {
						value = { type = "item", name = name, quality = "normal" },
						min   = 0,
						max   = 0,
					}
				end
			end
		end
	end

	section.filters = filters
end

-- Tries to revive every ghost entity inside the pocket dimension by consuming
-- items from the mythos chest inventory.  Called every 6 ticks.
function Mythos:buildGhosts()
	if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

	local ghosts = self.inside_surface.find_entities_filtered{ type = "entity-ghost" }
	if #ghosts == 0 then return end

	local inv = self.entity.get_inventory(defines.inventory.chest)
	if not inv then return end

	for _, ghost in pairs(ghosts) do
		if not ghost.valid then goto continue end

		local proto  = ghost.ghost_prototype
		local stacks = proto and proto.items_to_place_this
		local stack  = stacks and stacks[1]

		if stack then
			-- Need an item to place this ghost; check availability.
			if inv.get_item_count(stack.name) < stack.count then goto continue end
			inv.remove({ name = stack.name, count = stack.count })
			local leftover = ghost.revive{ raise_revive = true }
			if leftover == nil then
				-- Revive failed (collision, etc.); return the items.
				inv.insert({ name = stack.name, count = stack.count })
			end
		else
			-- Entity needs no item to be placed (e.g. no minable form).
			ghost.revive{ raise_revive = true }
		end

		::continue::
	end
end

-- Called every ~60 ticks to refresh logistic requests for all mythos instances.
function Mythos.onSlowTick()
	for _, state in pairs(storage.mythoi) do
		if state.entity.valid then
			state:updateRequests()
		end
	end
end

-- Handles any entity being built; registers new mythos instances or connects neighbours.
function Mythos.onEntityBuilt(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	-- Belt placed inside a pocket dimension: try to complete a connection from the inner side.
	local unitNum = tonumber(entity.surface.name:match("^mythos%-dimension%-(%d+)$"))
	if unitNum then
		local state = storage.mythoi[unitNum]
		if state and state.entity.valid and connectionTypes[entity.type] == "belt" then
			local slotKey = state:findInnerSlotAt(entity.position)
			if slotKey and state:connectFromInner(slotKey, entity) then
				entity.surface.play_sound{ path = "entity-close/assembling-machine-3", position = entity.position }
			end
		end
		return
	end

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
-- When an entity inside a pocket dimension is mined, its items are redirected to the
-- mythos chest instead of going to the player's / robot's inventory.
function Mythos.onEntityRemoved(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	if entity.name == "mythos" then
		local state = storage.mythoi[entity.unit_number]
		if state then state:destroy() end
		return
	end

	-- Handle entities removed from inside a pocket dimension.
	do
		local surfaceIndex = entity.surface_index
		for _, state in pairs(storage.mythoi) do
			if state.inside_surface and state.inside_surface.valid
					and state.inside_surface.index == surfaceIndex
					and state.entity.valid then
				-- Disconnect if this is a belt at a connection slot.
				if connectionTypes[entity.type] == "belt" then
					local slotKey = state:findInnerSlotAt(entity.position)
					if slotKey then state:disconnect(slotKey) end
				end
				-- Redirect any mined items to the chest.
				if event.buffer then
					local inv = state.entity.get_inventory(defines.inventory.chest)
					if inv then
						for i = 1, #event.buffer do
							local stack = event.buffer[i]
							if stack.valid_for_read then
								inv.insert(stack)
								stack.clear()
							end
						end
					end
				end
				return
			end
		end
	end

	if not connectionTypes[entity.type] then return end

	local state, slotKey = Mythos.findStateAndSlot(entity)
	if state then state:disconnect(slotKey) end
end

return Mythos
