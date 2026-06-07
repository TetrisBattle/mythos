local PocketDimension = require("script.PocketDimension")
local Registry        = require("script.registry")
local MythosInventory = require("script.mythosInventory")
local Mythos          = require("script.Mythos")
local MythosRestore   = require("script.mythosRestore")

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
			state:connectExistingNeighbours()

			::continue::
		end
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

function Maintenance.removeLegacyWalls()
	Registry.forEach(function(state)
		if state.inside_surface and state.inside_surface.valid then
			PocketDimension.removePerimeterWalls(state.inside_surface)
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

function Maintenance.onConfigurationChanged()
	pruneInvalidStates()
	Maintenance.reconnectOrphanMythoi()
	Maintenance.restoreIconRenders()
	Maintenance.removeLegacyWalls()
	Maintenance.refreshExistingDimensionViews()
	Maintenance.refreshAllDimensionGateRenders()
	MythosInventory.bootstrapExisting()
end

function Maintenance.refreshAfterLoad()
	pruneInvalidStates()
	Maintenance.reconnectOrphanMythoi()
	Maintenance.refreshAllDimensionGateRenders()
	Maintenance.refreshExistingDimensionViews()
end

return Maintenance
