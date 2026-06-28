local test = require("tests.lua_test")
local floor = require("script.pocket_dimension.floor")
local constants = require("script.pocket_dimension.constants")

local function makeSurface(opts)
	opts = opts or {}
	local surface = {
		set_tiles_calls = {},
		hidden_tiles = {},
		tiles = opts.tiles or {},
		blocked = opts.blocked or {},
	}

	function surface.find_tiles_filtered(filter)
		local out = {}
		for _, tile in ipairs(surface.tiles) do
			if not filter.name or tile.name == filter.name then
				out[#out + 1] = tile
			end
		end
		return out
	end

	function surface.set_tiles(tiles)
		surface.set_tiles_calls[#surface.set_tiles_calls + 1] = tiles
	end

	function surface.set_hidden_tile(pos, name)
		surface.hidden_tiles[#surface.hidden_tiles + 1] = { pos = pos, name = name }
	end

	function surface.find_entities_filtered(filter)
		local leftTop = filter.area[1]
		local key = leftTop[1] .. "," .. leftTop[2]
		if surface.blocked[key] then
			return { { valid = true, name = surface.blocked[key] } }
		end
		return {}
	end

	return surface
end

test.test("normalizeSize floors numeric input and enforces minimums", function()
	test.assertEquals(floor.normalizeSize("12.9", 10), 12)
	test.assertEquals(floor.normalizeSize("bad", 10), 10)
	test.assertEquals(floor.normalizeSize(4, 10), 10)
end)

test.test("floorCentre returns the center of inclusive tile bounds", function()
	local x, y = floor.floorCentre({ x_min = 0, x_max = 19, y_min = 0, y_max = 19 })
	test.assertEquals(x, 10)
	test.assertEquals(y, 10)
end)

test.test("inferFloorBounds scans floor tile positions", function()
	local surface = makeSurface({
		tiles = {
			{ name = constants.FLOOR_TILE, position = { x = 3.5, y = 5.5 } },
			{ name = constants.FLOOR_TILE, position = { x = 7.5, y = 2.5 } },
			{ name = "grass", position = { x = 99.5, y = 99.5 } },
		},
	})

	test.assertDeepEquals(floor.inferFloorBounds(surface), {
		x_min = 3,
		x_max = 7,
		y_min = 2,
		y_max = 5,
	})
end)

test.test("inferFloorBounds falls back to default bounds when no floor exists", function()
	local bounds = floor.inferFloorBounds(makeSurface())
	test.assertDeepEquals(bounds, constants.DEFAULT_FLOOR_BOUNDS)
end)

test.test("expandEdge adds the requested edge tiles and returns updated bounds", function()
	local surface = makeSurface()
	local result = floor.expandEdge(surface, { x_min = 0, x_max = 1, y_min = 0, y_max = 1 }, "right", nil, 2)

	test.assertDeepEquals(result, { x_min = 0, x_max = 3, y_min = 0, y_max = 1 })
	test.assertDeepEquals(surface.set_tiles_calls[1], {
		{ name = constants.FLOOR_TILE, position = { 2, 0 } },
		{ name = constants.FLOOR_TILE, position = { 2, 1 } },
		{ name = constants.FLOOR_TILE, position = { 3, 0 } },
		{ name = constants.FLOOR_TILE, position = { 3, 1 } },
	})
end)

test.test("contractEdge removes only unblocked right edge tiles down to the minimum width", function()
	local surface = makeSurface()
	local result = floor.contractEdge(surface, { x_min = 0, x_max = 11, y_min = 0, y_max = 1 }, "right", nil, 4)

	test.assertDeepEquals(result, { x_min = 0, x_max = 9, y_min = 0, y_max = 1 })
	test.assertDeepEquals(surface.set_tiles_calls[1], {
		{ name = "out-of-map", position = { 11, 0 } },
		{ name = "out-of-map", position = { 11, 1 } },
		{ name = "out-of-map", position = { 10, 0 } },
		{ name = "out-of-map", position = { 10, 1 } },
	})
	test.assertEquals(#surface.hidden_tiles, 4)
end)

test.test("contractEdge reports blocked tiles before mutating floor tiles", function()
	local surface = makeSurface({ blocked = { ["11,1"] = "assembling-machine-1" } })
	local result, reason = floor.contractEdge(surface, { x_min = 0, x_max = 11, y_min = 0, y_max = 1 }, "right", nil, 2)

	test.assertEquals(result, nil)
	test.assertEquals(reason, "blocked")
	test.assertEquals(#surface.set_tiles_calls, 0)
end)
