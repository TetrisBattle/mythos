local Common    = require("script.virtual_chest.common")
local Inventory = require("script.virtual_chest.inventory")
local Lifecycle = require("script.virtual_chest.lifecycle")

local Migration = {}

local function removeVirtualChestFromInventory(inv)
	if not (inv and inv.valid) then return end
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read
				and stack.name == Common.VIRTUAL_CHEST_PROTOTYPE then
			stack.clear()
		end
	end
end

local function removeVirtualChestFromEntityInventories(entity)
	if not (entity and entity.valid) then return end
	if entity.name == Common.VIRTUAL_CHEST_PROTOTYPE then return end
	for _, inv_def in pairs(defines.inventory) do
		removeVirtualChestFromInventory(entity.get_inventory(inv_def))
	end
end

local function purgeVirtualChestItems()
	for _, player in pairs(game.players) do
		if player.valid then
			for _, inv_def in pairs(defines.inventory) do
				removeVirtualChestFromInventory(player.get_inventory(inv_def))
			end
			local cursor = player.cursor_stack
			if cursor and cursor.valid_for_read
					and cursor.name == Common.VIRTUAL_CHEST_PROTOTYPE then
				cursor.clear()
			end
		end
	end

	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{ type = "item-entity" }) do
			if entity.valid and entity.stack.valid_for_read
					and entity.stack.name == Common.VIRTUAL_CHEST_PROTOTYPE then
				entity.destroy{ raise_destroy = false }
			end
		end

		for _, ghost in ipairs(surface.find_entities_filtered{ type = "entity-ghost" }) do
			if ghost.valid and ghost.ghost_name == Common.VIRTUAL_CHEST_PROTOTYPE then
				ghost.destroy{ raise_destroy = false }
			end
		end

		for _, entity in ipairs(surface.find_entities()) do
			removeVirtualChestFromEntityInventories(entity)
		end
	end
end

local function migrateStorageKeys()
	storage.virtualChests = storage.virtualChests or {}
	for _, legacy_key in ipairs(Common.LEGACY_REGISTRY_KEYS) do
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

local function tryGetLegacyLinkedInventory(force)
	local ok, inv = pcall(function()
		return force.get_linked_inventory(
			Common.LEGACY_PROTOTYPE,
			Common.VIRTUAL_CHEST_LINK_ID
		)
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
		if not (entity and entity.valid
				and entity.name == Common.LEGACY_PROTOTYPE) then return end
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
	storage.virtual_chest_legacy_linked_snapshot =
		storage.virtual_chest_legacy_linked_snapshot or {}

	local inv = tryGetLegacyLinkedInventory(force)
	if inv then
		local items = Inventory.snapshotLinkedInventory(inv)
		storage.virtual_chest_legacy_linked_snapshot[force.index] = items
		return items
	end

	local cached = storage.virtual_chest_legacy_linked_snapshot[force.index]
	if cached then return cached end

	inv = findLegacyEntityInventory(force)
	if inv then
		return Inventory.snapshotLinkedInventory(inv)
	end

	return {}
end

local function migrateItemsInInventory(inv)
	if not (inv and inv.valid) then return end
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read and stack.name == Common.LEGACY_ITEM then
			local count = stack.count
			local quality = stack.quality
			stack.clear()
			stack.set_stack{
				name    = Common.VIRTUAL_CHEST_PROTOTYPE,
				count   = count,
				quality = quality,
			}
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
	if not (entity and entity.valid
			and entity.name == Common.LEGACY_PROTOTYPE) then return end

	local surface = entity.surface
	local props = {
		name                      = Common.VIRTUAL_CHEST_PROTOTYPE,
		position                  = entity.position,
		direction                 = entity.direction,
		force                     = entity.force,
		create_build_effect_smoke = false,
	}
	local link_id = entity.link_id
	local destructible = entity.destructible
	local unit_number = entity.unit_number

	Lifecycle.unregister(unit_number)
	entity.destroy()

	local new_entity = surface.create_entity(props)
	if new_entity and new_entity.valid then
		new_entity.link_id = link_id or Common.VIRTUAL_CHEST_LINK_ID
		if destructible == false then
			new_entity.destructible = false
		end
		Lifecycle.onBuilt(new_entity)
	end
end

function Migration.migrateLegacy()
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
			if ghost.valid and ghost.ghost_name == Common.LEGACY_PROTOTYPE then
				ghost.ghost_name = Common.VIRTUAL_CHEST_PROTOTYPE
			end
		end

		for _, entity in ipairs(surface.find_entities_filtered{ type = "item-entity" }) do
			if entity.valid and entity.stack.valid_for_read
					and entity.stack.name == Common.LEGACY_ITEM then
				local count = entity.stack.count
				local quality = entity.stack.quality
				entity.stack.clear()
				entity.stack.set_stack{
					name    = Common.VIRTUAL_CHEST_PROTOTYPE,
					count   = count,
					quality = quality,
				}
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
		if cursor and cursor.valid_for_read and cursor.name == Common.LEGACY_ITEM then
			local count = cursor.count
			local quality = cursor.quality
			cursor.clear()
			cursor.set_stack{
				name    = Common.VIRTUAL_CHEST_PROTOTYPE,
				count   = count,
				quality = quality,
			}
		end
	end

	for _, force in pairs(game.forces) do
		Inventory.ensureSharedStorage(force)
		local new_inv = force.get_linked_inventory(
			Common.VIRTUAL_CHEST_PROTOTYPE,
			Common.VIRTUAL_CHEST_LINK_ID
		)
		Inventory.restoreLinkedInventory(new_inv, saved_by_force[force.index] or {})
		Inventory.enforceStorageCap(force)
	end

	storage.virtual_chest_legacy_linked_snapshot = nil
	storage.virtual_chest_legacy_migrated = true
end

function Migration.purgeAll()
	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{
				name = Common.VIRTUAL_CHEST_PROTOTYPE,
			}) do
			if entity.valid then
				entity.destroy{ raise_destroy = false }
			end
		end
	end

	storage.virtual_chest_storage_anchors = storage.virtual_chest_storage_anchors or {}
	for force_index, anchor_id in pairs(storage.virtual_chest_storage_anchors) do
		local force = game.forces[force_index]
		if force then
			local ok, inv = pcall(function()
				return force.get_linked_inventory(
					Common.VIRTUAL_CHEST_PROTOTYPE,
					Common.VIRTUAL_CHEST_LINK_ID
				)
			end)
			if ok and inv and inv.valid then
				inv.clear()
			end
		end

		local anchor = game.get_entity_by_unit_number(anchor_id)
		if anchor and anchor.valid then
			anchor.destroy{ raise_destroy = false }
		end
	end

	purgeVirtualChestItems()

	storage.virtual_chest_storage_anchors = {}
	storage.virtualChests = {}
end

return Migration
