local constants = require("script.pocket_dimension.constants")
local util      = require("script.util")

local function floorCentre(bounds)
	return (bounds.x_min + bounds.x_max + 1) / 2,
		(bounds.y_min + bounds.y_max + 1) / 2
end

-- Rounds a typed size up to the nearest even value.
local function snapSizeUpEven(size, minSize)
	size = math.floor(tonumber(size) or 0)
	minSize = minSize or constants.MIN_DIMENSION
	if size < minSize then return minSize end
	local rem = size % constants.FLOOR_SNAP
	if rem ~= 0 then size = size + (constants.FLOOR_SNAP - rem) end
	return size
end

-- Scans floor tiles and returns the axis-aligned bounds table.
local function inferFloorBounds(surface)
	local x_min, x_max, y_min, y_max
	local floorTiles = surface.find_tiles_filtered{ name = constants.FLOOR_TILE }
	for _, tile in pairs(floorTiles) do
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
			x_min = constants.DEFAULT_FLOOR_BOUNDS.x_min,
			x_max = constants.DEFAULT_FLOOR_BOUNDS.x_max,
			y_min = constants.DEFAULT_FLOOR_BOUNDS.y_min,
			y_max = constants.DEFAULT_FLOOR_BOUNDS.y_max,
		}
	end
	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
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
				newTiles[#newTiles + 1] = { name = constants.FLOOR_TILE, position = { x_min, y } }
			end
		end
	elseif edge == "right" then
		for _ = 1, steps do
			x_max = x_max + 1
			for y = y_min, y_max do
				newTiles[#newTiles + 1] = { name = constants.FLOOR_TILE, position = { x_max, y } }
			end
		end
	elseif edge == "top" then
		for _ = 1, steps do
			y_min = y_min - 1
			for x = x_min, x_max do
				newTiles[#newTiles + 1] = { name = constants.FLOOR_TILE, position = { x, y_min } }
			end
		end
	elseif edge == "bottom" then
		for _ = 1, steps do
			y_max = y_max + 1
			for x = x_min, x_max do
				newTiles[#newTiles + 1] = { name = constants.FLOOR_TILE, position = { x, y_max } }
			end
		end
	else
		return bounds
	end

	surface.set_tiles(newTiles)

	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
end

local function tileBlockedByPlayerEntity(surface, tx, ty)
	local area = { { tx, ty }, { tx + 1, ty + 1 } }
	for _, e in ipairs(surface.find_entities_filtered{ area = area }) do
		if e.valid and not util.isInfrastructureEntityName(e.name) then
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
-- "right" removes the rightmost column(s); "bottom" removes the bottommost row(s).
-- Returns nil when the edge cannot shrink further (minimum size or blocked tiles).
local function contractEdge(surface, bounds, edge, force, steps)
	steps = steps or 1
	if steps < 1 then return bounds end

	local x_min = bounds.x_min
	local x_max = bounds.x_max
	local y_min = bounds.y_min
	local y_max = bounds.y_max
	local removeTiles = {}

	if edge == "right" then
		local max_steps = x_max - x_min + 1 - constants.MIN_DIMENSION_WIDTH
		if max_steps < 1 then return nil end
		steps = math.min(steps, max_steps)
		local new_x_max = x_max - steps
		for x = x_max, new_x_max + 1, -1 do
			for y = y_min, y_max do
				removeTiles[#removeTiles + 1] = { x, y }
			end
		end
		x_max = new_x_max
	elseif edge == "bottom" then
		local max_steps = y_max - y_min + 1 - constants.MIN_DIMENSION_HEIGHT
		if max_steps < 1 then return nil end
		steps = math.min(steps, max_steps)
		local new_y_max = y_max - steps
		for y = new_y_max + 1, y_max do
			for x = x_min, x_max do
				removeTiles[#removeTiles + 1] = { x, y }
			end
		end
		y_max = new_y_max
	else
		return nil
	end

	for _, pos in ipairs(removeTiles) do
		if tileBlockedByPlayerEntity(surface, pos[1], pos[2]) then
			return nil, "blocked"
		end
	end

	removeFloorTiles(surface, removeTiles)

	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
end

return {
	floorCentre          = floorCentre,
	snapSizeUpEven      = snapSizeUpEven,
	inferFloorBounds    = inferFloorBounds,
	expandEdge          = expandEdge,
	contractEdge        = contractEdge,
}
