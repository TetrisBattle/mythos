local connections = require("control.connections")

function get_or_create_surface(uid)
  local name = "mythos_" .. uid
  local existing = game.get_surface(name)
  if existing then return existing end

  -- width=2/height=2 suppresses terrain generation
  local surface = game.create_surface(name, {width = 2, height = 2})
  surface.peaceful_mode = true
  surface.min_brightness = 1

  -- Mark chunks as generated so the camera can render them (no terrain gen needed)
  -- Our 32x32 area spans chunk coords -1 to 0 in both axes; use -2..2 to be safe
  for cx = -2, 2 do
    for cy = -2, 2 do
      surface.set_chunk_generated_status({cx, cy}, defines.chunk_generated_status.entities)
    end
  end

  -- Fill the 32x32 area with concrete tiles
  local tiles = {}
  for x = -16, 15 do
    for y = -16, 15 do
      tiles[#tiles + 1] = {name = "concrete", position = {x, y}}
    end
  end
  surface.set_tiles(tiles)

  -- Draw one yellow arrow per side, centered between the two ports on that side,
  -- pointing outward (direction_out).  The four midpoints are:
  --   North {0, -14.5}  South {0, 14.5}  East {14.5, 0}  West {-14.5, 0}
  local side_centers = {
    {x =    0, y = -14.5, dir_out = defines.direction.north},
    {x =    0, y =  14.5, dir_out = defines.direction.south},
    {x =  14.5, y =    0, dir_out = defines.direction.east},
    {x = -14.5, y =    0, dir_out = defines.direction.west},
  }
  for _, sc in ipairs(side_centers) do
    rendering.draw_sprite {
      sprite      = "mythos-port-indicator",
      target      = {x = sc.x, y = sc.y},
      surface     = surface,
      orientation = sc.dir_out / 16,
      x_scale     = 1.5,
      y_scale     = 1.5,
    }
  end

  return surface
end

-- Assign UID the moment a Mythos item is crafted
script.on_event(defines.events.on_player_crafted_item, function(event)
  local stack = event.item_stack
  if stack and stack.valid_for_read and stack.name == "mythos" then
    if not get_uid(stack) then
      assign_uid(stack)
    end
  end
end)

-- When the entity is placed: store unit_number → uid mapping
script.on_event(defines.events.on_built_entity, function(event)
  local entity = event.entity
  local uid = event.tags and event.tags.uid
  if not uid then
    -- No UID (e.g., spawned via console); generate one now
    storage.mythos_uid_counter = (storage.mythos_uid_counter or 0) + 1
    uid = tostring(storage.mythos_uid_counter)
    storage.mythos = storage.mythos or {}
    storage.mythos[uid] = {uid = uid, surface_name = "mythos_" .. uid}
  end
  storage.mythos_entities = storage.mythos_entities or {}
  storage.mythos_entities[entity.unit_number] = uid
  -- Store entity reference and outside position for the connection system
  local m = storage.mythos[uid]
  if m then
    m.entity      = entity
    m.outside_pos = {x = entity.position.x, y = entity.position.y}
    m.connections = m.connections or {}
  end
end, {{filter = "name", name = "mythos-entity"}})

-- When mined by a player: restore uid tags on the returned item
script.on_event(defines.events.on_player_mined_entity, function(event)
  storage.mythos_entities = storage.mythos_entities or {}
  local uid = storage.mythos_entities[event.entity.unit_number]
  if not uid then return end
  connections.destroy_all(uid)
  destroy_icon_render(uid)
  storage.mythos_entities[event.entity.unit_number] = nil

  local inv = game.players[event.player_index].get_main_inventory()
  for i = 1, #inv do
    local s = inv[i]
    if s.valid_for_read and s.name == "mythos" then
      local t = s.tags
      if not t or not t.uid then
        s.tags = {uid = uid}
        break
      end
    end
  end
end, {{filter = "name", name = "mythos-entity"}})

-- When destroyed (died): just clean up the mapping
script.on_event(defines.events.on_entity_died, function(event)
  storage.mythos_entities = storage.mythos_entities or {}
  local uid = storage.mythos_entities[event.entity.unit_number]
  if uid then
    connections.destroy_all(uid)
    destroy_icon_render(uid)
  end
  storage.mythos_entities[event.entity.unit_number] = nil
end, {{filter = "name", name = "mythos-entity"}})
