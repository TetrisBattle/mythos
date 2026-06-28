-- Registers built/removed event handlers for all relevant Factorio events.
local function appendIfPresent(events, event)
	if event then
		events[#events + 1] = event
	end
	return events
end

local function entityBuiltEvents()
	return appendIfPresent({
		defines.events.on_built_entity,
		defines.events.on_robot_built_entity,
		defines.events.script_raised_built,
		defines.events.script_raised_revive,
	}, defines.events.on_space_platform_built_entity)
end

local function entityRemovedEvents()
	return appendIfPresent({
		defines.events.on_player_mined_entity,
		defines.events.on_robot_mined_entity,
		defines.events.on_entity_died,
		defines.events.script_raised_destroy,
	}, defines.events.on_space_platform_mined_entity)
end

local function registerEach(events, handler)
	for _, event in ipairs(events) do
		script.on_event(event, handler)
	end
end

local function registerEvents(onBuilt, onRemoved)
	registerEach(entityBuiltEvents(), onBuilt)
	registerEach(entityRemovedEvents(), onRemoved)
end

return registerEvents
