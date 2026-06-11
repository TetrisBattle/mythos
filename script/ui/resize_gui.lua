-- Mythos Config GUI (resize + custom icons)
-- Shown while remote-viewing a pocket dimension. Anchored bottom-right.

local PocketDimension = require("script.pocket_dimension.init")
local Registry        = require("script.mythos.registry")
local util            = require("script.util")
local IconGui         = require("script.ui.icon_gui")

local ResizeGui = {}

local FRAME_NAME   = "mythos-config-panel"
local BTN_PREFIX   = "mythos-resize-"
local DEFAULT_WIDTH_FIELD  = "mythos-default-width-field"
local DEFAULT_HEIGHT_FIELD = "mythos-default-height-field"
local WIDTH_FIELD          = "mythos-resize-width-field"
local HEIGHT_FIELD         = "mythos-resize-height-field"

local buttonAction = {
	[BTN_PREFIX .. "top"]    = { edge = "bottom", expand = false },
	[BTN_PREFIX .. "bottom"] = { edge = "bottom", expand = true  },
	[BTN_PREFIX .. "right"]  = { edge = "right",  expand = true  },
	[BTN_PREFIX .. "left"]   = { edge = "right",  expand = false },
}

local arrowAction = {
	up    = { edge = "bottom", expand = false },
	down  = { edge = "bottom", expand = true  },
	right = { edge = "right", expand = true  },
	left  = { edge = "right", expand = false },
}

local SCREEN_MARGIN_RIGHT  = 32
local SCREEN_MARGIN_BOTTOM = 32
local FRAME_CHROME_W       = 12
local FRAME_CHROME_H       = 38

local LABEL_WIDTH   = 52
local FIELD_WIDTH   = 80
local CELL_SIZE     = 28
local ROW_SPACING   = 6

local function scaled(player, value)
	return math.floor(value * player.display_scale + 0.5)
end

local function defaultBounds()
	return PocketDimension.DEFAULT_FLOOR_BOUNDS
end

local function widthOf(state)
	local b = state.floor_bounds or defaultBounds()
	return util.floorWidth(b)
end

local function heightOf(state)
	local b = state.floor_bounds or defaultBounds()
	return util.floorHeight(b)
end

local function defaultWidthOf(state)
	return state.default_width or PocketDimension.DEFAULT_WIDTH
end

local function defaultHeightOf(state)
	return state.default_height or PocketDimension.DEFAULT_HEIGHT
end

local function getFrame(player)
	return player.gui.screen[FRAME_NAME]
end

local function findByName(element, name)
	if element.name == name then return element end
	for _, child in ipairs(element.children) do
		local found = findByName(child, name)
		if found then return found end
	end
end

local function panelDimensions(player)
	local rowWidth = LABEL_WIDTH + ROW_SPACING + FIELD_WIDTH + ROW_SPACING + CELL_SIZE * 2
	local defaultRowWidth = LABEL_WIDTH + ROW_SPACING + FIELD_WIDTH + ROW_SPACING + 16
		+ ROW_SPACING + FIELD_WIDTH
	local iconWidth = LABEL_WIDTH + ROW_SPACING + CELL_SIZE * 4 + 4 * 4
	local contentWidth = math.max(rowWidth, defaultRowWidth, iconWidth)
	local rowsHeight = CELL_SIZE + ROW_SPACING + CELL_SIZE + ROW_SPACING + CELL_SIZE + ROW_SPACING + CELL_SIZE
	return scaled(player, contentWidth + FRAME_CHROME_W),
		scaled(player, rowsHeight + FRAME_CHROME_H)
end

function ResizeGui.reposition(player)
	local frame = getFrame(player)
	if not (frame and frame.valid) then return end

	local width, height = panelDimensions(player)
	local res = player.display_resolution
	frame.location = {
		x = res.width - width - scaled(player, SCREEN_MARGIN_RIGHT),
		y = res.height - height - scaled(player, SCREEN_MARGIN_BOTTOM),
	}
end

local function refreshFields(frame, state)
	local defaultWidthField = findByName(frame, DEFAULT_WIDTH_FIELD)
	local defaultHeightField = findByName(frame, DEFAULT_HEIGHT_FIELD)
	if defaultWidthField and defaultWidthField.valid then
		defaultWidthField.text = tostring(defaultWidthOf(state))
	end
	if defaultHeightField and defaultHeightField.valid then
		defaultHeightField.text = tostring(defaultHeightOf(state))
	end

	local widthField = findByName(frame, WIDTH_FIELD)
	local heightField = findByName(frame, HEIGHT_FIELD)
	if widthField and widthField.valid then
		widthField.text = tostring(widthOf(state))
	end
	if heightField and heightField.valid then
		heightField.text = tostring(heightOf(state))
	end
end

local function stateFromTags(tags)
	if not (tags and tags.mythos_unit) then return nil end
	return Registry.get(tags.mythos_unit)
end

local function reportError(player, errKey)
	player.print({ errKey or "mythos-gui.resize-failed" })
end

local function applyEdge(player, state, edge, expand)
	local ok, errKey
	if expand then
		ok, errKey = state:expandEdge(edge)
	else
		ok, errKey = state:contractEdge(edge)
	end
	if ok then
		local frame = getFrame(player)
		if frame and frame.valid then refreshFields(frame, state) end
	else
		reportError(player, errKey)
	end
	return ok
end

local function playerState(player_index)
	local player = game.get_player(player_index)
	if not (player and ResizeGui.isOpen(player)) then return nil end
	local opened = player.opened
	if opened and opened.valid then
		local n = opened.name
		if n == WIDTH_FIELD or n == HEIGHT_FIELD
				or n == DEFAULT_WIDTH_FIELD or n == DEFAULT_HEIGHT_FIELD then
			return nil
		end
		if IconGui.isIconButton(n) then return nil end
	end
	local unit = storage.viewing and storage.viewing[player_index]
	local state = unit and Registry.get(unit)
	if not state then return nil end
	return player, state
end

local function applyDefaultSize(player, state)
	local frame = getFrame(player)
	if not (frame and frame.valid) then return end

	local widthField = findByName(frame, DEFAULT_WIDTH_FIELD)
	local heightField = findByName(frame, DEFAULT_HEIGHT_FIELD)
	if not (widthField and heightField) then return end

	local width  = PocketDimension.snapSizeUpEven(tonumber(widthField.text), PocketDimension.MIN_DIMENSION_WIDTH)
	local height = PocketDimension.snapSizeUpEven(tonumber(heightField.text), PocketDimension.MIN_DIMENSION_HEIGHT)
	if width < PocketDimension.MIN_DIMENSION_WIDTH
			or height < PocketDimension.MIN_DIMENSION_HEIGHT then
		reportError(player, "mythos-gui.resize-invalid-size")
		refreshFields(frame, state)
		return
	end

	state.default_width  = width
	state.default_height = height
	refreshFields(frame, state)
end

local function applyTypedSize(player, state)
	local frame = getFrame(player)
	if not (frame and frame.valid) then return end

	local widthField = findByName(frame, WIDTH_FIELD)
	local heightField = findByName(frame, HEIGHT_FIELD)
	if not (widthField and heightField) then return end

	local ok, errKey = state:resizeTo(tonumber(widthField.text), tonumber(heightField.text))
	if ok then
		refreshFields(frame, state)
	else
		reportError(player, errKey)
		refreshFields(frame, state)
	end
end

local function addArrowButton(parent, name, caption, tooltip, unit, width, height)
	local btn = parent.add{
		type    = "button",
		name    = name,
		caption = caption,
		tooltip = tooltip,
		tags    = { mythos_unit = unit },
		style   = "mythos_resize_button",
	}
	btn.style.width  = width
	btn.style.height = height
	return btn
end

local function addSizeField(parent, name, value, unit)
	return parent.add{
		type                  = "textfield",
		name                  = name,
		text                  = tostring(value),
		tooltip               = { "mythos-gui.resize-field-tooltip" },
		tags                  = { mythos_unit = unit },
		style                 = "mythos_resize_field",
		numeric               = true,
		allow_decimal         = false,
		allow_negative        = false,
		lose_focus_on_confirm = true,
	}
end

local function addDefaultSizeRow(parent, unit, state)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 6

	local label = row.add{ type = "label", caption = { "mythos-gui.default-size" } }
	label.style.width = LABEL_WIDTH

	local widthField = addSizeField(row, DEFAULT_WIDTH_FIELD, defaultWidthOf(state), unit)
	widthField.style.width = FIELD_WIDTH
	widthField.tooltip = { "mythos-gui.default-size-field-tooltip" }

	row.add{ type = "label", caption = "x" }

	local heightField = addSizeField(row, DEFAULT_HEIGHT_FIELD, defaultHeightOf(state), unit)
	heightField.style.width = FIELD_WIDTH
	heightField.tooltip = { "mythos-gui.default-size-field-tooltip" }
end

local function addHeightRow(parent, unit, state)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 6

	local label = row.add{ type = "label", caption = { "mythos-gui.resize-height" } }
	label.style.width = LABEL_WIDTH

	local field = addSizeField(row, HEIGHT_FIELD, heightOf(state), unit)
	field.style.width = FIELD_WIDTH

	local arrows = row.add{ type = "flow", direction = "horizontal" }
	addArrowButton(arrows, BTN_PREFIX .. "top", "▲", { "mythos-gui.contract-top" },
		unit, CELL_SIZE, CELL_SIZE)
	addArrowButton(arrows, BTN_PREFIX .. "bottom", "▼", { "mythos-gui.expand-top" },
		unit, CELL_SIZE, CELL_SIZE)
end

local function addWidthRow(parent, unit, state)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 6

	local label = row.add{ type = "label", caption = { "mythos-gui.resize-width" } }
	label.style.width = LABEL_WIDTH

	local field = addSizeField(row, WIDTH_FIELD, widthOf(state), unit)
	field.style.width = FIELD_WIDTH

	local arrows = row.add{ type = "flow", direction = "horizontal" }
	addArrowButton(arrows, BTN_PREFIX .. "left", "◄", { "mythos-gui.contract-right" },
		unit, CELL_SIZE, CELL_SIZE)
	addArrowButton(arrows, BTN_PREFIX .. "right", "►", { "mythos-gui.expand-right" },
		unit, CELL_SIZE, CELL_SIZE)
end

local function addIconRow(parent, unit, state)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 4

	local label = row.add{ type = "label", caption = { "mythos-gui.icon-title" } }
	label.style.width = LABEL_WIDTH

	local icons = state.custom_icons or {}
	for idx = 1, 4 do
		local btn = row.add{
			type      = "choose-elem-button",
			name      = IconGui.buttonName(idx),
			elem_type = "signal",
			tags      = { mythos_unit = unit, slot = idx },
		}
		btn.style.width  = CELL_SIZE
		btn.style.height = CELL_SIZE
		if icons[idx] then
			btn.elem_value = icons[idx]
		end
	end
end

local function buildPanel(player, state)
	local unit = state.entity.unit_number

	local frame = player.gui.screen.add{
		type      = "frame",
		name      = FRAME_NAME,
		caption   = { "mythos-gui.config-title" },
		direction = "vertical",
		style     = "mythos_resize_frame",
	}
	frame.auto_center = false

	local rows = frame.add{
		type      = "flow",
		direction = "vertical",
	}
	rows.style.vertical_spacing = 6

	addDefaultSizeRow(rows, unit, state)
	addWidthRow(rows, unit, state)
	addHeightRow(rows, unit, state)
	addIconRow(rows, unit, state)

	ResizeGui.reposition(player)
	return frame
end

function ResizeGui.isOpen(player)
	local frame = getFrame(player)
	return frame and frame.valid
end

function ResizeGui.open(player, state)
	ResizeGui.close(player)
	if player.controller_type ~= defines.controllers.remote then return end
	buildPanel(player, state)
end

function ResizeGui.close(player)
	local screenFrame = player.gui.screen[FRAME_NAME]
	if screenFrame and screenFrame.valid then screenFrame.destroy() end
	local relativeFrame = player.gui.relative[FRAME_NAME]
	if relativeFrame and relativeFrame.valid then relativeFrame.destroy() end
end

function ResizeGui.refresh(player, state)
	local frame = getFrame(player)
	if not (frame and frame.valid) then
		ResizeGui.open(player, state)
		return
	end
	refreshFields(frame, state)
end

function ResizeGui.onButtonClick(event)
	local element = event.element
	if not (element and element.valid) then return end

	local action = buttonAction[element.name]
	if not action then return end

	if not stateFromTags(element.tags) then return end

	local player, state = playerState(event.player_index)
	if not player then return end

	applyEdge(player, state, action.edge, action.expand)
end

function ResizeGui.onTextConfirmed(event)
	local element = event.element
	if not (element and element.valid) then return end
	if element.name ~= WIDTH_FIELD and element.name ~= HEIGHT_FIELD
			and element.name ~= DEFAULT_WIDTH_FIELD and element.name ~= DEFAULT_HEIGHT_FIELD then
		return
	end

	local state = stateFromTags(element.tags)
	if not state then return end

	local player = game.get_player(event.player_index)
	if not player then return end

	if element.name == DEFAULT_WIDTH_FIELD or element.name == DEFAULT_HEIGHT_FIELD then
		applyDefaultSize(player, state)
	else
		applyTypedSize(player, state)
	end
end

function ResizeGui.onArrowInput(player_index, direction)
	local action = arrowAction[direction]
	if not action then return end

	local player, state = playerState(player_index)
	if not player then return end

	applyEdge(player, state, action.edge, action.expand)
end

return ResizeGui
