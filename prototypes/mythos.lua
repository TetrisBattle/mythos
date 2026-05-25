local F = "__mythos__";
require("circuit-connector-sprites")

local function cwc0()
    return {shadow = {red = {0, 0}, green = {0, 0}}, wire = {red = {0, 0}, green = {0, 0}}}
end
local function cc0()
    return get_circuit_connector_sprites({0, 0}, nil, 1)
end

data:extend {
    {
        type = "storage-tank",
        name = "mythos-1",
        icon = F .. "/graphics/icon/mythos.png",
        icon_size = 64,
        flags = {"player-creation", "placeable-player"},
        minable = {mining_time = 0.5, result = "mythos-1-instantiated", count = 1},
        placeable_by = {item = "mythos-1", count = 1},
        max_health = 2000,
        collision_box = {{-1.8, -1.8}, {1.8, 1.8}},
        selection_box = {{-1.8, -1.8}, {1.8, 1.8}},
        pictures = {
            picture = {
                layers = {
                    {
                        filename = F .. "/graphics/mythos/mythos-shadow.png",
                        width = 416,
                        height = 320,
                        scale = 0.35,
                        shift = {0.75, 0},
                        draw_as_shadow = true
                    },
                    {
                        filename = F .. "/graphics/mythos/mythos.png",
                        width = 416,
                        height = 320,
                        scale = 0.5,
                        shift = {0.75, 0},
                    }
                }
            },
        },
        window_bounding_box = {{0, 0}, {0, 0}},
        fluid_box = {
            volume = 1,
            pipe_covers = pipecoverspictures(),
            pipe_connections = {},
        },
        flow_length_in_ticks = 1,
        circuit_wire_max_distance = 0,
        map_color = {r = 0.8, g = 0.7, b = 0.55},
        is_military_target = true,
        moc_ignore = true,
    },
    {
        type = "item-with-tags",
        name = "mythos-1-instantiated",
        localised_name = {"item-name.mythos-packed", {"entity-name.mythos-1"}},
        icons = {
            {
                icon = F .. "/graphics/icon/mythos.png",
                icon_size = 64,
            },
            {
                icon = F .. "/graphics/icon/packing-tape.png",
                icon_size = 64,
            }
        },
        subgroup = "mythos",
        order = "b-a",
        place_result = "mythos-1",
        stack_size = 1,
        weight = 100000000,
        flags = {"not-stackable"},
        hidden_in_factoriopedia = true,
        factoriopedia_alternative = "mythos-1"
    },
    {
        type = "item",
        name = "mythos-1",
        icon = F .. "/graphics/icon/mythos.png",
        icon_size = 64,
        subgroup = "mythos",
        order = "b-a",
        weight = 100000000,
        place_result = "mythos-1",
        stack_size = 1,
        flags = {"primary-place-result", "not-stackable"}
    }
}
