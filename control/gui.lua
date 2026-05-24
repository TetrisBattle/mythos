local HUD_NAME = "mythos_hud"

local function show_exit_hud(player)
  local screen = player.gui.screen
  if screen[HUD_NAME] then screen[HUD_NAME].destroy() end
  local frame = screen.add{type = "frame", name = HUD_NAME, direction = "horizontal"}
  frame.location = {10, 10}
  frame.style.padding = 4
  frame.add{type = "label", style = "bold_label", caption = "Pocket Dimension"}
  frame.add{type = "button", name = "mythos_exit_btn", caption = "Exit"}
  player.opened = frame  -- allows Escape to close it
end

local function hide_exit_hud(player)
  local elem = player.gui.screen[HUD_NAME]
  if elem and elem.valid then elem.destroy() end
end

local function enter_pocket(player, uid)
  storage.player_in_mythos = storage.player_in_mythos or {}
  if storage.player_in_mythos[player.index] then return end

  local surface = get_or_create_surface(uid)
  if not surface then return end

  local character = player.character  -- save before switching controller

  storage.player_in_mythos[player.index] = {
    uid = uid,
    return_surface_index = player.surface.index,
    return_position = {x = player.position.x, y = player.position.y},
    character = character,
  }

  player.set_controller({type = defines.controllers.god})
  player.teleport({0, 0}, surface)
  show_exit_hud(player)
end

local function exit_pocket(player)
  storage.player_in_mythos = storage.player_in_mythos or {}
  local data = storage.player_in_mythos[player.index]
  if not data then return end

  -- Clear tracking BEFORE teleporting (prevents re-entry on surface-changed event)
  storage.player_in_mythos[player.index] = nil
  hide_exit_hud(player)

  if data.character and data.character.valid then
    -- Must be on the same surface as the character before calling set_controller
    local return_surface = game.get_surface(data.return_surface_index)
    if return_surface then
      player.teleport(data.return_position, return_surface)
    end
    player.set_controller({type = defines.controllers.character, character = data.character})
  else
    -- Character died while inside; just return as god and let the player respawn normally
    local return_surface = game.get_surface(data.return_surface_index)
    if return_surface then
      player.teleport(data.return_position, return_surface)
    end
  end
end

-- Right-click the placed Mythos entity → enter pocket dimension
script.on_event(defines.events.on_gui_opened, function(event)
  if not (event.entity and event.entity.name == "mythos-entity") then return end
  local player = game.players[event.player_index]
  player.opened = nil  -- Close the default container GUI immediately

  storage.mythos_entities = storage.mythos_entities or {}
  local uid = storage.mythos_entities[event.entity.unit_number]
  if uid then
    enter_pocket(player, uid)
  end
end)

-- Exit button
script.on_event(defines.events.on_gui_click, function(event)
  if event.element.name == "mythos_exit_btn" then
    exit_pocket(game.players[event.player_index])
  end
end)

-- Escape key closes player.opened, which fires on_gui_closed
script.on_event(defines.events.on_gui_closed, function(event)
  if event.element and event.element.name == HUD_NAME then
    exit_pocket(game.players[event.player_index])
  end
end)

-- Safety: clean up if player is moved off the pocket surface by external means
script.on_event(defines.events.on_player_changed_surface, function(event)
  local player = game.players[event.player_index]
  storage.player_in_mythos = storage.player_in_mythos or {}
  if not storage.player_in_mythos[player.index] then return end
  if not player.surface.name:find("^mythos_") then
    hide_exit_hud(player)
    storage.player_in_mythos[player.index] = nil
  end
end)
