local registerEvents    = require("script.registerEvents")
local Mythos            = require("script.Mythos")
local IconGui           = require("script.iconGui")
local ResizeGui         = require("script.resizeGui")
local PocketDimension   = require("script.PocketDimension")

-- Module-local flag: on_load must not touch storage (CRC check).
local pending_gate_refresh = false

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

local function removeLegacyWalls()
	for _, state in pairs(storage.mythoi) do
		if state.inside_surface and state.inside_surface.valid then
			PocketDimension.removePerimeterWalls(state.inside_surface)
		end
	end
end

local function refreshExistingDimensionViews()
	for _, state in pairs(storage.mythoi) do
		if state.inside_surface and state.inside_surface.valid then
			state:syncFloorBoundsFromTiles()
			if state.floor_bounds then
				state.inside_x, state.inside_y = PocketDimension.floorCentre(state.floor_bounds)
				PocketDimension.ensureRemoteViewReady(
					state.inside_surface, state.floor_bounds, state.entity.force
				)
			end
		end
	end
end

script.on_init(function()
	storage.mythoi                 = {}
	storage.saved_dimensions       = {}
	storage.pending_player_restore = {}
	storage.viewing                = {}  -- player_index → unit_number while in remote view
	storage.pending_resize_gui     = {}  -- player_index → unit_number, opened next tick
end)

local function scheduleResizeGui(player_index, unit_number)
	storage.pending_resize_gui = storage.pending_resize_gui or {}
	storage.pending_resize_gui[player_index] = unit_number
end

local function tryOpenResizeGui(player_index, unit_number)
	local player = game.get_player(player_index)
	local state = storage.mythoi[unit_number]
	if not (player and state and state.entity.valid) then return end
	if player.controller_type ~= defines.controllers.remote then return end
	if player.surface ~= state.inside_surface then return end
	state:refreshGateRenders()
	ResizeGui.open(player, state)
end

script.on_load(function()
	-- Metatables are not saved; restore them so stored states can call methods.
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
	-- Rendering objects are not saved; redraw on the next tick (on_load cannot modify the world).
	pending_gate_refresh = true
end)

local function refreshAllGateRenders()
	for _, state in pairs(storage.mythoi) do
		if state.slots and state.inside_surface and state.inside_surface.valid then
			state:refreshGateRenders()
		end
	end
end

script.on_configuration_changed(function()
	restoreIconRenders()
	removeLegacyWalls()
	refreshExistingDimensionViews()
	refreshAllGateRenders()
end)

-- Pocket-dimension chunks must never keep generated grass tiles.
script.on_event(defines.events.on_chunk_generated, function(event)
	local surface = event.surface
	local unit_num = tonumber(surface.name:match("^mythos%-dimension%-(%d+)$"))
	if not unit_num then return end

	storage.mythoi = storage.mythoi or {}
	local state = storage.mythoi[unit_num]
	local bounds = state and state.floor_bounds
	if not bounds then
		bounds = PocketDimension.inferFloorBounds(surface)
	end

	PocketDimension.voidFillGeneratedChunk(surface, bounds, event.area)
	surface.set_chunk_generated_status(
		event.position,
		defines.chunk_generated_status.entities
	)
end)

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

-- Re-anchor the resize panel when the remote-view controller GUI appears.
script.on_event(defines.events.on_gui_opened, function(event)
	if event.gui_type ~= defines.gui_type.controller then return end
	storage.viewing = storage.viewing or {}
	local unit_number = storage.viewing[event.player_index]
	if not unit_number then return end
	local player = game.get_player(event.player_index)
	if not player or player.controller_type ~= defines.controllers.remote then return end
	scheduleResizeGui(event.player_index, unit_number)
end)

-- Opens the pocket dimension as a remote-view when the player uses the keybind.
-- Also opens the resize GUI in the bottom-right corner.
script.on_event("mythos-open-dimension", function(event)
	local player = game.get_player((event --[[@as EventData.CustomInputEvent]]).player_index)
	if not player then return end
	local ct = player.controller_type
	if ct ~= defines.controllers.character and ct ~= defines.controllers.remote then return end

	local entity = player.selected
	if not (entity and entity.valid and entity.name == "mythos") then return end

	local state = storage.mythoi[entity.unit_number]
	if not (state and state.inside_surface and state.inside_surface.valid) then return end

	storage.viewing = storage.viewing or {}
	storage.viewing[event.player_index] = entity.unit_number

	player.set_controller{
		type     = defines.controllers.remote,
		position = { x = state.inside_x, y = state.inside_y },
		surface  = state.inside_surface,
	}

	-- Defer one tick: controller / surface are not always ready synchronously.
	scheduleResizeGui(event.player_index, entity.unit_number)
end)

-- Open deferred resize panels once remote view has finished initialising.
script.on_nth_tick(1, function()
	if pending_gate_refresh then
		pending_gate_refresh = false
		refreshAllGateRenders()
		refreshExistingDimensionViews()
	end
	if not storage.pending_resize_gui then return end
	for player_index, unit_number in pairs(storage.pending_resize_gui) do
		tryOpenResizeGui(player_index, unit_number)
		storage.pending_resize_gui[player_index] = nil
	end
end)

-- Close the resize GUI when the player leaves remote-view mode.
script.on_event(defines.events.on_player_controller_changed, function(event)
	local player_index = event.player_index
	storage.viewing = storage.viewing or {}
	local unit_number = storage.viewing[player_index]
	if not unit_number then return end

	local player = game.get_player(player_index)
	if not player then return end

	if player.controller_type ~= defines.controllers.remote then
		ResizeGui.close(player)
		storage.viewing[player_index] = nil
		return
	end

	local state = storage.mythoi[unit_number]
	if not (state and state.inside_surface and state.inside_surface.valid) then
		ResizeGui.close(player)
		storage.viewing[player_index] = nil
		return
	end

	if player.surface ~= state.inside_surface then
		ResizeGui.close(player)
		storage.viewing[player_index] = nil
		return
	end

	scheduleResizeGui(player_index, unit_number)
end)

local function repositionResizeGui(player_index)
	storage.viewing = storage.viewing or {}
	if not storage.viewing[player_index] then return end
	local player = game.get_player(player_index)
	if player then ResizeGui.reposition(player) end
end

-- Keep the resize panel aligned when the display / UI scale changes.
script.on_event(defines.events.on_player_display_resolution_changed, function(event)
	repositionResizeGui(event.player_index)
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
	repositionResizeGui(event.player_index)
end)

-- Tear down when the player remote-views a different surface.
script.on_event(defines.events.on_player_changed_surface, function(event)
	local player_index = event.player_index
	storage.viewing = storage.viewing or {}
	local unit_number = storage.viewing[player_index]
	if not unit_number then return end

	local player = game.get_player(player_index)
	local state = storage.mythoi[unit_number]
	if not (player and state and state.inside_surface) then return end

	if player.controller_type == defines.controllers.remote
			and player.surface ~= state.inside_surface then
		ResizeGui.close(player)
		storage.viewing[player_index] = nil
	end
end)

-- Resize panel: GUI arrow buttons, typed sizes, and keyboard arrows (one step per press).
script.on_event(defines.events.on_gui_click, function(event)
	ResizeGui.onButtonClick(event)
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
	local element = event.element
	if not (element and element.valid) then return end
	if element.name ~= "mythos-resize-width-field"
			and element.name ~= "mythos-resize-height-field" then return end
	ResizeGui.onTextConfirmed(event)
end)

local function bindResizeArrow(name, direction)
	script.on_event(name, function(event)
		ResizeGui.onArrowInput((event --[[@as EventData.CustomInputEvent]]).player_index, direction)
	end)
end

bindResizeArrow("mythos-resize-up",    "up")
bindResizeArrow("mythos-resize-down",  "down")
bindResizeArrow("mythos-resize-left",  "left")
bindResizeArrow("mythos-resize-right", "right")
