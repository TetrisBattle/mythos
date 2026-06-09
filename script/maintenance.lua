local PocketDimension = require("script.PocketDimension")
local Registry        = require("script.registry")
local VirtualChest = require("script.virtualChest")
local Mythos          = require("script.Mythos")
local MythosRestore   = require("script.mythosRestore")
local util            = require("script.util")

local Maintenance = {}

local function pruneInvalidStates()
	for unitNumber, state in pairs(Registry.all()) do
		if not (state.entity and state.entity.valid) then
			Registry.remove(unitNumber)
		end
	end
end

function Maintenance.reconnectOrphanMythoi()
	for _, surface in pairs(game.surfaces) do
		if util.parseDimensionUnitNumber(surface) then goto continue_surface end
		for _, entity in ipairs(surface.find_entities_filtered{ name = "mythos" }) do
			if not (entity.valid and not Registry.get(entity.unit_number)) then goto continue end

			local dim_name = "mythos-dimension-" .. entity.unit_number
			local inner = game.surfaces[dim_name]
			local state
			if inner and inner.valid then
				state = MythosRestore.fromSaved(Mythos, entity, {
					surface      = inner,
					items        = {},
					custom_icons = nil,
				})
			else
				state = Mythos.new(entity)
			end
			Registry.set(entity.unit_number, state)
			state:syncElectricity()
			state:connectExistingNeighbours()

			::continue::
		end
		::continue_surface::
	end
end

function Maintenance.restoreIconRenders()
	Registry.forEach(function(state)
		if state.entity and state.entity.valid and state.custom_icons then
			state.icon_renders = nil
			for idx, signal in pairs(state.custom_icons) do
				state:setIcon(idx, signal)
			end
		end
	end)
end

function Maintenance.refreshExistingDimensionViews()
	Registry.forEach(function(state)
		if not (state.entity and state.entity.valid) then return end
		if state.inside_surface and state.inside_surface.valid then
			state:syncFloorBoundsFromTiles()
			if state.floor_bounds then
				state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
				PocketDimension.ensureRemoteViewReady(
					state.inside_surface, state.floor_bounds, state.entity.force
				)
			end
		end
	end)
end

function Maintenance.refreshAllDimensionGateRenders()
	Registry.forEach(function(state)
		if not (state.entity and state.entity.valid) then return end
		if state.slots and state.inside_surface and state.inside_surface.valid then
			state:refreshGateRenders()
		end
	end)
end

-- Outer link entities belong on the placement surface only (world grid).
-- Any left inside pocket-dimension surfaces are stale and flash power warnings.
function Maintenance.cleanupDimensionSurfaceOuterAccs()
	for _, surface in pairs(game.surfaces) do
		if util.parseDimensionUnitNumber(surface) then
			MythosRestore.destroyStrayOuterAccumulators(surface)
			MythosRestore.destroyStrayInnerAccumulators(surface)
		end
	end
end

function Maintenance.refreshPowerLinkEntities()
	Registry.forEach(function(state)
		MythosRestore.refreshPowerLinks(state)
	end)
end

function Maintenance.refreshPowerLinkEntitiesIfNeeded()
	Registry.forEach(function(state)
		if MythosRestore.powerLinksNeedRefresh(state) then
			MythosRestore.refreshPowerLinks(state)
		else
			MythosRestore.ensureHubPole(state)
			if state.entity and state.entity.valid then
				MythosRestore.ensureOuterPowerBridge(state.entity)
			end
		end
	end)
end

function Maintenance.migrateDimensionFloorTiles()
	for _, surface in pairs(game.surfaces) do
		if not util.parseDimensionUnitNumber(surface) then goto continue_surface end

		local tiles = {}
		for _, tile in pairs(surface.find_tiles_filtered{ name = "lab-dark-2" }) do
			tiles[#tiles + 1] = {
				name     = "mythos-dimension-floor",
				position = tile.position,
			}
		end
		if #tiles > 0 then
			surface.set_tiles(tiles)
		end

		::continue_surface::
	end
end

function Maintenance.removeNestedMythoi()
	for _, surface in pairs(game.surfaces) do
		if not util.parseDimensionUnitNumber(surface) then goto continue_surface end

		for _, entity in ipairs(surface.find_entities_filtered{ name = "mythos" }) do
			if not entity.valid then goto continue_entity end

			local pos   = entity.position
			local force = entity.force
			local state = Registry.get(entity.unit_number)
			if state then
				state:destroy()
			else
				entity.destroy{ raise_destroy = false }
			end

			surface.spill_item_stack{
				position = pos,
				stack    = { name = "mythos", count = 1 },
				force    = force,
			}

			::continue_entity::
		end

		::continue_surface::
	end
end

function Maintenance.cleanupNestedOuterAccReferences()
	Registry.forEach(function(state)
		if not (state.entity and state.entity.valid) then return end
		if not util.parseDimensionUnitNumber(state.entity.surface) then return end
		if state.outer_acc and state.outer_acc.valid then
			state.outer_acc.destroy()
		end
		state.outer_acc = nil
		MythosRestore.destroyStrayOuterAccumulators(state.entity.surface, state.entity.position)
	end)
end

function Maintenance.onConfigurationChanged()
	pruneInvalidStates()
	Maintenance.migrateDimensionFloorTiles()
	Maintenance.removeNestedMythoi()
	Maintenance.cleanupDimensionSurfaceOuterAccs()
	Maintenance.cleanupNestedOuterAccReferences()
	Maintenance.reconnectOrphanMythoi()
	Maintenance.refreshPowerLinkEntities()
	Maintenance.restoreIconRenders()
	Maintenance.refreshExistingDimensionViews()
	Maintenance.refreshAllDimensionGateRenders()
	VirtualChest.bootstrapExisting()
end

function Maintenance.refreshAfterLoad()
	pruneInvalidStates()
	Maintenance.migrateDimensionFloorTiles()
	Maintenance.removeNestedMythoi()
	Maintenance.cleanupDimensionSurfaceOuterAccs()
	Maintenance.cleanupNestedOuterAccReferences()
	Maintenance.reconnectOrphanMythoi()
	Maintenance.refreshPowerLinkEntitiesIfNeeded()
	Maintenance.refreshAllDimensionGateRenders()
	Maintenance.refreshExistingDimensionViews()
end

return Maintenance
