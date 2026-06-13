local Registry      = require("script.mythos.registry")
local GateSelectors = require("script.mythos.gate_selectors")

local GatePositionGui = {}

local FRAME_NAME = "mythos-gate-position-panel"
local BTN_PREFIX = "mythos-gate-position-button-"
local CELL_SIZE  = 40
local MYTHOS_IMAGE_SIZE     = 120
local MYTHOS_IMAGE_X_OFFSET = 10
local MYTHOS_IMAGE_Y_OFFSET = 40

local SIDE_SLOTS = {
	top    = { "T1", "T2", "T3", "T4" },
	left   = { "L1", "L2", "L3", "L4" },
	right  = { "R1", "R2", "R3", "R4" },
	bottom = { "B1", "B2", "B3", "B4" },
}

local GATE_SPRITES = {
	T = "mythos-gate-ui-top",
	L = "mythos-gate-ui-left",
	R = "mythos-gate-ui-right",
	B = "mythos-gate-ui-bottom",
}

local function getFrame(player)
	return player.gui.screen[FRAME_NAME]
end

local function buttonName(slotKey)
	return BTN_PREFIX .. slotKey
end

local function isButton(name)
	return name and name:sub(1, #BTN_PREFIX) == BTN_PREFIX
end

local function gateSprite(targetSlotKey)
	return GATE_SPRITES[targetSlotKey:sub(1, 1)] or "mythos-gate-ui-top"
end

local function slotAtPhysicalGate(state, physicalGateKey)
	local positions = state:normalizeDimensionGatePositions()
	for slotKey, candidatePhysicalGateKey in pairs(positions) do
		if candidatePhysicalGateKey == physicalGateKey then return slotKey end
	end
end

local function close(player)
	local frame = getFrame(player)
	if frame and frame.valid then frame.destroy() end
end

local function isGateFrame(element)
	return element and element.valid and element.name == FRAME_NAME
end

local function clearHoverBorder(player_index)
	storage.gate_hover_borders = storage.gate_hover_borders or {}
	local border = storage.gate_hover_borders[player_index]
	if border and border.valid then border.destroy() end
	storage.gate_hover_borders[player_index] = nil
end

local function addGateButton(parent, state, physicalGateKey, targetSlotKey)
	local currentSlotKey = slotAtPhysicalGate(state, physicalGateKey)
	local button = parent.add{
		type    = "sprite-button",
		name    = buttonName(targetSlotKey),
		sprite  = gateSprite(targetSlotKey),
		tooltip = { "mythos-gui.gate-position-button-tooltip", targetSlotKey },
		tags    = {
			mythos_unit       = state.entity.unit_number,
			physical_gate_key = physicalGateKey,
			target_slot       = targetSlotKey,
		},
		style = targetSlotKey == currentSlotKey
			and "mythos_gate_position_source_button"
			or "mythos_gate_position_button",
	}
	button.style.width = CELL_SIZE
	button.style.height = CELL_SIZE
	return button
end

local function addTopGate(parent, state, physicalGateKey, targetSlotKey)
	local column = parent.add{ type = "flow", direction = "vertical" }
	column.style.horizontal_align = "center"
	column.style.vertical_spacing = 2
	column.add{ type = "label", caption = targetSlotKey, style = "mythos_gate_position_label" }
	addGateButton(column, state, physicalGateKey, targetSlotKey)
end

local function addBottomGate(parent, state, physicalGateKey, targetSlotKey)
	local column = parent.add{ type = "flow", direction = "vertical" }
	column.style.horizontal_align = "center"
	column.style.vertical_spacing = 2
	addGateButton(column, state, physicalGateKey, targetSlotKey)
	column.add{ type = "label", caption = targetSlotKey, style = "mythos_gate_position_label" }
end

local function addLeftGate(parent, state, physicalGateKey, targetSlotKey)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 4
	local label = row.add{ type = "label", caption = targetSlotKey, style = "mythos_gate_position_label" }
	label.style.width = 24
	addGateButton(row, state, physicalGateKey, targetSlotKey)
end

local function addRightGate(parent, state, physicalGateKey, targetSlotKey)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 4
	addGateButton(row, state, physicalGateKey, targetSlotKey)
	row.add{ type = "label", caption = targetSlotKey, style = "mythos_gate_position_label" }
end

local function addHorizontalSide(parent, slots, state, physicalGateKey, gateBuilder)
	local flow = parent.add{ type = "flow", direction = "horizontal" }
	flow.style.horizontal_align = "center"
	flow.style.horizontal_spacing = 8
	for _, slotKey in ipairs(slots) do
		gateBuilder(flow, state, physicalGateKey, slotKey)
	end
end

local function addVerticalSide(parent, slots, state, physicalGateKey, gateBuilder)
	local flow = parent.add{ type = "flow", direction = "vertical" }
	flow.style.vertical_align = "center"
	flow.style.vertical_spacing = 6
	for _, slotKey in ipairs(slots) do
		gateBuilder(flow, state, physicalGateKey, slotKey)
	end
end

function GatePositionGui.close(player)
	close(player)
	if player then clearHoverBorder(player.index) end
end

function GatePositionGui.open(player, state, physicalGateKey)
	if not (player and state and state.entity and state.entity.valid and physicalGateKey) then return end
	close(player)

	local frame = player.gui.screen.add{
		type      = "frame",
		name      = FRAME_NAME,
		caption   = { "mythos-gui.gate-position-title" },
		direction = "vertical",
		style     = "mythos_gate_position_frame",
	}
	frame.auto_center = true
	player.opened = frame

	local grid = frame.add{ type = "table", column_count = 3 }
	grid.style.horizontal_spacing = 12
	grid.style.vertical_spacing = 8

	grid.add{ type = "empty-widget" }
	addHorizontalSide(grid, SIDE_SLOTS.top, state, physicalGateKey, addTopGate)
	grid.add{ type = "empty-widget" }

	addVerticalSide(grid, SIDE_SLOTS.left, state, physicalGateKey, addLeftGate)
	local center = grid.add{ type = "sprite", sprite = "mythos-gui-image" }
	center.style.width = MYTHOS_IMAGE_SIZE
	center.style.height = MYTHOS_IMAGE_SIZE
	center.style.left_margin = -MYTHOS_IMAGE_X_OFFSET
	center.style.top_margin = -MYTHOS_IMAGE_Y_OFFSET
	center.style.right_margin = MYTHOS_IMAGE_X_OFFSET
	center.style.bottom_margin = MYTHOS_IMAGE_Y_OFFSET
	addVerticalSide(grid, SIDE_SLOTS.right, state, physicalGateKey, addRightGate)

	grid.add{ type = "empty-widget" }
	addHorizontalSide(grid, SIDE_SLOTS.bottom, state, physicalGateKey, addBottomGate)
	grid.add{ type = "empty-widget" }
end

function GatePositionGui.tryOpenFromInput(event)
	if event.cursor_over_gui then return false end
	if event.cursor_gui_element and event.cursor_gui_element.valid then return false end

	local player = game.get_player(event.player_index)
	if not player then return false end
	local selected = player.selected
	local state, physicalGateKey = GateSelectors.findStateAndGatePosition(selected)
	if not (state and physicalGateKey) then return false end

	storage.viewing = storage.viewing or {}
	if storage.viewing[event.player_index] ~= state.entity.unit_number then return false end
	if player.controller_type ~= defines.controllers.remote then return false end
	if player.surface ~= state.inside_surface then return false end

	GatePositionGui.open(player, state, physicalGateKey)
	return true
end

function GatePositionGui.onButtonClick(event)
	local element = event.element
	if not (element and element.valid and isButton(element.name)) then return false end

	local tags = element.tags
	if not (tags and tags.mythos_unit and tags.target_slot) then return true end
	local state = Registry.get(tags.mythos_unit)
	local player = game.get_player(event.player_index)
	if not (state and player) then return true end

	local ok, errKey
	if tags.physical_gate_key and state.assignDimensionGateSlot then
		ok, errKey = state:assignDimensionGateSlot(tags.physical_gate_key, tags.target_slot)
	else
		ok, errKey = state:swapDimensionGateSlots(tags.source_slot, tags.target_slot)
	end
	if not ok then
		player.print({ errKey or "mythos-gui.gate-position-failed" })
		return true
	end
	close(player)
	return true
end

function GatePositionGui.onGuiClosed(event)
	if not isGateFrame(event.element) then return false end
	local player = game.get_player(event.player_index)
	if player then GatePositionGui.close(player) end
	return true
end

function GatePositionGui.clearHover(player_index)
	clearHoverBorder(player_index)
end

function GatePositionGui.onSelectedEntityChanged(event)
	clearHoverBorder(event.player_index)
end

return GatePositionGui
