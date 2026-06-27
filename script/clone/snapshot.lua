local PocketDimension = require("script.pocket_dimension.init")
local Registry        = require("script.mythos.registry")
local Queue           = require("script.clone.queue")
local util            = require("script.util")

local Snapshot = {}

function Snapshot.restoreCustomIcons(state, customIcons)
	if not customIcons then return end
	for idx, signal in pairs(customIcons) do
		state:setIcon(idx, signal)
	end
end

function Snapshot.normalizeSavedId(saved_id)
	if saved_id == nil then return nil end
	if type(saved_id) == "string" and saved_id:match("^blueprint%-snapshot%-") then
		return saved_id
	end
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

local function copyTable(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for k, v in pairs(value) do
		result[copyTable(k)] = copyTable(v)
	end
	return result
end

local function collectCloneableEntities(surface)
	local entities = {}
	local seen = {}

	local function add(entity)
		if not (entity and entity.valid) then return end
		local unit_number = entity.unit_number
		if unit_number and seen[unit_number] then return end
		if unit_number then seen[unit_number] = true end
		entities[#entities + 1] = entity
	end

	for _, entity in pairs(surface.find_entities()) do
		if not util.isInfrastructureEntityName(entity.name) then
			add(entity)
		end
	end

	for _, entity in pairs(surface.find_entities_filtered { type = "entity-ghost" }) do
		add(entity)
	end

	for _, entity in pairs(surface.find_entities_filtered { type = "tile-ghost" }) do
		add(entity)
	end

	return entities
end

local function nextSnapshotSurfaceName(saved_id)
	local suffix_id = tostring(saved_id):match("^blueprint%-snapshot%-(.+)$") or saved_id
	local base = "mythos-blueprint-snapshot-" .. suffix_id
	if not game.surfaces[base] then return base end

	local suffix = 1
	while game.surfaces[base .. "-" .. suffix] do
		suffix = suffix + 1
	end
	return base .. "-" .. suffix
end

local function createSnapshotSurface(saved_id, sourceState, sourceForce)
	local sourceSurface = sourceState.inside_surface
	if not (sourceSurface and sourceSurface.valid) then return nil end

	local bounds = sourceState.floor_bounds
	if not bounds then
		bounds = PocketDimension.inferFloorBounds(sourceSurface)
	end

	---@diagnostic disable-next-line: missing-fields
	local snapshot = game.create_surface(nextSnapshotSurfaceName(saved_id), {
		default_enable_all_autoplace_controls = false,
		width = 0,
		height = 0,
	})

	for _, force in pairs(game.forces) do
		force.set_surface_hidden(snapshot, true)
	end
	PocketDimension.syncSurfaceProperties(snapshot, sourceSurface)
	PocketDimension.ensureRemoteViewReady(snapshot, bounds, sourceForce)

	local entities = collectCloneableEntities(sourceSurface)
	if #entities > 0 then
		Queue.enterBulkClone()
		sourceSurface.clone_entities{
			entities             = entities,
			destination_offset   = { 0, 0 },
			destination_surface  = snapshot,
			destination_force    = sourceForce,
		}
		Queue.exitBulkClone()
	end

	return snapshot, bounds
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
	local saved_id = "blueprint-snapshot-" .. storage.mythos_next_snapshot_id

	local snapshotSurface, floor_bounds = createSnapshotSurface(
		saved_id, sourceState, sourceEntity.force
	)
	if not snapshotSurface then return nil end
	Queue.processPendingEntityClones(Mythos, { immediate = true })

	storage.saved_dimensions = storage.saved_dimensions or {}
	storage.saved_dimensions[saved_id] = {
		surface                  = snapshotSurface,
		source_unit_number       = sourceEntity.unit_number,
		floor_bounds             = util.copyBounds(floor_bounds),
		custom_icons             = copyTable(sourceState.custom_icons),
		dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
			copyTable(sourceState.dimension_gate_positions),
			floor_bounds
		),
		items                    = {},
	}
	return saved_id
end

return Snapshot
