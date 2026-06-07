-- Shared Mythos Inventory storage: force-wide chest pool and caps.

local MythosInventory = {}

local MAX_TOTAL_ITEMS = 5000
local MYTHOS_GHOST_GROUP = "Mythos"
local MAX_LOGISTIC_SLOTS = 100

local function distanceSq(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return dx * dx + dy * dy
end

local function getStorageInventory(entity)
	if not (entity and entity.valid) then return nil end

	local inv = entity.get_inventory(defines.inventory.chest)
	if inv and inv.valid then return inv end

	local maxIndex = entity.get_max_inventory_index()
	if maxIndex then
		for i = 1, maxIndex do
			inv = entity.get_inventory(i)
			if inv and inv.valid then
				return inv
			end
		end
	end

	return nil
end

local function stackQuality(quality)
	if not quality then return nil end
	if type(quality) == "string" then return quality end
	return quality.name
end

local function itemLookup(req)
	local quality = stackQuality(req.quality)
	if quality then
		return { name = req.name, quality = quality }
	end
	return req.name
end

local function itemRemoveFilter(req, count)
	local quality = stackQuality(req.quality)
	if quality then
		return { name = req.name, count = count, quality = quality }
	end
	return { name = req.name, count = count }
end

-- Factorio 2.0 exposes items_to_place_this as either an array or a dictionary.
function MythosInventory.normalizePlaceRequests(source, defaultQuality)
	local list = {}
	if not source then return list end

	if source[1] then
		for _, entry in ipairs(source) do
			if type(entry) == "table" and entry.name then
				list[#list + 1] = {
					name    = entry.name,
					count   = entry.count or 1,
					quality = stackQuality(entry.quality) or defaultQuality,
				}
			end
		end
		if #list > 0 then return list end
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
				quality = defaultQuality,
			}
			return list
		end
	end

	return list
end

function MythosInventory.totalItemCount(inv)
	local total = 0
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read then
			total = total + stack.count
		end
	end
	return total
end

function MythosInventory.register(entity)
	storage.mythos_inventories = storage.mythos_inventories or {}
	storage.mythos_inventories[entity.unit_number] = true
end

function MythosInventory.onBuilt(entity)
	MythosInventory.register(entity)
	MythosInventory.configureLogistics(entity)
end

function MythosInventory.unregister(unit_number)
	if not storage.mythos_inventories then return end
	storage.mythos_inventories[unit_number] = nil
end

function MythosInventory.configureLogistics(entity)
	entity.request_from_buffers = true
	local point = entity.get_logistic_point(defines.logistic_member_index.logistic_container)
	if point then
		point.trash_not_requested = false
	end
end

local function ghostQuality(ghost)
	if ghost.quality and ghost.quality.valid then
		return ghost.quality.name
	end
	return nil
end

function MythosInventory.ghostRequests(ghost)
	local quality = ghostQuality(ghost)

	local requests = ghost.item_requests
	if requests and #requests > 0 then
		local list = MythosInventory.normalizePlaceRequests(requests, quality)
		if #list > 0 then return list end
	end

	local proto = ghost.ghost_prototype
	if proto and proto.items_to_place_this then
		local list = MythosInventory.normalizePlaceRequests(proto.items_to_place_this, quality)
		if #list > 0 then return list end
	end

	if ghost.ghost_name then
		return { { name = ghost.ghost_name, count = 1, quality = quality } }
	end

	return nil
end

local function needKey(req)
	local quality = stackQuality(req.quality)
	if quality then
		return req.name .. "|" .. quality
	end
	return req.name
end

local function logisticQuality(quality)
	return stackQuality(quality) or "normal"
end

local function getGhostLogisticSection(entity)
	local sections = entity.get_logistic_sections()
	if not (sections and sections.valid) then return nil end

	for _, section in ipairs(sections.sections) do
		if section.valid and section.is_manual and section.group == MYTHOS_GHOST_GROUP then
			return section
		end
	end

	return sections.add_section(MYTHOS_GHOST_GROUP)
end

function MythosInventory.syncGhostLogisticRequests(entity, requests)
	if not (entity and entity.valid and entity.name == "mythos-inventory") then return end

	local section = getGhostLogisticSection(entity)
	if not (section and section.valid and section.is_manual) then return end

	local filters = {}
	for _, req in ipairs(requests) do
		if #filters >= MAX_LOGISTIC_SLOTS then break end
		local count = req.count or 1
		if count > 0 then
			filters[#filters + 1] = {
				value = {
					type    = "item",
					name    = req.name,
					quality = logisticQuality(req.quality),
				},
				min = count,
			}
		end
	end

	section.filters = filters
	section.active  = #filters > 0
end

function MythosInventory.clearGhostLogisticRequests(entity)
	if not (entity and entity.valid and entity.name == "mythos-inventory") then return end

	local sections = entity.get_logistic_sections()
	if not (sections and sections.valid) then return end

	for _, section in ipairs(sections.sections) do
		if section.valid and section.is_manual and section.group == MYTHOS_GHOST_GROUP then
			section.filters = {}
			section.active  = false
			return
		end
	end
end

function MythosInventory.aggregateGhostNeeds(surface, inventories)
	local totals = {}
	local order  = {}

	for _, ghost in ipairs(surface.find_entities_filtered{ type = "entity-ghost" }) do
		if not ghost.valid then goto continue end

		local requests = MythosInventory.ghostRequests(ghost)
		if requests then
			for _, req in ipairs(requests) do
				local key = needKey(req)
				if not totals[key] then
					totals[key] = {
						name    = req.name,
						count   = 0,
						quality = req.quality,
					}
					order[#order + 1] = key
				end
				totals[key].count = totals[key].count + (req.count or 1)
			end
		end

		::continue::
	end

	local result = {}
	for _, key in ipairs(order) do
		local req = totals[key]
		local have = MythosInventory.getItemCountFromInventories(inventories, req)
		local need = req.count - have
		if need > 0 then
			result[#result + 1] = {
				name    = req.name,
				count   = need,
				quality = req.quality,
			}
		end
	end
	return result
end

-- Prefer an outer-surface chest on the logistic network; fall back to pocket inventory.
function MythosInventory.requesterInventoriesForMythos(state)
	local all   = MythosInventory.sortedInventoriesForMythos(state)
	local outer = state.entity.surface

	for _, entity in ipairs(all) do
		if entity.valid and entity.surface == outer then
			return { entity }
		end
	end

	if all[1] and all[1].valid then
		return { all[1] }
	end
	return {}
end

function MythosInventory.findInventories(force)
	storage.mythos_inventories = storage.mythos_inventories or {}
	local list = {}
	for unit_number in pairs(storage.mythos_inventories) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid and entity.name == "mythos-inventory" then
			if entity.force == force then
				list[#list + 1] = entity
			end
		else
			storage.mythos_inventories[unit_number] = nil
		end
	end
	return list
end

function MythosInventory.sortedInventories(force, near_position)
	local list = MythosInventory.findInventories(force)
	if near_position then
		table.sort(list, function(a, b)
			return distanceSq(a.position, near_position) < distanceSq(b.position, near_position)
		end)
	end
	return list
end

-- Pocket-dimension inventories first, then remaining force chests by outer mythos proximity.
function MythosInventory.sortedInventoriesForMythos(state)
	local force = state.entity.force
	local near  = state.entity.position
	local seen  = {}
	local list  = {}

	local function add(entity)
		if entity.valid and entity.name == "mythos-inventory" and entity.force == force then
			if not seen[entity.unit_number] then
				seen[entity.unit_number] = true
				list[#list + 1] = entity
				MythosInventory.register(entity)
			end
		end
	end

	local inside = state.inside_surface
	if inside and inside.valid then
		for _, entity in ipairs(inside.find_entities_filtered{ name = "mythos-inventory" }) do
			add(entity)
		end
	end

	local outer = state.entity.surface
	if outer and outer.valid then
		for _, entity in ipairs(outer.find_entities_filtered{ name = "mythos-inventory" }) do
			add(entity)
		end
	end

	for _, entity in ipairs(MythosInventory.sortedInventories(force, near)) do
		if not seen[entity.unit_number] then
			list[#list + 1] = entity
		end
	end

	return list
end

function MythosInventory.getItemCountFromInventories(inventories, req)
	local needed = req.count or 1
	local total  = 0
	local lookup = itemLookup(req)
	for _, entity in ipairs(inventories) do
		if entity.valid then
			local inv = getStorageInventory(entity)
			if inv then
				total = total + inv.get_item_count(lookup)
			end
		end
	end
	if total >= needed then return total end

	-- Accept any quality when a specific quality was requested but not available.
	if stackQuality(req.quality) then
		for _, entity in ipairs(inventories) do
			if entity.valid then
				local inv = getStorageInventory(entity)
				if inv then
					total = total + inv.get_item_count(req.name)
				end
			end
		end
	end
	return total
end

function MythosInventory.removeItemsFromInventories(inventories, req)
	local remaining = req.count or 1
	for _, entity in ipairs(inventories) do
		if remaining <= 0 then break end
		if not entity.valid then goto continue end

		local inv = getStorageInventory(entity)
		if not inv then goto continue end

		local lookup = itemLookup(req)
		local have   = inv.get_item_count(lookup)
		if have < remaining and stackQuality(req.quality) then
			lookup = req.name
			have   = inv.get_item_count(lookup)
		end

		local take = math.min(have, remaining)
		if take > 0 then
			local removeFilter = itemRemoveFilter(req, take)
			if lookup == req.name then
				removeFilter = { name = req.name, count = take }
			end
			inv.remove(removeFilter)
			remaining = remaining - take
		end

		::continue::
	end
	return (req.count or 1) - remaining
end

function MythosInventory.insertItemsIntoInventories(inventories, items)
	if not items then return end
	for _, item in pairs(items) do
		local leftover = item.count
		for _, entity in ipairs(inventories) do
			if leftover <= 0 then break end
			if not entity.valid then goto continue end

			local inv = getStorageInventory(entity)
			if not inv then goto continue end

			leftover = leftover - inv.insert({
				name    = item.name,
				count   = leftover,
				quality = item.quality,
			})
			::continue::
		end
	end
end

function MythosInventory.enforceStorageCap(entity)
	local inv = getStorageInventory(entity)
	if not inv then return end

	local excess = MythosInventory.totalItemCount(inv) - MAX_TOTAL_ITEMS
	if excess <= 0 then return end

	for i = #inv, 1, -1 do
		if excess <= 0 then break end
		local stack = inv[i]
		if stack.valid_for_read then
			local removed = math.min(stack.count, excess)
			stack.count = stack.count - removed
			excess = excess - removed
		end
	end
end

function MythosInventory.getItemCount(force, item_name, near_position)
	local total = 0
	for _, entity in ipairs(MythosInventory.sortedInventories(force, near_position)) do
		if entity.valid then
			local inv = getStorageInventory(entity)
			if inv then
				total = total + inv.get_item_count(item_name)
			end
		end
	end
	return total
end

function MythosInventory.removeItems(force, near_position, item_name, count)
	local remaining = count
	for _, entity in ipairs(MythosInventory.sortedInventories(force, near_position)) do
		if remaining <= 0 then break end
		if not entity.valid then goto continue end

		local inv = getStorageInventory(entity)
		if not inv then goto continue end

		local have = inv.get_item_count(item_name)
		local take = math.min(have, remaining)
		if take > 0 then
			inv.remove({ name = item_name, count = take })
			remaining = remaining - take
		end

		::continue::
	end
	return count - remaining
end

function MythosInventory.insertStack(force, near_position, stack)
	if not stack.valid_for_read then return 0 end

	local leftover = stack.count
	for _, entity in ipairs(MythosInventory.sortedInventories(force, near_position)) do
		if leftover <= 0 then break end
		if not entity.valid then goto continue end

		local inv = getStorageInventory(entity)
		if not inv then goto continue end

		leftover = leftover - inv.insert({
			name    = stack.name,
			count   = leftover,
			quality = stack.quality,
		})

		::continue::
	end
	return leftover
end

function MythosInventory.insertItems(force, near_position, items)
	if not items then return end
	for _, item in pairs(items) do
		local leftover = item.count
		for _, entity in ipairs(MythosInventory.sortedInventories(force, near_position)) do
			if leftover <= 0 then break end
			if not entity.valid then goto continue end

			local inv = getStorageInventory(entity)
			if not inv then goto continue end

			leftover = leftover - inv.insert({
				name    = item.name,
				count   = leftover,
				quality = item.quality,
			})

			::continue::
		end
	end
end

function MythosInventory.tryMineEntity(force, near_position, entity, raise_destroyed)
	for _, chest in ipairs(MythosInventory.sortedInventories(force, near_position)) do
		if not chest.valid then goto continue end
		local inv = getStorageInventory(chest)
		if not inv then goto continue end
		if entity.mine{ inventory = inv, raise_destroyed = raise_destroyed or false } then
			return true
		end
		::continue::
	end
	return false
end

function MythosInventory.tickSlow()
	storage.mythos_inventories = storage.mythos_inventories or {}

	for unit_number in pairs(storage.mythos_inventories) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid and entity.name == "mythos-inventory" then
			MythosInventory.enforceStorageCap(entity)
		else
			storage.mythos_inventories[unit_number] = nil
		end
	end
end

function MythosInventory.bootstrapExisting()
	storage.mythos_inventories = storage.mythos_inventories or {}
	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{ name = "mythos-inventory" }) do
			if entity.valid then
				MythosInventory.onBuilt(entity)
			end
		end
	end
end

return MythosInventory
