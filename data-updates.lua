local F = "__mythos__"

local function blank()
    return {
        filename = F .. "/graphics/nothing.png",
        priority = "high",
        width = 1,
        height = 1
    }
end

local linked_belts = {}
for _, type in ipairs {"linked-belt", "transport-belt", "underground-belt", "loader-1x1", "loader", "splitter", "lane-splitter"} do
    for _, belt in pairs(data.raw[type]) do
        if belt.collision_mask and belt.collision_mask.layers and not belt.collision_mask.layers.transport_belt then
            belt.collision_mask.layers.transport_belt = true
        end

        local linked = table.deepcopy(belt)
        linked.allow_side_loading = false
        linked.type = "linked-belt"
        linked.next_upgrade = nil
        if not linked.localised_name then linked.localised_name = {"entity-name." .. linked.name} end
        linked.name = "factory-linked-" .. linked.name
        linked.structure = {
            direction_in = blank(),
            direction_out = blank()
        }
        linked.heating_energy = nil
        linked.selection_box = nil
        linked.minable = nil
        linked.hidden = true
        linked.belt_length = nil
        linked.collision_mask = {layers = {transport_belt = true}}
        linked.filter_count = nil
        linked.structure_render_layer = nil
        linked.container_distance = nil
        if type == "loader" or type == "splitter" then linked.collision_box = {{-0.4, -0.4}, {0.4, 0.4}} end

        linked_belts[#linked_belts + 1] = linked
    end
end
data:extend(linked_belts)
