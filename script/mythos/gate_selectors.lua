local Registry = require("script.mythos.registry")
local util     = require("script.util")

local GateSelectors = {}

GateSelectors.PROTOTYPE = "mythos-gate-selector"

local function destroySelector(entity)
	if entity and entity.valid then
		entity.destroy{ raise_destroy = false }
	end
end

function GateSelectors.findStateAndSlot(entity)
	if not (entity and entity.valid and entity.name == GateSelectors.PROTOTYPE) then return nil end
	for _, state in pairs(Registry.all()) do
		if state.inside_surface and state.inside_surface.valid
				and state.inside_surface.index == entity.surface.index then
			for slotKey, selector in pairs(state.gateSelectorEntities or {}) do
				if selector == entity then
					return state, slotKey
				end
			end
			local layout = state.getDimensionGateLayout and state:getDimensionGateLayout()
			for slotKey, gateLayout in pairs(layout or {}) do
				local pos = gateLayout.pos
				if util.nearPosition(entity.position, { x = pos[1], y = pos[2] }, 0.1) then
					return state, slotKey
				end
			end
		end
	end
end

function GateSelectors.install(Mythos)

	function Mythos:destroyGateSelectors()
		if self.gateSelectorEntities then
			for _, selector in pairs(self.gateSelectorEntities) do
				destroySelector(selector)
			end
		end
		self.gateSelectorEntities = nil
	end

	function Mythos:refreshGateSelectors(layout)
		if not (self.inside_surface and self.inside_surface.valid and self.entity and self.entity.valid) then
			return
		end

		self:destroyGateSelectors()
		for _, selector in pairs(self.inside_surface.find_entities_filtered{ name = GateSelectors.PROTOTYPE }) do
			destroySelector(selector)
		end
		self.gateSelectorEntities = {}
		layout = layout or self:getDimensionGateLayout()

		for slotKey, gateLayout in pairs(layout or {}) do
			local pos = gateLayout.pos
			local selector = self.inside_surface.create_entity{
				name        = GateSelectors.PROTOTYPE,
				position    = { x = pos[1], y = pos[2] },
				force       = self.entity.force,
				raise_built = false,
			}
			if selector and selector.valid then
				self.gateSelectorEntities[slotKey] = selector
			end
		end
	end

	function Mythos:findGateSelectorSlot(entity)
		if not (entity and entity.valid) then return nil end
		for slotKey, selector in pairs(self.gateSelectorEntities or {}) do
			if selector == entity then return slotKey end
			if selector and selector.valid and util.nearPosition(entity.position, selector.position, 0.1) then
				return slotKey
			end
		end
	end

end

return GateSelectors
