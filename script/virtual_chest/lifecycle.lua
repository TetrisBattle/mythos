local Config    = require("script.config")
local Common    = require("script.virtual_chest.common")
local Inventory = require("script.virtual_chest.inventory")

local Lifecycle = {}

function Lifecycle.isVirtualChestEntity(entity)
	return Common.isVirtualChestEntity(entity)
end

function Lifecycle.ensureLinkId(entity)
	if not Common.isVirtualChestEntity(entity) then return end
	entity.link_id = Common.VIRTUAL_CHEST_LINK_ID
end

function Lifecycle.register(entity)
	storage.virtualChests = storage.virtualChests or {}
	storage.virtualChests[entity.unit_number] = true
end

function Lifecycle.unregister(unit_number)
	if not storage.virtualChests then return end
	storage.virtualChests[unit_number] = nil
end

function Lifecycle.onBuilt(entity)
	Inventory.ensureSharedStorage(entity.force)
	Lifecycle.ensureLinkId(entity)
	Lifecycle.register(entity)
end

function Lifecycle.onRemoved(entity)
	if not entity then return end
	local unit_number = entity.unit_number
	if not unit_number then return end
	if not storage.virtualChests or not storage.virtualChests[unit_number] then return end

	Lifecycle.unregister(unit_number)
end

function Lifecycle.tickSlow()
	if Config.hideVirtualInventory() then return end

	storage.virtualChests = storage.virtualChests or {}

	local forcesSeen = {}
	for unit_number in pairs(storage.virtualChests) do
		local entity = game.get_entity_by_unit_number(unit_number)
		if Common.isVirtualChestEntity(entity) then
			Lifecycle.ensureLinkId(entity)
			forcesSeen[entity.force.index] = entity.force
		else
			storage.virtualChests[unit_number] = nil
		end
	end

	for _, force in pairs(forcesSeen) do
		Inventory.ensureSharedStorage(force)
		Inventory.enforceStorageCap(force)
	end
end

function Lifecycle.bootstrapExisting()
	if Config.hideVirtualInventory() then return end

	local Migration = require("script.virtual_chest.migration")
	Migration.migrateLegacy()

	storage.virtualChests = storage.virtualChests or {}

	for _, surface in pairs(game.surfaces) do
		for _, entity in ipairs(surface.find_entities_filtered{
				name = Common.VIRTUAL_CHEST_PROTOTYPE,
			}) do
			if entity.valid then
				Lifecycle.onBuilt(entity)
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
		Inventory.ensureSharedStorage(force)
		Inventory.enforceStorageCap(force)
	end
end

return Lifecycle
