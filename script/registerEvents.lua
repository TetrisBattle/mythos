-- Registers built/removed event handlers for all relevant Factorio events.
local function registerEvents(onBuilt, onRemoved)
	for _, event in pairs({
		defines.events.on_built_entity,
		defines.events.on_robot_built_entity,
		defines.events.script_raised_built,
		defines.events.script_raised_revive,
	}) do
		script.on_event(event, onBuilt)
	end

	for _, event in pairs({
		defines.events.on_player_mined_entity,
		defines.events.on_robot_mined_entity,
		defines.events.on_entity_died,
		defines.events.script_raised_destroy,
	}) do
		script.on_event(event, onRemoved)
	end
end

return registerEvents
