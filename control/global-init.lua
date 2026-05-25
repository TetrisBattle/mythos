local function init_globals()
  storage.mythos = storage.mythos or {}
  storage.mythos_uid_counter = storage.mythos_uid_counter or 0
  storage.player_in_mythos = storage.player_in_mythos or {}
  storage.mythos_entities = storage.mythos_entities or {}
  storage.player_gui_entity = storage.player_gui_entity or {}
  -- Per-instance connections table is initialised lazily inside connections.lua,
  -- but we ensure the parent table always exists here.
  for _, data in pairs(storage.mythos) do
    data.connections = data.connections or {}
  end
end

script.on_init(init_globals)
script.on_configuration_changed(init_globals)

function assign_uid(item_stack)
  storage.mythos_uid_counter = storage.mythos_uid_counter + 1
  local uid = tostring(storage.mythos_uid_counter)
  item_stack.tags = {uid = uid}
  storage.mythos[uid] = {uid = uid, surface_name = "mythos_" .. uid}
  return uid
end

function get_uid(item_stack)
  if item_stack and item_stack.valid_for_read and item_stack.name == "mythos" then
    local tags = item_stack.tags
    return tags and tags.uid
  end
  return nil
end
