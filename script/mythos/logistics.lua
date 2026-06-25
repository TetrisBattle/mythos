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

local function stackQuality(quality)
	if not quality then return nil end
	if type(quality) == "string" then return quality end
	return quality.name
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
					quality = stackQuality(entry.quality) or quality,
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

local function itemRequests(source)
	return normalizePlaceRequests(source, nil)
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

local function inventoryLookup(req)
	if req.quality then
		return { name = req.name, quality = req.quality }
	end
	return req.name
end

local function inventoryItemCount(inventory, req)
	return inventory.get_item_count(inventoryLookup(req))
end

local function satisfyModuleRequests(entity, inventories, requests)
	requests = itemRequests(requests)
	if not (entity and entity.valid and #requests > 0) then return false end

	local inventory = entity.get_module_inventory and entity.get_module_inventory()
	if not (inventory and inventory.valid) then return false end

	local all_satisfied = true
	for _, req in ipairs(requests) do
		local needed = (req.count or 1) - inventoryItemCount(inventory, req)
		if needed <= 0 then
			-- Already satisfied; a stale proxy can be removed.
		elseif inventory.can_insert({
				name    = req.name,
				count   = needed,
				quality = req.quality,
			}) and requestCanBeProvided(inventories, {
				name    = req.name,
				count   = needed,
				quality = req.quality,
			}) then
			local removed = consumeRequest(inventories, {
				name    = req.name,
				count   = needed,
				quality = req.quality,
			})
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
				if inserted < needed then
					all_satisfied = false
				end
			else
				all_satisfied = false
			end
		else
			all_satisfied = false
		end
	end
	return all_satisfied
end

local function satisfyModuleRequestsFree(entity, requests)
	requests = itemRequests(requests)
	if not (entity and entity.valid and #requests > 0) then return false end

	local inventory = entity.get_module_inventory and entity.get_module_inventory()
	if not (inventory and inventory.valid) then return false end

	local all_satisfied = true
	for _, req in ipairs(requests) do
		local needed = (req.count or 1) - inventoryItemCount(inventory, req)
		if needed <= 0 then
			-- Already satisfied; a stale proxy can be removed.
		else
			local inserted = inventory.insert{
				name    = req.name,
				count   = needed,
				quality = req.quality,
			}
			if inserted < needed then
				all_satisfied = false
			end
		end
	end
	return all_satisfied
end

local function satisfyItemRequestProxy(proxy, inventories, target)
	if not (proxy and proxy.valid) then return end
	local requests = itemRequests(proxy.item_requests)
	if not (requests and #requests > 0) then return end
	if satisfyModuleRequests(target, inventories, requests) and proxy.valid then
		proxy.destroy{ raise_destroy = false }
	end
end

local function planItem(plan)
	local id = plan and plan.id
	if not (id and id.name) then return nil end
	return {
		name    = id.name,
		quality = stackQuality(id.quality),
	}
end

local function stackMatches(stack, item)
	if not (stack and stack.valid_for_read and item and stack.name == item.name) then
		return false
	end
	if not item.quality then return true end
	return stack.quality and stack.quality.valid and stack.quality.name == item.quality
end

local function takeFromModuleSlot(inv, slot, item, count, removed)
	local stack = inv and inv[slot]
	if not stackMatches(stack, item) then return 0 end

	local take = math.min(count or 1, stack.count)
	removed[#removed + 1] = {
		name    = item.name,
		count   = take,
		quality = item.quality,
	}

	if stack.count <= take then
		stack.clear()
	else
		stack.count = stack.count - take
	end
	return take
end

local function moduleSlotCount(inv, slot, item)
	local stack = inv and inv[slot]
	if not stackMatches(stack, item) then return 0 end
	return stack.count
end

local function moduleInventoryCount(inv, item)
	local total = 0
	for slot = 1, #inv do
		total = total + moduleSlotCount(inv, slot, item)
	end
	return total
end

local function takeFromModuleInventory(inv, item, count, removed)
	local remaining = count
	for slot = 1, #inv do
		if remaining <= 0 then break end
		remaining = remaining - takeFromModuleSlot(inv, slot, item, remaining, removed)
	end
	return count - remaining
end

local function returnRemovedModules(state, removed)
	if not (removed and #removed > 0) then return end
	if Config.noCost() then return end
	VirtualChest.insertItems(state.entity.force, state.entity.position, removed)
end

local function processRemovalPlan(proxy, state)
	if not (proxy and proxy.valid and state and state.entity and state.entity.valid) then return false end

	local plans = proxy.removal_plan
	if not (plans and #plans > 0) then return false end

	local target = proxy.proxy_target
	if not (target and target.valid and target.get_module_inventory) then return false end

	local inv = target.get_module_inventory()
	if not (inv and inv.valid) then return false end

	local removed = {}
	local pending = false
	for _, plan in ipairs(plans) do
		local item = planItem(plan)
		if item then
			local positions = plan.items and plan.items.in_inventory
			if positions and #positions > 0 then
				local requested = 0
				local removed_for_plan = 0
				for _, pos in ipairs(positions) do
					requested = requested + (pos.count or 1)
					-- Blueprint inventory positions use 0-based stack indexes.
					removed_for_plan = removed_for_plan
						+ takeFromModuleSlot(inv, (pos.stack or 0) + 1, item, pos.count or 1, removed)
				end
				if removed_for_plan < requested then
					for _, pos in ipairs(positions) do
						if moduleSlotCount(inv, (pos.stack or 0) + 1, item) > 0 then
							pending = true
							break
						end
					end
				end
			else
				local removed_for_plan = takeFromModuleInventory(inv, item, 1, removed)
				if removed_for_plan < 1 and moduleInventoryCount(inv, item) > 0 then
					pending = true
				end
			end
		end
	end

	returnRemovedModules(state, removed)
	if not pending then
		if proxy.valid then proxy.destroy{ raise_destroy = false } end
	end
	return true
end

local function moduleStack(item, count)
	return {
		name    = item.name,
		count   = count,
		quality = item.quality,
	}
end

local function setModuleSlot(stack, item, count)
	local stack_spec = moduleStack(item, count)
	if not stack.can_set_stack(stack_spec) then return false end
	return stack.set_stack(stack_spec)
end

local function satisfyModuleSlotFree(inv, slot, item, count)
	local stack = inv and inv[slot]
	if not stack then return false end

	local have = moduleSlotCount(inv, slot, item)
	local needed = (count or 1) - have
	if needed <= 0 then return true end
	if stack.valid_for_read and have == 0 then return false end

	return setModuleSlot(stack, item, have + needed)
end

local function satisfyModuleSlot(inventories, inv, slot, item, count)
	local stack = inv and inv[slot]
	if not stack then return false end

	local have = moduleSlotCount(inv, slot, item)
	local needed = (count or 1) - have
	if needed <= 0 then return true end
	if stack.valid_for_read and have == 0 then return false end
	if not stack.can_set_stack(moduleStack(item, have + needed)) then return false end

	local req = moduleStack(item, needed)
	if not requestCanBeProvided(inventories, req) then return false end

	local removed = consumeRequest(inventories, req)
	if removed <= 0 then return false end

	if setModuleSlot(stack, item, have + removed) then
		return removed >= needed
	end

	refundRequests(inventories, { moduleStack(item, removed) })
	return false
end

local function processInsertPlan(proxy, inventories, no_cost)
	if not (proxy and proxy.valid) then return false end

	local plans = proxy.insert_plan
	if not (plans and #plans > 0) then return false end

	local target = proxy.proxy_target
	if not (target and target.valid and target.get_module_inventory) then return false end

	local inv = target.get_module_inventory()
	if not (inv and inv.valid) then return false end

	local handled = false
	local all_satisfied = true
	for _, plan in ipairs(plans) do
		local item = planItem(plan)
		local positions = item and plan.items and plan.items.in_inventory
		if positions and #positions > 0 then
			handled = true
			for _, pos in ipairs(positions) do
				-- Blueprint inventory positions use 0-based stack indexes.
				local slot = (pos.stack or 0) + 1
				local ok
				if no_cost then
					ok = satisfyModuleSlotFree(inv, slot, item, pos.count or 1)
				else
					ok = inventories and #inventories > 0
						and satisfyModuleSlot(inventories, inv, slot, item, pos.count or 1)
				end
				if not ok then all_satisfied = false end
			end
		end
	end

	if not handled then return false end
	if all_satisfied and proxy.valid then
		proxy.destroy{ raise_destroy = false }
	end
	return true
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

	proxy = proxy or created.item_request_proxy
	if proxy and proxy.valid and not processInsertPlan(proxy, inventories, false) then
		satisfyItemRequestProxy(proxy, inventories, created)
	end
	return true
end

local function materializeGhostFree(ghost)
	local _, created, proxy = ghost.silent_revive{ raise_revive = true }
	if created and created.valid then
		proxy = proxy or created.item_request_proxy
		if proxy and proxy.valid then
			if not processInsertPlan(proxy, nil, true)
					and satisfyModuleRequestsFree(created, proxy.item_requests)
					and proxy.valid then
				proxy.destroy{ raise_destroy = false }
			end
		end
	end
	return created and created.valid
end

local function satisfyRequestProxyForEntity(proxy, inventories, no_cost)
	if not (proxy and proxy.valid) then return end
	local target = proxy.proxy_target
	if not (target and target.valid) then return end

	if processInsertPlan(proxy, inventories, no_cost) then
		return
	elseif no_cost then
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
			if proxy.valid and not processRemovalPlan(proxy, self) then
				satisfyRequestProxyForEntity(proxy, inventories, no_cost)
			end
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
