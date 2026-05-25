local connections     = require("control.connections")

local HUD_NAME = "mythos_hud"

-- ---------------------------------------------------------------------------
-- Icon rendering
-- ---------------------------------------------------------------------------

local SPRITE_PREFIX = {virtual = "virtual-signal"}

local function icon_to_sprite(icon)
    if not icon then return nil end
    return (SPRITE_PREFIX[icon.type] or icon.type) .. "/" .. icon.name
end

local function update_icon_render(uid)
    local data = storage.mythos and storage.mythos[uid]
    if not data then return end

    -- Tear down previous render object
    if data.icon_render_id then
        local obj = rendering.get_object_by_id(data.icon_render_id)
        if obj and obj.valid then obj.destroy() end
        data.icon_render_id = nil
    end

    local entity = data.entity
    if not (entity and entity.valid) then return end
    if not data.icon then return end

    local sprite = icon_to_sprite(data.icon)
    if not sprite or not helpers.is_valid_sprite_path(sprite) then return end

    local obj = rendering.draw_sprite {
        sprite       = sprite,
        target       = {entity = entity, offset = {0, -0.75}},
        surface      = entity.surface,
        render_layer = "entity-info-icon",
        x_scale      = 1.5,
        y_scale      = 1.5,
    }
    data.icon_render_id = obj.id
end

-- Called from surface.lua when the entity is removed.
function destroy_icon_render(uid)
    local data = storage.mythos and storage.mythos[uid]
    if not data or not data.icon_render_id then return end
    local obj = rendering.get_object_by_id(data.icon_render_id)
    if obj and obj.valid then obj.destroy() end
    data.icon_render_id = nil
end

-- ---------------------------------------------------------------------------
-- Recursive delete: destroys a mythos entity, its pocket surface, all nested
-- mythos entities inside, and any players are ejected first.
-- ---------------------------------------------------------------------------

local function destroy_mythos_recursive(uid)
    local data = storage.mythos and storage.mythos[uid]
    if not data then return end

    -- 1. Eject any players currently inside this pocket dimension
    for player_index, pocket_data in pairs(storage.player_in_mythos or {}) do
        if pocket_data.uid == uid then
            local player = game.players[player_index]
            if player and player.valid then
                exit_pocket(player)
            end
        end
    end

    -- 2. Recursively destroy nested mythos entities on the pocket surface
    local surface = game.get_surface("mythos_" .. uid)
    if surface then
        local nested = surface.find_entities_filtered {name = "mythos-entity"}
        for _, nested_entity in ipairs(nested) do
            local nested_uid = storage.mythos_entities and storage.mythos_entities[nested_entity.unit_number]
            if nested_uid then
                storage.mythos_entities[nested_entity.unit_number] = nil  -- prevent double-process
                destroy_mythos_recursive(nested_uid)
            end
        end
        -- 3. Delete the pocket surface; any remaining entities are wiped by Factorio
        game.delete_surface(surface)
    end

    -- 4. Destroy the outer entity (no item drop)
    local entity = data.entity
    if entity and entity.valid then
        local unit_number = entity.unit_number
        connections.destroy_all(uid)
        destroy_icon_render(uid)
        storage.mythos_entities[unit_number] = nil
        entity.destroy()
    else
        destroy_icon_render(uid)
    end

    -- 5. Wipe all storage for this uid
    storage.mythos[uid] = nil
end

-- ---------------------------------------------------------------------------
-- Exit HUD  (shown while the player is inside a pocket dimension)
-- ---------------------------------------------------------------------------

local function show_exit_hud(player)
    local screen = player.gui.screen
    if screen[HUD_NAME] then screen[HUD_NAME].destroy() end
    local frame = screen.add {type = "frame", name = HUD_NAME, direction = "horizontal"}
    frame.location      = {10, 10}
    frame.style.padding = 4
    frame.add {type = "label", style = "bold_label", caption = "Pocket Dimension"}
    frame.add {type = "button", name = "mythos_exit_btn", caption = "Exit"}
    player.opened = frame
end

local function hide_exit_hud(player)
    local elem = player.gui.screen[HUD_NAME]
    if elem and elem.valid then elem.destroy() end
end

-- ---------------------------------------------------------------------------
-- Pocket travel
-- ---------------------------------------------------------------------------

local function enter_pocket(player, uid)
    storage.player_in_mythos = storage.player_in_mythos or {}
    if storage.player_in_mythos[player.index] then return end

    local surface = get_or_create_surface(uid)
    if not surface then return end

    local character = player.character

    storage.player_in_mythos[player.index] = {
        uid                  = uid,
        return_surface_index = player.surface.index,
        return_position      = {x = player.position.x, y = player.position.y},
        character            = character,
    }

    player.set_controller {type = defines.controllers.god}
    player.teleport({0, 0}, surface)
    show_exit_hud(player)
end

local function exit_pocket(player)
    storage.player_in_mythos = storage.player_in_mythos or {}
    local data = storage.player_in_mythos[player.index]
    if not data then return end

    storage.player_in_mythos[player.index] = nil
    hide_exit_hud(player)

    if data.character and data.character.valid then
        local return_surface = game.get_surface(data.return_surface_index)
        if return_surface then
            player.teleport(data.return_position, return_surface)
        end
        player.set_controller {type = defines.controllers.character, character = data.character}
    else
        local return_surface = game.get_surface(data.return_surface_index)
        if return_surface then
            player.teleport(data.return_position, return_surface)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

-- Right-click the entity → enter the pocket immediately.
-- Also handles the Shift+RMB custom-input once the data stage has been reloaded.
local function try_enter_from_entity(player, entity)
    if not (entity and entity.valid and entity.name == "mythos-entity") then return end
    storage.mythos_entities = storage.mythos_entities or {}
    local uid = storage.mythos_entities[entity.unit_number]
    if uid then enter_pocket(player, uid) end
end

script.on_event(defines.events.on_gui_opened, function(event)
    if not (event.entity and event.entity.name == "mythos-entity") then return end
    local player = game.players[event.player_index]
    player.opened = nil  -- suppress default container inventory
    try_enter_from_entity(player, event.entity)
end)

-- Shift+RMB custom-input (requires a full save-reload after first install).
pcall(script.on_event, "mythos-enter-pocket", function(event)
    local player = game.players[event.player_index]
    try_enter_from_entity(player, player.selected)
end)

-- Exit button click.
script.on_event(defines.events.on_gui_click, function(event)
    if event.element.name == "mythos_exit_btn" then
        exit_pocket(game.players[event.player_index])
    end
end)

-- Escape closes the HUD (exits pocket).
script.on_event(defines.events.on_gui_closed, function(event)
    if event.element and event.element.name == HUD_NAME then
        exit_pocket(game.players[event.player_index])
    end
end)

-- Safety: player teleported off pocket surface by external means
script.on_event(defines.events.on_player_changed_surface, function(event)
    local player = game.players[event.player_index]
    storage.player_in_mythos = storage.player_in_mythos or {}
    if not storage.player_in_mythos[player.index] then return end
    if not player.surface.name:find("^mythos_") then
        hide_exit_hud(player)
        storage.player_in_mythos[player.index] = nil
    end
end)

-- Restore icon renders on entity placement (e.g. player places a previously
-- mined entity that already had an icon saved in its uid data).
script.on_event(defines.events.on_built_entity, function(event)
    local entity = event.entity
    local uid = storage.mythos_entities and storage.mythos_entities[entity.unit_number]
    if uid then update_icon_render(uid) end
end, {{filter = "name", name = "mythos-entity"}})
