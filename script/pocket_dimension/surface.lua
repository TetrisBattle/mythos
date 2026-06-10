local constants = require("script.pocket_dimension.constants")
local floor     = require("script.pocket_dimension.floor")
local util      = require("script.util")

local function isFloorTile(x, y, bounds)
	return x >= bounds.x_min and x <= bounds.x_max
		and y >= bounds.y_min and y <= bounds.y_max
end

-- Stops infinite surfaces from filling new chunks with grass when touched.
local function suppressTerrainGeneration(surface)
	local mgs = surface.map_gen_settings
	mgs.default_enable_all_autoplace_controls = false
	mgs.autoplace_controls = {}
	local props = {}
	for key, value in pairs(mgs.property_expression_names or {}) do
		props[key] = value
	end
	props["elevation"] = -1000000
	props["moisture"]  = -1000000
	mgs.property_expression_names = props
	surface.map_gen_settings = mgs
end

local function chunkRange(bounds, margin)
	margin = margin or constants.CHUNK_MARGIN
	return
		math.floor(bounds.x_min / constants.CHUNK_SIZE) - margin,
		math.floor(bounds.x_max / constants.CHUNK_SIZE) + margin,
		math.floor(bounds.y_min / constants.CHUNK_SIZE) - margin,
		math.floor(bounds.y_max / constants.CHUNK_SIZE) + margin
end

local function applyVoidTiles(surface, voidTiles)
	if #voidTiles == 0 then return end
	surface.set_tiles(voidTiles)
	for _, tile in ipairs(voidTiles) do
		local pos = tile.position
		surface.set_hidden_tile({ pos[1], pos[2] }, "water")
	end
end

local function collectVoidTilesInRect(surface, bounds, x_min, x_max, y_min, y_max, voidTiles, voidKeys)
	local function queueVoidTile(x, y)
		local key = x .. "," .. y
		if voidKeys[key] or isFloorTile(x, y, bounds) then return end
		voidKeys[key] = true
		voidTiles[#voidTiles + 1] = { name = "out-of-map", position = { x, y } }
	end

	for x = x_min, x_max do
		for y = y_min, y_max do
			queueVoidTile(x, y)
		end
	end

	for _, tile in pairs(surface.find_tiles_filtered{
		area = { { x_min, y_min }, { x_max + 1, y_max + 1 } },
	}) do
		local tx = math.floor(tile.position.x)
		local ty = math.floor(tile.position.y)
		if tx >= x_min and tx <= x_max and ty >= y_min and ty <= y_max
				and tile.name ~= "out-of-map" then
			queueVoidTile(tx, ty)
		end
	end
end

-- Fills void outside the floor with out-of-map + a hidden water overlay.
local function ensureHiddenVoid(surface, bounds)
	local cx_min, cx_max, cy_min, cy_max = chunkRange(bounds)
	local voidTiles = {}
	local voidKeys = {}

	for cx = cx_min, cx_max do
		for cy = cy_min, cy_max do
			local x_min = cx * constants.CHUNK_SIZE
			local x_max = x_min + constants.CHUNK_SIZE - 1
			local y_min = cy * constants.CHUNK_SIZE
			local y_max = y_min + constants.CHUNK_SIZE - 1
			collectVoidTilesInRect(surface, bounds, x_min, x_max, y_min, y_max, voidTiles, voidKeys)
		end
	end

	applyVoidTiles(surface, voidTiles)
end

-- Called from on_chunk_generated so freshly generated chunks never keep grass.
local function voidFillGeneratedChunk(surface, bounds, area)
	local x_min = math.floor(area.left_top.x)
	local y_min = math.floor(area.left_top.y)
	local x_max = math.floor(area.right_bottom.x) - 1
	local y_max = math.floor(area.right_bottom.y) - 1
	local voidTiles = {}
	local voidKeys = {}
	collectVoidTilesInRect(surface, bounds, x_min, x_max, y_min, y_max, voidTiles, voidKeys)
	applyVoidTiles(surface, voidTiles)
end

-- Marks chunks as generated so remote-view does not show raw black void.
-- Must run only after out-of-map tiles are in place, otherwise the engine
-- fills untouched chunks with default grass.
local function ensureChunksGenerated(surface, bounds)
	local cx_min, cx_max, cy_min, cy_max = chunkRange(bounds)
	for cx = cx_min, cx_max do
		for cy = cy_min, cy_max do
			surface.set_chunk_generated_status(
				{ cx, cy },
				defines.chunk_generated_status.entities
			)
		end
	end
end

local function syncInfrastructure(surface, bounds)
	local cx, cy = floor.floorCentre(bounds)
	local pos = { cx, cy }
	for name in pairs(util.REMOTE_VIEW_ENTITY_NAMES) do
		for _, entity in pairs(surface.find_entities_filtered{ name = name }) do
			if entity.valid then entity.teleport(pos) end
		end
	end
	return cx, cy
end

-- Keeps void shell, chunk status, and hidden radar/pole centred after resize.
local function ensureRemoteViewReady(surface, bounds, _)
	suppressTerrainGeneration(surface)
	ensureHiddenVoid(surface, bounds)
	ensureChunksGenerated(surface, bounds)
	return syncInfrastructure(surface, bounds)
end

-- Creates the pocket-dimension surface for one mythos entity.
-- Default floor: 20x20 tiles (top-left anchored; grows down and right).
-- outer_surface: the LuaSurface the mythos is placed on; used to copy the
-- solar multiplier so solar panels inside match the planet the mythos is on.
-- Returns: surface, inner_acc
local function create(unit_number, force, outer_surface, opts)
	opts = opts or {}
	---@diagnostic disable-next-line: missing-fields
	local mapGenSettings = { default_enable_all_autoplace_controls = false, width = 0, height = 0 }
	local surface = game.create_surface(
		"mythos-dimension-" .. unit_number,
		mapGenSettings
	)

	-- Hide this surface from the map surface selector.
	-- set_surface_hidden is per-force; clone placement defers other forces.
	if opts.defer_force_hiding and force then
		force.set_surface_hidden(surface, true)
	else
		for _, f in pairs(game.forces) do
			f.set_surface_hidden(surface, true)
		end
	end
	suppressTerrainGeneration(surface)

	-- Keep the pocket dimension permanently at full daylight brightness.
	surface.daytime       = 0.5
	surface.freeze_daytime = true

	-- Floor
	local tiles = {}
	for x = constants.DEFAULT_FLOOR_BOUNDS.x_min, constants.DEFAULT_FLOOR_BOUNDS.x_max do
		for y = constants.DEFAULT_FLOOR_BOUNDS.y_min, constants.DEFAULT_FLOOR_BOUNDS.y_max do
			tiles[#tiles + 1] = { name = constants.FLOOR_TILE, position = { x, y } }
		end
	end
	surface.set_tiles(tiles)
	if not opts.defer_remote_view_prep then
		ensureRemoteViewReady(surface, constants.DEFAULT_FLOOR_BOUNDS, force)
	end

	local cx, cy = floor.floorCentre(constants.DEFAULT_FLOOR_BOUNDS)
	local centre = { cx, cy }

	-- Hidden radar so the interior is revealed when remote-viewing.
	local radar = surface.create_entity{
		name        = "mythos-hidden-radar",
		position    = centre,
		force       = force,
		raise_built = false,
	}
	if radar then radar.destructible = false end

	-- Sync solar output to the planet the mythos is placed on.
	-- Solar panels inside will produce power proportional to the outer
	-- surface's solar_power_multiplier (e.g., Aquilo gets ~30% of Nauvis).
	-- The dimension is kept at noon (daytime = 0.5) so solar panels always
	-- run at their full fraction without a day/night cycle.
	if outer_surface and outer_surface.valid then
		surface.solar_power_multiplier = outer_surface.solar_power_multiplier
	end

	-- Hidden electric pole: creates the electric network from the floor centre.
	-- Without this, the inner accumulator has no network to distribute into.
	local hub_pole = surface.create_entity{
		name        = "mythos-power-hub-pole",
		position    = centre,
		force       = force,
		raise_built = false,
	}
	if hub_pole then hub_pole.destructible = false end

	-- Inner power accumulator: joins the hub pole's network and acts as the
	-- battery that the script fills from the outer-surface accumulator.
	local inner_acc = surface.create_entity{
		name        = "mythos-power-link-inner",
		position    = centre,
		force       = force,
		raise_built = false,
	}
	if inner_acc then inner_acc.destructible = false end

	return surface, inner_acc
end

return {
	create                 = create,
	syncInfrastructure     = syncInfrastructure,
	ensureRemoteViewReady  = ensureRemoteViewReady,
	voidFillGeneratedChunk = voidFillGeneratedChunk,
}
