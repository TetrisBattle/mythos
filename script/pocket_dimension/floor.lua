local constants = require("script.pocket_dimension.constants")
local util = require("script.util")

local function boundsOf(x_min, x_max, y_min, y_max)
	return { x_min = x_min, x_max = x_max, y_min = y_min, y_max = y_max }
end

local function copyDefaultBounds()
	return boundsOf(
		constants.DEFAULT_FLOOR_BOUNDS.x_min,
		constants.DEFAULT_FLOOR_BOUNDS.x_max,
		constants.DEFAULT_FLOOR_BOUNDS.y_min,
		constants.DEFAULT_FLOOR_BOUNDS.y_max
	)
end

local function floorCentre(bounds)
	return (bounds.x_min + bounds.x_max + 1) / 2, (bounds.y_min + bounds.y_max + 1) / 2
end

-- Converts typed size input to a whole tile count and enforces the minimum.
local function normalizeSize(size, minSize)
	size = math.floor(tonumber(size) or 0)
	minSize = minSize or constants.MIN_DIMENSION
	if size < minSize then
		return minSize
	end
	return size
end

-- Scans floor tiles and returns the axis-aligned bounds table.
local function inferFloorBounds(surface)
	local x_min, x_max, y_min, y_max
	local floorTiles = surface.find_tiles_filtered({ name = constants.FLOOR_TILE })
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
		return copyDefaultBounds()
	end
	return boundsOf(x_min, x_max, y_min, y_max)
end

local function queueFloorTile(tiles, x, y)
	tiles[#tiles + 1] = { name = constants.FLOOR_TILE, position = { x, y } }
end

local function queueTilePosition(positions, x, y)
	positions[#positions + 1] = { x, y }
end

local function queueColumn(positions, x, y_min, y_max)
	for y = y_min, y_max do
		queueTilePosition(positions, x, y)
	end
end

local function queueRow(positions, y, x_min, x_max)
	for x = x_min, x_max do
		queueTilePosition(positions, x, y)
	end
end

-- Expands the floor toward `edge` by `steps` tiles (default 1).
-- Adds the new floor tiles and returns the updated bounds table.
local function expandEdge(surface, bounds, edge, _force, steps)
	steps = steps or 1
	if steps < 1 then
		return bounds
	end

	local x_min = bounds.x_min
	local x_max = bounds.x_max
	local y_min = bounds.y_min
	local y_max = bounds.y_max

	local newTiles = {}

	if edge == "left" then
		for _ = 1, steps do
			x_min = x_min - 1
			for y = y_min, y_max do
				queueFloorTile(newTiles, x_min, y)
			end
		end
	elseif edge == "right" then
		for _ = 1, steps do
			x_max = x_max + 1
			for y = y_min, y_max do
				queueFloorTile(newTiles, x_max, y)
			end
		end
	elseif edge == "top" then
		for _ = 1, steps do
			y_min = y_min - 1
			for x = x_min, x_max do
				queueFloorTile(newTiles, x, y_min)
			end
		end
	elseif edge == "bottom" then
		for _ = 1, steps do
			y_max = y_max + 1
			for x = x_min, x_max do
				queueFloorTile(newTiles, x, y_max)
			end
		end
	else
		return bounds
	end

	surface.set_tiles(newTiles)

	return boundsOf(x_min, x_max, y_min, y_max)
end

local function tileBlockedByPlayerEntity(surface, tx, ty)
	local area = { { tx, ty }, { tx + 1, ty + 1 } }
	for _, e in ipairs(surface.find_entities_filtered({ area = area })) do
		if e.valid and not util.isInfrastructureEntityName(e.name) then
			return true
		end
	end
	return false
end

local function columnBlocked(surface, x, y_min, y_max)
	for y = y_min, y_max do
		if tileBlockedByPlayerEntity(surface, x, y) then
			return true
		end
	end
	return false
end

local function rowBlocked(surface, y, x_min, x_max)
	for x = x_min, x_max do
		if tileBlockedByPlayerEntity(surface, x, y) then
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

local function countSafeRightColumns(surface, bounds, steps)
	local safe = 0
	for k = 1, steps do
		if columnBlocked(surface, bounds.x_max - k + 1, bounds.y_min, bounds.y_max) then
			break
		end
		safe = k
	end
	return safe
end

local function countSafeBottomRows(surface, bounds, steps)
	local safe = 0
	for k = 1, steps do
		if rowBlocked(surface, bounds.y_max - k + 1, bounds.x_min, bounds.x_max) then
			break
		end
		safe = k
	end
	return safe
end

local function contractRightEdge(surface, bounds, steps)
	local max_steps = util.floorWidth(bounds) - constants.MIN_DIMENSION_WIDTH
	if max_steps < 1 then
		return nil
	end
	steps = math.min(steps, max_steps)

	local safe = countSafeRightColumns(surface, bounds, steps)
	if safe < 1 then
		return nil, nil, "blocked"
	end

	local removeTiles = {}
	local new_x_max = bounds.x_max - safe
	for x = bounds.x_max, new_x_max + 1, -1 do
		queueColumn(removeTiles, x, bounds.y_min, bounds.y_max)
	end

	return boundsOf(bounds.x_min, new_x_max, bounds.y_min, bounds.y_max), removeTiles
end

local function contractBottomEdge(surface, bounds, steps)
	local max_steps = util.floorHeight(bounds) - constants.MIN_DIMENSION_HEIGHT
	if max_steps < 1 then
		return nil
	end
	steps = math.min(steps, max_steps)

	local safe = countSafeBottomRows(surface, bounds, steps)
	if safe < 1 then
		return nil, nil, "blocked"
	end

	local removeTiles = {}
	local new_y_max = bounds.y_max - safe
	for y = new_y_max + 1, bounds.y_max do
		queueRow(removeTiles, y, bounds.x_min, bounds.x_max)
	end

	return boundsOf(bounds.x_min, bounds.x_max, bounds.y_min, new_y_max), removeTiles
end

-- Shrinks the floor from the free edge by `steps` tiles (default 1).
-- "right" removes the rightmost column(s); "bottom" removes the bottommost row(s).
-- Returns nil when the edge cannot shrink further (minimum size or blocked tiles).
local function contractEdge(surface, bounds, edge, _force, steps)
	steps = steps or 1
	if steps < 1 then
		return bounds
	end

	local newBounds, removeTiles, reason
	if edge == "right" then
		newBounds, removeTiles, reason = contractRightEdge(surface, bounds, steps)
	elseif edge == "bottom" then
		newBounds, removeTiles, reason = contractBottomEdge(surface, bounds, steps)
	else
		return nil
	end

	if not newBounds then
		return nil, reason
	end
	removeFloorTiles(surface, removeTiles)

	return newBounds
end

return {
	floorCentre = floorCentre,
	normalizeSize = normalizeSize,
	inferFloorBounds = inferFloorBounds,
	expandEdge = expandEdge,
	contractEdge = contractEdge,
}
