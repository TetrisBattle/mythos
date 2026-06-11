local Config = require("script.config")
local Common = require("script.virtual_chest.common")

local Inventory = {}

function Inventory.getSharedInventory(force)
	if not force then return nil end
	local inv = force.get_linked_inventory(
		Common.VIRTUAL_CHEST_PROTOTYPE,
		Common.VIRTUAL_CHEST_LINK_ID
	)
	if inv and inv.valid then return inv end
	return Inventory.ensureSharedStorage(force)
end

function Inventory.ensureSharedStorage(force)
	if Config.hideVirtualInventory() then return nil end
	if not force then return nil end

	storage.virtual_chest_storage_anchors = storage.virtual_chest_storage_anchors or {}
	local anchor_id = storage.virtual_chest_storage_anchors[force.index]
	if anchor_id then
		local anchor = game.get_entity_by_unit_number(anchor_id)
		if anchor and anchor.valid then
			anchor.link_id = Common.VIRTUAL_CHEST_LINK_ID
			local inv = force.get_linked_inventory(
				Common.VIRTUAL_CHEST_PROTOTYPE,
				Common.VIRTUAL_CHEST_LINK_ID
			)
			if inv and inv.valid then return inv end
		elseif anchor then
			anchor.destroy()
		end
	end

	local surface = game.surfaces[1]
	if not surface then return nil end

	local anchor = surface.create_entity{
		name                      = Common.VIRTUAL_CHEST_PROTOTYPE,
		position                  = { -50000 + force.index, -50000 },
		force                     = force,
		create_build_effect_smoke = false,
	}
	if not (anchor and anchor.valid) then return nil end

	anchor.link_id      = Common.VIRTUAL_CHEST_LINK_ID
	anchor.destructible = false
	storage.virtual_chest_storage_anchors[force.index] = anchor.unit_number
	return force.get_linked_inventory(
		Common.VIRTUAL_CHEST_PROTOTYPE,
		Common.VIRTUAL_CHEST_LINK_ID
	)
end

function Inventory.normalizePlaceRequests(source, defaultQuality)
	local list = {}
	if not source then return list end

	if source[1] then
		for _, entry in ipairs(source) do
			if type(entry) == "table" and entry.name then
				list[#list + 1] = {
					name    = entry.name,
					count   = entry.count or 1,
					quality = Common.stackQuality(entry.quality) or defaultQuality,
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

function Inventory.totalItemCount(inv)
	local total = 0
	for i = 1, #inv do
		local stack = inv[i]
		if stack.valid_for_read then
			total = total + stack.count
		end
	end
	return total
end

function Inventory.findInventories(force)
	storage.virtualChests = storage.virtualChests or {}
	local list = {}
	for unit_number in pairs(storage.virtualChests) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if entity and entity.valid and entity.name == Common.VIRTUAL_CHEST_PROTOTYPE then
			local entityForce = entity.force
			if entityForce and entityForce == force then
				list[#list + 1] = entity
			end
		else
			storage.virtualChests[unit_number] = nil
		end
	end
	return list
end

function Inventory.sortedInventories(force, near_position)
	local list = Inventory.findInventories(force)
	if near_position then
		table.sort(list, function(a, b)
			return Common.distanceSq(a.position, near_position)
				< Common.distanceSq(b.position, near_position)
		end)
	end
	return list
end

local function countInSharedInventory(force, req)
	local inv = Inventory.getSharedInventory(force)
	if not inv then return 0 end

	local lookup = Common.itemLookup(req)
	local total  = inv.get_item_count(lookup)
	if total >= (req.count or 1) then return total end

	if Common.stackQuality(req.quality) then
		total = total + inv.get_item_count(req.name)
	end
	return total
end

local function removeFromSharedInventory(force, req)
	local inv = Inventory.getSharedInventory(force)
	if not inv then return 0 end

	local remaining = req.count or 1
	local quality   = Common.stackQuality(req.quality)
	local lookup    = Common.itemLookup(req)
	local have      = inv.get_item_count(lookup)

	if have < remaining and quality then
		lookup = req.name
		have   = inv.get_item_count(lookup)
	end

	local take = math.min(have, remaining)
	if take > 0 then
		local removeFilter = Common.itemRemoveFilter(req, take)
		if lookup == req.name then
			removeFilter = { name = req.name, count = take }
		end
		inv.remove(removeFilter)
		remaining = remaining - take
	end

	return (req.count or 1) - remaining
end

function Inventory.getItemCountFromInventories(inventories, req)
	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return 0 end
	return countInSharedInventory(force, req)
end

function Inventory.removeItemsFromInventories(inventories, req)
	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return 0 end
	return removeFromSharedInventory(force, req)
end

function Inventory.insertItemsIntoInventories(inventories, items)
	if not items then return end

	local force = inventories[1] and inventories[1].valid and inventories[1].force
	if not force then return end

	local inv = Inventory.getSharedInventory(force)
	if not inv then return end

	for _, item in pairs(items) do
		inv.insert({
			name    = item.name,
			count   = item.count,
			quality = item.quality,
		})
	end
end

function Inventory.getItemCount(force, item_name, near_position)
	return countInSharedInventory(force, { name = item_name, count = 1 })
end

function Inventory.removeItems(force, near_position, item_name, count)
	return removeFromSharedInventory(force, { name = item_name, count = count })
end

function Inventory.insertStack(force, near_position, stack)
	if not stack.valid_for_read then return stack.count end

	local inv = Inventory.getSharedInventory(force)
	if not inv then return stack.count end

	local before = Inventory.totalItemCount(inv)
	inv.insert({
		name    = stack.name,
		count   = stack.count,
		quality = stack.quality,
	})
	local after = Inventory.totalItemCount(inv)
	return stack.count - (after - before)
end

function Inventory.insertItems(force, near_position, items)
	if not items then return end

	local inv = Inventory.getSharedInventory(force)
	if not inv then return end

	for _, item in pairs(items) do
		inv.insert({
			name    = item.name,
			count   = item.count,
			quality = item.quality,
		})
	end
end

function Inventory.enforceStorageCap(force)
	local inv = Inventory.getSharedInventory(force)
	if not inv then return end

	local excess = Inventory.totalItemCount(inv) - Common.MAX_TOTAL_ITEMS
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

return Inventory
