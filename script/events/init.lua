local registerEvents  = require("script.registerEvents")
local Mythos          = require("script.mythos.init")
local Maintenance     = require("script.migrations.init")
local RemoteView      = require("script.ui.remote_view")
local SettingsSync    = require("script.settingsSync")
local Chunks          = require("script.events.chunks")
local Gui             = require("script.events.gui")
local GatePositionGui = require("script.ui.gate_position_gui")
local Ticks           = require("script.events.ticks")

local RuntimeEvents = {}

RuntimeEvents.onConfigurationChanged = Maintenance.onConfigurationChanged

local function bindResizeArrow(name, direction)
	script.on_event(name, Gui.onResizeArrowInput(direction))
end

function RuntimeEvents.register()
	script.on_event(defines.events.on_chunk_generated, Chunks.onChunkGenerated)

	registerEvents(Mythos.onEntityBuilt, Mythos.onEntityRemoved)

	script.on_event(defines.events.on_entity_cloned, Mythos.onEntityCloned)

	script.on_event(defines.events.on_entity_settings_pasted, Mythos.onEntitySettingsPasted)

	script.on_event(defines.events.on_player_setup_blueprint, Mythos.onPlayerSetupBlueprint)

	script.on_event(defines.events.on_pre_player_mined_item, Mythos.onPrePlayerMinedItem)

	script.on_nth_tick(6,   Ticks.onFastTick)
	script.on_nth_tick(60,  Ticks.onSlowTick)
	script.on_nth_tick(300, Ticks.onSolarSync)

	script.on_event(defines.events.on_marked_for_deconstruction,  Mythos.onMarkedForDeconstruction)
	script.on_event(defines.events.on_cancelled_deconstruction,   Mythos.onCancelledDeconstruction)
	script.on_event(defines.events.on_player_cursor_stack_changed, Mythos.onCursorChanged)

	script.on_event(defines.events.on_selected_entity_changed, GatePositionGui.onSelectedEntityChanged)

	script.on_event(defines.events.on_gui_opened, Gui.onGuiOpened)

	script.on_event(defines.events.on_gui_closed, Gui.onGuiClosed)

	script.on_event(defines.events.on_gui_elem_changed, Gui.onGuiElemChanged)

	script.on_event("mythos-open-dimension", RemoteView.openSelectedDimension)

	script.on_nth_tick(1, Ticks.onTick)

	script.on_event(defines.events.on_player_controller_changed, RemoteView.onPlayerControllerChanged)

	script.on_event(defines.events.on_player_display_resolution_changed, Gui.onPlayerDisplayChanged)

	script.on_event(defines.events.on_player_display_scale_changed, Gui.onPlayerDisplayChanged)

	script.on_event(defines.events.on_player_changed_surface, RemoteView.onPlayerChangedSurface)

	script.on_event(defines.events.on_gui_click, Gui.onGuiClick)

	script.on_event(defines.events.on_gui_confirmed, Gui.onGuiConfirmed)

	bindResizeArrow("mythos-resize-up",    "up")
	bindResizeArrow("mythos-resize-down",  "down")
	bindResizeArrow("mythos-resize-left",  "left")
	bindResizeArrow("mythos-resize-right", "right")

	script.on_event(defines.events.on_runtime_mod_setting_changed, SettingsSync.onRuntimeModSettingChanged)
end

return RuntimeEvents
