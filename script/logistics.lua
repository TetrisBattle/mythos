-- ── Logistics System ──────────────────────────────────────────────────────────
-- Manages auto-building of ghost entities using items from Mythos Inventory chests.

local MythosInventory = require("script.mythosInventory")

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
	MythosInventory.insertItemsIntoInventories(inventories, items)
end

local function materializeGhost(ghost, inventories, requests)
	for _, req in ipairs(requests) do
		local needed = req.count or 1
		if MythosInventory.getItemCountFromInventories(inventories, req) < needed then
			return false
		end
	end

	local consumed = {}
	for _, req in ipairs(requests) do
		local needed  = req.count or 1
		local removed = MythosInventory.removeItemsFromInventories(inventories, req)
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

	local quality
	if ghost.quality and ghost.quality.valid then
		quality = ghost.quality.name
	end
	if not quality and requests[1] then
		quality = requests[1].quality
	end
	local params  = {
		name        = ghost.ghost_name,
		position    = ghost.position,
		direction   = ghost.direction,
		force       = ghost.force,
		raise_built = true,
	}
	if quality then
		params.quality = quality
	end

	local created = ghost.surface.create_entity(params)
	if not (created and created.valid) then
		refundRequests(inventories, consumed)
		return false
	end

	ghost.destroy{ raise_destroy = false }
	return true
end

function Logistics.install(Mythos)

	function Mythos:buildGhosts()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

		local inventories = MythosInventory.sortedInventoriesForMythos(self)
		if #inventories == 0 then return end

		local ghosts = self.inside_surface.find_entities_filtered{ type = "entity-ghost" }

		for _, ghost in pairs(ghosts) do
			if not ghost.valid then goto continue end

			local requests = MythosInventory.ghostRequests(ghost)
			if requests and #requests > 0 then
				materializeGhost(ghost, inventories, requests)
			else
				ghost.revive{ raise_revive = true }
			end

			::continue::
		end
	end

end

return Logistics
