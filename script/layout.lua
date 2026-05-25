local north = defines.direction.north
local east = defines.direction.east
local south = defines.direction.south
local west = defines.direction.west

local opposite = {[north] = south, [east] = west, [south] = north, [west] = east}
local DX = {[north] = 0, [east] = 1, [south] = 0, [west] = -1}
local DY = {[north] = -1, [east] = 0, [south] = 1, [west] = 0}

local make_connection = function(id, outside_x, outside_y, inside_x, inside_y, direction_out)
    return {
        id = id,
        outside_x = outside_x,
        outside_y = outside_y,
        inside_x = inside_x,
        inside_y = inside_y,
        indicator_dx = DX[direction_out],
        indicator_dy = DY[direction_out],
        direction_in = opposite[direction_out],
        direction_out = direction_out,
    }
end

local make_quality_connection = function(id, outside_x, outside_y, inside_x, inside_y, direction_out, quality)
    local connection = make_connection(id, outside_x, outside_y, inside_x, inside_y, direction_out)
    connection.quality = quality
    return connection
end

local layout_generators = {
    ["factory-1"] = {
        name = "factory-1",
        tier = 1,
        inside_size = 30,
        outside_size = 8,
        inside_door_x = 0,
        inside_door_y = 16,
        outside_door_x = 0,
        outside_door_y = 4,
        outside_energy_receiver_type = "factory-power-input-8",
        inside_energy_x = -4,
        inside_energy_y = 17,
        overlay_x = 0,
        overlay_y = 3,
        rectangles = {
            {
                x1 = -16, x2 = 16, y1 = -16, y2 = 16, tile = "factory-wall-1"
            },
            {
                x1 = -15, x2 = 15, y1 = -15, y2 = 15, tile = "factory-floor"
            },
            {
                x1 = -3, x2 = 3, y1 = 15, y2 = 18, tile = "factory-wall-1"
            },
            {
                x1 = -2, x2 = 2, y1 = 15, y2 = 18, tile = "factory-entrance"
            },
        },
        mosaics = {
            {
                x1 = -6,
                x2 = 6,
                y1 = -4,
                y2 = 4,
                tile = "factory-pattern-1",
                pattern = {
                    " ++++    ++ ",
                    "++  ++  +++ ",
                    "++  ++ + ++ ",
                    "++ +++   ++ ",
                    "+++ ++   ++ ",
                    "++  ++   ++ ",
                    "++  ++   ++ ",
                    " ++++  +++++",
                }
            },
        },
        connection_tile = "factory-floor",
        connections = {
            w1 = make_connection("w1", -4.5, -2.5, -15.5, -9.5, west),
            w2 = make_connection("w2", -4.5, -1.5, -15.5, -5.5, west),
            w3 = make_connection("w3", -4.5, 1.5, -15.5, 5.5, west),
            w4 = make_connection("w4", -4.5, 2.5, -15.5, 9.5, west),
            w5 = make_quality_connection("w5", -4.5, 0.5, -15.5, 2.5, west, 3),
            w6 = make_quality_connection("w6", -4.5, -0.5, -15.5, -2.5, west, 2),

            e1 = make_connection("e1", 4.5, -2.5, 15.5, -9.5, east),
            e2 = make_connection("e2", 4.5, -1.5, 15.5, -5.5, east),
            e3 = make_connection("e3", 4.5, 1.5, 15.5, 5.5, east),
            e4 = make_connection("e4", 4.5, 2.5, 15.5, 9.5, east),
            e5 = make_quality_connection("e5", 4.5, 0.5, 15.5, 2.5, east, 2),
            e6 = make_quality_connection("e6", 4.5, -0.5, 15.5, -2.5, east, 3),

            n1 = make_connection("n1", -2.5, -4.5, -9.5, -15.5, north),
            n2 = make_connection("n2", -1.5, -4.5, -5.5, -15.5, north),
            n3 = make_connection("n3", 1.5, -4.5, 5.5, -15.5, north),
            n4 = make_connection("n4", 2.5, -4.5, 9.5, -15.5, north),
            n5 = make_quality_connection("n5", -0.5, -4.5, -2.5, -15.5, north, 1),
            n6 = make_quality_connection("n6", 0.5, -4.5, 2.5, -15.5, north, 1),
            n7 = make_quality_connection("n7", -3.5, -4.5, -12.5, -15.5, north, 4),
            n8 = make_quality_connection("n8", 3.5, -4.5, 12.5, -15.5, north, 5),

            s1 = make_connection("s1", -2.5, 4.5, -9.5, 15.5, south),
            s2 = make_connection("s2", -1.5, 4.5, -5.5, 15.5, south),
            s3 = make_connection("s3", 1.5, 4.5, 5.5, 15.5, south),
            s4 = make_connection("s4", 2.5, 4.5, 9.5, 15.5, south),
            s7 = make_quality_connection("s7", -3.5, 4.5, -12.5, 15.5, south, 5),
            s8 = make_quality_connection("s8", 3.5, 4.5, 12.5, 15.5, south, 4),
        },
        overlays = {
            outside_x = 0,
            outside_y = -1,
            outside_w = 8,
            outside_h = 6,
            inside_x = -3.5,
            inside_y = 18.5,
        },
    },
}

_G.reload_layouts = function()
    storage.layout_generators = storage.layout_generators or {}
    for name, layout in pairs(layout_generators) do
        storage.layout_generators[name] = layout
    end
end

factorissimo.on_event(factorissimo.events.on_init(), reload_layouts)
