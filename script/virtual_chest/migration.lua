local Common    = require("script.virtual_chest.common")

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
