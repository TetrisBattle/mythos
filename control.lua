local registerEvents = require("script.registerEvents")
local Mythos = require("script.Mythos")

script.on_init(function()
	storage.mythoi = {}
end)

script.on_load(function()
	-- Metatables are not saved; restore them so methods work after a load.
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
end)

registerEvents(Mythos.onEntityBuilt, Mythos.onEntityRemoved)

script.on_event("mythos-open-dimension", function(event)
	local player = game.get_player((event --[[@as EventData.CustomInputEvent]]).player_index)
	if not player then return end
	if player.controller_type ~= defines.controllers.character then return end

	local entity = player.selected
	if not (entity and entity.valid and entity.name == "mythos") then return end

	local state = storage.mythoi[entity.unit_number]
	if not (state and state.inside_surface and state.inside_surface.valid) then return end

	player.set_controller{
		type     = defines.controllers.remote,
		position = { x = state.inside_x, y = state.inside_y },
		surface  = state.inside_surface,
	}
end)
