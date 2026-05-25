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
-- Fluid connection proxy: a single hidden pipe with one outward-facing normal
-- port (connects to the player's pipe network) and one linked port (bridges
-- the two surfaces).  Two of these are linked via add_linked_connection so
-- the inside and outside pipe networks share a pressure system — fluid flows
-- bidirectionally, exactly like putting pipes next to each other in the world.
-- ---------------------------------------------------------------------------

local base_pipe = data.raw["pipe"]["pipe"]

-- Deep copy gives us all the required picture/sprite fields for free.
-- We override only fluid_box and entity metadata.
local fluid_connector = table.deepcopy(base_pipe)
fluid_connector.name           = "mythos-fluid-connector"
fluid_connector.minable        = nil
fluid_connector.next_upgrade   = nil
fluid_connector.hidden         = true
fluid_connector.selection_box  = nil
fluid_connector.collision_mask = {layers = {}}
fluid_connector.flags = {
    "not-blueprintable", "not-deconstructable", "not-on-map",
    "not-flammable", "not-repairable", "hide-alt-info",
}
-- One outward-facing normal port (rotates with entity direction) +
-- one linked port for the cross-surface bridge.
fluid_connector.fluid_box = {
    volume = base_pipe.fluid_box.volume,
    pipe_connections = {
        {position = {0, 0}, direction = defines.direction.north,
         connection_type = "normal"},
        {position = {0, 0}, direction = defines.direction.south,
         connection_type = "linked", linked_connection_id = 0},
    },
}

data:extend {fluid_connector}

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
