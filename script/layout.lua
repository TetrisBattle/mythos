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
    ["mythos-1"] = {
        name = "mythos-1",
        tier = 1,
        inside_size = 32,
        outside_size = 4,
        inside_door_x = 0,
        inside_door_y = 17,
        outside_door_x = 0,
        outside_door_y = 2,
        outside_energy_receiver_type = "mythos-power-input-4",
        outside_requester_chest = "mythos-requester-chest-mythos-1",
        outside_ejector_chest = "mythos-eject-chest-mythos-1",
        inside_energy_x = -4,
        inside_energy_y = 18,
        overlay_x = 0,
        overlay_y = 1,
        rectangles = {
            {x1 = -17, x2 = 17, y1 = -17, y2 = 17, tile = "mythos-wall-1"},
            {x1 = -16, x2 = 16, y1 = -16, y2 = 16, tile = "mythos-floor"},
        },
        mosaics = {},
        connection_tile = "mythos-floor",
        connections = {
            w1 = make_connection("w1", -2.5, -0.5, -16.5, -0.5, west),
            w2 = make_connection("w2", -2.5,  0.5, -16.5,  0.5, west),

            e1 = make_connection("e1",  2.5, -0.5,  16.5, -0.5, east),
            e2 = make_connection("e2",  2.5,  0.5,  16.5,  0.5, east),

            n1 = make_connection("n1", -0.5, -2.5, -0.5, -16.5, north),
            n2 = make_connection("n2",  0.5, -2.5,  0.5, -16.5, north),

            s1 = make_connection("s1", -0.5,  2.5, -0.5,  16.5, south),
            s2 = make_connection("s2",  0.5,  2.5,  0.5,  16.5, south),
        },
        overlays = {
            outside_x = 0,
            outside_y = -0.5,
            outside_w = 4,
            outside_h = 3,
            inside_x = -1.5,
            inside_y = 18.5,
        },
        cerys_radiative_towers = {
            {-10,  10},
            { 10,  10},
            { 10, -10},
            {-10, -10},
        },
    },
}

--[[
/c __mythos__ reload_layouts()
--]]

_G.reload_layouts = function()
    storage.layout_generators = storage.layout_generators or {}
    for name, layout in pairs(layout_generators) do
        storage.layout_generators[name] = layout
    end
end

mythos.on_event(mythos.events.on_init(), reload_layouts)
