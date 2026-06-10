local Queue = {}

local ENTITIES_PER_TICK         = 250
local FINISHES_PER_TICK         = 4
local CLONE_PLACEMENTS_PER_TICK = 8
local SURFACE_HIDES_PER_TICK    = 16
-- Copy-paste completes in one shot below this count; larger interiors stream in faster batches.
local IMMEDIATE_CLONE_MAX       = 400

-- Session-only queues; copy-paste work is never resumed after save/load.
local bulk_clone_depth         = 0
local pending_entity_clones    = {}
local deferred_apply_jobs      = {}
local deferred_finish_jobs     = {}
local pending_clone_placements = {}
local pending_surface_hides    = {}
local placement_ticks          = {}
local handlers                 = {}

function Queue.configure(new_handlers)
	handlers = new_handlers or {}
end

function Queue.enterBulkClone()
	bulk_clone_depth = bulk_clone_depth + 1
end

function Queue.exitBulkClone()
	bulk_clone_depth = bulk_clone_depth - 1
end

function Queue.isBulkCloning()
	return bulk_clone_depth > 0
end

function Queue.hasDeferredApplyFor(state)
	for _, job in ipairs(deferred_apply_jobs) do
		if job.state == state then return true end
	end
	return false
end

function Queue.markPlacementTick(unit_number, tick)
	if placement_ticks[unit_number] == tick then
		return false
	end
	placement_ticks[unit_number] = tick
	return true
end

function Queue.queuePendingEntityClone(source, dest)
	pending_entity_clones[#pending_entity_clones + 1] = {
		source = source,
		dest   = dest,
	}
end

local function processPendingEntityClones(Mythos)
	while #pending_entity_clones > 0 do
		local batch = pending_entity_clones
		pending_entity_clones = {}
		for _, pair in ipairs(batch) do
			if pair.source.valid and pair.dest.valid then
				handlers.cloneFromEntity(Mythos, pair.source, pair.dest)
			end
		end
	end
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
		job.entities = handlers.collectCloneableEntities(sourceSurface)
		job.needs_entity_collect = false
		job.cursor = 1
	end

	if job.needs_floor_prep and job.sourceBounds then
		handlers.prepareDestinationFloor(state, job.sourceBounds)
		job.needs_floor_prep = false
	end

	local entity_count = job.entities and #job.entities or 0
	if entity_count > IMMEDIATE_CLONE_MAX then
		return false
	end

	if entity_count > 0 then
		handlers.runBulkClone(sourceSurface, job.entities, state.inside_surface, job.destForce)
		processPendingEntityClones(job.Mythos)
	end

	handlers.finishDimensionApply(state, job.sourceState, job.destForce)
	if job.on_complete then job.on_complete() end
	return true
end

function Queue.queueDeferredDimensionApply(Mythos, state, sourceState, destForce, on_complete, opts)
	opts = opts or {}
	local sourceSurface = sourceState.inside_surface
	if not (sourceSurface and sourceSurface.valid) then return false end

	local sourceBounds = handlers.resolveSourceBounds(sourceState)
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

function Queue.queueDeferredFinish(fn)
	deferred_finish_jobs[#deferred_finish_jobs + 1] = fn
end

local function processDeferredFinishes()
	local budget = FINISHES_PER_TICK
	while #deferred_finish_jobs > 0 and budget > 0 do
		local fn = table.remove(deferred_finish_jobs, 1)
		fn()
		budget = budget - 1
	end
end

function Queue.queueClonePlacement(intent)
	pending_clone_placements[#pending_clone_placements + 1] = intent
end

local function executePlacementIntent(intent)
	if not (intent and intent.entity and intent.entity.valid) then return end

	if intent.kind == "saved_id" then
		handlers.cloneFromSavedId(
			intent.Mythos, intent.entity, intent.saved_id, intent.consume
		)
	elseif intent.kind == "entity" then
		local source = intent.source_entity
		if source and source.valid then
			handlers.cloneFromEntity(intent.Mythos, source, intent.entity, { immediate = true })
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

function Queue.processDeferredApplies()
	processDeferredFinishes()
	Queue.processPendingSurfaceHides()
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
		else
			local sourceSurface = job.sourceState.inside_surface
			if not (sourceSurface and sourceSurface.valid) then
				if job.on_complete then job.on_complete() end
				table.remove(deferred_apply_jobs, i)
			elseif job.needs_entity_collect then
				job.entities = handlers.collectCloneableEntities(sourceSurface)
				job.needs_entity_collect = false
				job.cursor = 1
				if tryCompleteApplyJob(job) then
					table.remove(deferred_apply_jobs, i)
				else
					i = i + 1
				end
			elseif job.needs_floor_prep then
				handlers.prepareDestinationFloor(state, job.sourceBounds)
				job.needs_floor_prep = false
				if tryCompleteApplyJob(job) then
					table.remove(deferred_apply_jobs, i)
				elseif #job.entities == 0 then
					handlers.finishDimensionApply(state, job.sourceState, job.destForce)
					if job.on_complete then job.on_complete() end
					table.remove(deferred_apply_jobs, i)
				else
					i = i + 1
				end
			else
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
					handlers.runBulkClone(sourceSurface, batch, state.inside_surface, job.destForce)
					processPendingEntityClones(job.Mythos)
				end

				if job.cursor > #job.entities then
					handlers.finishDimensionApply(state, job.sourceState, job.destForce)
					if job.on_complete then job.on_complete() end
					table.remove(deferred_apply_jobs, i)
				else
					i = i + 1
				end
			end
		end
	end
end

function Queue.queueSurfaceHide(surface, skip_force)
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

function Queue.processPendingSurfaceHides()
	local budget = SURFACE_HIDES_PER_TICK
	while #pending_surface_hides > 0 and budget > 0 do
		local job = table.remove(pending_surface_hides, 1)
		if job.surface and job.surface.valid and job.force then
			job.force.set_surface_hidden(job.surface, true)
		end
		budget = budget - 1
	end
end

return Queue
