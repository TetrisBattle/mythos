local registerEvents = require("script.registerEvents")
local Mythos         = require("script.Mythos")

script.on_init(function()
	storage.mythoi = {}
end)

script.on_load(function()
	-- Metatables are not saved; restore them so stored states can call methods.
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
end)

-- Core entity lifecycle events (build / remove).
registerEvents(Mythos.onEntityBuilt, Mythos.onEntityRemoved)

-- Tick handlers: belt transport + ghost building (fast), logistic requests + deletion retries (slow).
script.on_nth_tick(6,  Mythos.onNthTick)
script.on_nth_tick(60, Mythos.onSlowTick)

-- Dimension-deletion: auto-mine marked entities into the mythos chest.
script.on_event(defines.events.on_marked_for_deconstruction,  Mythos.onMarkedForDeconstruction)
script.on_event(defines.events.on_cancelled_deconstruction,   Mythos.onCancelledDeconstruction)

-- Opens the pocket dimension as a remote-view when the player uses the keybind.
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
