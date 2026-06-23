local IconGui    = require("script.ui.icon_gui")
local GatePositionGui = require("script.ui.gate_position_gui")
local ResizeGui  = require("script.ui.resize_gui")
local RemoteView = require("script.ui.remote_view")

local Gui = {}

function Gui.onGuiOpened(event)
	if event.gui_type == defines.gui_type.entity then
		local entity = event.entity
		if entity and entity.valid and entity.name == "mythos" then
			local player = game.get_player(event.player_index)
			if player then IconGui.open(player, entity) end
		end
	elseif event.gui_type == defines.gui_type.controller then
		RemoteView.onControllerGuiOpened(event)
	end
end

function Gui.onGuiClosed(event)
	if GatePositionGui.onGuiClosed(event) then return end

	if event.gui_type ~= defines.gui_type.entity then return end
	local entity = event.entity
	if not (entity and entity.valid and entity.name == "mythos") then return end

	local player = game.get_player(event.player_index)
	if player then IconGui.close(player) end
end

function Gui.onGuiElemChanged(event)
	IconGui.onElemChanged(event)
end

function Gui.onGuiClick(event)
	if GatePositionGui.onButtonClick(event) then return end
	ResizeGui.onButtonClick(event)
end

function Gui.onGuiConfirmed(event)
	local element = event.element
	if not (element and element.valid) then return end
	if element.name == "mythos-resize-width-field"
			or element.name == "mythos-resize-height-field" then
		ResizeGui.onTextConfirmed(event)
	end
end

function Gui.onPlayerDisplayChanged(event)
	RemoteView.repositionResizeGui(event.player_index)
end

function Gui.onResizeArrowInput(direction)
	return RemoteView.onResizeArrowInput(direction)
end

return Gui
