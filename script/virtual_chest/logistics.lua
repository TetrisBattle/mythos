local Common    = require("script.virtual_chest.common")
local Inventory = require("script.virtual_chest.inventory")
local Lifecycle = require("script.virtual_chest.lifecycle")

local Logistics = {}

local function ghostQuality(ghost)
	if ghost.quality and ghost.quality.valid then
		return ghost.quality.name
	end
	return nil
end

function Logistics.ghostRequests(ghost)
	local quality = ghostQuality(ghost)

	local requests = ghost.item_requests
	if requests and #requests > 0 then
		local list = Inventory.normalizePlaceRequests(requests, quality)
		if #list > 0 then return list end
	end

	local proto = ghost.ghost_prototype
	if proto and proto.items_to_place_this then
		local list = Inventory.normalizePlaceRequests(proto.items_to_place_this, quality)
		if #list > 0 then return list end
	end

	if ghost.ghost_name then
		return { { name = ghost.ghost_name, count = 1, quality = quality } }
	end

	return nil
end

function Logistics.sortedInventoriesForMythos(state)
	local force = state.entity.force
	local near  = state.entity.position
	local seen  = {}
	local list  = {}

	local function add(entity)
		if Common.isVirtualChestEntity(entity) and entity.force == force then
			if not seen[entity.unit_number] then
				seen[entity.unit_number] = true
				list[#list + 1] = entity
				Lifecycle.register(entity)
			end
		end
	end

	local inside = state.inside_surface
	if inside and inside.valid then
		for _, entity in ipairs(inside.find_entities_filtered{
				name = Common.VIRTUAL_CHEST_PROTOTYPE,
			}) do
			add(entity)
		end
	end

	local outer = state.entity.surface
	if outer and outer.valid then
		for _, entity in ipairs(outer.find_entities_filtered{
				name = Common.VIRTUAL_CHEST_PROTOTYPE,
			}) do
			add(entity)
		end
	end

	for _, entity in ipairs(Inventory.sortedInventories(force, near)) do
		if not seen[entity.unit_number] then
			list[#list + 1] = entity
		end
	end

	return list
end

function Logistics.tryMineEntity(force, near_position, entity, raise_destroyed)
	local inv = Inventory.getSharedInventory(force)
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

return Logistics
