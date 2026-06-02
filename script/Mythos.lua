local PocketDimension   = require("script.PocketDimension")
local util              = require("script.util")
local Connections       = require("script.connections")
local Logistics         = require("script.logistics")
local DimensionDeletion = require("script.dimensionDeletion")

local positionKey       = util.positionKey

-- ── Entity → connection-type mapping ──────────────────────────────────────────
-- Used to decide how a slot should be wired when an entity is placed next to
-- (or inside) a mythos.  Belts move items, pipes move fluid, heat-pipes move heat.
local connectionTypes   = {
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

local Mythos            = {}
Mythos.__index          = Mythos
Mythos.connectionTypes  = connectionTypes -- exposed for callers that need the map

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
			slots[slotKey].gateRender = rendering.draw_sprite {
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

-- Returns true when the mythos has items in its chest or non-default entities
-- in the pocket dimension.  Pass the mining `buffer` when called from a mine
-- event, because Factorio drains the chest into the buffer before it fires.
function Mythos:hasContents(buffer)
	if buffer then
		for i = 1, #buffer do
			local s = buffer[i]
			if s.valid_for_read and s.name ~= "mythos" and s.name ~= "mythos-with-contents" then
				return true
			end
		end
	else
		local inv = self.entity.get_inventory(defines.inventory.chest)
		if inv and not inv.is_empty() then return true end
	end
	if self.inside_surface and self.inside_surface.valid then
		for _, e in pairs(self.inside_surface.find_entities()) do
			if e.valid and e.name ~= "stone-wall" and e.name ~= "mythos-hidden-radar" then
				return true
			end
		end
		-- find_entities() does not return ghost entities; check explicitly.
		if #self.inside_surface.find_entities_filtered { type = "entity-ghost" } > 0 then
			return true
		end
		if #self.inside_surface.find_entities_filtered { type = "tile-ghost" } > 0 then
			return true
		end
	end
	return false
end

-- Preserves this mythos for future restoration: keeps the pocket-dimension alive,
-- snapshots chest items (stripping them from `buffer` for mine events, or
-- draining the chest for death events to prevent loot spill), disconnects all
-- slots, and removes this instance from the active table WITHOUT deleting the
-- surface.  Returns the saved_id to embed in the pickup item.
function Mythos:save(buffer)
	local saved_id = self.entity.unit_number
	local items    = {}

	if buffer then
		-- Mining path: chest contents already moved to buffer by Factorio.
		for i = 1, #buffer do
			local s = buffer[i]
			if s.valid_for_read and s.name ~= "mythos" and s.name ~= "mythos-with-contents" then
				items[#items + 1] = {
					name    = s.name,
					count   = s.count,
					quality = s.quality and s.quality.name or "normal",
				}
				s.clear()
			end
		end
	else
		-- Death / script-destroy path: chest not yet spilled.
		local inv = self.entity.get_inventory(defines.inventory.chest)
		if inv then
			for i = 1, #inv do
				local slot = inv[i]
				if slot.valid_for_read then
					items[#items + 1] = {
						name    = slot.name,
						count   = slot.count,
						quality = slot.quality and slot.quality.name or "normal",
					}
				end
			end
			inv.clear() -- prevent engine loot spill
		end
	end

	storage.saved_dimensions = storage.saved_dimensions or {}
	storage.saved_dimensions[saved_id] = { surface = self.inside_surface, items = items }

	for slotKey in pairs(self.slots) do
		self:disconnect(slotKey)
	end
	storage.mythoi[self.entity.unit_number] = nil
	return saved_id
end

-- Returns the saved_id embedded in the item used to build `entity`, or nil.
-- For player builds reads from the per-player cursor cache set by onCursorChanged.
-- For robot builds attempts a best-effort read of event.stack.tags.
function Mythos.extractSavedId(event)
	-- Reject only when we can positively identify a non-saved item was used.
	-- Allowing nil covers cases where Factorio does not populate event.item.
	if event.item and event.item.name ~= "mythos-with-contents" then return nil end
	if event.player_index then
		storage.pending_player_restore = storage.pending_player_restore or {}
		local saved_id = storage.pending_player_restore[event.player_index]
		if saved_id then
			storage.pending_player_restore[event.player_index] = nil
			return saved_id
		end
	end
	-- Robot build: attempt to read tags from the (possibly empty) cargo slot.
	local stack = event.stack
	if stack and stack.valid then
		local ok, tags = pcall(function() return stack.tags end)
		if ok and tags and tags.saved_id then return tags.saved_id end
	end
	return nil
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

-- ── Heat transport ───────────────────────────────────────────────────────────
-- Equalises temperature between the outer and inner hidden heat-pipe proxies.
-- Averages the two temperatures and applies the result to both entities so the
-- two networks converge each tick.
local function transferHeat(a, b)
	local avg = (a.temperature + b.temperature) * 0.5
	a.temperature = avg
	b.temperature = avg
end

-- ── Fluid transport ───────────────────────────────────────────────────────────
-- Equalises fluid between the outer hidden pipe (connected to the external
-- network via Factorio's native fluid sim) and the inner pocket-dimension pipe
-- (which the player's internal network connects to).  Called every 6 ticks.
-- Each of the two pipes is a full-capacity vanilla pipe (100 units), so we
-- move half the difference each call to converge quickly without overshooting.
local function transferFluid(a, b)
	local aContents = a.get_fluid_contents()
	local bContents = b.get_fluid_contents()
	-- Merge all fluid names present on either side.
	local fluids = {}
	for name in pairs(aContents) do fluids[name] = true end
	for name in pairs(bContents) do fluids[name] = true end
	for fluidName in pairs(fluids) do
		local aAmt = aContents[fluidName] or 0
		local bAmt = bContents[fluidName] or 0
		local diff = aAmt - bAmt
		if diff > 0.01 then
			local moved = a.remove_fluid({ name = fluidName, amount = diff * 0.5 })
			if moved > 0 then b.insert_fluid({ name = fluidName, amount = moved }) end
		elseif diff < -0.01 then
			local moved = b.remove_fluid({ name = fluidName, amount = -diff * 0.5 })
			if moved > 0 then a.insert_fluid({ name = fluidName, amount = moved }) end
		end
	end
end

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
			if conn and conn.connType == "pipe"
				and conn.outerProxy and conn.outerProxy.valid
				and conn.innerProxy and conn.innerProxy.valid then
				transferFluid(conn.outerProxy, conn.innerProxy)
			end
			if conn and conn.connType == "heat-pipe"
				and conn.outerProxy and conn.outerProxy.valid
				and conn.innerProxy and conn.innerProxy.valid then
				transferHeat(conn.outerProxy, conn.innerProxy)
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
				entity.surface.play_sound { path = "entity-close/assembling-machine-3", position = entity.position }
			end
		end
		return
	end

	-- Case 2: a new mythos entity was placed.
	if entity.name == "mythos" then
		local saved_id = Mythos.extractSavedId(event)
		local saved    = saved_id and storage.saved_dimensions and storage.saved_dimensions[saved_id]
		if saved then
			-- Restore from a previously saved pocket dimension.
			storage. ---@diagnostic disable-next-line: need-check-nil
			saved_dimensions[saved_id] = nil
			local cx = entity.position.x
			local cy = entity.position.y
			local slots, byExternalPos = Connections.buildSlots(cx, cy)
			-- Gate sprites already exist on the saved surface; no need to re-draw.
			local state = setmetatable({
				entity           = entity,
				slots            = slots,
				byExternalPos    = byExternalPos,
				inside_surface   = saved.surface,
				inside_x         = PocketDimension.VIEW_X,
				inside_y         = PocketDimension.VIEW_Y,
				pendingDeletions = {},
			}, Mythos)
			entity.request_from_buffers = true
			local inv = entity.get_inventory(defines.inventory.chest)
			if inv and saved.items then
				for _, item in pairs(saved.items) do
					inv.insert({ name = item.name, count = item.count, quality = item.quality })
				end
			end
			storage.mythoi[entity.unit_number] = state
			state:connectExistingNeighbours()
		else
			local state = Mythos.new(entity)
			storage.mythoi[entity.unit_number] = state
			state:connectExistingNeighbours()
		end
		return
	end

	-- Case 3: a connectable entity was placed next to an existing mythos.
	if not connectionTypes[entity.type] then return end
	local state, slotKey = Mythos.findStateAndSlot(entity)
	if not state then return end
	if state:connect(slotKey, entity) then
		entity.surface.play_sound { path = "entity-close/assembling-machine-3", position = entity.position }
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
		if state then
			if state:hasContents(event.buffer) then
				local saved_id = state:save(event.buffer)
				if event.buffer then
					-- Mined by player or robot: swap mythos → mythos-with-contents.
					event.buffer.remove({ name = "mythos", count = 1 })
					event.buffer.insert({ name = "mythos-with-contents", count = 1 })
					for i = 1, #event.buffer do
						local s = event.buffer[i]
						if s.valid_for_read and s.name == "mythos-with-contents" then
							s.tags = { saved_id = saved_id }
							break
						end
					end
					-- Prime the restore cache directly so it is available in onEntityBuilt
					-- even if the cursor-stack tag mechanism fails (e.g. on_player_cursor_stack_changed
					-- fires while the cursor is still the mining tool, clearing the cache).
					if event.player_index then
						storage.pending_player_restore = storage.pending_player_restore or {}
						storage.pending_player_restore[event.player_index] = saved_id
					end
				else
					-- Killed or script-destroyed: drop item on the ground.
					local dropped = entity.surface.create_entity {
						name     = "item-on-ground",
						position = entity.position,
						stack    = { name = "mythos-with-contents", count = 1 },
					}
					if dropped and dropped.valid then
						dropped.stack.tags = { saved_id = saved_id }
					end
				end
			else
				state:destroy()
			end
		end
		return
	end

	-- Case 2: an entity was removed from inside a pocket dimension.
	local surfaceIndex = entity.surface_index
	for _, state in pairs(storage.mythoi) do
		if state.inside_surface and state.inside_surface.valid
			and state.inside_surface.index == surfaceIndex
			and state.entity.valid then
			-- Pocket-dimension walls are permanent: rebuild immediately and discard
			-- the mined item so it is neither given to the player nor to the chest.
			if entity.name == "stone-wall" then
				state.inside_surface.create_entity {
					name        = "stone-wall",
					position    = entity.position,
					force       = entity.force,
					raise_built = false,
				}
				if event.buffer then
					for i = 1, #event.buffer do
						if event.buffer[i].valid_for_read then event.buffer[i].clear() end
					end
				end
				return
			end

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

-- Caches the saved_id from a mythos-with-contents cursor item so it is
-- available in onEntityBuilt (which fires before the cursor is consumed).
function Mythos.onCursorChanged(event)
	storage.pending_player_restore = storage.pending_player_restore or {}
	local player = game.get_player(event.player_index)
	if not player then return end
	local stack = player.cursor_stack
	if stack and stack.valid_for_read and stack.name == "mythos-with-contents" then
		local tags = stack.tags
		storage.pending_player_restore[event.player_index] = tags and tags.saved_id
	else
		storage.pending_player_restore[event.player_index] = nil
	end
end

return Mythos
