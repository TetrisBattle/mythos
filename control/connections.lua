-- Belt connection system for Mythos pocket-dimension entities.
--
-- Each 4×4 mythos-entity has 8 connection points (2 per cardinal side).
-- When a matching belt is placed on both the outside world tile AND the
-- corresponding inside-surface tile, a pair of hidden "mythos-linked-*"
-- linked-belt entities is created and connected via connect_linked_belts().
--
-- Coordinates are relative to the entity's centre on each surface:
--   outside centre = entity.position
--   inside  centre = {0, 0}  (the pocket-dimension surface origin)

local M = {}

-- ---------------------------------------------------------------------------
-- Connection point layout
-- ---------------------------------------------------------------------------
-- make_connection(id, outside_x, outside_y, inside_x, inside_y, direction_out)
-- direction_out = the direction a belt must face to carry items OUTWARD
--                 (i.e. from inside the pocket towards the outside world).

local north = defines.direction.north
local south = defines.direction.south
local east  = defines.direction.east
local west  = defines.direction.west

local DX = {[north] = 0, [east] = 1, [south] = 0, [west] = -1}
local DY = {[north] = -1, [east] = 0, [south] = 1, [west] = 0}
local OPPOSITE = {[north] = south, [south] = north, [east] = west, [west] = east}

local function make_connection(id, ox, oy, ix, iy, dir_out)
    return {
        id           = id,
        outside_x    = ox,
        outside_y    = oy,
        inside_x     = ix,
        inside_y     = iy,
        direction_out = dir_out,
        direction_in  = OPPOSITE[dir_out],
        indicator_dx  = DX[dir_out],
        indicator_dy  = DY[dir_out],
    }
end

-- The mythos-entity selection_box is ±2 tiles.
-- Outside connection points sit 0.5 tiles beyond that edge (at ±2.5).
-- Inside connection points sit 1.5 tiles inside the 32-tile pocket edge (at ±14.5).
local CONNECTIONS = {
    -- North side
    n1 = make_connection("n1", -0.5, -2.5, -0.5, -14.5, north),
    n2 = make_connection("n2",  0.5, -2.5,  0.5, -14.5, north),
    -- South side
    s1 = make_connection("s1", -0.5,  2.5, -0.5,  14.5, south),
    s2 = make_connection("s2",  0.5,  2.5,  0.5,  14.5, south),
    -- East side
    e1 = make_connection("e1",  2.5, -0.5,  14.5, -0.5, east),
    e2 = make_connection("e2",  2.5,  0.5,  14.5,  0.5, east),
    -- West side
    w1 = make_connection("w1", -2.5, -0.5, -14.5, -0.5, west),
    w2 = make_connection("w2", -2.5,  0.5, -14.5,  0.5, west),
}

-- ---------------------------------------------------------------------------
-- Belt-type helpers  (mirror factorissimo's logic)
-- ---------------------------------------------------------------------------

local BELT_ENTITY_TYPES = {
    ["transport-belt"]  = true,
    ["underground-belt"]= true,
    ["loader"]          = true,
    ["loader-1x1"]      = true,
    ["linked-belt"]     = true,
    ["splitter"]        = true,
    ["lane-splitter"]   = true,
    ["inserter"]        = true,
}

local DIRECTION_AGNOSTIC = {
    ["transport-belt"] = true,
    ["splitter"]       = true,
    ["lane-splitter"]  = true,
    ["inserter"]       = true,
}

local function get_belt_io_type(entity)
    if entity.type == "loader" or entity.type == "loader-1x1" then
        return entity.loader_type
    elseif entity.type == "linked-belt" then
        return entity.linked_belt_type
    elseif entity.type == "underground-belt" then
        return entity.belt_to_ground_type
    end
end

local function get_entity_direction(entity)
    -- Inserters "point" opposite to their facing for belt purposes
    if entity.type == "inserter" then
        return (entity.direction + 8) % 16
    end
    return entity.direction
end

-- Returns the shared facing direction if the two entities can form a belt
-- connection at this cpos, or nil if they cannot.
local function get_conn_facing(outside_entity, inside_entity, dir_out, dir_in)
    local oe_type = outside_entity.type
    local ie_type = inside_entity.type
    local od = get_entity_direction(outside_entity)
    local id = get_entity_direction(inside_entity)

    if not DIRECTION_AGNOSTIC[oe_type] then
        local io_type = get_belt_io_type(outside_entity)
        if io_type == "input" then
            if dir_out ~= od then return nil end
        else
            if dir_in ~= od then return nil end
        end
    end

    if not DIRECTION_AGNOSTIC[ie_type] then
        local io_type = get_belt_io_type(inside_entity)
        if io_type == "input" then
            if dir_in ~= id then return nil end
        else
            if dir_out ~= id then return nil end
        end
    end

    return (od == id) and od or nil
end

-- ---------------------------------------------------------------------------
-- Connection lifecycle
-- ---------------------------------------------------------------------------

local function destroy_connection(conn)
    if conn.from_link and conn.from_link.valid then
        conn.from_link.destroy()
    end
    if conn.to_link and conn.to_link.valid then
        conn.to_link.destroy()
    end
end

local function connect_belt_pair(mythos_data, cpos, outside_entity, inside_entity)
    local conn_facing = get_conn_facing(
        outside_entity, inside_entity, cpos.direction_out, cpos.direction_in
    )
    if not conn_facing then return nil end
    if conn_facing ~= cpos.direction_in and conn_facing ~= cpos.direction_out then return nil end

    -- Two inserters at the same point makes no sense
    if inside_entity.type == "inserter" and outside_entity.type == "inserter" then return nil end

    -- Long inserters are not supported
    if inside_entity.type  == "inserter" and inside_entity.name:find("long")  then return nil end
    if outside_entity.type == "inserter" and outside_entity.name:find("long") then return nil end

    -- Derive linked-belt prototype names
    local inside_link_name, outside_link_name
    if inside_entity.type == "inserter" then
        inside_link_name  = "mythos-linked-" .. outside_entity.name
    else
        inside_link_name  = "mythos-linked-" .. inside_entity.name
    end
    if outside_entity.type == "inserter" then
        outside_link_name = "mythos-linked-" .. inside_entity.name
    else
        outside_link_name = "mythos-linked-" .. outside_entity.name
    end

    if not prototypes.entity[inside_link_name] or not prototypes.entity[outside_link_name] then
        return nil
    end

    local outside_pos = mythos_data.outside_pos
    local outside_link_pos = {
        x = outside_pos.x + cpos.outside_x - cpos.indicator_dx,
        y = outside_pos.y + cpos.outside_y - cpos.indicator_dy,
    }
    local outside_link = outside_entity.surface.create_entity {
        name                     = outside_link_name,
        position                 = outside_link_pos,
        create_build_effect_smoke = false,
        raise_built              = false,
    } or outside_entity.surface.find_entity(outside_link_name, outside_link_pos)
    if not outside_link then return nil end
    outside_link.destructible = false
    outside_link.force = outside_entity.force_index

    local inside_surface = game.get_surface(mythos_data.surface_name)
    if not inside_surface then return nil end

    local inside_link = inside_surface.create_entity {
        name                     = inside_link_name,
        position                 = {
            x = cpos.inside_x + cpos.indicator_dx,
            y = cpos.inside_y + cpos.indicator_dy,
        },
        create_build_effect_smoke = false,
        raise_built              = false,
        force                    = inside_entity.force,
    }
    if not inside_link then
        outside_link.destroy()
        return nil
    end
    inside_link.destructible = false

    -- Wire them together
    local from_link, to_link, facing
    if conn_facing == cpos.direction_in then
        -- Flow: outside → inside
        from_link = outside_link
        to_link   = inside_link
        facing    = cpos.direction_in
    else
        -- Flow: inside → outside
        from_link = inside_link
        to_link   = outside_link
        facing    = cpos.direction_out
    end

    from_link.linked_belt_type = "input"
    to_link.linked_belt_type   = "output"
    to_link.connect_linked_belts(from_link)

    local from_dir = get_entity_direction(
        conn_facing == cpos.direction_in and outside_entity or inside_entity
    )
    from_link.direction = from_dir
    to_link.direction   = from_dir

    return {
        from_link        = from_link,
        to_link          = to_link,
        outside_entity   = outside_entity,
        inside_entity    = inside_entity,
        facing           = facing,
        cid              = cpos.id,
    }
end

-- Attempt to establish a connection at one cpos for a given mythos instance.
-- Does nothing if a connection already exists there.
local function try_init_connection(uid, mythos_data, cpos)
    mythos_data.connections = mythos_data.connections or {}
    if mythos_data.connections[cpos.id] then return end  -- already connected

    local building = mythos_data.entity
    if not (building and building.valid) then return end

    local outside_surface = building.surface
    local outside_pos     = mythos_data.outside_pos

    local outside_entities = outside_surface.find_entities_filtered {
        position = {outside_pos.x + cpos.outside_x, outside_pos.y + cpos.outside_y},
        force    = building.force,
    }
    if not outside_entities or not outside_entities[1] then return end

    local inside_surface = game.get_surface(mythos_data.surface_name)
    if not inside_surface then return end

    local inside_entities = inside_surface.find_entities_filtered {
        position = {cpos.inside_x, cpos.inside_y},
    }
    if not inside_entities or not inside_entities[1] then return end

    for _, oe in pairs(outside_entities) do
        if not BELT_ENTITY_TYPES[oe.type] then goto next_outside end
        for _, ie in pairs(inside_entities) do
            if not BELT_ENTITY_TYPES[ie.type] then goto next_inside end
            -- Types must match for a valid connection
            if oe.type ~= ie.type and
               not (oe.type == "inserter" or ie.type == "inserter") then
                goto next_inside
            end

            local conn = connect_belt_pair(mythos_data, cpos, oe, ie)
            if conn then
                mythos_data.connections[cpos.id] = conn
                return
            end
            ::next_inside::
        end
        ::next_outside::
    end
end

-- Remove and clean up a single connection slot.
local function drop_connection(mythos_data, cid)
    local conn = mythos_data.connections and mythos_data.connections[cid]
    if not conn then return end
    destroy_connection(conn)
    mythos_data.connections[cid] = nil
end

-- Re-evaluate one connection slot: destroy it if either endpoint is gone or
-- has rotated incompatibly, then try to re-establish it.
local function recheck_connection(uid, mythos_data, cpos)
    local conn = mythos_data.connections and mythos_data.connections[cpos.id]
    if conn then
        local still_valid = conn.from_link.valid and conn.to_link.valid
                         and conn.outside_entity.valid and conn.inside_entity.valid
        if still_valid then
            local facing = get_conn_facing(
                conn.outside_entity, conn.inside_entity,
                cpos.direction_out, cpos.direction_in
            )
            still_valid = (facing == conn.facing)
        end
        if not still_valid then
            drop_connection(mythos_data, cpos.id)
        end
    end
    try_init_connection(uid, mythos_data, cpos)
end

-- Recheck every connection point for a mythos instance.
function M.recheck_all(uid)
    local mythos_data = storage.mythos and storage.mythos[uid]
    if not mythos_data then return end
    for _, cpos in pairs(CONNECTIONS) do
        recheck_connection(uid, mythos_data, cpos)
    end
end

-- Destroy all active connections for a mythos instance (called on entity removal).
function M.destroy_all(uid)
    local mythos_data = storage.mythos and storage.mythos[uid]
    if not mythos_data or not mythos_data.connections then return end
    for cid in pairs(mythos_data.connections) do
        drop_connection(mythos_data, cid)
    end
end

-- ---------------------------------------------------------------------------
-- Find which mythos instances (if any) have a connection point at `position`
-- on `surface`, then recheck those points.
-- ---------------------------------------------------------------------------

local function recheck_nearby(surface, position)
    if not storage.mythos then return end
    for uid, mythos_data in pairs(storage.mythos) do
        local building = mythos_data.entity
        if not (building and building.valid) then goto skip end
        if building.surface_index ~= surface.index then goto skip end

        local opos = mythos_data.outside_pos
        for _, cpos in pairs(CONNECTIONS) do
            local cx = opos.x + cpos.outside_x
            local cy = opos.y + cpos.outside_y
            -- Check if the event position is within 0.6 tiles of this connection point
            if math.abs(position.x - cx) < 0.6 and math.abs(position.y - cy) < 0.6 then
                recheck_connection(uid, mythos_data, cpos)
            end
        end
        ::skip::
    end
end

-- Also check entities placed/removed on an *inside* surface
local function recheck_inside_nearby(surface, position)
    if not storage.mythos then return end
    for uid, mythos_data in pairs(storage.mythos) do
        if mythos_data.surface_name ~= surface.name then goto skip end
        for _, cpos in pairs(CONNECTIONS) do
            local cx = cpos.inside_x
            local cy = cpos.inside_y
            if math.abs(position.x - cx) < 0.6 and math.abs(position.y - cy) < 0.6 then
                recheck_connection(uid, mythos_data, cpos)
            end
        end
        ::skip::
    end
end

-- ---------------------------------------------------------------------------
-- Event handlers
-- ---------------------------------------------------------------------------

local function on_entity_changed(event)
    local entity = event.entity
    if not entity.valid then return end
    if not BELT_ENTITY_TYPES[entity.type] then return end

    local surface = entity.surface
    -- Check if this is an inside surface of any mythos pocket
    if surface.name:find("^mythos_") then
        recheck_inside_nearby(surface, entity.position)
    else
        recheck_nearby(surface, entity.position)
    end
end

local BELT_FILTERS = {}
for t in pairs(BELT_ENTITY_TYPES) do
    BELT_FILTERS[#BELT_FILTERS + 1] = {filter = "type", type = t}
end

script.on_event(defines.events.on_built_entity,         on_entity_changed, BELT_FILTERS)
script.on_event(defines.events.on_robot_built_entity,   on_entity_changed, BELT_FILTERS)
script.on_event(defines.events.on_player_mined_entity,  on_entity_changed, BELT_FILTERS)
script.on_event(defines.events.on_robot_mined_entity,   on_entity_changed, BELT_FILTERS)
script.on_event(defines.events.on_entity_died,          on_entity_changed, BELT_FILTERS)

script.on_event(defines.events.on_player_rotated_entity, function(event)
    local entity = event.entity
    if not entity.valid then return end
    if not BELT_ENTITY_TYPES[entity.type] then return end
    local surface = entity.surface
    if surface.name:find("^mythos_") then
        recheck_inside_nearby(surface, entity.position)
    else
        recheck_nearby(surface, entity.position)
    end
end)

return M
