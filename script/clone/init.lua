local Snapshot  = require("script.clone.snapshot")
local Apply     = require("script.clone.apply")
local Queue     = require("script.clone.queue")
local Blueprint = require("script.clone.blueprint")

local MythosClone = {}

function MythosClone.isBulkCloning()
	return Queue.isBulkCloning()
end

function MythosClone.processDeferredApplies()
	Queue.processDeferredApplies()
end

function MythosClone.clearPendingPaste(player_index)
	Blueprint.clearPendingPaste(player_index)
end

function MythosClone.schedulePlacement(Mythos, entity, event)
	Apply.schedulePlacement(Mythos, entity, event)
end

function MythosClone.cloneFromSavedId(Mythos, entity, saved_id, consume)
	Apply.cloneFromSavedId(Mythos, entity, saved_id, consume)
end

function MythosClone.snapshotForBlueprint(Mythos, sourceEntity)
	return Snapshot.snapshotForBlueprint(Mythos, sourceEntity)
end

function MythosClone.queueSurfaceHide(surface, skip_force)
	Queue.queueSurfaceHide(surface, skip_force)
end

function MythosClone.processPendingSurfaceHides()
	Queue.processPendingSurfaceHides()
end

function MythosClone.cloneFromEntity(Mythos, sourceEntity, destEntity, opts)
	Apply.cloneFromEntity(Mythos, sourceEntity, destEntity, opts)
end

function MythosClone.install(Mythos)
	function Mythos.onEntityCloned(event)
		local source = event.source
		local dest = event.destination
		if not (source and source.valid and dest and dest.valid) then return end
		if source.name ~= "mythos" or dest.name ~= "mythos" then return end

		if Queue.isBulkCloning() then
			Queue.queuePendingEntityClone(source, dest)
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
		Blueprint.onPlayerSetupBlueprint(Mythos, event, MythosClone.snapshotForBlueprint)
	end

	function Mythos.processDeferredClones()
		MythosClone.processDeferredApplies()
	end
end

local queueHandlers = Apply.queueHandlers()
queueHandlers.cloneFromEntity = function(...)
	return MythosClone.cloneFromEntity(...)
end
queueHandlers.cloneFromSavedId = function(...)
	return MythosClone.cloneFromSavedId(...)
end
Queue.configure(queueHandlers)

return MythosClone
