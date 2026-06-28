local PocketDimension = require("script.pocket_dimension.init")
local Registry = require("script.mythos.registry")
local SettingsSync = require("script.settingsSync")
local Mythos = require("script.mythos.init")
local MythosRestore = require("script.mythosRestore")
local Bridge = require("script.power.bridge")
local util = require("script.util")

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
			for _, entity in ipairs(surface.find_entities_filtered({ name = "mythos" })) do
				if entity.valid and not Registry.get(entity.unit_number) then
					local dim_name = "mythos-dimension-" .. entity.unit_number
					local inner = game.surfaces[dim_name]
					local state
					if inner and inner.valid then
						state = MythosRestore.fromSaved(Mythos, entity, {
							surface = inner,
							items = {},
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
		if not (state.entity and state.entity.valid) then
			return
		end
		if state.inside_surface and state.inside_surface.valid then
			state:syncFloorBoundsFromTiles()
			if state.floor_bounds then
				state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
				PocketDimension.ensureRemoteViewReady(state.inside_surface, state.floor_bounds, state.entity.force)
			end
		end
	end)
end

function Migrations.refreshAllDimensionGateRenders()
	Registry.forEach(function(state)
		if not (state.entity and state.entity.valid) then
			return
		end
		if state.slots and state.inside_surface and state.inside_surface.valid then
			state:refreshGateRenders()
		end
	end)
end

function Migrations.refreshPowerLinkEntities()
	Registry.forEach(function(state)
		if state.syncFloorBoundsFromTiles then
			state:syncFloorBoundsFromTiles()
		end
		Bridge.refreshPowerLinks(state)
	end)
end

function Migrations.refreshPowerLinkEntitiesIfNeeded()
	Registry.forEach(function(state)
		if state.syncFloorBoundsFromTiles then
			state:syncFloorBoundsFromTiles()
		end
		if Bridge.powerLinksNeedRefresh(state) then
			Bridge.refreshPowerLinks(state)
		else
			Bridge.ensureHubPole(state)
			if state.entity and state.entity.valid then
				Bridge.ensureOuterPowerBridge(state.entity)
			end
			if state.syncElectricity then
				state:syncElectricity()
			end
		end
	end)
end

local function applyStep(step)
	step.run()
end

local CONFIGURATION_CHANGED_STEPS = {
	{ name = "pruneInvalidStates", run = pruneInvalidStates },
	{ name = "reconnectOrphanMythoi", run = Migrations.reconnectOrphanMythoi },
	{ name = "refreshPowerLinkEntities", run = Migrations.refreshPowerLinkEntities },
	{ name = "restoreIconRenders", run = Migrations.restoreIconRenders },
	{ name = "refreshExistingDimensionViews", run = Migrations.refreshExistingDimensionViews },
	{ name = "refreshAllDimensionGateRenders", run = Migrations.refreshAllDimensionGateRenders },
	{ name = "applySettings", run = SettingsSync.apply },
}

local POST_LOAD_REFRESH_STEPS = {
	{ name = "pruneInvalidStates", run = pruneInvalidStates },
	{ name = "reconnectOrphanMythoi", run = Migrations.reconnectOrphanMythoi },
	{ name = "refreshPowerLinkEntitiesIfNeeded", run = Migrations.refreshPowerLinkEntitiesIfNeeded },
	{ name = "refreshAllDimensionGateRenders", run = Migrations.refreshAllDimensionGateRenders },
	{ name = "refreshExistingDimensionViews", run = Migrations.refreshExistingDimensionViews },
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
