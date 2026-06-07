local DEFAULT_WIDTH  = 32
local DEFAULT_HEIGHT = 16
local DEFAULT_Y_MAX  = DEFAULT_WIDTH - 1
local DEFAULT_Y_MIN  = DEFAULT_Y_MAX - DEFAULT_HEIGHT + 1
local DEFAULT_FLOOR_BOUNDS = {
	x_min = 0,
	x_max = DEFAULT_WIDTH - 1,
	y_min = DEFAULT_Y_MIN,
	y_max = DEFAULT_Y_MAX,
}
local VIEW_X = DEFAULT_WIDTH / 2
local VIEW_Y = (DEFAULT_Y_MIN + DEFAULT_Y_MAX) / 2

local GATES_PER_SIDE = 4

-- GATES_PER_SIDE consecutive floor-tile indices clustered in the wall centre.
local function gateCoordsAlong(min_coord, max_coord)
	local span = max_coord - min_coord + 1
	local start = min_coord + math.floor((span - GATES_PER_SIDE) / 2)
	local coords = {}
	for i = 0, GATES_PER_SIDE - 1 do
		coords[i + 1] = start + i
	end
	return coords
end

local function allGateCoordsFit(min_coord, max_coord)
	for _, c in ipairs(gateCoordsAlong(min_coord, max_coord)) do
		if c < min_coord or c > max_coord then return false end
	end
	return true
end

local function floorCentre(bounds)
	return (bounds.x_min + bounds.x_max + 1) / 2,
		(bounds.y_min + bounds.y_max + 1) / 2
end

local CHUNK_SIZE    = 32
local CHUNK_MARGIN  = 2   -- whole chunks of void kept around the floor
local FLOOR_TILE    = "lab-dark-2"

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
	margin = margin or CHUNK_MARGIN
	return
		math.floor(bounds.x_min / CHUNK_SIZE) - margin,
		math.floor(bounds.x_max / CHUNK_SIZE) + margin,
		math.floor(bounds.y_min / CHUNK_SIZE) - margin,
		math.floor(bounds.y_max / CHUNK_SIZE) + margin
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
			local x_min = cx * CHUNK_SIZE
			local x_max = x_min + CHUNK_SIZE - 1
			local y_min = cy * CHUNK_SIZE
			local y_max = y_min + CHUNK_SIZE - 1
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
	local cx, cy = floorCentre(bounds)
	local pos = { cx, cy }
	for _, name in ipairs{
		"mythos-hidden-radar",
		"mythos-power-hub-pole",
		"mythos-power-link-inner",
	} do
		for _, e in pairs(surface.find_entities_filtered{ name = name }) do
			if e.valid then e.teleport(pos) end
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

-- Arrow buttons resize in 8-tile steps; typed sizes snap to 2-tile (even) accuracy.
local RESIZE_STEP   = 8
local FLOOR_SNAP    = 2
local MIN_DIMENSION = GATES_PER_SIDE

-- Rounds a typed size up to the nearest even value (minimum MIN_DIMENSION).
local function snapSizeUpEven(size)
	size = math.floor(tonumber(size) or 0)
	if size < MIN_DIMENSION then return MIN_DIMENSION end
	local rem = size % FLOOR_SNAP
	if rem ~= 0 then size = size + (FLOOR_SNAP - rem) end
	return size
end

-- Maps each mythos slot key to the wall-gap position and the gate sprite orientation.
--   pos             : rendering.draw_sprite position (centre of the wall-gap tile).
--   gateOrientation : RealOrientation (0–1) passed to rendering.draw_sprite.
--     The image has its connection at the bottom, so:
--       top wall    → 0    (no rotation,  connection faces south into room)
--       right wall  → 0.25 (90° CW,       connection faces west  into room)
--       bottom wall → 0.5  (180°,         connection faces north into room)
--       left wall   → 0.75 (270° CW,      connection faces east  into room)
-- innerBeltPos: the tile one step inside the floor where the player places their belt.

-- Creates the pocket-dimension surface for one mythos entity.
-- Default floor: 32×16 tiles (full width, bottom-anchored).
-- outer_surface: the LuaSurface the mythos is placed on; used to copy the
-- solar multiplier so solar panels inside match the planet the mythos is on.
-- Returns: surface, inner_acc
local function create(unit_number, force, outer_surface)
	---@diagnostic disable-next-line: missing-fields
	local mapGenSettings = { default_enable_all_autoplace_controls = false, width = 0, height = 0 }
	local surface = game.create_surface(
		"mythos-dimension-" .. unit_number,
		mapGenSettings
	)

	-- Hide this surface from the map surface selector.
	-- set_surface_hidden is per-force, so call it for every force.
	for _, f in pairs(game.forces) do
		f.set_surface_hidden(surface, true)
	end
	suppressTerrainGeneration(surface)

	-- Keep the pocket dimension permanently at full daylight brightness.
	surface.daytime       = 0.5
	surface.freeze_daytime = true

	-- Floor
	local tiles = {}
	for x = DEFAULT_FLOOR_BOUNDS.x_min, DEFAULT_FLOOR_BOUNDS.x_max do
		for y = DEFAULT_FLOOR_BOUNDS.y_min, DEFAULT_FLOOR_BOUNDS.y_max do
			tiles[#tiles + 1] = { name = "lab-dark-2", position = { x, y } }
		end
	end
	surface.set_tiles(tiles)
	ensureRemoteViewReady(surface, DEFAULT_FLOOR_BOUNDS, force)

	local cx, cy = floorCentre(DEFAULT_FLOOR_BOUNDS)
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

-- ── Resize helpers ─────────────────────────────────────────────────────────────

-- Scans floor tiles and returns the axis-aligned bounds table.
local function inferFloorBounds(surface)
	local x_min, x_max, y_min, y_max
	for _, tile in pairs(surface.find_tiles_filtered{ name = FLOOR_TILE }) do
		-- tile.position is the tile centre (n.5); floor yields the tile index.
		local tx = math.floor(tile.position.x)
		local ty = math.floor(tile.position.y)
		x_min = x_min and math.min(x_min, tx) or tx
		x_max = x_max and math.max(x_max, tx) or tx
		y_min = y_min and math.min(y_min, ty) or ty
		y_max = y_max and math.max(y_max, ty) or ty
	end
	if not x_min then
		return {
			x_min = DEFAULT_FLOOR_BOUNDS.x_min,
			x_max = DEFAULT_FLOOR_BOUNDS.x_max,
			y_min = DEFAULT_FLOOR_BOUNDS.y_min,
			y_max = DEFAULT_FLOOR_BOUNDS.y_max,
		}
	end
	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
end

-- Computes gate/belt positions for arbitrary floor bounds.
-- Each wall gets GATES_PER_SIDE adjacent gates centred on that axis.
local function computeSlotBeltLayoutForBounds(x_min, x_max, y_min, y_max)
	local layout = {}
	for i, y in ipairs(gateCoordsAlong(y_min, y_max)) do
		local yc = y + 0.5  -- tile index → tile centre
		layout["left-" .. i] = {
			pos             = { x_min - 0.5, yc },
			innerBeltPos    = { x_min + 0.5, yc },
			gateOrientation = 0.75,
		}
		layout["right-" .. i] = {
			pos             = { x_max + 1.5, yc },
			innerBeltPos    = { x_max + 0.5, yc },
			gateOrientation = 0.25,
		}
	end
	for i, x in ipairs(gateCoordsAlong(x_min, x_max)) do
		local xc = x + 0.5
		layout["top-" .. i] = {
			pos             = { xc, y_min - 0.5 },
			innerBeltPos    = { xc, y_min + 0.5 },
			gateOrientation = 0,
		}
		layout["bottom-" .. i] = {
			pos             = { xc, y_max + 1.5 },
			innerBeltPos    = { xc, y_max + 0.5 },
			gateOrientation = 0.5,
		}
	end
	return layout
end

-- Default layout for new dimensions (derived from default floor bounds).
local slotBeltLayout = computeSlotBeltLayoutForBounds(
	DEFAULT_FLOOR_BOUNDS.x_min, DEFAULT_FLOOR_BOUNDS.x_max,
	DEFAULT_FLOOR_BOUNDS.y_min, DEFAULT_FLOOR_BOUNDS.y_max
)

-- Removes legacy perimeter stone walls (no longer placed on new dimensions).
local function removePerimeterWalls(surface)
	for _, e in pairs(surface.find_entities_filtered{ name = "stone-wall" }) do
		if e.valid then e.destroy{ raise_destroy = false } end
	end
end

-- Expands the floor toward `edge` by `steps` tiles (default 1).
-- Adds the new floor tiles and returns the updated bounds table.
local function expandEdge(surface, bounds, edge, force, steps)
	steps = steps or 1
	if steps < 1 then return bounds end

	local x_min = bounds.x_min
	local x_max = bounds.x_max
	local y_min = bounds.y_min
	local y_max = bounds.y_max

	local newTiles = {}

	if edge == "left" then
		for _ = 1, steps do
			x_min = x_min - 1
			for y = y_min, y_max do
				newTiles[#newTiles + 1] = { name = "lab-dark-2", position = { x_min, y } }
			end
		end
	elseif edge == "right" then
		for _ = 1, steps do
			x_max = x_max + 1
			for y = y_min, y_max do
				newTiles[#newTiles + 1] = { name = "lab-dark-2", position = { x_max, y } }
			end
		end
	elseif edge == "top" then
		for _ = 1, steps do
			y_min = y_min - 1
			for x = x_min, x_max do
				newTiles[#newTiles + 1] = { name = "lab-dark-2", position = { x, y_min } }
			end
		end
	elseif edge == "bottom" then
		for _ = 1, steps do
			y_max = y_max + 1
			for x = x_min, x_max do
				newTiles[#newTiles + 1] = { name = "lab-dark-2", position = { x, y_max } }
			end
		end
	else
		return bounds
	end

	surface.set_tiles(newTiles)
	removePerimeterWalls(surface)

	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
end

-- Hidden infrastructure — not player-placed obstructions.
local CONTRACT_IGNORE = {
	["mythos-hidden-radar"]     = true,
	["mythos-power-hub-pole"]   = true,
	["mythos-power-link-inner"] = true,
	["mythos-hidden-pipe"]      = true,
	["mythos-hidden-heat-pipe"] = true,
}

local function tileBlockedByPlayerEntity(surface, tx, ty)
	local area = { { tx, ty }, { tx + 1, ty + 1 } }
	for _, e in ipairs(surface.find_entities_filtered{ area = area }) do
		if e.valid and not CONTRACT_IGNORE[e.name] then
			return true
		end
	end
	return false
end

-- Reverts floor tiles to the same hidden void used at surface creation.
local function removeFloorTiles(surface, positions)
	local tiles = {}
	for _, pos in ipairs(positions) do
		tiles[#tiles + 1] = { name = "out-of-map", position = pos }
	end
	surface.set_tiles(tiles)
	for _, pos in ipairs(positions) do
		surface.set_hidden_tile({ pos[1], pos[2] }, "water")
	end
end

-- Shrinks the floor from the free edge by `steps` tiles (default 1).
-- "right" removes the rightmost column(s); "top" removes the topmost row(s).
-- Returns nil when the edge cannot shrink further (gate tiles or minimum size).
local function contractEdge(surface, bounds, edge, force, steps)
	steps = steps or 1
	if steps < 1 then return bounds end

	local x_min = bounds.x_min
	local x_max = bounds.x_max
	local y_min = bounds.y_min
	local y_max = bounds.y_max
	local removeTiles = {}

	if edge == "right" then
		local new_x_max = x_max - steps
		local new_width = new_x_max - x_min + 1
		if new_width < MIN_DIMENSION then return nil end
		if not allGateCoordsFit(x_min, new_x_max) then return nil end
		for x = x_max, new_x_max + 1, -1 do
			for y = y_min, y_max do
				removeTiles[#removeTiles + 1] = { x, y }
			end
		end
		x_max = new_x_max
	elseif edge == "top" then
		local new_y_min = y_min + steps
		local new_height = y_max - new_y_min + 1
		if new_height < MIN_DIMENSION then return nil end
		if not allGateCoordsFit(new_y_min, y_max) then return nil end
		for y = y_min, new_y_min - 1 do
			for x = x_min, x_max do
				removeTiles[#removeTiles + 1] = { x, y }
			end
		end
		y_min = new_y_min
	else
		return nil
	end

	for _, pos in ipairs(removeTiles) do
		if tileBlockedByPlayerEntity(surface, pos[1], pos[2]) then
			return nil, "blocked"
		end
	end

	removeFloorTiles(surface, removeTiles)
	removePerimeterWalls(surface)

	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
end

return {
	create                          = create,
	removePerimeterWalls            = removePerimeterWalls,
	DEFAULT_WIDTH                   = DEFAULT_WIDTH,
	DEFAULT_HEIGHT                  = DEFAULT_HEIGHT,
	DEFAULT_FLOOR_BOUNDS            = DEFAULT_FLOOR_BOUNDS,
	VIEW_X                          = VIEW_X,
	VIEW_Y                          = VIEW_Y,
	GATES_PER_SIDE                  = GATES_PER_SIDE,
	RESIZE_STEP                     = RESIZE_STEP,
	MIN_DIMENSION                   = MIN_DIMENSION,
	snapSizeUpEven                  = snapSizeUpEven,
	slotBeltLayout                  = slotBeltLayout,
	computeSlotBeltLayoutForBounds  = computeSlotBeltLayoutForBounds,
	inferFloorBounds                = inferFloorBounds,
	expandEdge                      = expandEdge,
	contractEdge                    = contractEdge,
	floorCentre                     = floorCentre,
	ensureRemoteViewReady           = ensureRemoteViewReady,
	voidFillGeneratedChunk          = voidFillGeneratedChunk,
}
