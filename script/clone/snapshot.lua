local PocketDimension = require("script.pocket_dimension.init")
local Registry        = require("script.mythos.registry")

local Snapshot = {}

function Snapshot.restoreCustomIcons(state, customIcons)
	if not customIcons then return end
	for idx, signal in pairs(customIcons) do
		state:setIcon(idx, signal)
	end
end

function Snapshot.normalizeSavedId(saved_id)
	if saved_id == nil then return nil end
	return tonumber(saved_id) or saved_id
end

function Snapshot.readTagSavedId(tags)
	if not tags then return nil end
	local ok, t = pcall(function() return tags end)
	if not ok or not t then return nil end
	return Snapshot.normalizeSavedId(t.mythos_snapshot or t.saved_id)
end

local function boundsForSurface(surface, cached)
	if cached then return cached end
	if surface and surface.valid then
		return PocketDimension.inferFloorBounds(surface)
	end
	return nil
end

function Snapshot.resolveSourceState(sourceEntity)
	local state = Registry.get(sourceEntity.unit_number)
	if state and state.inside_surface and state.inside_surface.valid then
		if not state.floor_bounds then
			state.floor_bounds = PocketDimension.inferFloorBounds(state.inside_surface)
		end
		state:normalizeDimensionGatePositions()
		return state
	end

	local surface = game.surfaces["mythos-dimension-" .. sourceEntity.unit_number]
	if surface and surface.valid then
		return {
			inside_surface           = surface,
			floor_bounds             = boundsForSurface(surface, state and state.floor_bounds),
			custom_icons             = state and state.custom_icons,
			dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
				state and state.dimension_gate_positions
			),
		}
	end

	return nil
end

function Snapshot.resolveLazySourceState(saved)
	if not saved then return nil end

	if saved.surface and saved.surface.valid then
		return {
			inside_surface           = saved.surface,
			floor_bounds             = boundsForSurface(saved.surface, saved.floor_bounds),
			custom_icons             = saved.custom_icons,
			dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
				saved.dimension_gate_positions
			),
		}
	end

	local unit_number = saved.source_unit_number
	if not unit_number then return nil end

	local live = Registry.get(unit_number)
	if live and live.inside_surface and live.inside_surface.valid then
		return {
			inside_surface           = live.inside_surface,
			floor_bounds             = saved.floor_bounds or live.floor_bounds
				or PocketDimension.inferFloorBounds(live.inside_surface),
			custom_icons             = saved.custom_icons or live.custom_icons,
			dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
				saved.dimension_gate_positions or live.dimension_gate_positions
			),
		}
	end

	local mined = storage.saved_dimensions[unit_number]
	if mined and mined.surface and mined.surface.valid then
		return {
			inside_surface           = mined.surface,
			floor_bounds             = saved.floor_bounds
				or boundsForSurface(mined.surface, mined.floor_bounds),
			custom_icons             = saved.custom_icons or mined.custom_icons,
			dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
				saved.dimension_gate_positions or mined.dimension_gate_positions
			),
		}
	end

	local surface = game.surfaces["mythos-dimension-" .. unit_number]
	if surface and surface.valid then
		return {
			inside_surface           = surface,
			floor_bounds             = saved.floor_bounds or PocketDimension.inferFloorBounds(surface),
			custom_icons             = saved.custom_icons,
			dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
				saved.dimension_gate_positions
			),
		}
	end

	return nil
end

function Snapshot.sourceStateFromSaved(saved)
	return Snapshot.resolveLazySourceState(saved)
end

function Snapshot.snapshotForBlueprint(Mythos, sourceEntity)
	local sourceState = Snapshot.resolveSourceState(sourceEntity)
	if not sourceState then return nil end

	storage.mythos_next_snapshot_id = (storage.mythos_next_snapshot_id or 0) + 1
	local saved_id = storage.mythos_next_snapshot_id

	local floor_bounds = sourceState.floor_bounds
	if not floor_bounds and sourceState.inside_surface and sourceState.inside_surface.valid then
		floor_bounds = PocketDimension.inferFloorBounds(sourceState.inside_surface)
	end

	storage.saved_dimensions = storage.saved_dimensions or {}
	storage.saved_dimensions[saved_id] = {
		source_unit_number       = sourceEntity.unit_number,
		floor_bounds             = floor_bounds,
		custom_icons             = sourceState.custom_icons,
		dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
			sourceState.dimension_gate_positions
		),
		items                    = {},
	}
	return saved_id
end

return Snapshot
