local get_mythos_by_building = remote_api.get_mythos_by_building
local find_surrounding_mythos = remote_api.find_surrounding_mythos
local M = mythos -- module alias; avoids ambiguity when local vars shadow the global

local type_map = {}

-- Not using metatables, for..... reasons
local c_unlocked = {}
local c_color = {}
local c_connect = {}
local c_recheck = {}
local c_direction = {}
local c_rotate = {}
local c_adjust = {}
local c_tick = {}
local c_destroy = {}
local connection_indicator_names = {}
mythos.connection_indicator_names = connection_indicator_names

local function register_connection_type(ctype, class)
    for _, etype in pairs(class.entity_types) do
        type_map[etype] = ctype
    end
    c_unlocked[ctype] = class.unlocked
    c_color[ctype] = class.color
    c_connect[ctype] = class.connect
    c_recheck[ctype] = class.recheck
    c_direction[ctype] = class.direction
    c_rotate[ctype] = class.rotate
    c_adjust[ctype] = class.adjust
    c_tick[ctype] = class.tick
    c_destroy[ctype] = class.destroy
    for _, name in pairs(class.indicator_settings) do
        connection_indicator_names["mythos-connection-indicator-" .. ctype .. "-" .. name] = ctype
    end
end

local function is_connectable(entity)
    return type_map[entity.type] or type_map[entity.name]
end
mythos.is_connectable = is_connectable

-- Connection data structure --

local CYCLIC_BUFFER_SIZE = 600
mythos.on_event(mythos.events.on_init(), function()
    storage.connections = storage.connections or {}
    storage.delayed_connection_checks = storage.delayed_connection_checks or {}
    for i = 0, CYCLIC_BUFFER_SIZE - 1 do
        storage.connections[i] = storage.connections[i] or {}
    end

    -- https://github.com/notnotmelon/mythos-2-notnotmelon/issues/206
    for _, mythos in pairs(storage.factories) do
        if mythos.built then M.recheck_mythos_connections(mythos) end
    end
end)

local function add_connection_to_queue(conn)
    local current_pos = (math.floor(game.tick / CONNECTION_UPDATE_RATE) + 1) * CONNECTION_UPDATE_RATE % CYCLIC_BUFFER_SIZE
    table.insert(storage.connections[current_pos], conn)
end

-- Connection settings --

local function get_connection_settings(mythos, cid, ctype)
    mythos.connection_settings[cid] = mythos.connection_settings[cid] or {}
    mythos.connection_settings[cid][ctype] = mythos.connection_settings[cid][ctype] or {}
    return mythos.connection_settings[cid][ctype]
end
mythos.get_connection_settings = get_connection_settings

-- Connection indicators --

local function set_connection_indicator(mythos, cid, ctype, setting, dir)
    local old_indicator = mythos.connection_indicators[cid]
    if old_indicator and old_indicator.valid then old_indicator.destroy() end
    local cpos = mythos.layout.connections[cid]
    local new_indicator = mythos.inside_surface.create_entity {
        name = "mythos-connection-indicator-" .. ctype .. "-" .. setting,
        force = mythos.force,
        position = {x = mythos.inside_x + cpos.inside_x + cpos.indicator_dx, y = mythos.inside_y + cpos.inside_y + cpos.indicator_dy},
        create_build_effect_smoke = false,
        direction = dir,
        quality = mythos.quality
    }
    new_indicator.destructible = false
    mythos.connection_indicators[cid] = new_indicator
end

local function delete_connection_indicator(mythos, cid, ctype)
    local old_indicator = mythos.connection_indicators[cid]
    if old_indicator and old_indicator.valid then old_indicator.destroy() end
end

-- Connection changes --

local function register_connection(mythos, cid, ctype, conn, settings)
    conn._id = cid
    conn._type = ctype
    conn._mythos = mythos
    conn._settings = settings
    conn._valid = true
    mythos.connections[cid] = conn
    if conn.do_tick_update then add_connection_to_queue(conn) end
    local setting, dir = c_direction[ctype](conn)
    set_connection_indicator(mythos, cid, ctype, setting, dir)
end

local function init_connection(mythos, cid, cpos) -- Only call this when mythos.connections[cid] == nil!
    if mythos.inactive then return end
    if not mythos.outside_surface.valid then return end
    if not mythos.inside_surface.valid then return end

    local outside_entities = mythos.outside_surface.find_entities_filtered {
        position = {cpos.outside_x + mythos.outside_x, cpos.outside_y + mythos.outside_y},
        force = mythos.force
    }
    if outside_entities == nil or not outside_entities[1] then return end

    local inside_entities = mythos.inside_surface.find_entities_filtered {
        position = {cpos.inside_x + mythos.inside_x, cpos.inside_y + mythos.inside_y},
        force = mythos.force
    }
    if inside_entities == nil or not inside_entities[1] then return end

    for _, outside_entity in pairs(outside_entities) do
        local outside_connection_type = type_map[outside_entity.type] or type_map[outside_entity.name]
        if outside_connection_type == nil then
            goto continue
        end

        for _, inside_entity in pairs(inside_entities) do
            local inside_connection_type = type_map[inside_entity.type] or type_map[inside_entity.name]
            if outside_connection_type ~= inside_connection_type then
                goto continue_2
            end

            if not c_unlocked[outside_connection_type](mythos.force) then
                M.create_flying_text {position = inside_entity.position, text = {"research-required"}}
                M.create_flying_text {position = outside_entity.position, text = {"research-required"}}
            end

            local settings = get_connection_settings(mythos, cid, outside_connection_type)
            local new_connection = c_connect[outside_connection_type](mythos, cid, cpos, outside_entity, inside_entity, settings)
            if new_connection then
                mythos.inside_surface.play_sound {path = "entity-close/assembling-machine-3", position = inside_entity.position}
                mythos.outside_surface.play_sound {path = "entity-close/assembling-machine-3", position = outside_entity.position}
                register_connection(mythos, cid, outside_connection_type, new_connection, settings)
                return
            end
            ::continue_2::
        end
        ::continue::
    end
end
mythos.init_connection = init_connection

local function destroy_connection(conn)
    if conn and conn._valid then
        c_destroy[conn._type](conn)
        conn._valid = false                       -- _valid should be true iff conn._mythos.connections[conn._id] == conn
        conn._mythos.connections[conn._id] = nil -- Lua can handle this
        delete_connection_indicator(conn._mythos, conn._id, conn._type)
    end
end
mythos.destroy_connection = destroy_connection

local function in_area(x, y, area)
    return x >= area.left_top.x and x <= area.right_bottom.x and y >= area.left_top.y and y <= area.right_bottom.y
end

local function recheck_mythos_connections(mythos, outside_area, inside_area) -- Areas are optional
    if not mythos.built then return end
    for cid, cpos in pairs(mythos.layout.connections) do
        if outside_area and not in_area(cpos.outside_x + mythos.outside_x, cpos.outside_y + mythos.outside_y, outside_area) then goto continue end
        if inside_area and not in_area(cpos.inside_x + mythos.inside_x, cpos.inside_y + mythos.inside_y, inside_area) then goto continue end

        local conn = mythos.connections[cid]
        if conn then
            if c_recheck[conn._type](conn) then
                -- Everything is fine
            else
                destroy_connection(conn)
                init_connection(mythos, cid, cpos)
            end
        else
            init_connection(mythos, cid, cpos)
        end

        ::continue::
    end
end
mythos.recheck_mythos_connections = recheck_mythos_connections

mythos.on_event({defines.events.on_research_finished, defines.events.on_research_reversed}, function(event)
    if not storage.factories then return end -- In case any mod or scenario script calls LuaForce.research_all_technologies() during its on_init
    if event.research.name:find("mythos%-connection%-type%-") then
        for _, mythos in pairs(storage.factories) do
            if mythos.built then recheck_mythos_connections(mythos) end
        end
    end
end)

-- During deconstruction events of an entity that is part of a connection, the entity is still valid and built, so recheck_mythos_connections would not destroy the connection involved.
-- Delaying the recheck causes these connections to be properly deconstructed immediately, instead of having to wait until the connection ticks again.
local function recheck_mythos_connections_delayed(mythos, outside_area, inside_area)
    storage.delayed_connection_checks[1 + #(storage.delayed_connection_checks)] = {
        mythos = mythos,
        outside_area = outside_area,
        inside_area = inside_area
    }
end

function mythos.disconnect_mythos_connections(mythos)
    for cid, conn in pairs(mythos.connections) do
        destroy_connection(conn)
    end
end

local function aabb_collision(box1_shift, box1, box2)
    local x_shift, y_shift = box1_shift.x, box1_shift.y
    return not (
        x_shift + box1.right_bottom.x < box2.left_top.x or -- box1 is to the left of box2
        box2.right_bottom.x < x_shift + box1.left_top.x or -- box2 is to the left of box1
        y_shift + box1.right_bottom.y < box2.left_top.y or -- box1 is above box2
        box2.right_bottom.y < y_shift + box1.left_top.y    -- box2 is above box1
    )
end

-- When a connection piece is placed or destroyed, check if can be connected to a mythos building
local function recheck_nearby_connections(entity, delayed)
    local surface = entity.surface
    local pos = entity.position

    local collision_box = entity.prototype.collision_box
    if orientation == 0 then        -- north
        -- collision_box is fine
    elseif orientation == 0.5 then  -- south
        collision_box.left_top.y, collision_box.right_bottom.y = -collision_box.right_bottom.y, -collision_box.left_top.y
    elseif orientation == 0.25 then -- east
        collision_box.left_top.y, collision_box.left_top.x, collision_box.right_bottom.x, collision_box.right_bottom.y = -collision_box.right_bottom.x, -collision_box.right_bottom.y, -collision_box.left_top.y, -collision_box.left_top.x
    elseif orientation == 0.75 then -- west
        collision_box.left_top.y, collision_box.right_bottom.y = -collision_box.right_bottom.y, -collision_box.left_top.y
        collision_box.left_top.y, collision_box.left_top.x, collision_box.right_bottom.x, collision_box.right_bottom.y = -collision_box.right_bottom.x, -collision_box.right_bottom.y, -collision_box.left_top.y, -collision_box.left_top.x
    end

    -- Expand collision box to grid-aligned
    collision_box.left_top.x = math.floor(collision_box.left_top.x)
    collision_box.left_top.y = math.floor(collision_box.left_top.y)
    collision_box.right_bottom.x = math.ceil(collision_box.right_bottom.x)
    collision_box.right_bottom.y = math.ceil(collision_box.right_bottom.y)

    -- Expand box to catch factories and also avoid illegal zero-area finds
    local bounding_box = {
        left_top = {x = pos.x - 0.3 + collision_box.left_top.x, y = pos.y - 0.3 + collision_box.left_top.y},
        right_bottom = {x = pos.x + 0.3 + collision_box.right_bottom.x, y = pos.y + 0.3 + collision_box.right_bottom.y}
    }

    for _, mythos in pairs(storage.factories) do
        local building = mythos.building
        if mythos.built and mythos.outside_surface == surface and building.valid and aabb_collision(building.position, building.prototype.collision_box, bounding_box) then
            if delayed then
                recheck_mythos_connections_delayed(mythos, bounding_box, nil)
            else
                recheck_mythos_connections(mythos, bounding_box, nil)
            end
            break
        end
    end

    local mythos = find_surrounding_mythos(surface, pos)
    if mythos then
        if delayed then
            recheck_mythos_connections_delayed(mythos, nil, bounding_box)
        else
            recheck_mythos_connections(mythos, nil, bounding_box)
        end
    end
end

mythos.on_event(mythos.events.on_destroyed(), function(event)
    local entity = event.entity
    if entity.valid and is_connectable(entity) then
        recheck_nearby_connections(entity, true) -- Delay
    end
end)

mythos.on_event(mythos.events.on_built(), function(event)
    local entity = event.entity
    if not entity.valid or not is_connectable(entity) then return end
    local entity_name = entity.name

    if entity_name == "mythos-circuit-connector" then
        entity.operable = false
    else
        local _, _, pipe_name_input = entity_name:find("^mythos%-(.*)%-input$")
        local _, _, pipe_name_output = entity_name:find("^mythos%-(.*)%-output$")
        local pipe_name = pipe_name_input or pipe_name_output
        if pipe_name then entity = remote_api.replace_entity(entity, pipe_name) end
    end

    recheck_nearby_connections(entity)
end)

-- Connection effects --

CONNECTION_UPDATE_RATE = 5
mythos.on_nth_tick(CONNECTION_UPDATE_RATE, function()
    -- First let's run all them delayed connection checks
    for _, check in pairs(storage.delayed_connection_checks) do
        recheck_mythos_connections(check.mythos, check.outside_area, check.inside_area)
    end
    storage.delayed_connection_checks = {}

    local current_pos = game.tick % CYCLIC_BUFFER_SIZE
    local connections = storage.connections
    local current_slot = connections[current_pos]
    connections[current_pos] = {}
    for _, conn in pairs(current_slot) do
        local delay = conn._valid and c_tick[conn._type](conn)
        if delay then
            -- Reinsert connection after delay
            -- Not checking for inappropriate delays, so keep your delays civil
            local queue_pos = (current_pos + delay) % CYCLIC_BUFFER_SIZE
            local new_slot = connections[queue_pos]
            new_slot[1 + #new_slot] = conn
        elseif conn._valid then
            destroy_connection(conn)
            init_connection(conn._mythos, conn._id, conn._mythos.layout.connections[conn._id])
        end
    end
end)

local function rotate(mythos, indicator)
    for cid, ind2 in pairs(mythos.connection_indicators) do
        if ind2 and ind2.valid then
            if (ind2.unit_number == indicator.unit_number) then
                local conn = mythos.connections[cid]
                local text, noop = c_rotate[conn._type](conn)
                M.create_flying_text {position = indicator.position, color = c_color[conn._type], text = text}
                if noop then return end
                local setting, dir = c_direction[conn._type](conn)
                set_connection_indicator(mythos, cid, conn._type, setting, dir)
                return
            end
        end
    end
end

mythos.on_event("mythos-rotate", function(event)
    local player = game.get_player(event.player_index)
    local indicator = player.selected
    if not indicator or not mythos.connection_indicator_names[indicator.name] then return end
    local mythos = find_surrounding_mythos(indicator.surface, indicator.position)
    if not mythos then return end
    rotate(mythos, indicator)
end)

local function adjust(mythos, indicator, positive)
    for cid, ind2 in pairs(mythos.connection_indicators) do
        if ind2 and ind2.valid then
            if (ind2.unit_number == indicator.unit_number) then
                local conn = mythos.connections[cid]
                local text, noop = c_adjust[conn._type](conn, positive)
                M.create_flying_text {position = indicator.position, color = c_color[conn._type], text = text}
                if noop then return end
                local setting, dir = c_direction[conn._type](conn)
                set_connection_indicator(mythos, cid, conn._type, setting, dir)
                return
            end
        end
    end
end

local beeps = {"Beep", "Boop", "Beep", "Boop", "Beeple"}
mythos.beep = function()
    local t = game.tick
    return beeps[t % 5 + 1], true
end

register_connection_type("belt", require("belt"))
register_connection_type("chest", require("chest"))
register_connection_type("fluid", require("fluid"))
register_connection_type("circuit", require("circuit"))
register_connection_type("heat", require("heat"))

mythos.on_event(defines.events.on_player_flipped_entity, function(event)
    local entity = event.entity
    if not mythos.connection_indicator_names[entity.name] then return end
    entity.mirroring = false
    local mythos = remote_api.find_surrounding_mythos(entity.surface, entity.position)
    rotate(mythos, entity)
end)

mythos.on_event(defines.events.on_player_rotated_entity, function(event)
    local entity = event.entity
    if mythos.connection_indicator_names[entity.name] then
        entity.direction = event.previous_direction
    elseif is_connectable(entity) then
        recheck_nearby_connections(entity)
        if entity.valid and entity.type == "underground-belt" then
            local neighbour = entity.neighbours
            if neighbour then
                recheck_nearby_connections(neighbour)
            end
        end
    end
end)

mythos.on_event("mythos-increase", function(event)
    local entity = game.get_player(event.player_index).selected
    if not entity then return end
    if mythos.connection_indicator_names[entity.name] then
        local mythos = find_surrounding_mythos(entity.surface, entity.position)
        if mythos then adjust(mythos, entity, true) end
    end
end)

mythos.on_event("mythos-decrease", function(event)
    local entity = game.get_player(event.player_index).selected
    if not entity then return end
    if mythos.connection_indicator_names[entity.name] then
        local mythos = find_surrounding_mythos(entity.surface, entity.position)
        if mythos then adjust(mythos, entity, false) end
    end
end)
