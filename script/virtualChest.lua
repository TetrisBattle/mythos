-- Shared linked-container pool for virtual chests.

local VirtualChest = {}

local MAX_TOTAL_ITEMS        = 5000
local VIRTUAL_CHEST_LINK_ID  = 1
local VIRTUAL_CHEST_PROTOTYPE = "virtual-chest"
local LEGACY_PROTOTYPE       = "mythos-inventory"
local LEGACY_ITEM            = "mythos-inventory"
local LEGACY_REGISTRY_KEYS   = { "mythos_inventories", "virtual_chests" }

VirtualChest.PROTOTYPE = VIRTUAL_CHEST_PROTOTYPE

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

local function isVirtualChestEntity(entity)
	return entity and entity.valid
		and (entity.name == VIRTUAL_CHEST_PROTOTYPE or entity.name == LEGACY_PROTOTYPE)
end

function VirtualChest.getSharedInventory(force)
	if not force then return nil end
	local inv = force.get_linked_inventory(VIRTUAL_CHEST_PROTOTYPE, VIRTUAL_CHEST_LINK_ID)
	if inv and inv.valid then return inv end
	return VirtualChest.ensureSharedStorage(force)
end

function VirtualChest.ensureSharedStorage(force)
	if not force then return nil end

	storage.virtual_chest_storage_anchors = storage.virtual_chest_storage_anchors or {}
	local anchor_id = storage.virtual_chest_storage_anchors[force.index]
	if anchor_id then
		local anchor = game.get_entity_by_unit_number(anchor_id)
		if anchor and anchor.valid then
			anchor.link_id = VIRTUAL_CHEST_LINK_ID
			local inv = force.get_linked_inventory(VIRTUAL_CHEST_PROTOTYPE, VIRTUAL_CHEST_LINK_ID)
			if inv and inv.valid then return inv end
		elseif anchor then
			anchor.destroy()
		end
	end

	local surface = game.surfaces[1]
	if not surface then return nil end

	local anchor = surface.create_entity{
		name                      = VIRTUAL_CHEST_PROTOTYPE,
		position                  = { -50000 + force.index, -50000 },
		force                     = force,
		create_build_effect_smoke = false,
	}
	if not (anchor and anchor.valid) then return nil end

	anchor.link_id      = VIRTUAL_CHEST_LINK_ID
	anchor.destructible = false
	storage.virtual_chest_storage_anchors[force.index] = anchor.unit_number
	return force.get_linked_inventory(VIRTUAL_CHEST_PROTOTYPE, VIRTUAL_CHEST_LINK_ID)
end

function VirtualChest.ensureLinkId(entity)
	if not isVirtualChestEntity(entity) then return end
	entity.link_id = VIRTUAL_CHEST_LINK_ID
end

function VirtualChest.normalizePlaceRequests(source, defaultQuality)
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

function VirtualChest.totalItemCount(inv)
	local total = 0
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read then
			total = total + stack.count
		end
	end
	return total
end

function VirtualChest.register(entity)
	storage.virtualChests = storage.virtualChests or {}
	storage.virtualChests[entity.unit_number] = true
end

function VirtualChest.unregister(unit_number)
	if not storage.virtualChests then return end
	storage.virtualChests[unit_number] = nil
end

function VirtualChest.onBuilt(entity)
	VirtualChest.ensureSharedStorage(entity.force)
	VirtualChest.ensureLinkId(entity)
	VirtualChest.register(entity)
end

function VirtualChest.onRemoved(entity)
	if not entity then return end
	local unit_number = entity.unit_number
	if not unit_number then return end
	if not storage.virtualChests or not storage.virtualChests[unit_number] then return end

	VirtualChest.unregister(unit_number)
end

local function ghostQuality(ghost)
	if ghost.quality and ghost.quality.valid then
		return ghost.quality.name
	end
	return nil
end

function VirtualChest.ghostRequests(ghost)
	local quality = ghostQuality(ghost)

	local requests = ghost.item_requests
	if requests and #requests > 0 then
		local list = VirtualChest.normalizePlaceRequests(requests, quality)
		if #list > 0 then return list end
	end

	local proto = ghost.ghost_prototype
	if proto and proto.items_to_place_this then
		local list = VirtualChest.normalizePlaceRequests(proto.items_to_place_this, quality)
		if #list > 0 then return list end
	end

	if ghost.ghost_name then
		return { { name = ghost.ghost_name, count = 1, quality = quality } }
	end

	return nil
end

function VirtualChest.findInventories(force)
	storage.virtualChests = storage.virtualChests or {}
	local list = {}
	for unit_number in pairs(storage.virtualChests) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if isVirtualChestEntity(entity) then
			if entity.force == force then
				list[#list + 1] = entity
			end
		else
			storage.virtualChests[unit_number] = nil
		end
	end
	return list
end

function VirtualChest.sortedInventories(force, near_position)
	local list = VirtualChest.findInventories(force)
	if near_position then
		table.sort(list, function(a, b)
			return distanceSq(a.position, near_position) < distanceSq(b.position, near_position)
		end)
	end
	return list
end

function VirtualChest.sortedInventoriesForMythos(state)
	local force = state.entity.force
	local near  = state.entity.position
	local seen  = {}
	local list  = {}

	local function add(entity)
		if isVirtualChestEntity(entity) and entity.force == force then
			if not seen[entity.unit_number] then
				seen[entity.unit_number] = true
				list[#list + 1] = entity
				VirtualChest.register(entity)
			end
		end
	end

	local inside = state.inside_surface
	if inside and inside.valid then
		for _, entity in ipairs(inside.find_entities_filtered{ name = VIRTUAL_CHEST_PROTOTYPE }) do
			add(entity)
		end
		if not storage.virtual_chest_legacy_migrated then
			local ok, legacy = pcall(function()
				return inside.find_entities_filtered{ name = LEGACY_PROTOTYPE }
			end)
			if ok then
				for _, entity in ipairs(legacy) do
					add(entity)
				end
			end
		end
	end

	local outer = state.entity.surface
	if outer and outer.valid then
		for _, entity in ipairs(outer.find_entities_filtered{ name = VIRTUAL_CHEST_PROTOTYPE }) do
			add(entity)
		end
		if not storage.virtual_chest_legacy_migrated then
			local ok, legacy = pcall(function()
				return outer.find_entities_filtered{ name = LEGACY_PROTOTYPE }
			end)
			if ok then
				for _, entity in ipairs(legacy) do
					add(entity)
				end
			end
		end
	end

	for _, entity in ipairs(VirtualChest.sortedInventories(force, near)) do
		if not seen[entity.unit_number] then
			list[#list + 1] = entity
		end
	end

	return list
end

local function countInSharedInventory(force, req)
	local inv = VirtualChest.getSharedInventory(force)
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
	local inv = VirtualChest.getSharedInventory(force)
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

function VirtualChest.getItemCountFromInventories(inventories, req)
	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return 0 end
	return countInSharedInventory(force, req)
end

function VirtualChest.removeItemsFromInventories(inventories, req)
	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return 0 end
	return removeFromSharedInventory(force, req)
end

function VirtualChest.insertItemsIntoInventories(inventories, items)
	if not items then return end

	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return end

	local inv = VirtualChest.getSharedInventory(force)
	if not inv then return end

	for _, item in pairs(items) do
		inv.insert({
			name    = item.name,
			count   = item.count,
			quality = item.quality,
		})
	end
end

function VirtualChest.getItemCount(force, item_name, near_position)
	return countInSharedInventory(force, { name = item_name, count = 1 })
end

function VirtualChest.removeItems(force, near_position, item_name, count)
	return removeFromSharedInventory(force, { name = item_name, count = count })
end

function VirtualChest.insertStack(force, near_position, stack)
	if not stack.valid_for_read then return stack.count end

	local inv = VirtualChest.getSharedInventory(force)
	if not inv then return stack.count end

	local before = VirtualChest.totalItemCount(inv)
	inv.insert({
		name    = stack.name,
		count   = stack.count,
		quality = stack.quality,
	})
	local after = VirtualChest.totalItemCount(inv)
	return stack.count - (after - before)
end

function VirtualChest.insertItems(force, near_position, items)
	if not items then return end

	local inv = VirtualChest.getSharedInventory(force)
	if not inv then return end

	for _, item in pairs(items) do
		inv.insert({
			name    = item.name,
			count   = item.count,
			quality = item.quality,
		})
	end
end

function VirtualChest.tryMineEntity(force, near_position, entity, raise_destroyed)
	local inv = VirtualChest.getSharedInventory(force)
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
	local inv = VirtualChest.getSharedInventory(force)
	if not inv then return end

	local excess = VirtualChest.totalItemCount(inv) - MAX_TOTAL_ITEMS
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

local function migrateStorageKeys()
	storage.virtualChests = storage.virtualChests or {}
	for _, legacy_key in ipairs(LEGACY_REGISTRY_KEYS) do
		local legacy = storage[legacy_key]
		if legacy then
			for unit_number, registered in pairs(legacy) do
				storage.virtualChests[unit_number] = registered
			end
			storage[legacy_key] = nil
		end
	end

	if storage.mythos_storage_anchors then
		storage.virtual_chest_storage_anchors = storage.virtual_chest_storage_anchors or {}
		for force_index, anchor_id in pairs(storage.mythos_storage_anchors) do
			storage.virtual_chest_storage_anchors[force_index] = anchor_id
		end
		storage.mythos_storage_anchors = nil
	end
end

local function snapshotLinkedInventory(inv)
	local items = {}
	if not (inv and inv.valid) then return items end
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read then
			items[#items + 1] = {
				name    = stack.name,
				count   = stack.count,
				quality = stack.quality,
			}
		end
	end
	return items
end

local function restoreLinkedInventory(inv, items)
	if not (inv and inv.valid) then return end
	for _, item in ipairs(items) do
		inv.insert(item)
	end
end

local function tryGetLegacyLinkedInventory(force)
	local ok, inv = pcall(function()
		return force.get_linked_inventory(LEGACY_PROTOTYPE, VIRTUAL_CHEST_LINK_ID)
	end)
	if ok and inv and inv.valid then return inv end
	return nil
end

local function collectLegacyUnitNumbers()
	local units = {}
	if storage.virtualChests then
		for unit_number in pairs(storage.virtualChests) do
			units[unit_number] = true
		end
	end
	return units
end

local function foreachLegacyChestEntity(callback)
	local seen = {}
	local function visit(entity)
		if not (entity and entity.valid and entity.name == LEGACY_PROTOTYPE) then return end
		local unit_number = entity.unit_number
		if seen[unit_number] then return end
		seen[unit_number] = true
		callback(entity)
	end

	for unit_number in pairs(collectLegacyUnitNumbers()) do
		visit(game.get_entity_by_unit_number(unit_number))
	end

	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{ type = "linked-container" }) do
			visit(entity)
		end
	end
end

local function findLegacyEntityInventory(force)
	local found
	foreachLegacyChestEntity(function(entity)
		if found or entity.force ~= force then return end
		local inv = entity.get_inventory(defines.inventory.chest)
		if inv and inv.valid then
			found = inv
		end
	end)
	return found
end

local function snapshotLegacyForceInventory(force)
	storage.virtual_chest_legacy_linked_snapshot = storage.virtual_chest_legacy_linked_snapshot or {}

	local inv = tryGetLegacyLinkedInventory(force)
	if inv then
		local items = snapshotLinkedInventory(inv)
		storage.virtual_chest_legacy_linked_snapshot[force.index] = items
		return items
	end

	local cached = storage.virtual_chest_legacy_linked_snapshot[force.index]
	if cached then return cached end

	inv = findLegacyEntityInventory(force)
	if inv then
		return snapshotLinkedInventory(inv)
	end

	return {}
end

local function migrateItemsInInventory(inv)
	if not (inv and inv.valid) then return end
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read and stack.name == LEGACY_ITEM then
			local count = stack.count
			local quality = stack.quality
			stack.clear()
			stack.set_stack{ name = VIRTUAL_CHEST_PROTOTYPE, count = count, quality = quality }
		end
	end
end

local function migrateEntityInventories(entity)
	if not entity.valid then return end
	for _, inv_def in pairs(defines.inventory) do
		migrateItemsInInventory(entity.get_inventory(inv_def))
	end
end

local function migrateLegacyEntity(entity)
	if not (entity and entity.valid and entity.name == LEGACY_PROTOTYPE) then return end

	local surface = entity.surface
	local props = {
		name                      = VIRTUAL_CHEST_PROTOTYPE,
		position                  = entity.position,
		direction                 = entity.direction,
		force                     = entity.force,
		create_build_effect_smoke = false,
	}
	local link_id = entity.link_id
	local destructible = entity.destructible
	local unit_number = entity.unit_number

	VirtualChest.unregister(unit_number)
	entity.destroy()

	local new_entity = surface.create_entity(props)
	if new_entity and new_entity.valid then
		new_entity.link_id = link_id or VIRTUAL_CHEST_LINK_ID
		if destructible == false then
			new_entity.destructible = false
		end
		VirtualChest.onBuilt(new_entity)
	end
end

function VirtualChest.migrateLegacy()
	if storage.virtual_chest_legacy_migrated then return end

	migrateStorageKeys()

	local saved_by_force = {}
	for _, force in pairs(game.forces) do
		saved_by_force[force.index] = snapshotLegacyForceInventory(force)
	end

	foreachLegacyChestEntity(function(entity)
		migrateLegacyEntity(entity)
	end)

	for _, surface in pairs(game.surfaces) do
		for _, ghost in ipairs(surface.find_entities_filtered{ type = "entity-ghost" }) do
			if ghost.valid and ghost.ghost_name == LEGACY_PROTOTYPE then
				ghost.ghost_name = VIRTUAL_CHEST_PROTOTYPE
			end
		end

		for _, entity in ipairs(surface.find_entities_filtered{ type = "item-entity" }) do
			if entity.valid and entity.stack.valid_for_read and entity.stack.name == LEGACY_ITEM then
				local count = entity.stack.count
				local quality = entity.stack.quality
				entity.stack.clear()
				entity.stack.set_stack{ name = VIRTUAL_CHEST_PROTOTYPE, count = count, quality = quality }
			end
		end

		for _, entity in ipairs(surface.find_entities()) do
			migrateEntityInventories(entity)
		end
	end

	for _, player in pairs(game.players) do
		migrateItemsInInventory(player.get_main_inventory())
		migrateItemsInInventory(player.get_inventory(defines.inventory.character_trash))
		local cursor = player.cursor_stack
		if cursor and cursor.valid_for_read and cursor.name == LEGACY_ITEM then
			local count = cursor.count
			local quality = cursor.quality
			cursor.clear()
			cursor.set_stack{ name = VIRTUAL_CHEST_PROTOTYPE, count = count, quality = quality }
		end
	end

	for _, force in pairs(game.forces) do
		VirtualChest.ensureSharedStorage(force)
		local new_inv = force.get_linked_inventory(VIRTUAL_CHEST_PROTOTYPE, VIRTUAL_CHEST_LINK_ID)
		restoreLinkedInventory(new_inv, saved_by_force[force.index] or {})
		enforceStorageCap(force)
	end

	storage.virtual_chest_legacy_linked_snapshot = nil
	storage.virtual_chest_legacy_migrated = true
end

function VirtualChest.tickSlow()
	storage.virtualChests = storage.virtualChests or {}

	local forcesSeen = {}
	for unit_number in pairs(storage.virtualChests) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if isVirtualChestEntity(entity) then
			VirtualChest.ensureLinkId(entity)
			forcesSeen[entity.force.index] = entity.force
		else
			storage.virtualChests[unit_number] = nil
		end
	end

	for _, force in pairs(forcesSeen) do
		VirtualChest.ensureSharedStorage(force)
		enforceStorageCap(force)
	end
end

function VirtualChest.bootstrapExisting()
	VirtualChest.migrateLegacy()

	storage.virtualChests = storage.virtualChests or {}

	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{ name = VIRTUAL_CHEST_PROTOTYPE }) do
			if entity.valid then
				VirtualChest.onBuilt(entity)
			end
		end
	end

	local forcesSeen = {}
	for unit_number in pairs(storage.virtualChests) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid then
			forcesSeen[entity.force.index] = entity.force
		end
	end
	for _, force in pairs(forcesSeen) do
		VirtualChest.ensureSharedStorage(force)
		enforceStorageCap(force)
	end
end

return VirtualChest
