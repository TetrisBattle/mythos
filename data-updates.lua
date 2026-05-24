-- Generate hidden linked-belt proxies used by the belt connection system.
-- Each real belt type gets a "mythos-linked-<name>" variant with:
--   • type = "linked-belt"  (Factorio built-in for cross-surface belt bridges)
--   • blank graphics        (invisible; positioned at connection points)
--   • no collision except transport_belt layer  (doesn't block players/buildings)

local F = "__mythos__"

local function blank_sprite()
    return {
        filename = F .. "/graphics/nothing.png",
        priority = "high",
        width = 1,
        height = 1,
    }
end

local linked_belts = {}
for _, belt_type in ipairs {"transport-belt", "underground-belt", "loader-1x1", "loader", "splitter", "lane-splitter", "linked-belt"} do
    for _, belt in pairs(data.raw[belt_type] or {}) do
        -- Skip prototypes that are already mythos-linked variants
        if belt.name:find("^mythos%-linked%-") then goto continue end

        local linked = table.deepcopy(belt)
        linked.type = "linked-belt"
        linked.name = "mythos-linked-" .. belt.name
        linked.next_upgrade = nil
        if not linked.localised_name then
            linked.localised_name = {"entity-name." .. belt.name}
        end
        -- Blank out all visual structure so linked belts are invisible
        linked.structure = {
            direction_in  = blank_sprite(),
            direction_out = blank_sprite(),
        }
        linked.heating_energy        = nil
        linked.selection_box         = nil
        linked.minable               = nil
        linked.hidden                = true
        linked.belt_length           = nil
        linked.collision_mask        = {layers = {transport_belt = true}}
        linked.filter_count          = nil
        linked.structure_render_layer = nil
        linked.container_distance    = nil
        linked.allow_side_loading    = false
        -- Loaders and splitters need a smaller collision box to fit on a single tile
        if belt_type == "loader" or belt_type == "splitter" then
            linked.collision_box = {{-0.4, -0.4}, {0.4, 0.4}}
        end

        linked_belts[#linked_belts + 1] = linked
        ::continue::
    end
end

data:extend(linked_belts)

-- ---------------------------------------------------------------------------
-- Fluid connection proxies: hidden pumps with one normal port (world-facing)
-- and one linked port (cross-surface).  Mirrored from factorissimo's pattern.
-- ---------------------------------------------------------------------------

local base_pump       = data.raw["pump"]["pump"]
local pumping_speed   = base_pump.pumping_speed * 10

-- Raise max_fluid_flow so our fast pumps don't get capped by the utility constant
local util_consts = data.raw["utility-constants"]["default"]
util_consts.max_fluid_flow = math.max(util_consts.max_fluid_flow or 0, pumping_speed)

local function make_pump(name, normal_flow, linked_flow)
    return {
        type        = "pump",
        name        = name,
        icon        = base_pump.icon,
        icon_size   = base_pump.icon_size,
        localised_name = {"entity-name.pump"},
        flags = {"not-blueprintable", "not-deconstructable", "not-on-map",
                 "not-flammable", "not-repairable", "hide-alt-info"},
        max_health = 50,
        hidden     = true,
        fluid_box  = {
            volume                = pumping_speed,
            hide_connection_info  = true,
            pipe_connections = {
                {position = {0, 0}, direction = defines.direction.north,
                 flow_direction = normal_flow, connection_type = "normal"},
                {position = {0, 0}, direction = defines.direction.south,
                 flow_direction = linked_flow, connection_type = "linked",
                 linked_connection_id = 0},
            },
        },
        energy_source    = {type = "void"},
        pumping_speed    = pumping_speed,
        energy_usage     = "1W",
        collision_box    = {{-0.5, -0.5}, {0.5, 0.5}},
        collision_mask   = {layers = {}},
        quality_indicator_scale = 0,
        squeak_behaviour = false,
    }
end

-- inside-input:  takes fluid FROM the pocket-dimension, sends it cross-surface
-- inside-output: receives fluid from cross-surface, delivers it INTO the pocket
local inside_input  = make_pump("mythos-inside-pump-input",  "input",  "output")
local inside_output = make_pump("mythos-inside-pump-output", "output", "input")

-- outside variants are identical but selectable so players can see them
local outside_input  = table.deepcopy(inside_input)
outside_input.name   = "mythos-outside-pump-input"
outside_input.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
outside_input.selection_priority = 51

local outside_output = table.deepcopy(inside_output)
outside_output.name  = "mythos-outside-pump-output"
outside_output.selection_box = {{-0.5, -0.5}, {0.5, 0.5}}
outside_output.selection_priority = 51

data:extend {inside_input, inside_output, outside_input, outside_output}

-- ---------------------------------------------------------------------------
-- Heat connection proxy: a minimal hidden heat-pipe used as a dummy connector.
-- Temperature equalisation is handled at runtime in connections.lua.
-- ---------------------------------------------------------------------------

local base_heat = data.raw["heat-pipe"]["heat-pipe"]
data:extend {{
    type                = "heat-pipe",
    name                = "mythos-heat-connector",
    selectable_in_game  = false,
    flags               = {"not-on-map", "hide-alt-info"},
    hidden              = true,
    collision_mask      = {layers = {}},
    collision_box       = table.deepcopy(base_heat.collision_box),
    localised_name      = {"entity-name.heat-pipe"},
    max_health          = 1,
    heat_buffer = {
        max_temperature        = 0,
        specific_heat          = "1W",
        max_transfer           = "1W",
        default_temperature    = 0,
        min_working_temperature = 0,
        min_temperature_gradient = 0,
        connections            = table.deepcopy(base_heat.heat_buffer.connections),
    },
}}
