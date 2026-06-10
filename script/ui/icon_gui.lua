-- Icon helpers for Mythos Config (world-space icon rendering uses spritePath).

local Registry = require("script.mythos.registry")

local IconGui = {}

local BTN_PREFIX = "mythos-icon-button-"
local FRAME_NAME = "mythos-icon-panel"
local CELL_SIZE = 28

local TYPE_PREFIX = {
	item               = "item",
	virtual            = "virtual-signal",
	fluid              = "fluid",
	entity             = "entity",
	recipe             = "recipe",
	quality            = "quality",
	["space-location"] = "space-location",
	["asteroid-chunk"] = "asteroid-chunk",
}

local function getFrame(player)
	return player.gui.screen[FRAME_NAME]
end

local function stateFromEntity(entity)
	if not (entity and entity.valid and entity.name == "mythos") then return nil end
	return Registry.get(entity.unit_number)
end

function IconGui.buttonName(slot)
	return BTN_PREFIX .. slot
end

function IconGui.isIconButton(name)
	return name and name:sub(1, #BTN_PREFIX) == BTN_PREFIX
end

function IconGui.signalType(signal)
	if not signal then return nil end
	return signal.type or "item"
end

function IconGui.spritePath(signal)
	if not (signal and signal.name) then return nil end
	local prefix = TYPE_PREFIX[IconGui.signalType(signal)]
	if not prefix then return nil end
	local path = prefix .. "/" .. signal.name
	if helpers.is_valid_sprite_path(path) then return path end
	path = prefix .. "." .. signal.name
	if helpers.is_valid_sprite_path(path) then return path end
	return nil
end

function IconGui.close(player)
	local frame = getFrame(player)
	if frame and frame.valid then frame.destroy() end
end

function IconGui.open(player, entity)
	if not player then return end

	IconGui.close(player)

	local state = stateFromEntity(entity)
	if not (state and state.entity and state.entity.valid) then return end

	local frame = player.gui.screen.add{
		type      = "frame",
		name      = FRAME_NAME,
		caption   = { "mythos-gui.icon-title" },
		direction = "vertical",
	}
	frame.auto_center = true

	local row = frame.add{ type = "flow", direction = "horizontal" }
	row.style.horizontal_spacing = 4

	local icons = state.custom_icons or {}
	for idx = 1, 4 do
		local btn = row.add{
			type      = "choose-elem-button",
			name      = IconGui.buttonName(idx),
			elem_type = "signal",
			tags      = { mythos_unit = entity.unit_number, slot = idx },
		}
		btn.style.width = CELL_SIZE
		btn.style.height = CELL_SIZE
		if icons[idx] then
			btn.elem_value = icons[idx]
		end
	end
end

function IconGui.onElemChanged(event)
	local element = event.element
	if not (element and element.valid) then return end
	if not IconGui.isIconButton(element.name) then return end

	local tags = element.tags
	if not (tags and tags.mythos_unit and tags.slot) then return end

	local state = Registry.get(tags.mythos_unit)
	if not (state and state.entity and state.entity.valid) then return end

	state:setIcon(tags.slot, element.elem_value)
end

return IconGui
