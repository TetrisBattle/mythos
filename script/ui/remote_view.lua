local Registry  = require("script.mythos.registry")
local ResizeGui = require("script.ui.resize_gui")

local RemoteView = {}

local function scheduleResizeGui(player_index, unit_number)
	storage.pending_resize_gui = storage.pending_resize_gui or {}
	storage.pending_resize_gui[player_index] = unit_number
end

local function clearRemoteView(player_index, player)
	if player then
		ResizeGui.close(player)
	end
	storage.viewing = storage.viewing or {}
	storage.viewing[player_index] = nil
end

local function tryOpenResizeGui(player_index, unit_number)
	local player = game.get_player(player_index)
	local state = Registry.get(unit_number)
	if not (player and state and state.entity.valid) then return end
	if player.controller_type ~= defines.controllers.remote then return end
	if player.surface ~= state.inside_surface then return end
	state:refreshGateRenders()
	ResizeGui.open(player, state)
end

local function cursorOnSelectionBox(entity, position)
	if not (entity and entity.valid and position) then return false end
	local box = entity.selection_box
	if not box then return false end
	local x, y = position.x, position.y
	return x >= box.left_top.x and x <= box.right_bottom.x
		and y >= box.left_top.y and y <= box.right_bottom.y
end

local function shouldIgnoreOpenInput(player, event)
	if not player then return true end
	if event and event.cursor_over_gui then return true end
	if event and event.cursor_gui_element and event.cursor_gui_element.valid then return true end

	-- Quickbar / inventory clicks expose items; ignore only those, not tiles under mythos edges.
	if event and event.selected_prototype and event.selected_prototype.base_type == "item" then
		return true
	end

	local stack = player.cursor_stack
	if stack and stack.valid_for_read then return true end

	local ghost = player.cursor_ghost
	if ghost and ghost.valid then return true end

	return false
end

local function findMythosAtCursor(player, position)
	if not (player and position and player.surface) then return nil end

	-- Only consider mythoi whose selection box actually contains the click.
	local candidates = player.surface.find_entities_filtered{
		name = "mythos",
		area = {
			{ position.x - 2, position.y - 2 },
			{ position.x + 2, position.y + 2 },
		},
	}

	local best, best_dist
	for _, entity in ipairs(candidates) do
		if entity.valid and cursorOnSelectionBox(entity, position) then
			local dx = entity.position.x - position.x
			local dy = entity.position.y - position.y
			local dist = dx * dx + dy * dy
			if not best_dist or dist < best_dist then
				best = entity
				best_dist = dist
			end
		end
	end
	return best
end

function RemoteView.resolveMythosEntity(player, cursor_position, event)
	if not player then return nil end
	if shouldIgnoreOpenInput(player, event) then return nil end
	if not cursor_position then return nil end

	local selected = player.selected
	if selected and selected.valid and selected.name == "mythos"
			and cursorOnSelectionBox(selected, cursor_position) then
		return selected
	end

	return findMythosAtCursor(player, cursor_position)
end

function RemoteView.openForEntity(player_index, entity)
	local player = game.get_player(player_index)
	if not player then return end

	local controller = player.controller_type
	if controller ~= defines.controllers.character and controller ~= defines.controllers.remote then return end
	if not (entity and entity.valid and entity.name == "mythos") then return end

	local state = Registry.get(entity.unit_number)
	if not (state and state.inside_surface and state.inside_surface.valid) then return end

	state:syncElectricity()

	storage.viewing = storage.viewing or {}
	storage.viewing[player_index] = entity.unit_number

	player.set_controller{
		type     = defines.controllers.remote,
		position = { x = state.inside_x, y = state.inside_y },
		surface  = state.inside_surface,
	}

	scheduleResizeGui(player_index, entity.unit_number)
end

function RemoteView.onControllerGuiOpened(event)
	if event.gui_type ~= defines.gui_type.controller then return end
	storage.viewing = storage.viewing or {}
	local unit_number = storage.viewing[event.player_index]
	if not unit_number then return end
	local player = game.get_player(event.player_index)
	if not player or player.controller_type ~= defines.controllers.remote then return end
	scheduleResizeGui(event.player_index, unit_number)
end

function RemoteView.openSelectedDimension(event)
	local e = event --[[@as EventData.CustomInputEvent]]
	local player = game.get_player(e.player_index)
	if not player then return end

	local entity = RemoteView.resolveMythosEntity(player, e.cursor_position, e)
	if entity then
		RemoteView.openForEntity(e.player_index, entity)
	end
end

function RemoteView.openPendingResizeGuis()
	if not storage.pending_resize_gui then return end
	for player_index, unit_number in pairs(storage.pending_resize_gui) do
		tryOpenResizeGui(player_index, unit_number)
		storage.pending_resize_gui[player_index] = nil
	end
end

function RemoteView.onPlayerControllerChanged(event)
	local player_index = event.player_index
	storage.viewing = storage.viewing or {}
	local unit_number = storage.viewing[player_index]
	if not unit_number then return end

	local player = game.get_player(player_index)
	if not player then return end

	if player.controller_type ~= defines.controllers.remote then
		clearRemoteView(player_index, player)
		return
	end

	local state = Registry.get(unit_number)
	if not (state and state.inside_surface and state.inside_surface.valid) then
		clearRemoteView(player_index, player)
		return
	end

	if player.surface ~= state.inside_surface then
		clearRemoteView(player_index, player)
		return
	end

	scheduleResizeGui(player_index, unit_number)
end

function RemoteView.repositionResizeGui(player_index)
	storage.viewing = storage.viewing or {}
	if not storage.viewing[player_index] then return end
	local player = game.get_player(player_index)
	if player then ResizeGui.reposition(player) end
end

function RemoteView.onPlayerChangedSurface(event)
	local player_index = event.player_index
	storage.viewing = storage.viewing or {}
	local unit_number = storage.viewing[player_index]
	if not unit_number then return end

	local player = game.get_player(player_index)
	local state = Registry.get(unit_number)
	if not (player and state and state.inside_surface) then return end

	if player.controller_type == defines.controllers.remote
			and player.surface ~= state.inside_surface then
		clearRemoteView(player_index, player)
	end
end

function RemoteView.onResizeArrowInput(direction)
	return function(event)
		ResizeGui.onArrowInput((event --[[@as EventData.CustomInputEvent]]).player_index, direction)
	end
end

return RemoteView
