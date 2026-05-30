-- ── Dimension Deletion System ─────────────────────────────────────────────────
-- When a player marks an entity inside a pocket dimension for deconstruction,
-- this system automatically mines it and moves everything (the entity itself
-- plus any items inside its inventories) into the mythos chest.
--
-- If the chest is full the entity is queued and retried every ~60 ticks.
-- Cancelling the deconstruction mark removes the entity from the queue.
--
-- The feature works for any entity: assemblers, belts with items on them,
-- furnaces with fuel and ingredients inside — all contents transfer atomically.
-- If even one item cannot fit the entire operation is deferred.

local DimensionDeletion = {}

function DimensionDeletion.install(Mythos, connectionTypes)

	-- Returns the Mythos state whose pocket dimension has the given surface index,
	-- or nil if the surface does not belong to any live pocket dimension.
	local function findStateForSurface(surfaceIndex)
		for _, state in pairs(storage.mythoi) do
			if state.inside_surface
					and state.inside_surface.valid
					and state.inside_surface.index == surfaceIndex
					and state.entity.valid then
				return state
			end
		end
	end

	-- Attempts to mine `entity` directly into the mythos chest.
	-- entity.mine() is atomic: it only destroys the entity if every item
	-- (entity item + all inventory contents) fits into the target inventory.
	-- If the entity was a belt at a gate position, the slot is disconnected.
	-- Returns true if mining succeeded, false if the chest was too full.
	function Mythos:tryDeleteEntity(entity)
		if not (entity and entity.valid) then return true end

		local inv = self.entity.get_inventory(defines.inventory.chest)
		if not inv then return false end

		-- Capture position and type before mine() invalidates the entity reference.
		local isBelt    = connectionTypes[entity.type] == "belt"
		local entityPos = isBelt and { x = entity.position.x, y = entity.position.y } or nil

		-- mine() deposits the entity item + all inventory contents into inv.
		-- Returns false without destroying the entity if inv lacks sufficient space.
		local success = entity.mine{ inventory = inv, raise_destroyed = false }

		if success and isBelt and entityPos then
			-- Disconnect the gate slot so the connection state stays consistent.
			local slotKey = self:findInnerSlotAt(entityPos)
			if slotKey then self:disconnect(slotKey) end
		end

		return success
	end

	-- Retries all pending deletions for this state.  Called from onSlowTick.
	-- Entities successfully mined are removed from the queue.
	-- Entities already gone (mined by other means) are silently dropped.
	function Mythos:flushPendingDeletions()
		if not (self.pendingDeletions and #self.pendingDeletions > 0) then return end

		local remaining = {}
		for _, entity in ipairs(self.pendingDeletions) do
			if entity.valid then
				if not self:tryDeleteEntity(entity) then
					remaining[#remaining + 1] = entity  -- Still no room; keep in queue.
				end
			end
			-- Entities no longer valid were removed by other means — just drop them.
		end
		self.pendingDeletions = remaining
	end

	-- Fired when any entity inside a pocket dimension is marked for deconstruction.
	-- Tries an immediate mine; queues the entity for retry if the chest was full.
	function Mythos.onMarkedForDeconstruction(event)
		local entity = event.entity
		if not (entity and entity.valid) then return end

		-- Non-minable entities (hidden infrastructure, walls, etc.) can never be
		-- transferred to the chest, so ignore them entirely.
		local mineable = entity.prototype.mineable_properties
		if not (mineable and mineable.minable) then return end

		local state = findStateForSurface(entity.surface_index)
		if not state then return end

		if not state:tryDeleteEntity(entity) then
			-- Chest was full; queue for retry on the next slow tick.
			state.pendingDeletions = state.pendingDeletions or {}
			state.pendingDeletions[#state.pendingDeletions + 1] = entity
		end
	end

	-- Fired when a deconstruction mark is cancelled inside a pocket dimension.
	-- Removes the entity from the pending-retry queue so it won't be mined later.
	function Mythos.onCancelledDeconstruction(event)
		local entity = event.entity
		if not (entity and entity.valid) then return end

		local state = findStateForSurface(entity.surface_index)
		if not state or not state.pendingDeletions then return end

		for i = #state.pendingDeletions, 1, -1 do
			if state.pendingDeletions[i] == entity then
				table.remove(state.pendingDeletions, i)
			end
		end
	end

end

return DimensionDeletion
