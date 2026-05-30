local PocketDimension   = require("script.PocketDimension")
local util              = require("script.util")
local Connections       = require("script.connections")
local Logistics         = require("script.logistics")
local DimensionDeletion = require("script.dimensionDeletion")

local positionKey = util.positionKey

-- ── Entity → connection-type mapping ──────────────────────────────────────────
-- Used to decide how a slot should be wired when an entity is placed next to
-- (or inside) a mythos.  Belts move items, pipes move fluid, heat-pipes move heat.
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

-- ── Mythos class ───────────────────────────────────────────────────────────────
-- One instance per placed mythos entity.
-- Stores the pocket-dimension surface, slot geometry, and all active connections.
-- Persisted in storage.mythoi[unit_number]; metatables are restored on game load.

local Mythos = {}
Mythos.__index        = Mythos
Mythos.connectionTypes = connectionTypes  -- exposed for callers that need the map

-- Creates a new Mythos instance for a freshly placed entity.
function Mythos.new(mythosEntity)
	local cx = mythosEntity.position.x
	local cy = mythosEntity.position.y

	local slots, byExternalPos = Connections.buildSlots(cx, cy)

	local dim = PocketDimension.create(mythosEntity.unit_number, mythosEntity.force)
	mythosEntity.request_from_buffers = true

	-- Draw permanent gate sprites at every connection point inside the dimension.
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

	return setmetatable({
		entity           = mythosEntity,
		slots            = slots,
		byExternalPos    = byExternalPos,
		inside_surface   = dim,
		inside_x         = PocketDimension.VIEW_X,
		inside_y         = PocketDimension.VIEW_Y,
		pendingDeletions = {},
	}, Mythos)
end

-- Returns the external-slot key for a world position, or nil.
function Mythos:findSlotAt(pos)
	return self.byExternalPos[positionKey(pos.x, pos.y)]
end

-- Returns true when at least one slot sharing the same inner tile still has an
-- active connection.  Corner slots can share a tile, so this prevents removing
-- a shared hidden proxy connector before both slots are disconnected.
function Mythos:innerPositionStillNeeded(innerPos)
	local key = positionKey(innerPos.x, innerPos.y)
	for _, slot in pairs(self.slots) do
		if slot.conn and positionKey(slot.inner.x, slot.inner.y) == key then
			return true
		end
	end
	return false
end

-- Disconnects all slots, deletes the pocket-dimension surface, and removes this
-- instance from global storage.
function Mythos:destroy()
	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	if self.inside_surface and self.inside_surface.valid then
		game.delete_surface(self.inside_surface)
	end
	storage.mythoi[self.entity.unit_number] = nil
end

-- ── Sub-system installation ────────────────────────────────────────────────────
-- Each module adds its methods directly onto the Mythos prototype.
Connections.install(Mythos, connectionTypes)
Logistics.install(Mythos)
DimensionDeletion.install(Mythos, connectionTypes)

-- ── Belt item transport ────────────────────────────────────────────────────────
-- Moves all items from every lane of `from` into the matching lane of `to`.
-- Items that do not fit are left on `from`.
local function transferBeltLines(from, to)
	for lane = 1, 2 do
		local fromLine = from.get_transport_line(lane)
		local toLine   = to.get_transport_line(lane)
		for _, stack in pairs(fromLine.get_contents()) do
			local single = { name = stack.name, quality = stack.quality, count = 1 }
			for _ = 1, stack.count do
				if not toLine.can_insert_at_back() then goto nextLane end
				local taken = fromLine.remove_item(single)
				if taken > 0 then
					if not toLine.insert_at_back(single) then
						fromLine.insert_at_back(single)
						goto nextLane
					end
				end
			end
		end
		::nextLane::
	end
end

-- ── Tick handlers ──────────────────────────────────────────────────────────────

-- Called every 6 ticks: pushes items across active belt connections, then tries
-- to revive pending ghosts inside each pocket dimension.
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

-- Called every 60 ticks: refreshes logistic requests and retries any deletions
-- that were blocked because the mythos chest was full.
function Mythos.onSlowTick()
	for _, state in pairs(storage.mythoi) do
		if state.entity.valid then
			state:updateRequests()
			state:flushPendingDeletions()
		end
	end
end

-- ── Entity event handlers ──────────────────────────────────────────────────────

-- Handles any entity being built anywhere in the world.
function Mythos.onEntityBuilt(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	-- Case 1: entity placed inside a pocket dimension.
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

	-- Case 2: a new mythos entity was placed.
	if entity.name == "mythos" then
		local state = Mythos.new(entity)
		storage.mythoi[entity.unit_number] = state
		state:connectExistingNeighbours()
		return
	end

	-- Case 3: a connectable entity was placed next to an existing mythos.
	if not connectionTypes[entity.type] then return end
	local state, slotKey = Mythos.findStateAndSlot(entity)
	if not state then return end
	if state:connect(slotKey, entity) then
		entity.surface.play_sound{ path = "entity-close/assembling-machine-3", position = entity.position }
	end
end

-- Handles any entity being removed anywhere in the world.
-- Items mined from inside a pocket dimension are redirected to the mythos chest.
function Mythos.onEntityRemoved(event)
	local entity = event.entity
	if not (entity and entity.valid) then return end

	-- Case 1: the mythos entity itself was removed.
	if entity.name == "mythos" then
		local state = storage.mythoi[entity.unit_number]
		if state then state:destroy() end
		return
	end

	-- Case 2: an entity was removed from inside a pocket dimension.
	local surfaceIndex = entity.surface_index
	for _, state in pairs(storage.mythoi) do
		if state.inside_surface and state.inside_surface.valid
				and state.inside_surface.index == surfaceIndex
				and state.entity.valid then

			-- Keep connection state consistent if a belt gate was removed.
			if connectionTypes[entity.type] == "belt" then
				local slotKey = state:findInnerSlotAt(entity.position)
				if slotKey then state:disconnect(slotKey) end
			end

			-- Redirect mined items to the chest instead of the player/robot inventory.
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

	-- Case 3: a connectable entity next to a mythos was removed.
	if not connectionTypes[entity.type] then return end
	local state, slotKey = Mythos.findStateAndSlot(entity)
	if state then state:disconnect(slotKey) end
end

return Mythos
