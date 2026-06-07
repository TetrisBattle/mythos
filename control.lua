local registerEvents    = require("script.registerEvents")
local Mythos            = require("script.Mythos")
local IconGui           = require("script.iconGui")
local ResizeGui         = require("script.resizeGui")
local PocketDimension   = require("script.PocketDimension")
local Registry          = require("script.registry")
local util              = require("script.util")
local Maintenance       = require("script.maintenance")
local RemoteView        = require("script.remoteView")

-- Module-local flag: on_load must not touch storage (CRC check).
local pending_gate_refresh = false

script.on_init(function()
	storage.mythoi                 = {}
	storage.saved_dimensions       = {}
	storage.pending_player_restore = {}
	storage.viewing                = {}  -- player_index → unit_number while in remote view
	storage.pending_resize_gui     = {}  -- player_index → unit_number, opened next tick
end)

script.on_load(function()
	-- Metatables are not saved; restore them so stored states can call methods.
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
	-- Rendering objects are not saved; redraw on the next tick (on_load cannot modify the world).
	pending_gate_refresh = true
end)

script.on_configuration_changed(Maintenance.onConfigurationChanged)

-- Pocket-dimension chunks must never keep generated grass tiles.
script.on_event(defines.events.on_chunk_generated, function(event)
	local surface = event.surface
	local unit_num = util.parseDimensionUnitNumber(surface)
	if not unit_num then return end

	local state = Registry.get(unit_num)
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
	Registry.forEach(function(state)
		if state.entity.valid then
			state:syncSolar()
		end
	end)
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
	if event.gui_type == defines.gui_type.entity then
		local entity = event.entity
		if not (entity and entity.valid and entity.name == "mythos") then return end
		local player = game.get_player(event.player_index)
		if player then IconGui.open(player, entity) end
	elseif event.gui_type == defines.gui_type.controller then
		RemoteView.onControllerGuiOpened(event)
	end
end)

script.on_event(defines.events.on_gui_closed, function(event)
	if event.gui_type ~= defines.gui_type.entity then return end
	local entity = event.entity
	if not (entity and entity.valid and entity.name == "mythos") then return end
	local player = game.get_player(event.player_index)
	if player then IconGui.close(player) end
end)

script.on_event(defines.events.on_gui_elem_changed, IconGui.onElemChanged)

script.on_event("mythos-open-dimension", RemoteView.openSelectedDimension)

-- Open deferred resize panels once remote view has finished initialising.
script.on_nth_tick(1, function()
	if pending_gate_refresh then
		pending_gate_refresh = false
		Maintenance.refreshAfterLoad()
	end
	RemoteView.openPendingResizeGuis()
end)

script.on_event(defines.events.on_player_controller_changed, RemoteView.onPlayerControllerChanged)

-- Keep the resize panel aligned when the display / UI scale changes.
script.on_event(defines.events.on_player_display_resolution_changed, function(event)
	RemoteView.repositionResizeGui(event.player_index)
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
	RemoteView.repositionResizeGui(event.player_index)
end)

script.on_event(defines.events.on_player_changed_surface, RemoteView.onPlayerChangedSurface)

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
	script.on_event(name, RemoteView.onResizeArrowInput(direction))
end

bindResizeArrow("mythos-resize-up",    "up")
bindResizeArrow("mythos-resize-down",  "down")
bindResizeArrow("mythos-resize-left",  "left")
bindResizeArrow("mythos-resize-right", "right")
