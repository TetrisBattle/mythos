-- Handles the icon-picker panel that opens alongside the mythos logistics GUI.
-- When a player opens a mythos entity (left-click), this module creates a small
-- relative-GUI frame anchored to the right of the container GUI.  The player
-- can pick up to 4 signals as custom icons, rendered in world-space above the
-- entity.  The icons are NOT derived automatically from chest contents.

local Registry = require("script.registry")

local IconGui = {}

local FRAME_NAME  = "mythos-icon-panel"
local BTN_PREFIX  = "mythos-icon-button-" -- followed by 1-4

-- Signal-type → sprite-path prefix mapping.
local TYPE_PREFIX = {
	item                 = "item",
	virtual              = "virtual-signal",
	fluid                = "fluid",
	entity               = "entity",
	recipe               = "recipe",
	quality              = "quality",
	["space-location"]   = "space-location",
	["asteroid-chunk"]   = "asteroid-chunk",
}

-- Factorio 2.0 reads item SignalIDs with type = nil; treat that as "item".
function IconGui.signalType(signal)
	if not signal then return nil end
	return signal.type or "item"
end

-- Builds the sprite path for a SignalID, or returns nil if unsupported.
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

-- Opens (or refreshes) the icon panel for a mythos entity.
-- Called from on_gui_opened; recreates the frame so current icons are shown.
function IconGui.open(player, entity)
	-- Destroy any stale panel first.
	local existing = player.gui.relative[FRAME_NAME]
	if existing and existing.valid then existing.destroy() end

	local state = Registry.get(entity.unit_number)
	if not state then return end

	local frame = player.gui.relative.add {
		type      = "frame",
		name      = FRAME_NAME,
		caption   = { "mythos-gui.icon-title" },
		direction = "vertical",
		anchor    = {
			gui      = defines.relative_gui_type.container_gui,
			position = defines.relative_gui_position.right,
			name     = "mythos",
		},
	}

	local inner = frame.add {
		type  = "frame",
		style = "inside_shallow_frame_with_padding",
	}

	-- Two rows of two buttons.
	local icons = state.custom_icons or {}
	for row = 0, 1 do
		local r = inner.add { type = "flow", direction = "horizontal" }
		r.style.horizontal_spacing = 4
		for col = 0, 1 do
			local idx = row * 2 + col + 1
			local btn = r.add {
				type      = "choose-elem-button",
				name      = BTN_PREFIX .. idx,
				elem_type = "signal",
				tags      = { mythos_unit = entity.unit_number, slot = idx },
			}
			if icons[idx] then
				btn.elem_value = icons[idx]
			end
		end
	end
end

-- Closes and destroys the panel for a player (called from on_gui_closed).
function IconGui.close(player)
	local frame = player.gui.relative[FRAME_NAME]
	if frame and frame.valid then frame.destroy() end
end

-- Handles on_gui_elem_changed: updates one of the 4 icon slots when the player
-- picks or clears a signal in any of the choose-elem-buttons.
function IconGui.onElemChanged(event)
	local element = event.element
	if not (element and element.valid) then return end

	local tags = element.tags
	if not (tags and tags.mythos_unit and tags.slot) then return end

	local state = Registry.get(tags.mythos_unit)
	if not (state and state.entity and state.entity.valid) then return end

	state:setIcon(tags.slot, element.elem_value) -- elem_value is nil when cleared
end

return IconGui
