-- Shared linked-container pool for mythos-inventory chests.

local MythosInventory = {}

local MAX_TOTAL_ITEMS  = 5000
local MYTHOS_LINK_ID   = 1
local MYTHOS_PROTOTYPE = "mythos-inventory"

local function distanceSq(a, b)
	local dx = a.x - b.x
	local dy = a.y - b.y
	return dx * dx + dy * dy
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

function MythosInventory.getSharedInventory(force)
	if not force then return nil end
	local inv = force.get_linked_inventory(MYTHOS_PROTOTYPE, MYTHOS_LINK_ID)
	if inv and inv.valid then return inv end
	return MythosInventory.ensureSharedStorage(force)
end

function MythosInventory.ensureSharedStorage(force)
	if not force then return nil end

	storage.mythos_storage_anchors = storage.mythos_storage_anchors or {}
	local anchor_id = storage.mythos_storage_anchors[force.index]
	if anchor_id then
		local anchor = game.get_entity_by_unit_number(anchor_id)
		if anchor and anchor.valid then
			anchor.link_id = MYTHOS_LINK_ID
			local inv = force.get_linked_inventory(MYTHOS_PROTOTYPE, MYTHOS_LINK_ID)
			if inv and inv.valid then return inv end
		elseif anchor then
			anchor.destroy()
		end
	end

	local surface = game.surfaces[1]
	if not surface then return nil end

	local anchor = surface.create_entity{
		name                      = MYTHOS_PROTOTYPE,
		position                  = { -50000 + force.index, -50000 },
		force                     = force,
		create_build_effect_smoke = false,
	}
	if not (anchor and anchor.valid) then return nil end

	anchor.link_id      = MYTHOS_LINK_ID
	anchor.destructible = false
	storage.mythos_storage_anchors[force.index] = anchor.unit_number
	return force.get_linked_inventory(MYTHOS_PROTOTYPE, MYTHOS_LINK_ID)
end

function MythosInventory.ensureLinkId(entity)
	if not (entity and entity.valid and entity.name == MYTHOS_PROTOTYPE) then return end
	entity.link_id = MYTHOS_LINK_ID
end

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

function MythosInventory.unregister(unit_number)
	if not storage.mythos_inventories then return end
	storage.mythos_inventories[unit_number] = nil
end

function MythosInventory.onBuilt(entity)
	MythosInventory.ensureSharedStorage(entity.force)
	MythosInventory.ensureLinkId(entity)
	MythosInventory.register(entity)
end

function MythosInventory.onRemoved(entity)
	if not entity then return end
	local unit_number = entity.unit_number
	if not unit_number then return end
	if not storage.mythos_inventories or not storage.mythos_inventories[unit_number] then return end

	MythosInventory.unregister(unit_number)
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

function MythosInventory.findInventories(force)
	storage.mythos_inventories = storage.mythos_inventories or {}
	local list = {}
	for unit_number in pairs(storage.mythos_inventories) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid and entity.name == MYTHOS_PROTOTYPE then
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

function MythosInventory.sortedInventoriesForMythos(state)
	local force = state.entity.force
	local near  = state.entity.position
	local seen  = {}
	local list  = {}

	local function add(entity)
		if entity.valid and entity.name == MYTHOS_PROTOTYPE and entity.force == force then
			if not seen[entity.unit_number] then
				seen[entity.unit_number] = true
				list[#list + 1] = entity
				MythosInventory.register(entity)
			end
		end
	end

	local inside = state.inside_surface
	if inside and inside.valid then
		for _, entity in ipairs(inside.find_entities_filtered{ name = MYTHOS_PROTOTYPE }) do
			add(entity)
		end
	end

	local outer = state.entity.surface
	if outer and outer.valid then
		for _, entity in ipairs(outer.find_entities_filtered{ name = MYTHOS_PROTOTYPE }) do
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

local function countInSharedInventory(force, req)
	local inv = MythosInventory.getSharedInventory(force)
	if not inv then return 0 end

	local lookup = itemLookup(req)
	local total  = inv.get_item_count(lookup)
	if total >= (req.count or 1) then return total end

	if stackQuality(req.quality) then
		total = total + inv.get_item_count(req.name)
	end
	return total
end

local function removeFromSharedInventory(force, req)
	local inv = MythosInventory.getSharedInventory(force)
	if not inv then return 0 end

	local remaining = req.count or 1
	local quality   = stackQuality(req.quality)
	local lookup    = itemLookup(req)
	local have      = inv.get_item_count(lookup)

	if have < remaining and quality then
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

	return (req.count or 1) - remaining
end

function MythosInventory.getItemCountFromInventories(inventories, req)
	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return 0 end
	return countInSharedInventory(force, req)
end

function MythosInventory.removeItemsFromInventories(inventories, req)
	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return 0 end
	return removeFromSharedInventory(force, req)
end

function MythosInventory.insertItemsIntoInventories(inventories, items)
	if not items then return end

	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return end

	local inv = MythosInventory.getSharedInventory(force)
	if not inv then return end

	for _, item in pairs(items) do
		inv.insert({
			name    = item.name,
			count   = item.count,
			quality = item.quality,
		})
	end
end

function MythosInventory.getItemCount(force, item_name, near_position)
	return countInSharedInventory(force, { name = item_name, count = 1 })
end

function MythosInventory.removeItems(force, near_position, item_name, count)
	return removeFromSharedInventory(force, { name = item_name, count = count })
end

function MythosInventory.insertStack(force, near_position, stack)
	if not stack.valid_for_read then return stack.count end

	local inv = MythosInventory.getSharedInventory(force)
	if not inv then return stack.count end

	local before = MythosInventory.totalItemCount(inv)
	inv.insert({
		name    = stack.name,
		count   = stack.count,
		quality = stack.quality,
	})
	local after = MythosInventory.totalItemCount(inv)
	return stack.count - (after - before)
end

function MythosInventory.insertItems(force, near_position, items)
	if not items then return end

	local inv = MythosInventory.getSharedInventory(force)
	if not inv then return end

	for _, item in pairs(items) do
		inv.insert({
			name    = item.name,
			count   = item.count,
			quality = item.quality,
		})
	end
end

function MythosInventory.tryMineEntity(force, near_position, entity, raise_destroyed)
	local inv = MythosInventory.getSharedInventory(force)
	if not inv then return false end

	-- entity.mine only accepts script or entity inventories, not force-linked handles.
	local scratch = game.create_inventory(10)
	if not scratch then return false end

	local mined = entity.mine{ inventory = scratch, raise_destroyed = raise_destroyed or false }
	if not mined then
		scratch.destroy()
		return false
	end

	for i = 1, #scratch do
		local stack = scratch[i]
		if stack.valid_for_read then
			inv.insert({
				name    = stack.name,
				count   = stack.count,
				quality = stack.quality,
			})
		end
	end
	scratch.destroy()
	return true
end

local function enforceStorageCap(force)
	local inv = MythosInventory.getSharedInventory(force)
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

function MythosInventory.tickSlow()
	storage.mythos_inventories = storage.mythos_inventories or {}

	local forcesSeen = {}
	for unit_number in pairs(storage.mythos_inventories) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid and entity.name == MYTHOS_PROTOTYPE then
			MythosInventory.ensureLinkId(entity)
			forcesSeen[entity.force.index] = entity.force
		else
			storage.mythos_inventories[unit_number] = nil
		end
	end

	for _, force in pairs(forcesSeen) do
		MythosInventory.ensureSharedStorage(force)
		enforceStorageCap(force)
	end
end

function MythosInventory.bootstrapExisting()
	storage.mythos_inventories = storage.mythos_inventories or {}

	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{ name = MYTHOS_PROTOTYPE }) do
			if entity.valid then
				MythosInventory.onBuilt(entity)
			end
		end
	end

	local forcesSeen = {}
	for unit_number in pairs(storage.mythos_inventories) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid then
			forcesSeen[entity.force.index] = entity.force
		end
	end
	for _, force in pairs(forcesSeen) do
		MythosInventory.ensureSharedStorage(force)
		enforceStorageCap(force)
	end
end

return MythosInventory
