-- Icon helpers for Mythos Config (world-space icon rendering uses spritePath).

local Registry = require("script.registry")

local IconGui = {}

local BTN_PREFIX = "mythos-icon-button-"

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
