-- ── Dimension Deletion System ─────────────────────────────────────────────────
-- Mines entities inside a pocket dimension into the nearest Mythos Inventory chest.

local Registry        = require("script.registry")
local MythosInventory = require("script.mythosInventory")

local DimensionDeletion = {}

function DimensionDeletion.install(Mythos, connectionTypes)

	function Mythos:tryDeleteEntity(entity)
		if not (entity and entity.valid) then return true end

		local isBelt    = connectionTypes[entity.type] == "belt"
		local entityPos = isBelt and { x = entity.position.x, y = entity.position.y } or nil

		local success = MythosInventory.tryMineEntity(
			self.entity.force,
			self.entity.position,
			entity,
			false
		)

		if success and isBelt and entityPos then
			local slotKey = self:findInnerSlotAt(entityPos)
			if slotKey then self:disconnect(slotKey) end
		end

		return success
	end

	function Mythos:flushPendingDeletions()
		if not (self.pendingDeletions and #self.pendingDeletions > 0) then return end

		local remaining = {}
		for _, entity in ipairs(self.pendingDeletions) do
			if entity.valid then
				if not self:tryDeleteEntity(entity) then
					remaining[#remaining + 1] = entity
				end
			end
		end
		self.pendingDeletions = remaining
	end

	function Mythos.onMarkedForDeconstruction(event)
		local entity = event.entity
		if not (entity and entity.valid) then return end

		local mineable = entity.prototype.mineable_properties
		if not (mineable and mineable.minable) then return end

		local state = Registry.findByInsideSurfaceIndex(entity.surface_index)
		if not state then return end

		if not state:tryDeleteEntity(entity) then
			state.pendingDeletions = state.pendingDeletions or {}
			state.pendingDeletions[#state.pendingDeletions + 1] = entity
		end
	end

	function Mythos.onCancelledDeconstruction(event)
		local entity = event.entity
		if not (entity and entity.valid) then return end

		local state = Registry.findByInsideSurfaceIndex(entity.surface_index)
		if not state or not state.pendingDeletions then return end

		for i = #state.pendingDeletions, 1, -1 do
			if state.pendingDeletions[i] == entity then
				table.remove(state.pendingDeletions, i)
			end
		end
	end

end

return DimensionDeletion
