local PocketDimension = require("script.pocket_dimension.init")
local Connections     = require("script.mythos.connections")
local MythosRestore   = require("script.mythosRestore")
local Bridge          = require("script.power.bridge")
local Registry        = require("script.mythos.registry")
local util            = require("script.util")
local Snapshot        = require("script.clone.snapshot")
local Queue           = require("script.clone.queue")
local Blueprint       = require("script.clone.blueprint")

local Apply = {}

local function dimensionHasPlayerContent(surface)
	if not (surface and surface.valid) then return false end
	for _, entity in pairs(surface.find_entities()) do
		if entity.valid and not util.isInfrastructureEntityName(entity.name) then
			return true
		end
	end
	if #surface.find_entities_filtered { type = "entity-ghost" } > 0 then return true end
	if #surface.find_entities_filtered { type = "tile-ghost" } > 0 then return true end
	return false
end

local function hasCustomIcons(state)
	if not (state and state.custom_icons) then return false end
	for _ in pairs(state.custom_icons) do return true end
	return false
end

local function needsDeepCopy(state)
	if not state then return true end
	if not (state.inside_surface and state.inside_surface.valid) then return true end
	if hasCustomIcons(state) then return false end
	return not dimensionHasPlayerContent(state.inside_surface)
end

local function dropMythosItem(targetEntity, saved_id)
	if not (targetEntity and targetEntity.valid and targetEntity.surface and targetEntity.surface.valid) then
		return
	end

	local dropped = targetEntity.surface.create_entity{
		name     = "item-on-ground",
		position = targetEntity.position,
		stack    = {
			name  = saved_id and "mythos-with-contents" or "mythos",
			count = 1,
		},
	}
	if dropped and dropped.valid and saved_id then
		dropped.stack.tags = { saved_id = saved_id }
	end
end

local function preserveMythosBeforeClear(entity, targetEntity)
	local state = entity.unit_number and Registry.get(entity.unit_number)
	if state then
		local saved_id = state:save()
		dropMythosItem(targetEntity, saved_id)
	elseif targetEntity and targetEntity.valid then
		dropMythosItem(targetEntity, nil)
	end

	if entity.valid then
		entity.destroy{ raise_destroy = false }
	end
end

local function clearPlayerContent(surface, targetEntity)
	for _, entity in pairs(surface.find_entities()) do
		if entity.valid and not util.isInfrastructureEntityName(entity.name) then
			if entity.name == "mythos" then
				preserveMythosBeforeClear(entity, targetEntity)
			else
				entity.destroy{ raise_destroy = false }
			end
		end
	end
	for _, entity in pairs(surface.find_entities_filtered { type = "entity-ghost" }) do
		if entity.valid then entity.destroy{ raise_destroy = false } end
	end
	for _, entity in pairs(surface.find_entities_filtered { type = "tile-ghost" }) do
		if entity.valid then entity.destroy{ raise_destroy = false } end
	end
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

local function buildState(Mythos, entity, inside_surface, inner_acc)
	local slots, byExternalPos = Connections.buildSlots(entity.position.x, entity.position.y)
	local outer_acc = Bridge.createOuterAccumulatorForEntity(entity)

	local outer_surface = entity.surface
	PocketDimension.syncSurfaceProperties(inside_surface, outer_surface)

	return setmetatable({
		entity                  = entity,
		slots                   = slots,
		byExternalPos           = byExternalPos,
		inside_surface          = inside_surface,
		pendingDeletions        = {},
		outer_acc               = outer_acc,
		inner_acc               = inner_acc,
		dimension_gate_positions = PocketDimension.defaultDimensionGatePositions(),
	}, Mythos)
end

local function runBulkClone(sourceSurface, entities, destSurface, destForce)
	if #entities == 0 then return end
	Queue.enterBulkClone()
	sourceSurface.clone_entities{
		entities             = entities,
		destination_offset   = { 0, 0 },
		destination_surface  = destSurface,
		destination_force    = destForce,
	}
	Queue.exitBulkClone()
end

local function prepareDestinationFloor(state, sourceBounds)
	local targetWidth  = util.floorWidth(sourceBounds)
	local targetHeight = util.floorHeight(sourceBounds)
	state:syncFloorBoundsFromTiles()
	local curWidth  = util.floorWidth(state.floor_bounds)
	local curHeight = util.floorHeight(state.floor_bounds)
	if curWidth ~= targetWidth or curHeight ~= targetHeight then
		state:resizeTo(targetWidth, targetHeight)
	else
		state.floor_bounds = util.copyBounds(sourceBounds)
	end
end

local function finishDimensionApply(state, sourceState, destForce)
	state:syncFloorBoundsFromTiles()
	if state.floor_bounds then
		state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
		PocketDimension.ensureRemoteViewReady(
			state.inside_surface, state.floor_bounds, destForce
		)
	else
		state.inside_x = PocketDimension.VIEW_X
		state.inside_y = PocketDimension.VIEW_Y
	end
	state.dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
		sourceState.dimension_gate_positions
	)
	state:invalidateDimensionGateLayout()
	Bridge.ensureHubPole(state)
	state:syncElectricity()
	state:refreshGateRenders()
	Snapshot.restoreCustomIcons(state, sourceState.custom_icons)
end

local function resolveSourceBounds(sourceState)
	local sourceBounds = sourceState.floor_bounds
	local sourceSurface = sourceState.inside_surface
	if not sourceBounds and sourceSurface and sourceSurface.valid then
		sourceBounds = PocketDimension.inferFloorBounds(sourceSurface)
	end
	return sourceBounds
end

local function registerPlacementShell(state, sourceState, defer_remote_view_prep)
	local sourceBounds = resolveSourceBounds(sourceState)
	if not sourceBounds then return end

	state.floor_bounds = util.copyBounds(sourceBounds)
	state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
	if not defer_remote_view_prep
			and state.inside_surface and state.inside_surface.valid then
		PocketDimension.syncRemoteViewInfrastructure(
			state.inside_surface, state.floor_bounds, state.entity.force
		)
	end
	Snapshot.restoreCustomIcons(state, sourceState.custom_icons)
	state.dimension_gate_positions = PocketDimension.normalizeDimensionGatePositions(
		sourceState.dimension_gate_positions
	)
end

local function finishNormalPlacement(Mythos, entity)
	if Registry.get(entity.unit_number) then return end

	local state = Mythos.new(entity)
	Registry.set(entity.unit_number, state)
	state:syncElectricity()
	state:connectExistingNeighbours()
end

local function cloneToEntity(Mythos, destEntity, sourceState, opts)
	if not (destEntity and destEntity.valid and sourceState) then return false end

	local sourceSurface = sourceState.inside_surface
	if not (sourceSurface and sourceSurface.valid) then return false end

	local existing = Registry.get(destEntity.unit_number)
	local state
	local inside_surface
	local reusing = existing and existing.inside_surface and existing.inside_surface.valid
	local defer_remote_view_prep = not reusing

	if reusing then
		state = existing
		inside_surface = state.inside_surface
		clearPlayerContent(inside_surface, destEntity)
		PocketDimension.syncSurfaceProperties(inside_surface, destEntity.surface)
	else
		local inner_acc
		inside_surface, inner_acc = PocketDimension.create(
			destEntity.unit_number, destEntity.force, destEntity.surface,
			{ defer_remote_view_prep = true, defer_force_hiding = true }
		)
		Queue.queueSurfaceHide(inside_surface, destEntity.force)
		state = buildState(Mythos, destEntity, inside_surface, inner_acc)
	end

	registerPlacementShell(state, sourceState, defer_remote_view_prep)
	Registry.set(destEntity.unit_number, state)
	state:syncElectricity()

	return Queue.queueDeferredDimensionApply(Mythos, state, sourceState, destEntity.force, function()
		state:connectExistingNeighbours()
	end, opts)
end

local function extractPlacementSavedId(Mythos, entity, event)
	local saved_id = Mythos.extractSavedId(event)
	if saved_id then return Snapshot.normalizeSavedId(saved_id), true end

	-- Robot ghost revive and script_raised_revive expose tags on the event.
	if event and event.tags then
		saved_id = Snapshot.readTagSavedId(event.tags)
		if saved_id then return saved_id, false end
	end

	saved_id = Snapshot.readTagSavedId(entity and entity.tags)
	if saved_id then return saved_id, false end

	return nil, false
end

local function tryCloneFromPlayerCopySource(Mythos, entity, event)
	if not (event and event.player_index) then return false end
	local player = game.get_player(event.player_index)
	if not player then return false end

	local source = player.entity_copy_source
	if not (source and source.valid and source.name == "mythos") then return false end
	if source.unit_number == entity.unit_number then return false end

	Apply.cloneFromEntity(Mythos, source, entity, { immediate = true })
	return Registry.get(entity.unit_number) ~= nil
end

local function capturePlacementIntent(Mythos, entity, event)
	if Blueprint.pendingPasteAllowed(event) then
		return {
			kind     = "saved_id",
			Mythos   = Mythos,
			entity   = entity,
			saved_id = Blueprint.consumePendingPaste(event),
			consume  = false,
		}
	end

	local saved_id, consume = extractPlacementSavedId(Mythos, entity, event)
	if saved_id then
		return {
			kind     = "saved_id",
			Mythos   = Mythos,
			entity   = entity,
			saved_id = saved_id,
			consume  = consume,
		}
	end

	if event and event.player_index then
		local player = game.get_player(event.player_index)
		local source = player and player.entity_copy_source
		if source and source.valid and source.name == "mythos"
				and source.unit_number ~= entity.unit_number then
			return {
				kind          = "entity",
				Mythos        = Mythos,
				entity        = entity,
				source_entity = source,
			}
		end
	end

	return nil
end

local function placementNeedsClone(Mythos, entity, event, existing)
	if existing and not needsDeepCopy(existing) then return false end
	if existing and Queue.hasDeferredApplyFor(existing) then return false end
	if Blueprint.pendingPasteAllowed(event) then return true end
	local saved_id = select(1, extractPlacementSavedId(Mythos, entity, event))
	if saved_id then return true end
	if event and event.player_index then
		local player = game.get_player(event.player_index)
		local source = player and player.entity_copy_source
		if source and source.valid and source.name == "mythos"
				and source.unit_number ~= entity.unit_number then
			return true
		end
	end
	return false
end

local function runPlacement(Mythos, entity, event)
	local paste_saved_id = Blueprint.consumePendingPaste(event)
	if paste_saved_id then
		Apply.cloneFromSavedId(Mythos, entity, paste_saved_id, false)
		return
	end

	local saved_id, consume = extractPlacementSavedId(Mythos, entity, event)
	if saved_id then
		Apply.cloneFromSavedId(Mythos, entity, saved_id, consume)
		return
	end

	if tryCloneFromPlayerCopySource(Mythos, entity, event) then
		return
	end

	if Registry.get(entity.unit_number) then return end

	finishNormalPlacement(Mythos, entity)
end

function Apply.schedulePlacement(Mythos, entity, event)
	local existing = Registry.get(entity.unit_number)
	if existing and not needsDeepCopy(existing) then
		Blueprint.discardPendingPasteSlot(event)
		return
	end

	if existing and Queue.hasDeferredApplyFor(existing) then
		return
	end

	local unit_number = entity.unit_number
	if not Queue.markPlacementTick(unit_number, game.tick) then
		return
	end

	if placementNeedsClone(Mythos, entity, event, existing) then
		local intent = capturePlacementIntent(Mythos, entity, event)
		if intent then
			Queue.queueClonePlacement(intent)
			return
		end
	end

	runPlacement(Mythos, entity, event)
end

function Apply.cloneFromSavedId(Mythos, entity, saved_id, consume)
	saved_id = Snapshot.normalizeSavedId(saved_id)
	if not saved_id then
		finishNormalPlacement(Mythos, entity)
		return
	end

	storage.saved_dimensions = storage.saved_dimensions or {}
	local saved = storage.saved_dimensions[saved_id]
	if not saved then
		finishNormalPlacement(Mythos, entity)
		return
	end

	if consume then
		storage.saved_dimensions[saved_id] = nil
		if saved.surface and saved.surface.valid then
			local state = MythosRestore.fromSaved(Mythos, entity, saved)
			Registry.set(entity.unit_number, state)
			Queue.queueDeferredFinish(function()
				MythosRestore.finishFromSaved(state, entity, saved)
			end)
			return
		end
		local sourceState = Snapshot.resolveLazySourceState(saved)
		if sourceState and cloneToEntity(Mythos, entity, sourceState, nil) then
			return
		end
		finishNormalPlacement(Mythos, entity)
		return
	end

	local sourceState = Snapshot.sourceStateFromSaved(saved)
	if not sourceState or not cloneToEntity(Mythos, entity, sourceState, nil) then
		finishNormalPlacement(Mythos, entity)
	end
end

function Apply.cloneFromEntity(Mythos, sourceEntity, destEntity, opts)
	if not (destEntity and destEntity.valid) then return end

	local sourceState = Snapshot.resolveSourceState(sourceEntity)
	if not sourceState then
		if not Registry.get(destEntity.unit_number) then
			finishNormalPlacement(Mythos, destEntity)
		end
		return
	end

	if not cloneToEntity(Mythos, destEntity, sourceState, opts) then
		if not Registry.get(destEntity.unit_number) then
			finishNormalPlacement(Mythos, destEntity)
		end
	end
end

function Apply.queueHandlers()
	return {
		cloneFromEntity          = Apply.cloneFromEntity,
		cloneFromSavedId        = Apply.cloneFromSavedId,
		collectCloneableEntities = collectCloneableEntities,
		finishDimensionApply     = finishDimensionApply,
		prepareDestinationFloor  = prepareDestinationFloor,
		resolveSourceBounds      = resolveSourceBounds,
		runBulkClone             = runBulkClone,
	}
end

return Apply
