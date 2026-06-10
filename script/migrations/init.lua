local PocketDimension = require("script.pocket_dimension.init")
local Registry        = require("script.mythos.registry")
local SettingsSync    = require("script.settingsSync")
local Mythos          = require("script.mythos.init")
local MythosRestore   = require("script.mythosRestore")
local Bridge          = require("script.power.bridge")
local util            = require("script.util")

local Migrations = {}

local function pruneInvalidStates()
	for unitNumber, state in pairs(Registry.all()) do
		if not (state.entity and state.entity.valid) then
			Registry.remove(unitNumber)
		end
	end
end

function Migrations.reconnectOrphanMythoi()
	for _, surface in pairs(game.surfaces) do
		if not util.parseDimensionUnitNumber(surface) then
			for _, entity in ipairs(surface.find_entities_filtered{ name = "mythos" }) do
				if entity.valid and not Registry.get(entity.unit_number) then
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
				end
			end
		end
	end
end

function Migrations.restoreIconRenders()
	Registry.forEach(function(state)
		if state.entity and state.entity.valid and state.custom_icons then
			state.icon_renders = nil
			for idx, signal in pairs(state.custom_icons) do
				state:setIcon(idx, signal)
			end
		end
	end)
end

function Migrations.refreshExistingDimensionViews()
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

function Migrations.refreshAllDimensionGateRenders()
	Registry.forEach(function(state)
		if not (state.entity and state.entity.valid) then return end
		if state.slots and state.inside_surface and state.inside_surface.valid then
			state:refreshGateRenders()
		end
	end)
end

-- Outer link entities belong on the placement surface only (world grid).
-- Any left inside pocket-dimension surfaces are stale and flash power warnings.
function Migrations.cleanupDimensionSurfaceOuterAccs()
	for _, surface in pairs(game.surfaces) do
		if util.parseDimensionUnitNumber(surface) then
			Bridge.destroyStrayOuterAccumulators(surface)
			Bridge.destroyStrayInnerAccumulators(surface)
		end
	end
end

function Migrations.refreshPowerLinkEntities()
	Registry.forEach(function(state)
		Bridge.refreshPowerLinks(state)
	end)
end

function Migrations.refreshPowerLinkEntitiesIfNeeded()
	Registry.forEach(function(state)
		if Bridge.powerLinksNeedRefresh(state) then
			Bridge.refreshPowerLinks(state)
		else
			Bridge.ensureHubPole(state)
			if state.entity and state.entity.valid then
				Bridge.ensureOuterPowerBridge(state.entity)
			end
		end
	end)
end

function Migrations.migrateDimensionFloorTiles()
	for _, surface in pairs(game.surfaces) do
		if util.parseDimensionUnitNumber(surface) then
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
		end
	end
end

function Migrations.removeNestedMythoi()
	for _, surface in pairs(game.surfaces) do
		if util.parseDimensionUnitNumber(surface) then
			for _, entity in ipairs(surface.find_entities_filtered{ name = "mythos" }) do
				if entity.valid then
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
				end
			end
		end
	end
end

function Migrations.cleanupNestedOuterAccReferences()
	Registry.forEach(function(state)
		if not (state.entity and state.entity.valid) then return end
		if not util.parseDimensionUnitNumber(state.entity.surface) then return end
		if state.outer_acc and state.outer_acc.valid then
			state.outer_acc.destroy()
		end
		state.outer_acc = nil
		Bridge.destroyStrayOuterAccumulators(state.entity.surface, state.entity.position)
	end)
end

local function applyStep(step)
	step.run()
end

local CONFIGURATION_CHANGED_STEPS = {
	{ name = "pruneInvalidStates",              run = pruneInvalidStates },
	{ name = "migrateDimensionFloorTiles",      run = Migrations.migrateDimensionFloorTiles },
	{ name = "removeNestedMythoi",              run = Migrations.removeNestedMythoi },
	{ name = "cleanupDimensionSurfaceOuterAccs", run = Migrations.cleanupDimensionSurfaceOuterAccs },
	{ name = "cleanupNestedOuterAccReferences", run = Migrations.cleanupNestedOuterAccReferences },
	{ name = "reconnectOrphanMythoi",           run = Migrations.reconnectOrphanMythoi },
	{ name = "refreshPowerLinkEntities",        run = Migrations.refreshPowerLinkEntities },
	{ name = "restoreIconRenders",              run = Migrations.restoreIconRenders },
	{ name = "refreshExistingDimensionViews",   run = Migrations.refreshExistingDimensionViews },
	{ name = "refreshAllDimensionGateRenders",  run = Migrations.refreshAllDimensionGateRenders },
	{ name = "applySettings",                   run = SettingsSync.apply },
}

local POST_LOAD_REFRESH_STEPS = {
	{ name = "pruneInvalidStates",                run = pruneInvalidStates },
	{ name = "migrateDimensionFloorTiles",        run = Migrations.migrateDimensionFloorTiles },
	{ name = "removeNestedMythoi",                run = Migrations.removeNestedMythoi },
	{ name = "cleanupDimensionSurfaceOuterAccs",  run = Migrations.cleanupDimensionSurfaceOuterAccs },
	{ name = "cleanupNestedOuterAccReferences",   run = Migrations.cleanupNestedOuterAccReferences },
	{ name = "reconnectOrphanMythoi",             run = Migrations.reconnectOrphanMythoi },
	{ name = "refreshPowerLinkEntitiesIfNeeded",  run = Migrations.refreshPowerLinkEntitiesIfNeeded },
	{ name = "refreshAllDimensionGateRenders",    run = Migrations.refreshAllDimensionGateRenders },
	{ name = "refreshExistingDimensionViews",     run = Migrations.refreshExistingDimensionViews },
}

function Migrations.onConfigurationChanged()
	for _, step in ipairs(CONFIGURATION_CHANGED_STEPS) do
		applyStep(step)
	end
end

function Migrations.refreshAfterLoad()
	for _, step in ipairs(POST_LOAD_REFRESH_STEPS) do
		applyStep(step)
	end
end

return Migrations
