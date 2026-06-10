local PocketDimension = require("script.pocket_dimension.init")
local Registry        = require("script.mythos.registry")
local util            = require("script.util")

local Bridge = {}

local OUTER_POWER_LINK_TYPE = "accumulator"
local INNER_POWER_LINK_TYPE = "electric-energy-interface"

local function findOrCreateOuterPole(surface, position, force)
	local poles = surface.find_entities_filtered{
		name     = "mythos-power-outer-pole",
		position = position,
	}
	local pole = poles[1]
	if pole and pole.valid then return pole end

	pole = surface.create_entity{
		name        = "mythos-power-outer-pole",
		position    = position,
		force       = force,
		raise_built = false,
	}
	if pole then pole.destructible = false end
	return pole
end

function Bridge.createOuterAccumulator(entity)
	local position = entity.position
	findOrCreateOuterPole(entity.surface, position, entity.force)

	local outer_acc = entity.surface.create_entity{
		name        = "mythos-power-link-outer",
		position    = position,
		force       = entity.force,
		raise_built = false,
	}
	if outer_acc then outer_acc.destructible = false end
	return outer_acc
end

function Bridge.destroyOuterPowerBridge(surface, position)
	if not (surface and surface.valid) then return end
	for _, name in ipairs{ "mythos-power-link-outer", "mythos-power-outer-pole" } do
		local filters = { name = name }
		if position then filters.position = position end
		for _, entity in ipairs(surface.find_entities_filtered(filters)) do
			if entity.valid then entity.destroy() end
		end
	end
end

function Bridge.destroyStrayOuterAccumulators(surface, position)
	Bridge.destroyOuterPowerBridge(surface, position)
end

function Bridge.createOuterAccumulatorForEntity(entity)
	if not (entity and entity.valid) then return nil end
	local parentUnit = util.parseDimensionUnitNumber(entity.surface)
	if parentUnit and Registry.get(parentUnit) then
		-- Nested mythoi must not keep a placement-surface outer link; remove
		-- orphans from older saves that overlap the mythos footprint.
		Bridge.destroyStrayOuterAccumulators(entity.surface, entity.position)
		return nil
	end
	return Bridge.createOuterAccumulator(entity)
end

local function innerAccumulatorPosition(surface, centre)
	if centre then return centre end
	local bounds = PocketDimension.inferFloorBounds(surface)
	local cx, cy = PocketDimension.floorCentre(bounds)
	return { cx, cy }
end

function Bridge.findOrCreateInnerAccumulator(surface, force, centre)
	local inner_accs = surface.find_entities_filtered{ name = "mythos-power-link-inner" }
	local inner_acc = inner_accs[1]
	if inner_acc and inner_acc.valid and inner_acc.type == INNER_POWER_LINK_TYPE then
		return inner_acc
	end

	if inner_acc and inner_acc.valid then inner_acc.destroy() end

	local pos = innerAccumulatorPosition(surface, centre)
	inner_acc = surface.create_entity{
		name        = "mythos-power-link-inner",
		position    = pos,
		force       = force,
		raise_built = false,
	}
	if inner_acc then inner_acc.destructible = false end
	return inner_acc
end

local function recreateHubPole(surface, centre, force)
	for _, pole in ipairs(surface.find_entities_filtered{ name = "mythos-power-hub-pole" }) do
		if pole.valid then pole.destroy() end
	end
	local pole = surface.create_entity{
		name        = "mythos-power-hub-pole",
		position    = centre,
		force       = force,
		raise_built = false,
	}
	if pole then pole.destructible = false end
	return pole
end

function Bridge.ensureHubPole(state)
	if not (state.entity and state.entity.valid
			and state.inside_surface and state.inside_surface.valid
			and state.floor_bounds) then
		return
	end
	local cx, cy = PocketDimension.floorCentre(state.floor_bounds)
	recreateHubPole(state.inside_surface, { cx, cy }, state.entity.force)
end

function Bridge.ensureOuterPowerBridge(entity)
	if not (entity and entity.valid) then return end
	if util.parseDimensionUnitNumber(entity.surface) then return end
	findOrCreateOuterPole(entity.surface, entity.position, entity.force)
end

function Bridge.destroyStrayInnerAccumulators(surface)
	if not (surface and surface.valid) then return end
	local inner_accs = surface.find_entities_filtered{ name = "mythos-power-link-inner" }
	for i = 2, #inner_accs do
		if inner_accs[i].valid then inner_accs[i].destroy() end
	end
end

function Bridge.refreshPowerLinks(state)
	if not (state.entity and state.entity.valid) then return end

	local inner_energy, outer_energy = 0, 0
	if state.inner_acc and state.inner_acc.valid then
		inner_energy = state.inner_acc.energy
		state.inner_acc.destroy()
	end
	state.inner_acc = nil

	if state.outer_acc and state.outer_acc.valid then
		outer_energy = state.outer_acc.energy
		state.outer_acc.destroy()
	end
	state.outer_acc = nil

	state.outer_acc = Bridge.createOuterAccumulatorForEntity(state.entity)
	if state.outer_acc and state.outer_acc.valid then
		state.outer_acc.energy = outer_energy
	end

	if state.inside_surface and state.inside_surface.valid then
		Bridge.destroyStrayInnerAccumulators(state.inside_surface)
		local centre
		if state.floor_bounds then
			local cx, cy = PocketDimension.floorCentre(state.floor_bounds)
			centre = { cx, cy }
		end
		state.inner_acc = Bridge.findOrCreateInnerAccumulator(
			state.inside_surface, state.entity.force, centre
		)
		if state.inner_acc and state.inner_acc.valid then
			state.inner_acc.energy = inner_energy
			if state.inner_acc.type == INNER_POWER_LINK_TYPE then
				state.inner_acc.power_production = inner_energy > 0 and inner_energy or 0
			end
		end
		if state.floor_bounds then
			local cx, cy = PocketDimension.floorCentre(state.floor_bounds)
			recreateHubPole(state.inside_surface, { cx, cy }, state.entity.force)
			PocketDimension.syncRemoteViewInfrastructure(
				state.inside_surface, state.floor_bounds
			)
		end
	end

	state:syncElectricity()
end

function Bridge.powerLinksNeedRefresh(state)
	if not (state and state.entity and state.entity.valid) then return false end

	local expects_outer_link = not util.parseDimensionUnitNumber(state.entity.surface)
	if expects_outer_link then
		if not (state.outer_acc and state.outer_acc.valid) then return true end
		if state.outer_acc.type ~= OUTER_POWER_LINK_TYPE then return true end
	end

	if state.inside_surface and state.inside_surface.valid then
		if not (state.inner_acc and state.inner_acc.valid) then return true end
		if state.inner_acc.type ~= INNER_POWER_LINK_TYPE then return true end
	end

	if state.outer_acc and state.outer_acc.valid and state.outer_acc.type ~= OUTER_POWER_LINK_TYPE then
		return true
	end
	if state.inner_acc and state.inner_acc.valid and state.inner_acc.type ~= INNER_POWER_LINK_TYPE then
		return true
	end
	return false
end

return Bridge
