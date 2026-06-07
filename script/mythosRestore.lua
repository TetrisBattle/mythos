local PocketDimension = require("script.PocketDimension")
local Connections     = require("script.connections")
local MythosInventory = require("script.mythosInventory")

local MythosRestore = {}

function MythosRestore.createOuterAccumulator(entity)
	local outer_acc = entity.surface.create_entity{
		name        = "mythos-power-link-outer",
		position    = entity.position,
		force       = entity.force,
		raise_built = false,
	}
	if outer_acc then outer_acc.destructible = false end
	return outer_acc
end

local function findOrCreateInnerAccumulator(surface, force)
	local inner_accs = surface.find_entities_filtered{ name = "mythos-power-link-inner" }
	local inner_acc = inner_accs[1]
	if inner_acc then return inner_acc end

	inner_acc = surface.create_entity{
		name        = "mythos-power-link-inner",
		position    = { PocketDimension.VIEW_X, PocketDimension.VIEW_Y },
		force       = force,
		raise_built = false,
	}
	if inner_acc then inner_acc.destructible = false end
	return inner_acc
end

local function restoreCustomIcons(state, customIcons)
	if not customIcons then return end
	for idx, signal in pairs(customIcons) do
		state:setIcon(idx, signal)
	end
end

function MythosRestore.fromSaved(Mythos, entity, saved)
	local slots, byExternalPos = Connections.buildSlots(entity.position.x, entity.position.y)
	local outer_acc = MythosRestore.createOuterAccumulator(entity)
	local inner_acc = findOrCreateInnerAccumulator(saved.surface, entity.force)

	local outer_surface = entity.surface
	if outer_surface and outer_surface.valid and saved.surface.valid then
		saved.surface.solar_power_multiplier = outer_surface.solar_power_multiplier
	end

	local state = setmetatable({
		entity           = entity,
		slots            = slots,
		byExternalPos    = byExternalPos,
		inside_surface   = saved.surface,
		pendingDeletions = {},
		outer_acc        = outer_acc,
		inner_acc        = inner_acc,
	}, Mythos)

	state:syncFloorBoundsFromTiles()
	if state.floor_bounds then
		state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
		PocketDimension.ensureRemoteViewReady(
			state.inside_surface, state.floor_bounds, entity.force
		)
	else
		state.inside_x = PocketDimension.VIEW_X
		state.inside_y = PocketDimension.VIEW_Y
	end
	state:refreshGateRenders()

	MythosInventory.insertItems(entity.force, entity.position, saved.items)
	restoreCustomIcons(state, saved.custom_icons)

	return state
end

return MythosRestore
