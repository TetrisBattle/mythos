-- ── Logistics System ──────────────────────────────────────────────────────────
-- Manages auto-building of ghost entities using items from Virtual chests.

local VirtualChest = require("script.virtual_chest.init")
local Config       = require("script.config")

local Logistics = {}

local function ghostQuality(ghost)
	if ghost.quality and ghost.quality.valid then
		return ghost.quality.name
	end
	return nil
end

local function normalizePlaceRequests(source, quality)
	local list = {}
	if not source then return list end

	if source[1] then
		for _, entry in ipairs(source) do
			if type(entry) == "table" and entry.name then
				list[#list + 1] = {
					name    = entry.name,
					count   = entry.count or 1,
					quality = entry.quality or quality,
				}
			end
		end
		return list
	end

	for name, entry in pairs(source) do
		if type(name) == "string" then
			local count = 1
			if type(entry) == "table" and entry.count then
				count = entry.count
			end
			list[#list + 1] = {
				name    = name,
				count   = count,
				quality = quality,
			}
		end
	end

	return list
end

local function ghostPlaceRequests(ghost)
	local quality = ghostQuality(ghost)
	local proto = ghost.ghost_prototype
	if proto and proto.items_to_place_this then
		local list = normalizePlaceRequests(proto.items_to_place_this, quality)
		if #list > 0 then return list end
	end

	if ghost.ghost_name then
		return { { name = ghost.ghost_name, count = 1, quality = quality } }
	end

	return nil
end

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

local function requestCanBeProvided(inventories, req)
	return VirtualChest.getItemCountFromInventories(inventories, req) >= (req.count or 1)
end

local function consumeRequest(inventories, req)
	return VirtualChest.removeItemsFromInventories(inventories, req)
end

local function satisfyModuleRequests(entity, inventories, requests)
	if not (entity and entity.valid and requests and #requests > 0) then return false end

	local inventory = entity.get_module_inventory and entity.get_module_inventory()
	if not (inventory and inventory.valid) then return false end

	local all_satisfied = true
	for _, req in ipairs(requests) do
		local stack = {
			name    = req.name,
			count   = req.count or 1,
			quality = req.quality,
		}
		if inventory.can_insert(stack) and requestCanBeProvided(inventories, req) then
			local removed = consumeRequest(inventories, req)
			if removed > 0 then
				local inserted = inventory.insert{
					name    = req.name,
					count   = removed,
					quality = req.quality,
				}
				if inserted < removed then
					refundRequests(inventories, {
						{
							name    = req.name,
							count   = removed - inserted,
							quality = req.quality,
						},
					})
				end
				if inserted < (req.count or 1) then
					all_satisfied = false
				end
			end
		else
			all_satisfied = false
		end
	end
	return all_satisfied
end

local function satisfyModuleRequestsFree(entity, requests)
	if not (entity and entity.valid and requests and #requests > 0) then return false end

	local inventory = entity.get_module_inventory and entity.get_module_inventory()
	if not (inventory and inventory.valid) then return false end

	local all_satisfied = true
	for _, req in ipairs(requests) do
		local inserted = inventory.insert{
			name    = req.name,
			count   = req.count or 1,
			quality = req.quality,
		}
		if inserted < (req.count or 1) then
			all_satisfied = false
		end
	end
	return all_satisfied
end

local function satisfyItemRequestProxy(proxy, inventories, target)
	if not (proxy and proxy.valid) then return end
	local requests = proxy.item_requests
	if not (requests and #requests > 0) then return end
	if satisfyModuleRequests(target, inventories, requests) and proxy.valid then
		proxy.destroy{ raise_destroy = false }
	end
end

local function materializeGhost(ghost, inventories, requests)
	for _, req in ipairs(requests) do
		if not requestCanBeProvided(inventories, req) then
			return false
		end
	end

	local consumed = {}
	for _, req in ipairs(requests) do
		local removed = consumeRequest(inventories, req)
		if removed < (req.count or 1) then
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

	local _, created, proxy = ghost.silent_revive{ raise_revive = true }
	if not (created and created.valid) then
		refundRequests(inventories, consumed)
		return false
	end

	satisfyItemRequestProxy(proxy or created.item_request_proxy, inventories, created)
	return true
end

local function materializeGhostFree(ghost)
	local _, created, proxy = ghost.silent_revive{ raise_revive = true }
	if created and created.valid then
		proxy = proxy or created.item_request_proxy
		if proxy and proxy.valid
				and satisfyModuleRequestsFree(created, proxy.item_requests)
				and proxy.valid then
			proxy.destroy{ raise_destroy = false }
		end
	end
	return created and created.valid
end

local function satisfyRequestProxyForEntity(proxy, inventories, no_cost)
	if not (proxy and proxy.valid) then return end
	local target = proxy.proxy_target
	if not (target and target.valid) then return end

	if no_cost then
		if satisfyModuleRequestsFree(target, proxy.item_requests) and proxy.valid then
			proxy.destroy{ raise_destroy = false }
		end
	elseif inventories and #inventories > 0 then
		satisfyItemRequestProxy(proxy, inventories, target)
	end
end

function Logistics.install(Mythos)

	function Mythos:buildGhostFree(ghost)
		if not (ghost and ghost.valid and ghost.type == "entity-ghost") then return false end

		local requests = ghostPlaceRequests(ghost)
		if not (requests and #requests > 0) then return false end

		return materializeGhostFree(ghost)
	end

	function Mythos:buildGhosts()
		if not (self.entity.valid and self.inside_surface and self.inside_surface.valid) then return end

		local ghosts = self.inside_surface.find_entities_filtered{ type = "entity-ghost" }

		local no_cost = Config.noCost()
		local inventories = no_cost and nil or VirtualChest.sortedInventoriesForMythos(self)

		for _, proxy in pairs(self.inside_surface.find_entities_filtered{ name = "item-request-proxy" }) do
			satisfyRequestProxyForEntity(proxy, inventories, no_cost)
		end

		if #ghosts == 0 then return end

		for _, ghost in pairs(ghosts) do
			if ghost.valid then

				local requests = ghostPlaceRequests(ghost)
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
