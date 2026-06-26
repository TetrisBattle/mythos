-- Registers built/removed event handlers for all relevant Factorio events.
local function registerEvents(onBuilt, onRemoved)
	local builtEvents = {
		defines.events.on_built_entity,
		defines.events.on_robot_built_entity,
		defines.events.script_raised_built,
		defines.events.script_raised_revive,
	}
	if defines.events.on_space_platform_built_entity then
		builtEvents[#builtEvents + 1] = defines.events.on_space_platform_built_entity
	end
	for _, event in pairs(builtEvents) do
		script.on_event(event, onBuilt)
	end

	local removedEvents = {
		defines.events.on_player_mined_entity,
		defines.events.on_robot_mined_entity,
		defines.events.on_entity_died,
		defines.events.script_raised_destroy,
	}
	if defines.events.on_space_platform_mined_entity then
		removedEvents[#removedEvents + 1] = defines.events.on_space_platform_mined_entity
	end
	for _, event in pairs(removedEvents) do
		script.on_event(event, onRemoved)
	end
end

return registerEvents
