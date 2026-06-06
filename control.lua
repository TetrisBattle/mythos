local registerEvents = require("script.registerEvents")
local Mythos         = require("script.Mythos")
local IconGui        = require("script.iconGui")

-- Rendering objects are not saved; redraw custom icons after load or mod update.
local function restoreIconRenders()
	for _, state in pairs(storage.mythoi) do
		if state.entity and state.entity.valid and state.custom_icons then
			state.icon_renders = nil
			for idx, signal in pairs(state.custom_icons) do
				state:setIcon(idx, signal)
			end
		end
	end
end

script.on_init(function()
	storage.mythoi                = {}
	storage.saved_dimensions      = {}
	storage.pending_player_restore = {}
end)

script.on_load(function()
	-- Metatables are not saved; restore them so stored states can call methods.
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
end)

script.on_configuration_changed(restoreIconRenders)

-- Core entity lifecycle events (build / remove).
registerEvents(Mythos.onEntityBuilt, Mythos.onEntityRemoved)

-- Tick handlers: belt transport + ghost building (fast), logistic requests + deletion retries (slow).
script.on_nth_tick(6,   Mythos.onNthTick)
script.on_nth_tick(60,  Mythos.onSlowTick)

-- Solar sync: re-copies outer surface solar multiplier to pocket dimension
-- every 5 seconds.  Keeps solar panel output correct if the mythos moves
-- between surfaces (e.g., a space platform travelling between planets).
script.on_nth_tick(300, function()
	for _, state in pairs(storage.mythoi) do
		if state.entity.valid then
			state:syncSolar()
		end
	end
end)

-- Dimension-deletion: auto-mine marked entities into the mythos chest.
script.on_event(defines.events.on_marked_for_deconstruction,  Mythos.onMarkedForDeconstruction)
script.on_event(defines.events.on_cancelled_deconstruction,   Mythos.onCancelledDeconstruction)

-- Cache saved_id when player picks up a mythos-with-contents item so it can
-- be retrieved in onEntityBuilt (which fires before the cursor is consumed).
script.on_event(defines.events.on_player_cursor_stack_changed, Mythos.onCursorChanged)

-- Icon panel: open alongside the container GUI, close when it closes,
-- and handle signal selection.  The icon is manually set by the player only;
-- it is never derived automatically from chest contents.
script.on_event(defines.events.on_gui_opened, function(event)
	if event.gui_type ~= defines.gui_type.entity then return end
	local entity = event.entity
	if not (entity and entity.valid and entity.name == "mythos") then return end
	local player = game.get_player(event.player_index)
	if player then IconGui.open(player, entity) end
end)

script.on_event(defines.events.on_gui_closed, function(event)
	if event.gui_type ~= defines.gui_type.entity then return end
	local entity = event.entity
	if not (entity and entity.valid and entity.name == "mythos") then return end
	local player = game.get_player(event.player_index)
	if player then IconGui.close(player) end
end)

script.on_event(defines.events.on_gui_elem_changed, IconGui.onElemChanged)

-- Opens the pocket dimension as a remote-view when the player uses the keybind.
script.on_event("mythos-open-dimension", function(event)
	local player = game.get_player((event --[[@as EventData.CustomInputEvent]]).player_index)
	if not player then return end
	local ct = player.controller_type
	if ct ~= defines.controllers.character and ct ~= defines.controllers.remote then return end

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
