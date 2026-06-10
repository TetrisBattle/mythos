local Snapshot = require("script.clone.snapshot")

local Blueprint = {}

local PASTE_TTL = 3600

local function isRobotBuiltEvent(event)
	return event and event.name == defines.events.on_robot_built_entity
end

function Blueprint.setPendingPaste(player_index, saved_ids)
	storage.mythos_pending_paste = {
		ids          = saved_ids,
		expires_tick = game.tick + PASTE_TTL,
		player_index = player_index,
	}
end

function Blueprint.pendingPasteAllowed(event)
	local pending = storage.mythos_pending_paste
	if not pending then return false end
	if game.tick > pending.expires_tick then
		storage.mythos_pending_paste = nil
		return false
	end
	local ids = pending.ids
	if not ids or #ids == 0 then
		storage.mythos_pending_paste = nil
		return false
	end
	local built_by = event and event.player_index
	if pending.player_index and built_by and pending.player_index ~= built_by
			and not isRobotBuiltEvent(event) then
		return false
	end
	return true
end

function Blueprint.consumePendingPaste(event)
	if not Blueprint.pendingPasteAllowed(event) then return nil end
	return table.remove(storage.mythos_pending_paste.ids, 1)
end

function Blueprint.discardPendingPasteSlot(event)
	Blueprint.consumePendingPaste(event)
end

function Blueprint.clearPendingPaste(player_index)
	if not storage.mythos_pending_paste then return end
	local pending = storage.mythos_pending_paste
	if not player_index or not pending.player_index or pending.player_index == player_index then
		storage.mythos_pending_paste = nil
	end
end

local function resolveWritableBlueprint(event)
	local player = event.player_index and game.get_player(event.player_index)
	if player then
		if player.blueprint_to_setup and player.blueprint_to_setup.valid_for_read then
			return player.blueprint_to_setup
		end
		if player.cursor_stack and player.cursor_stack.valid_for_read then
			return player.cursor_stack
		end
	end
	if event.stack and event.stack.valid_for_read then
		return event.stack
	end
	return event.record
end

local function getBlueprintEntities(bp)
	if not bp then return nil end
	if bp.get_blueprint_entities then
		local ok, entities = pcall(function() return bp.get_blueprint_entities() end)
		if ok and entities then return entities end
	end
	return nil
end

local function tagBlueprintEntity(bp, entity_number, saved_id)
	if not (bp and entity_number and saved_id) then return false end
	if bp.set_blueprint_entity_tag then
		bp.set_blueprint_entity_tag(entity_number, "mythos_snapshot", saved_id)
		bp.set_blueprint_entity_tag(entity_number, "saved_id", saved_id)
		return true
	end
	return false
end

local function tagBlueprintEntitiesFallback(bp, entities, entries, mapping)
	if not (bp and entities and entries) then return end

	local by_source = {}
	for _, entry in ipairs(entries) do
		if entry.source and entry.saved_id then
			by_source[entry.source.unit_number] = entry.saved_id
		end
	end

	local changed = false
	for _, bp_entity in pairs(entities) do
		if bp_entity.name == "mythos" then
			local saved_id
			if mapping then
				local source = mapping[bp_entity.entity_number]
				if source and source.valid then
					saved_id = by_source[source.unit_number]
				end
			end
			if not saved_id then
				for _, entry in ipairs(entries) do
					if entry.index == bp_entity.entity_number then
						saved_id = entry.saved_id
						break
					end
				end
			end
			if saved_id then
				bp_entity.tags = bp_entity.tags or {}
				bp_entity.tags.mythos_snapshot = saved_id
				bp_entity.tags.saved_id = saved_id
				changed = true
			end
		end
	end

	if changed and bp.set_blueprint_entities then
		bp.set_blueprint_entities(entities)
	end
end

local function applyBlueprintSnapshotTags(event, entries)
	local bp = resolveWritableBlueprint(event)
	if not bp then return end

	local entities = getBlueprintEntities(bp)
	if not entities then return end

	local mapping
	if event.mapping and event.mapping.valid then
		local ok, map = pcall(function() return event.mapping.get() end)
		if ok then mapping = map end
	end

	local tagged = false
	if mapping and bp.set_blueprint_entity_tag then
		for _, bp_entity in pairs(entities) do
			if bp_entity.name == "mythos" then
				local source = mapping[bp_entity.entity_number]
				if source and source.valid then
					for _, entry in ipairs(entries) do
						if entry.source == source and entry.saved_id then
							if tagBlueprintEntity(bp, bp_entity.entity_number, entry.saved_id) then
								tagged = true
							end
							break
						end
					end
				end
			end
		end
	end

	if not tagged then
		tagBlueprintEntitiesFallback(bp, entities, entries, mapping)
	end
end

local function collectBlueprintMythosSources(event)
	local entries = {}
	local seen = {}

	local function add(index, source)
		if not (source and source.valid and source.name == "mythos") then return end
		if seen[source.unit_number] then return end
		seen[source.unit_number] = true
		entries[#entries + 1] = { index = index, source = source }
	end

	local mapping = event.mapping
	if mapping and mapping.valid then
		local ok, map = pcall(function() return mapping.get() end)
		if ok and map then
			for bp_index, source in pairs(map) do
				add(bp_index, source)
			end
		end
	end

	if #entries == 0 and event.surface and event.surface.valid and event.area then
		local area = event.area
		local found = event.surface.find_entities_filtered{
			name = "mythos",
			area = {
				{ area.left_top.x, area.left_top.y },
				{ area.right_bottom.x, area.right_bottom.y },
			},
		}
		for i, source in ipairs(found) do
			add(i, source)
		end
	end

	return entries
end

function Blueprint.onPlayerSetupBlueprint(Mythos, event, snapshotForBlueprint)
	local entries = collectBlueprintMythosSources(event)
	if #entries == 0 then return end

	table.sort(entries, function(a, b)
		return a.index < b.index
	end)

	local snapshot_by_source = {}
	local saved_ids = {}
	for _, entry in ipairs(entries) do
		local unit_number = entry.source.unit_number
		local saved_id = snapshot_by_source[unit_number]
		if not saved_id then
			saved_id = (snapshotForBlueprint or Snapshot.snapshotForBlueprint)(Mythos, entry.source)
			if saved_id then
				snapshot_by_source[unit_number] = saved_id
			end
		end
		entry.saved_id = saved_id
		if saved_id then
			saved_ids[#saved_ids + 1] = saved_id
		end
	end
	if #saved_ids == 0 then return end

	Blueprint.setPendingPaste(event.player_index, saved_ids)
	applyBlueprintSnapshotTags(event, entries)
end

return Blueprint
