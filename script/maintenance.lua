local PocketDimension = require("script.PocketDimension")
local Registry        = require("script.registry")

local Maintenance = {}

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
		if state.slots and state.inside_surface and state.inside_surface.valid then
			state:refreshGateRenders()
		end
	end)
end

function Maintenance.onConfigurationChanged()
	Maintenance.restoreIconRenders()
	Maintenance.removeLegacyWalls()
	Maintenance.refreshExistingDimensionViews()
	Maintenance.refreshAllDimensionGateRenders()
end

function Maintenance.refreshAfterLoad()
	Maintenance.refreshAllDimensionGateRenders()
	Maintenance.refreshExistingDimensionViews()
end

return Maintenance
