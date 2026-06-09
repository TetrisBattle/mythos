local registerEvents    = require("script.registerEvents")
local Mythos            = require("script.Mythos")
local IconGui           = require("script.iconGui")
local ResizeGui         = require("script.resizeGui")
local PocketDimension   = require("script.PocketDimension")
local Registry          = require("script.registry")
local util              = require("script.util")
local Maintenance       = require("script.maintenance")
local RemoteView        = require("script.remoteView")
local SettingsSync      = require("script.settingsSync")

local pending_gate_refresh = false

script.on_init(function()
	storage.mythoi                 = {}
	storage.saved_dimensions       = {}
	storage.pending_player_restore = {}
	storage.viewing                = {}
	storage.pending_resize_gui     = {}
	storage.virtualChests          = {}
	storage.mythos_next_snapshot_id = 0
	storage.mythos_pending_paste    = nil
	SettingsSync.apply()
end)

script.on_load(function()
	for _, state in pairs(storage.mythoi) do
		setmetatable(state, Mythos)
	end
	pending_gate_refresh = true
end)

script.on_configuration_changed(Maintenance.onConfigurationChanged)

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

registerEvents(Mythos.onEntityBuilt, Mythos.onEntityRemoved)

script.on_event(defines.events.on_entity_cloned, Mythos.onEntityCloned)

script.on_event(defines.events.on_entity_settings_pasted, Mythos.onEntitySettingsPasted)

script.on_event(defines.events.on_player_setup_blueprint, Mythos.onPlayerSetupBlueprint)

script.on_event(defines.events.on_pre_player_mined_item, Mythos.onPrePlayerMinedItem)

script.on_nth_tick(6,   Mythos.onNthTick)
script.on_nth_tick(60,  Mythos.onSlowTick)

script.on_nth_tick(300, function()
	Registry.forEach(function(state)
		if state.entity.valid then
			state:syncSolar()
		end
	end)
end)

script.on_event(defines.events.on_marked_for_deconstruction,  Mythos.onMarkedForDeconstruction)
script.on_event(defines.events.on_cancelled_deconstruction,   Mythos.onCancelledDeconstruction)
script.on_event(defines.events.on_player_cursor_stack_changed, Mythos.onCursorChanged)

script.on_event(defines.events.on_gui_opened, function(event)
	if event.gui_type == defines.gui_type.entity then
		local entity = event.entity
		if entity and entity.valid and entity.name == "mythos" then
			local player = game.get_player(event.player_index)
			if player then IconGui.open(player, entity) end
		end
	elseif event.gui_type == defines.gui_type.controller then
		RemoteView.onControllerGuiOpened(event)
	end
end)

script.on_event(defines.events.on_gui_elem_changed, IconGui.onElemChanged)

script.on_event("mythos-open-dimension", RemoteView.openSelectedDimension)

script.on_nth_tick(1, function()
	if pending_gate_refresh then
		pending_gate_refresh = false
		Maintenance.refreshAfterLoad()
		SettingsSync.apply()
	end
	Mythos.processDeferredClones()
	RemoteView.openPendingResizeGuis()
end)

script.on_event(defines.events.on_player_controller_changed, RemoteView.onPlayerControllerChanged)

script.on_event(defines.events.on_player_display_resolution_changed, function(event)
	RemoteView.repositionResizeGui(event.player_index)
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
	RemoteView.repositionResizeGui(event.player_index)
end)

script.on_event(defines.events.on_player_changed_surface, RemoteView.onPlayerChangedSurface)

script.on_event(defines.events.on_gui_click, ResizeGui.onButtonClick)

script.on_event(defines.events.on_gui_confirmed, function(event)
	local element = event.element
	if not (element and element.valid) then return end
	if element.name == "mythos-resize-width-field"
			or element.name == "mythos-resize-height-field"
			or element.name == "mythos-default-width-field"
			or element.name == "mythos-default-height-field" then
		ResizeGui.onTextConfirmed(event)
	end
end)

local function bindResizeArrow(name, direction)
	script.on_event(name, RemoteView.onResizeArrowInput(direction))
end

bindResizeArrow("mythos-resize-up",    "up")
bindResizeArrow("mythos-resize-down",  "down")
bindResizeArrow("mythos-resize-left",  "left")
bindResizeArrow("mythos-resize-right", "right")

script.on_event(defines.events.on_runtime_mod_setting_changed, SettingsSync.onRuntimeModSettingChanged)
