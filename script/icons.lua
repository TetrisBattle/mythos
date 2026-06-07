local IconGui = require("script.iconGui")

local Icons = {}

function Icons.install(Mythos)

	-- Redraws all active icons with layout-aware positions and scales.
	-- Layout rules:
	--   1 icon  -> large, centred above entity
	--   2 icons -> side by side, medium scale
	--   3 icons -> 2 on top row, 1 centred on bottom row
	--   4 icons -> 2x2 grid
	function Mythos:refreshIconRenders()
		self.icon_renders = self.icon_renders or {}
		self.custom_icons = self.custom_icons or {}

		for i, render in pairs(self.icon_renders) do
			if render and render.valid then render.destroy() end
			self.icon_renders[i] = nil
		end

		local active = {}
		for i = 1, 4 do
			if self.custom_icons[i] then
				active[#active + 1] = { idx = i, signal = self.custom_icons[i] }
			end
		end

		local count = #active
		if count == 0 then return end

		local offsets, scale
		if count == 1 then
			scale = 0.9
			offsets = { { 0, -0.1 } }
		elseif count == 2 then
			scale = 0.55
			offsets = {
				{ -0.45, -0.1 },
				{  0.45, -0.1 },
			}
		elseif count == 3 then
			scale = 0.55
			offsets = {
				{ -0.45, -0.5 },
				{  0.45, -0.5 },
				{  0,     0.3 },
			}
		else
			scale = 0.55
			offsets = {
				{ -0.45, -0.5 },
				{  0.45, -0.5 },
				{ -0.45,  0.3 },
				{  0.45,  0.3 },
			}
		end

		for i, entry in ipairs(active) do
			local sprite = IconGui.spritePath(entry.signal)
			if sprite then
				self.icon_renders[entry.idx] = rendering.draw_sprite {
					sprite       = sprite,
					target       = { entity = self.entity, offset = offsets[i] or { 0, -1.6 } },
					surface      = self.entity.surface,
					x_scale      = scale,
					y_scale      = scale,
					render_layer = "entity-info-icon-above",
				}
			end
		end
	end

	function Mythos:setIcon(index, signal)
		self.icon_renders = self.icon_renders or {}
		self.custom_icons = self.custom_icons or {}

		self.custom_icons[index] = signal or nil
		self:refreshIconRenders()
	end

end

return Icons
