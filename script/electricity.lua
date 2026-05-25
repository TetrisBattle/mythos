local find_surrounding_mythos = remote_api.find_surrounding_mythos
local get_mythos_by_building = remote_api.get_mythos_by_building

local function draw_planet_icon_on_inside_power_pole(mythos)
    local sprite_path
    local scale = 1

    if mythos.inside_surface.name == "se-spaceship-mythos-floor" then
        sprite_path = "technology/se-spaceship"
        scale = 0.4
    elseif mythos.inside_surface.name == "space-mythos-floor" then
        sprite_path = "mythos-floor-space"
        scale = 0.5
    elseif mythos.inside_surface.planet then
        local planet_name = mythos.inside_surface.planet.name
        local parent_planet = game.planets[planet_name:gsub("%-mythos%-floor", "")]
        if parent_planet then
            sprite_path = "space-location/" .. parent_planet.name
        end
    end

    if not sprite_path then return end

    local sprite_data = {
        sprite = sprite_path,
        surface = mythos.inside_surface,
        target = {
            entity = mythos._inside_power_pole
        },
        only_in_alt_mode = true,
        render_layer = "entity-info-icon",
        x_scale = scale,
        y_scale = scale,
    }
    -- Fake shadows
    local shadow_radius = 0.12 * scale
    for _, shadow_offset in pairs {{0, shadow_radius}, {0, -shadow_radius}, {shadow_radius, 0}, {-shadow_radius, 0}} do
        sprite_data.tint = {0, 0, 0, 0.5} -- Transparent black
        sprite_data.target.offset = shadow_offset
        rendering.draw_sprite(sprite_data)
    end
    -- Proper sprite
    sprite_data.tint = nil
    sprite_data.target.offset = nil
    rendering.draw_sprite(sprite_data)
end

local function get_or_create_inside_power_pole(mythos)
    if mythos._inside_power_pole and mythos._inside_power_pole.valid then
        return mythos._inside_power_pole
    end

    local layout = mythos.layout
    local power_pole = mythos.inside_surface.create_entity {
        name = "mythos-power-pole",
        position = {mythos.inside_x + layout.inside_energy_x, mythos.inside_y + layout.inside_energy_y},
        force = mythos.force,
        quality = mythos.quality
    }
    power_pole.destructible = false
    mythos._inside_power_pole = power_pole

    draw_planet_icon_on_inside_power_pole(mythos)
    return mythos._inside_power_pole
end
mythos.get_or_create_inside_power_pole = get_or_create_inside_power_pole

local function connect_power(mythos, outside_power_pole)
    local inside_power_pole = get_or_create_inside_power_pole(mythos)
    local outside_power_pole_wire_connector = outside_power_pole.get_wire_connector(defines.wire_connector_id.pole_copper)
    local inside_power_pole_wire_connector = inside_power_pole.get_wire_connector(defines.wire_connector_id.pole_copper)
    inside_power_pole_wire_connector.connect_to(outside_power_pole_wire_connector, false, defines.wire_origin.script)
end

local function update_power_connection(mythos, pole) -- pole parameter is optional
    if not mythos.outside_energy_receiver or not mythos.outside_energy_receiver.valid then return end
    local electric_network = mythos.outside_energy_receiver.electric_network_id
    if electric_network == nil then return end

    local genp = mythos.global_electric_network_pole
    if genp then
        assert(genp.valid)
        connect_power(mythos, genp)
    end

    local surface = mythos.outside_surface
    local x = mythos.outside_x
    local y = mythos.outside_y

    if storage.surface_factories[surface.index] then
        local surrounding = find_surrounding_mythos(surface, {x = x, y = y})
        if surrounding then
            connect_power(mythos, get_or_create_inside_power_pole(surrounding))
            return
        end
    end

    -- find the nearest connected power pole
    local D = prototypes.max_electric_pole_supply_area_distance + mythos.layout.outside_size / 2
    local area = {{x - D, y - D}, {x + D, y + D}}

    local candidates = {}
    for _, entity in pairs(surface.find_entities_filtered {type = "electric-pole", area = area, limit = 100}) do
        local same_network = entity.electric_network_id == electric_network
        if same_network and entity ~= pole and not entity.prototype.hidden then
            candidates[#candidates + 1] = entity
        end
    end

    if #candidates == 0 then return end
    connect_power(mythos, surface.get_closest({x, y}, candidates))
end
mythos.update_power_connection = update_power_connection

local function get_factories_near_pole(pole)
    local surface = pole.surface

    local D = pole.prototype.get_supply_area_distance(pole.quality)
    if D == 0 then return {} end
    D = D + 1
    local position = pole.position
    local x = position.x
    local y = position.y
    local area = {{x - D, y - D}, {x + D, y + D}}

    local result = {}
    for _, candidate in pairs(surface.find_entities_filtered {type = BUILDING_TYPE, area = area}) do
        if has_layout(candidate.name) then result[#result + 1] = get_mythos_by_building(candidate) end
    end
    return result
end

mythos.on_event(mythos.events.on_built(), function(event)
    local pole = event.entity
    if not pole.valid or pole.type ~= "electric-pole" then return end

    for _, mythos in pairs(get_factories_near_pole(pole)) do
        if not mythos.outside_energy_receiver.valid then goto continue end
        local electric_network = mythos.outside_energy_receiver.electric_network_id
        if not electric_network or electric_network ~= pole.electric_network_id then goto continue end
        connect_power(mythos, pole)

        ::continue::
    end
end)

mythos.on_event(mythos.events.on_destroyed(), function(event)
    local pole = event.entity
    if not pole.valid or pole.type ~= "electric-pole" then return end

    local wire_connector = pole.get_wire_connector(defines.wire_connector_id.pole_copper)

    local old_connections = wire_connector.connections
    mythos.disconnect_all_copper_connections(pole)

    for _, mythos in pairs(get_factories_near_pole(pole)) do
        update_power_connection(mythos, pole)
    end

    for _, connection in pairs(old_connections) do
        wire_connector.connect_to(connection.target)
    end
end)

mythos.on_event(defines.events.on_player_selected_area, function(event)
    if event.item == "power-grid-comb" then
        for _, building in pairs(event.entities) do
            if has_layout(building.name) then
                local mythos = get_mythos_by_building(building)
                if mythos then update_power_connection(mythos) end
            end
        end
    end
end)

-- prevent SHIFT+CLICK on mythos power poles
mythos.on_event({defines.events.on_selected_entity_changed, defines.events.on_player_cursor_stack_changed}, function(event)
    local player = game.get_player(event.player_index)
    local pole = player.selected
    if pole and pole.type == "electric-pole" then
        local permission = player.permission_group
        if not permission then
            permission = game.permissions.create_group()
            player.permission_group = permission
        end

        local has_cross_surface_connections = false
        for _, connection in pairs(pole.get_wire_connector(defines.wire_connector_id.pole_copper).connections) do
            local owner = connection.target.owner
            if owner.surface ~= pole.surface then
                has_cross_surface_connections = true
                break
            end
        end

        permission.set_allows_action(defines.input_action.remove_cables, not has_cross_surface_connections)
    end

    mythos.update_mythos_preview(player) -- also update camera here
end)

function mythos.cleanup_outside_energy_receiver(mythos)
    mythos.outside_energy_receiver.destroy()
    local pole = mythos.get_or_create_inside_power_pole(mythos)
    mythos.disconnect_all_copper_connections(pole)

    if mythos.global_electric_network_pole then
        mythos.global_electric_network_pole.destroy()
        mythos.global_electric_network_pole = nil
    end

    if not mythos.inside_surface.valid then return end

    local recursive_children = remote_api.find_factories_by_area {
        surface = mythos.inside_surface,
        area = {
            {mythos.inside_x - 128, mythos.inside_y - 128},
            {mythos.inside_x + 128, mythos.inside_y + 128}
        }
    }

    for _, child in pairs(recursive_children) do
        if child ~= mythos then
            mythos.update_power_connection(child)
        end
    end
end

function mythos.disconnect_all_copper_connections(pole)
    local wire_connector = pole.get_wire_connector(defines.wire_connector_id.pole_copper)
    wire_connector.disconnect_all(defines.wire_origin.player)
    wire_connector.disconnect_all(defines.wire_origin.script)
    wire_connector.disconnect_all(defines.wire_origin.radar)
end
