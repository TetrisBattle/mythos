-- ── Logistics System ──────────────────────────────────────────────────────────
-- Manages auto-building of ghost entities using items from Virtual chests.

local VirtualChest = require("script.virtual_chest.init")
local Config       = require("script.config")

local Logistics = {}

local function refundRequests(inventories, requests)
	local items = {}
	for _, req in ipairs(requests) do
		items[#items + 1] = {
			name    = req.name,
			count   = req.count or 1,
			quality = req.quality,
		}
	end
	VirtualChest.insertItemsIntoInventories(inventories, items)
end

local function materializeGhost(ghost, inventories, requests)
	for _, req in ipairs(requests) do
		local needed = req.count or 1
		if VirtualChest.getItemCountFromInventories(inventories, req) < needed then
			return false
		end
	end

	local consumed = {}
	for _, req in ipairs(requests) do
		local needed  = req.count or 1
		local removed = VirtualChest.removeItemsFromInventories(inventories, req)
		if removed < needed then
			if removed > 0 then
				consumed[#consumed + 1] = {
					name    = req.name,
					count   = removed,
					quality = req.quality,
				}
			end
			refundRequests(inventories, consumed)
			return false
		end
		consumed[#consumed + 1] = {
			name    = req.name,
			count   = removed,
			quality = req.quality,
		}
	end

	local _, created = ghost.silent_revive{ raise_revive = true }
	if not (created and created.valid) then
		refundRequests(inventories, consumed)
		return false
	end

	return true
end

local function materializeGhostFree(ghost)
	local _, created = ghost.silent_revive{ raise_revive = true }
	return created and created.valid
end

function Logistics.install(Mythos)

	function Mythos:buildGhosts()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

		local inventories = VirtualChest.sortedInventoriesForMythos(self)
		local ghosts = self.inside_surface.find_entities_filtered{ type = "entity-ghost" }
		local no_cost = Config.noCost()

		for _, ghost in pairs(ghosts) do
			if ghost.valid then

				local requests = VirtualChest.ghostRequests(ghost)
				if requests and #requests > 0 then

					if no_cost then
						materializeGhostFree(ghost)
					elseif #inventories > 0 then
						materializeGhost(ghost, inventories, requests)
					end
				end
			end
		end
	end

end

return Logistics
