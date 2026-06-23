local PocketDimension = require("script.pocket_dimension.init")
local Connections     = require("script.mythos.connections")
local VirtualChest    = require("script.virtual_chest.init")
local Bridge          = require("script.power.bridge")
local util            = require("script.util")

local MythosRestore = {}

MythosRestore.createOuterAccumulator          = Bridge.createOuterAccumulator
MythosRestore.destroyOuterPowerBridge        = Bridge.destroyOuterPowerBridge
MythosRestore.destroyStrayOuterAccumulators  = Bridge.destroyStrayOuterAccumulators
MythosRestore.createOuterAccumulatorForEntity = Bridge.createOuterAccumulatorForEntity
MythosRestore.ensureHubPole                  = Bridge.ensureHubPole
MythosRestore.ensureOuterPowerBridge         = Bridge.ensureOuterPowerBridge
MythosRestore.destroyStrayInnerAccumulators  = Bridge.destroyStrayInnerAccumulators
MythosRestore.refreshPowerLinks              = Bridge.refreshPowerLinks
MythosRestore.powerLinksNeedRefresh          = Bridge.powerLinksNeedRefresh

local function restoreCustomIcons(state, customIcons)
	if not customIcons then return end
	for idx, signal in pairs(customIcons) do
		state:setIcon(idx, signal)
	end
end

local function normalizeGatePositions(gatePositions)
	return PocketDimension.normalizeDimensionGatePositions(gatePositions)
end

function MythosRestore.fromSaved(Mythos, entity, saved)
	local slots, byExternalPos = Connections.buildSlots(entity.position.x, entity.position.y)
	local outer_acc = Bridge.createOuterAccumulatorForEntity(entity)
	local centre
	if saved.floor_bounds then
		local cx, cy = PocketDimension.floorCentre(saved.floor_bounds)
		centre = { cx, cy }
	end
	local inner_acc = Bridge.findOrCreateInnerAccumulator(saved.surface, entity.force, centre)

	local outer_surface = entity.surface
	if outer_surface and outer_surface.valid and saved.surface.valid then
		saved.surface.solar_power_multiplier = outer_surface.solar_power_multiplier
	end

	local state = setmetatable({
		entity                  = entity,
		slots                   = slots,
		byExternalPos           = byExternalPos,
		inside_surface          = saved.surface,
		pendingDeletions        = {},
		outer_acc               = outer_acc,
		inner_acc               = inner_acc,
		dimension_gate_positions = normalizeGatePositions(saved.dimension_gate_positions),
	}, Mythos)

	if saved.floor_bounds then
		state.floor_bounds = util.copyBounds(saved.floor_bounds)
	else
		state:syncFloorBoundsFromTiles()
	end
	if state.floor_bounds then
		state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
		PocketDimension.syncRemoteViewInfrastructure(
			state.inside_surface, state.floor_bounds, entity.force
		)
	else
		state.inside_x = PocketDimension.VIEW_X
		state.inside_y = PocketDimension.VIEW_Y
	end

	restoreCustomIcons(state, saved.custom_icons)
	state:syncElectricity()

	return state
end

function MythosRestore.finishFromSaved(state, entity, saved)
	if not (state and state.entity and state.entity.valid) then return end
	VirtualChest.insertItems(entity.force, entity.position, saved.items)
	state:syncElectricity()
	state:refreshGateRenders()
	state:connectExistingNeighbours()
end

return MythosRestore
