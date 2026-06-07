-- ── Pocket-Dimension Resize GUI ────────────────────────────────────────────────
-- Shown while remote-viewing a pocket dimension.  Auto-sized, anchored to the
-- bottom-right corner of the screen.

local PocketDimension = require("script.PocketDimension")
local ResizeGui       = {}
local FRAME_NAME   = "mythos-resize-panel"
local BTN_PREFIX   = "mythos-resize-"
local WIDTH_FIELD  = "mythos-resize-width-field"
local HEIGHT_FIELD = "mythos-resize-height-field"

local buttonAction = {
	[BTN_PREFIX .. "top"]    = { edge = "top",   expand = true  },
	[BTN_PREFIX .. "bottom"] = { edge = "top",   expand = false },
	[BTN_PREFIX .. "right"]  = { edge = "right", expand = true  },
	[BTN_PREFIX .. "left"]   = { edge = "right", expand = false },
}

local arrowAction = {
	up    = { edge = "top",   expand = true  },
	down  = { edge = "top",   expand = false },
	right = { edge = "right", expand = true  },
	left  = { edge = "right", expand = false },
}

local SCREEN_MARGIN_RIGHT  = 32  -- inset from the right edge (vanilla UI border)
local SCREEN_MARGIN_BOTTOM = 32  -- inset from the bottom edge
local FRAME_CHROME_W = 12  -- horizontal frame padding (estimate)
local FRAME_CHROME_H = 38  -- caption bar + vertical padding (estimate)

local function scaled(player, value)
	return math.floor(value * player.display_scale + 0.5)
end

local LABEL_WIDTH      = 52
local FIELD_WIDTH      = 80
local CELL_SIZE        = 28
local ROW_SPACING      = 6

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function defaultBounds()
	return PocketDimension.DEFAULT_FLOOR_BOUNDS
end

local function widthOf(state)
	local b = state.floor_bounds or defaultBounds()
	return b.x_max - b.x_min + 1
end

local function heightOf(state)
	local b = state.floor_bounds or defaultBounds()
	return b.y_max - b.y_min + 1
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

-- Factorio does not expose rendered GUI dimensions; derive from layout constants.
local function panelDimensions(player)
	local rowWidth  = LABEL_WIDTH + ROW_SPACING + FIELD_WIDTH + ROW_SPACING + CELL_SIZE * 2
	local rowsHeight = CELL_SIZE + ROW_SPACING + CELL_SIZE
	return scaled(player, rowWidth + FRAME_CHROME_W),
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
	return storage.mythoi[tags.mythos_unit]
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
		if n == WIDTH_FIELD or n == HEIGHT_FIELD then return nil end
	end
	local unit = storage.viewing and storage.viewing[player_index]
	local state = unit and storage.mythoi[unit]
	if not state then return nil end
	return player, state
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

-- ── Panel build ───────────────────────────────────────────────────────────────

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

-- Row: label | input | ▲ ▼
local function addHeightRow(parent, unit, state)
	local row = parent.add{ type = "flow", direction = "horizontal" }
	row.style.vertical_align = "center"
	row.style.horizontal_spacing = 6

	local label = row.add{ type = "label", caption = { "mythos-gui.resize-height" } }
	label.style.width = LABEL_WIDTH

	local field = addSizeField(row, HEIGHT_FIELD, heightOf(state), unit)
	field.style.width = FIELD_WIDTH

	local arrows = row.add{ type = "flow", direction = "horizontal" }
	addArrowButton(arrows, BTN_PREFIX .. "top", "▲", { "mythos-gui.expand-top" },
		unit, CELL_SIZE, CELL_SIZE)
	addArrowButton(arrows, BTN_PREFIX .. "bottom", "▼", { "mythos-gui.contract-top" },
		unit, CELL_SIZE, CELL_SIZE)
end

-- Row: label | input | ◄►
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

local function buildPanel(player, state)
	local unit = state.entity.unit_number

	local frame = player.gui.screen.add{
		type      = "frame",
		name      = FRAME_NAME,
		caption   = { "mythos-gui.resize-title" },
		direction = "vertical",
		style     = "mythos_resize_frame",
	}
	frame.auto_center = false
	local rows = frame.add{
		type      = "flow",
		direction = "vertical",
	}
	rows.style.vertical_spacing = 6

	addWidthRow(rows, unit, state)
	addHeightRow(rows, unit, state)

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

-- ── Input routing ─────────────────────────────────────────────────────────────

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
	if element.name ~= WIDTH_FIELD and element.name ~= HEIGHT_FIELD then return end

	local state = stateFromTags(element.tags)
	if not state then return end

	local player = game.get_player(event.player_index)
	if not player then return end

	applyTypedSize(player, state)
end

function ResizeGui.onArrowInput(player_index, direction)
	local action = arrowAction[direction]
	if not action then return end

	local player, state = playerState(player_index)
	if not player then return end

	applyEdge(player, state, action.edge, action.expand)
end

return ResizeGui
