local PocketDimension = require("script.PocketDimension")
local Connections     = require("script.connections")
local MythosRestore   = require("script.mythosRestore")
local Registry        = require("script.registry")
local util            = require("script.util")

local MythosClone = {}

local PASTE_TTL                 = 3600
local ENTITIES_PER_TICK         = 250
local FINISHES_PER_TICK         = 4
local CLONE_PLACEMENTS_PER_TICK = 8
local SURFACE_HIDES_PER_TICK    = 16
-- Copy-paste completes in one shot below this count; larger interiors stream in faster batches.
local IMMEDIATE_CLONE_MAX       = 400

-- Session-only queues; copy-paste work is never resumed after save/load.
local bulk_clone_depth       = 0
local pending_entity_clones  = {}
local deferred_apply_jobs    = {}
local deferred_finish_jobs   = {}
local pending_clone_placements = {}
local pending_surface_hides  = {}
local placement_ticks        = {}

local function restoreCustomIcons(state, customIcons)
	if not customIcons then return end
	for idx, signal in pairs(customIcons) do
		state:setIcon(idx, signal)
	end
end

local function normalizeSavedId(saved_id)
	if saved_id == nil then return nil end
	return tonumber(saved_id) or saved_id
end

local function readTagSavedId(tags)
	if not tags then return nil end
	local ok, t = pcall(function() return tags end)
	if not ok or not t then return nil end
	return normalizeSavedId(t.mythos_snapshot or t.saved_id)
end

local function boundsForSurface(surface, cached)
	if cached then return cached end
	if surface and surface.valid then
		return PocketDimension.inferFloorBounds(surface)
	end
	return nil
end

local function resolveSourceState(sourceEntity)
	local state = Registry.get(sourceEntity.unit_number)
	if state and state.inside_surface and state.inside_surface.valid then
		if not state.floor_bounds then
			state.floor_bounds = PocketDimension.inferFloorBounds(state.inside_surface)
		end
		return state
	end

	local surface = game.surfaces["mythos-dimension-" .. sourceEntity.unit_number]
	if surface and surface.valid then
		return {
			inside_surface = surface,
			floor_bounds   = boundsForSurface(surface, state and state.floor_bounds),
			custom_icons   = state and state.custom_icons,
			default_width  = state and state.default_width,
			default_height = state and state.default_height,
		}
	end

	return nil
end

local function resolveLazySourceState(saved)
	if not saved then return nil end

	if saved.surface and saved.surface.valid then
		return {
			inside_surface = saved.surface,
			floor_bounds   = boundsForSurface(saved.surface, saved.floor_bounds),
			custom_icons   = saved.custom_icons,
			default_width  = saved.default_width,
			default_height = saved.default_height,
		}
	end

	local unit_number = saved.source_unit_number
	if not unit_number then return nil end

	local live = Registry.get(unit_number)
	if live and live.inside_surface and live.inside_surface.valid then
		return {
			inside_surface = live.inside_surface,
			floor_bounds   = saved.floor_bounds or live.floor_bounds
				or PocketDimension.inferFloorBounds(live.inside_surface),
			custom_icons   = saved.custom_icons or live.custom_icons,
			default_width  = saved.default_width or live.default_width,
			default_height = saved.default_height or live.default_height,
		}
	end

	local mined = storage.saved_dimensions[unit_number]
	if mined and mined.surface and mined.surface.valid then
		return {
			inside_surface = mined.surface,
			floor_bounds   = saved.floor_bounds
				or boundsForSurface(mined.surface, mined.floor_bounds),
			custom_icons   = saved.custom_icons or mined.custom_icons,
			default_width  = saved.default_width or mined.default_width,
			default_height = saved.default_height or mined.default_height,
		}
	end

	local surface = game.surfaces["mythos-dimension-" .. unit_number]
	if surface and surface.valid then
		return {
			inside_surface = surface,
			floor_bounds   = saved.floor_bounds or PocketDimension.inferFloorBounds(surface),
			custom_icons   = saved.custom_icons,
			default_width  = saved.default_width,
			default_height = saved.default_height,
		}
	end

	return nil
end

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

local function sourceStateFromSaved(saved)
	return resolveLazySourceState(saved)
end

local function clearPlayerContent(surface)
	for _, entity in pairs(surface.find_entities()) do
		if entity.valid and not util.isInfrastructureEntityName(entity.name) then
			entity.destroy{ raise_destroy = false }
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
	local outer_acc = MythosRestore.createOuterAccumulatorForEntity(entity)

	local outer_surface = entity.surface
	if outer_surface and outer_surface.valid and inside_surface.valid then
		inside_surface.solar_power_multiplier = outer_surface.solar_power_multiplier
	end

	return setmetatable({
		entity           = entity,
		slots            = slots,
		byExternalPos    = byExternalPos,
		inside_surface   = inside_surface,
		pendingDeletions = {},
		outer_acc        = outer_acc,
		inner_acc        = inner_acc,
	}, Mythos)
end

local function enterBulkClone()
	bulk_clone_depth = bulk_clone_depth + 1
end

local function exitBulkClone()
	bulk_clone_depth = bulk_clone_depth - 1
end

local function isBulkCloning()
	return bulk_clone_depth > 0
end

function MythosClone.isBulkCloning()
	return isBulkCloning()
end

local function hasDeferredApplyFor(state)
	for _, job in ipairs(deferred_apply_jobs) do
		if job.state == state then return true end
	end
	return false
end

local function isRobotBuiltEvent(event)
	return event and event.name == defines.events.on_robot_built_entity
end

local function runBulkClone(sourceSurface, entities, destSurface, destForce)
	if #entities == 0 then return end
	enterBulkClone()
	sourceSurface.clone_entities{
		entities             = entities,
		destination_offset   = { 0, 0 },
		destination_surface  = destSurface,
		destination_force    = destForce,
	}
	exitBulkClone()
end

local function processPendingEntityClones(Mythos)
	while #pending_entity_clones > 0 do
		local batch = pending_entity_clones
		pending_entity_clones = {}
		for _, pair in ipairs(batch) do
			if pair.source.valid and pair.dest.valid then
				MythosClone.cloneFromEntity(Mythos, pair.source, pair.dest)
			end
		end
	end
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
	state:syncElectricity()
	state:refreshGateRenders()
	restoreCustomIcons(state, sourceState.custom_icons)
	if sourceState.default_width then state.default_width = sourceState.default_width end
	if sourceState.default_height then state.default_height = sourceState.default_height end
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
			state.inside_surface, state.floor_bounds
		)
	end
	restoreCustomIcons(state, sourceState.custom_icons)
	if sourceState.default_width then state.default_width = sourceState.default_width end
	if sourceState.default_height then state.default_height = sourceState.default_height end
end

local function queueDeferredFinish(fn)
	deferred_finish_jobs[#deferred_finish_jobs + 1] = fn
end

local function tryCompleteApplyJob(job)
	local state = job.state
	if not (state and state.entity and state.entity.valid
			and state.inside_surface and state.inside_surface.valid) then
		return false
	end

	local sourceSurface = job.sourceState.inside_surface
	if not (sourceSurface and sourceSurface.valid) then return false end

	if job.needs_entity_collect then
		job.entities = collectCloneableEntities(sourceSurface)
		job.needs_entity_collect = false
		job.cursor = 1
	end

	if job.needs_floor_prep and job.sourceBounds then
		prepareDestinationFloor(state, job.sourceBounds)
		job.needs_floor_prep = false
	end

	local entity_count = job.entities and #job.entities or 0
	if entity_count > IMMEDIATE_CLONE_MAX then
		return false
	end

	if entity_count > 0 then
		runBulkClone(sourceSurface, job.entities, state.inside_surface, job.destForce)
		processPendingEntityClones(job.Mythos)
	end

	finishDimensionApply(state, job.sourceState, job.destForce)
	if job.on_complete then job.on_complete() end
	return true
end

local function queueDeferredDimensionApply(Mythos, state, sourceState, destForce, on_complete, opts)
	opts = opts or {}
	local sourceSurface = sourceState.inside_surface
	if not (sourceSurface and sourceSurface.valid) then return false end

	local sourceBounds = resolveSourceBounds(sourceState)
	local job = {
		Mythos               = Mythos,
		state                = state,
		sourceState          = sourceState,
		destForce            = destForce,
		sourceBounds         = sourceBounds,
		entities             = nil,
		cursor               = 1,
		needs_entity_collect = true,
		needs_floor_prep     = sourceBounds ~= nil,
		on_complete          = on_complete,
		prefer_immediate     = opts.immediate == true,
	}
	deferred_apply_jobs[#deferred_apply_jobs + 1] = job

	if job.prefer_immediate and tryCompleteApplyJob(job) then
		table.remove(deferred_apply_jobs, #deferred_apply_jobs)
	end
	return true
end

local function processDeferredFinishes()
	local budget = FINISHES_PER_TICK
	while #deferred_finish_jobs > 0 and budget > 0 do
		local fn = table.remove(deferred_finish_jobs, 1)
		fn()
		budget = budget - 1
	end
end

local function executePlacementIntent(intent)
	if not (intent and intent.entity and intent.entity.valid) then return end

	if intent.kind == "saved_id" then
		MythosClone.cloneFromSavedId(
			intent.Mythos, intent.entity, intent.saved_id, intent.consume
		)
	elseif intent.kind == "entity" then
		local source = intent.source_entity
		if source and source.valid then
			MythosClone.cloneFromEntity(intent.Mythos, source, intent.entity, { immediate = true })
		end
	end
end

local function processPendingClonePlacements()
	local budget = CLONE_PLACEMENTS_PER_TICK
	while #pending_clone_placements > 0 and budget > 0 do
		local intent = table.remove(pending_clone_placements, 1)
		executePlacementIntent(intent)
		budget = budget - 1
	end
end

function MythosClone.processDeferredApplies()
	processDeferredFinishes()
	MythosClone.processPendingSurfaceHides()
	if #pending_clone_placements > 0 then
		processPendingClonePlacements()
		return
	end
	if #deferred_apply_jobs == 0 then return end

	local budget = ENTITIES_PER_TICK
	local i = 1
	while i <= #deferred_apply_jobs and budget > 0 do
		local job = deferred_apply_jobs[i]
		local state = job.state
		if not (state and state.entity and state.entity.valid
				and state.inside_surface and state.inside_surface.valid) then
			table.remove(deferred_apply_jobs, i)
			goto continue
		end

		local sourceSurface = job.sourceState.inside_surface
		if not (sourceSurface and sourceSurface.valid) then
			if job.on_complete then job.on_complete() end
			table.remove(deferred_apply_jobs, i)
			goto continue
		end

		if job.needs_entity_collect then
			job.entities = collectCloneableEntities(sourceSurface)
			job.needs_entity_collect = false
			job.cursor = 1
			if tryCompleteApplyJob(job) then
				table.remove(deferred_apply_jobs, i)
				goto continue
			end
			i = i + 1
			goto continue
		end

		if job.needs_floor_prep then
			prepareDestinationFloor(state, job.sourceBounds)
			job.needs_floor_prep = false
			if tryCompleteApplyJob(job) then
				table.remove(deferred_apply_jobs, i)
				goto continue
			end
			if #job.entities == 0 then
				finishDimensionApply(state, job.sourceState, job.destForce)
				if job.on_complete then job.on_complete() end
				table.remove(deferred_apply_jobs, i)
			else
				i = i + 1
			end
			goto continue
		end

		local batch = {}
		while job.cursor <= #job.entities and budget > 0 do
			local entity = job.entities[job.cursor]
			job.cursor = job.cursor + 1
			budget = budget - 1
			if entity and entity.valid then
				batch[#batch + 1] = entity
			end
		end

		if #batch > 0 then
			runBulkClone(sourceSurface, batch, state.inside_surface, job.destForce)
			processPendingEntityClones(job.Mythos)
		end

		if job.cursor > #job.entities then
			finishDimensionApply(state, job.sourceState, job.destForce)
			if job.on_complete then job.on_complete() end
			table.remove(deferred_apply_jobs, i)
		else
			i = i + 1
		end

		::continue::
	end
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
		clearPlayerContent(inside_surface)
		local outer_surface = destEntity.surface
		if outer_surface and outer_surface.valid then
			inside_surface.solar_power_multiplier = outer_surface.solar_power_multiplier
		end
	else
		local inner_acc
		inside_surface, inner_acc = PocketDimension.create(
			destEntity.unit_number, destEntity.force, destEntity.surface,
			{ defer_remote_view_prep = true, defer_force_hiding = true }
		)
		MythosClone.queueSurfaceHide(inside_surface, destEntity.force)
		state = buildState(Mythos, destEntity, inside_surface, inner_acc)
	end

	registerPlacementShell(state, sourceState, defer_remote_view_prep)
	Registry.set(destEntity.unit_number, state)
	state:syncElectricity()

	return queueDeferredDimensionApply(Mythos, state, sourceState, destEntity.force, function()
		state:connectExistingNeighbours()
	end, opts)
end

local function setPendingPaste(player_index, saved_ids)
	storage.mythos_pending_paste = {
		ids          = saved_ids,
		expires_tick = game.tick + PASTE_TTL,
		player_index = player_index,
	}
end

local function pendingPasteAllowed(event)
	local pending = storage.mythos_pending_paste
	if not pending then return false end
	if game.tick > pending.expires_tick then
		storage.mythos_pending_paste = nil
		return false
	end
	local ids = pending.ids
	if not ids or #ids == 0 then
		storage.mythos_pending_paste = nil
		return false
	end
	local built_by = event and event.player_index
	if pending.player_index and built_by and pending.player_index ~= built_by
			and not isRobotBuiltEvent(event) then
		return false
	end
	return true
end

local function consumePendingPaste(event)
	if not pendingPasteAllowed(event) then return nil end
	return table.remove(storage.mythos_pending_paste.ids, 1)
end

local function discardPendingPasteSlot(event)
	consumePendingPaste(event)
end

function MythosClone.clearPendingPaste(player_index)
	if not storage.mythos_pending_paste then return end
	local pending = storage.mythos_pending_paste
	if not player_index or not pending.player_index or pending.player_index == player_index then
		storage.mythos_pending_paste = nil
	end
end

local function extractPlacementSavedId(Mythos, entity, event)
	local saved_id = Mythos.extractSavedId(event)
	if saved_id then return normalizeSavedId(saved_id), true end

	-- Robot ghost revive and script_raised_revive expose tags on the event.
	if event and event.tags then
		saved_id = readTagSavedId(event.tags)
		if saved_id then return saved_id, false end
	end

	saved_id = readTagSavedId(entity and entity.tags)
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

	MythosClone.cloneFromEntity(Mythos, source, entity, { immediate = true })
	return Registry.get(entity.unit_number) ~= nil
end

local function capturePlacementIntent(Mythos, entity, event)
	if pendingPasteAllowed(event) then
		return {
			kind     = "saved_id",
			Mythos   = Mythos,
			entity   = entity,
			saved_id = consumePendingPaste(event),
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
				kind           = "entity",
				Mythos         = Mythos,
				entity         = entity,
				source_entity  = source,
			}
		end
	end

	return nil
end

local function queueClonePlacement(intent)
	pending_clone_placements[#pending_clone_placements + 1] = intent
end

local function placementNeedsClone(Mythos, entity, event, existing)
	if existing and not needsDeepCopy(existing) then return false end
	if existing and hasDeferredApplyFor(existing) then return false end
	if pendingPasteAllowed(event) then return true end
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
	local paste_saved_id = consumePendingPaste(event)
	if paste_saved_id then
		MythosClone.cloneFromSavedId(Mythos, entity, paste_saved_id, false)
		return
	end

	local saved_id, consume = extractPlacementSavedId(Mythos, entity, event)
	if saved_id then
		MythosClone.cloneFromSavedId(Mythos, entity, saved_id, consume)
		return
	end

	if tryCloneFromPlayerCopySource(Mythos, entity, event) then
		return
	end

	if Registry.get(entity.unit_number) then return end

	finishNormalPlacement(Mythos, entity)
end

function MythosClone.schedulePlacement(Mythos, entity, event)
	local existing = Registry.get(entity.unit_number)
	if existing and not needsDeepCopy(existing) then
		discardPendingPasteSlot(event)
		return
	end

	if existing and hasDeferredApplyFor(existing) then
		return
	end

	local unit_number = entity.unit_number
	if placement_ticks[unit_number] == game.tick then
		return
	end
	placement_ticks[unit_number] = game.tick

	if placementNeedsClone(Mythos, entity, event, existing) then
		local intent = capturePlacementIntent(Mythos, entity, event)
		if intent then
			queueClonePlacement(intent)
			return
		end
	end

	runPlacement(Mythos, entity, event)
end

function MythosClone.cloneFromSavedId(Mythos, entity, saved_id, consume)
	saved_id = normalizeSavedId(saved_id)
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
			queueDeferredFinish(function()
				MythosRestore.finishFromSaved(state, entity, saved)
			end)
			return
		end
		local sourceState = resolveLazySourceState(saved)
		if sourceState and cloneToEntity(Mythos, entity, sourceState, nil) then
			return
		end
		finishNormalPlacement(Mythos, entity)
		return
	end

	local sourceState = sourceStateFromSaved(saved)
	if not sourceState or not cloneToEntity(Mythos, entity, sourceState, nil) then
		finishNormalPlacement(Mythos, entity)
	end
end

function MythosClone.snapshotForBlueprint(Mythos, sourceEntity)
	local sourceState = resolveSourceState(sourceEntity)
	if not sourceState then return nil end

	storage.mythos_next_snapshot_id = (storage.mythos_next_snapshot_id or 0) + 1
	local saved_id = storage.mythos_next_snapshot_id

	local floor_bounds = sourceState.floor_bounds
	if not floor_bounds and sourceState.inside_surface and sourceState.inside_surface.valid then
		floor_bounds = PocketDimension.inferFloorBounds(sourceState.inside_surface)
	end

	storage.saved_dimensions = storage.saved_dimensions or {}
	storage.saved_dimensions[saved_id] = {
		source_unit_number = sourceEntity.unit_number,
		floor_bounds       = floor_bounds,
		custom_icons       = sourceState.custom_icons,
		default_width      = sourceState.default_width,
		default_height     = sourceState.default_height,
		items              = {},
	}
	return saved_id
end

function MythosClone.queueSurfaceHide(surface, skip_force)
	if not (surface and surface.valid) then return end
	for _, force in pairs(game.forces) do
		if force ~= skip_force then
			pending_surface_hides[#pending_surface_hides + 1] = {
				surface = surface,
				force   = force,
			}
		end
	end
end

function MythosClone.processPendingSurfaceHides()
	local budget = SURFACE_HIDES_PER_TICK
	while #pending_surface_hides > 0 and budget > 0 do
		local job = table.remove(pending_surface_hides, 1)
		if job.surface and job.surface.valid and job.force then
			job.force.set_surface_hidden(job.surface, true)
		end
		budget = budget - 1
	end
end

function MythosClone.cloneFromEntity(Mythos, sourceEntity, destEntity, opts)
	if not (destEntity and destEntity.valid) then return end

	local sourceState = resolveSourceState(sourceEntity)
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

local function resolveWritableBlueprint(event)
	local player = event.player_index and game.get_player(event.player_index)
	if player then
		if player.blueprint_to_setup and player.blueprint_to_setup.valid_for_read then
			return player.blueprint_to_setup
		end
		if player.cursor_stack and player.cursor_stack.valid_for_read then
			return player.cursor_stack
		end
	end
	if event.stack and event.stack.valid_for_read then
		return event.stack
	end
	return event.record
end

local function getBlueprintEntities(bp)
	if not bp then return nil end
	if bp.get_blueprint_entities then
		local ok, entities = pcall(function() return bp.get_blueprint_entities() end)
		if ok and entities then return entities end
	end
	return nil
end

local function tagBlueprintEntity(bp, entity_number, saved_id)
	if not (bp and entity_number and saved_id) then return false end
	if bp.set_blueprint_entity_tag then
		bp.set_blueprint_entity_tag(entity_number, "mythos_snapshot", saved_id)
		bp.set_blueprint_entity_tag(entity_number, "saved_id", saved_id)
		return true
	end
	return false
end

local function tagBlueprintEntitiesFallback(bp, entities, entries, mapping)
	if not (bp and entities and entries) then return end

	local by_source = {}
	for _, entry in ipairs(entries) do
		if entry.source and entry.saved_id then
			by_source[entry.source.unit_number] = entry.saved_id
		end
	end

	local changed = false
	for _, bp_entity in pairs(entities) do
		if bp_entity.name ~= "mythos" then goto continue end

		local saved_id
		if mapping then
			local source = mapping[bp_entity.entity_number]
			if source and source.valid then
				saved_id = by_source[source.unit_number]
			end
		end
		if not saved_id then
			for _, entry in ipairs(entries) do
				if entry.index == bp_entity.entity_number then
					saved_id = entry.saved_id
					break
				end
			end
		end
		if saved_id then
			bp_entity.tags = bp_entity.tags or {}
			bp_entity.tags.mythos_snapshot = saved_id
			bp_entity.tags.saved_id = saved_id
			changed = true
		end

		::continue::
	end

	if changed and bp.set_blueprint_entities then
		bp.set_blueprint_entities(entities)
	end
end

local function applyBlueprintSnapshotTags(event, entries)
	local bp = resolveWritableBlueprint(event)
	if not bp then return end

	local entities = getBlueprintEntities(bp)
	if not entities then return end

	local mapping
	if event.mapping and event.mapping.valid then
		local ok, map = pcall(function() return event.mapping.get() end)
		if ok then mapping = map end
	end

	local tagged = false
	if mapping and bp.set_blueprint_entity_tag then
		for _, bp_entity in pairs(entities) do
			if bp_entity.name ~= "mythos" then goto continue end
			local source = mapping[bp_entity.entity_number]
			if not (source and source.valid) then goto continue end
			for _, entry in ipairs(entries) do
				if entry.source == source and entry.saved_id then
					if tagBlueprintEntity(bp, bp_entity.entity_number, entry.saved_id) then
						tagged = true
					end
					break
				end
			end
			::continue::
		end
	end

	if not tagged then
		tagBlueprintEntitiesFallback(bp, entities, entries, mapping)
	end
end

local function collectBlueprintMythosSources(event)
	local entries = {}
	local seen = {}

	local function add(index, source)
		if not (source and source.valid and source.name == "mythos") then return end
		if seen[source.unit_number] then return end
		seen[source.unit_number] = true
		entries[#entries + 1] = { index = index, source = source }
	end

	local mapping = event.mapping
	if mapping and mapping.valid then
		local ok, map = pcall(function() return mapping.get() end)
		if ok and map then
			for bp_index, source in pairs(map) do
				add(bp_index, source)
			end
		end
	end

	if #entries == 0 and event.surface and event.surface.valid and event.area then
		local area = event.area
		local found = event.surface.find_entities_filtered{
			name = "mythos",
			area = {
				{ area.left_top.x, area.left_top.y },
				{ area.right_bottom.x, area.right_bottom.y },
			},
		}
		for i, source in ipairs(found) do
			add(i, source)
		end
	end

	return entries
end

function MythosClone.install(Mythos)
	function Mythos.onEntityCloned(event)
		local source = event.source
		local dest = event.destination
		if not (source and source.valid and dest and dest.valid) then return end
		if source.name ~= "mythos" or dest.name ~= "mythos" then return end

		if isBulkCloning() then
			pending_entity_clones[#pending_entity_clones + 1] = {
				source = source,
				dest   = dest,
			}
			return
		end

		MythosClone.cloneFromEntity(Mythos, source, dest)
	end

	function Mythos.onEntitySettingsPasted(event)
		local source = event.source
		local dest = event.destination
		if not (source and source.valid and dest and dest.valid) then return end
		if source.name ~= "mythos" or dest.name ~= "mythos" then return end

		MythosClone.cloneFromEntity(Mythos, source, dest, { immediate = true })
	end

	function Mythos.onPlayerSetupBlueprint(event)
		local entries = collectBlueprintMythosSources(event)
		if #entries == 0 then return end

		table.sort(entries, function(a, b)
			return a.index < b.index
		end)

		local snapshot_by_source = {}
		local saved_ids = {}
		for _, entry in ipairs(entries) do
			local unit_number = entry.source.unit_number
			local saved_id = snapshot_by_source[unit_number]
			if not saved_id then
				saved_id = MythosClone.snapshotForBlueprint(Mythos, entry.source)
				if saved_id then
					snapshot_by_source[unit_number] = saved_id
				end
			end
			entry.saved_id = saved_id
			if saved_id then
				saved_ids[#saved_ids + 1] = saved_id
			end
		end
		if #saved_ids == 0 then return end

		setPendingPaste(event.player_index, saved_ids)
		applyBlueprintSnapshotTags(event, entries)
	end

	function Mythos.processDeferredClones()
		MythosClone.processDeferredApplies()
	end
end

return MythosClone
