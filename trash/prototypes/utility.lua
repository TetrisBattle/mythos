local F = "__mythos__"

-- Circuit connectors

data:extend {{
    type = "item",
    name = "mythos-circuit-connector",
    icon = F .. "/graphics/icon/mythos-circuit-connector.png",
    icon_size = 64,
    flags = {},
    subgroup = "mythos",
    order = "c-b",
    place_result = "mythos-circuit-connector",
    stack_size = 50,
}}

data:extend {{
    type = "electric-pole",
    name = "mythos-circuit-connector",
    icon = F .. "/graphics/icon/mythos-circuit-connector.png",
    icon_size = 64,
    flags = {"placeable-neutral", "player-creation"},
    minable = {mining_time = 0.5, result = "mythos-circuit-connector"},
    max_health = 50,
    corpse = "small-remnants",
    supply_area_distance = 0,
    draw_copper_wires = false,
    collision_box = {{-0.35, -0.35}, {0.35, 0.35}},
    selection_box = {{-0.5, -0.5}, {0.5, 0.5}},
    auto_connect_up_to_n_wires = 0,
    pictures = {
        layers = {
            {
                direction_count = 1,
                filename = F .. "/graphics/entity/mythos-circuit-connector.png",
                width = 64,
                height = 64,
                scale = 0.51,
            },
            {
                direction_count = 1,
                filename = F .. "/graphics/entity/mythos-circuit-connector-sh.png",
                width = 85,
                height = 85,
                scale = 0.51,
                draw_as_shadow = true,
            },
        }
    },
    connection_points = {{
        shadow = {
            red = {0.75, 0.5625},
            green = {0.21875, 0.5625}
        },
        wire = {
            red = {0.28125, 0.15625},
            green = {-0.21875, 0.15625}
        }
    }},
    maximum_wire_distance = 14,
}}

local mythos_circuit_connector_invisible = table.deepcopy(data.raw["electric-pole"]["mythos-circuit-connector"])
mythos_circuit_connector_invisible.name = "mythos-circuit-connector-invisible"
mythos_circuit_connector_invisible.localised_name = {"entity-name.mythos-circuit-connector"}
mythos_circuit_connector_invisible.localised_description = {"entity-description.mythos-circuit-connector"}
mythos_circuit_connector_invisible.pictures = nil
mythos_circuit_connector_invisible.selection_box = nil
mythos_circuit_connector_invisible.minable = nil
mythos_circuit_connector_invisible.corpse = nil
mythos_circuit_connector_invisible.hidden = true
mythos_circuit_connector_invisible.draw_circuit_wires = false
mythos_circuit_connector_invisible.draw_copper_wires = false
mythos_circuit_connector_invisible.factoriopedia_alternative = "mythos-circuit-connector"
data:extend {mythos_circuit_connector_invisible}
