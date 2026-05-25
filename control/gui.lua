local connections     = require("control.connections")

local HUD_NAME        = "mythos_hud"
local ENTITY_GUI_NAME = "mythos_entity_gui"

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
        close_entity_gui_for_unit(unit_number)
        storage.mythos_entities[unit_number] = nil
        entity.destroy()
    else
        destroy_icon_render(uid)
    end

    -- 5. Wipe all storage for this uid
    storage.mythos[uid] = nil
end

-- ---------------------------------------------------------------------------
-- Entity GUI  (opens on right-click; shows icon picker + Enter button)
-- ---------------------------------------------------------------------------

local function get_uid_for_player_gui(player_index)
    local unit_number = storage.player_gui_entity and storage.player_gui_entity[player_index]
    if not unit_number then return nil end
    return storage.mythos_entities and storage.mythos_entities[unit_number]
end

local function open_entity_gui(player, entity, uid)
    local old = player.gui.screen[ENTITY_GUI_NAME]
    if old and old.valid then old.destroy() end

    storage.player_gui_entity = storage.player_gui_entity or {}
    storage.player_gui_entity[player.index] = entity.unit_number

    local frame = player.gui.screen.add {
        type      = "frame",
        name      = ENTITY_GUI_NAME,
        caption   = "Pocket Dimension",
        direction = "vertical",
    }
    frame.auto_center = true

    -- Icon picker row
    local row = frame.add {type = "flow", direction = "horizontal"}
    row.style.vertical_align     = "center"
    row.style.horizontal_spacing = 8
    row.add {type = "label", caption = "Icon:"}
    local picker = row.add {
        type      = "choose-elem-button",
        name      = "mythos_icon_picker",
        elem_type = "signal",
    }
    local icon = storage.mythos[uid] and storage.mythos[uid].icon
    if icon then picker.elem_value = icon end

    -- Buttons row: Enter + Delete
    local btns = frame.add {type = "flow", direction = "horizontal"}
    btns.style.top_margin         = 8
    btns.style.horizontal_spacing = 8
    btns.add {
        type    = "button",
        name    = "mythos_enter_btn",
        caption = "Enter",
        style   = "confirm_button",
    }
    btns.add {
        type    = "sprite-button",
        name    = "mythos_delete_btn",
        sprite  = "utility/trash",
        tooltip = "Permanently delete this pocket dimension and everything inside it. This cannot be undone.",
        style   = "tool_button",
    }

    player.opened = frame  -- Escape closes it
end

local function close_entity_gui(player)
    local frame = player.gui.screen[ENTITY_GUI_NAME]
    if frame and frame.valid then frame.destroy() end
    storage.player_gui_entity = storage.player_gui_entity or {}
    storage.player_gui_entity[player.index] = nil
end

-- Close the entity GUI for every player who currently has `unit_number` open.
-- Called from surface.lua when the entity is mined or destroyed.
function close_entity_gui_for_unit(unit_number)
    if not storage.player_gui_entity then return end
    for player_index, open_unit in pairs(storage.player_gui_entity) do
        if open_unit == unit_number then
            local player = game.players[player_index]
            if player and player.valid then close_entity_gui(player) end
        end
    end
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

-- Right-click entity → open config GUI (instead of immediately entering)
script.on_event(defines.events.on_gui_opened, function(event)
    if not (event.entity and event.entity.name == "mythos-entity") then return end
    local player = game.players[event.player_index]
    player.opened = nil  -- suppress default container inventory

    storage.mythos_entities = storage.mythos_entities or {}
    local uid = storage.mythos_entities[event.entity.unit_number]
    if uid then open_entity_gui(player, event.entity, uid) end
end)

-- Icon picker changed → persist and redraw
script.on_event(defines.events.on_gui_elem_changed, function(event)
    if event.element.name ~= "mythos_icon_picker" then return end
    local uid = get_uid_for_player_gui(event.player_index)
    if not uid then return end
    local data = storage.mythos[uid]
    if not data then return end
    data.icon = event.element.elem_value  -- nil when cleared
    update_icon_render(uid)
end)

-- Button clicks
script.on_event(defines.events.on_gui_click, function(event)
    local player = game.players[event.player_index]
    if event.element.name == "mythos_enter_btn" then
        local uid = get_uid_for_player_gui(player.index)
        close_entity_gui(player)
        if uid then enter_pocket(player, uid) end
    elseif event.element.name == "mythos_delete_btn" then
        local uid = get_uid_for_player_gui(player.index)
        close_entity_gui(player)  -- close for the clicking player first
        if uid then destroy_mythos_recursive(uid) end
    elseif event.element.name == "mythos_exit_btn" then
        exit_pocket(player)
    end
end)

-- Escape
script.on_event(defines.events.on_gui_closed, function(event)
    if not event.element then return end
    if event.element.name == ENTITY_GUI_NAME then
        close_entity_gui(game.players[event.player_index])
    elseif event.element.name == HUD_NAME then
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
