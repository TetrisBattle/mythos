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
